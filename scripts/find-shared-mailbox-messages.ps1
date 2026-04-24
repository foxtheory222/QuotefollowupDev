param(
  [string]$MailboxAddress,
  [string]$SubjectContains = "",
  [datetime]$ReceivedAfter = [datetime]::MinValue,
  [int]$TopCount = 10,
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

if ([string]::IsNullOrWhiteSpace($MailboxAddress)) {
  throw "MailboxAddress is required."
}

$outlook = New-Object -ComObject Outlook.Application
$namespace = $outlook.GetNamespace("MAPI")
$recipient = $namespace.CreateRecipient($MailboxAddress)
[void]$recipient.Resolve()
if (-not $recipient.Resolved) {
  throw "Mailbox recipient did not resolve: $MailboxAddress"
}

$inbox = $namespace.GetSharedDefaultFolder($recipient, 6)
$items = $inbox.Items
$items.Sort("[ReceivedTime]", $true)

$candidateItems = $items
if ($ReceivedAfter -gt [datetime]::MinValue) {
  $receivedAfterLocal = $ReceivedAfter.ToLocalTime().ToString("MM/dd/yyyy hh:mm tt")
  $candidateItems = $items.Restrict("[ReceivedTime] >= '" + $receivedAfterLocal + "'")
  $candidateItems.Sort("[ReceivedTime]", $true)
}

$rows = New-Object System.Collections.Generic.List[object]
for ($index = 1; $index -le $candidateItems.Count; $index += 1) {
  if ($rows.Count -ge $TopCount) {
    break
  }

  $item = $candidateItems.Item($index)
  if ($null -eq $item -or $item.Class -ne 43) {
    continue
  }

  $subject = [string]$item.Subject
  if (-not [string]::IsNullOrWhiteSpace($SubjectContains) -and $subject -notlike ("*" + $SubjectContains + "*")) {
    continue
  }

  $attachments = New-Object System.Collections.Generic.List[object]
  for ($attachmentIndex = 1; $attachmentIndex -le $item.Attachments.Count; $attachmentIndex += 1) {
    $attachment = $item.Attachments.Item($attachmentIndex)
    $attachments.Add([pscustomobject]@{
        name = [string]$attachment.FileName
      }) | Out-Null
  }

  $senderEmail = $null
  try {
    $senderEmail = [string]$item.SenderEmailAddress
  } catch {
  }

  $receivedTime = $null
  try {
    $receivedTime = ([datetime]$item.ReceivedTime).ToString("o")
  } catch {
  }

  $rows.Add([pscustomobject]@{
      subject = $subject
      sender = [string]$item.SenderName
      sender_email = $senderEmail
      received_time = $receivedTime
      unread = [bool]$item.UnRead
      attachment_count = [int]$item.Attachments.Count
      attachments = @($attachments.ToArray())
    }) | Out-Null
}

$report = [pscustomobject]@{
  captured_at = (Get-Date).ToUniversalTime().ToString("o")
  mailbox = $MailboxAddress
  subject_contains = $SubjectContains
  received_after = if ($ReceivedAfter -gt [datetime]::MinValue) { $ReceivedAfter.ToUniversalTime().ToString("o") } else { $null }
  rows = @($rows.ToArray())
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $OutputPath = Join-Path (Join-Path (Get-Location) "results") ("shared-mailbox-find-$stamp.json")
}

Write-Utf8Json -Path $OutputPath -Object $report

$report.rows |
  Select-Object subject, sender, received_time, attachment_count |
  Format-Table -AutoSize

Write-Host "OUTPUT_PATH=$OutputPath"
