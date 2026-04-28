param(
  [string]$TargetEnvironmentUrl = "<URL>
  [string]$Username = "<EMAIL>",
  [string[]]$BranchCodes = @("4171", "4172", "4173"),
  [switch]$Apply,
  [string]$OutputJson = "results\\live-backorder-overdue-day-repair.json",
  [string]$OutputMarkdown = "VERIFICATION\\backorder-overdue-day-repair.md"
)

$ErrorActionPreference = "Stop"

Import-Module Microsoft.Xrm.Data.Powershell

function Resolve-RepoPath {
  param([string]$Path)

  if ([System.IO.Path]::IsPathRooted($Path)) {
    return $Path
  }

  return Join-Path (Get-Location) $Path
}

function Ensure-Directory {
  param([string]$Path)

  if (-not [string]::IsNullOrWhiteSpace($Path) -and -not (Test-Path -LiteralPath $Path)) {
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

  [System.IO.File]::WriteAllText($Path, ($Object | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
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

  if ($null -eq $Value) {
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
  if ($text -in @("true", "1", "yes")) {
    return $true
  }
  if ($text -in @("false", "0", "no")) {
    return $false
  }

  return $null
}

function Get-IntegerValue {
  param([object]$Value)

  if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
    return 0
  }

  try {
    return [int]$Value
  } catch {
    return 0
  }
}

function Get-DecimalValue {
  param([object]$Value)

  if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
    return [decimal]0
  }

  try {
    return [decimal]$Value
  } catch {
    return [decimal]0
  }
}

function Days-Between {
  param(
    [datetime]$Later,
    [datetime]$Earlier
  )

  return [math]::Max(0, [int][math]::Floor(($Later.Date - $Earlier.Date).TotalDays))
}

function Test-OperationalRowIsActive {
  param([object]$Row)

  $inactiveOn = Get-DateValue $Row.qfu_inactiveon
  if ($inactiveOn) {
    return $false
  }

  $active = Get-BoolValue $Row.qfu_active
  if ($null -ne $active) {
    return $active
  }

  return $true
}

function Test-BackorderReadyToShipOnly {
  param([object]$Row)

  $qtyOnDelivery = Get-DecimalValue $Row.qfu_qtyondelnotpgid
  $qtyNotOnDelivery = Get-DecimalValue $Row.qfu_qtynotondel
  return $qtyOnDelivery -gt 0 -and $qtyNotOnDelivery -le 0
}

function Test-BackorderActionable {
  param([object]$Row)

  $qtyOnDelivery = Get-DecimalValue $Row.qfu_qtyondelnotpgid
  $qtyNotOnDelivery = Get-DecimalValue $Row.qfu_qtynotondel
  return $qtyNotOnDelivery -gt 0 -or $qtyOnDelivery -gt 0
}

function Get-DesiredBackorderOverdueDays {
  param(
    [object]$Row,
    [datetime]$Today
  )

  $onTimeDate = Get-DateValue $Row.qfu_ontimedate
  if (-not $onTimeDate) {
    return 0
  }

  if ($onTimeDate.Date -ge $Today.Date) {
    return 0
  }

  return Days-Between -Later $Today -Earlier $onTimeDate
}

$connection = Connect-Target -Url $TargetEnvironmentUrl -User $Username
$today = (Get-Date).Date
$branchReports = New-Object System.Collections.Generic.List[object]
$updatedCount = 0

foreach ($branchCode in $BranchCodes) {
  $rows = @(
    (Get-CrmRecords -conn $connection -EntityLogicalName "qfu_backorder" -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $branchCode -Fields @(
        "qfu_backorderid",
        "qfu_sourceid",
        "qfu_salesdocnumber",
        "qfu_sourceline",
        "qfu_daysoverdue",
        "qfu_ontimedate",
        "qfu_qtynotondel",
        "qfu_qtyondelnotpgid",
        "qfu_reasonforrejection",
        "qfu_active",
        "qfu_inactiveon",
        "qfu_lastseenon",
        "createdon",
        "modifiedon"
      ) -TopCount 5000).CrmRecords
  )

  $activeRows = @($rows | Where-Object { Test-OperationalRowIsActive -Row $_ })
  $actionableRows = @($activeRows | Where-Object { Test-BackorderActionable -Row $_ })
  $changes = New-Object System.Collections.Generic.List[object]

  foreach ($row in $actionableRows) {
    $currentDays = Get-IntegerValue $row.qfu_daysoverdue
    $desiredDays = Get-DesiredBackorderOverdueDays -Row $row -Today $today
    if ($currentDays -eq $desiredDays) {
      continue
    }

    $readyToShipOnly = Test-BackorderReadyToShipOnly -Row $row
    $change = [pscustomobject]@{
      record_id = [string]$row.qfu_backorderid
      source_id = [string]$row.qfu_sourceid
      sales_doc_number = [string]$row.qfu_salesdocnumber
      source_line = [string]$row.qfu_sourceline
      on_time_date = if ($row.qfu_ontimedate) { ([datetime]$row.qfu_ontimedate).ToString("yyyy-MM-dd") } else { $null }
      current_days_overdue = $currentDays
      desired_days_overdue = $desiredDays
      qty_not_on_delivery = [decimal](Get-DecimalValue $row.qfu_qtynotondel)
      qty_on_delivery_not_pgid = [decimal](Get-DecimalValue $row.qfu_qtyondelnotpgid)
      ready_to_ship_only = [bool]$readyToShipOnly
      reason_for_rejection = [string]$row.qfu_reasonforrejection
      createdon = if ($row.createdon) { ([datetime]$row.createdon).ToString("o") } else { $null }
      modifiedon = if ($row.modifiedon) { ([datetime]$row.modifiedon).ToString("o") } else { $null }
    }
    $changes.Add($change) | Out-Null

    if ($Apply) {
      Set-CrmRecord -conn $connection -EntityLogicalName "qfu_backorder" -Id $row.qfu_backorderid -Fields @{
        qfu_daysoverdue = $desiredDays
      } | Out-Null
      $updatedCount += 1
    }
  }

  $branchReports.Add([pscustomobject]@{
    branch_code = $branchCode
    active_row_count = $actionableRows.Count
    candidate_update_count = $changes.Count
    rows_becoming_overdue_count = @($changes | Where-Object { $_.current_days_overdue -le 0 -and $_.desired_days_overdue -gt 0 }).Count
    rows_clearing_overdue_count = @($changes | Where-Object { $_.current_days_overdue -gt 0 -and $_.desired_days_overdue -le 0 }).Count
    ready_to_ship_only_change_count = @($changes | Where-Object { $_.ready_to_ship_only }).Count
    backlog_change_count = @($changes | Where-Object { -not $_.ready_to_ship_only }).Count
    sample_changes = @($changes | Select-Object -First 20)
  }) | Out-Null
}

$report = [pscustomobject]@{
  generated_on = (Get-Date).ToUniversalTime().ToString("o")
  target_environment_url = $TargetEnvironmentUrl
  branch_codes = @($BranchCodes)
  as_of_date = $today.ToString("yyyy-MM-dd")
  apply = [bool]$Apply
  updated_count = $updatedCount
  branches = @($branchReports.ToArray())
}

$jsonPath = Resolve-RepoPath -Path $OutputJson
Write-Utf8Json -Path $jsonPath -Object $report

$markdown = New-Object System.Collections.Generic.List[string]
$markdown.Add("# Live Backorder Overdue Day Repair") | Out-Null
$markdown.Add("") | Out-Null
$markdown.Add("- Generated: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))") | Out-Null
$markdown.Add("- Environment: $TargetEnvironmentUrl") | Out-Null
$markdown.Add("- As of: $($today.ToString('yyyy-MM-dd'))") | Out-Null
$markdown.Add("- Apply: $([bool]$Apply)") | Out-Null
$markdown.Add("- Updated rows: $updatedCount") | Out-Null
$markdown.Add("- Rule: qfu_daysoverdue is a derived field and should equal max(today - qfu_ontimedate, 0) for active current-state backorders.") | Out-Null
$markdown.Add("") | Out-Null

foreach ($branch in $report.branches) {
  $markdown.Add("## Branch $($branch.branch_code)") | Out-Null
  $markdown.Add("") | Out-Null
  $markdown.Add("- Active rows: $($branch.active_row_count)") | Out-Null
  $markdown.Add("- Candidate updates: $($branch.candidate_update_count)") | Out-Null
  $markdown.Add("- Rows becoming overdue: $($branch.rows_becoming_overdue_count)") | Out-Null
  $markdown.Add("- Rows clearing overdue: $($branch.rows_clearing_overdue_count)") | Out-Null
  $markdown.Add("- Backlog row changes: $($branch.backlog_change_count)") | Out-Null
  $markdown.Add("- Ready-to-ship-only row changes: $($branch.ready_to_ship_only_change_count)") | Out-Null
  $markdown.Add("") | Out-Null

  if ($branch.sample_changes.Count -gt 0) {
    $markdown.Add("| Source Id | Order | Line | On-Time Date | Current Days | Desired Days | Qty Not On Del | Qty On Del Not PGI | Ready To Ship Only |") | Out-Null
    $markdown.Add("| --- | --- | --- | --- | ---: | ---: | ---: | ---: | --- |") | Out-Null
    foreach ($change in $branch.sample_changes) {
      $markdown.Add("| $($change.source_id) | $($change.sales_doc_number) | $($change.source_line) | $($change.on_time_date) | $($change.current_days_overdue) | $($change.desired_days_overdue) | $($change.qty_not_on_delivery) | $($change.qty_on_delivery_not_pgid) | $($change.ready_to_ship_only) |") | Out-Null
    }
    $markdown.Add("") | Out-Null
  }
}

$markdownPath = Resolve-RepoPath -Path $OutputMarkdown
Write-Utf8File -Path $markdownPath -Content ($markdown -join [Environment]::NewLine)

Write-Host "OUTPUT_JSON=$jsonPath"
Write-Host "OUTPUT_MARKDOWN=$markdownPath"
Write-Host "APPLY=$([bool]$Apply)"
Write-Host "UPDATED_COUNT=$updatedCount"
