param(
  [string]$TargetEnvironmentUrl = "<URL>
  [string]$Username = "<EMAIL>",
  [string[]]$BranchCodes = @("4171", "4172", "4173"),
  [string]$OutputPath = "",
  [string]$JsonOutputPath = ""
)

$ErrorActionPreference = "Stop"

Import-Module Microsoft.Xrm.Data.Powershell

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

  $directory = Split-Path -Parent $Path
  if ($directory) {
    Ensure-Directory -Path $directory
  }

  [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
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

  [System.IO.File]::WriteAllText($Path, ($Object | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
}

function Connect-Target {
  param(
    [string]$Url,
    [string]$User
  )

  $conn = Connect-CrmOnline -ServerUrl $Url -ForceOAuth -Username $User
  if (-not $conn -or -not $conn.IsReady) {
    throw "Dataverse connection failed for $Url : $($conn.LastCrmError)"
  }

  return $conn
}

function Get-DateValue {
  param([object]$Value)

  if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
    return $null
  }

  try {
    return [datetime]$Value
  } catch {
    return $null
  }
}

function Get-BoolValue {
  param([object]$Value)

  if ($null -eq $Value) {
    return $null
  }

  if ($Value -is [bool]) {
    return [bool]$Value
  }

  $text = ([string]$Value).Trim().ToLowerInvariant()
  switch ($text) {
    "true" { return $true }
    "false" { return $false }
    "yes" { return $true }
    "no" { return $false }
    "1" { return $true }
    "0" { return $false }
    default { return $null }
  }
}

function Test-BudgetRowIsActive {
  param([object]$Row)

  $value = if ($Row.PSObject.Properties["qfu_isactive"]) { $Row.qfu_isactive } else { $null }
  $boolValue = Get-BoolValue -Value $value
  if ($null -ne $boolValue) {
    return (-not $boolValue)
  }

  return $false
}

function Get-ActiveFiscalYear {
  param([datetime]$ReferenceDate)

  $yearNumber = if ($ReferenceDate.Month -ge 7) { $ReferenceDate.Year + 1 } else { $ReferenceDate.Year }
  return "FY{0}" -f $yearNumber.ToString().Substring(2, 2)
}

function Get-LatestBillingDayFromJson {
  param([string]$JsonText)

  if ([string]::IsNullOrWhiteSpace($JsonText)) {
    return $null
  }

  $billingValues = New-Object System.Collections.Generic.List[string]
  foreach ($pattern in @('"Billing Day"\s*:\s*"([^"]+)"', '"billing_day"\s*:\s*"([^"]+)"', '"BillingDay"\s*:\s*"([^"]+)"')) {
    foreach ($match in [regex]::Matches($JsonText, $pattern)) {
      $billingValues.Add($match.Groups[1].Value) | Out-Null
    }
  }

  $latest = $null
  foreach ($billingValue in $billingValues) {
    $billingDate = Get-DateValue $billingValue
    if (-not $billingDate -and -not [string]::IsNullOrWhiteSpace([string]$billingValue)) {
      $number = 0.0
      if ([double]::TryParse([string]$billingValue, [ref]$number) -and $number -gt 30000) {
        $billingDate = [datetime]::FromOADate($number)
      }
    }
    if ($billingDate -and ($null -eq $latest -or $billingDate -gt $latest)) {
      $latest = $billingDate
    }
  }

  return $latest
}

function Get-JsonRowCount {
  param([string]$JsonText)

  if ([string]::IsNullOrWhiteSpace($JsonText)) {
    return 0
  }

  return [regex]::Matches($JsonText, '"Billing Day"\s*:\s*"([^"]+)"|"billing_day"\s*:\s*"([^"]+)"|"BillingDay"\s*:\s*"([^"]+)"').Count
}

function Select-CurrentBudgetRow {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$BranchCode
  )

  $now = Get-Date
  $sourceId = "{0}|SA1300|{1}-{2}" -f $BranchCode, ('{0:d4}' -f $now.Year), ('{0:d2}' -f $now.Month)
  $fiscalYear = Get-ActiveFiscalYear -ReferenceDate $now

  $rows = @(
    (Get-CrmRecords -conn $Connection -EntityLogicalName "qfu_budget" -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $BranchCode -Fields @(
        "qfu_budgetid",
        "qfu_sourceid",
        "qfu_fiscalyear",
        "qfu_isactive",
        "qfu_lastupdated",
        "qfu_opsdailycadjson",
        "qfu_opsdailyusdjson",
        "createdon",
        "modifiedon"
      ) -TopCount 100
    ).CrmRecords
  )

  $currentRows = @(
    $rows |
      Where-Object {
        [string]$_.qfu_sourceid -eq $sourceId -and
        (
          [string]::IsNullOrWhiteSpace([string]$_.qfu_fiscalyear) -or
          [string]$_.qfu_fiscalyear -eq $fiscalYear
        )
      } |
      Sort-Object modifiedon, createdon -Descending
  )

  if ($currentRows.Count -gt 0) {
    return $currentRows[0]
  }

  return @(
    $rows |
      Sort-Object modifiedon, createdon -Descending
  ) | Select-Object -First 1
}

function Get-LatestSa1300Batch {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$BranchCode
  )

  return @(
    (Get-CrmRecords -conn $Connection -EntityLogicalName "qfu_ingestionbatch" -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $BranchCode -Fields @(
        "qfu_ingestionbatchid",
        "qfu_sourcefamily",
        "qfu_sourcefilename",
        "qfu_status",
        "qfu_startedon",
        "qfu_completedon",
        "createdon"
      ) -TopCount 5000
    ).CrmRecords |
      Where-Object { [string]$_.qfu_sourcefamily -eq "SA1300" } |
      Sort-Object createdon -Descending
  ) | Select-Object -First 1
}

function Get-LatestOpsDailyRow {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$BranchCode
  )

  return @(
    (Get-CrmRecords -conn $Connection -EntityLogicalName "qfu_branchopsdaily" -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $BranchCode -Fields @(
        "qfu_branchopsdailyid",
        "qfu_snapshotdate",
        "qfu_billingday",
        "qfu_billinglabel",
        "qfu_currencytype",
        "modifiedon",
        "createdon"
      ) -TopCount 1000
    ).CrmRecords |
      Where-Object { Get-DateValue $_.qfu_billingday } |
      Sort-Object qfu_billingday, modifiedon -Descending
  ) | Select-Object -First 1
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path (Get-Location) "VERIFICATION\sa1300-opsdaily-freshness.md"
}

if ([string]::IsNullOrWhiteSpace($JsonOutputPath)) {
  $JsonOutputPath = Join-Path (Get-Location) "results\sa1300-opsdaily-freshness.json"
}

$connection = Connect-Target -Url $TargetEnvironmentUrl -User $Username
$rows = New-Object System.Collections.Generic.List[object]

foreach ($branchCode in $BranchCodes) {
  $batch = Get-LatestSa1300Batch -Connection $connection -BranchCode $branchCode
  $budget = Select-CurrentBudgetRow -Connection $connection -BranchCode $branchCode
  $latestBranchOps = Get-LatestOpsDailyRow -Connection $connection -BranchCode $branchCode

  $cadLatest = if ($budget) { Get-LatestBillingDayFromJson -JsonText ([string]$budget.qfu_opsdailycadjson) } else { $null }
  $usdLatest = if ($budget) { Get-LatestBillingDayFromJson -JsonText ([string]$budget.qfu_opsdailyusdjson) } else { $null }
  $payloadLatest = @($cadLatest, $usdLatest | Where-Object { $_ }) | Sort-Object -Descending | Select-Object -First 1
  $branchOpsLatest = if ($latestBranchOps) { Get-DateValue $latestBranchOps.qfu_billingday } else { $null }
  $batchCompleted = if ($batch) { Get-DateValue $batch.qfu_completedon } else { $null }
  $lagDays = if ($batchCompleted -and $payloadLatest) { ($batchCompleted.Date - $payloadLatest.Date).Days } else { $null }

  $status = "ok"
  $note = "Live SA1300 budget payload and qfu_branchopsdaily rows agree."
  if (-not $budget) {
    $status = "missing-budget-row"
    $note = "No active current-month SA1300 qfu_budget row was found."
  } elseif (-not $payloadLatest -and -not $branchOpsLatest) {
    $status = "missing-opsdaily"
    $note = "Current SA1300 budget row has no ops payload and qfu_branchopsdaily has no dated rows."
  } elseif ($payloadLatest -and $branchOpsLatest -and $payloadLatest.Date -ne $branchOpsLatest.Date) {
    $status = "budget-payload-drift"
    $note = "Current qfu_budget ops payload date does not match the latest qfu_branchopsdaily billing day."
  } elseif (-not $payloadLatest -and $branchOpsLatest) {
    $status = "missing-budget-payload"
    $note = "qfu_branchopsdaily has rows, but the current qfu_budget payload is empty."
  } elseif ($lagDays -ne $null -and $lagDays -gt 1) {
    $status = "stale-upstream-or-replay"
    $note = "The live SA1300 payload is internally consistent, but the latest billing day trails the latest completed SA1300 batch by more than one day."
  }

  $rows.Add([pscustomobject]@{
      branch_code = $branchCode
      status = $status
      note = $note
      latest_batch_completedon = if ($batchCompleted) { $batchCompleted.ToString("yyyy-MM-dd HH:mm:ss") } else { $null }
      latest_batch_file = if ($batch) { [string]$batch.qfu_sourcefilename } else { $null }
      budget_lastupdated = if ($budget) { (Get-DateValue $budget.qfu_lastupdated).ToString("yyyy-MM-dd HH:mm:ss") } else { $null }
      budget_payload_latest_billing_day = if ($payloadLatest) { $payloadLatest.ToString("yyyy-MM-dd") } else { $null }
      branchopsdaily_latest_billing_day = if ($branchOpsLatest) { $branchOpsLatest.ToString("yyyy-MM-dd") } else { $null }
      branchopsdaily_snapshotdate = if ($latestBranchOps) { (Get-DateValue $latestBranchOps.qfu_snapshotdate).ToString("yyyy-MM-dd") } else { $null }
      cad_payload_rows = if ($budget) { Get-JsonRowCount -JsonText ([string]$budget.qfu_opsdailycadjson) } else { 0 }
      usd_payload_rows = if ($budget) { Get-JsonRowCount -JsonText ([string]$budget.qfu_opsdailyusdjson) } else { 0 }
      billing_day_lag_days = $lagDays
    }) | Out-Null
}

$report = [pscustomobject]@{
  generated_at = (Get-Date).ToString("o")
  environment_url = $TargetEnvironmentUrl
  branches = @($rows.ToArray())
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# SA1300 Ops Daily Freshness") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("- Generated: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))") | Out-Null
$lines.Add("- Environment: $TargetEnvironmentUrl") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Branch | Status | Latest Batch | Budget Payload Day | Branch Ops Day | Lag Days | Note |") | Out-Null
$lines.Add("| --- | --- | --- | --- | --- | ---: | --- |") | Out-Null
foreach ($row in $rows) {
  $lines.Add("| $($row.branch_code) | $($row.status) | $($row.latest_batch_completedon) | $($row.budget_payload_latest_billing_day) | $($row.branchopsdaily_latest_billing_day) | $($row.billing_day_lag_days) | $($row.note) |") | Out-Null
}

Write-Utf8File -Path $OutputPath -Content ($lines -join [Environment]::NewLine)
Write-Utf8Json -Path $JsonOutputPath -Object $report

Write-Host "MARKDOWN_PATH=$OutputPath"
Write-Host "JSON_PATH=$JsonOutputPath"
