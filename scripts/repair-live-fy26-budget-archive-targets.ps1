param(
  [string]$TargetEnvironmentUrl = "https://regionaloperationshub.crm.dynamics.com",
  [string]$Username = "smcfarlane@applied.com",
  [string]$FiscalYear = "FY26",
  [string]$SnapshotJson = "results\tmp-budget-debug.json",
  [string]$HistoricalActualsJson = "results\gl060-history-actuals-seed.json",
  [string]$OutputJson = "results\fy26-budget-archive-repair.json",
  [string]$OutputMarkdown = "VERIFICATION\annual-budget-target-repair.md",
  [switch]$Apply
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

$BranchMap = [ordered]@{
  "4171" = [ordered]@{ branch_slug = "4171-calgary"; region_slug = "southern-alberta"; branch_name = "Calgary" }
  "4172" = [ordered]@{ branch_slug = "4172-lethbridge"; region_slug = "southern-alberta"; branch_name = "Lethbridge" }
  "4173" = [ordered]@{ branch_slug = "4173-medicine-hat"; region_slug = "southern-alberta"; branch_name = "Medicine Hat" }
}

$FiscalMonths = @(
  @{ number = 7; short = "Jul" },
  @{ number = 8; short = "Aug" },
  @{ number = 9; short = "Sep" },
  @{ number = 10; short = "Oct" },
  @{ number = 11; short = "Nov" },
  @{ number = 12; short = "Dec" },
  @{ number = 1; short = "Jan" },
  @{ number = 2; short = "Feb" },
  @{ number = 3; short = "Mar" },
  @{ number = 4; short = "Apr" },
  @{ number = 5; short = "May" },
  @{ number = 6; short = "Jun" }
)

function Resolve-RepoPath {
  param([string]$Path)

  if ([System.IO.Path]::IsPathRooted($Path)) {
    return $Path
  }

  return Join-Path $RepoRoot $Path
}

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

  $resolved = Resolve-RepoPath -Path $Path
  Ensure-Directory -Path (Split-Path -Parent $resolved)
  [System.IO.File]::WriteAllText($resolved, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Write-Utf8Json {
  param(
    [string]$Path,
    [object]$Object
  )

  Write-Utf8File -Path $Path -Content ($Object | ConvertTo-Json -Depth 20)
}

function ConvertTo-DecimalOrNull {
  param([object]$Value)

  if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
    return $null
  }

  if ($Value -is [decimal] -or $Value -is [double] -or $Value -is [int] -or $Value -is [long]) {
    return [decimal]$Value
  }

  $cleaned = ([string]$Value) -replace "[^0-9\.\-]", ""
  if ([string]::IsNullOrWhiteSpace($cleaned)) {
    return $null
  }

  return [decimal]::Parse($cleaned, [System.Globalization.CultureInfo]::InvariantCulture)
}

function ConvertTo-IntOrZero {
  param([object]$Value)

  if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
    return 0
  }

  $cleaned = ([string]$Value) -replace "[^0-9\-]", ""
  if ([string]::IsNullOrWhiteSpace($cleaned)) {
    return 0
  }

  return [int]$cleaned
}

function Format-Currency {
  param([object]$Value)

  $number = ConvertTo-DecimalOrNull -Value $Value
  if ($null -eq $number) {
    return "n/a"
  }

  return ('{0:C2}' -f $number)
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

function Parse-BudgetSnapshot {
  param([string]$Path)

  $payload = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  $records = @()

  foreach ($branchPayload in @($payload)) {
    foreach ($row in @($branchPayload.archives)) {
      $monthNumber = ConvertTo-IntOrZero -Value $row.qfu_month
      $yearNumber = ConvertTo-IntOrZero -Value $row.qfu_year
      $budgetGoal = ConvertTo-DecimalOrNull -Value $row.qfu_budgetgoal
      $monthName = [string]$row.qfu_monthname
      $fiscalYear = [string]$row.qfu_fiscalyear

      if (-not $monthNumber -or -not $yearNumber -or $null -eq $budgetGoal) {
        continue
      }

      $records += [pscustomobject]@{
        branch_code = [string]$branchPayload.branch
        month = $monthNumber
        month_name = $monthName
        year = $yearNumber
        fiscal_year = if ([string]::IsNullOrWhiteSpace($fiscalYear)) { $FiscalYear } else { $fiscalYear }
        budget_goal = $budgetGoal
      }
    }
  }

  return @($records | Sort-Object branch_code, year, month)
}

function Parse-HistoricalActuals {
  param([string]$Path)

  $payload = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  $actuals = @{}

  foreach ($row in @($payload.updated_rows)) {
    $key = "{0}|{1}" -f [string]$row.branch_code, [int]$row.month
    $actuals[$key] = [decimal]$row.actual_sales
  }

  return $actuals
}

function Canonical-BudgetArchiveSourceId {
  param(
    [string]$BranchCode,
    [string]$TargetFiscalYear,
    [int]$MonthNumber
  )

  return "{0}|budgetarchive|{1}|{2:00}" -f $BranchCode, $TargetFiscalYear, $MonthNumber
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

function Select-CanonicalArchiveRow {
  param(
    [object[]]$Rows,
    [string]$BranchCode,
    [string]$BranchSlug,
    [string]$RegionSlug,
    [int]$MonthNumber,
    [int]$YearNumber,
    [string]$TargetFiscalYear
  )

  $expectedSourceId = Canonical-BudgetArchiveSourceId -BranchCode $BranchCode -TargetFiscalYear $TargetFiscalYear -MonthNumber $MonthNumber
  return @(
    $Rows |
      Sort-Object `
        @{ Expression = { if ([string]$_.qfu_sourceid -eq $expectedSourceId) { 1 } else { 0 } }; Descending = $true }, `
        @{ Expression = { if ([string]$_.qfu_fiscalyear -eq $TargetFiscalYear) { 1 } else { 0 } }; Descending = $true }, `
        @{ Expression = { if ([string]$_.qfu_branchslug -eq $BranchSlug) { 1 } else { 0 } }; Descending = $true }, `
        @{ Expression = { if ([string]$_.qfu_regionslug -eq $RegionSlug) { 1 } else { 0 } }; Descending = $true }, `
        @{ Expression = { if (ConvertTo-DecimalOrNull -Value $_.qfu_budgetgoal) { 1 } else { 0 } }; Descending = $true }, `
        @{ Expression = { Get-DateValue -Row $_ -Fields @("qfu_lastupdated", "modifiedon", "createdon") }; Descending = $true }, `
        @{ Expression = { [string]$_.qfu_budgetarchiveid } }
  ) | Select-Object -First 1
}

function Get-LiveBudgetArchiveRows {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string[]]$BranchCodes
  )

  $values = ($BranchCodes | ForEach-Object { "<value>$_</value>" }) -join ""
  $fetch = @"
<fetch count='5000'>
  <entity name='qfu_budgetarchive'>
    <attribute name='qfu_budgetarchiveid' />
    <attribute name='qfu_name' />
    <attribute name='qfu_sourceid' />
    <attribute name='qfu_branchcode' />
    <attribute name='qfu_branchslug' />
    <attribute name='qfu_regionslug' />
    <attribute name='qfu_month' />
    <attribute name='qfu_monthname' />
    <attribute name='qfu_year' />
    <attribute name='qfu_fiscalyear' />
    <attribute name='qfu_budgetgoal' />
    <attribute name='qfu_actualsales' />
    <attribute name='qfu_sourcefamily' />
    <attribute name='qfu_lastupdated' />
    <attribute name='createdon' />
    <attribute name='modifiedon' />
    <filter type='and'>
      <condition attribute='qfu_branchcode' operator='in'>
$values
      </condition>
    </filter>
  </entity>
</fetch>
"@

  return @((Get-CrmRecordsByFetch -conn $Connection -Fetch $fetch).CrmRecords)
}

function Measure-Coverage {
  param(
    [object[]]$Rows,
    [string]$TargetFiscalYear
  )

  $branchSummaries = @()
  foreach ($branchCode in ($BranchMap.Keys | Sort-Object)) {
    $branchRows = @($Rows | Where-Object { [string]$_.qfu_branchcode -eq $branchCode })
    $monthIndex = @{}
    foreach ($row in $branchRows) {
      $rowMonth = ConvertTo-IntOrZero -Value $row.qfu_month
      $rowYear = ConvertTo-IntOrZero -Value $row.qfu_year
      $rowFiscalYear = [string]$row.qfu_fiscalyear
      if (-not $rowMonth) {
        continue
      }
      if (-not [string]::IsNullOrWhiteSpace($rowFiscalYear) -and $rowFiscalYear -ne $TargetFiscalYear) {
        continue
      }
      if ($rowYear -and $rowYear -ne 2026) {
        continue
      }
      $monthIndex[$rowMonth] = $true
    }

    $totalTarget = @($Rows | Where-Object {
      [string]$_.qfu_branchcode -eq $branchCode -and
      (ConvertTo-IntOrZero -Value $_.qfu_year) -eq 2026 -and
      (ConvertTo-IntOrZero -Value $_.qfu_month) -in $FiscalMonths.number
    } | Group-Object { ConvertTo-IntOrZero -Value $_.qfu_month } | ForEach-Object {
      $meta = $BranchMap[$branchCode]
      $winner = Select-CanonicalArchiveRow -Rows $_.Group -BranchCode $branchCode -BranchSlug $meta.branch_slug -RegionSlug $meta.region_slug -MonthNumber ([int]$_.Name) -YearNumber 2026 -TargetFiscalYear $TargetFiscalYear
      ConvertTo-DecimalOrNull -Value $winner.qfu_budgetgoal
    } | Measure-Object -Sum).Sum

    $missingMonths = @($FiscalMonths | Where-Object { -not $monthIndex.ContainsKey($_.number) } | ForEach-Object { $_.short })
    $branchSummaries += [pscustomobject]@{
      branch_code = $branchCode
      coverage_count = $monthIndex.Count
      missing_months = $missingMonths
      fy_target = if ($totalTarget) { [decimal]$totalTarget } else { 0 }
    }
  }

  return $branchSummaries
}

$snapshotPath = Resolve-RepoPath -Path $SnapshotJson
$historicalActualsPath = Resolve-RepoPath -Path $HistoricalActualsJson
$outputJsonPath = Resolve-RepoPath -Path $OutputJson
$outputMarkdownPath = Resolve-RepoPath -Path $OutputMarkdown

$snapshotRows = Parse-BudgetSnapshot -Path $snapshotPath
$actualSalesMap = Parse-HistoricalActuals -Path $historicalActualsPath
$connection = Connect-Org -Url $TargetEnvironmentUrl
$existingRows = Get-LiveBudgetArchiveRows -Connection $connection -BranchCodes $BranchMap.Keys
$beforeCoverage = Measure-Coverage -Rows $existingRows -TargetFiscalYear $FiscalYear
$captureTime = Get-Date
$actions = @()
$duplicates = @()

foreach ($snapshotRow in $snapshotRows) {
  $branchMeta = $BranchMap[[string]$snapshotRow.branch_code]
  if (-not $branchMeta) {
    continue
  }

  $branchRows = @($existingRows | Where-Object {
    [string]$_.qfu_branchcode -eq $snapshotRow.branch_code -and
    (ConvertTo-IntOrZero -Value $_.qfu_month) -eq [int]$snapshotRow.month -and
    (ConvertTo-IntOrZero -Value $_.qfu_year) -eq [int]$snapshotRow.year
  })
  if ($branchRows.Count -gt 1) {
    $duplicates += [pscustomobject]@{
      branch_code = $snapshotRow.branch_code
      month = [int]$snapshotRow.month
      year = [int]$snapshotRow.year
      count = $branchRows.Count
      row_ids = @($branchRows | ForEach-Object { [string]$_.qfu_budgetarchiveid })
    }
  }

  $canonical = Select-CanonicalArchiveRow `
    -Rows $branchRows `
    -BranchCode $snapshotRow.branch_code `
    -BranchSlug $branchMeta.branch_slug `
    -RegionSlug $branchMeta.region_slug `
    -MonthNumber ([int]$snapshotRow.month) `
    -YearNumber ([int]$snapshotRow.year) `
    -TargetFiscalYear $FiscalYear

  $actualKey = "{0}|{1}" -f $snapshotRow.branch_code, [int]$snapshotRow.month
  $existingActualSales = if ($canonical) { $canonical.qfu_actualsales } else { $null }
  $actualSales = if ($actualSalesMap.ContainsKey($actualKey)) { [decimal]$actualSalesMap[$actualKey] } else { ConvertTo-DecimalOrNull -Value $existingActualSales }
  $canonicalSourceId = Canonical-BudgetArchiveSourceId -BranchCode $snapshotRow.branch_code -TargetFiscalYear $FiscalYear -MonthNumber ([int]$snapshotRow.month)
  $fields = @{
    qfu_name = "{0} {1} {2} Budget Archive" -f $snapshotRow.branch_code, $snapshotRow.month_name, $snapshotRow.year
    qfu_sourceid = $canonicalSourceId
    qfu_budgetgoal = [decimal]$snapshotRow.budget_goal
    qfu_month = [int]$snapshotRow.month
    qfu_monthname = [string]$snapshotRow.month_name
    qfu_year = [int]$snapshotRow.year
    qfu_fiscalyear = [string]$FiscalYear
    qfu_lastupdated = $captureTime
    qfu_branchcode = [string]$snapshotRow.branch_code
    qfu_branchslug = [string]$branchMeta.branch_slug
    qfu_regionslug = [string]$branchMeta.region_slug
    qfu_sourcefamily = "SA1300"
  }
  if ($null -ne $actualSales) {
    $fields.qfu_actualsales = [decimal]$actualSales
  }

  $status = if ($canonical) { "update" } else { "create" }
  if ($Apply) {
    if ($canonical) {
      Set-CrmRecord -conn $connection -EntityLogicalName "qfu_budgetarchive" -Id $canonical.qfu_budgetarchiveid -Fields $fields | Out-Null
    } else {
      $newId = New-CrmRecord -conn $connection -EntityLogicalName "qfu_budgetarchive" -Fields $fields
      $canonical = [pscustomobject]@{ qfu_budgetarchiveid = $newId }
    }
  }

  $actions += [pscustomobject]@{
    branch_code = $snapshotRow.branch_code
    month = [int]$snapshotRow.month
    month_name = [string]$snapshotRow.month_name
    year = [int]$snapshotRow.year
    fiscal_year = $FiscalYear
    budget_goal = [decimal]$snapshotRow.budget_goal
    actual_sales = $actualSales
    action = $status
    target_row_id = if ($canonical) { [string]$canonical.qfu_budgetarchiveid } else { "" }
    source_id = $canonicalSourceId
  }
}

$afterRows = if ($Apply) {
  Get-LiveBudgetArchiveRows -Connection $connection -BranchCodes $BranchMap.Keys
} else {
  $existingRows
}
$afterCoverage = Measure-Coverage -Rows $afterRows -TargetFiscalYear $FiscalYear
$beforeFyTarget = @($beforeCoverage | Measure-Object -Property fy_target -Sum).Sum
$afterFyTarget = @($afterCoverage | Measure-Object -Property fy_target -Sum).Sum

$result = [ordered]@{
  generated_at = $captureTime.ToString("o")
  target_environment = $TargetEnvironmentUrl
  fiscal_year = $FiscalYear
  apply = [bool]$Apply
  snapshot_json = $snapshotPath
  historical_actuals_json = $historicalActualsPath
  rows_expected = $snapshotRows.Count
  rows_planned_or_applied = $actions.Count
  duplicate_groups_found = $duplicates.Count
  duplicates = $duplicates
  before = [ordered]@{
    regional_fy_target = if ($beforeFyTarget) { [decimal]$beforeFyTarget } else { 0 }
    branches = $beforeCoverage
  }
  after = [ordered]@{
    regional_fy_target = if ($afterFyTarget) { [decimal]$afterFyTarget } else { 0 }
    branches = $afterCoverage
  }
  actions = $actions
}

$markdown = @()
$markdown += "# FY26 Budget Archive Repair"
$markdown += ""
$markdown += "- Generated: $($result.generated_at)"
$markdown += "- Environment: ``$TargetEnvironmentUrl``"
$markdown += "- Fiscal year: ``$FiscalYear``"
$markdown += "- Mode: " + ($(if ($Apply) { "apply" } else { "dry-run" }))
$markdown += "- Snapshot source: ``$snapshotPath``"
$markdown += "- Historical actuals source: ``$historicalActualsPath``"
$markdown += "- Planned/applied rows: $($actions.Count)"
$markdown += "- Duplicate month groups found: $($duplicates.Count)"
$markdown += ""
$markdown += "## Before"
$markdown += ""
$markdown += "| Branch | Coverage | Missing Months | FY Target |"
$markdown += "| --- | --- | --- | --- |"
foreach ($branch in $beforeCoverage) {
  $markdown += "| $($branch.branch_code) | $($branch.coverage_count)/12 | " + ($(if ($branch.missing_months.Count) { $branch.missing_months -join ", " } else { "None" })) + " | $(Format-Currency $branch.fy_target) |"
}
$markdown += ""
$markdown += "- Regional FY target: $(Format-Currency $beforeFyTarget)"
$markdown += ""
$markdown += "## After"
$markdown += ""
$markdown += "| Branch | Coverage | Missing Months | FY Target |"
$markdown += "| --- | --- | --- | --- |"
foreach ($branch in $afterCoverage) {
  $markdown += "| $($branch.branch_code) | $($branch.coverage_count)/12 | " + ($(if ($branch.missing_months.Count) { $branch.missing_months -join ", " } else { "None" })) + " | $(Format-Currency $branch.fy_target) |"
}
$markdown += ""
$markdown += "- Regional FY target: $(Format-Currency $afterFyTarget)"
$markdown += ""
$markdown += "## Actions"
$markdown += ""
$markdown += "| Branch | Month | Action | Budget Goal | Actual Sales | Source Id |"
$markdown += "| --- | --- | --- | --- | --- | --- |"
foreach ($action in $actions) {
  $markdown += "| $($action.branch_code) | $($action.month_name) $($action.year) | $($action.action) | $(Format-Currency $action.budget_goal) | $(Format-Currency $action.actual_sales) | ``$($action.source_id)`` |"
}

Write-Utf8Json -Path $OutputJson -Object $result
Write-Utf8File -Path $OutputMarkdown -Content ($markdown -join [Environment]::NewLine)
Write-Output ("JSON_PATH=" + $outputJsonPath)
Write-Output ("MARKDOWN_PATH=" + $outputMarkdownPath)
