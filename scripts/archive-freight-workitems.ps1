param(
  [string]$RepoRoot = "C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion",
  [string]$TargetEnvironmentUrl = "https://regionaloperationshub.crm.dynamics.com",
  [string]$Username = "smcfarlane@applied.com",
  [int]$ArchiveAfterDays = 60,
  [string]$OutputJson = "results\freight-archive-summary.json"
)

$ErrorActionPreference = "Stop"

. (Join-Path $RepoRoot "scripts\deploy-southern-alberta-pilot.ps1")
. (Join-Path $RepoRoot "scripts\deploy-freight-worklist.ps1")

function Convert-FreightArchiveBoolean {
  param($Value)

  if ($null -eq $Value) {
    return $false
  }

  if ($Value -is [bool]) {
    return [bool]$Value
  }

  $text = [string]$Value
  if ([string]::IsNullOrWhiteSpace($text)) {
    return $false
  }

  switch ($text.Trim().ToLowerInvariant()) {
    "1" { return $true }
    "0" { return $false }
    "true" { return $true }
    "false" { return $false }
    "yes" { return $true }
    "no" { return $false }
    default { return $false }
  }
}

$target = Connect-Org -Url $TargetEnvironmentUrl
Write-Host "Connected target: $($target.ConnectedOrgFriendlyName)"

Ensure-FreightSchema -Connection $target

$now = [datetime]::UtcNow
$cutoff = $now.AddDays(-1 * [Math]::Abs($ArchiveAfterDays))
$rows = @((Get-CrmRecords -conn $target -EntityLogicalName "qfu_freightworkitem" -Fields @(
      "qfu_freightworkitemid",
      "qfu_sourceid",
      "qfu_branchcode",
      "qfu_branchslug",
      "qfu_status",
      "qfu_lastactivityon",
      "qfu_commentupdatedon",
      "qfu_claimedon",
      "qfu_lastseenon",
      "qfu_isarchived",
      "qfu_archivedon",
      "createdon",
      "modifiedon"
    ) -TopCount 5000).CrmRecords)

$eligible = @()
foreach ($row in $rows) {
  $status = [string]$row.qfu_status
  $statusNormalized = $status.Trim().ToLowerInvariant()
  if ($statusNormalized -notin @("closed", "no action")) {
    continue
  }
  if (Convert-FreightArchiveBoolean $row.qfu_isarchived) {
    continue
  }

  $lastActivity = $null
  $activityCandidates = @($row.qfu_lastactivityon, $row.qfu_commentupdatedon, $row.qfu_claimedon, $row.qfu_lastseenon)
  $fallbackCandidates = @($row.modifiedon, $row.createdon)
  $candidatePool = $activityCandidates
  if (-not ($activityCandidates | Where-Object { $_ })) {
    $candidatePool = $fallbackCandidates
  }

  foreach ($candidate in $candidatePool) {
    if ($candidate) {
      try {
        $parsed = [datetime]$candidate
        if (-not $lastActivity -or $parsed -gt $lastActivity) {
          $lastActivity = $parsed
        }
      } catch {
      }
    }
  }

  if ($lastActivity -and $lastActivity -le $cutoff) {
    $eligible += [pscustomobject]@{
      id = [string]$row.qfu_freightworkitemid
      source_id = [string]$row.qfu_sourceid
      branch_code = [string]$row.qfu_branchcode
      branch_slug = [string]$row.qfu_branchslug
      status = $status
      last_activity_on = $lastActivity.ToString("s")
    }
  }
}

foreach ($candidate in $eligible) {
  Set-CrmRecord -conn $target -EntityLogicalName "qfu_freightworkitem" -Id $candidate.id -Fields @{
    qfu_isarchived = $true
    qfu_archivedon = $now
  } | Out-Null
}

$result = [ordered]@{
  target_environment = $TargetEnvironmentUrl
  archive_after_days = $ArchiveAfterDays
  archived_count = @($eligible).Count
  archived_rows = @($eligible)
}

Write-Utf8Json -Path (Join-Path $RepoRoot $OutputJson) -Object $result
Write-Output ($result | ConvertTo-Json -Depth 6)
