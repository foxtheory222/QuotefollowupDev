param(
  [string]$TargetEnvironmentUrl = "<URL>
  [string]$Username = "<EMAIL>",
  [string[]]$BranchCodes = @("4171", "4172", "4173"),
  [string]$OutputJson = "VERIFICATION\\margin-snapshot-integrity.json",
  [string]$OutputMarkdown = "VERIFICATION\\margin-snapshot-integrity.md"
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

function Snapshot-DayKey {
  param([object]$Value)

  $parsed = Get-DateValue $Value
  if (-not $parsed) {
    return ""
  }

  return $parsed.ToString("yyyy-MM-dd")
}

function Normalize-IdentityValue {
  param([object]$Value)

  $raw = if ($null -eq $Value) { "" } else { [string]$Value }
  $text = $raw.Trim().ToLowerInvariant() -replace "\s+", " "
  if ($text -match "^\d+\.0+$") {
    return ($text -replace "\.0+$", "")
  }

  return $text
}

$connection = Connect-Target -Url $TargetEnvironmentUrl -User $Username
$monthKey = (Get-Date).ToString("yyyy-MM")
$branchReports = New-Object System.Collections.Generic.List[object]

foreach ($branchCode in $BranchCodes) {
  $rows = @(
    (Get-CrmRecords -conn $connection -EntityLogicalName "qfu_marginexception" -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $branchCode -Fields @(
        "qfu_marginexceptionid",
        "qfu_sourceid",
        "qfu_snapshotdate",
        "qfu_billingdate",
        "qfu_billingdocumentnumber",
        "qfu_reviewtype",
        "qfu_customername",
        "qfu_cssr",
        "qfu_cssrname",
        "createdon",
        "modifiedon"
      ) -TopCount 5000).CrmRecords
  )

  $monthRows = @($rows | Where-Object {
    $billingDate = Get-DateValue $_.qfu_billingdate
    $billingDate -and $billingDate.ToString("yyyy-MM") -eq $monthKey
  })

  $latestSnapshotDate = @($monthRows | Sort-Object { Get-DateValue $_.qfu_snapshotdate } -Descending | Select-Object -First 1 | ForEach-Object { Get-DateValue $_.qfu_snapshotdate })[0]
  $latestSnapshotKey = Snapshot-DayKey $latestSnapshotDate
  $latestSnapshotRows = if ($latestSnapshotKey) {
    @($monthRows | Where-Object { (Snapshot-DayKey $_.qfu_snapshotdate) -eq $latestSnapshotKey })
  } else {
    @()
  }

  $latestDuplicates = @(
    $latestSnapshotRows |
      Group-Object {
        "{0}|{1}" -f
          (Normalize-IdentityValue $_.qfu_billingdocumentnumber),
          (Normalize-IdentityValue $_.qfu_reviewtype)
      } |
      Where-Object { $_.Count -gt 1 } |
      Sort-Object Count -Descending
  )

  $repeatedAcrossSnapshots = @(
    $monthRows |
      Group-Object {
        "{0}|{1}" -f
          (Normalize-IdentityValue $_.qfu_billingdocumentnumber),
          (Normalize-IdentityValue $_.qfu_reviewtype)
      } |
      Where-Object {
        @($_.Group | ForEach-Object { Snapshot-DayKey $_.qfu_snapshotdate } | Sort-Object -Unique).Count -gt 1
      } |
      Sort-Object Count -Descending
  )

  $branchReports.Add([pscustomobject]@{
    branch_code = $branchCode
    current_month = $monthKey
    current_month_row_count = @($monthRows).Count
    latest_snapshot_date = if ($latestSnapshotDate) { $latestSnapshotDate.ToString("yyyy-MM-dd") } else { $null }
    latest_snapshot_row_count = @($latestSnapshotRows).Count
    latest_snapshot_duplicate_doc_review_groups = @($latestDuplicates).Count
    repeated_doc_review_across_snapshot_days = @($repeatedAcrossSnapshots).Count
    latest_snapshot_duplicate_samples = @(
      $latestDuplicates |
        Select-Object -First 10 |
        ForEach-Object {
          $parts = ([string]$_.Name).Split("|", 2)
          [pscustomobject]@{
            billing_document = $parts[0]
            review_type = if ($parts.Length -gt 1) { $parts[1] } else { "" }
            row_count = $_.Count
            source_ids = @($_.Group | ForEach-Object { [string]$_.qfu_sourceid })
          }
        }
    )
    repeated_doc_review_samples = @(
      $repeatedAcrossSnapshots |
        Select-Object -First 10 |
        ForEach-Object {
          $parts = ([string]$_.Name).Split("|", 2)
          [pscustomobject]@{
            billing_document = $parts[0]
            review_type = if ($parts.Length -gt 1) { $parts[1] } else { "" }
            snapshot_days = @($_.Group | ForEach-Object { Snapshot-DayKey $_.qfu_snapshotdate } | Sort-Object -Unique)
            source_ids = @($_.Group | ForEach-Object { [string]$_.qfu_sourceid })
          }
        }
    )
  }) | Out-Null
}

$jsonPath = Resolve-RepoPath -Path $OutputJson
$markdownPath = Resolve-RepoPath -Path $OutputMarkdown

$report = [pscustomobject]@{
  generated_on = (Get-Date).ToUniversalTime().ToString("o")
  target_environment_url = $TargetEnvironmentUrl
  current_month = $monthKey
  branches = @($branchReports.ToArray())
}

Write-Utf8Json -Path $jsonPath -Object $report

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Margin Snapshot Integrity") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("- Generated: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))") | Out-Null
$lines.Add("- Environment: $TargetEnvironmentUrl") | Out-Null
$lines.Add("- Current billing month checked: $monthKey") | Out-Null
$lines.Add("") | Out-Null

foreach ($branch in $report.branches) {
  $lines.Add("## Branch $($branch.branch_code)") | Out-Null
  $lines.Add("") | Out-Null
  $lines.Add("- Current-month rows: $($branch.current_month_row_count)") | Out-Null
  $latestSnapshotLabel = if ([string]::IsNullOrWhiteSpace([string]$branch.latest_snapshot_date)) { "None" } else { [string]$branch.latest_snapshot_date }
  $lines.Add("- Latest snapshot date: $latestSnapshotLabel") | Out-Null
  $lines.Add("- Latest-snapshot rows: $($branch.latest_snapshot_row_count)") | Out-Null
  $lines.Add("- Duplicate billing-doc/review groups on latest snapshot: $($branch.latest_snapshot_duplicate_doc_review_groups)") | Out-Null
  $lines.Add("- Billing-doc/review groups spanning multiple snapshot days this month: $($branch.repeated_doc_review_across_snapshot_days)") | Out-Null
  if (@($branch.repeated_doc_review_samples).Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("| Billing Doc | Review Type | Snapshot Days |") | Out-Null
    $lines.Add("| --- | --- | --- |") | Out-Null
    foreach ($sample in $branch.repeated_doc_review_samples) {
      $lines.Add("| $($sample.billing_document) | $($sample.review_type) | $((@($sample.snapshot_days) -join ', ')) |") | Out-Null
    }
  }
  $lines.Add("") | Out-Null
}

Write-Utf8File -Path $markdownPath -Content ($lines -join [Environment]::NewLine)

Write-Host "JSON_PATH=$jsonPath"
Write-Host "MARKDOWN_PATH=$markdownPath"
