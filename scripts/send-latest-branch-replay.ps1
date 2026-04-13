param(
  [string]$LatestRoot = "C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\Latest",
  [string[]]$Branches = @("4171", "4172", "4173"),
  [int]$RepeatCount = 1,
  [int]$PauseSeconds = 5,
  [string]$OutputPath = "results\latest-branch-replay-send-summary.json",
  [switch]$AllowProductionReplay,
  [switch]$AllowDuplicateReplay,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

if ($RepeatCount -lt 1) {
  throw "RepeatCount must be at least 1."
}

if (-not $DryRun -and -not $AllowProductionReplay) {
  throw "Latest replay is blocked by default because it can duplicate or overwrite live current-state. Re-run with -AllowProductionReplay only for an intentional production replay."
}

if ($RepeatCount -gt 1 -and -not $AllowDuplicateReplay) {
  throw "RepeatCount greater than 1 is blocked by default because it can duplicate current-state imports. Re-run with -AllowDuplicateReplay only when an intentional duplicate replay is required."
}

function Ensure-Directory {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Get-BranchAttachments {
  param(
    [string]$Root,
    [string]$BranchCode
  )

  $branchPath = Join-Path $Root $BranchCode
  if (-not (Test-Path -LiteralPath $branchPath)) {
    throw "Branch folder not found: $branchPath"
  }

  $files = @(Get-ChildItem -LiteralPath $branchPath -File | Sort-Object Name)
  if ($files.Count -eq 0) {
    throw "No files found for branch $BranchCode in $branchPath"
  }

  return $files
}

function Write-Utf8Json {
  param(
    [string]$Path,
    [object]$Object
  )

  $fullPath = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path -Path (Get-Location).Path -ChildPath $Path }
  $parent = Split-Path -Parent $fullPath
  if ($parent) {
    Ensure-Directory -Path $parent
  }

  $json = $Object | ConvertTo-Json -Depth 20
  [System.IO.File]::WriteAllText([string]$fullPath, [string]$json, [System.Text.UTF8Encoding]::new($false))
  return $fullPath
}

$outlook = $null
if (-not $DryRun) {
  $outlook = New-Object -ComObject Outlook.Application
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$summary = New-Object System.Collections.Generic.List[object]

foreach ($branch in $Branches) {
  $attachments = @(Get-BranchAttachments -Root $LatestRoot -BranchCode $branch)
  $recipient = "$branch@applied.com"

  for ($pass = 1; $pass -le $RepeatCount; $pass += 1) {
    $subject = "QFU replay $branch pass $pass $timestamp"
    $body = @"
Automated QFU replay for branch $branch.

Pass: $pass of $RepeatCount
Attachments: $($attachments.Count)
Source folder: $(Join-Path $LatestRoot $branch)
"@

    if (-not $DryRun) {
      $mail = $outlook.CreateItem(0)
      $mail.To = $recipient
      $mail.Subject = $subject
      $mail.Body = $body

      foreach ($file in $attachments) {
        [void]$mail.Attachments.Add($file.FullName)
      }

      $mail.Send()
    }

    $summary.Add([pscustomobject]@{
      branch = $branch
      recipient = $recipient
      pass = $pass
      subject = $subject
      production_replay_allowed = [bool]$AllowProductionReplay
      dry_run = [bool]$DryRun
      attachment_count = $attachments.Count
      attachments = @($attachments | ForEach-Object { $_.Name })
      sent_at = (Get-Date).ToUniversalTime().ToString("o")
    }) | Out-Null

    if ($pass -lt $RepeatCount -and $PauseSeconds -gt 0) {
      Start-Sleep -Seconds $PauseSeconds
    }
  }
}

$report = [ordered]@{
  latest_root = $LatestRoot
  branches = @($Branches)
  repeat_count = $RepeatCount
  production_replay_allowed = [bool]$AllowProductionReplay
  dry_run = [bool]$DryRun
  runs = @($summary.ToArray())
}

$savedPath = Write-Utf8Json -Path $OutputPath -Object $report

Write-Host "OUTPUT_PATH=$savedPath"
