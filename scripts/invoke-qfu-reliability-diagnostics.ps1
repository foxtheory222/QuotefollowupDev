param(
  [string]$TargetEnvironmentUrl = "https://regionaloperationshub.crm.dynamics.com",
  [string]$Username = "smcfarlane@applied.com",
  [string]$OutputMarkdown = "VERIFICATION\\qfu-reliability-diagnostics.md"
)

$ErrorActionPreference = "Stop"

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

$root = Get-Location
$healthScript = Join-Path $root "scripts\\run-live-qfu-health-check.ps1"
$outputPath = if ([System.IO.Path]::IsPathRooted($OutputMarkdown)) { $OutputMarkdown } else { Join-Path $root $OutputMarkdown }

& powershell -NoProfile -ExecutionPolicy Bypass -File $healthScript -TargetEnvironmentUrl $TargetEnvironmentUrl -Username $Username | Out-Null

$generatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$lines = @(
  "# QFU Reliability Diagnostics",
  "",
  "- Generated: $generatedAt",
  "- Environment: $TargetEnvironmentUrl",
  "",
  "## Entry Point",
  "",
  "- Run ``powershell -NoProfile -ExecutionPolicy Bypass -File scripts\\invoke-qfu-reliability-diagnostics.ps1``",
  "- This wrapper executes the live operational audit, overdue-backorder consistency audit, overdue-day repair plan, duplicate repair plan, lifecycle backfill plan, budget lineage verification, flow-health check, margin snapshot integrity audit, and CSSR overdue order-count audit.",
  "",
  "## Primary Artifacts",
  "",
  "- ``VERIFICATION\\operational-current-state-audit.md``",
  "- ``VERIFICATION\\overdue-backorder-consistency.md``",
  "- ``VERIFICATION\\backorder-overdue-day-repair.md``",
  "- ``results\\live-operational-duplicate-repair.json``",
  "- ``results\\live-operational-lifecycle-backfill.json``",
  "- ``VERIFICATION\\budget-lineage-checks.md``",
  "- ``results\\southern-alberta-flow-health-*.json``",
  "- ``VERIFICATION\\margin-snapshot-integrity.md``",
  "- ``VERIFICATION\\cssr-overdue-order-counts.md``",
  "- ``VERIFICATION\\live-browser-verification.md``",
  "- ``VERIFICATION\\live-browser-verification.json``",
  "- ``VERIFICATION\\live-health-check-summary.md``",
  "",
  "## Five-Minute Triage",
  "",
  "1. Open ``VERIFICATION\\operational-current-state-audit.md`` and confirm duplicate-group counts for qfu_quote, qfu_backorder, qfu_deliverynotpgi, and qfu_marginexception.",
  "2. Open ``VERIFICATION\\overdue-backorder-consistency.md`` and confirm overdue counts are being driven by ``qfu_daysoverdue`` rather than raw on-time date drift.",
  "3. Open ``VERIFICATION\\backorder-overdue-day-repair.md`` to see whether active ZBO rows have stale derived overdue days from a controlled seed or replay.",
  "4. Open ``results\\live-operational-duplicate-repair.json`` to see exactly which row wins per canonical key before any cleanup is applied.",
  "5. Open ``results\\live-operational-lifecycle-backfill.json`` and confirm qfu_quote, qfu_backorder, and qfu_deliverynotpgi no longer rely on null lifecycle fields.",
  "6. Open ``VERIFICATION\\budget-lineage-checks.md`` and confirm current-month budget actual/target lineage is not falling back to stale summary rows.",
  "7. Open the latest ``results\\southern-alberta-flow-health-*.json`` and confirm whether the latest source family run came from a real flow or a controlled seed/replay.",
  "8. Open ``VERIFICATION\\margin-snapshot-integrity.md`` and confirm the latest branch margin snapshot has zero duplicate billing-doc/review groups before trusting the branch and analytics margin panels.",
  "9. Open ``VERIFICATION\\cssr-overdue-order-counts.md`` and confirm where overdue line counts diverge from distinct overdue order counts before changing CSSR or owner-facing backlog widgets.",
  "10. Open ``VERIFICATION\\live-browser-verification.md`` and confirm the live portal is actually serving the deduped branch config, distinct-order CSSR leaderboard, and latest-snapshot abnormal-margin view.",
  "11. If the overdue-day repair plan shows stale derived days, run ``powershell -NoProfile -ExecutionPolicy Bypass -File scripts\\repair-live-backorder-overdue-days.ps1 -Apply`` and then rerun ``scripts\\refresh-live-branch-daily-summaries.ps1 -Apply``.",
  "12. If duplicates, lifecycle gaps, or stale imports are present, repair live data first, then rerun this wrapper and confirm the artifacts normalize."
)

Write-Utf8File -Path $outputPath -Content ($lines -join [Environment]::NewLine)

Write-Host "OUTPUT_PATH=$outputPath"
