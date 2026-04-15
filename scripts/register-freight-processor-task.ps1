param(
  [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
  [string]$TargetEnvironmentUrl = $env:QFU_TARGET_ENVIRONMENT_URL,
  [string]$Username = "smcfarlane@applied.com",
  [string]$TaskName = "QFU-Freight-Inbox-Queue-Processor",
  [int]$IntervalMinutes = 15,
  [switch]$StartImmediately
)

$ErrorActionPreference = "Stop"

$processorScript = Join-Path $RepoRoot "scripts\process-freight-inbox-queue.ps1"
if (-not (Test-Path -LiteralPath $processorScript)) {
  throw "Processor script not found: $processorScript"
}

if ([string]::IsNullOrWhiteSpace($TargetEnvironmentUrl)) {
  throw "Provide -TargetEnvironmentUrl or set QFU_TARGET_ENVIRONMENT_URL before registering the freight processor task."
}

$taskCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$processorScript`" -RepoRoot `"$RepoRoot`" -TargetEnvironmentUrl `"$TargetEnvironmentUrl`" -Username `"$Username`""
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

& schtasks.exe /Change /TN $TaskName /ENABLE | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "Failed to enable scheduled task: $TaskName"
}

if ($StartImmediately) {
  & schtasks.exe /Run /TN $TaskName | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to start scheduled task: $TaskName"
  }
}

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

Write-Host "TASK_NAME=$TaskName"
Write-Host "TASK_COMMAND=$taskCommand"
Write-Host "TASK_STATE=$(if ($task) { $task.State } else { 'missing' })"
Write-Host "TASK_START_IMMEDIATELY=$([bool]$StartImmediately)"
