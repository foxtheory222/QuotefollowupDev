[CmdletBinding()]
param(
  [string]$ProbePath,
  [string[]]$BranchCodes = @("4171", "4172", "4173"),
  [datetime]$AsOfDate = (Get-Date),
  [string]$OutputJson,
  [string]$OutputMarkdown
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

function Ensure-Directory {
  param([string]$Path)

  if (-not [string]::IsNullOrWhiteSpace($Path) -and -not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Write-Utf8File {
  param(
    [string]$Path,
    [string]$Content
  )

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return
  }

  $parent = Split-Path -Parent $Path
  Ensure-Directory $parent
  [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Resolve-LatestProbePath {
  param([string]$RootPath)

  $candidate = Get-ChildItem -LiteralPath (Join-Path $RootPath "results") -Filter "portal-runtime-data-probe-*.json" -File -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending |
    Select-Object -First 1

  if ($candidate) {
    return $candidate.FullName
  }

  return $null
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

function Get-FormattedLabel {
  param(
    [object]$Row,
    [string]$FieldName
  )

  $formattedField = "{0}@OData.Community.Display.V1.FormattedValue" -f $FieldName
  if ($Row.PSObject.Properties[$formattedField] -and -not [string]::IsNullOrWhiteSpace([string]$Row.$formattedField)) {
    return [string]$Row.$formattedField
  }

  return ""
}

function Test-BudgetRowIsActive {
  param([object]$Row)

  if ($Row.PSObject.Properties['qfu_isactive'] -and $Row.qfu_isactive -is [bool]) {
    return (-not [bool]$Row.qfu_isactive)
  }

  $formatted = (Get-FormattedLabel -Row $Row -FieldName "qfu_isactive").Trim().ToLowerInvariant()
  switch ($formatted) {
    "yes" { return $true }
    "no" { return $false }
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

function Get-BudgetRowReason {
  param(
    [object]$Row,
    [string]$ExpectedSourceId
  )

  $reasons = [System.Collections.Generic.List[string]]::new()
  if (Test-BudgetRowIsActive -Row $Row) {
    $reasons.Add("active") | Out-Null
  }
  if ([string]$Row.qfu_sourcefamily -eq "SA1300") {
    $reasons.Add("SA1300") | Out-Null
  }
  if ([string]$Row.qfu_sourceid -eq $ExpectedSourceId) {
    $reasons.Add("canonical-sourceid") | Out-Null
  }

  $timestamp = Get-DateValue -Row $Row -Fields @("qfu_lastupdated", "modifiedon", "createdon")
  if ($timestamp) {
    $reasons.Add("latest=" + $timestamp.ToString("s")) | Out-Null
  }

  if ($reasons.Count) {
    return ($reasons -join ", ")
  }

  return "fallback-id-order"
}

function Get-ArchiveRowReason {
  param(
    [object]$Row,
    [string]$ExpectedSourceId
  )

  $reasons = [System.Collections.Generic.List[string]]::new()
  if ([string]$Row.qfu_sourceid -eq $ExpectedSourceId) {
    $reasons.Add("canonical-sourceid") | Out-Null
  }
  if ($null -ne $Row.qfu_budgetgoal) {
    $reasons.Add("has-goal") | Out-Null
  }

  $timestamp = Get-DateValue -Row $Row -Fields @("modifiedon", "createdon")
  if ($timestamp) {
    $reasons.Add("latest=" + $timestamp.ToString("s")) | Out-Null
  }

  if ($reasons.Count) {
    return ($reasons -join ", ")
  }

  return "fallback-id-order"
}

if ([string]::IsNullOrWhiteSpace($ProbePath)) {
  $ProbePath = Resolve-LatestProbePath -RootPath $RepoRoot
}

if ([string]::IsNullOrWhiteSpace($OutputJson)) {
  $OutputJson = Join-Path $RepoRoot "VERIFICATION\budget-duplicate-audit.json"
}

if ([string]::IsNullOrWhiteSpace($OutputMarkdown)) {
  $OutputMarkdown = Join-Path $RepoRoot "VERIFICATION\budget-duplicate-audit.md"
}

if (-not $ProbePath -or -not (Test-Path -LiteralPath $ProbePath)) {
  throw "Portal runtime data probe not found. Expected something like results\\portal-runtime-data-probe-*.json."
}

$probe = Get-Content -LiteralPath $ProbePath -Raw | ConvertFrom-Json
$budgetRows = @($probe.budgets.json.value)
$archiveRows = @($probe.budgetarchives.json.value)
$currentFiscalYear = Get-ActiveFiscalYearLabel -ReferenceDate $AsOfDate
$currentMonth = $AsOfDate.Month
$currentYear = $AsOfDate.Year

$filteredBudgetRows = @($budgetRows | Where-Object { $BranchCodes -contains [string]$_.qfu_branchcode })
$filteredArchiveRows = @($archiveRows | Where-Object { $BranchCodes -contains [string]$_.qfu_branchcode })

$budgetGroups = foreach ($group in ($filteredBudgetRows | Group-Object {
      $monthNumber = [int]$_.qfu_month
      $yearNumber = [int]$_.qfu_year
      $fiscalYear = Normalize-FiscalYearLabel -Value $_.qfu_fiscalyear -MonthNumber $monthNumber -YearNumber $yearNumber
      "{0}|{1}|{2:00}" -f [string]$_.qfu_branchcode, $fiscalYear, $monthNumber
    })) {
  $ordered = @($group.Group | Sort-Object `
      @{ Expression = { if (Test-BudgetRowIsActive -Row $_) { 1 } else { 0 } }; Descending = $true }, `
      @{ Expression = { if ([string]$_.qfu_sourcefamily -eq "SA1300") { 1 } else { 0 } }; Descending = $true }, `
      @{ Expression = { $expected = "{0}|SA1300|{1}-{2:00}" -f [string]$_.qfu_branchcode, [int]$_.qfu_year, [int]$_.qfu_month; if ([string]$_.qfu_sourceid -eq $expected) { 1 } else { 0 } }; Descending = $true }, `
      @{ Expression = { $timestamp = Get-DateValue -Row $_ -Fields @("qfu_lastupdated", "modifiedon", "createdon"); if ($timestamp) { $timestamp } else { [datetime]::MinValue } }; Descending = $true }, `
      @{ Expression = { if ($null -ne $_.qfu_budgetgoal) { 1 } else { 0 } }; Descending = $true }, `
      @{ Expression = { [string]$_.qfu_budgetid } })

  $winner = $ordered | Select-Object -First 1
  $monthNumber = [int]$winner.qfu_month
  $yearNumber = [int]$winner.qfu_year
  $fiscalYear = Normalize-FiscalYearLabel -Value $winner.qfu_fiscalyear -MonthNumber $monthNumber -YearNumber $yearNumber
  $expectedSourceId = "{0}|SA1300|{1}-{2:00}" -f [string]$winner.qfu_branchcode, $yearNumber, $monthNumber

  [pscustomobject]@{
    branchCode = [string]$winner.qfu_branchcode
    fiscalYear = $fiscalYear
    monthNumber = $monthNumber
    yearNumber = $yearNumber
    isCurrentMonth = ($monthNumber -eq $currentMonth -and $fiscalYear -eq $currentFiscalYear)
    candidateCount = $ordered.Count
    activeCandidateCount = @($ordered | Where-Object { Test-BudgetRowIsActive -Row $_ }).Count
    winner = [pscustomobject]@{
      budgetId = [string]$winner.qfu_budgetid
      sourceId = [string]$winner.qfu_sourceid
      active = Test-BudgetRowIsActive -Row $winner
      formattedLabel = Get-FormattedLabel -Row $winner -FieldName "qfu_isactive"
      reason = Get-BudgetRowReason -Row $winner -ExpectedSourceId $expectedSourceId
    }
    candidates = @($ordered | ForEach-Object {
        $timestamp = Get-DateValue -Row $_ -Fields @("qfu_lastupdated", "modifiedon", "createdon")
        $rowExpectedSourceId = "{0}|SA1300|{1}-{2:00}" -f [string]$_.qfu_branchcode, [int]$_.qfu_year, [int]$_.qfu_month
        [pscustomobject]@{
          budgetId = [string]$_.qfu_budgetid
          sourceId = [string]$_.qfu_sourceid
          sourceFamily = [string]$_.qfu_sourcefamily
          active = Test-BudgetRowIsActive -Row $_
          formattedLabel = Get-FormattedLabel -Row $_ -FieldName "qfu_isactive"
          lastUpdated = if ($timestamp) { $timestamp.ToString("s") } else { "" }
          actualSales = [double]$_.qfu_actualsales
          budgetGoal = [double]$_.qfu_budgetgoal
          reason = Get-BudgetRowReason -Row $_ -ExpectedSourceId $rowExpectedSourceId
        }
      })
  }
}

$archiveGroups = foreach ($group in ($filteredArchiveRows | Group-Object {
      $monthNumber = [int]$_.qfu_month
      $yearNumber = [int]$_.qfu_year
      $fiscalYear = Normalize-FiscalYearLabel -Value $_.qfu_fiscalyear -MonthNumber $monthNumber -YearNumber $yearNumber
      "{0}|{1}|{2:00}" -f [string]$_.qfu_branchcode, $fiscalYear, $monthNumber
    })) {
  $ordered = @($group.Group | Sort-Object `
      @{ Expression = { $expected = "{0}|budgetarchive|{1}|{2:00}" -f [string]$_.qfu_branchcode, (Normalize-FiscalYearLabel -Value $_.qfu_fiscalyear -MonthNumber ([int]$_.qfu_month) -YearNumber ([int]$_.qfu_year)), [int]$_.qfu_month; if ([string]$_.qfu_sourceid -eq $expected) { 1 } else { 0 } }; Descending = $true }, `
      @{ Expression = { if ($null -ne $_.qfu_budgetgoal) { 1 } else { 0 } }; Descending = $true }, `
      @{ Expression = { $timestamp = Get-DateValue -Row $_ -Fields @("modifiedon", "createdon"); if ($timestamp) { $timestamp } else { [datetime]::MinValue } }; Descending = $true }, `
      @{ Expression = { [string]$_.qfu_budgetarchiveid } })

  $winner = $ordered | Select-Object -First 1
  $monthNumber = [int]$winner.qfu_month
  $yearNumber = [int]$winner.qfu_year
  $fiscalYear = Normalize-FiscalYearLabel -Value $winner.qfu_fiscalyear -MonthNumber $monthNumber -YearNumber $yearNumber
  $expectedSourceId = "{0}|budgetarchive|{1}|{2:00}" -f [string]$winner.qfu_branchcode, $fiscalYear, $monthNumber

  [pscustomobject]@{
    branchCode = [string]$winner.qfu_branchcode
    fiscalYear = $fiscalYear
    monthNumber = $monthNumber
    yearNumber = $yearNumber
    isCurrentMonth = ($monthNumber -eq $currentMonth -and $fiscalYear -eq $currentFiscalYear)
    candidateCount = $ordered.Count
    winner = [pscustomobject]@{
      budgetArchiveId = [string]$winner.qfu_budgetarchiveid
      sourceId = [string]$winner.qfu_sourceid
      reason = Get-ArchiveRowReason -Row $winner -ExpectedSourceId $expectedSourceId
    }
    candidates = @($ordered | ForEach-Object {
        $timestamp = Get-DateValue -Row $_ -Fields @("modifiedon", "createdon")
        $rowFiscalYear = Normalize-FiscalYearLabel -Value $_.qfu_fiscalyear -MonthNumber ([int]$_.qfu_month) -YearNumber ([int]$_.qfu_year)
        $rowExpectedSourceId = "{0}|budgetarchive|{1}|{2:00}" -f [string]$_.qfu_branchcode, $rowFiscalYear, [int]$_.qfu_month
        [pscustomobject]@{
          budgetArchiveId = [string]$_.qfu_budgetarchiveid
          sourceId = [string]$_.qfu_sourceid
          budgetGoal = [double]$_.qfu_budgetgoal
          actualSales = if ($null -eq $_.qfu_actualsales) { $null } else { [double]$_.qfu_actualsales }
          lastUpdated = if ($timestamp) { $timestamp.ToString("s") } else { "" }
          reason = Get-ArchiveRowReason -Row $_ -ExpectedSourceId $rowExpectedSourceId
        }
      })
  }
}

$report = [pscustomobject]@{
  generatedOn = (Get-Date).ToString("s")
  probePath = $ProbePath
  asOfDate = $AsOfDate.ToString("yyyy-MM-dd")
  currentFiscalYear = $currentFiscalYear
  currentMonth = $currentMonth
  notes = @(
    "Raw qfu_isactive = false is treated as active.",
    "Current portal probe evidence also shows formatted Yes on rows where raw qfu_isactive = false."
  )
  budgetGroups = @($budgetGroups)
  archiveGroups = @($archiveGroups)
}

$duplicateBudgetGroups = @($budgetGroups | Where-Object { $_.candidateCount -gt 1 })
$duplicateArchiveGroups = @($archiveGroups | Where-Object { $_.candidateCount -gt 1 })
$currentBudgetGroups = @($budgetGroups | Where-Object { $_.isCurrentMonth })
$currentArchiveGroups = @($archiveGroups | Where-Object { $_.isCurrentMonth })

$markdown = @(
  "# Budget Duplicate Audit",
  "",
  "- Probe: $ProbePath",
  "- As of: $($AsOfDate.ToString("yyyy-MM-dd"))",
  "- Current fiscal year: $currentFiscalYear",
  "- Current month: $currentMonth",
  "- Budget groups with duplicates: $($duplicateBudgetGroups.Count)",
  "- Archive groups with duplicates: $($duplicateArchiveGroups.Count)",
  "",
  "## Notes",
  "",
  "- Raw `qfu_isactive = false` is treated as active.",
  "- Current portal probe evidence shows formatted `Yes` on rows where raw `qfu_isactive = false`.",
  ""
)

if ($currentBudgetGroups.Count) {
  $markdown += @(
    "## Current Month Budget Groups",
    "",
    "| Branch | FY | Month | Candidates | Active Candidates | Winner | Winner Reason |",
    "| --- | --- | ---: | ---: | ---: | --- | --- |"
  )
  foreach ($group in $currentBudgetGroups) {
    $markdown += "| $($group.branchCode) | $($group.fiscalYear) | $($group.monthNumber) | $($group.candidateCount) | $($group.activeCandidateCount) | $($group.winner.budgetId) | $($group.winner.reason) |"
  }
  $markdown += ""
}

if ($duplicateBudgetGroups.Count) {
  $markdown += "## Budget Duplicate Groups"
  $markdown += ""
  foreach ($group in $duplicateBudgetGroups) {
    $markdown += @(
      "### $($group.branchCode) | $($group.fiscalYear) | Month $($group.monthNumber)",
      "",
      "| Budget Id | Source Id | Active | Formatted Label | Last Updated | Actual Sales | Goal | Reason |",
      "| --- | --- | --- | --- | --- | ---: | ---: | --- |"
    )
    foreach ($candidate in $group.candidates) {
      $markdown += "| $($candidate.budgetId) | $($candidate.sourceId) | $($candidate.active) | $($candidate.formattedLabel) | $($candidate.lastUpdated) | $([math]::Round($candidate.actualSales, 2)) | $([math]::Round($candidate.budgetGoal, 2)) | $($candidate.reason) |"
    }
    $markdown += ""
  }
}

if ($currentArchiveGroups.Count) {
  $markdown += @(
    "## Current Month Archive Groups",
    "",
    "| Branch | FY | Month | Candidates | Winner | Winner Reason |",
    "| --- | --- | ---: | ---: | --- | --- |"
  )
  foreach ($group in $currentArchiveGroups) {
    $markdown += "| $($group.branchCode) | $($group.fiscalYear) | $($group.monthNumber) | $($group.candidateCount) | $($group.winner.budgetArchiveId) | $($group.winner.reason) |"
  }
  $markdown += ""
}

if ($duplicateArchiveGroups.Count) {
  $markdown += "## Archive Duplicate Groups"
  $markdown += ""
  foreach ($group in $duplicateArchiveGroups) {
    $markdown += @(
      "### $($group.branchCode) | $($group.fiscalYear) | Month $($group.monthNumber)",
      "",
      "| Archive Id | Source Id | Last Updated | Goal | Actual | Reason |",
      "| --- | --- | --- | ---: | ---: | --- |"
    )
    foreach ($candidate in $group.candidates) {
      $actualLabel = if ($null -eq $candidate.actualSales) { "" } else { [math]::Round($candidate.actualSales, 2) }
      $markdown += "| $($candidate.budgetArchiveId) | $($candidate.sourceId) | $($candidate.lastUpdated) | $([math]::Round($candidate.budgetGoal, 2)) | $actualLabel | $($candidate.reason) |"
    }
    $markdown += ""
  }
}

Write-Utf8File -Path $OutputMarkdown -Content ($markdown -join [Environment]::NewLine)
Write-Utf8File -Path $OutputJson -Content ($report | ConvertTo-Json -Depth 10)

$report | ConvertTo-Json -Depth 10
