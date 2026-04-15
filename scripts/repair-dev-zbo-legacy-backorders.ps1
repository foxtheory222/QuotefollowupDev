param(
  [string]$TargetEnvironmentUrl = "https://orgad610d2c.crm3.dynamics.com",
  [string]$Username = "smcfarlane@applied.com",
  [string]$BranchCode = "4171",
  [string]$BranchSlug = "4171-calgary",
  [string]$RegionSlug = "southern-alberta",
  [int]$MaxCountDelta = 25,
  [string]$OutputJson = "results\\repair-dev-zbo-legacy-backorders.json",
  [switch]$Force
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

  [System.IO.File]::WriteAllText($Path, ($Object | ConvertTo-Json -Depth 10), [System.Text.UTF8Encoding]::new($false))
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

function Parse-LineNumberFromName {
  param([string]$Name)

  if ([string]::IsNullOrWhiteSpace($Name)) {
    return $null
  }

  $match = [regex]::Match($Name, '^BO-(?<salesDoc>[^-]+)-(?<line>.+)$')
  if (-not $match.Success) {
    return $null
  }

  return [string]$match.Groups["line"].Value
}

function Get-LatestBranchSummary {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$Code
  )

  $rows = @(
    (Get-CrmRecords -conn $Connection -EntityLogicalName "qfu_branchdailysummary" -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $Code -Fields @(
        "qfu_branchdailysummaryid",
        "qfu_branchcode",
        "qfu_branchslug",
        "qfu_summarydate",
        "qfu_backordercount",
        "createdon"
      ) -TopCount 50
    ).CrmRecords
  )

  return $rows |
    Sort-Object @{ Expression = { Get-DateValue $_.qfu_summarydate }; Descending = $true }, @{ Expression = { Get-DateValue $_.createdon }; Descending = $true } |
    Select-Object -First 1
}

$outputPath = Resolve-RepoPath -Path $OutputJson
$connection = Connect-Target -Url $TargetEnvironmentUrl -User $Username
$latestSummary = Get-LatestBranchSummary -Connection $connection -Code $BranchCode

$allBackorders = @(
  (Get-CrmRecords -conn $connection -EntityLogicalName "qfu_backorder" -Fields @(
      "qfu_backorderid",
      "qfu_name",
      "qfu_salesdocnumber",
      "qfu_sourceid",
      "qfu_sourcefamily",
      "qfu_branchcode",
      "qfu_branchslug",
      "qfu_sourceline",
      "qfu_active",
      "qfu_inactiveon",
      "qfu_quantity",
      "qfu_daysoverdue",
      "createdon",
      "modifiedon"
    ) -TopCount 5000
  ).CrmRecords
)

$candidateRows = @(
  $allBackorders | Where-Object {
    [string]::IsNullOrWhiteSpace([string]$_.qfu_branchcode) -and
    [string]::IsNullOrWhiteSpace([string]$_.qfu_branchslug) -and
    [string]::IsNullOrWhiteSpace([string]$_.qfu_sourceid) -and
    -not [string]::IsNullOrWhiteSpace([string]$_.qfu_salesdocnumber) -and
    ([string]$_.qfu_name) -like "BO-*"
  }
)

$activationCandidates = @(
  $allBackorders | Where-Object {
    [string]$_.qfu_branchcode -eq $BranchCode -and
    [string]$_.qfu_sourcefamily -eq "ZBO" -and
    (([string]$_.qfu_active).Trim().ToLowerInvariant() -in @("false", "0", "no")) -and
    -not (Get-DateValue -Value $_.qfu_inactiveon)
  }
)

$summaryBackorderCount = if ($latestSummary) { [int]$latestSummary.qfu_backordercount } else { $null }
$countDelta = if ($null -ne $summaryBackorderCount) { [math]::Abs($candidateRows.Count - $summaryBackorderCount) } else { $null }

if (-not $Force -and $candidateRows.Count -gt 0 -and $null -ne $countDelta -and $countDelta -gt $MaxCountDelta) {
  throw "Refusing repair because candidate row count $($candidateRows.Count) differs from latest branch summary count $summaryBackorderCount by $countDelta. Re-run with -Force to override."
}

$updated = New-Object System.Collections.Generic.List[object]
$skipped = New-Object System.Collections.Generic.List[object]
$activated = New-Object System.Collections.Generic.List[object]

foreach ($row in $candidateRows) {
  $lineNumber = if (-not [string]::IsNullOrWhiteSpace([string]$row.qfu_sourceline)) {
    [string]$row.qfu_sourceline
  } else {
    Parse-LineNumberFromName -Name ([string]$row.qfu_name)
  }

  if ([string]::IsNullOrWhiteSpace($lineNumber)) {
    $skipped.Add([pscustomobject]@{
      backorder_id = [string]$row.qfu_backorderid
      name = [string]$row.qfu_name
      reason = "Could not parse source line from qfu_name."
    }) | Out-Null
    continue
  }

  $salesDoc = [string]$row.qfu_salesdocnumber
  $fields = @{
    qfu_name = "{0}-BO-{1}-{2}" -f $BranchCode, $salesDoc, $lineNumber
    qfu_sourceid = "{0}|ZBO|{1}|{2}" -f $BranchCode, $salesDoc, $lineNumber
    qfu_branchcode = $BranchCode
    qfu_branchslug = $BranchSlug
    qfu_regionslug = $RegionSlug
    qfu_sourcefamily = "ZBO"
    qfu_sourceline = $lineNumber
  }

  Set-CrmRecord -conn $connection -EntityLogicalName "qfu_backorder" -Id $row.qfu_backorderid -Fields $fields | Out-Null

  $updated.Add([pscustomobject]@{
    backorder_id = [string]$row.qfu_backorderid
    sales_doc = $salesDoc
    source_line = $lineNumber
    source_id = $fields.qfu_sourceid
  }) | Out-Null
}

foreach ($row in $activationCandidates) {
  Set-CrmRecord -conn $connection -EntityLogicalName "qfu_backorder" -Id $row.qfu_backorderid -Fields @{
    qfu_active = $true
    qfu_inactiveon = $null
  } | Out-Null

  $activated.Add([pscustomobject]@{
    backorder_id = [string]$row.qfu_backorderid
    source_id = [string]$row.qfu_sourceid
    branch_code = [string]$row.qfu_branchcode
  }) | Out-Null
}

$report = [pscustomobject]@{
  generated_on = (Get-Date).ToUniversalTime().ToString("o")
  target_environment_url = $TargetEnvironmentUrl
  branch_code = $BranchCode
  branch_slug = $BranchSlug
  region_slug = $RegionSlug
  latest_summary = if ($latestSummary) {
    [pscustomobject]@{
      branchdailysummary_id = [string]$latestSummary.qfu_branchdailysummaryid
      summary_date = if ($latestSummary.qfu_summarydate) { ([datetime]$latestSummary.qfu_summarydate).ToString("yyyy-MM-dd") } else { $null }
      backorder_count = [int]$latestSummary.qfu_backordercount
    }
  } else {
    $null
  }
  candidate_count = $candidateRows.Count
  activation_candidate_count = $activationCandidates.Count
  count_delta = $countDelta
  updated_count = $updated.Count
  activated_count = $activated.Count
  skipped_count = $skipped.Count
  updated_sample = @($updated.ToArray() | Select-Object -First 20)
  activated_sample = @($activated.ToArray() | Select-Object -First 20)
  skipped = @($skipped.ToArray())
}

Write-Utf8Json -Path $outputPath -Object $report
$report | ConvertTo-Json -Depth 10
