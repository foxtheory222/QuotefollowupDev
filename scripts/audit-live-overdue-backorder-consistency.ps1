param(
  [string]$TargetEnvironmentUrl = "https://regionaloperationshub.crm.dynamics.com",
  [string]$Username = "smcfarlane@applied.com",
  [string[]]$BranchCodes = @("4171", "4172", "4173"),
  [string]$OutputJson = "VERIFICATION\\overdue-backorder-consistency.json",
  [string]$OutputMarkdown = "VERIFICATION\\overdue-backorder-consistency.md"
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

function Test-BackorderOverdueDateMismatch {
  param(
    [object]$Row,
    [datetime]$Today
  )

  if ($null -eq $Row.qfu_daysoverdue -or [string]::IsNullOrWhiteSpace([string]$Row.qfu_daysoverdue)) {
    return $false
  }

  $onTimeDate = Get-DateValue $Row.qfu_ontimedate
  if (-not $onTimeDate) {
    return $false
  }

  return (Get-IntegerValue $Row.qfu_daysoverdue) -le 0 -and $onTimeDate.Date -lt $Today.Date
}

$connection = Connect-Target -Url $TargetEnvironmentUrl -User $Username
$today = (Get-Date).Date
$branchReports = New-Object System.Collections.Generic.List[object]

foreach ($branchCode in $BranchCodes) {
  $rows = @(
    (Get-CrmRecords -conn $connection -EntityLogicalName "qfu_backorder" -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $branchCode -Fields @(
        "qfu_backorderid",
        "qfu_sourceid",
        "qfu_salesdocnumber",
        "qfu_daysoverdue",
        "qfu_ontimedate",
        "qfu_qtynotondel",
        "qfu_qtyondelnotpgid",
        "qfu_totalvalue",
        "qfu_active",
        "qfu_inactiveon",
        "createdon",
        "modifiedon"
      ) -TopCount 5000).CrmRecords
  )

  $activeRows = @($rows | Where-Object { Test-OperationalRowIsActive -Row $_ })
  $positiveDayRows = @($activeRows | Where-Object {
      (Test-BackorderActionable -Row $_) -and
      (Get-IntegerValue $_.qfu_daysoverdue) -gt 0
    })
  $mismatchRows = @($activeRows | Where-Object {
      (Test-BackorderActionable -Row $_) -and
      (Test-BackorderOverdueDateMismatch -Row $_ -Today $today)
    })
  $mismatchReadyRows = @($mismatchRows | Where-Object { Test-BackorderReadyToShipOnly -Row $_ })
  $mismatchBacklogRows = @($mismatchRows | Where-Object { -not (Test-BackorderReadyToShipOnly -Row $_) })

  $branchReports.Add([pscustomobject]@{
    branch_code = $branchCode
    active_rows = @($activeRows).Count
    corrected_overdue_rows = @($positiveDayRows).Count
    mismatch_rows = @($mismatchRows).Count
    mismatch_ready_to_ship_only_rows = @($mismatchReadyRows).Count
    mismatch_backlog_rows = @($mismatchBacklogRows).Count
    mismatch_value = [decimal](@($mismatchRows | Measure-Object -Property qfu_totalvalue -Sum).Sum)
    sample_rows = @(
      $mismatchRows |
        Select-Object -First 15 |
        ForEach-Object {
          [pscustomobject]@{
            source_id = [string]$_.qfu_sourceid
            sales_doc = [string]$_.qfu_salesdocnumber
            days_overdue = Get-IntegerValue $_.qfu_daysoverdue
            on_time_date = if ($_.qfu_ontimedate) { ([datetime]$_.qfu_ontimedate).ToString("yyyy-MM-dd") } else { $null }
            qty_not_on_delivery = Get-DecimalValue $_.qfu_qtynotondel
            qty_on_delivery_not_pgid = Get-DecimalValue $_.qfu_qtyondelnotpgid
            total_value = Get-DecimalValue $_.qfu_totalvalue
            ready_to_ship_only = Test-BackorderReadyToShipOnly -Row $_
          }
        }
    )
  }) | Out-Null
}

$report = [pscustomobject]@{
  generated_on = (Get-Date).ToUniversalTime().ToString("o")
  target_environment_url = $TargetEnvironmentUrl
  branch_codes = @($BranchCodes)
  overdue_rule = "Overdue uses qfu_daysoverdue as authority. Past on-time dates with qfu_daysoverdue = 0 are flagged for diagnosis and are not counted overdue by the hardened runtime."
  branches = @($branchReports.ToArray())
}

$jsonPath = Resolve-RepoPath -Path $OutputJson
$markdownPath = Resolve-RepoPath -Path $OutputMarkdown
Write-Utf8Json -Path $jsonPath -Object $report

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Live Overdue Backorder Consistency Audit") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("- Generated: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))") | Out-Null
$lines.Add("- Environment: $TargetEnvironmentUrl") | Out-Null
$lines.Add("- Rule: $($report.overdue_rule)") | Out-Null
$lines.Add("") | Out-Null

foreach ($branch in $report.branches) {
  $lines.Add("## Branch $($branch.branch_code)") | Out-Null
  $lines.Add("") | Out-Null
  $lines.Add("- Active current-state rows: $($branch.active_rows)") | Out-Null
  $lines.Add("- Corrected overdue rows: $($branch.corrected_overdue_rows)") | Out-Null
  $lines.Add("- Past on-time + zero-day mismatch rows: $($branch.mismatch_rows)") | Out-Null
  $lines.Add("- Mismatch rows that are ready-to-ship only: $($branch.mismatch_ready_to_ship_only_rows)") | Out-Null
  $lines.Add("- Mismatch rows that still have backlog quantity: $($branch.mismatch_backlog_rows)") | Out-Null
  $lines.Add("- Mismatch value: $([math]::Round([decimal]$branch.mismatch_value, 2))") | Out-Null
  if (@($branch.sample_rows).Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("| Source Id | Order | Days Overdue | On-Time Date | Qty Not On Del | Qty On Del Not PGI | Value | Ready To Ship Only |") | Out-Null
    $lines.Add("| --- | --- | ---: | --- | ---: | ---: | ---: | --- |") | Out-Null
    foreach ($sample in @($branch.sample_rows)) {
      $lines.Add("| $($sample.source_id) | $($sample.sales_doc) | $($sample.days_overdue) | $($sample.on_time_date) | $($sample.qty_not_on_delivery) | $($sample.qty_on_delivery_not_pgid) | $($sample.total_value) | $($sample.ready_to_ship_only) |") | Out-Null
    }
  }
  $lines.Add("") | Out-Null
}

Write-Utf8File -Path $markdownPath -Content ($lines -join [Environment]::NewLine)

Write-Host "JSON_PATH=$jsonPath"
Write-Host "MARKDOWN_PATH=$markdownPath"
