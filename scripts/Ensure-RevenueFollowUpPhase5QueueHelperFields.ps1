param(
    [string]$EnvironmentUrl = 'https://orga632edd5.crm3.dynamics.com',
    [string]$SolutionUniqueName = 'qfu_revenuefollowupworkbench',
    [string]$OutputPath = 'results\phase5-final-fix-queue-helper-fields.json'
)

$ErrorActionPreference = 'Stop'

$roleValueToText = @{
    985020000 = 'TSR'
    985020001 = 'CSSR'
    985020002 = 'Manager'
    985020003 = 'GM'
    985020004 = 'Admin'
    985020005 = 'Unassigned'
}

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
    'Content-Type'     = 'application/json; charset=utf-8'
    'OData-MaxVersion' = '4.0'
    'OData-Version'    = '4.0'
}
$readHeaders = $headers.Clone()
$readHeaders.Remove('Content-Type')

function Invoke-DvGet {
    param([string]$RelativeUrl)
    Invoke-RestMethod -Method Get -Uri "$EnvironmentUrl/api/data/v9.2/$RelativeUrl" -Headers $readHeaders
}

function Invoke-DvPost {
    param([string]$RelativeUrl, [object]$Body)
    Invoke-RestMethod -Method Post -Uri "$EnvironmentUrl/api/data/v9.2/$RelativeUrl" -Headers $headers -Body ($Body | ConvertTo-Json -Depth 30)
}

function Invoke-DvPatch {
    param([string]$RelativeUrl, [object]$Body)
    Invoke-RestMethod -Method Patch -Uri "$EnvironmentUrl/api/data/v9.2/$RelativeUrl" -Headers $headers -Body ($Body | ConvertTo-Json -Depth 30)
}

function Get-AllRows {
    param([string]$RelativeUrl)
    $rows = @()
    $url = "$EnvironmentUrl/api/data/v9.2/$RelativeUrl"
    do {
        $response = Invoke-RestMethod -Method Get -Uri $url -Headers $readHeaders
        $rows += @($response.value)
        $url = $response.'@odata.nextLink'
    } while ($url)
    return $rows
}

function Get-AttributeMetadata {
    param([string]$LogicalName)
    try {
        Invoke-DvGet "EntityDefinitions(LogicalName='qfu_workitem')/Attributes(LogicalName='$LogicalName')?`$select=LogicalName,SchemaName,MetadataId,AttributeType"
    }
    catch {
        if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) {
            return $null
        }
        throw
    }
}

function New-StringAttribute {
    param(
        [string]$SchemaName,
        [string]$DisplayName,
        [int]$MaxLength
    )

    $body = @{
        '@odata.type' = 'Microsoft.Dynamics.CRM.StringAttributeMetadata'
        SchemaName    = $SchemaName
        DisplayName   = @{
            LocalizedLabels = @(
                @{
                    Label        = $DisplayName
                    LanguageCode = 1033
                }
            )
        }
        Description   = @{
            LocalizedLabels = @(
                @{
                    Label        = "Phase 5 queue helper field for stable Workbench filtering/display. True routing remains on lookup and choice fields."
                    LanguageCode = 1033
                }
            )
        }
        RequiredLevel = @{
            Value                              = 'None'
            CanBeChanged                       = $true
            ManagedPropertyLogicalName         = 'canmodifyrequirementlevelsettings'
        }
        MaxLength     = $MaxLength
        FormatName    = @{
            Value = 'Text'
        }
    }

    Invoke-DvPost "EntityDefinitions(LogicalName='qfu_workitem')/Attributes" $body | Out-Null
}

function Add-AttributeToSolution {
    param([guid]$MetadataId)
    try {
        Invoke-DvPost 'AddSolutionComponent' @{
            ComponentType         = 2
            ComponentId           = $MetadataId
            SolutionUniqueName    = $SolutionUniqueName
            AddRequiredComponents = $false
            DoNotIncludeSubcomponents = $true
        } | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Publish-WorkItemEntity {
    Invoke-DvPost 'PublishXml' @{
        ParameterXml = '<importexportxml><entities><entity>qfu_workitem</entity></entities><nodes/><securityroles/><settings/><workflows/></importexportxml>'
    } | Out-Null
}

$requiredAttributes = @(
    @{ LogicalName = 'qfu_currentqueueroletext'; SchemaName = 'qfu_CurrentQueueRoleText'; DisplayName = 'Current Queue Role Text'; MaxLength = 50 },
    @{ LogicalName = 'qfu_currentqueueownerstaffkey'; SchemaName = 'qfu_CurrentQueueOwnerStaffKey'; DisplayName = 'Current Queue Owner Staff Key'; MaxLength = 100 },
    @{ LogicalName = 'qfu_currentqueueownername'; SchemaName = 'qfu_CurrentQueueOwnerName'; DisplayName = 'Current Queue Owner Name'; MaxLength = 200 }
)

$attributeResults = @()
$createdAny = $false
foreach ($attribute in $requiredAttributes) {
    $existing = Get-AttributeMetadata -LogicalName $attribute.LogicalName
    $created = $false
    if (-not $existing) {
        New-StringAttribute -SchemaName $attribute.SchemaName -DisplayName $attribute.DisplayName -MaxLength $attribute.MaxLength
        $createdAny = $true
        Start-Sleep -Seconds 8
        $existing = Get-AttributeMetadata -LogicalName $attribute.LogicalName
        $created = $true
    }

    $addedToSolution = $false
    if ($existing -and $existing.MetadataId) {
        $addedToSolution = Add-AttributeToSolution -MetadataId ([guid]$existing.MetadataId)
    }

    $attributeResults += [pscustomobject]@{
        logicalName     = $attribute.LogicalName
        schemaName      = $attribute.SchemaName
        found           = [bool]$existing
        created         = $created
        metadataId      = if ($existing) { $existing.MetadataId } else { $null }
        addedToSolution = $addedToSolution
    }
}

if ($createdAny) {
    Publish-WorkItemEntity
    Start-Sleep -Seconds 12
}

$staffRows = Get-AllRows "qfu_staffs?`$select=qfu_staffid,qfu_name,qfu_staffnumber&`$filter=statecode eq 0"
$staffById = @{}
foreach ($staff in $staffRows) {
    $staffById[[string]$staff.qfu_staffid] = $staff
}

$workItems = Get-AllRows "qfu_workitems?`$select=qfu_workitemid,qfu_workitemnumber,qfu_currentqueuerole,_qfu_currentqueueownerstaff_value,qfu_currentqueueroletext,qfu_currentqueueownerstaffkey,qfu_currentqueueownername&`$filter=statecode eq 0"
$updated = 0
$unchanged = 0
$unassigned = 0

foreach ($workItem in $workItems) {
    $ownerId = [string]$workItem.'_qfu_currentqueueownerstaff_value'
    $staff = if ($ownerId -and $staffById.ContainsKey($ownerId)) { $staffById[$ownerId] } else { $null }
    $roleText = if ($null -ne $workItem.qfu_currentqueuerole -and $roleValueToText.ContainsKey([int]$workItem.qfu_currentqueuerole)) {
        $roleValueToText[[int]$workItem.qfu_currentqueuerole]
    }
    else {
        'Unassigned'
    }

    if (-not $ownerId -or -not $staff) {
        $roleText = if ($roleText -eq 'Unassigned') { 'Unassigned' } else { $roleText }
    }
    if ($roleText -eq 'Unassigned') {
        $unassigned++
    }

    $staffKey = if ($staff -and -not [string]::IsNullOrWhiteSpace($staff.qfu_staffnumber)) {
        [string]$staff.qfu_staffnumber
    }
    elseif ($staff) {
        [string]$staff.qfu_staffid
    }
    else {
        $null
    }

    $staffName = if ($staff) { [string]$staff.qfu_name } else { $null }

    $needsUpdate = (
        [string]$workItem.qfu_currentqueueroletext -ne $roleText -or
        [string]$workItem.qfu_currentqueueownerstaffkey -ne [string]$staffKey -or
        [string]$workItem.qfu_currentqueueownername -ne [string]$staffName
    )

    if ($needsUpdate) {
        Invoke-DvPatch "qfu_workitems($($workItem.qfu_workitemid))" @{
            qfu_currentqueueroletext       = $roleText
            qfu_currentqueueownerstaffkey  = $staffKey
            qfu_currentqueueownername      = $staffName
        } | Out-Null
        $updated++
    }
    else {
        $unchanged++
    }
}

$roleCounts = Get-AllRows "qfu_workitems?`$select=qfu_workitemid,qfu_currentqueueroletext&`$filter=statecode eq 0" |
    Group-Object qfu_currentqueueroletext |
    ForEach-Object {
        [pscustomobject]@{
            roleText = if ([string]::IsNullOrWhiteSpace($_.Name)) { '(blank)' } else { $_.Name }
            count    = $_.Count
        }
    }

$result = [ordered]@{
    environmentUrl = $EnvironmentUrl
    timestamp = (Get-Date).ToString('o')
    solutionUniqueName = $SolutionUniqueName
    attributes = $attributeResults
    createdAnyAttributes = $createdAny
    activeWorkItemsProcessed = @($workItems).Count
    workItemsUpdated = $updated
    workItemsUnchanged = $unchanged
    unassignedRoleTextCount = $unassigned
    roleTextCounts = @($roleCounts)
}

$directory = Split-Path -Parent $OutputPath
if ($directory) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}
$result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
$result | ConvertTo-Json -Depth 20
