param(
  [string]$RepoRoot = "C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion",
  [string]$TargetEnvironmentUrl = "https://regionaloperationshub.crm.dynamics.com",
  [string]$Username = "smcfarlane@applied.com",
  [string[]]$BranchCodes = @("4171", "4172", "4173"),
  [string]$OutputJson = "results\live-refresh-20260407-074015\sa1300-budget-normalization-summary.json"
)

$ErrorActionPreference = "Stop"

Import-Module Microsoft.Xrm.Data.Powershell

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

function Get-ActiveFiscalYear {
  param([datetime]$ReferenceDate)

  $yearNumber = if ($ReferenceDate.Month -ge 7) { $ReferenceDate.Year + 1 } else { $ReferenceDate.Year }
  return "FY{0}" -f $yearNumber.ToString().Substring(2, 2)
}

function Get-PreviousFiscalYear {
  param([datetime]$ReferenceDate)

  $active = Get-ActiveFiscalYear -ReferenceDate $ReferenceDate
  $yearSuffix = [int]$active.Substring(2, 2)
  $previousYearSuffix = if ($yearSuffix -le 0) { 99 } else { $yearSuffix - 1 }
  return "FY{0}" -f $previousYearSuffix.ToString("00")
}

function Get-RetiredBudgetSourceId {
  param(
    [string]$CurrentSourceId,
    [string]$BudgetId
  )

  $suffix = if ([string]::IsNullOrWhiteSpace($BudgetId)) { [guid]::NewGuid().Guid.Substring(0, 8) } else { $BudgetId.Substring(0, 8) }
  return "{0}|retired|{1}" -f $CurrentSourceId, $suffix
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

function Sort-BudgetRows {
  param(
    [object[]]$Rows,
    [string]$ExpectedFiscalYear
  )

  return @(
    $Rows |
      Sort-Object `
        @{ Expression = { if ([string]$_.qfu_fiscalyear -eq $ExpectedFiscalYear) { 1 } else { 0 } }; Descending = $true }, `
        @{ Expression = { if ([string]$_.qfu_sourcefamily -eq "SA1300") { 1 } else { 0 } }; Descending = $true }, `
        @{ Expression = { if (Test-BudgetRowIsActive -Row $_) { 1 } else { 0 } }; Descending = $true }, `
        @{ Expression = { if ($_.modifiedon) { [datetime]$_.modifiedon } else { [datetime]::MinValue } }; Descending = $true }, `
        @{ Expression = { if ($_.createdon) { [datetime]$_.createdon } else { [datetime]::MinValue } }; Descending = $true }
  )
}

$now = Get-Date
$currentMonth = $now.Month
$currentYear = $now.Year
$currentMonthName = $now.ToString("MMMM")
$currentFiscalYear = Get-ActiveFiscalYear -ReferenceDate $now
$previousFiscalYear = Get-PreviousFiscalYear -ReferenceDate $now
$connection = Connect-Org -Url $TargetEnvironmentUrl

$summaryRows = @()

foreach ($branchCode in @($BranchCodes | Sort-Object -Unique)) {
  $sourceId = "{0}|SA1300|{1}-{2}" -f $branchCode, ('{0:d4}' -f $currentYear), ('{0:d2}' -f $currentMonth)
  $currentRows = @(
    (Get-CrmRecords -conn $connection -EntityLogicalName "qfu_budget" -FilterAttribute "qfu_sourceid" -FilterOperator eq -FilterValue $sourceId -Fields @(
        "qfu_budgetid",
        "qfu_name",
        "qfu_sourceid",
        "qfu_branchcode",
        "qfu_branchslug",
        "qfu_regionslug",
        "qfu_month",
        "qfu_monthname",
        "qfu_year",
        "qfu_fiscalyear",
        "qfu_actualsales",
        "qfu_budgetgoal",
        "qfu_sourcefamily",
        "qfu_sourcefile",
        "qfu_cadsales",
        "qfu_usdsales",
        "qfu_isactive",
        "qfu_lastupdated",
        "createdon",
        "modifiedon"
      ) -TopCount 20
    ).CrmRecords
  )

  if ($currentRows.Count -eq 0) {
    $summaryRows += [pscustomobject]@{
      branch_code = $branchCode
      source_id = $sourceId
      status = "missing"
      canonical_budget_id = $null
      retired_budget_ids = @()
    }
    continue
  }

  $sortedRows = Sort-BudgetRows -Rows $currentRows -ExpectedFiscalYear $currentFiscalYear
  $canonicalRow = $sortedRows | Select-Object -First 1
  $duplicateRows = @($sortedRows | Select-Object -Skip 1)
  $canonicalActual = if ($null -eq $canonicalRow.qfu_actualsales -or [string]::IsNullOrWhiteSpace([string]$canonicalRow.qfu_actualsales)) { 0 } else { [decimal]$canonicalRow.qfu_actualsales }
  $canonicalGoal = if ($null -eq $canonicalRow.qfu_budgetgoal -or [string]::IsNullOrWhiteSpace([string]$canonicalRow.qfu_budgetgoal)) { 0 } else { [decimal]$canonicalRow.qfu_budgetgoal }
  $percentAchieved = if ($canonicalGoal -gt 0) { [math]::Round(($canonicalActual / $canonicalGoal) * 100, 2) } else { 0 }

  Set-CrmRecord -conn $connection -EntityLogicalName "qfu_budget" -Id $canonicalRow.qfu_budgetid -Fields @{
    qfu_isactive = $false
    qfu_fiscalyear = $currentFiscalYear
    qfu_sourcefamily = "SA1300"
    qfu_sourceid = $sourceId
    qfu_month = $currentMonth
    qfu_monthname = $currentMonthName
    qfu_year = $currentYear
    qfu_percentachieved = $percentAchieved
    qfu_lastupdated = $now
  } | Out-Null

  $otherActiveRows = @(
    (Get-CrmRecords -conn $connection -EntityLogicalName "qfu_budget" -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $branchCode -Fields @(
        "qfu_budgetid",
        "qfu_sourceid",
        "qfu_fiscalyear",
        "qfu_isactive",
        "qfu_sourcefamily"
      ) -TopCount 50
    ).CrmRecords |
      Where-Object {
        [string]$_.qfu_sourcefamily -eq "SA1300" -and
        (Test-BudgetRowIsActive -Row $_) -and
        [string]$_.qfu_budgetid -ne [string]$canonicalRow.qfu_budgetid
      }
  )

  $rowsToRetire = @(
    $duplicateRows + $otherActiveRows |
      Group-Object { [string]$_.qfu_budgetid } |
      ForEach-Object { $_.Group | Select-Object -First 1 }
  )

  foreach ($row in $rowsToRetire) {
    $retireFields = @{
      qfu_isactive = $true
      qfu_lastupdated = $now
    }

    if ([string]$row.qfu_sourceid -eq $sourceId) {
      $retireFields.qfu_sourceid = Get-RetiredBudgetSourceId -CurrentSourceId $sourceId -BudgetId ([string]$row.qfu_budgetid)
    }

    if ([string]::IsNullOrWhiteSpace([string]$row.qfu_fiscalyear) -or [string]$row.qfu_fiscalyear -eq $currentFiscalYear) {
      $retireFields.qfu_fiscalyear = $previousFiscalYear
    }

    Set-CrmRecord -conn $connection -EntityLogicalName "qfu_budget" -Id $row.qfu_budgetid -Fields $retireFields | Out-Null
  }

  $summaryRows += [pscustomobject]@{
    branch_code = $branchCode
    source_id = $sourceId
    status = "normalized"
    canonical_budget_id = [string]$canonicalRow.qfu_budgetid
    canonical_actual_sales = $canonicalActual
    canonical_budget_goal = $canonicalGoal
    canonical_fiscal_year = $currentFiscalYear
    retired_budget_ids = @($rowsToRetire | ForEach-Object { [string]$_.qfu_budgetid } | Sort-Object -Unique)
  }
}

$report = [pscustomobject]@{
  normalized_at = (Get-Date).ToString("o")
  target_environment_url = $TargetEnvironmentUrl
  current_month = $currentMonth
  current_year = $currentYear
  current_fiscal_year = $currentFiscalYear
  branches = $summaryRows
}

$outputPath = Resolve-RepoPath -Path $OutputJson
Write-Utf8Json -Path $outputPath -Object $report

$summaryRows | Select-Object branch_code,status,canonical_budget_id,canonical_actual_sales,canonical_budget_goal | Format-Table -AutoSize
Write-Host "OUTPUT_PATH=$outputPath"
