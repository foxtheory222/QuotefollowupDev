param(
  [string]$OutputJson = "results\\local-task-health.json",
  [string]$OutputMarkdown = "VERIFICATION\\local-task-health.md"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

$taskSpecs = @(
  [pscustomobject]@{
    task_name = "QFU-Freight-Inbox-Queue-Processor"
    purpose = "Clears queued freight raw documents into processed or duplicate ingestion states."
  },
  [pscustomobject]@{
    task_name = "QFU-Branch-Daily-Summary-Refresh"
    purpose = "Keeps qfu_branchdailysummary aligned with live qfu_budget and current-state rows."
  }
)

function Ensure-Directory {
  param([string]$Path)

  if (-not [string]::IsNullOrWhiteSpace($Path) -and -not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Resolve-RepoPath {
  param([string]$Path)

  if ([System.IO.Path]::IsPathRooted($Path)) {
    return $Path
  }

  return Join-Path $RepoRoot $Path
}

function Write-Utf8File {
  param(
    [string]$Path,
    [string]$Content
  )

  $resolved = Resolve-RepoPath -Path $Path
  $directory = Split-Path -Parent $resolved
  if ($directory) {
    Ensure-Directory -Path $directory
  }

  [System.IO.File]::WriteAllText($resolved, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Format-DateTimeValue {
  param([object]$Value)

  if ($null -eq $Value) {
    return ""
  }

  try {
    return ([datetime]$Value).ToString("yyyy-MM-dd HH:mm:ss")
  } catch {
    return ""
  }
}

$rows = foreach ($taskSpec in $taskSpecs) {
  $task = Get-ScheduledTask -TaskName $taskSpec.task_name -ErrorAction SilentlyContinue
  $info = if ($task) { Get-ScheduledTaskInfo -TaskName $taskSpec.task_name -ErrorAction SilentlyContinue } else { $null }
  $exists = $null -ne $task
  $enabled = if ($task -and $task.Settings) { [bool]$task.Settings.Enabled } else { $false }
  $state = if ($task) { [string]$task.State } else { "missing" }
  $lastTaskResult = if ($info) { [int]$info.LastTaskResult } else { $null }
  $lastRunTime = if ($info) { Format-DateTimeValue -Value $info.LastRunTime } else { "" }
  $nextRunTime = if ($info) { Format-DateTimeValue -Value $info.NextRunTime } else { "" }
  $issues = New-Object System.Collections.Generic.List[string]

  if (-not $exists) {
    $issues.Add("missing") | Out-Null
  } elseif (-not $enabled -or $state -eq "Disabled") {
    $issues.Add("disabled") | Out-Null
  } elseif (
    $state -ne "Running" -and
    $null -ne $lastTaskResult -and
    $lastTaskResult -ne 0 -and
    $lastRunTime -and
    $lastRunTime -ne "1999-11-30 00:00:00"
  ) {
    $issues.Add("last-result=$lastTaskResult") | Out-Null
  }

  [pscustomobject]@{
    task_name = $taskSpec.task_name
    purpose = $taskSpec.purpose
    exists = $exists
    enabled = $enabled
    state = $state
    last_run_time = $lastRunTime
    next_run_time = $nextRunTime
    last_task_result = if ($null -ne $lastTaskResult) { [string]$lastTaskResult } else { "" }
    issues = @($issues.ToArray())
  }
}

$issueCount = @($rows | Where-Object { @($_.issues).Count -gt 0 }).Count
$report = [pscustomobject]@{
  generated_at = (Get-Date).ToString("o")
  issue_count = $issueCount
  tasks = @($rows)
}

$markdown = @(
  "# Local QFU Task Health",
  "",
  "- Generated: $($report.generated_at)",
  "- Tasks checked: $(@($rows).Count)",
  "- Tasks with issues: $issueCount",
  "",
  "| Task | Exists | Enabled | State | Last Run | Next Run | Result | Issues |",
  "| --- | --- | --- | --- | --- | --- | --- | --- |"
)

foreach ($row in $rows) {
  $markdown += "| $($row.task_name) | $($row.exists) | $($row.enabled) | $($row.state) | $($row.last_run_time) | $($row.next_run_time) | $($row.last_task_result) | $((@($row.issues) -join ', ')) |"
}

Write-Utf8File -Path $OutputJson -Content ($report | ConvertTo-Json -Depth 20)
Write-Utf8File -Path $OutputMarkdown -Content ($markdown -join [Environment]::NewLine)

Write-Host "JSON_PATH=$(Resolve-RepoPath -Path $OutputJson)"
Write-Host "MARKDOWN_PATH=$(Resolve-RepoPath -Path $OutputMarkdown)"
