param(
  [string]$ExampleRoot = "C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\example",
  [string[]]$Branches = @("4171", "4172", "4173"),
  [string[]]$Families = @("SA1300", "SP830CA", "ZBO", "GL060"),
  [int]$PauseSeconds = 2,
  [string]$OutputPath = "",
  [switch]$AllowProductionReplay,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

if (-not $DryRun -and -not $AllowProductionReplay) {
  throw "Example replay is blocked by default because it can contaminate live current-state. Re-run with -AllowProductionReplay only for an intentional production replay."
}

$familySpecs = @(
  [pscustomobject]@{
    Family = "SA1300"
    EmlPattern = "*SA1300*.eml"
    AttachmentPattern = "SA1300*.xlsx"
    SubjectFallback = "SA1300-Excel Report"
  },
  [pscustomobject]@{
    Family = "SP830CA"
    EmlPattern = "*SP830CA*.eml"
    AttachmentPattern = "*SP830CA*.xlsx"
    SubjectFallback = "SP830CA - Quote Follow Up Report"
  },
  [pscustomobject]@{
    Family = "ZBO"
    EmlPattern = "Daily Backorder Report *.eml"
    AttachmentPattern = "*ZBO*.xlsx"
    SubjectFallback = $null
  },
  [pscustomobject]@{
    Family = "GL060"
    EmlPattern = "*GL060*.eml"
    AttachmentPattern = "*GL060*.pdf"
    SubjectFallback = "GL060 P&L report - Last month"
  }
)

function Ensure-Directory {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
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
  [System.IO.File]::WriteAllText($fullPath, $json, [System.Text.UTF8Encoding]::new($false))
  return $fullPath
}

function Get-UnfoldedHeaderValue {
  param(
    [string]$Content,
    [string]$HeaderName
  )

  $match = [regex]::Match($Content, "(?im)^$([regex]::Escape($HeaderName)):\s*(.+(?:\r?\n[ \t].+)*)")
  if (-not $match.Success) {
    return $null
  }

  $value = $match.Groups[1].Value -replace "\r?\n[ \t]+", " "
  return $value.Trim()
}

function Get-FamilyPayload {
  param(
    [string]$Root,
    [string]$BranchCode,
    [string]$Family
  )

  $spec = $familySpecs | Where-Object { $_.Family -eq $Family } | Select-Object -First 1
  if (-not $spec) {
    throw "Unsupported family: $Family"
  }

  $branchPath = Join-Path $Root $BranchCode
  if (-not (Test-Path -LiteralPath $branchPath)) {
    throw "Branch folder not found: $branchPath"
  }

  $eml = Get-ChildItem -LiteralPath $branchPath -Filter $spec.EmlPattern -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $eml) {
    throw "No $Family .eml file found in $branchPath"
  }

  $attachment = Get-ChildItem -LiteralPath $branchPath -Filter $spec.AttachmentPattern -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $attachment) {
    throw "No $Family attachment file found in $branchPath"
  }

  $content = Get-Content -LiteralPath $eml.FullName -Raw
  $subject = Get-UnfoldedHeaderValue -Content $content -HeaderName "Subject"
  if ([string]::IsNullOrWhiteSpace($subject)) {
    $subject = $spec.SubjectFallback
  }

  if ([string]::IsNullOrWhiteSpace($subject)) {
    throw "Unable to determine subject for $Family in $($eml.FullName)"
  }

  return [pscustomobject]@{
    BranchCode = $BranchCode
    Family = $Family
    Recipient = "$BranchCode@applied.com"
    Subject = $subject
    EmlPath = $eml.FullName
    AttachmentPath = $attachment.FullName
    AttachmentName = $attachment.Name
    EmlLastWriteTime = $eml.LastWriteTime
    AttachmentLastWriteTime = $attachment.LastWriteTime
  }
}

$selectedFamilies = @($Families | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
$selectedBranches = @($Branches | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
$payloads = New-Object System.Collections.Generic.List[object]

foreach ($branch in $selectedBranches) {
  foreach ($family in $selectedFamilies) {
    $payloads.Add((Get-FamilyPayload -Root $ExampleRoot -BranchCode $branch -Family $family)) | Out-Null
  }
}

$outlook = $null
if (-not $DryRun) {
  $outlook = New-Object -ComObject Outlook.Application
}

$replayStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$summary = New-Object System.Collections.Generic.List[object]

foreach ($payload in $payloads) {
  if (-not $DryRun) {
    $mail = $outlook.CreateItem(0)
    $mail.To = $payload.Recipient
    $mail.Subject = $payload.Subject
    $mail.Body = @"
Automated QFU example replay.

Replay stamp: $replayStamp
Branch: $($payload.BranchCode)
Family: $($payload.Family)
Source .eml: $([System.IO.Path]::GetFileName($payload.EmlPath))
Attachment: $($payload.AttachmentName)
"@
    [void]$mail.Attachments.Add($payload.AttachmentPath)
    $mail.Send()
  }

  $summary.Add([pscustomobject]@{
    branch = $payload.BranchCode
    family = $payload.Family
    recipient = $payload.Recipient
    subject = $payload.Subject
    attachment = $payload.AttachmentName
    source_eml = $payload.EmlPath
    source_attachment = $payload.AttachmentPath
    source_eml_last_write = $payload.EmlLastWriteTime
    source_attachment_last_write = $payload.AttachmentLastWriteTime
    production_replay_allowed = [bool]$AllowProductionReplay
    dry_run = [bool]$DryRun
    sent_at = (Get-Date).ToUniversalTime().ToString("o")
  }) | Out-Null

  if ($PauseSeconds -gt 0) {
    Start-Sleep -Seconds $PauseSeconds
  }
}

$report = [ordered]@{
  captured_at = (Get-Date).ToUniversalTime().ToString("o")
  example_root = $ExampleRoot
  replay_stamp = $replayStamp
  branches = @($selectedBranches)
  families = @($selectedFamilies)
  production_replay_allowed = [bool]$AllowProductionReplay
  dry_run = [bool]$DryRun
  runs = @($summary.ToArray())
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path "results" "example-branch-replay-send-summary-$replayStamp.json"
}

$savedPath = Write-Utf8Json -Path $OutputPath -Object $report

$report.runs |
  Sort-Object branch, family |
  Select-Object branch, family, recipient, subject, attachment, sent_at |
  Format-Table -AutoSize

Write-Host "OUTPUT_PATH=$savedPath"
