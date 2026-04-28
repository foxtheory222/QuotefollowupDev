param(
    [string]$EnvironmentUrl = "https://orga632edd5.crm3.dynamics.com/",
    [string]$SolutionUniqueName = "qfu_revenuefollowupworkbench",
    [ValidateSet("DryRun", "Apply")][string]$Mode = "DryRun",
    [switch]$ConfirmApply,
    [string]$BranchCode = "",
    [int]$LimitQuoteGroups = 0,
    [string]$ScopeFile = "",
    [string]$ResultPath = "results/phase3-resolver-dryrun-20260427.json",
    [string]$ReportPath = "results/phase3-resolver-dryrun-20260427.md"
)

$ErrorActionPreference = "Stop"

if ($Mode -eq "Apply" -and -not $ConfirmApply) {
    throw "Apply mode requires -ConfirmApply. Default resolver execution must remain dry-run."
}

Import-Module Az.Accounts -ErrorAction Stop

if (-not $EnvironmentUrl.EndsWith("/")) {
    $EnvironmentUrl = "$EnvironmentUrl/"
}
$BranchCodeFilter = $BranchCode

function Import-ControlledScope {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return @()
    }

    $resolved = Resolve-Path -Path $Path -ErrorAction Stop
    $ext = [System.IO.Path]::GetExtension($resolved.Path).ToLowerInvariant()
    if ($ext -eq ".json") {
        $json = Get-Content -Raw -Path $resolved.Path | ConvertFrom-Json
        if ($json -is [array]) { return @($json) }
        if ($json.value) { return @($json.value) }
        return @($json)
    }

    return @(Import-Csv -Path $resolved.Path)
}

function Get-ScopeGroupKeys {
    param([object[]]$Rows)

    $keys = @{}
    foreach ($row in $Rows) {
        $selectedValue = $row.selected
        if ($null -ne $selectedValue -and [string]$selectedValue -notin @("TRUE", "True", "true", "1", "yes", "YES", "Yes")) {
            continue
        }

        $sourceExternalKey = if ($row.sourceexternalkey) { [string]$row.sourceexternalkey } elseif ($row.qfu_sourceexternalkey) { [string]$row.qfu_sourceexternalkey } else { "" }
        $branch = if ($row.branch_code) { [string]$row.branch_code } elseif ($row.qfu_branchcode) { [string]$row.qfu_branchcode } else { "" }
        $document = if ($row.sourcedocumentnumber) { [string]$row.sourcedocumentnumber } elseif ($row.qfu_sourcedocumentnumber) { [string]$row.qfu_sourcedocumentnumber } elseif ($row.quote_number) { [string]$row.quote_number } else { "" }

        if (-not [string]::IsNullOrWhiteSpace($sourceExternalKey)) {
            $parts = $sourceExternalKey.Split("|")
            if ($parts.Count -ge 3) {
                $branch = $parts[1]
                $document = $parts[2]
            }
        }

        if ([string]::IsNullOrWhiteSpace($branch) -or [string]::IsNullOrWhiteSpace($document)) {
            throw "Scope row is missing branch/document identity. Provide sourceexternalkey or branch_code + sourcedocumentnumber."
        }

        $groupKey = Get-GroupKey -BranchCode $branch -BranchSlug "" -QuoteNumber $document
        $keys[$groupKey] = $true
    }

    return $keys
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

function Invoke-DvAll {
    param([Parameter(Mandatory = $true)][string]$Path)

    $items = New-Object System.Collections.ArrayList
    $uri = "$($EnvironmentUrl)api/data/v9.2/$Path"
    $headers = Get-Headers

    while ($uri) {
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -ErrorAction Stop
        if ($response.value) {
            foreach ($item in @($response.value)) {
                [void]$items.Add($item)
            }
        }
        $uri = $response.'@odata.nextLink'
    }

    return @($items)
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

function Add-Count {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Map,
        [AllowNull()][string]$Key
    )

    if ([string]::IsNullOrWhiteSpace($Key)) {
        $Key = "BLANK"
    }
    if (-not $Map.ContainsKey($Key)) {
        $Map[$Key] = 0
    }
    $Map[$Key]++
}

function ConvertTo-TopCounts {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Map,
        [int]$Top = 10
    )

    return @(
        $Map.GetEnumerator() |
            Sort-Object Value -Descending |
            Select-Object -First $Top |
            ForEach-Object {
                [ordered]@{
                    value = $_.Key
                    count = $_.Value
                }
            }
    )
}

function Get-StableHash {
    param([Parameter(Mandatory = $true)][string]$Value)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    $hash = $sha.ComputeHash($bytes)
    return (($hash | ForEach-Object { $_.ToString("x2") }) -join "").Substring(0, 12)
}

function Normalize-QfuAlias {
    param([AllowNull()][object]$RawAlias)

    if ($null -eq $RawAlias) {
        return [ordered]@{ raw = $null; normalized = ""; isValid = $false; reason = "Blank" }
    }

    $rawText = ([string]$RawAlias).Trim()
    if ($rawText.Length -eq 0) {
        return [ordered]@{ raw = $rawText; normalized = ""; isValid = $false; reason = "Blank" }
    }

    $normalized = $rawText
    if ($rawText -match '^[+-]?\d+\.0+$') {
        $normalized = $rawText -replace '\.0+$', ''
    }
    elseif ($rawText -notmatch '^\d+$') {
        $normalized = $rawText.ToUpperInvariant()
    }

    $invalidTokens = @("", "0", "00000000", "NULL", "N/A", "NA", "NONE")
    $upper = $normalized.ToUpperInvariant()
    if ($invalidTokens -contains $upper) {
        $reason = if ($upper -eq "0" -or $upper -eq "00000000") { "Zero" } else { "Blank" }
        return [ordered]@{ raw = $rawText; normalized = $normalized; isValid = $false; reason = $reason }
    }

    return [ordered]@{ raw = $rawText; normalized = $normalized; isValid = $true; reason = "" }
}

function Get-NextBusinessDay {
    param(
        [AllowNull()][datetime]$BasisDate,
        [int]$BusinessDays = 1
    )

    if (-not $BasisDate) {
        $BasisDate = Get-Date
    }

    $date = $BasisDate.Date
    $remaining = [Math]::Max(1, $BusinessDays)
    while ($remaining -gt 0) {
        $date = $date.AddDays(1)
        if ($date.DayOfWeek -ne [System.DayOfWeek]::Saturday -and $date.DayOfWeek -ne [System.DayOfWeek]::Sunday) {
            $remaining--
        }
    }
    return $date
}

function Get-GroupKey {
    param(
        [AllowNull()][string]$BranchCode,
        [AllowNull()][string]$BranchSlug,
        [AllowNull()][string]$QuoteNumber
    )

    $branchPart = if (-not [string]::IsNullOrWhiteSpace($BranchCode)) { $BranchCode.Trim() } elseif (-not [string]::IsNullOrWhiteSpace($BranchSlug)) { $BranchSlug.Trim() } else { "UNKNOWN" }
    $quotePart = if (-not [string]::IsNullOrWhiteSpace($QuoteNumber)) { $QuoteNumber.Trim() } else { "UNKNOWN" }
    return "$branchPart|$quotePart"
}

function Select-SourceAlias {
    param(
        [object[]]$Rows,
        [string]$NumberField,
        [string]$NameField
    )

    $valid = @()
    $invalid = @()
    foreach ($row in $Rows) {
        $normalized = Normalize-QfuAlias -RawAlias $row.$NumberField
        if ($normalized.isValid) {
            $valid += [pscustomobject]$normalized
        }
        else {
            $invalid += [pscustomobject]$normalized
        }
    }

    $uniqueValid = @($valid | Group-Object normalized | ForEach-Object { $_.Group[0] })
    if ($uniqueValid.Count -eq 1) {
        return [ordered]@{
            status     = "valid"
            raw        = $uniqueValid[0].raw
            normalized = $uniqueValid[0].normalized
            reason     = ""
            display    = ($Rows | Where-Object { $_.$NameField } | Select-Object -First 1).$NameField
        }
    }
    if ($uniqueValid.Count -gt 1) {
        return [ordered]@{
            status     = "ambiguous-source"
            raw        = ($uniqueValid | ForEach-Object { $_.raw }) -join "|"
            normalized = ($uniqueValid | ForEach-Object { $_.normalized }) -join "|"
            reason     = "Multiple source number aliases on one quote"
            display    = ""
        }
    }

    $firstInvalid = if ($invalid.Count -gt 0) { $invalid[0] } else { [pscustomobject](Normalize-QfuAlias -RawAlias $null) }
    return [ordered]@{
        status     = "invalid"
        raw        = $firstInvalid.raw
        normalized = $firstInvalid.normalized
        reason     = $firstInvalid.reason
        display    = ($Rows | Where-Object { $_.$NameField } | Select-Object -First 1).$NameField
    }
}

function Resolve-Alias {
    param(
        [object[]]$Aliases,
        [int]$AliasType,
        [string]$NormalizedAlias,
        [AllowNull()][string]$BranchId,
        [AllowNull()][string]$BranchCode,
        [AllowNull()][string]$BranchSlug,
        [int]$SourceSystem
    )

    $matches = @($Aliases | Where-Object {
        [int]$_.qfu_sourcesystem -eq $SourceSystem -and
        [int]$_.qfu_aliastype -eq $AliasType -and
        $_.qfu_normalizedalias -eq $NormalizedAlias -and
        $_.'_qfu_staff_value'
    })

    if ($matches.Count -eq 0) {
        return [ordered]@{ status = "unmapped"; staffId = $null; matchCount = 0; reason = "No active alias mapping" }
    }

    $scored = @()
    foreach ($match in $matches) {
        $score = -1
        $matchBranch = $match.'_qfu_branch_value'
        $scope = if ($match.qfu_scopekey) { ([string]$match.qfu_scopekey).Trim() } else { "" }
        if ($BranchId -and $matchBranch -and $matchBranch -eq $BranchId) {
            $score = 3
        }
        elseif ($scope -and (($BranchCode -and $scope -eq $BranchCode) -or ($BranchSlug -and $scope -eq $BranchSlug))) {
            $score = 2
        }
        elseif (-not $matchBranch -and ([string]::IsNullOrWhiteSpace($scope) -or $scope -eq "GLOBAL")) {
            $score = 1
        }

        if ($score -ge 0) {
            $scored += [pscustomobject]@{
                score   = $score
                staffId = $match.'_qfu_staff_value'
                aliasId = $match.qfu_staffaliasid
            }
        }
    }

    if ($scored.Count -eq 0) {
        return [ordered]@{ status = "unmapped"; staffId = $null; matchCount = $matches.Count; reason = "Alias exists but no branch/scope match" }
    }

    $bestScore = ($scored | Measure-Object -Property score -Maximum).Maximum
    $best = @($scored | Where-Object { $_.score -eq $bestScore })
    $staffIds = @($best | Select-Object -ExpandProperty staffId -Unique)
    if ($staffIds.Count -gt 1) {
        return [ordered]@{ status = "ambiguous"; staffId = $null; matchCount = $best.Count; reason = "Multiple staff mappings at same scope priority" }
    }

    return [ordered]@{ status = "resolved"; staffId = $staffIds[0]; matchCount = $best.Count; reason = "" }
}

function New-ExceptionPlan {
    param(
        [string]$SourceExternalKey,
        [string]$SourceDocumentNumber,
        [int]$ExceptionType,
        [string]$ExceptionTypeLabel,
        [string]$SourceField,
        [string]$RawValue,
        [string]$NormalizedValue,
        [string]$DisplayName,
        [AllowNull()][string]$BranchId,
        [AllowNull()][string]$QuoteId,
        [AllowNull()][string]$QuoteLineId,
        [AllowNull()][string]$WorkItemId
    )

    $normalizedPart = if ([string]::IsNullOrWhiteSpace($NormalizedValue)) { "BLANK" } else { $NormalizedValue }
    $rawPart = if ([string]::IsNullOrWhiteSpace($RawValue)) { "BLANK" } else { $RawValue }
    $exceptionKey = "Quote|$SourceExternalKey|$ExceptionTypeLabel|$SourceField|$normalizedPart"
    return [ordered]@{
        exceptionKey          = $exceptionKey
        sourceExternalKey     = $SourceExternalKey
        sourceDocumentNumber  = $SourceDocumentNumber
        sourceDocumentHash    = Get-StableHash -Value $SourceDocumentNumber
        exceptionType         = $ExceptionTypeLabel
        exceptionTypeValue    = $ExceptionType
        sourceField           = $SourceField
        rawValue              = $rawPart
        normalizedValue       = $normalizedPart
        displayName           = $DisplayName
        branchId              = $BranchId
        quoteId               = $QuoteId
        quoteLineId           = $QuoteLineId
        workItemId            = $WorkItemId
    }
}

function Set-ExceptionPlanWorkItemId {
    param(
        [Parameter(Mandatory = $true)][System.Collections.ArrayList]$Plans,
        [Parameter(Mandatory = $true)][string]$SourceExternalKey,
        [Parameter(Mandatory = $true)][string]$WorkItemId
    )

    foreach ($plan in $Plans) {
        if ($plan.sourceExternalKey -eq $SourceExternalKey -and -not $plan.workItemId) {
            $plan["workItemId"] = $WorkItemId
        }
    }
}

function Test-CanAutoUpdateWorkItemStatus {
    param(
        [AllowNull()][object]$CurrentStatus,
        [System.Collections.IDictionary]$Option
    )

    if ($null -eq $CurrentStatus) { return $true }

    $systemOwned = @(
        [int]$Option.openWorkItemStatus,
        [int]$Option.dueTodayWorkItemStatus,
        [int]$Option.overdueWorkItemStatus
    )

    return $systemOwned -contains [int]$CurrentStatus
}

function Get-CalculatedWorkItemStatus {
    param(
        [AllowNull()][object]$NextFollowUpOn,
        [System.Collections.IDictionary]$Option,
        [datetime]$Today
    )

    if ($null -eq $NextFollowUpOn) {
        return [int]$Option.openWorkItemStatus
    }

    $followUpDate = ([datetime]$NextFollowUpOn).Date
    if ($followUpDate -lt $Today.Date) {
        return [int]$Option.overdueWorkItemStatus
    }
    if ($followUpDate -eq $Today.Date) {
        return [int]$Option.dueTodayWorkItemStatus
    }

    return [int]$Option.openWorkItemStatus
}

function Get-WorkItemStatusLabel {
    param(
        [AllowNull()][object]$Status,
        [System.Collections.IDictionary]$Option
    )

    if ($null -eq $Status) { return "Blank" }
    switch ([int]$Status) {
        ([int]$Option.openWorkItemStatus) { return "Open" }
        ([int]$Option.dueTodayWorkItemStatus) { return "Due Today" }
        ([int]$Option.overdueWorkItemStatus) { return "Overdue" }
        ([int]$Option.waitingCustomerWorkItemStatus) { return "Waiting on Customer" }
        ([int]$Option.waitingVendorWorkItemStatus) { return "Waiting on Vendor" }
        ([int]$Option.roadblockWorkItemStatus) { return "Roadblock" }
        ([int]$Option.escalatedWorkItemStatus) { return "Escalated" }
        ([int]$Option.completedWorkItemStatus) { return "Completed" }
        ([int]$Option.closedWonWorkItemStatus) { return "Closed Won" }
        ([int]$Option.closedLostWorkItemStatus) { return "Closed Lost" }
        ([int]$Option.cancelledWorkItemStatus) { return "Cancelled" }
        default { return [string]$Status }
    }
}

$option = [ordered]@{
    quoteWorkType          = Get-OptionValue -ChoiceName "qfu_worktype" -Label "Quote"
    sp830SourceSystem      = Get-OptionValue -ChoiceName "qfu_sourcesystem" -Label "SP830CA"
    amNumberAliasType      = Get-OptionValue -ChoiceName "qfu_aliastype" -Label "AM Number"
    cssrNumberAliasType    = Get-OptionValue -ChoiceName "qfu_aliastype" -Label "CSSR Number"
    gteOperator            = Get-OptionValue -ChoiceName "qfu_thresholdoperator" -Label "GreaterThanOrEqual"
    highValueOnlyMode      = Get-OptionValue -ChoiceName "qfu_workitemgenerationmode" -Label "HighValueOnly"
    allQuotesMode          = Get-OptionValue -ChoiceName "qfu_workitemgenerationmode" -Label "AllQuotes"
    reportingOnlyMode      = Get-OptionValue -ChoiceName "qfu_workitemgenerationmode" -Label "ReportingOnly"
    openWorkItemStatus     = Get-OptionValue -ChoiceName "qfu_workitemstatus" -Label "Open"
    dueTodayWorkItemStatus = Get-OptionValue -ChoiceName "qfu_workitemstatus" -Label "Due Today"
    overdueWorkItemStatus  = Get-OptionValue -ChoiceName "qfu_workitemstatus" -Label "Overdue"
    waitingCustomerWorkItemStatus = Get-OptionValue -ChoiceName "qfu_workitemstatus" -Label "Waiting on Customer"
    waitingVendorWorkItemStatus = Get-OptionValue -ChoiceName "qfu_workitemstatus" -Label "Waiting on Vendor"
    roadblockWorkItemStatus = Get-OptionValue -ChoiceName "qfu_workitemstatus" -Label "Roadblock"
    escalatedWorkItemStatus = Get-OptionValue -ChoiceName "qfu_workitemstatus" -Label "Escalated"
    completedWorkItemStatus = Get-OptionValue -ChoiceName "qfu_workitemstatus" -Label "Completed"
    closedWonWorkItemStatus = Get-OptionValue -ChoiceName "qfu_workitemstatus" -Label "Closed Won"
    closedLostWorkItemStatus = Get-OptionValue -ChoiceName "qfu_workitemstatus" -Label "Closed Lost"
    cancelledWorkItemStatus = Get-OptionValue -ChoiceName "qfu_workitemstatus" -Label "Cancelled"
    highPriority           = Get-OptionValue -ChoiceName "qfu_priority" -Label "High"
    assignedStatus         = Get-OptionValue -ChoiceName "qfu_assignmentstatus" -Label "Assigned"
    needsTsrStatus         = Get-OptionValue -ChoiceName "qfu_assignmentstatus" -Label "Needs TSR Assignment"
    needsCssrStatus        = Get-OptionValue -ChoiceName "qfu_assignmentstatus" -Label "Needs CSSR Assignment"
    unmappedStatus         = Get-OptionValue -ChoiceName "qfu_assignmentstatus" -Label "Unmapped"
    errorStatus            = Get-OptionValue -ChoiceName "qfu_assignmentstatus" -Label "Error"
    missingTsrException    = Get-OptionValue -ChoiceName "qfu_exceptiontype" -Label "Missing TSR Alias"
    missingCssrException   = Get-OptionValue -ChoiceName "qfu_exceptiontype" -Label "Missing CSSR Alias"
    blankAliasException    = Get-OptionValue -ChoiceName "qfu_exceptiontype" -Label "Blank Alias"
    zeroAliasException     = Get-OptionValue -ChoiceName "qfu_exceptiontype" -Label "Zero Alias"
    ambiguousException     = Get-OptionValue -ChoiceName "qfu_exceptiontype" -Label "Ambiguous Alias"
    missingBranchException = Get-OptionValue -ChoiceName "qfu_exceptiontype" -Label "Missing Branch"
    missingPolicyException = Get-OptionValue -ChoiceName "qfu_exceptiontype" -Label "Missing Policy"
    openExceptionStatus    = Get-OptionValue -ChoiceName "qfu_exceptionstatus" -Label "Open"
}

$entitySets = [ordered]@{
    quote                = Get-EntitySetName -LogicalName "qfu_quote"
    quoteLine            = Get-EntitySetName -LogicalName "qfu_quoteline"
    branch               = Get-EntitySetName -LogicalName "qfu_branch"
    staff                = Get-EntitySetName -LogicalName "qfu_staff"
    policy               = Get-EntitySetName -LogicalName "qfu_policy"
    staffAlias           = Get-EntitySetName -LogicalName "qfu_staffalias"
    workItem             = Get-EntitySetName -LogicalName "qfu_workitem"
    workItemAction       = Get-EntitySetName -LogicalName "qfu_workitemaction"
    assignmentException  = Get-EntitySetName -LogicalName "qfu_assignmentexception"
}

$activeQuoteFilter = [System.Uri]::EscapeDataString("statecode eq 0 and (qfu_active eq true or qfu_active eq null)")
$quoteSelect = "qfu_quoteid,qfu_quotenumber,qfu_branchcode,qfu_branchslug,qfu_amount,qfu_sourcedate,qfu_sourceupdatedon,qfu_sourceid,qfu_customername,modifiedon,createdon,qfu_active"
$quotes = Invoke-DvAll -Path "$($entitySets.quote)?`$select=$quoteSelect&`$filter=$activeQuoteFilter"
if ($BranchCodeFilter) {
    $quotes = @($quotes | Where-Object { $_.qfu_branchcode -eq $BranchCodeFilter })
}

$lineFilter = [System.Uri]::EscapeDataString("statecode eq 0")
$lineSelect = "qfu_quotelineid,qfu_quotenumber,qfu_branchcode,qfu_branchslug,qfu_tsr,qfu_tsrname,qfu_cssr,qfu_cssrname,qfu_linetotal,qfu_amount,qfu_sourcedate,qfu_lastimportdate,qfu_sourceid,qfu_uniquekey"
$quoteLines = Invoke-DvAll -Path "$($entitySets.quoteLine)?`$select=$lineSelect&`$filter=$lineFilter"
if ($BranchCodeFilter) {
    $quoteLines = @($quoteLines | Where-Object { $_.qfu_branchcode -eq $BranchCodeFilter })
}

$branches = Invoke-DvAll -Path "$($entitySets.branch)?`$select=qfu_branchid,qfu_branchcode,qfu_branchslug,qfu_name,qfu_active"
$policies = Invoke-DvAll -Path "$($entitySets.policy)?`$select=qfu_policyid,qfu_scopekey,qfu_policykey,qfu_worktype,qfu_highvaluethreshold,qfu_thresholdoperator,qfu_workitemgenerationmode,qfu_requiredattempts,qfu_firstfollowupbasis,qfu_firstfollowupbusinessdays,qfu_primaryownerstrategy,qfu_supportownerstrategy,qfu_active,_qfu_branch_value"
$aliases = Invoke-DvAll -Path "$($entitySets.staffAlias)?`$select=qfu_staffaliasid,qfu_sourcesystem,qfu_aliastype,qfu_normalizedalias,qfu_scopekey,qfu_active,_qfu_staff_value,_qfu_branch_value&`$filter=$([System.Uri]::EscapeDataString('statecode eq 0 and qfu_active eq true'))"
$existingWorkItems = Invoke-DvAll -Path "$($entitySets.workItem)?`$select=qfu_workitemid,qfu_sourceexternalkey,qfu_worktype,qfu_sourcesystem,qfu_completedattempts,qfu_nextfollowupon,qfu_lastfollowedupon,qfu_lastactionon,qfu_status,qfu_assignmentstatus,_qfu_primaryownerstaff_value,_qfu_supportownerstaff_value,_qfu_tsrstaff_value,_qfu_cssrstaff_value,qfu_stickynote&`$filter=$([System.Uri]::EscapeDataString('statecode eq 0'))"
$actions = Invoke-DvAll -Path "$($entitySets.workItemAction)?`$select=qfu_workitemactionid,_qfu_workitem_value,qfu_countsasattempt,qfu_actionon&`$filter=$([System.Uri]::EscapeDataString('statecode eq 0'))"
$existingExceptions = Invoke-DvAll -Path "$($entitySets.assignmentException)?`$select=qfu_assignmentexceptionid,qfu_exceptionkey,qfu_sourceexternalkey,qfu_exceptiontype,qfu_sourcefield,qfu_normalizedvalue&`$filter=$([System.Uri]::EscapeDataString('statecode eq 0'))"

$branchByCode = @{}
$branchBySlug = @{}
foreach ($branch in $branches) {
    if ($branch.qfu_branchcode) { $branchByCode[[string]$branch.qfu_branchcode] = $branch }
    if ($branch.qfu_branchslug) { $branchBySlug[[string]$branch.qfu_branchslug] = $branch }
}

$quoteByGroup = @{}
foreach ($quote in $quotes) {
    if ([string]::IsNullOrWhiteSpace($quote.qfu_quotenumber)) { continue }
    $key = Get-GroupKey -BranchCode $quote.qfu_branchcode -BranchSlug $quote.qfu_branchslug -QuoteNumber $quote.qfu_quotenumber
    if (-not $quoteByGroup.ContainsKey($key)) {
        $quoteByGroup[$key] = $quote
    }
}

$linesByGroup = @{}
foreach ($line in $quoteLines) {
    if ([string]::IsNullOrWhiteSpace($line.qfu_quotenumber)) { continue }
    $key = Get-GroupKey -BranchCode $line.qfu_branchcode -BranchSlug $line.qfu_branchslug -QuoteNumber $line.qfu_quotenumber
    if (-not $linesByGroup.ContainsKey($key)) {
        $linesByGroup[$key] = New-Object System.Collections.ArrayList
    }
    [void]$linesByGroup[$key].Add($line)
}

$workItemBySourceKey = @{}
foreach ($workItem in $existingWorkItems) {
    if ($workItem.qfu_sourceexternalkey -and [int]$workItem.qfu_worktype -eq [int]$option.quoteWorkType) {
        $workItemBySourceKey[$workItem.qfu_sourceexternalkey] = $workItem
    }
}

$rollupByWorkItem = @{}
foreach ($action in $actions) {
    $workItemId = $action.'_qfu_workitem_value'
    if (-not $workItemId) { continue }
    if (-not $rollupByWorkItem.ContainsKey($workItemId)) {
        $rollupByWorkItem[$workItemId] = [ordered]@{
            completedAttempts = 0
            lastFollowedUpOn  = $null
            lastActionOn      = $null
        }
    }
    $rollup = $rollupByWorkItem[$workItemId]
    $actionOn = if ($action.qfu_actionon) { [datetime]$action.qfu_actionon } else { $null }
    if ($actionOn) {
        if (-not $rollup.lastActionOn -or $actionOn -gt $rollup.lastActionOn) {
            $rollup.lastActionOn = $actionOn
        }
        if ($action.qfu_countsasattempt -eq $true) {
            $rollup.completedAttempts++
            if (-not $rollup.lastFollowedUpOn -or $actionOn -gt $rollup.lastFollowedUpOn) {
                $rollup.lastFollowedUpOn = $actionOn
            }
        }
    }
}

$exceptionByKey = @{}
foreach ($exception in $existingExceptions) {
    if ($exception.qfu_exceptionkey) {
        $exceptionByKey[$exception.qfu_exceptionkey] = $exception
    }
}

$globalPolicies = @($policies | Where-Object { $_.qfu_active -eq $true -and [int]$_.qfu_worktype -eq [int]$option.quoteWorkType -and $_.qfu_scopekey -eq "GLOBAL" })
$scopeRows = @()
$scopeGroupKeys = @{}
if (-not [string]::IsNullOrWhiteSpace($ScopeFile)) {
    $scopeRows = Import-ControlledScope -Path $ScopeFile
    if ($scopeRows.Count -eq 0) {
        throw "ScopeFile '$ScopeFile' did not contain any selected scope rows."
    }
    $scopeGroupKeys = Get-ScopeGroupKeys -Rows $scopeRows
}

$groups = @($quoteByGroup.Keys | Sort-Object)
if ($scopeGroupKeys.Count -gt 0) {
    $groups = @($groups | Where-Object { $scopeGroupKeys.ContainsKey($_) })
    if ($groups.Count -eq 0) {
        throw "ScopeFile '$ScopeFile' did not match any active quote groups."
    }
}
if ($LimitQuoteGroups -gt 0) {
    $groups = @($groups | Select-Object -First $LimitQuoteGroups)
}

$counts = [ordered]@{
    quoteSourceRecordsScanned          = $quotes.Count
    quoteLineRecordsScanned            = $quoteLines.Count
    quoteGroupsFound                   = $groups.Count
    quoteGroupsAtOrAboveThreshold      = 0
    workItemsWouldBeCreated            = 0
    workItemsWouldBeUpdated            = 0
    workItemsCreated                   = 0
    workItemsUpdated                   = 0
    lowValueQuoteGroupsSkipped         = 0
    tsrAliasesResolved                 = 0
    cssrAliasesResolved                = 0
    tsrExceptions                      = 0
    cssrExceptions                     = 0
    missingBranchExceptions            = 0
    missingPolicyExceptions            = 0
    ambiguousAliasExceptions           = 0
    assignmentExceptionsWouldBeCreated = 0
    assignmentExceptionsWouldBeUpdated = 0
    assignmentExceptionsCreated        = 0
    assignmentExceptionsUpdated        = 0
    alertsSent                         = 0
}

$topUnresolvedAm = @{}
$topUnresolvedCssr = @{}
$sampleWorkItems = New-Object System.Collections.ArrayList
$sampleExceptions = New-Object System.Collections.ArrayList
$exceptionPlans = New-Object System.Collections.ArrayList

foreach ($groupKey in $groups) {
    $quote = $quoteByGroup[$groupKey]
    $groupLines = if ($linesByGroup.ContainsKey($groupKey)) { @($linesByGroup[$groupKey].ToArray()) } else { @() }
    if ($groupLines.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($quote.qfu_quotenumber)) {
        $groupLines = @($quoteLines | Where-Object {
            $_.qfu_quotenumber -eq $quote.qfu_quotenumber -and
            (
                (-not [string]::IsNullOrWhiteSpace($quote.qfu_branchcode) -and $_.qfu_branchcode -eq $quote.qfu_branchcode) -or
                (-not [string]::IsNullOrWhiteSpace($quote.qfu_branchslug) -and $_.qfu_branchslug -eq $quote.qfu_branchslug)
            )
        })
    }
    $sourceRows = if ($groupLines.Count -gt 0) { $groupLines } else { @($quote) }

    $sourceBranchCode = if ($quote.qfu_branchcode) { [string]$quote.qfu_branchcode } elseif ($groupLines.Count -gt 0) { [string]$groupLines[0].qfu_branchcode } else { "" }
    $sourceBranchSlug = if ($quote.qfu_branchslug) { [string]$quote.qfu_branchslug } elseif ($groupLines.Count -gt 0) { [string]$groupLines[0].qfu_branchslug } else { "" }
    $branch = $null
    if ($sourceBranchCode -and $branchByCode.ContainsKey($sourceBranchCode)) {
        $branch = $branchByCode[$sourceBranchCode]
    }
    elseif ($sourceBranchSlug -and $branchBySlug.ContainsKey($sourceBranchSlug)) {
        $branch = $branchBySlug[$sourceBranchSlug]
    }

    $total = [decimal]0
    if ($groupLines.Count -gt 0) {
        foreach ($line in $groupLines) {
            if ($null -ne $line.qfu_linetotal) { $total += [decimal]$line.qfu_linetotal }
            elseif ($null -ne $line.qfu_amount) { $total += [decimal]$line.qfu_amount }
        }
    }
    if ($total -eq 0 -and $null -ne $quote.qfu_amount) {
        $total = [decimal]$quote.qfu_amount
    }

    $branchId = if ($branch) { $branch.qfu_branchid } else { $null }
    $branchPolicies = @()
    if ($branchId) {
        $branchPolicies = @($policies | Where-Object { $_.qfu_active -eq $true -and [int]$_.qfu_worktype -eq [int]$option.quoteWorkType -and $_.'_qfu_branch_value' -eq $branchId })
    }
    if ($branchPolicies.Count -eq 0 -and ($sourceBranchCode -or $sourceBranchSlug)) {
        $branchPolicies = @($policies | Where-Object {
            $_.qfu_active -eq $true -and
            [int]$_.qfu_worktype -eq [int]$option.quoteWorkType -and
            (($_.qfu_scopekey -eq $sourceBranchCode) -or ($_.qfu_scopekey -eq $sourceBranchSlug))
        })
    }
    $policy = if ($branchPolicies.Count -gt 0) { $branchPolicies[0] } elseif ($globalPolicies.Count -gt 0) { $globalPolicies[0] } else { $null }

    $sourceExternalKey = "SP830CA|$sourceBranchCode|$($quote.qfu_quotenumber)"
    $existingWorkItem = if ($workItemBySourceKey.ContainsKey($sourceExternalKey)) { $workItemBySourceKey[$sourceExternalKey] } else { $null }
    $sourceDocumentNumber = [string]$quote.qfu_quotenumber
    $representativeQuoteLineId = if ($groupLines.Count -gt 0) { $groupLines[0].qfu_quotelineid } else { $null }
    if (-not $representativeQuoteLineId -and -not [string]::IsNullOrWhiteSpace($quote.qfu_quotenumber)) {
        $fallbackQuoteLine = @($quoteLines | Where-Object {
            $_.qfu_quotenumber -eq $quote.qfu_quotenumber -and
            (
                (-not [string]::IsNullOrWhiteSpace($sourceBranchCode) -and $_.qfu_branchcode -eq $sourceBranchCode) -or
                (-not [string]::IsNullOrWhiteSpace($sourceBranchSlug) -and $_.qfu_branchslug -eq $sourceBranchSlug)
            )
        } | Select-Object -First 1)
        if ($fallbackQuoteLine.Count -gt 0) {
            $representativeQuoteLineId = $fallbackQuoteLine[0].qfu_quotelineid
        }
    }
    $existingWorkItemId = if ($existingWorkItem) { $existingWorkItem.qfu_workitemid } else { $null }

    if (-not $branch) {
        $counts.missingBranchExceptions++
        [void]$exceptionPlans.Add((New-ExceptionPlan -SourceExternalKey $sourceExternalKey -SourceDocumentNumber $sourceDocumentNumber -ExceptionType $option.missingBranchException -ExceptionTypeLabel "Missing Branch" -SourceField "qfu_branchcode" -RawValue $sourceBranchCode -NormalizedValue $sourceBranchCode -DisplayName "Missing branch for quote source" -BranchId $null -QuoteId $quote.qfu_quoteid -QuoteLineId $representativeQuoteLineId -WorkItemId $existingWorkItemId))
    }
    if (-not $policy) {
        $counts.missingPolicyExceptions++
        [void]$exceptionPlans.Add((New-ExceptionPlan -SourceExternalKey $sourceExternalKey -SourceDocumentNumber $sourceDocumentNumber -ExceptionType $option.missingPolicyException -ExceptionTypeLabel "Missing Policy" -SourceField "qfu_policy" -RawValue "" -NormalizedValue "GLOBAL" -DisplayName "Missing quote policy" -BranchId $branchId -QuoteId $quote.qfu_quoteid -QuoteLineId $representativeQuoteLineId -WorkItemId $existingWorkItemId))
        continue
    }

    $threshold = if ($null -ne $policy.qfu_highvaluethreshold) { [decimal]$policy.qfu_highvaluethreshold } else { [decimal]3000 }
    $generationMode = if ($null -ne $policy.qfu_workitemgenerationmode) { [int]$policy.qfu_workitemgenerationmode } else { [int]$option.highValueOnlyMode }
    $requiredAttempts = if ($null -ne $policy.qfu_requiredattempts) { [int]$policy.qfu_requiredattempts } else { 3 }
    $qualifies = if ([int]$policy.qfu_thresholdoperator -eq [int]$option.gteOperator) { $total -ge $threshold } else { $total -gt $threshold }
    if ($qualifies) {
        $counts.quoteGroupsAtOrAboveThreshold++
    }
    elseif ($generationMode -eq [int]$option.highValueOnlyMode) {
        $counts.lowValueQuoteGroupsSkipped++
        continue
    }
    elseif ($generationMode -eq [int]$option.reportingOnlyMode) {
        $counts.lowValueQuoteGroupsSkipped++
        continue
    }

    $tsrSource = Select-SourceAlias -Rows $sourceRows -NumberField "qfu_tsr" -NameField "qfu_tsrname"
    $cssrSource = Select-SourceAlias -Rows $sourceRows -NumberField "qfu_cssr" -NameField "qfu_cssrname"

    $tsrResolution = [ordered]@{ status = "not-attempted"; staffId = $null; reason = "" }
    $cssrResolution = [ordered]@{ status = "not-attempted"; staffId = $null; reason = "" }

    if ($tsrSource.status -eq "valid") {
        $tsrResolution = Resolve-Alias -Aliases $aliases -AliasType $option.amNumberAliasType -NormalizedAlias $tsrSource.normalized -BranchId $branchId -BranchCode $sourceBranchCode -BranchSlug $sourceBranchSlug -SourceSystem $option.sp830SourceSystem
        if ($tsrResolution.status -eq "resolved") {
            $counts.tsrAliasesResolved++
        }
        elseif ($tsrResolution.status -eq "ambiguous") {
            $counts.tsrExceptions++
            $counts.ambiguousAliasExceptions++
            Add-Count -Map $topUnresolvedAm -Key $tsrSource.normalized
            [void]$exceptionPlans.Add((New-ExceptionPlan -SourceExternalKey $sourceExternalKey -SourceDocumentNumber $sourceDocumentNumber -ExceptionType $option.ambiguousException -ExceptionTypeLabel "Ambiguous Alias" -SourceField "qfu_tsr" -RawValue $tsrSource.raw -NormalizedValue $tsrSource.normalized -DisplayName "Ambiguous TSR alias" -BranchId $branchId -QuoteId $quote.qfu_quoteid -QuoteLineId $representativeQuoteLineId -WorkItemId $existingWorkItemId))
        }
        else {
            $counts.tsrExceptions++
            Add-Count -Map $topUnresolvedAm -Key $tsrSource.normalized
            [void]$exceptionPlans.Add((New-ExceptionPlan -SourceExternalKey $sourceExternalKey -SourceDocumentNumber $sourceDocumentNumber -ExceptionType $option.missingTsrException -ExceptionTypeLabel "Missing TSR Alias" -SourceField "qfu_tsr" -RawValue $tsrSource.raw -NormalizedValue $tsrSource.normalized -DisplayName "Unmapped TSR alias" -BranchId $branchId -QuoteId $quote.qfu_quoteid -QuoteLineId $representativeQuoteLineId -WorkItemId $existingWorkItemId))
        }
    }
    elseif ($tsrSource.status -eq "ambiguous-source") {
        $counts.tsrExceptions++
        $counts.ambiguousAliasExceptions++
        Add-Count -Map $topUnresolvedAm -Key $tsrSource.normalized
        [void]$exceptionPlans.Add((New-ExceptionPlan -SourceExternalKey $sourceExternalKey -SourceDocumentNumber $sourceDocumentNumber -ExceptionType $option.ambiguousException -ExceptionTypeLabel "Ambiguous Alias" -SourceField "qfu_tsr" -RawValue $tsrSource.raw -NormalizedValue $tsrSource.normalized -DisplayName "Multiple TSR source aliases" -BranchId $branchId -QuoteId $quote.qfu_quoteid -QuoteLineId $representativeQuoteLineId -WorkItemId $existingWorkItemId))
    }
    else {
        $counts.tsrExceptions++
        Add-Count -Map $topUnresolvedAm -Key $tsrSource.normalized
        $exceptionType = if ($tsrSource.reason -eq "Zero") { $option.zeroAliasException } else { $option.blankAliasException }
        $exceptionLabel = if ($tsrSource.reason -eq "Zero") { "Zero Alias" } else { "Blank Alias" }
        [void]$exceptionPlans.Add((New-ExceptionPlan -SourceExternalKey $sourceExternalKey -SourceDocumentNumber $sourceDocumentNumber -ExceptionType $exceptionType -ExceptionTypeLabel $exceptionLabel -SourceField "qfu_tsr" -RawValue $tsrSource.raw -NormalizedValue $tsrSource.normalized -DisplayName "Invalid TSR alias" -BranchId $branchId -QuoteId $quote.qfu_quoteid -QuoteLineId $representativeQuoteLineId -WorkItemId $existingWorkItemId))
    }

    if ($cssrSource.status -eq "valid") {
        $cssrResolution = Resolve-Alias -Aliases $aliases -AliasType $option.cssrNumberAliasType -NormalizedAlias $cssrSource.normalized -BranchId $branchId -BranchCode $sourceBranchCode -BranchSlug $sourceBranchSlug -SourceSystem $option.sp830SourceSystem
        if ($cssrResolution.status -eq "resolved") {
            $counts.cssrAliasesResolved++
        }
        elseif ($cssrResolution.status -eq "ambiguous") {
            $counts.cssrExceptions++
            $counts.ambiguousAliasExceptions++
            Add-Count -Map $topUnresolvedCssr -Key $cssrSource.normalized
            [void]$exceptionPlans.Add((New-ExceptionPlan -SourceExternalKey $sourceExternalKey -SourceDocumentNumber $sourceDocumentNumber -ExceptionType $option.ambiguousException -ExceptionTypeLabel "Ambiguous Alias" -SourceField "qfu_cssr" -RawValue $cssrSource.raw -NormalizedValue $cssrSource.normalized -DisplayName "Ambiguous CSSR alias" -BranchId $branchId -QuoteId $quote.qfu_quoteid -QuoteLineId $representativeQuoteLineId -WorkItemId $existingWorkItemId))
        }
        else {
            $counts.cssrExceptions++
            Add-Count -Map $topUnresolvedCssr -Key $cssrSource.normalized
            [void]$exceptionPlans.Add((New-ExceptionPlan -SourceExternalKey $sourceExternalKey -SourceDocumentNumber $sourceDocumentNumber -ExceptionType $option.missingCssrException -ExceptionTypeLabel "Missing CSSR Alias" -SourceField "qfu_cssr" -RawValue $cssrSource.raw -NormalizedValue $cssrSource.normalized -DisplayName "Unmapped CSSR alias" -BranchId $branchId -QuoteId $quote.qfu_quoteid -QuoteLineId $representativeQuoteLineId -WorkItemId $existingWorkItemId))
        }
    }
    elseif ($cssrSource.status -eq "ambiguous-source") {
        $counts.cssrExceptions++
        $counts.ambiguousAliasExceptions++
        Add-Count -Map $topUnresolvedCssr -Key $cssrSource.normalized
        [void]$exceptionPlans.Add((New-ExceptionPlan -SourceExternalKey $sourceExternalKey -SourceDocumentNumber $sourceDocumentNumber -ExceptionType $option.ambiguousException -ExceptionTypeLabel "Ambiguous Alias" -SourceField "qfu_cssr" -RawValue $cssrSource.raw -NormalizedValue $cssrSource.normalized -DisplayName "Multiple CSSR source aliases" -BranchId $branchId -QuoteId $quote.qfu_quoteid -QuoteLineId $representativeQuoteLineId -WorkItemId $existingWorkItemId))
    }
    else {
        $counts.cssrExceptions++
        Add-Count -Map $topUnresolvedCssr -Key $cssrSource.normalized
        $exceptionType = if ($cssrSource.reason -eq "Zero") { $option.zeroAliasException } else { $option.blankAliasException }
        $exceptionLabel = if ($cssrSource.reason -eq "Zero") { "Zero Alias" } else { "Blank Alias" }
        [void]$exceptionPlans.Add((New-ExceptionPlan -SourceExternalKey $sourceExternalKey -SourceDocumentNumber $sourceDocumentNumber -ExceptionType $exceptionType -ExceptionTypeLabel $exceptionLabel -SourceField "qfu_cssr" -RawValue $cssrSource.raw -NormalizedValue $cssrSource.normalized -DisplayName "Invalid CSSR alias" -BranchId $branchId -QuoteId $quote.qfu_quoteid -QuoteLineId $representativeQuoteLineId -WorkItemId $existingWorkItemId))
    }

    $assignmentStatus = $option.assignedStatus
    if ($tsrResolution.status -ne "resolved" -and $cssrResolution.status -ne "resolved") {
        $assignmentStatus = $option.unmappedStatus
    }
    elseif ($tsrResolution.status -ne "resolved") {
        $assignmentStatus = $option.needsTsrStatus
    }
    elseif ($cssrResolution.status -ne "resolved") {
        $assignmentStatus = $option.needsCssrStatus
    }
    if (-not $branch -or -not $policy) {
        $assignmentStatus = $option.errorStatus
    }

    if ($existingWorkItem) {
        $counts.workItemsWouldBeUpdated++
    }
    else {
        $counts.workItemsWouldBeCreated++
    }

    $basisDate = if ($groupLines.Count -gt 0 -and $groupLines[0].qfu_lastimportdate) { [datetime]$groupLines[0].qfu_lastimportdate } elseif ($quote.qfu_sourceupdatedon) { [datetime]$quote.qfu_sourceupdatedon } elseif ($quote.modifiedon) { [datetime]$quote.modifiedon } else { [datetime]$quote.createdon }
    $nextFollowUp = Get-NextBusinessDay -BasisDate $basisDate -BusinessDays ([int]$policy.qfu_firstfollowupbusinessdays)
    $effectiveNextFollowUp = if ($existingWorkItem -and $existingWorkItem.qfu_nextfollowupon) { [datetime]$existingWorkItem.qfu_nextfollowupon } else { $nextFollowUp }
    $calculatedWorkItemStatus = Get-CalculatedWorkItemStatus -NextFollowUpOn $effectiveNextFollowUp -Option $option -Today (Get-Date).Date
    $canAutoUpdateStatus = if ($existingWorkItem) { Test-CanAutoUpdateWorkItemStatus -CurrentStatus $existingWorkItem.qfu_status -Option $option } else { $true }
    $existingRollup = if ($existingWorkItem -and $rollupByWorkItem.ContainsKey($existingWorkItem.qfu_workitemid)) { $rollupByWorkItem[$existingWorkItem.qfu_workitemid] } else { $null }

    $workItemPlan = [ordered]@{
        sampleId                    = Get-StableHash -Value $sourceExternalKey
        sourceExternalKeyHash       = Get-StableHash -Value $sourceExternalKey
        sourceDocumentHash          = Get-StableHash -Value $sourceDocumentNumber
        branchCode                  = $sourceBranchCode
        workType                    = "Quote"
        sourceSystem                = "SP830CA"
        totalValue                  = [Math]::Round($total, 2)
        requiredAttempts            = $requiredAttempts
        completedAttemptsActionRollup = if ($existingRollup) { $existingRollup.completedAttempts } else { $null }
        nextFollowUpOn              = $nextFollowUp.ToString("yyyy-MM-dd")
        effectiveNextFollowUpOn     = $effectiveNextFollowUp.ToString("yyyy-MM-dd")
        calculatedStatus            = Get-WorkItemStatusLabel -Status $calculatedWorkItemStatus -Option $option
        existingStatus              = if ($existingWorkItem) { Get-WorkItemStatusLabel -Status $existingWorkItem.qfu_status -Option $option } else { "New" }
        statusWillAutoUpdate        = [bool]$canAutoUpdateStatus
        assignmentStatus            = switch ($assignmentStatus) {
            $option.assignedStatus { "Assigned" }
            $option.needsTsrStatus { "Needs TSR Assignment" }
            $option.needsCssrStatus { "Needs CSSR Assignment" }
            $option.unmappedStatus { "Unmapped" }
            default { "Error" }
        }
        tsrResolution               = $tsrResolution.status
        cssrResolution              = $cssrResolution.status
        existingWorkItem            = [bool]$existingWorkItem
        preservation                = "Does not overwrite sticky note, sticky note timestamps, action history, last followed-up/action dates, or non-empty manual owners."
    }
    if ($sampleWorkItems.Count -lt 5) {
        [void]$sampleWorkItems.Add($workItemPlan)
    }

    if ($Mode -eq "Apply") {
        $body = @{
            qfu_workitemnumber       = "Quote $($quote.qfu_quotenumber)"
            qfu_worktype             = $option.quoteWorkType
            qfu_sourcesystem         = $option.sp830SourceSystem
            qfu_sourcedocumentnumber = $quote.qfu_quotenumber
            qfu_sourceexternalkey    = $sourceExternalKey
            qfu_totalvalue           = $total
            qfu_customername         = $quote.qfu_customername
            qfu_requiredattempts     = $requiredAttempts
            qfu_priority             = $option.highPriority
            qfu_assignmentstatus     = $assignmentStatus
            "qfu_Policy@odata.bind"  = "/$($entitySets.policy)($($policy.qfu_policyid))"
            "qfu_SourceQuote@odata.bind" = "/$($entitySets.quote)($($quote.qfu_quoteid))"
        }
        if ($branchId) { $body["qfu_Branch@odata.bind"] = "/$($entitySets.branch)($branchId)" }
        if ($representativeQuoteLineId) { $body["qfu_SourceQuoteLine@odata.bind"] = "/$($entitySets.quoteLine)($representativeQuoteLineId)" }
        if ($canAutoUpdateStatus) { $body.qfu_status = $calculatedWorkItemStatus }
        if (-not $existingWorkItem -or -not $existingWorkItem.qfu_nextfollowupon) { $body.qfu_nextfollowupon = $nextFollowUp.ToString("o") }
        if (-not $existingWorkItem) { $body.qfu_completedattempts = 0 }
        if ($tsrResolution.status -eq "resolved") {
            if (-not $existingWorkItem -or -not $existingWorkItem.'_qfu_primaryownerstaff_value') { $body["qfu_PrimaryOwnerStaff@odata.bind"] = "/$($entitySets.staff)($($tsrResolution.staffId))" }
            if (-not $existingWorkItem -or -not $existingWorkItem.'_qfu_tsrstaff_value') { $body["qfu_TsrStaff@odata.bind"] = "/$($entitySets.staff)($($tsrResolution.staffId))" }
        }
        if ($cssrResolution.status -eq "resolved") {
            if (-not $existingWorkItem -or -not $existingWorkItem.'_qfu_supportownerstaff_value') { $body["qfu_SupportOwnerStaff@odata.bind"] = "/$($entitySets.staff)($($cssrResolution.staffId))" }
            if (-not $existingWorkItem -or -not $existingWorkItem.'_qfu_cssrstaff_value') { $body["qfu_CssrStaff@odata.bind"] = "/$($entitySets.staff)($($cssrResolution.staffId))" }
        }

        if ($existingWorkItem) {
            Invoke-DvNoContent -Method Patch -Path "$($entitySets.workItem)($($existingWorkItem.qfu_workitemid))" -Body $body -WriteOperation:$true | Out-Null
            $counts.workItemsUpdated++
        }
        else {
            $createdWorkItem = Invoke-Dv -Method Post -Path $entitySets.workItem -Body $body -WriteOperation:$true
            if (-not $createdWorkItem.qfu_workitemid) {
                throw "Apply mode created a work item but the response did not include qfu_workitemid; refusing to continue because assignment exceptions could not be linked."
            }
            if ($exceptionPlans.Count -gt 0) {
                Set-ExceptionPlanWorkItemId -Plans $exceptionPlans -SourceExternalKey $sourceExternalKey -WorkItemId $createdWorkItem.qfu_workitemid
            }
            $counts.workItemsCreated++
        }
    }
}

foreach ($exceptionPlan in $exceptionPlans) {
    if ($exceptionByKey.ContainsKey($exceptionPlan.exceptionKey)) {
        $counts.assignmentExceptionsWouldBeUpdated++
    }
    else {
        $counts.assignmentExceptionsWouldBeCreated++
    }
    if ($sampleExceptions.Count -lt 5) {
        [void]$sampleExceptions.Add([ordered]@{
            sampleId          = Get-StableHash -Value $exceptionPlan.exceptionKey
            sourceDocumentHash = $exceptionPlan.sourceDocumentHash
            exceptionType     = $exceptionPlan.exceptionType
            sourceField       = $exceptionPlan.sourceField
            normalizedValue   = $exceptionPlan.normalizedValue
            quoteLineIdPresent = [bool]$exceptionPlan.quoteLineId
            existingException = $exceptionByKey.ContainsKey($exceptionPlan.exceptionKey)
        })
    }

    if ($Mode -eq "Apply") {
        $exceptionBody = @{
            qfu_name                  = "$($exceptionPlan.exceptionType) - $($exceptionPlan.sourceField)"
            qfu_exceptionkey          = $exceptionPlan.exceptionKey
            qfu_exceptiontype         = $exceptionPlan.exceptionTypeValue
            qfu_sourcesystem          = $option.sp830SourceSystem
            qfu_sourcefield           = $exceptionPlan.sourceField
            qfu_rawvalue              = $exceptionPlan.rawValue
            qfu_normalizedvalue       = $exceptionPlan.normalizedValue
            qfu_displayname           = $exceptionPlan.displayName
            qfu_sourcedocumentnumber  = $exceptionPlan.sourceDocumentNumber
            qfu_sourceexternalkey     = $exceptionPlan.sourceExternalKey
            qfu_status                = $option.openExceptionStatus
        }
        if ($exceptionPlan.branchId) { $exceptionBody["qfu_Branch@odata.bind"] = "/$($entitySets.branch)($($exceptionPlan.branchId))" }
        if ($exceptionPlan.quoteId) { $exceptionBody["qfu_SourceQuote@odata.bind"] = "/$($entitySets.quote)($($exceptionPlan.quoteId))" }
        if ($exceptionPlan.quoteLineId) { $exceptionBody["qfu_SourceQuoteLine@odata.bind"] = "/$($entitySets.quoteLine)($($exceptionPlan.quoteLineId))" }
        if ($exceptionPlan.workItemId) { $exceptionBody["qfu_WorkItem@odata.bind"] = "/$($entitySets.workItem)($($exceptionPlan.workItemId))" }

        if ($exceptionByKey.ContainsKey($exceptionPlan.exceptionKey)) {
            Invoke-DvNoContent -Method Patch -Path "$($entitySets.assignmentException)($($exceptionByKey[$exceptionPlan.exceptionKey].qfu_assignmentexceptionid))" -Body $exceptionBody -WriteOperation:$true | Out-Null
            $counts.assignmentExceptionsUpdated++
        }
        else {
            Invoke-Dv -Method Post -Path $entitySets.assignmentException -Body $exceptionBody -WriteOperation:$true | Out-Null
            $counts.assignmentExceptionsCreated++
        }
    }
}

$normalizationTests = @(
    "7001634.0",
    "corey carpenter",
    "",
    "0",
    "00000000",
    "N/A",
    "NULL",
    "001234"
) | ForEach-Object {
    $normalized = Normalize-QfuAlias -RawAlias $_
    [ordered]@{
        input      = $_
        normalized = $normalized.normalized
        isValid    = $normalized.isValid
        reason     = $normalized.reason
    }
}

$result = [ordered]@{
    phase                     = "Phase 3"
    checkedAtUtc              = (Get-Date).ToUniversalTime().ToString("o")
    environmentUrl            = $EnvironmentUrl.TrimEnd("/")
    solutionUniqueName        = $SolutionUniqueName
    mode                      = $Mode
    branchCodeFilter          = $BranchCodeFilter
    limitQuoteGroups          = $LimitQuoteGroups
    scopeFile                 = $ScopeFile
    scopeRowsProvided         = $scopeRows.Count
    scopeQuoteGroupsSelected  = $groups.Count
    entitySets                = $entitySets
    optionValues              = $option
    counts                    = $counts
    topUnresolvedAmNumbers    = ConvertTo-TopCounts -Map $topUnresolvedAm
    topUnresolvedCssrNumbers  = ConvertTo-TopCounts -Map $topUnresolvedCssr
    sampleWorkItemPayloads    = @($sampleWorkItems)
    sampleExceptionPayloads   = @($sampleExceptions)
    normalizationTests        = @($normalizationTests)
    rollupBehavior            = [ordered]@{
        implementedInResolverDryRun = $true
        activeServerSideFlowOrPlugin = $false
        completedAttempts = "Count related qfu_workitemaction rows where qfu_countsasattempt = true."
        lastFollowedUpOn = "Max qfu_actionon where qfu_countsasattempt = true."
        lastActionOn = "Max qfu_actionon across all related actions."
        applyModeNote = "Apply mode does not overwrite existing manual/action-derived values unless a later explicit rollup automation phase enables it."
    }
    applyModeHardening        = [ordered]@{
        exceptionSourceDocumentNumber = "qfu_sourcedocumentnumber is populated from the source quote number in apply mode."
        exceptionSourceQuoteLookup    = "qfu_sourcequote is populated when a quote header exists."
        exceptionSourceQuoteLineLookup = "qfu_sourcequoteline is populated from a representative quote line when available."
        newWorkItemExceptionLink      = "Newly created work item ids are captured and applied to related exception plans before exception writes."
        statusPreservation            = "Existing manual or terminal qfu_status values are preserved. System-owned Open, Due Today, and Overdue statuses are recalculated from qfu_nextfollowupon."
        ownerPreservation             = "Existing non-empty primary, support, TSR, and CSSR owner fields are not overwritten."
        nextFollowUpPreservation      = "Existing qfu_nextfollowupon is not overwritten."
        actionHistoryPreservation     = "qfu_workitemaction rows, qfu_lastfollowedupon, qfu_lastactionon, and existing completed attempts are not overwritten."
    }
    noAlertGuarantee          = "The resolver does not create qfu_alertlog records, does not call Power Automate alert flows, and reports alertsSent = 0."
    preservationGuarantee     = "The resolver does not overwrite qfu_stickynote, qfu_stickynoteupdatedon, qfu_stickynoteupdatedby, qfu_workitemaction history, qfu_lastfollowedupon, qfu_lastactionon, or non-empty manual owner fields."
}

$resultDirectory = Split-Path -Parent $ResultPath
if ($resultDirectory -and -not (Test-Path -LiteralPath $resultDirectory)) {
    New-Item -ItemType Directory -Path $resultDirectory -Force | Out-Null
}
$result | ConvertTo-Json -Depth 100 | Set-Content -Path $ResultPath -Encoding UTF8

$reportLines = New-Object System.Collections.Generic.List[string]
$reportLines.Add("# Phase 3 Resolver Dry-Run Results")
$reportLines.Add("")
$reportLines.Add("- Checked UTC: $($result.checkedAtUtc)")
$reportLines.Add("- Environment: $($result.environmentUrl)")
$reportLines.Add("- Mode: $Mode")
$reportLines.Add("- Branch filter: $(if ($BranchCodeFilter) { $BranchCodeFilter } else { 'none' })")
$reportLines.Add("- Alerts sent: 0")
$reportLines.Add("")
$reportLines.Add("## Counts")
$reportLines.Add("")
$reportLines.Add("| Metric | Count |")
$reportLines.Add("| --- | ---: |")
foreach ($property in $counts.Keys) {
    $reportLines.Add("| $property | $($counts[$property]) |")
}
$reportLines.Add("")
$reportLines.Add("## Top Unresolved AM Numbers")
$reportLines.Add("")
$reportLines.Add("| Value | Count |")
$reportLines.Add("| --- | ---: |")
foreach ($item in (ConvertTo-TopCounts -Map $topUnresolvedAm)) {
    $reportLines.Add("| $($item.value) | $($item.count) |")
}
$reportLines.Add("")
$reportLines.Add("## Top Unresolved CSSR Numbers")
$reportLines.Add("")
$reportLines.Add("| Value | Count |")
$reportLines.Add("| --- | ---: |")
foreach ($item in (ConvertTo-TopCounts -Map $topUnresolvedCssr)) {
    $reportLines.Add("| $($item.value) | $($item.count) |")
}
$reportLines.Add("")
$reportLines.Add("## Sanitized Sample Work Item Payloads")
$reportLines.Add("")
$reportLines.Add('```json')
$reportLines.Add((@($sampleWorkItems) | ConvertTo-Json -Depth 20))
$reportLines.Add('```')
$reportLines.Add("")
$reportLines.Add("## Sanitized Sample Assignment Exception Payloads")
$reportLines.Add("")
$reportLines.Add('```json')
$reportLines.Add((@($sampleExceptions) | ConvertTo-Json -Depth 20))
$reportLines.Add('```')
$reportLines.Add("")
$reportLines.Add("No customer names are included in this report. Source document values are represented as hashes in samples.")

$reportDirectory = Split-Path -Parent $ReportPath
if ($reportDirectory -and -not (Test-Path -LiteralPath $reportDirectory)) {
    New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
}
$resolvedReportDirectory = (Resolve-Path -LiteralPath $reportDirectory).Path
$resolvedReportPath = Join-Path $resolvedReportDirectory (Split-Path -Leaf $ReportPath)
[System.IO.File]::WriteAllText($resolvedReportPath, (($reportLines -join [Environment]::NewLine) + [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))

$result | ConvertTo-Json -Depth 100
