[CmdletBinding()]
param(
  [string]$TargetEnvironmentUrl = "https://regionaloperationshub.crm.dynamics.com",
  [string]$Username = "smcfarlane@applied.com",
  [string[]]$BranchCodes = @("4171", "4172", "4173"),
  [datetime]$AsOfDate = (Get-Date),
  [decimal]$Tolerance = 0.01,
  [string]$OutputJson = "VERIFICATION\budget-lineage-checks.json",
  [string]$OutputMarkdown = "VERIFICATION\budget-lineage-checks.md",
  [switch]$FailOnIssue
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

function Ensure-Directory {
  param([string]$Path)

  if (-not [string]::IsNullOrWhiteSpace($Path) -and -not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Resolve-RepoPath {
  param([string]$Path)

  if ([System.IO.Path]::IsPathRooted($Path)) {
    return $Path
  }

  return Join-Path $RepoRoot $Path
}

function Write-Utf8File {
  param(
    [string]$Path,
    [string]$Content
  )

  $resolved = Resolve-RepoPath -Path $Path
  Ensure-Directory (Split-Path -Parent $resolved)
  [System.IO.File]::WriteAllText($resolved, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Write-Utf8Json {
  param(
    [string]$Path,
    [object]$Object
  )

  Write-Utf8File -Path $Path -Content ($Object | ConvertTo-Json -Depth 20)
}

function Connect-Org {
  param([string]$Url)

  Import-Module Microsoft.Xrm.Data.Powershell

  $conn = Connect-CrmOnline -ServerUrl $Url -ForceOAuth -Username $Username
  if (-not $conn -or -not $conn.IsReady) {
    throw "Dataverse connection failed for $Url : $($conn.LastCrmError)"
  }

  return $conn
}

function Get-ActiveFiscalYearLabel {
  param([datetime]$ReferenceDate)

  $yearNumber = if ($ReferenceDate.Month -ge 7) { $ReferenceDate.Year + 1 } else { $ReferenceDate.Year }
  return "FY{0}" -f $yearNumber.ToString().Substring(2, 2)
}

function Normalize-FiscalYearLabel {
  param(
    [object]$Value,
    [int]$MonthNumber,
    [int]$YearNumber
  )

  $text = if ($null -eq $Value) { "" } else { ([string]$Value).Trim().ToUpperInvariant() }
  if ($text -match '^FY\d{2}$') {
    return $text
  }
  if ($YearNumber -gt 0) {
    $fiscalYear = if ($MonthNumber -ge 7) { $YearNumber + 1 } else { $YearNumber }
    return "FY{0}" -f $fiscalYear.ToString().Substring(2, 2)
  }
  return ""
}

function Get-DateValue {
  param(
    [object]$Row,
    [string[]]$Fields
  )

  foreach ($field in @($Fields)) {
    if ($Row.PSObject.Properties[$field] -and -not [string]::IsNullOrWhiteSpace([string]$Row.$field)) {
      try {
        return [datetime]$Row.$field
      } catch {
      }
    }
  }

  return $null
}

function Get-DecimalOrNull {
  param([object]$Value)

  if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
    return $null
  }

  return [decimal]$Value
}

function Format-Currency {
  param([object]$Value)

  $number = Get-DecimalOrNull -Value $Value
  if ($null -eq $number) {
    return "n/a"
  }

  return ('{0:C2}' -f $number)
}

function Format-Pace {
  param([object]$Value)

  $number = Get-DecimalOrNull -Value $Value
  if ($null -eq $number) {
    return "n/a"
  }

  return ('{0:N2}%' -f $number)
}

function Get-RowValue {
  param(
    [object]$Row,
    [string]$FieldName
  )

  if ($null -eq $Row -or -not $Row.PSObject.Properties[$FieldName]) {
    return $null
  }

  return $Row.$FieldName
}

function Value-Present {
  param([object]$Value)

  return ($null -ne $Value -and -not [string]::IsNullOrWhiteSpace([string]$Value))
}

function Values-Differ {
  param(
    [object]$Left,
    [object]$Right,
    [decimal]$Threshold
  )

  if (-not (Value-Present $Left) -or -not (Value-Present $Right)) {
    return $false
  }

  return [math]::Abs(([decimal]$Left) - ([decimal]$Right)) -gt $Threshold
}

function Test-BudgetRowIsActive {
  param([object]$Row)

  if ($Row.PSObject.Properties['qfu_isactive'] -and $Row.qfu_isactive -is [bool]) {
    return (-not [bool]$Row.qfu_isactive)
  }

  $text = if ($Row.PSObject.Properties['qfu_isactive']) { ([string]$Row.qfu_isactive).Trim().ToLowerInvariant() } else { "" }
  switch ($text) {
    "false" { return $true }
    "true" { return $false }
    "yes" { return $true }
    "no" { return $false }
    default { return $false }
  }
}

function Select-CanonicalBudgetRow {
  param(
    [object[]]$Rows,
    [string]$BranchCode,
    [int]$MonthNumber,
    [int]$YearNumber,
    [string]$FiscalYear
  )

  $expectedSourceId = "{0}|SA1300|{1}-{2:00}" -f $BranchCode, $YearNumber, $MonthNumber
  return @(
    $Rows |
      Sort-Object `
        @{ Expression = { if (Test-BudgetRowIsActive -Row $_) { 1 } else { 0 } }; Descending = $true }, `
        @{ Expression = { if ([string]$_.qfu_sourcefamily -eq "SA1300") { 1 } else { 0 } }; Descending = $true }, `
        @{ Expression = { if ([string]$_.qfu_sourceid -eq $expectedSourceId) { 1 } else { 0 } }; Descending = $true }, `
        @{ Expression = { if ([string]$_.qfu_fiscalyear -eq $FiscalYear) { 1 } else { 0 } }; Descending = $true }, `
        @{ Expression = { Get-DateValue -Row $_ -Fields @("qfu_lastupdated", "modifiedon", "createdon") } ; Descending = $true }, `
        @{ Expression = { if ($null -ne $_.qfu_budgetgoal) { 1 } else { 0 } }; Descending = $true }, `
        @{ Expression = { [string]$_.qfu_budgetid } }
  ) | Select-Object -First 1
}

function Select-CanonicalArchiveRow {
  param(
    [object[]]$Rows,
    [string]$BranchCode,
    [int]$MonthNumber,
    [string]$FiscalYear
  )

  $expectedSourceId = "{0}|budgetarchive|{1}|{2:00}" -f $BranchCode, $FiscalYear, $MonthNumber
  return @(
    $Rows |
      Sort-Object `
        @{ Expression = { if ([string]$_.qfu_sourceid -eq $expectedSourceId) { 1 } else { 0 } }; Descending = $true }, `
        @{ Expression = { if ($null -ne $_.qfu_budgetgoal) { 1 } else { 0 } }; Descending = $true }, `
        @{ Expression = { Get-DateValue -Row $_ -Fields @("qfu_lastupdated", "modifiedon", "createdon") } ; Descending = $true }, `
        @{ Expression = { [string]$_.qfu_budgetarchiveid } }
  ) | Select-Object -First 1
}

function New-Issue {
  param(
    [string]$Severity,
    [string]$Code,
    [string]$Detail
  )

  return [pscustomobject]@{
    severity = $Severity
    code = $Code
    detail = $Detail
  }
}

$connection = Connect-Org -Url $TargetEnvironmentUrl
$currentMonth = $AsOfDate.Month
$currentYear = $AsOfDate.Year
$currentFiscalYear = Get-ActiveFiscalYearLabel -ReferenceDate $AsOfDate
$branchResults = @()
$allIssues = New-Object System.Collections.Generic.List[object]

foreach ($branchCode in @($BranchCodes | Sort-Object -Unique)) {
  $budgetRows = @(
    (Get-CrmRecords -conn $connection -EntityLogicalName "qfu_budget" -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $branchCode -Fields @(
        "qfu_budgetid",
        "qfu_sourceid",
        "qfu_sourcefamily",
        "qfu_branchcode",
        "qfu_month",
        "qfu_year",
        "qfu_fiscalyear",
        "qfu_actualsales",
        "qfu_budgetgoal",
        "qfu_isactive",
        "qfu_lastupdated",
        "createdon",
        "modifiedon"
      ) -TopCount 50
    ).CrmRecords |
      Where-Object {
        [int]$_.qfu_month -eq $currentMonth -and
        (Normalize-FiscalYearLabel -Value $_.qfu_fiscalyear -MonthNumber ([int]$_.qfu_month) -YearNumber ([int]$_.qfu_year)) -eq $currentFiscalYear
      }
  )

  $archiveRows = @(
    (Get-CrmRecords -conn $connection -EntityLogicalName "qfu_budgetarchive" -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $branchCode -Fields @(
        "qfu_budgetarchiveid",
        "qfu_sourceid",
        "qfu_sourcefamily",
        "qfu_branchcode",
        "qfu_month",
        "qfu_year",
        "qfu_fiscalyear",
        "qfu_budgetgoal",
        "qfu_actualsales",
        "qfu_lastupdated",
        "createdon",
        "modifiedon"
      ) -TopCount 50
    ).CrmRecords |
      Where-Object {
        [int]$_.qfu_month -eq $currentMonth -and
        (Normalize-FiscalYearLabel -Value $_.qfu_fiscalyear -MonthNumber ([int]$_.qfu_month) -YearNumber ([int]$_.qfu_year)) -eq $currentFiscalYear
      }
  )

  $summaryRow = @(
    (Get-CrmRecords -conn $connection -EntityLogicalName "qfu_branchdailysummary" -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $branchCode -Fields @(
        "qfu_branchdailysummaryid",
        "qfu_branchcode",
        "qfu_summarydate",
        "qfu_budgetactual",
        "qfu_budgettarget",
        "qfu_budgetpace",
        "qfu_lastcalculatedon",
        "createdon",
        "modifiedon"
      ) -TopCount 10
    ).CrmRecords |
      Sort-Object { Get-DateValue -Row $_ -Fields @("qfu_summarydate", "qfu_lastcalculatedon", "createdon") } -Descending
  ) | Select-Object -First 1

  $canonicalBudget = Select-CanonicalBudgetRow -Rows $budgetRows -BranchCode $branchCode -MonthNumber $currentMonth -YearNumber $currentYear -FiscalYear $currentFiscalYear
  $canonicalArchive = Select-CanonicalArchiveRow -Rows $archiveRows -BranchCode $branchCode -MonthNumber $currentMonth -FiscalYear $currentFiscalYear
  $summaryDate = Get-DateValue -Row $summaryRow -Fields @("qfu_summarydate", "qfu_lastcalculatedon", "createdon")
  $summaryIsCurrentMonth = !!($summaryDate -and $summaryDate.Month -eq $currentMonth -and $summaryDate.Year -eq $currentYear)
  $issues = New-Object System.Collections.Generic.List[object]

  if ($budgetRows.Count -gt 1) {
    $issues.Add((New-Issue -Severity "warning" -Code "duplicate_current_budget_rows" -Detail "$branchCode has $($budgetRows.Count) current-month qfu_budget rows.")) | Out-Null
  }

  $activeBudgetRows = @($budgetRows | Where-Object { Test-BudgetRowIsActive -Row $_ })
  if ($activeBudgetRows.Count -gt 1) {
    $issues.Add((New-Issue -Severity "warning" -Code "duplicate_active_current_budget_rows" -Detail "$branchCode has $($activeBudgetRows.Count) active current-month qfu_budget rows.")) | Out-Null
  }

  if ($archiveRows.Count -gt 1) {
    $issues.Add((New-Issue -Severity "warning" -Code "duplicate_current_budgetarchive_rows" -Detail "$branchCode has $($archiveRows.Count) current-month qfu_budgetarchive rows.")) | Out-Null
  }

  $budgetActual = Get-DecimalOrNull -Value (Get-RowValue -Row $canonicalBudget -FieldName "qfu_actualsales")
  $budgetTarget = Get-DecimalOrNull -Value (Get-RowValue -Row $canonicalBudget -FieldName "qfu_budgetgoal")
  $archiveTarget = Get-DecimalOrNull -Value (Get-RowValue -Row $canonicalArchive -FieldName "qfu_budgetgoal")
  $summaryActual = if ($summaryIsCurrentMonth) { Get-DecimalOrNull -Value (Get-RowValue -Row $summaryRow -FieldName "qfu_budgetactual") } else { $null }
  $summaryTarget = if ($summaryIsCurrentMonth) { Get-DecimalOrNull -Value (Get-RowValue -Row $summaryRow -FieldName "qfu_budgettarget") } else { $null }

  if ($summaryRow -and -not $summaryIsCurrentMonth -and (Value-Present $summaryRow.qfu_budgetactual -or Value-Present $summaryRow.qfu_budgettarget)) {
    $issues.Add((New-Issue -Severity "warning" -Code "stale_summary_fallback_blocked" -Detail "$branchCode latest qfu_branchdailysummary row is from $($summaryDate.ToString('yyyy-MM-dd')); it must not drive April budget numbers.")) | Out-Null
  }

  if (Values-Differ -Left $archiveTarget -Right $budgetTarget -Threshold $Tolerance) {
    $issues.Add((New-Issue -Severity "warning" -Code "target_mismatch_archive_vs_budget" -Detail "$branchCode target mismatch: qfu_budgetarchive $(Format-Currency $archiveTarget) vs qfu_budget $(Format-Currency $budgetTarget).")) | Out-Null
  }

  if (Values-Differ -Left $archiveTarget -Right $summaryTarget -Threshold $Tolerance) {
    $issues.Add((New-Issue -Severity "warning" -Code "target_mismatch_archive_vs_summary" -Detail "$branchCode target mismatch: qfu_budgetarchive $(Format-Currency $archiveTarget) vs qfu_branchdailysummary $(Format-Currency $summaryTarget).")) | Out-Null
  }

  if (Values-Differ -Left $budgetActual -Right $summaryActual -Threshold $Tolerance) {
    $issues.Add((New-Issue -Severity "warning" -Code "actual_mismatch_budget_vs_summary" -Detail "$branchCode actual mismatch: qfu_budget $(Format-Currency $budgetActual) vs qfu_branchdailysummary $(Format-Currency $summaryActual).")) | Out-Null
  }

  $expectedActual = if ($null -ne $budgetActual) { $budgetActual } elseif ($null -ne $summaryActual) { $summaryActual } else { $null }
  $expectedActualSource = if ($null -ne $budgetActual) { "qfu_budget" } elseif ($null -ne $summaryActual) { "qfu_branchdailysummary" } else { "awaiting-live-actual" }
  $expectedTarget = if ($null -ne $archiveTarget) { $archiveTarget } elseif ($null -ne $summaryTarget) { $summaryTarget } elseif ($null -ne $budgetTarget) { $budgetTarget } else { $null }
  $expectedTargetSource = if ($null -ne $archiveTarget) { "qfu_budgetarchive" } elseif ($null -ne $summaryTarget) { "qfu_branchdailysummary" } elseif ($null -ne $budgetTarget) { "qfu_budget" } else { "missing-target" }
  $expectedPace = if ($null -ne $expectedActual -and $null -ne $expectedTarget -and $expectedTarget -gt 0) { [math]::Round(([decimal]$expectedActual / [decimal]$expectedTarget) * 100, 2) } else { $null }

  if ($null -eq $expectedTarget) {
    $issues.Add((New-Issue -Severity "critical" -Code "missing_current_month_target" -Detail "$branchCode has no trustworthy current-month budget target in qfu_budgetarchive, qfu_branchdailysummary, or qfu_budget.")) | Out-Null
  }

  if ($null -eq $expectedActual) {
    $issues.Add((New-Issue -Severity "warning" -Code "missing_current_month_actual" -Detail "$branchCode has no trustworthy current-month actual yet. Runtime should stay Awaiting Live SA1300 instead of backfilling the wrong month.")) | Out-Null
  }

  $branchResult = [pscustomobject]@{
    branch_code = $branchCode
    current_month = $currentMonth
    current_year = $currentYear
    current_fiscal_year = $currentFiscalYear
    summary = [pscustomobject]@{
      row_id = if ($summaryRow) { [string]$summaryRow.qfu_branchdailysummaryid } else { "" }
      summary_date = if ($summaryDate) { $summaryDate.ToString("yyyy-MM-dd") } else { "" }
      is_current_month = $summaryIsCurrentMonth
      budget_actual = $summaryActual
      budget_target = $summaryTarget
    }
    qfu_budget = [pscustomobject]@{
      candidate_count = $budgetRows.Count
      active_candidate_count = $activeBudgetRows.Count
      canonical_id = if ($canonicalBudget) { [string]$canonicalBudget.qfu_budgetid } else { "" }
      source_id = if ($canonicalBudget) { [string]$canonicalBudget.qfu_sourceid } else { "" }
      actual_sales = $budgetActual
      budget_goal = $budgetTarget
      last_updated = if ($canonicalBudget) { (Get-DateValue -Row $canonicalBudget -Fields @("qfu_lastupdated", "modifiedon", "createdon")).ToString("s") } else { "" }
    }
    qfu_budgetarchive = [pscustomobject]@{
      candidate_count = $archiveRows.Count
      canonical_id = if ($canonicalArchive) { [string]$canonicalArchive.qfu_budgetarchiveid } else { "" }
      source_id = if ($canonicalArchive) { [string]$canonicalArchive.qfu_sourceid } else { "" }
      budget_goal = $archiveTarget
      last_updated = if ($canonicalArchive) { (Get-DateValue -Row $canonicalArchive -Fields @("qfu_lastupdated", "modifiedon", "createdon")).ToString("s") } else { "" }
    }
    expected_display = [pscustomobject]@{
      actual = $expectedActual
      actual_source = $expectedActualSource
      target = $expectedTarget
      target_source = $expectedTargetSource
      pace_pct = $expectedPace
    }
    issues = $issues.ToArray()
  }

  $branchResults += $branchResult
  foreach ($issue in $issues) {
    $allIssues.Add([pscustomobject]@{
      branch_code = $branchCode
      severity = $issue.severity
      code = $issue.code
      detail = $issue.detail
    }) | Out-Null
  }
}

$displayableBranches = @($branchResults | Where-Object { $null -ne $_.expected_display.target })
$regionActual = 0
foreach ($branch in @($displayableBranches | Where-Object { $null -ne $_.expected_display.actual })) {
  $regionActual += [decimal]$branch.expected_display.actual
}
$regionTarget = 0
foreach ($branch in $displayableBranches) {
  $regionTarget += [decimal]$branch.expected_display.target
}
$regionPace = if ($regionTarget -and [decimal]$regionTarget -gt 0 -and $regionActual -ne $null) { [math]::Round(([decimal]$regionActual / [decimal]$regionTarget) * 100, 2) } else { $null }

$report = [pscustomobject]@{
  generated_at = (Get-Date).ToString("o")
  target_environment_url = $TargetEnvironmentUrl
  as_of_date = $AsOfDate.ToString("yyyy-MM-dd")
  current_month = $currentMonth
  current_year = $currentYear
  current_fiscal_year = $currentFiscalYear
  summary = [pscustomobject]@{
    branches_checked = $branchResults.Count
    total_issues = $allIssues.Count
    critical_issues = @($allIssues | Where-Object { $_.severity -eq "critical" }).Count
    warning_issues = @($allIssues | Where-Object { $_.severity -eq "warning" }).Count
  }
  region_expected_display = [pscustomobject]@{
    actual = $regionActual
    target = $regionTarget
    pace_pct = $regionPace
  }
  branches = $branchResults
  issues = $allIssues.ToArray()
}

$criticalIssueCount = @($allIssues | Where-Object { $_.severity -eq "critical" }).Count
$warningIssueCount = @($allIssues | Where-Object { $_.severity -eq "warning" }).Count

$markdown = @(
  "# Budget Lineage Checks",
  "",
  "- Generated: $($report.generated_at)",
  ('- Environment: `' + $TargetEnvironmentUrl + '`'),
  ("- As of: " + $AsOfDate.ToString("yyyy-MM-dd")),
  "- Branches checked: $($branchResults.Count)",
  ("- Issues: " + $allIssues.Count + " total (" + $criticalIssueCount + " critical, " + $warningIssueCount + " warning)"),
  "",
  "## Expected Display",
  "",
  "| Branch | Actual | Actual Source | Target | Target Source | Pace | Latest Summary | Issues |",
  "| --- | --- | --- | --- | --- | --- | --- | --- |"
)

foreach ($branch in $branchResults) {
  $markdown += "| $($branch.branch_code) | $(Format-Currency $branch.expected_display.actual) | $($branch.expected_display.actual_source) | $(Format-Currency $branch.expected_display.target) | $($branch.expected_display.target_source) | $(Format-Pace $branch.expected_display.pace_pct) | $($branch.summary.summary_date) | $(@($branch.issues).Count) |"
}

$markdown += @(
  "",
  "## Regional Rollup",
  "",
  "- Expected actual: $(Format-Currency $regionActual)",
  "- Expected target: $(Format-Currency $regionTarget)",
  "- Expected pace: $(Format-Pace $regionPace)",
  "",
  "## Issues",
  ""
)

if ($allIssues.Count -eq 0) {
  $markdown += "- None"
} else {
  foreach ($issue in $allIssues) {
    $markdown += "- [$($issue.severity)] $($issue.branch_code) $($issue.code): $($issue.detail)"
  }
}

Write-Utf8Json -Path $OutputJson -Object $report
Write-Utf8File -Path $OutputMarkdown -Content ($markdown -join [Environment]::NewLine)

Write-Host "JSON_PATH=$(Resolve-RepoPath -Path $OutputJson)"
Write-Host "MARKDOWN_PATH=$(Resolve-RepoPath -Path $OutputMarkdown)"

if ($FailOnIssue -and $allIssues.Count -gt 0) {
  throw "Budget lineage verification reported $($allIssues.Count) issue(s)."
}
