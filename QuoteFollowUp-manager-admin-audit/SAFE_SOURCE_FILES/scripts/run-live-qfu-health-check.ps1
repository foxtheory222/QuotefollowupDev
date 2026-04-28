param(
  [string]$TargetEnvironmentUrl = "<URL>
  [string]$Username = "<EMAIL>"
)

$ErrorActionPreference = "Stop"

$root = Get-Location
$auditScript = Join-Path $root "scripts\audit-live-operational-current-state.ps1"
$overdueAuditScript = Join-Path $root "scripts\audit-live-overdue-backorder-consistency.ps1"
$overdueRepairScript = Join-Path $root "scripts\repair-live-backorder-overdue-days.ps1"
$repairPlanScript = Join-Path $root "scripts\repair-live-operational-duplicates.ps1"
$lifecycleBackfillScript = Join-Path $root "scripts\backfill-live-operational-lifecycle.ps1"
$budgetScript = Join-Path $root "scripts\verify-live-budget-lineage.ps1"
$flowScript = Join-Path $root "scripts\check-southern-alberta-flow-health.ps1"
$opsDailyFreshnessScript = Join-Path $root "scripts\check-live-sa1300-opsdaily-freshness.ps1"
$marginSnapshotScript = Join-Path $root "scripts\audit-live-margin-snapshot-integrity.ps1"
$cssrOrderCountScript = Join-Path $root "scripts\audit-live-cssr-overdue-order-counts.ps1"
$taskHealthScript = Join-Path $root "scripts\check-local-qfu-task-health.ps1"
$summaryPath = Join-Path $root "VERIFICATION\live-health-check-summary.md"

function Ensure-Directory {
  param([string]$Path)

  if (-not [string]::IsNullOrWhiteSpace($Path) -and -not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
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

$steps = @()

& powershell -NoProfile -ExecutionPolicy Bypass -File $auditScript -TargetEnvironmentUrl $TargetEnvironmentUrl -Username $Username
$steps += [pscustomobject]@{ name = "operational current-state audit"; path = "VERIFICATION\\operational-current-state-audit.md" }

& powershell -NoProfile -ExecutionPolicy Bypass -File $overdueAuditScript -TargetEnvironmentUrl $TargetEnvironmentUrl -Username $Username
$steps += [pscustomobject]@{ name = "overdue backorder consistency audit"; path = "VERIFICATION\\overdue-backorder-consistency.md" }

& powershell -NoProfile -ExecutionPolicy Bypass -File $overdueRepairScript -TargetEnvironmentUrl $TargetEnvironmentUrl -Username $Username
$steps += [pscustomobject]@{ name = "backorder overdue day repair plan"; path = "VERIFICATION\\backorder-overdue-day-repair.md" }

& powershell -NoProfile -ExecutionPolicy Bypass -File $repairPlanScript -TargetEnvironmentUrl $TargetEnvironmentUrl -Username $Username
$steps += [pscustomobject]@{ name = "operational duplicate repair plan"; path = "results\\live-operational-duplicate-repair.json" }

& powershell -NoProfile -ExecutionPolicy Bypass -File $lifecycleBackfillScript -TargetEnvironmentUrl $TargetEnvironmentUrl -Username $Username
$steps += [pscustomobject]@{ name = "operational lifecycle backfill plan"; path = "results\\live-operational-lifecycle-backfill.json" }

& powershell -NoProfile -ExecutionPolicy Bypass -File $budgetScript
$steps += [pscustomobject]@{ name = "budget lineage check"; path = "VERIFICATION\\budget-lineage-checks.md" }

& powershell -NoProfile -ExecutionPolicy Bypass -File $flowScript -TargetEnvironmentUrl $TargetEnvironmentUrl -Username $Username
$steps += [pscustomobject]@{ name = "flow health check"; path = "results\\southern-alberta-flow-health-*.json" }

& powershell -NoProfile -ExecutionPolicy Bypass -File $opsDailyFreshnessScript -TargetEnvironmentUrl $TargetEnvironmentUrl -Username $Username
$steps += [pscustomobject]@{ name = "SA1300 ops daily freshness check"; path = "VERIFICATION\\sa1300-opsdaily-freshness.md" }

& powershell -NoProfile -ExecutionPolicy Bypass -File $marginSnapshotScript -TargetEnvironmentUrl $TargetEnvironmentUrl -Username $Username
$steps += [pscustomobject]@{ name = "margin snapshot integrity audit"; path = "VERIFICATION\\margin-snapshot-integrity.md" }

& powershell -NoProfile -ExecutionPolicy Bypass -File $cssrOrderCountScript -TargetEnvironmentUrl $TargetEnvironmentUrl -Username $Username
$steps += [pscustomobject]@{ name = "CSSR overdue order-count audit"; path = "VERIFICATION\\cssr-overdue-order-counts.md" }

& powershell -NoProfile -ExecutionPolicy Bypass -File $taskHealthScript
$steps += [pscustomobject]@{ name = "local scheduled task health"; path = "VERIFICATION\\local-task-health.md" }

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Live QFU Health Check") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("- Generated: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))") | Out-Null
$lines.Add("- Environment: $TargetEnvironmentUrl") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("## Included Checks") | Out-Null
$lines.Add("") | Out-Null
foreach ($step in $steps) {
  $lines.Add("- $($step.name): ``$($step.path)``") | Out-Null
}
$lines.Add("") | Out-Null
$lines.Add("Run command: ``powershell -NoProfile -ExecutionPolicy Bypass -File scripts\\run-live-qfu-health-check.ps1``") | Out-Null

Write-Utf8File -Path $summaryPath -Content ($lines -join [Environment]::NewLine)

Write-Host "SUMMARY_PATH=$summaryPath"
