param(
  [string]$RepoRoot = "C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion",
  [string]$TaskName = "QFU-Freight-Inbox-Queue-Processor",
  [int]$IntervalMinutes = 15
)

$ErrorActionPreference = "Stop"

$processorScript = Join-Path $RepoRoot "scripts\process-freight-inbox-queue.ps1"
if (-not (Test-Path -LiteralPath $processorScript)) {
  throw "Processor script not found: $processorScript"
}

$taskCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$processorScript`""
$arguments = @(
  "/Create",
  "/SC", "MINUTE",
  "/MO", "$IntervalMinutes",
  "/TN", $TaskName,
  "/TR", $taskCommand,
  "/F"
)

& schtasks.exe @arguments | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "Failed to register scheduled task: $TaskName"
}

Write-Host "TASK_NAME=$TaskName"
Write-Host "TASK_COMMAND=$taskCommand"
