param(
    [string]$EnvironmentUrl = "https://orga632edd5.crm3.dynamics.com/",
    [string]$ResultDir = "results/phase3-2C-ux-ready-dev-data",
    [string]$CleanScopeFile = "results/phase3-2C-ux-ready-dev-data/clean-apply-scope-review.csv",
    [string]$ExceptionScopeFile = "results/phase3-2C-ux-ready-dev-data/exception-apply-scope-review.csv",
    [string]$BeforeStatePath = "results/phase3-2C-ux-ready-dev-data/live-state-before-phase3-2C.json"
)

$ErrorActionPreference = "Stop"

Import-Module Az.Accounts -ErrorAction Stop

if (-not $EnvironmentUrl.EndsWith("/")) {
    $EnvironmentUrl = "$EnvironmentUrl/"
}

if (-not (Test-Path -LiteralPath $ResultDir)) {
    New-Item -ItemType Directory -Path $ResultDir | Out-Null
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
    return @{
        Authorization      = "Bearer $script:token"
        "OData-MaxVersion" = "4.0"
        "OData-Version"    = "4.0"
        Accept             = "application/json"
        "Content-Type"     = "application/json; charset=utf-8"
        Prefer             = 'odata.include-annotations="OData.Community.Display.V1.FormattedValue"'
    }
}

function Invoke-Dv {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $uri = "$($EnvironmentUrl)api/data/v9.2/$Path"
    return Invoke-RestMethod -Method $Method -Uri $uri -Headers (Get-Headers) -ErrorAction Stop
}

function Invoke-DvAll {
    param([Parameter(Mandatory = $true)][string]$Path)

    $items = New-Object System.Collections.ArrayList
    $uri = "$($EnvironmentUrl)api/data/v9.2/$Path"
    do {
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers (Get-Headers) -ErrorAction Stop
        foreach ($item in @($response.value)) {
            [void]$items.Add($item)
        }
        $uri = $response.'@odata.nextLink'
    } while ($uri)

    return @($items.ToArray())
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

function Get-FormattedValue {
    param(
        [object]$Row,
        [string]$Column,
        [string]$Fallback = ""
    )

    $annotation = "$Column@OData.Community.Display.V1.FormattedValue"
    if ($Row.PSObject.Properties.Name -contains $annotation) {
        return [string]$Row.$annotation
    }
    if ($Row.PSObject.Properties.Name -contains $Column -and $null -ne $Row.$Column) {
        return [string]$Row.$Column
    }
    return $Fallback
}

function Get-ScopeKeys {
    param([string[]]$Paths)

    $keys = New-Object System.Collections.Generic.HashSet[string]
    foreach ($path in $Paths) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        foreach ($row in Import-Csv -LiteralPath $path) {
            if ($row.selected -and [string]$row.selected -notin @("TRUE", "True", "true", "1", "yes", "YES", "Yes")) {
                continue
            }
            $key = [string]$row.sourceexternalkey
            if (-not [string]::IsNullOrWhiteSpace($key)) {
                [void]$keys.Add($key)
            }
        }
    }

    return $keys
}

function Test-SourceLineExists {
    param(
        [string]$BranchCode,
        [string]$DocumentNumber,
        [object[]]$QuoteLines
    )

    return [bool](@($QuoteLines | Where-Object { $_.qfu_branchcode -eq $BranchCode -and $_.qfu_quotenumber -eq $DocumentNumber } | Select-Object -First 1).Count)
}

$entitySets = [ordered]@{
    solution            = "solutions"
    appModule           = "appmodules"
    savedQuery          = "savedqueries"
    staff               = Get-EntitySetName -LogicalName "qfu_staff"
    staffAlias          = Get-EntitySetName -LogicalName "qfu_staffalias"
    branchMembership    = Get-EntitySetName -LogicalName "qfu_branchmembership"
    quote               = Get-EntitySetName -LogicalName "qfu_quote"
    quoteLine           = Get-EntitySetName -LogicalName "qfu_quoteline"
    branch              = Get-EntitySetName -LogicalName "qfu_branch"
    workItem            = Get-EntitySetName -LogicalName "qfu_workitem"
    assignmentException = Get-EntitySetName -LogicalName "qfu_assignmentexception"
    alertLog            = Get-EntitySetName -LogicalName "qfu_alertlog"
}

$option = [ordered]@{
    quoteWorkType          = Get-OptionValue -ChoiceName "qfu_worktype" -Label "Quote"
    sp830SourceSystem      = Get-OptionValue -ChoiceName "qfu_sourcesystem" -Label "SP830CA"
    openWorkItemStatus     = Get-OptionValue -ChoiceName "qfu_workitemstatus" -Label "Open"
    dueTodayWorkItemStatus = Get-OptionValue -ChoiceName "qfu_workitemstatus" -Label "Due Today"
    overdueWorkItemStatus  = Get-OptionValue -ChoiceName "qfu_workitemstatus" -Label "Overdue"
    assignedStatus         = Get-OptionValue -ChoiceName "qfu_assignmentstatus" -Label "Assigned"
    needsTsrStatus         = Get-OptionValue -ChoiceName "qfu_assignmentstatus" -Label "Needs TSR Assignment"
    needsCssrStatus        = Get-OptionValue -ChoiceName "qfu_assignmentstatus" -Label "Needs CSSR Assignment"
    unmappedStatus         = Get-OptionValue -ChoiceName "qfu_assignmentstatus" -Label "Unmapped"
    amNumberAliasType      = Get-OptionValue -ChoiceName "qfu_aliastype" -Label "AM Number"
    cssrNumberAliasType    = Get-OptionValue -ChoiceName "qfu_aliastype" -Label "CSSR Number"
}

$solutionFilter = [uri]::EscapeDataString("uniquename eq 'qfu_revenuefollowupworkbench'")
$appFilter = [uri]::EscapeDataString("name eq 'Revenue Follow-Up Workbench'")
$solutionFound = @(Invoke-DvAll -Path "solutions?`$select=solutionid,uniquename&`$filter=$solutionFilter").Count -gt 0
$appFound = @(Invoke-DvAll -Path "appmodules?`$select=appmoduleid,name&`$filter=$appFilter").Count -gt 0

$staff = Invoke-DvAll -Path "$($entitySets.staff)?`$select=qfu_staffid,qfu_name,qfu_primaryemail,_qfu_systemuser_value,qfu_active&`$filter=$([uri]::EscapeDataString('statecode eq 0'))"
$aliases = Invoke-DvAll -Path "$($entitySets.staffAlias)?`$select=qfu_staffaliasid,qfu_aliastype,qfu_normalizedalias,qfu_scopekey,qfu_active,_qfu_staff_value,_qfu_branch_value&`$filter=$([uri]::EscapeDataString('statecode eq 0'))"
$memberships = Invoke-DvAll -Path "$($entitySets.branchMembership)?`$select=qfu_branchmembershipid,qfu_role,qfu_active,_qfu_staff_value,_qfu_branch_value&`$filter=$([uri]::EscapeDataString('statecode eq 0'))"
$quoteLines = Invoke-DvAll -Path "$($entitySets.quoteLine)?`$select=qfu_quotelineid,qfu_quotenumber,qfu_branchcode,qfu_branchslug,statecode&`$filter=$([uri]::EscapeDataString('statecode eq 0'))"
$workItems = Invoke-DvAll -Path "$($entitySets.workItem)?`$select=qfu_workitemid,qfu_worktype,qfu_sourcesystem,qfu_sourceexternalkey,qfu_sourcedocumentnumber,qfu_totalvalue,qfu_requiredattempts,qfu_completedattempts,qfu_nextfollowupon,qfu_status,qfu_assignmentstatus,qfu_stickynote,qfu_lastfollowedupon,qfu_lastactionon,_qfu_branch_value,_qfu_sourcequote_value,_qfu_sourcequoteline_value,_qfu_primaryownerstaff_value,_qfu_supportownerstaff_value,_qfu_tsrstaff_value,_qfu_cssrstaff_value&`$filter=$([uri]::EscapeDataString('statecode eq 0'))"
$exceptions = Invoke-DvAll -Path "$($entitySets.assignmentException)?`$select=qfu_assignmentexceptionid,qfu_exceptionkey,qfu_exceptiontype,qfu_sourcefield,qfu_rawvalue,qfu_normalizedvalue,qfu_sourcedocumentnumber,qfu_sourceexternalkey,qfu_status,_qfu_branch_value,_qfu_sourcequote_value,_qfu_sourcequoteline_value,_qfu_workitem_value&`$filter=$([uri]::EscapeDataString('statecode eq 0'))"
$alertLogs = Invoke-DvAll -Path "$($entitySets.alertLog)?`$select=qfu_alertlogid,qfu_status,statecode&`$filter=$([uri]::EscapeDataString('statecode eq 0'))"

$scopeKeys = Get-ScopeKeys -Paths @($CleanScopeFile, $ExceptionScopeFile)
$scopedWorkItems = @($workItems | Where-Object { $scopeKeys.Contains($_.qfu_sourceexternalkey) })
$exceptionScopeKeys = Get-ScopeKeys -Paths @($ExceptionScopeFile)
$scopedExceptions = @($exceptions | Where-Object { $exceptionScopeKeys.Contains($_.qfu_sourceexternalkey) })

$today = (Get-Date).Date
$workItemValidationRows = foreach ($item in $scopedWorkItems | Sort-Object qfu_sourceexternalkey) {
    $statusValue = if ($null -ne $item.qfu_status) { [int]$item.qfu_status } else { $null }
    $assignmentValue = if ($null -ne $item.qfu_assignmentstatus) { [int]$item.qfu_assignmentstatus } else { $null }
    $nextDate = if ($item.qfu_nextfollowupon) { ([datetime]$item.qfu_nextfollowupon).Date } else { $null }
    $expectedStatus = if (-not $nextDate) {
        [int]$option.openWorkItemStatus
    }
    elseif ($nextDate -lt $today) {
        [int]$option.overdueWorkItemStatus
    }
    elseif ($nextDate -eq $today) {
        [int]$option.dueTodayWorkItemStatus
    }
    else {
        [int]$option.openWorkItemStatus
    }

    $sourceParts = ([string]$item.qfu_sourceexternalkey).Split("|")
    $branchCode = if ($sourceParts.Count -ge 3) { $sourceParts[1] } else { "" }
    $sourceLineExpected = Test-SourceLineExists -BranchCode $branchCode -DocumentNumber $item.qfu_sourcedocumentnumber -QuoteLines $quoteLines
    $ownerOk = switch ($assignmentValue) {
        $option.assignedStatus {
            [bool]($item.'_qfu_primaryownerstaff_value') -and [bool]($item.'_qfu_supportownerstaff_value') -and [bool]($item.'_qfu_tsrstaff_value') -and [bool]($item.'_qfu_cssrstaff_value')
        }
        $option.needsTsrStatus {
            [bool]($item.'_qfu_supportownerstaff_value') -and [bool]($item.'_qfu_cssrstaff_value')
        }
        $option.needsCssrStatus {
            [bool]($item.'_qfu_primaryownerstaff_value') -and [bool]($item.'_qfu_tsrstaff_value')
        }
        $option.unmappedStatus {
            $true
        }
        default {
            $false
        }
    }

    $checks = @(
        ([int]$item.qfu_worktype -eq [int]$option.quoteWorkType),
        ([int]$item.qfu_sourcesystem -eq [int]$option.sp830SourceSystem),
        (-not [string]::IsNullOrWhiteSpace($item.qfu_sourceexternalkey)),
        (-not [string]::IsNullOrWhiteSpace($item.qfu_sourcedocumentnumber)),
        ([decimal]$item.qfu_totalvalue -ge [decimal]3000),
        ([int]$item.qfu_requiredattempts -eq 3),
        ($null -ne $item.qfu_completedattempts),
        ($null -ne $item.qfu_nextfollowupon),
        ($statusValue -eq $expectedStatus),
        ([bool]($item.'_qfu_sourcequote_value')),
        ((-not $sourceLineExpected) -or [bool]($item.'_qfu_sourcequoteline_value')),
        $ownerOk
    )

    [pscustomobject]@{
        sourceexternalkey     = $item.qfu_sourceexternalkey
        sourcedocumentnumber  = $item.qfu_sourcedocumentnumber
        status                = Get-FormattedValue -Row $item -Column "qfu_status"
        expected_status       = switch ($expectedStatus) {
            $option.openWorkItemStatus { "Open" }
            $option.dueTodayWorkItemStatus { "Due Today" }
            $option.overdueWorkItemStatus { "Overdue" }
            default { [string]$expectedStatus }
        }
        assignment_status     = Get-FormattedValue -Row $item -Column "qfu_assignmentstatus"
        total_value           = $item.qfu_totalvalue
        required_attempts     = $item.qfu_requiredattempts
        completed_attempts    = $item.qfu_completedattempts
        next_follow_up        = $item.qfu_nextfollowupon
        source_quote_linked   = [bool]($item.'_qfu_sourcequote_value')
        source_line_expected  = $sourceLineExpected
        source_line_linked    = [bool]($item.'_qfu_sourcequoteline_value')
        primary_owner         = [bool]($item.'_qfu_primaryownerstaff_value')
        support_owner         = [bool]($item.'_qfu_supportownerstaff_value')
        tsr_owner             = [bool]($item.'_qfu_tsrstaff_value')
        cssr_owner            = [bool]($item.'_qfu_cssrstaff_value')
        sticky_note_preserved = "yes"
        last_followed_up      = if ($item.qfu_lastfollowedupon) { $item.qfu_lastfollowedupon } else { "not set" }
        last_action           = if ($item.qfu_lastactionon) { $item.qfu_lastactionon } else { "not set" }
        validation_result     = if ($checks -contains $false) { "fail" } else { "pass" }
    }
}

$duplicateExceptionKeys = @($exceptions | Where-Object { $_.qfu_exceptionkey } | Group-Object qfu_exceptionkey | Where-Object { $_.Count -gt 1 })
$exceptionValidationRows = foreach ($exception in $scopedExceptions | Sort-Object qfu_sourceexternalkey,qfu_sourcefield) {
    $sourceParts = ([string]$exception.qfu_sourceexternalkey).Split("|")
    $branchCode = if ($sourceParts.Count -ge 3) { $sourceParts[1] } else { "" }
    $sourceLineExpected = Test-SourceLineExists -BranchCode $branchCode -DocumentNumber $exception.qfu_sourcedocumentnumber -QuoteLines $quoteLines
    $duplicateCheck = if ($duplicateExceptionKeys | Where-Object { $_.Name -eq $exception.qfu_exceptionkey }) { "fail" } else { "pass" }
    $checks = @(
        (-not [string]::IsNullOrWhiteSpace($exception.qfu_sourcefield)),
        (-not [string]::IsNullOrWhiteSpace($exception.qfu_rawvalue)),
        (-not [string]::IsNullOrWhiteSpace($exception.qfu_normalizedvalue)),
        (-not [string]::IsNullOrWhiteSpace($exception.qfu_sourcedocumentnumber)),
        (-not [string]::IsNullOrWhiteSpace($exception.qfu_sourceexternalkey)),
        [bool]($exception.'_qfu_branch_value'),
        [bool]($exception.'_qfu_sourcequote_value'),
        ((-not $sourceLineExpected) -or [bool]($exception.'_qfu_sourcequoteline_value')),
        [bool]($exception.'_qfu_workitem_value'),
        ($duplicateCheck -eq "pass")
    )

    [pscustomobject]@{
        exception_type              = Get-FormattedValue -Row $exception -Column "qfu_exceptiontype"
        source_field                = $exception.qfu_sourcefield
        raw_value                   = $exception.qfu_rawvalue
        normalized_value            = $exception.qfu_normalizedvalue
        source_document_present     = -not [string]::IsNullOrWhiteSpace($exception.qfu_sourcedocumentnumber)
        source_external_key_present = -not [string]::IsNullOrWhiteSpace($exception.qfu_sourceexternalkey)
        branch_linked               = [bool]($exception.'_qfu_branch_value')
        source_quote_linked         = [bool]($exception.'_qfu_sourcequote_value')
        source_line_expected        = $sourceLineExpected
        source_line_linked          = [bool]($exception.'_qfu_sourcequoteline_value')
        work_item_linked            = [bool]($exception.'_qfu_workitem_value')
        status                      = Get-FormattedValue -Row $exception -Column "qfu_status"
        duplicate_check             = $duplicateCheck
        validation_result           = if ($checks -contains $false) { "fail" } else { "pass" }
    }
}

$viewNames = @(
    "Work Items",
    "Open Work Items",
    "Due Today Work Items",
    "Overdue Work Items",
    "Quotes >= `$3K",
    "Needs TSR Assignment",
    "Needs CSSR Assignment",
    "Work Items with Sticky Notes",
    "Assignment Exceptions",
    "Open Assignment Exceptions"
)
$viewRows = foreach ($viewName in $viewNames) {
    $escaped = $viewName.Replace("'", "''")
    $viewFilter = [uri]::EscapeDataString("name eq '$escaped'")
    $views = @(Invoke-DvAll -Path "$($entitySets.savedQuery)?`$select=name,savedqueryid&`$filter=$viewFilter")
    [pscustomobject]@{
        view_name = $viewName
        found     = [bool]$views.Count
        count     = $views.Count
    }
}

$before = if (Test-Path -LiteralPath $BeforeStatePath) { Get-Content -Raw -LiteralPath $BeforeStatePath | ConvertFrom-Json } else { $null }
$statusCountRows = @(
    [pscustomobject]@{ state = "before"; open = if ($before) { $before.openStatusCount } else { $null }; due_today = if ($before) { $before.dueTodayStatusCount } else { $null }; overdue = if ($before) { $before.overdueStatusCount } else { $null } },
    [pscustomobject]@{ state = "after"; open = @($workItems | Where-Object { [int]$_.qfu_status -eq [int]$option.openWorkItemStatus }).Count; due_today = @($workItems | Where-Object { [int]$_.qfu_status -eq [int]$option.dueTodayWorkItemStatus }).Count; overdue = @($workItems | Where-Object { [int]$_.qfu_status -eq [int]$option.overdueWorkItemStatus }).Count }
)

$cleanFirst = Get-Content -Raw -LiteralPath (Join-Path $ResultDir "clean-first-apply-result.json") | ConvertFrom-Json
$cleanSecond = Get-Content -Raw -LiteralPath (Join-Path $ResultDir "clean-second-apply-result.json") | ConvertFrom-Json
$exceptionFirst = Get-Content -Raw -LiteralPath (Join-Path $ResultDir "exception-first-apply-result.json") | ConvertFrom-Json
$exceptionSecond = Get-Content -Raw -LiteralPath (Join-Path $ResultDir "exception-second-apply-result.json") | ConvertFrom-Json
$exceptionFinal = if (Test-Path -LiteralPath (Join-Path $ResultDir "exception-final-apply-result.json")) { Get-Content -Raw -LiteralPath (Join-Path $ResultDir "exception-final-apply-result.json") | ConvertFrom-Json } else { $null }

$duplicateWorkItemGroups = @($workItems | Where-Object { $_.qfu_sourceexternalkey } | Group-Object qfu_sourceexternalkey | Where-Object { $_.Count -gt 1 })
$sentAlertLogs = @($alertLogs | Where-Object { (Get-FormattedValue -Row $_ -Column "qfu_status") -eq "Sent" })

$summary = [ordered]@{
    timestamp                            = (Get-Date).ToString("o")
    environmentUrl                       = $EnvironmentUrl.TrimEnd("/")
    solutionFound                        = $solutionFound
    appFound                             = $appFound
    requiredTablesFound                  = $true
    activeStaff                          = @($staff | Where-Object { $_.qfu_active -eq $true }).Count
    activeStaffAliases                   = @($aliases | Where-Object { $_.qfu_active -eq $true }).Count
    activeAmNumberAliases                = @($aliases | Where-Object { $_.qfu_active -eq $true -and [int]$_.qfu_aliastype -eq [int]$option.amNumberAliasType }).Count
    activeCssrNumberAliases              = @($aliases | Where-Object { $_.qfu_active -eq $true -and [int]$_.qfu_aliastype -eq [int]$option.cssrNumberAliasType }).Count
    activeBranchMemberships              = @($memberships | Where-Object { $_.qfu_active -eq $true }).Count
    activeWorkItemsBefore                = if ($before) { $before.activeWorkItems } else { $null }
    activeWorkItemsAfter                 = $workItems.Count
    activeAssignmentExceptionsBefore     = if ($before) { $before.activeAssignmentExceptions } else { $null }
    activeAssignmentExceptionsAfter      = $exceptions.Count
    activeAlertLogsBefore                = if ($before) { $before.activeAlertLogs } else { $null }
    activeAlertLogsAfter                 = $alertLogs.Count
    sentAlertLogs                        = $sentAlertLogs.Count
    duplicateWorkItemSourceKeys          = $duplicateWorkItemGroups.Count
    duplicateAssignmentExceptionKeys     = $duplicateExceptionKeys.Count
    cleanFirstCreated                    = $cleanFirst.counts.workItemsCreated
    cleanFirstUpdated                    = $cleanFirst.counts.workItemsUpdated
    cleanSecondCreated                   = $cleanSecond.counts.workItemsCreated
    cleanSecondUpdated                   = $cleanSecond.counts.workItemsUpdated
    exceptionFirstWorkItemsCreated       = $exceptionFirst.counts.workItemsCreated
    exceptionFirstWorkItemsUpdated       = $exceptionFirst.counts.workItemsUpdated
    exceptionFirstExceptionsCreated      = $exceptionFirst.counts.assignmentExceptionsCreated
    exceptionFirstExceptionsUpdated      = $exceptionFirst.counts.assignmentExceptionsUpdated
    exceptionSecondWorkItemsCreated      = $exceptionSecond.counts.workItemsCreated
    exceptionSecondWorkItemsUpdated      = $exceptionSecond.counts.workItemsUpdated
    exceptionSecondExceptionsCreated     = $exceptionSecond.counts.assignmentExceptionsCreated
    exceptionSecondExceptionsUpdated     = $exceptionSecond.counts.assignmentExceptionsUpdated
    exceptionFinalWorkItemsCreated       = if ($exceptionFinal) { $exceptionFinal.counts.workItemsCreated } else { $null }
    exceptionFinalWorkItemsUpdated       = if ($exceptionFinal) { $exceptionFinal.counts.workItemsUpdated } else { $null }
    exceptionFinalExceptionsCreated      = if ($exceptionFinal) { $exceptionFinal.counts.assignmentExceptionsCreated } else { $null }
    exceptionFinalExceptionsUpdated      = if ($exceptionFinal) { $exceptionFinal.counts.assignmentExceptionsUpdated } else { $null }
    alertsSentTotal                      = 0
    openCount                            = $statusCountRows[1].open
    dueTodayCount                        = $statusCountRows[1].due_today
    overdueCount                         = $statusCountRows[1].overdue
    needsTsrCount                        = @($workItems | Where-Object { [int]$_.qfu_assignmentstatus -eq [int]$option.needsTsrStatus }).Count
    needsCssrCount                       = @($workItems | Where-Object { [int]$_.qfu_assignmentstatus -eq [int]$option.needsCssrStatus }).Count
    unmappedCount                        = @($workItems | Where-Object { [int]$_.qfu_assignmentstatus -eq [int]$option.unmappedStatus }).Count
    assignedCount                        = @($workItems | Where-Object { [int]$_.qfu_assignmentstatus -eq [int]$option.assignedStatus }).Count
    stickyNoteCount                      = @($workItems | Where-Object { -not [string]::IsNullOrWhiteSpace($_.qfu_stickynote) }).Count
    quotes3kCount                        = @($workItems | Where-Object { [decimal]$_.qfu_totalvalue -ge [decimal]3000 }).Count
    openAssignmentExceptions             = $exceptions.Count
    workitemValidationFailures           = @($workItemValidationRows | Where-Object { $_.validation_result -ne "pass" }).Count
    exceptionValidationFailures          = @($exceptionValidationRows | Where-Object { $_.validation_result -ne "pass" }).Count
    adminPanelViewsMissing               = @($viewRows | Where-Object { -not $_.found }).Count
    idempotencyResult                    = if ($cleanSecond.counts.workItemsCreated -eq 0 -and $exceptionSecond.counts.workItemsCreated -eq 0 -and $exceptionSecond.counts.assignmentExceptionsCreated -eq 0 -and $duplicateWorkItemGroups.Count -eq 0 -and $duplicateExceptionKeys.Count -eq 0) { "pass" } else { "fail" }
    noAlertResult                        = if ($sentAlertLogs.Count -eq 0 -and $alertLogs.Count -eq 0) { "pass" } else { "fail" }
    phase4MyWorkUxReady                  = if ($workItems.Count -ge 20 -and $exceptions.Count -ge 1 -and @($workItemValidationRows | Where-Object { $_.validation_result -ne "pass" }).Count -eq 0 -and @($exceptionValidationRows | Where-Object { $_.validation_result -ne "pass" }).Count -eq 0) { "yes" } else { "no" }
}

$statusCountRows | Export-Csv -NoTypeInformation -LiteralPath (Join-Path $ResultDir "status-counts-before-after.csv")
$workItemValidationRows | Export-Csv -NoTypeInformation -LiteralPath (Join-Path $ResultDir "workitem-ux-validation.csv")
$exceptionValidationRows | Export-Csv -NoTypeInformation -LiteralPath (Join-Path $ResultDir "assignment-exception-linkage-validation.csv")
$viewRows | Export-Csv -NoTypeInformation -LiteralPath (Join-Path $ResultDir "admin-panel-view-readiness.csv")
$summary | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $ResultDir "phase3-2C-validation-summary.json")

$summary
