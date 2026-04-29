param(
    [string]$EnvironmentUrl = 'https://orga632edd5.crm3.dynamics.com',
    [string[]]$CanvasRoots = @(
        'tmp\phase5-final-fix-exported-canvas',
        'tmp\phase5-final-fix-canvas-clean'
    ),
    [string]$OutputPath = 'results\phase5-final-ux-nav-canvas-tabledefinition-helper-metadata.json'
)

$ErrorActionPreference = 'Stop'

function Get-AccessToken {
    $tokenObject = Get-AzAccessToken -ResourceUrl "$EnvironmentUrl/"
    $token = $tokenObject.Token
    if ($token -is [System.Security.SecureString]) {
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($token)
        try {
            $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        }
        finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
    return $token
}

$headers = @{
    Authorization      = "Bearer $(Get-AccessToken)"
    Accept             = 'application/json'
    'OData-MaxVersion' = '4.0'
    'OData-Version'    = '4.0'
}

function Invoke-DvGet {
    param([string]$RelativeUrl)
    Invoke-RestMethod -Method Get -Uri "$EnvironmentUrl/api/data/v9.2/$RelativeUrl" -Headers $headers
}

function Get-AttributeMetadata {
    param(
        [string]$LogicalName,
        [string]$TypeSegment
    )

    $relative = "EntityDefinitions(LogicalName='qfu_workitem')/Attributes(LogicalName='$LogicalName')"
    if ($TypeSegment) {
        $relative = "$relative/$TypeSegment"
    }
    Invoke-DvGet $relative
}

function Add-OrReplaceByLogicalName {
    param(
        [object[]]$Items,
        [object]$NewItem
    )

    $logicalName = [string]$NewItem.LogicalName
    $kept = @($Items | Where-Object { [string]$_.LogicalName -ne $logicalName })
    return @($kept + $NewItem)
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Value
    )

    $json = $Value | ConvertTo-Json -Depth 100
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

$attributeSpecs = @(
    @{ LogicalName = 'qfu_currentqueueownername'; TypeSegment = 'Microsoft.Dynamics.CRM.StringAttributeMetadata'; Bucket = 'Attributes' },
    @{ LogicalName = 'qfu_currentqueueownerstaffkey'; TypeSegment = 'Microsoft.Dynamics.CRM.StringAttributeMetadata'; Bucket = 'Attributes' },
    @{ LogicalName = 'qfu_currentqueueroletext'; TypeSegment = 'Microsoft.Dynamics.CRM.StringAttributeMetadata'; Bucket = 'Attributes' },
    @{ LogicalName = 'qfu_currentqueuerole'; TypeSegment = 'Microsoft.Dynamics.CRM.PicklistAttributeMetadata'; Bucket = 'Picklist' }
)

$metadata = @{}
foreach ($spec in $attributeSpecs) {
    $metadata[$spec.LogicalName] = Get-AttributeMetadata -LogicalName $spec.LogicalName -TypeSegment $spec.TypeSegment
}

$results = [System.Collections.Generic.List[object]]::new()

foreach ($root in $CanvasRoots) {
    $tablePath = Join-Path $root 'pkgs\TableDefinitions\Work Items.json'
    if (-not (Test-Path -LiteralPath $tablePath)) {
        $results.Add([pscustomobject]@{
            root = $root
            found = $false
            updated = $false
            message = "Missing Work Items table definition"
        })
        continue
    }

    $tableDefinitionFile = Get-Content -LiteralPath $tablePath -Raw | ConvertFrom-Json
    $entityMetadata = $tableDefinitionFile.TableDefinition.EntityMetadata | ConvertFrom-Json
    $picklistMetadata = $tableDefinitionFile.TableDefinition.PicklistOptionSetAttribute | ConvertFrom-Json

    $beforeAttributes = @($entityMetadata.Attributes).Count
    $beforePicklists = @($picklistMetadata.value).Count

    foreach ($spec in $attributeSpecs) {
        $attribute = $metadata[$spec.LogicalName]
        if ($spec.Bucket -eq 'Attributes') {
            $entityMetadata.Attributes = Add-OrReplaceByLogicalName -Items @($entityMetadata.Attributes) -NewItem $attribute
        }
        elseif ($spec.Bucket -eq 'Picklist') {
            $entityMetadata.Attributes = Add-OrReplaceByLogicalName -Items @($entityMetadata.Attributes) -NewItem $attribute
            $picklistMetadata.value = Add-OrReplaceByLogicalName -Items @($picklistMetadata.value) -NewItem $attribute
        }
    }

    $tableDefinitionFile.TableDefinition.EntityMetadata = ($entityMetadata | ConvertTo-Json -Depth 100 -Compress)
    $tableDefinitionFile.TableDefinition.PicklistOptionSetAttribute = ($picklistMetadata | ConvertTo-Json -Depth 100 -Compress)
    Write-JsonFile -Path $tablePath -Value $tableDefinitionFile

    $afterAttributes = @($entityMetadata.Attributes).Count
    $afterPicklists = @($picklistMetadata.value).Count
    $present = @($attributeSpecs | ForEach-Object {
        $name = $_.LogicalName
        [pscustomobject]@{
            logicalName = $name
            inEntityMetadata = [bool](@($entityMetadata.Attributes | Where-Object { $_.LogicalName -eq $name }).Count)
            inPicklistMetadata = if ($_.Bucket -eq 'Picklist') { [bool](@($picklistMetadata.value | Where-Object { $_.LogicalName -eq $name }).Count) } else { $null }
        }
    })

    $results.Add([pscustomobject]@{
        root = $root
        found = $true
        updated = $true
        attributesBefore = $beforeAttributes
        attributesAfter = $afterAttributes
        picklistsBefore = $beforePicklists
        picklistsAfter = $afterPicklists
        helperFieldPresence = $present
    })
}

$summary = [pscustomobject]@{
    environmentUrl = $EnvironmentUrl
    generatedOn = (Get-Date).ToString('o')
    attributesFetched = @($attributeSpecs | ForEach-Object { $_.LogicalName })
    roots = $results
}

$outputDir = Split-Path -Parent $OutputPath
if ($outputDir) {
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
}
Write-JsonFile -Path $OutputPath -Value $summary
$summary | ConvertTo-Json -Depth 20
