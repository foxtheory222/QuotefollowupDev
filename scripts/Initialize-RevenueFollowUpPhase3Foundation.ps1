param(
    [string]$EnvironmentUrl = "https://orga632edd5.crm3.dynamics.com/",
    [string]$SolutionUniqueName = "qfu_revenuefollowupworkbench",
    [string]$ResultPath = "results/phase3-foundation-20260427.json"
)

$ErrorActionPreference = "Stop"

Import-Module Az.Accounts -ErrorAction Stop

if (-not $EnvironmentUrl.EndsWith("/")) {
    $EnvironmentUrl = "$EnvironmentUrl/"
}

function Convert-AccessTokenToString {
    param([object]$Token)

    if ($Token -is [securestring]) {
        return [System.Net.NetworkCredential]::new("", $Token).Password
    }

    return [string]$Token
}

function Get-DataverseToken {
    $tokenResult = Get-AzAccessToken -ResourceUrl $EnvironmentUrl
    return Convert-AccessTokenToString -Token $tokenResult.Token
}

$script:token = Get-DataverseToken

function Get-Headers {
    param([bool]$WriteOperation = $false)

    $headers = @{
        Authorization      = "Bearer $script:token"
        "OData-MaxVersion" = "4.0"
        "OData-Version"    = "4.0"
        Accept             = "application/json"
        "Content-Type"     = "application/json; charset=utf-8"
    }

    if ($WriteOperation) {
        $headers["MSCRM.SolutionUniqueName"] = $SolutionUniqueName
        $headers["Prefer"] = "return=representation"
    }

    return $headers
}

function Invoke-Dv {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        [object]$Body = $null,
        [bool]$WriteOperation = $false
    )

    $uri = "$($EnvironmentUrl)api/data/v9.2/$Path"
    $headers = Get-Headers -WriteOperation:$WriteOperation

    if ($null -eq $Body) {
        return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -ErrorAction Stop
    }

    $json = $Body | ConvertTo-Json -Depth 100
    return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -Body $json -ErrorAction Stop
}

function Invoke-DvNoContent {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        [object]$Body = $null,
        [bool]$WriteOperation = $false
    )

    $uri = "$($EnvironmentUrl)api/data/v9.2/$Path"
    $headers = Get-Headers -WriteOperation:$WriteOperation
    if ($headers.ContainsKey("Prefer")) {
        $headers.Remove("Prefer")
    }

    if ($null -eq $Body) {
        return Invoke-WebRequest -UseBasicParsing -Method $Method -Uri $uri -Headers $headers -ErrorAction Stop
    }

    $json = $Body | ConvertTo-Json -Depth 100
    return Invoke-WebRequest -UseBasicParsing -Method $Method -Uri $uri -Headers $headers -Body $json -ErrorAction Stop
}

function Invoke-DvOrNull {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        return Invoke-Dv -Method Get -Path $Path
    }
    catch {
        return $null
    }
}

function Escape-ODataValue {
    param([string]$Value)
    return $Value.Replace("'", "''")
}

function Get-First {
    param([object]$Response)

    if ($Response -and $null -ne $Response.value) {
        $values = @($Response.value)
        if ($values.Count -gt 0) {
            return $values[0]
        }
    }

    return $null
}

function Get-EntitySetName {
    param([Parameter(Mandatory = $true)][string]$LogicalName)

    $metadata = Invoke-Dv -Method Get -Path "EntityDefinitions(LogicalName='$LogicalName')?`$select=EntitySetName"
    return $metadata.EntitySetName
}

function Get-AttributeTypeMap {
    param([Parameter(Mandatory = $true)][string]$LogicalName)

    $response = Invoke-Dv -Method Get -Path "EntityDefinitions(LogicalName='$LogicalName')/Attributes?`$select=LogicalName,AttributeType"
    $map = @{}
    foreach ($attribute in $response.value) {
        $map[$attribute.LogicalName] = $attribute.AttributeType
    }
    return $map
}

function Get-OptionValue {
    param(
        [Parameter(Mandatory = $true)][string]$ChoiceName,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $choice = Invoke-Dv -Method Get -Path "GlobalOptionSetDefinitions(Name='$ChoiceName')"
    foreach ($option in $choice.Options) {
        $localized = $option.Label.UserLocalizedLabel.Label
        if ($localized -eq $Label) {
            return [int]$option.Value
        }
    }

    throw "Choice option not found: $ChoiceName / $Label"
}

function New-StringAttributeBody {
    param(
        [Parameter(Mandatory = $true)][string]$SchemaName,
        [Parameter(Mandatory = $true)][string]$DisplayName,
        [int]$MaxLength = 450
    )

    return @{
        "@odata.type"   = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
        SchemaName      = $SchemaName
        DisplayName     = @{
            "@odata.type"     = "Microsoft.Dynamics.CRM.Label"
            LocalizedLabels   = @(
                @{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label         = $DisplayName
                    LanguageCode  = 1033
                }
            )
        }
        RequiredLevel   = @{
            Value = "None"
        }
        MaxLength       = $MaxLength
        FormatName      = @{
            Value = "Text"
        }
    }
}

function Ensure-TextAttribute {
    param(
        [Parameter(Mandatory = $true)][string]$Table,
        [Parameter(Mandatory = $true)][string]$LogicalName,
        [Parameter(Mandatory = $true)][string]$SchemaName,
        [Parameter(Mandatory = $true)][string]$DisplayName
    )

    $existing = Invoke-DvOrNull -Path "EntityDefinitions(LogicalName='$Table')/Attributes(LogicalName='$LogicalName')?`$select=LogicalName,AttributeType"
    if ($existing) {
        return [ordered]@{
            logicalName = $LogicalName
            created     = $false
            found       = $true
            status      = "found"
        }
    }

    $body = New-StringAttributeBody -SchemaName $SchemaName -DisplayName $DisplayName
    Invoke-DvNoContent -Method Post -Path "EntityDefinitions(LogicalName='$Table')/Attributes" -Body $body -WriteOperation:$true | Out-Null

    return [ordered]@{
        logicalName = $LogicalName
        created     = $true
        found       = $true
        status      = "created"
    }
}

function Get-KeyBySchemaName {
    param(
        [Parameter(Mandatory = $true)][string]$Table,
        [Parameter(Mandatory = $true)][string]$KeyName
    )

    $keys = Invoke-DvOrNull -Path "EntityDefinitions(LogicalName='$Table')/Keys?`$select=SchemaName,KeyAttributes,EntityKeyIndexStatus"
    if (-not $keys) {
        return $null
    }

    foreach ($key in $keys.value) {
        if ($key.SchemaName -eq $KeyName) {
            return $key
        }
    }

    return $null
}

function Ensure-AlternateKey {
    param(
        [Parameter(Mandatory = $true)][string]$Table,
        [Parameter(Mandatory = $true)][string]$KeyName,
        [Parameter(Mandatory = $true)][string[]]$Columns,
        [string]$Purpose,
        [string]$ReplacementField = "",
        [string]$ReplacementSchemaName = "",
        [string]$ReplacementDisplayName = ""
    )

    $existing = Get-KeyBySchemaName -Table $Table -KeyName $KeyName
    if ($existing) {
        $existingColumns = @($existing.KeyAttributes)
        if ($existingColumns.Count -eq 0) {
            $existingColumns = $Columns
        }
        return [ordered]@{
            table                 = $Table
            keyName               = $KeyName
            status                = "found"
            columns               = $existingColumns
            replacementField      = $null
            entityKeyIndexStatus  = $existing.EntityKeyIndexStatus
            safeForIdempotency    = $true
            purpose               = $Purpose
            failure               = $null
        }
    }

    $body = @{
        "@odata.type"  = "Microsoft.Dynamics.CRM.EntityKeyMetadata"
        SchemaName     = $KeyName
        DisplayName    = @{
            "@odata.type"   = "Microsoft.Dynamics.CRM.Label"
            LocalizedLabels = @(
                @{
                    "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                    Label         = $KeyName
                    LanguageCode  = 1033
                }
            )
        }
        KeyAttributes = $Columns
    }

    try {
        Invoke-DvNoContent -Method Post -Path "EntityDefinitions(LogicalName='$Table')/Keys" -Body $body -WriteOperation:$true | Out-Null
        $created = Get-KeyBySchemaName -Table $Table -KeyName $KeyName
        return [ordered]@{
            table                 = $Table
            keyName               = $KeyName
            status                = "created"
            columns               = $Columns
            replacementField      = $null
            entityKeyIndexStatus  = if ($created) { $created.EntityKeyIndexStatus } else { "unknown" }
            safeForIdempotency    = $true
            purpose               = $Purpose
            failure               = $null
        }
    }
    catch {
        $failureMessage = $_.Exception.Message
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $failureMessage = $_.ErrorDetails.Message
        }

        if (-not $ReplacementField) {
            return [ordered]@{
                table                 = $Table
                keyName               = $KeyName
                status                = "deferred"
                columns               = $Columns
                replacementField      = $null
                entityKeyIndexStatus  = $null
                safeForIdempotency    = $false
                purpose               = $Purpose
                failure               = $failureMessage
            }
        }

        $fieldResult = Ensure-TextAttribute -Table $Table -LogicalName $ReplacementField -SchemaName $ReplacementSchemaName -DisplayName $ReplacementDisplayName
        $replacementKeyName = $KeyName
        $replacementExisting = Get-KeyBySchemaName -Table $Table -KeyName $replacementKeyName
        if ($replacementExisting) {
            return [ordered]@{
                table                 = $Table
                keyName               = $replacementKeyName
                status                = "found-replacement"
                columns               = @($ReplacementField)
                replacementField      = $fieldResult
                entityKeyIndexStatus  = $replacementExisting.EntityKeyIndexStatus
                safeForIdempotency    = $true
                purpose               = $Purpose
                failure               = "Direct key failed: $failureMessage"
            }
        }

        $replacementBody = @{
            "@odata.type"  = "Microsoft.Dynamics.CRM.EntityKeyMetadata"
            SchemaName     = $replacementKeyName
            DisplayName    = @{
                "@odata.type"   = "Microsoft.Dynamics.CRM.Label"
                LocalizedLabels = @(
                    @{
                        "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"
                        Label         = $replacementKeyName
                        LanguageCode  = 1033
                    }
                )
            }
            KeyAttributes = @($ReplacementField)
        }

        try {
            Invoke-DvNoContent -Method Post -Path "EntityDefinitions(LogicalName='$Table')/Keys" -Body $replacementBody -WriteOperation:$true | Out-Null
            $replacementCreated = Get-KeyBySchemaName -Table $Table -KeyName $replacementKeyName
            return [ordered]@{
                table                 = $Table
                keyName               = $replacementKeyName
                status                = "created-replacement"
                columns               = @($ReplacementField)
                replacementField      = $fieldResult
                entityKeyIndexStatus  = if ($replacementCreated) { $replacementCreated.EntityKeyIndexStatus } else { "unknown" }
                safeForIdempotency    = $true
                purpose               = $Purpose
                failure               = "Direct key failed: $failureMessage"
            }
        }
        catch {
            $replacementFailure = $_.Exception.Message
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                $replacementFailure = $_.ErrorDetails.Message
            }

            return [ordered]@{
                table                 = $Table
                keyName               = $replacementKeyName
                status                = "deferred"
                columns               = @($ReplacementField)
                replacementField      = $fieldResult
                entityKeyIndexStatus  = $null
                safeForIdempotency    = $false
                purpose               = $Purpose
                failure               = "Direct key failed: $failureMessage; replacement key failed: $replacementFailure"
            }
        }
    }
}

$result = [ordered]@{
    phase                = "Phase 3"
    checkedAtUtc         = (Get-Date).ToUniversalTime().ToString("o")
    environmentUrl       = $EnvironmentUrl.TrimEnd("/")
    solutionUniqueName   = $SolutionUniqueName
    solution             = $null
    app                  = $null
    requiredTables       = @()
    requiredSourceTables = @()
    entitySets           = [ordered]@{}
    optionValues         = [ordered]@{}
    alternateKeys        = @()
    policySeed           = $null
    publish              = $null
    blockers            = @()
}

$solutionFilter = [System.Uri]::EscapeDataString("uniquename eq '$SolutionUniqueName'")
$solutionResponse = Invoke-DvOrNull -Path "solutions?`$select=solutionid,uniquename,friendlyname,version,ismanaged&`$filter=$solutionFilter"
$result.solution = Get-First $solutionResponse
if (-not $result.solution) {
    $result.blockers += "Solution not found: $SolutionUniqueName"
}

$appFilter = [System.Uri]::EscapeDataString("uniquename eq 'qfu_RevenueFollowUpWorkbench'")
$appResponse = Invoke-DvOrNull -Path "appmodules?`$select=appmoduleid,name,uniquename&`$filter=$appFilter"
$result.app = Get-First $appResponse
if (-not $result.app) {
    $result.blockers += "Revenue Follow-Up Workbench app not found."
}

$mvpTables = @(
    "qfu_staff",
    "qfu_staffalias",
    "qfu_branchmembership",
    "qfu_policy",
    "qfu_workitem",
    "qfu_workitemaction",
    "qfu_alertlog",
    "qfu_assignmentexception"
)

$sourceTables = @("qfu_quote", "qfu_quoteline", "qfu_branch")

foreach ($table in ($mvpTables + $sourceTables | Select-Object -Unique)) {
    $metadata = Invoke-DvOrNull -Path "EntityDefinitions(LogicalName='$table')?`$select=LogicalName,SchemaName,MetadataId,EntitySetName,PrimaryIdAttribute,PrimaryNameAttribute"
    $found = [bool]$metadata
    $entry = [ordered]@{
        logicalName          = $table
        found                = $found
        entitySetName        = if ($metadata) { $metadata.EntitySetName } else { $null }
        primaryIdAttribute   = if ($metadata) { $metadata.PrimaryIdAttribute } else { $null }
        primaryNameAttribute = if ($metadata) { $metadata.PrimaryNameAttribute } else { $null }
    }
    if ($mvpTables -contains $table) {
        $result.requiredTables += $entry
    }
    else {
        $result.requiredSourceTables += $entry
    }
    if ($metadata) {
        $result.entitySets[$table] = $metadata.EntitySetName
    }
    else {
        $result.blockers += "Required table not found: $table"
    }
}

if ($result.blockers.Count -gt 0) {
    $directory = Split-Path -Parent $ResultPath
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $result | ConvertTo-Json -Depth 100 | Set-Content -Path $ResultPath -Encoding UTF8
    throw "Phase 3 foundation blocked: $($result.blockers -join '; ')"
}

$result.optionValues.qfu_worktype_quote = Get-OptionValue -ChoiceName "qfu_worktype" -Label "Quote"
$result.optionValues.qfu_sourcesystem_sp830ca = Get-OptionValue -ChoiceName "qfu_sourcesystem" -Label "SP830CA"
$result.optionValues.qfu_aliastype_amnumber = Get-OptionValue -ChoiceName "qfu_aliastype" -Label "AM Number"
$result.optionValues.qfu_aliastype_cssrnumber = Get-OptionValue -ChoiceName "qfu_aliastype" -Label "CSSR Number"
$result.optionValues.qfu_thresholdoperator_gte = Get-OptionValue -ChoiceName "qfu_thresholdoperator" -Label "GreaterThanOrEqual"
$result.optionValues.qfu_workitemgenerationmode_highvalueonly = Get-OptionValue -ChoiceName "qfu_workitemgenerationmode" -Label "HighValueOnly"
$result.optionValues.qfu_firstfollowupbasis_importdate = Get-OptionValue -ChoiceName "qfu_firstfollowupbasis" -Label "ImportDate"
$result.optionValues.qfu_alertmode_disabled = Get-OptionValue -ChoiceName "qfu_alertmode" -Label "Disabled"
$result.optionValues.qfu_cssralertmode_disabled = Get-OptionValue -ChoiceName "qfu_cssralertmode" -Label "Disabled"

$keyDefinitions = @(
    @{
        Table       = "qfu_staffalias"
        KeyName     = "qfu_key_staffalias_source_type_alias_scope"
        Columns     = @("qfu_sourcesystem", "qfu_aliastype", "qfu_normalizedalias", "qfu_scopekey")
        Purpose     = "Prevents duplicate alias mappings."
        Replacement = $null
    },
    @{
        Table       = "qfu_branchmembership"
        KeyName     = "qfu_key_branchmembership_branch_staff_role"
        Columns     = @("qfu_branch", "qfu_staff", "qfu_role")
        Purpose     = "Prevents duplicate branch/staff/role mappings where feasible."
        Replacement = $null
    },
    @{
        Table       = "qfu_policy"
        KeyName     = "qfu_key_policy_scope_worktype_activekey"
        Columns     = @("qfu_scopekey", "qfu_worktype", "qfu_active")
        Purpose     = "Helps prevent duplicate active policies."
        Replacement = @{
            Field       = "qfu_policykey"
            SchemaName  = "qfu_PolicyKey"
            DisplayName = "Policy Key"
        }
    },
    @{
        Table       = "qfu_workitem"
        KeyName     = "qfu_key_workitem_type_sourcekey"
        Columns     = @("qfu_worktype", "qfu_sourceexternalkey")
        Purpose     = "Ensures resolver reruns update the same work item instead of creating duplicates."
        Replacement = @{
            Field       = "qfu_workitemkey"
            SchemaName  = "qfu_WorkItemKey"
            DisplayName = "Work Item Key"
        }
    },
    @{
        Table       = "qfu_alertlog"
        KeyName     = "qfu_key_alertlog_dedupekey"
        Columns     = @("qfu_dedupekey")
        Purpose     = "Future alert dedupe. No alerts are sent in Phase 3."
        Replacement = $null
    },
    @{
        Table       = "qfu_assignmentexception"
        KeyName     = "qfu_key_assignmentexception_sourcekey_type_field_value"
        Columns     = @("qfu_sourceexternalkey", "qfu_exceptiontype", "qfu_sourcefield", "qfu_normalizedvalue")
        Purpose     = "Ensures reruns do not create duplicate exceptions."
        Replacement = @{
            Field       = "qfu_exceptionkey"
            SchemaName  = "qfu_ExceptionKey"
            DisplayName = "Exception Key"
        }
    }
)

foreach ($definition in $keyDefinitions) {
    if ($definition.Replacement) {
        $result.alternateKeys += Ensure-AlternateKey -Table $definition.Table -KeyName $definition.KeyName -Columns $definition.Columns -Purpose $definition.Purpose -ReplacementField $definition.Replacement.Field -ReplacementSchemaName $definition.Replacement.SchemaName -ReplacementDisplayName $definition.Replacement.DisplayName
    }
    else {
        $result.alternateKeys += Ensure-AlternateKey -Table $definition.Table -KeyName $definition.KeyName -Columns $definition.Columns -Purpose $definition.Purpose
    }
}

$policySet = $result.entitySets["qfu_policy"]
$policyKeyAttribute = Invoke-DvOrNull -Path "EntityDefinitions(LogicalName='qfu_policy')/Attributes(LogicalName='qfu_policykey')?`$select=LogicalName"
$policyKeyValue = "GLOBAL|Quote|Active"
$policy = $null
$policySelect = "qfu_policyid,qfu_name,qfu_scopekey,qfu_worktype,qfu_active,createdon"
if ($policyKeyAttribute) {
    $policySelect = "$policySelect,qfu_policykey"
}
$policyResponse = Invoke-DvOrNull -Path "${policySet}?`$select=$policySelect"
if ($policyResponse -and $null -ne $policyResponse.value) {
    $policies = @($policyResponse.value)
    if ($policyKeyAttribute) {
        $keyMatches = @($policies | Where-Object { $_.qfu_policykey -eq $policyKeyValue })
        if ($keyMatches.Count -gt 0) {
            $policy = $keyMatches[0]
        }
    }
    if (-not $policy) {
        $scopeMatches = @($policies | Where-Object { $_.qfu_scopekey -eq "GLOBAL" -and [int]$_.qfu_worktype -eq [int]$result.optionValues["qfu_worktype_quote"] })
        if ($scopeMatches.Count -gt 0) {
            $policy = $scopeMatches[0]
        }
    }
}
$policyBody = @{
    qfu_name                       = "Default Quote Follow-Up Policy"
    qfu_scopekey                   = "GLOBAL"
    qfu_worktype                   = $result.optionValues.qfu_worktype_quote
    qfu_highvaluethreshold         = 3000
    qfu_thresholdoperator          = $result.optionValues.qfu_thresholdoperator_gte
    qfu_workitemgenerationmode     = $result.optionValues.qfu_workitemgenerationmode_highvalueonly
    qfu_requiredattempts           = 3
    qfu_firstfollowupbasis         = $result.optionValues.qfu_firstfollowupbasis_importdate
    qfu_firstfollowupbusinessdays  = 1
    qfu_primaryownerstrategy       = "TSRFromAMNumber"
    qfu_supportownerstrategy       = "CSSRFromCSSRNumber"
    qfu_gmccmode                   = $result.optionValues.qfu_alertmode_disabled
    qfu_managerccmode              = $result.optionValues.qfu_alertmode_disabled
    qfu_cssralertmode              = $result.optionValues.qfu_cssralertmode_disabled
    qfu_digestenabled              = $false
    qfu_targetedalertenabled       = $false
    qfu_active                     = $true
}

if ($policyKeyAttribute) {
    $policyBody.qfu_policykey = $policyKeyValue
}

if ($policy) {
    Invoke-DvNoContent -Method Patch -Path "$policySet($($policy.qfu_policyid))" -Body $policyBody -WriteOperation:$true | Out-Null
    $result.policySeed = [ordered]@{
        status                       = "updated"
        policyId                     = $policy.qfu_policyid
        scope                        = "GLOBAL"
        workType                     = "Quote"
        highValueThreshold           = 3000
        thresholdOperator            = "GreaterThanOrEqual"
        workItemGenerationMode       = "HighValueOnly"
        requiredAttempts             = 3
        firstFollowUpBasis           = "ImportDate"
        firstFollowUpBusinessDays    = 1
        active                       = $true
        alertModes                   = "GM Disabled; Manager Disabled; CSSR Disabled; digest false; targeted false"
    }
}
else {
    try {
        $createdPolicy = Invoke-Dv -Method Post -Path $policySet -Body $policyBody -WriteOperation:$true
    }
    catch {
        $failureMessage = $_.Exception.Message
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $failureMessage = $_.ErrorDetails.Message
        }

        if ($failureMessage -notmatch "qfu_key_policy_scope_worktype_activekey") {
            throw
        }

        $recoverResponse = Invoke-Dv -Method Get -Path "${policySet}?`$select=qfu_policyid,qfu_name,qfu_scopekey,qfu_worktype,qfu_active,qfu_policykey"
        $recoverMatches = @(@($recoverResponse.value) | Where-Object { $_.qfu_policykey -eq $policyKeyValue })
        $createdPolicy = if ($recoverMatches.Count -gt 0) { $recoverMatches[0] } else { $null }
        if (-not $createdPolicy) {
            throw "Policy create hit duplicate key, but the existing keyed policy could not be retrieved. Original failure: $failureMessage"
        }
        Invoke-DvNoContent -Method Patch -Path "$policySet($($createdPolicy.qfu_policyid))" -Body $policyBody -WriteOperation:$true | Out-Null
    }
    $result.policySeed = [ordered]@{
        status                       = "created-or-recovered"
        policyId                     = $createdPolicy.qfu_policyid
        scope                        = "GLOBAL"
        workType                     = "Quote"
        highValueThreshold           = 3000
        thresholdOperator            = "GreaterThanOrEqual"
        workItemGenerationMode       = "HighValueOnly"
        requiredAttempts             = 3
        firstFollowUpBasis           = "ImportDate"
        firstFollowUpBusinessDays    = 1
        active                       = $true
        alertModes                   = "GM Disabled; Manager Disabled; CSSR Disabled; digest false; targeted false"
    }
}

$publish = & pac solution publish --environment $EnvironmentUrl.TrimEnd("/") 2>&1
$result.publish = [ordered]@{
    command  = "pac solution publish --environment $($EnvironmentUrl.TrimEnd('/'))"
    exitCode = $LASTEXITCODE
    output   = ($publish | Out-String).Trim()
}

$directory = Split-Path -Parent $ResultPath
if ($directory -and -not (Test-Path -LiteralPath $directory)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}

$result | ConvertTo-Json -Depth 100 | Set-Content -Path $ResultPath -Encoding UTF8
$result | ConvertTo-Json -Depth 100
