param(
  [string]$RepoRoot = "C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion",
  [string]$TargetEnvironmentUrl = "<URL>
  [string]$Username = "<EMAIL>",
  [string]$BudgetSnapshotJson = "results\tmp-budget-debug.json",
  [string]$HistoricalActualsJson = "results\gl060-history-actuals-seed.json",
  [string]$DashboardParserScript = "scripts\parse-southern-alberta-dashboard-spine.py",
  [string]$DashboardJson = "results\live-dashboard-repair\dashboard-spine-example.json",
  [string]$ExampleRoot = "example",
  [string]$OutputJson = "results\live-dashboard-repair\repair-summary.json"
)

$ErrorActionPreference = "Stop"

Import-Module Microsoft.Xrm.Data.Powershell

$branchMap = @{
  "4171" = [ordered]@{ branch_slug = "4171-calgary"; region_slug = "southern-alberta"; branch_name = "Calgary" }
  "4172" = [ordered]@{ branch_slug = "4172-lethbridge"; region_slug = "southern-alberta"; branch_name = "Lethbridge" }
  "4173" = [ordered]@{ branch_slug = "4173-medicine-hat"; region_slug = "southern-alberta"; branch_name = "Medicine Hat" }
}

function Ensure-Directory {
  param([string]$Path)

  if ($Path -and -not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Write-Utf8Json {
  param(
    [string]$Path,
    [object]$Object
  )

  $directory = Split-Path -Parent $Path
  if ($directory) {
    Ensure-Directory -Path $directory
  }

  $json = $Object | ConvertTo-Json -Depth 20
  [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Resolve-RepoPath {
  param([string]$Path)

  if ([System.IO.Path]::IsPathRooted($Path)) {
    return $Path
  }

  return Join-Path $RepoRoot $Path
}

function Connect-Org {
  param([string]$Url)

  $conn = Connect-CrmOnline -ServerUrl $Url -ForceOAuth -Username $Username
  if (-not $conn -or -not $conn.IsReady) {
    throw "Dataverse connection failed for $Url : $($conn.LastCrmError)"
  }

  return $conn
}

function ConvertTo-Decimal {
  param($Value)

  if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
    return $null
  }

  $text = [string]$Value
  $cleaned = $text -replace "[^0-9\.\-]", ""
  if ([string]::IsNullOrWhiteSpace($cleaned)) {
    return $null
  }

  return [decimal]::Parse($cleaned, [System.Globalization.CultureInfo]::InvariantCulture)
}

function ConvertTo-Int {
  param($Value)

  if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
    return $null
  }

  $text = ([string]$Value) -replace "[^0-9\-]", ""
  if ([string]::IsNullOrWhiteSpace($text)) {
    return $null
  }

  return [int]$text
}

function Test-BudgetRowIsActive {
  param([object]$Row)

  $value = if ($Row.PSObject.Properties['qfu_isactive']) { $Row.qfu_isactive } else { $null }
  if ($value -is [bool]) {
    return (-not $value)
  }

  # Current portal/Web API evidence shows formatted "Yes" on rows where raw qfu_isactive = false.
  # Treat raw false as authoritative and only fall back to this custom label mapping when bools are unavailable.
  $label = if ($null -eq $value) { "" } else { ([string]$value).Trim().ToLowerInvariant() }
  switch ($label) {
    "yes" { return $true }
    "false" { return $true }
    "no" { return $false }
    "true" { return $false }
    default { return $false }
  }
}

function Convert-RecordToFields {
  param([object]$Record)

  $fields = @{}
  foreach ($property in $Record.PSObject.Properties) {
    $value = $property.Value
    if (
      $null -ne $value -and
      $property.Name -in @("qfu_snapshotdate", "qfu_billingdate", "qfu_startedon", "qfu_completedon")
    ) {
      $value = [datetime]$value
    }
    $fields[$property.Name] = $value
  }
  return $fields
}

function Parse-BudgetArchiveSnapshot {
  param([string]$Path)

  $payload = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  $records = @()

  foreach ($branchPayload in @($payload)) {
    $branchCode = [string]$branchPayload.branch
    foreach ($row in @($branchPayload.archives)) {
      $monthNumber = ConvertTo-Int $row.qfu_month
      $yearNumber = ConvertTo-Int $row.qfu_year
      $budgetGoal = ConvertTo-Decimal $row.qfu_budgetgoal
      $monthName = [string]$row.qfu_monthname
      $fiscalYear = [string]$row.qfu_fiscalyear

      if (-not $monthNumber -or -not $yearNumber -or $null -eq $budgetGoal) {
        continue
      }

      $records += [pscustomobject]@{
        branch_code = $branchCode
        month = $monthNumber
        month_name = $monthName
        year = $yearNumber
        fiscal_year = $fiscalYear
        budget_goal = $budgetGoal
      }
    }
  }

  return $records
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

function Ensure-ParsedDashboardData {
  param(
    [string]$ParserPath,
    [string]$ExampleRootPath,
    [string]$OutputPath
  )

  $python = Get-Command python -ErrorAction SilentlyContinue
  if (-not $python) {
    throw "python is required to parse the dashboard example files."
  }

  Ensure-Directory (Split-Path -Parent $OutputPath)
  & $python.Source $ParserPath --example-root $ExampleRootPath --sa1300-root $ExampleRootPath --gl060-root $ExampleRootPath --output $OutputPath
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $OutputPath)) {
    throw "Failed to generate dashboard repair JSON: $OutputPath"
  }
}

function Upsert-BySourceId {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$EntityLogicalName,
    [object[]]$Records
  )

  $idFieldName = "{0}id" -f $EntityLogicalName
  $created = 0
  $updated = 0

  foreach ($record in @($Records)) {
    $fields = Convert-RecordToFields -Record $record
    $existing = @((Get-CrmRecords -conn $Connection -EntityLogicalName $EntityLogicalName -FilterAttribute "qfu_sourceid" -FilterOperator eq -FilterValue $record.qfu_sourceid -Fields @($idFieldName) -TopCount 1).CrmRecords) | Select-Object -First 1
    if ($existing) {
      Set-CrmRecord -conn $Connection -EntityLogicalName $EntityLogicalName -Id $existing.$idFieldName -Fields $fields | Out-Null
      $updated += 1
    } else {
      New-CrmRecord -conn $Connection -EntityLogicalName $EntityLogicalName -Fields $fields | Out-Null
      $created += 1
    }
  }

  return [ordered]@{
    count = @($Records).Count
    created = $created
    updated = $updated
  }
}

function Sync-BudgetArchives {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [object[]]$BudgetSnapshotRows,
    [hashtable]$ActualSalesMap
  )

  $created = 0
  $updated = 0
  $rows = @()
  $capturedAt = Get-Date

  foreach ($record in @($BudgetSnapshotRows | Sort-Object branch_code, year, month)) {
    $branchMeta = $branchMap[[string]$record.branch_code]
    if (-not $branchMeta) {
      continue
    }

    $sourceId = "{0}|budgettarget|{1}-{2}" -f $record.branch_code, ('{0:d4}' -f [int]$record.year), ('{0:d2}' -f [int]$record.month)
    $actualKey = "{0}|{1}" -f $record.branch_code, [int]$record.month
    $actualSales = if ($ActualSalesMap.ContainsKey($actualKey)) { [decimal]$ActualSalesMap[$actualKey] } else { $null }

    $fields = @{
      qfu_name = "{0} {1} {2} Budget Target" -f $record.branch_code, $record.month_name, $record.year
      qfu_sourceid = $sourceId
      qfu_budgetgoal = [decimal]$record.budget_goal
      qfu_actualsales = $actualSales
      qfu_month = [int]$record.month
      qfu_monthname = [string]$record.month_name
      qfu_year = [int]$record.year
      qfu_fiscalyear = [string]$record.fiscal_year
      qfu_lastupdated = $capturedAt
      qfu_branchcode = [string]$record.branch_code
      qfu_branchslug = [string]$branchMeta.branch_slug
      qfu_regionslug = [string]$branchMeta.region_slug
      qfu_sourcefamily = "SA1300"
    }

    $existing = @((Get-CrmRecords -conn $Connection -EntityLogicalName "qfu_budgetarchive" -FilterAttribute "qfu_sourceid" -FilterOperator eq -FilterValue $sourceId -Fields @("qfu_budgetarchiveid") -TopCount 1).CrmRecords) | Select-Object -First 1
    if ($existing) {
      Set-CrmRecord -conn $Connection -EntityLogicalName "qfu_budgetarchive" -Id $existing.qfu_budgetarchiveid -Fields $fields | Out-Null
      $updated += 1
    } else {
      New-CrmRecord -conn $Connection -EntityLogicalName "qfu_budgetarchive" -Fields $fields | Out-Null
      $created += 1
    }

    $rows += [pscustomobject]@{
      branch_code = $record.branch_code
      source_id = $sourceId
      month = [int]$record.month
      month_name = $record.month_name
      year = [int]$record.year
      budget_goal = [decimal]$record.budget_goal
      actual_sales = $actualSales
      status = if ($existing) { "updated" } else { "created" }
    }
  }

  return [ordered]@{
    count = $rows.Count
    created = $created
    updated = $updated
    rows = $rows
  }
}

function Get-ActiveFiscalYear {
  param([datetime]$ReferenceDate)

  $yearNumber = if ($ReferenceDate.Month -ge 7) { $ReferenceDate.Year + 1 } else { $ReferenceDate.Year }
  return "FY{0}" -f $yearNumber.ToString().Substring(2, 2)
}

function Update-CurrentBudgetTargets {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [object[]]$BudgetSnapshotRows
  )

  $today = Get-Date
  $currentMonth = $today.Month
  $currentYear = $today.Year
  $currentFiscalYear = Get-ActiveFiscalYear -ReferenceDate $today
  $resultRows = @()
  $updated = 0

  foreach ($branchCode in ($branchMap.Keys | Sort-Object)) {
    $targetRow = @($BudgetSnapshotRows | Where-Object { [string]$_.branch_code -eq $branchCode -and [int]$_.month -eq $currentMonth -and [int]$_.year -eq $currentYear } | Select-Object -First 1)
    if (-not $targetRow) {
      continue
    }

    $budgetSourceId = "{0}|SA1300|{1}-{2}" -f $branchCode, ('{0:d4}' -f $currentYear), ('{0:d2}' -f $currentMonth)
    $rows = @(
      (Get-CrmRecords -conn $Connection -EntityLogicalName "qfu_budget" -FilterAttribute "qfu_sourceid" -FilterOperator eq -FilterValue $budgetSourceId -Fields @(
          "qfu_budgetid",
          "qfu_actualsales",
          "qfu_fiscalyear",
          "qfu_sourcefamily",
          "qfu_isactive",
          "createdon",
          "modifiedon"
        ) -TopCount 20
      ).CrmRecords |
        Sort-Object `
          @{ Expression = { if ([string]$_.qfu_fiscalyear -eq $currentFiscalYear) { 1 } else { 0 } }; Descending = $true }, `
          @{ Expression = { if ([string]$_.qfu_sourcefamily -eq "SA1300") { 1 } else { 0 } }; Descending = $true }, `
          @{ Expression = { if (Test-BudgetRowIsActive -Row $_) { 1 } else { 0 } }; Descending = $true }, `
          @{ Expression = { if ($_.modifiedon) { [datetime]$_.modifiedon } else { [datetime]::MinValue } }; Descending = $true }, `
          @{ Expression = { if ($_.createdon) { [datetime]$_.createdon } else { [datetime]::MinValue } }; Descending = $true }
    )
    if (-not $rows.Count) {
      continue
    }

    $canonicalRow = $rows | Select-Object -First 1
    $duplicateRows = @($rows | Select-Object -Skip 1)
    $actualSales = ConvertTo-Decimal $canonicalRow.qfu_actualsales
    $percentAchieved = if ($targetRow.budget_goal -gt 0 -and $null -ne $actualSales) { [math]::Round(([decimal]$actualSales / [decimal]$targetRow.budget_goal) * 100, 2) } else { 0 }

    Set-CrmRecord -conn $Connection -EntityLogicalName "qfu_budget" -Id $canonicalRow.qfu_budgetid -Fields @{
      qfu_budgetgoal = [decimal]$targetRow.budget_goal
      qfu_budgetname = "{0} {1} Budget" -f $targetRow.month_name, $currentYear
      qfu_monthname = [string]$targetRow.month_name
      qfu_month = [int]$currentMonth
      qfu_year = [int]$currentYear
      qfu_fiscalyear = $currentFiscalYear
      qfu_isactive = $false
      qfu_percentachieved = $percentAchieved
      qfu_lastupdated = $today
    } | Out-Null
    $updated += 1

    foreach ($row in $duplicateRows) {
      Set-CrmRecord -conn $Connection -EntityLogicalName "qfu_budget" -Id $row.qfu_budgetid -Fields @{
        qfu_isactive = $true
        qfu_lastupdated = $today
      } | Out-Null
      $updated += 1
    }

    $resultRows += [pscustomobject]@{
      branch_code = $branchCode
      canonical_budget_id = [string]$canonicalRow.qfu_budgetid
      deactivated_budget_ids = @($duplicateRows | ForEach-Object { [string]$_.qfu_budgetid })
      budget_goal = [decimal]$targetRow.budget_goal
      actual_sales = $actualSales
    }
  }

  return [ordered]@{
    updated = $updated
    rows = $resultRows
  }
}

$budgetSnapshotPath = Resolve-RepoPath -Path $BudgetSnapshotJson
$historicalActualsPath = Resolve-RepoPath -Path $HistoricalActualsJson
$dashboardParserPath = Resolve-RepoPath -Path $DashboardParserScript
$dashboardJsonPath = Resolve-RepoPath -Path $DashboardJson
$exampleRootPath = Resolve-RepoPath -Path $ExampleRoot
$outputPath = Resolve-RepoPath -Path $OutputJson

Ensure-ParsedDashboardData -ParserPath $dashboardParserPath -ExampleRootPath $exampleRootPath -OutputPath $dashboardJsonPath

$budgetSnapshotRows = Parse-BudgetArchiveSnapshot -Path $budgetSnapshotPath
$actualSalesMap = Parse-HistoricalActuals -Path $historicalActualsPath
$dashboardPayload = Get-Content -LiteralPath $dashboardJsonPath -Raw | ConvertFrom-Json

$marginRecords = @()
$lateOrderRecords = @()
$snapshotBatchRecords = @()
foreach ($branchPayload in @($dashboardPayload.branches)) {
  $marginRecords += @($branchPayload.abnormal_margin.records)
  $lateOrderRecords += @($branchPayload.late_orders.records)
  $snapshotBatchRecords += @(
    @($branchPayload.batches) |
      Where-Object { $_.qfu_sourcefamily -in @("SA1300-ABNORMALMARGIN", "SA1300-LATEORDER") }
  )
}

$connection = Connect-Org -Url $TargetEnvironmentUrl
$budgetArchiveResult = Sync-BudgetArchives -Connection $connection -BudgetSnapshotRows $budgetSnapshotRows -ActualSalesMap $actualSalesMap
$budgetCurrentResult = Update-CurrentBudgetTargets -Connection $connection -BudgetSnapshotRows $budgetSnapshotRows
$marginResult = Upsert-BySourceId -Connection $connection -EntityLogicalName "qfu_marginexception" -Records $marginRecords
$lateOrderResult = Upsert-BySourceId -Connection $connection -EntityLogicalName "qfu_lateorderexception" -Records $lateOrderRecords
$batchResult = Upsert-BySourceId -Connection $connection -EntityLogicalName "qfu_ingestionbatch" -Records $snapshotBatchRecords

$result = [ordered]@{
  target_environment = $TargetEnvironmentUrl
  repaired_at = (Get-Date).ToString("o")
  parsed_dashboard_json = $dashboardJsonPath
  budget_archive = $budgetArchiveResult
  current_budget_targets = $budgetCurrentResult
  abnormal_margin = $marginResult
  late_order = $lateOrderResult
  ingestion_batches = $batchResult
}

Write-Utf8Json -Path $outputPath -Object $result
Write-Output ($result | ConvertTo-Json -Depth 10)
