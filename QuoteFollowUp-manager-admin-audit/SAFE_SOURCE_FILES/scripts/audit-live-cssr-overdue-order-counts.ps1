param(
  [string]$TargetEnvironmentUrl = "<URL>
  [string]$Username = "<EMAIL>",
  [string[]]$BranchCodes = @("4171", "4172", "4173"),
  [string]$OutputJson = "VERIFICATION\\cssr-overdue-order-counts.json",
  [string]$OutputMarkdown = "VERIFICATION\\cssr-overdue-order-counts.md"
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

function Test-OperationalRowIsActive {
  param([object]$Row)

  if ($Row.qfu_inactiveon) {
    return $false
  }

  $active = Get-BoolValue $Row.qfu_active
  if ($null -ne $active) {
    return $active
  }

  return $true
}

$connection = Connect-Target -Url $TargetEnvironmentUrl -User $Username
$branchSummaryByCode = @{}
$topRowsByBranch = @{}

foreach ($branchCode in $BranchCodes) {
  $rows = @(
    (Get-CrmRecords -conn $connection -EntityLogicalName "qfu_backorder" -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $branchCode -Fields @(
        "qfu_backorderid",
        "qfu_sourceid",
        "qfu_salesdocnumber",
        "qfu_cssrname",
        "qfu_daysoverdue",
        "qfu_totalvalue",
        "qfu_qtyondelnotpgid",
        "qfu_qtynotondel",
        "qfu_active",
        "qfu_inactiveon"
      ) -TopCount 5000).CrmRecords
  )

  $activeRows = @($rows | Where-Object { Test-OperationalRowIsActive -Row $_ })
  $overdueRows = @(
    $activeRows |
      Where-Object {
        (Test-BackorderActionable -Row $_) -and
        (Get-IntegerValue $_.qfu_daysoverdue) -gt 0
      }
  )
  $groupRows = New-Object System.Collections.Generic.List[object]

  foreach ($group in @($overdueRows | Group-Object {
    $name = ([string]$_.qfu_cssrname).Trim()
    if ([string]::IsNullOrWhiteSpace($name)) { "Unassigned" } else { $name }
  })) {
    $orderKeys = @(
      $group.Group |
        ForEach-Object { ([string]$_.qfu_salesdocnumber).Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object -Unique
    )
    $groupRows.Add([pscustomobject]@{
      cssr = $group.Name
      overdue_line_count = $group.Count
      overdue_order_count = @($orderKeys).Count
      overdue_value = [decimal](@($group.Group | Measure-Object -Property qfu_totalvalue -Sum).Sum)
      oldest_days = [int](@($group.Group | Measure-Object -Property qfu_daysoverdue -Maximum).Maximum)
    }) | Out-Null
  }

  $topRows = @(
    $groupRows.ToArray() |
      Sort-Object -Property @(
        @{ Expression = "overdue_order_count"; Descending = $true },
        @{ Expression = "overdue_line_count"; Descending = $true },
        @{ Expression = "cssr"; Descending = $false }
      ) |
      Select-Object -First 10
  )
  $branchOrderKeys = @(
    $overdueRows |
      ForEach-Object { [string]$_.qfu_salesdocnumber } |
      ForEach-Object { $_.Trim() } |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
      Sort-Object -Unique
  )
  $branchOverdueLineCount = @($overdueRows).Count
  $branchOverdueOrderCount = @($branchOrderKeys).Count
  $branchCssrCount = $groupRows.Count
  $topRowsByBranch[$branchCode] = @($topRows)
  $branchSummaryByCode[$branchCode] = [ordered]@{
    branch_code = $branchCode
    overdue_line_count = $branchOverdueLineCount
    overdue_order_count = $branchOverdueOrderCount
    cssr_count = $branchCssrCount
  }
}

$jsonPath = Resolve-RepoPath -Path $OutputJson
$markdownPath = Resolve-RepoPath -Path $OutputMarkdown

$report = [pscustomobject]@{
  generated_on = (Get-Date).ToUniversalTime().ToString("o")
  target_environment_url = $TargetEnvironmentUrl
  branches = @(
    $BranchCodes | ForEach-Object {
      [pscustomobject]$branchSummaryByCode[$_]
    }
  )
}

Write-Utf8Json -Path $jsonPath -Object $report

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# CSSR Overdue Order Counts") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("- Generated: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))") | Out-Null
$lines.Add("- Environment: $TargetEnvironmentUrl") | Out-Null
$lines.Add("") | Out-Null

foreach ($branch in $report.branches) {
  $lines.Add("## Branch $($branch.branch_code)") | Out-Null
  $lines.Add("") | Out-Null
  $lines.Add("- Overdue line rows: $($branch.overdue_line_count)") | Out-Null
  $lines.Add("- Distinct overdue orders: $($branch.overdue_order_count)") | Out-Null
  $lines.Add("- CSSRs with overdue orders: $($branch.cssr_count)") | Out-Null
  $lines.Add("") | Out-Null
  $lines.Add("| CSSR | Overdue Orders | Overdue Lines | Oldest Days | Overdue Value |") | Out-Null
  $lines.Add("| --- | ---: | ---: | ---: | ---: |") | Out-Null
  foreach ($row in @($topRowsByBranch[$branch.branch_code])) {
    $lines.Add("| $($row.cssr) | $($row.overdue_order_count) | $($row.overdue_line_count) | $($row.oldest_days) | $([decimal]$row.overdue_value) |") | Out-Null
  }
  $lines.Add("") | Out-Null
}

Write-Utf8File -Path $markdownPath -Content ($lines -join [Environment]::NewLine)

Write-Host "JSON_PATH=$jsonPath"
Write-Host "MARKDOWN_PATH=$markdownPath"
