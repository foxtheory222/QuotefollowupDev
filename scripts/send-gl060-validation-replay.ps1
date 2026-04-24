param(
  [string]$RepoRoot = "C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion",
  [string]$AttachmentRoot = "C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\results\gl060-example-extracted-20260420",
  [string[]]$BranchCodes = @("4171", "4172", "4173"),
  [string]$Subject = "GL060 P&L report - Last month",
  [int]$PauseSeconds = 1,
  [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

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

  $json = $Object | ConvertTo-Json -Depth 20
  [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

$replayStamp = Get-Date -Format "yyyyMMdd-HHmmss"
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $RepoRoot "results\gl060-validation-replay-send-$replayStamp.json"
}

$outlook = New-Object -ComObject Outlook.Application
$namespace = $outlook.GetNamespace("MAPI")
$rows = New-Object System.Collections.Generic.List[object]

foreach ($branchCode in @($BranchCodes | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
  $attachmentName = "{0}-GL060 Report - Profit Center - CanSC - Publish.pdf" -f $branchCode
  $attachmentPath = Join-Path $AttachmentRoot $attachmentName
  if (-not (Test-Path -LiteralPath $attachmentPath)) {
    throw "Attachment not found: $attachmentPath"
  }

  $mail = $outlook.CreateItem(0)
  $recipientAddress = "{0}@applied.com" -f $branchCode
  $mail.To = $recipientAddress
  $mail.Subject = $Subject
  $mail.Body = @"
Automated GL060 ingress validation replay.

Replay stamp: $replayStamp
Branch: $branchCode
Attachment: $attachmentName
"@
  $resolvedRecipient = $namespace.CreateRecipient($recipientAddress)
  [void]$resolvedRecipient.Resolve()
  $resolvedEntry = if ($resolvedRecipient.Resolved) { $resolvedRecipient.AddressEntry } else { $null }
  [void]$mail.Attachments.Add($attachmentPath)
  $mail.Send()

  $rows.Add([pscustomobject]@{
      branch_code = $branchCode
      recipient = $recipientAddress
      subject = $Subject
      attachment = $attachmentName
      attachment_path = $attachmentPath
      recipient_resolved = [bool]$resolvedRecipient.Resolved
      resolved_name = if ($resolvedEntry) { [string]$resolvedEntry.Name } else { $null }
      resolved_type = if ($resolvedEntry) { [string]$resolvedEntry.Type } else { $null }
      resolved_address = if ($resolvedEntry) { [string]$resolvedEntry.Address } else { $null }
      replay_stamp = $replayStamp
      sent_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    }) | Out-Null

  if ($PauseSeconds -gt 0) {
    Start-Sleep -Seconds $PauseSeconds
  }
}

$report = [pscustomobject]@{
  captured_at = (Get-Date).ToUniversalTime().ToString("o")
  replay_stamp = $replayStamp
  attachment_root = $AttachmentRoot
  rows = @($rows.ToArray())
}

Write-Utf8Json -Path $OutputPath -Object $report

$report.rows |
  Select-Object branch_code, recipient, recipient_resolved, resolved_name, resolved_type, attachment, sent_at_utc |
  Format-Table -AutoSize

Write-Host "OUTPUT_PATH=$OutputPath"
