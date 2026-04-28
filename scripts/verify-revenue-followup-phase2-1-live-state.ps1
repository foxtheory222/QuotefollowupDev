param(
    [string]$EnvironmentUrl = "https://orga632edd5.crm3.dynamics.com/",
    [string]$SolutionUniqueName = "qfu_revenuefollowupworkbench",
    [string]$ResultPath = "results/phase2-1-live-state-20260427.json"
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

$token = Get-DataverseToken
$headers = @{
    Authorization      = "Bearer $token"
    "OData-MaxVersion" = "4.0"
    "OData-Version"    = "4.0"
    Accept             = "application/json"
}

function Invoke-DvGet {
    param([Parameter(Mandatory = $true)][string]$Path)

    $uri = "$($EnvironmentUrl)api/data/v9.2/$Path"
    return Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -ErrorAction Stop
}

function Invoke-DvGetOrNull {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        return Invoke-DvGet -Path $Path
    }
    catch {
        return $null
    }
}

function New-FoundResult {
    param(
        [string]$Name,
        [bool]$Found,
        [object]$Details = $null
    )

    return [ordered]@{
        name    = $Name
        found   = $Found
        details = $Details
    }
}

$expectedTables = @(
    "qfu_staff",
    "qfu_staffalias",
    "qfu_branchmembership",
    "qfu_policy",
    "qfu_workitem",
    "qfu_workitemaction",
    "qfu_alertlog",
    "qfu_assignmentexception"
)

$expectedChoices = @(
    "qfu_role",
    "qfu_worktype",
    "qfu_sourcesystem",
    "qfu_aliastype",
    "qfu_rolehint",
    "qfu_thresholdoperator",
    "qfu_workitemgenerationmode",
    "qfu_firstfollowupbasis",
    "qfu_alertmode",
    "qfu_cssralertmode",
    "qfu_workitemstatus",
    "qfu_priority",
    "qfu_escalationlevel",
    "qfu_assignmentstatus",
    "qfu_actiontype",
    "qfu_alerttype",
    "qfu_alertstatus",
    "qfu_exceptiontype",
    "qfu_exceptionstatus"
)

$expectedFields = [ordered]@{
    qfu_staff = @(
        "qfu_name", "qfu_primaryemail", "qfu_staffnumber", "qfu_systemuser",
        "qfu_entraobjectid", "qfu_defaultbranch", "qfu_active", "qfu_notes"
    )
    qfu_branchmembership = @(
        "qfu_branch", "qfu_staff", "qfu_role", "qfu_active", "qfu_startdate",
        "qfu_enddate", "qfu_isprimary", "qfu_notes"
    )
    qfu_staffalias = @(
        "qfu_sourcesystem", "qfu_aliastype", "qfu_rawalias", "qfu_normalizedalias",
        "qfu_rolehint", "qfu_branch", "qfu_scopekey", "qfu_staff", "qfu_active",
        "qfu_verifiedby", "qfu_verifiedon", "qfu_notes"
    )
    qfu_policy = @(
        "qfu_name", "qfu_branch", "qfu_scopekey", "qfu_worktype",
        "qfu_highvaluethreshold", "qfu_thresholdoperator", "qfu_workitemgenerationmode",
        "qfu_requiredattempts", "qfu_firstfollowupbasis", "qfu_firstfollowupbusinessdays",
        "qfu_primaryownerstrategy", "qfu_supportownerstrategy", "qfu_gmccmode",
        "qfu_managerccmode", "qfu_cssralertmode", "qfu_escalateafterbusinessdays",
        "qfu_digestenabled", "qfu_targetedalertenabled", "qfu_active"
    )
    qfu_assignmentexception = @(
        "qfu_exceptiontype", "qfu_branch", "qfu_sourcesystem", "qfu_sourcefield",
        "qfu_rawvalue", "qfu_normalizedvalue", "qfu_displayname", "qfu_sourcedocumentnumber",
        "qfu_sourceexternalkey", "qfu_sourcequote", "qfu_sourcequoteline",
        "qfu_sourcebackorder", "qfu_workitem", "qfu_status", "qfu_resolvedstaff",
        "qfu_resolvedby", "qfu_resolvedon", "qfu_notes"
    )
    qfu_workitem = @(
        "qfu_workitemnumber", "qfu_worktype", "qfu_sourcesystem", "qfu_branch",
        "qfu_sourcedocumentnumber", "qfu_stickynote", "qfu_stickynoteupdatedon",
        "qfu_stickynoteupdatedby", "qfu_customername", "qfu_totalvalue",
        "qfu_primaryownerstaff", "qfu_supportownerstaff", "qfu_tsrstaff", "qfu_cssrstaff",
        "qfu_requiredattempts", "qfu_completedattempts", "qfu_status", "qfu_priority",
        "qfu_nextfollowupon", "qfu_lastfollowedupon", "qfu_lastactionon", "qfu_overduesince",
        "qfu_escalationlevel", "qfu_policy", "qfu_assignmentstatus", "qfu_notes"
    )
    qfu_workitemaction = @(
        "qfu_workitem", "qfu_actiontype", "qfu_countsasattempt", "qfu_actionby",
        "qfu_actionon", "qfu_attemptnumber", "qfu_outcome", "qfu_nextfollowupon",
        "qfu_relatedalert", "qfu_notes"
    )
    qfu_alertlog = @(
        "qfu_workitem", "qfu_alerttype", "qfu_recipientstaff", "qfu_recipientemail",
        "qfu_ccemails", "qfu_dedupekey", "qfu_status", "qfu_senton",
        "qfu_failuremessage", "qfu_flowrunid", "qfu_notes"
    )
}

$expectedLookups = [ordered]@{
    qfu_staff = @("qfu_systemuser", "qfu_defaultbranch")
    qfu_branchmembership = @("qfu_branch", "qfu_staff")
    qfu_staffalias = @("qfu_branch", "qfu_staff", "qfu_verifiedby")
    qfu_policy = @("qfu_branch")
    qfu_assignmentexception = @(
        "qfu_branch", "qfu_sourcequote", "qfu_sourcequoteline", "qfu_sourcebackorder",
        "qfu_workitem", "qfu_resolvedstaff", "qfu_resolvedby"
    )
    qfu_workitem = @(
        "qfu_branch", "qfu_primaryownerstaff", "qfu_supportownerstaff", "qfu_tsrstaff",
        "qfu_cssrstaff", "qfu_policy"
    )
    qfu_workitemaction = @("qfu_workitem", "qfu_actionby", "qfu_relatedalert")
    qfu_alertlog = @("qfu_workitem", "qfu_recipientstaff")
}

$requiredViews = [ordered]@{
    qfu_staff = @("Active Staff", "Staff Missing Email", "Staff Missing Dataverse User")
    qfu_branchmembership = @("Active Branch Memberships", "Memberships by Branch", "Memberships by Role")
    qfu_staffalias = @("Active Aliases", "Unverified Aliases", "Aliases by Source System", "Potential Duplicate Aliases")
    qfu_policy = @("Active Policies", "Draft/Inactive Policies", "Policies by Branch", "Quote Policies")
    qfu_assignmentexception = @("Open Assignment Exceptions", "Missing TSR Alias", "Missing CSSR Alias", "Blank/Zero Alias Exceptions", "Resolved Exceptions")
    qfu_workitem = @("Open Work Items", "Needs TSR Assignment", "Needs CSSR Assignment", "Quotes >= `$3K", "Overdue Work Items", "Work Items with Sticky Notes")
    qfu_workitemaction = @("Recent Actions", "Attempt Actions", "Non-Attempt Actions")
    qfu_alertlog = @("Pending Alerts", "Failed Alerts", "Sent Alerts", "Suppressed/Skipped Alerts")
}

$result = [ordered]@{
    checkedAtUtc          = (Get-Date).ToUniversalTime().ToString("o")
    environmentUrl        = $EnvironmentUrl.TrimEnd("/")
    solutionUniqueName    = $SolutionUniqueName
    solution              = $null
    choices               = @()
    tables                = @()
    modelDrivenApps       = @()
    appFound              = $false
    formsByTable          = [ordered]@{}
    viewsByTable          = [ordered]@{}
    requiredViewCoverage  = [ordered]@{}
    errors                = @()
}

$encodedSolutionFilter = [System.Uri]::EscapeDataString("uniquename eq '$SolutionUniqueName'")
$solutionResponse = Invoke-DvGetOrNull -Path "solutions?`$select=solutionid,uniquename,friendlyname,version,ismanaged&`$filter=$encodedSolutionFilter"
if ($solutionResponse -and $solutionResponse.value.Count -gt 0) {
    $result.solution = $solutionResponse.value[0]
}

foreach ($choice in $expectedChoices) {
    $choiceMeta = Invoke-DvGetOrNull -Path "GlobalOptionSetDefinitions(Name='$choice')?`$select=Name,MetadataId"
    $result.choices += New-FoundResult -Name $choice -Found ([bool]$choiceMeta) -Details $choiceMeta
}

foreach ($table in $expectedTables) {
    $tableMeta = Invoke-DvGetOrNull -Path "EntityDefinitions(LogicalName='$table')?`$select=LogicalName,SchemaName,MetadataId,ObjectTypeCode"
    $attributes = @()
    $relationships = @()
    $fieldCoverage = @()
    $lookupCoverage = @()

    if ($tableMeta) {
        $attributeResponse = Invoke-DvGetOrNull -Path "EntityDefinitions(LogicalName='$table')/Attributes?`$select=LogicalName,SchemaName,AttributeType"
        if ($attributeResponse) {
            $attributes = @($attributeResponse.value)
        }

        $relationshipResponse = Invoke-DvGetOrNull -Path "EntityDefinitions(LogicalName='$table')/ManyToOneRelationships?`$select=SchemaName,ReferencingAttribute,ReferencedEntity,ReferencingEntity"
        if ($relationshipResponse) {
            $relationships = @($relationshipResponse.value)
        }
    }

    $fieldNames = @($attributes | ForEach-Object { $_.LogicalName })
    foreach ($field in $expectedFields[$table]) {
        $fieldCoverage += [ordered]@{
            name  = $field
            found = $fieldNames -contains $field
        }
    }

    $relationshipAttributes = @($relationships | ForEach-Object { $_.ReferencingAttribute })
    foreach ($lookup in $expectedLookups[$table]) {
        $lookupCoverage += [ordered]@{
            name  = $lookup
            found = $relationshipAttributes -contains $lookup
        }
    }

    $result.tables += [ordered]@{
        name                = $table
        found               = [bool]$tableMeta
        metadata            = $tableMeta
        expectedFields      = $fieldCoverage
        expectedLookups     = $lookupCoverage
        relationshipSummary = @($relationships | Select-Object SchemaName, ReferencingAttribute, ReferencedEntity)
    }

    $formFilter = [System.Uri]::EscapeDataString("objecttypecode eq '$table'")
    $formsResponse = Invoke-DvGetOrNull -Path "systemforms?`$select=formid,name,type,objecttypecode&`$filter=$formFilter"
    $result.formsByTable[$table] = @()
    if ($formsResponse) {
        $result.formsByTable[$table] = @($formsResponse.value | Select-Object name, type, formid)
    }

    $viewFilter = [System.Uri]::EscapeDataString("returnedtypecode eq '$table'")
    $viewsResponse = Invoke-DvGetOrNull -Path "savedqueries?`$select=savedqueryid,name,returnedtypecode,querytype,isdefault&`$filter=$viewFilter"
    $result.viewsByTable[$table] = @()
    if ($viewsResponse) {
        $result.viewsByTable[$table] = @($viewsResponse.value | Select-Object name, querytype, isdefault, savedqueryid)
    }

    $existingViewNames = @($result.viewsByTable[$table] | ForEach-Object { $_.name })
    $result.requiredViewCoverage[$table] = @()
    foreach ($viewName in $requiredViews[$table]) {
        $result.requiredViewCoverage[$table] += [ordered]@{
            name  = $viewName
            found = $existingViewNames -contains $viewName
        }
    }
}

$appsResponse = Invoke-DvGetOrNull -Path "appmodules?`$select=appmoduleid,name,uniquename,clienttype,url&`$top=200"
if ($appsResponse) {
    $result.modelDrivenApps = @(
        $appsResponse.value |
            Where-Object {
                $_.name -eq "Revenue Follow-Up Workbench" -or
                $_.uniquename -eq "qfu_revenuefollowupworkbench" -or
                $_.name -like "*Revenue Follow-Up*" -or
                $_.uniquename -like "*revenue*follow*"
            } |
            Select-Object appmoduleid, name, uniquename, clienttype, url
    )
    $result.appFound = @($result.modelDrivenApps).Count -gt 0
}

$resultDirectory = Split-Path -Parent $ResultPath
if ($resultDirectory -and -not (Test-Path $resultDirectory)) {
    New-Item -ItemType Directory -Path $resultDirectory -Force | Out-Null
}

$json = $result | ConvertTo-Json -Depth 80
[System.IO.File]::WriteAllText((Resolve-Path -LiteralPath (Split-Path -Parent $ResultPath)).Path + "\" + (Split-Path -Leaf $ResultPath), $json, [System.Text.UTF8Encoding]::new($false))

$summary = [ordered]@{
    environmentUrl = $result.environmentUrl
    solutionFound  = [bool]$result.solution
    tablesFound    = @($result.tables | Where-Object { $_.found }).Count
    choicesFound   = @($result.choices | Where-Object { $_.found }).Count
    appFound       = $result.appFound
    resultPath     = $ResultPath
}

$summary | ConvertTo-Json -Depth 10
