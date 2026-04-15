param(
  [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
  [string]$TargetEnvironmentUrl = $env:QFU_TARGET_ENVIRONMENT_URL,
  [string]$Username = "smcfarlane@applied.com",
  [string]$TaskName = "QFU-Branch-Daily-Summary-Refresh",
  [int]$IntervalMinutes = 15,
  [switch]$StartImmediately
)

$ErrorActionPreference = "Stop"

$refreshScript = Join-Path $RepoRoot "scripts\refresh-live-branch-daily-summaries.ps1"
if (-not (Test-Path -LiteralPath $refreshScript)) {
  throw "Refresh script not found: $refreshScript"
}

if ([string]::IsNullOrWhiteSpace($TargetEnvironmentUrl)) {
  throw "Provide -TargetEnvironmentUrl or set QFU_TARGET_ENVIRONMENT_URL before registering the branch summary refresh task."
}

$taskCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$refreshScript`" -Apply -TargetEnvironmentUrl `"$TargetEnvironmentUrl`" -Username `"$Username`""
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
