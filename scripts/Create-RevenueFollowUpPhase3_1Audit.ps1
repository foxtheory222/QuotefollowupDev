param(
    [string]$WorkspaceRoot = (Get-Location).Path,
    [string]$AuditRootName = "_phase3_1_alias_apply_audit",
    [string]$ZipName = "QuoteFollowUp-phase-3-1-alias-mapping-apply-hardening-audit.zip"
)

$ErrorActionPreference = "Stop"

$workspace = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
$auditRoot = Join-Path $workspace $AuditRootName
$zipPath = Join-Path $workspace $ZipName
$durableRepo = Join-Path $workspace "tmp-github-QuoteFollowUp"

if (-not $auditRoot.StartsWith($workspace, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Audit root resolved outside workspace: $auditRoot"
}

if (Test-Path -LiteralPath $auditRoot) {
    $resolvedAuditRoot = (Resolve-Path -LiteralPath $auditRoot).Path
    if (-not $resolvedAuditRoot.StartsWith($workspace, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove audit root outside workspace: $resolvedAuditRoot"
    }
    Remove-Item -LiteralPath $resolvedAuditRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $auditRoot -Force | Out-Null

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
function Write-TextFile {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Content
    )
    $path = Join-Path $auditRoot $RelativePath
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($path, $Content.TrimEnd() + [Environment]::NewLine, $utf8NoBom)
}

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Get-GitValue {
    param([string[]]$Arguments)
    if (-not (Test-Path -LiteralPath (Join-Path $durableRepo ".git"))) {
        return ""
    }
    $output = & git -C $durableRepo @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) { return "" }
    return ($output -join [Environment]::NewLine).Trim()
}

function YesNo {
    param([bool]$Value)
    if ($Value) { return "yes" }
    return "no"
}

function Copy-SafeFile {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$DestinationRoot
    )
    $source = Join-Path $workspace $RelativePath
    $destination = Join-Path $DestinationRoot $RelativePath
    $destinationDir = Split-Path -Parent $destination
    if (-not (Test-Path -LiteralPath $destinationDir)) {
        New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    }
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

$summaryPath = Join-Path $workspace "results\phase3-1-alias-mapping\phase3-1-alias-mapping-summary.json"
$dryRunPath = Join-Path $workspace "results\phase3-1-resolver-dryrun-20260427.json"
$dryRunReportPath = Join-Path $workspace "results\phase3-1-resolver-dryrun-20260427.md"
$summary = Read-JsonFile -Path $summaryPath
$dryRun = Read-JsonFile -Path $dryRunPath
$timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss zzz")

$branch = Get-GitValue -Arguments @("rev-parse", "--abbrev-ref", "HEAD")
$commitHash = Get-GitValue -Arguments @("rev-parse", "HEAD")
$commitMessage = Get-GitValue -Arguments @("log", "-1", "--pretty=%s")
$gitStatus = Get-GitValue -Arguments @("status", "--short")
$hasUncommitted = -not [string]::IsNullOrWhiteSpace($gitStatus)
if ([string]::IsNullOrWhiteSpace($gitStatus)) { $gitStatusDisplay = "clean" } else { $gitStatusDisplay = $gitStatus }

$keyRows = foreach ($key in $summary.alternateKeys) {
    $attrs = @($key.keyAttributes) -join ", "
    "| $($key.table) | $($key.keyName) | $(YesNo ([bool]$key.found)) | $($key.entityKeyIndexStatus) | $attrs |"
}

$countRows = foreach ($property in $dryRun.counts.PSObject.Properties) {
    "| $($property.Name) | $($property.Value) |"
}

$currentRepoState = @"
# Current Repo State

Timestamp: $timestamp

Workspace root: $workspace

Durable repo copy: $durableRepo

Working operations folder is not the Git repository root. Long-lived source files were mirrored into the durable repo copy.

| Item | Value |
| --- | --- |
| Current branch | $branch |
| Latest commit hash | $commitHash |
| Latest commit message | $commitMessage |
| Uncommitted changes | $(YesNo $hasUncommitted) |

## Git Status Summary

~~~text
$gitStatusDisplay
~~~
"@
Write-TextFile -RelativePath "CURRENT_REPO_STATE.md" -Content $currentRepoState

$phaseStatus = @"
# Phase Status

Current phase: Phase 3.1 - alias mapping prep and apply-mode hardening before controlled resolver apply.

Execution mode: dry-run only. Apply mode was not run.

## Functional Now

- Live dev solution, app, required tables, and Phase 3 keys were rechecked.
- Current staff, staff alias, and branch membership counts were audited.
- Alias review and import templates were generated.
- Resolver apply mode was hardened for source links, status preservation, owner preservation, next follow-up preservation, sticky note preservation, and action history preservation.
- Resolver dry-run still returns the same selection counts after hardening.
- No solution export was required because Phase 3.1 changed scripts, docs, templates, and dry-run evidence only; no Dataverse metadata changed.

## Not Functional Yet

- No staff or alias mappings exist yet.
- Apply mode has not created work items or assignment exceptions.
- No broad apply run has been performed.
- No alerts, daily digests, My Work page, Manager Panel, GM Review, or security roles are active.

## Next

- Human review of alias templates.
- Enter or import confirmed staff, alias, and branch membership data.
- Rerun dry-run and confirm resolved owner counts improve.
- Pick one small dev apply scope only after mapping review.

## Still Left

- Controlled apply-mode validation.
- Resolver automation trigger design.
- Work item action rollup automation.
- Alert and digest phase.
- Security roles and access model.

## Blocking Questions

- Which unresolved AM Number aliases map to which staff records.
- Which unresolved CSSR Number aliases map to which staff records.
- Whether the 45 line-only quote groups should be included by a later union-of-header-and-line resolver design.
- Which branch or quote group should be used for first controlled apply.
"@
Write-TextFile -RelativePath "PHASE_STATUS.md" -Content $phaseStatus

$liveState = @"
# Live State Recheck

Environment: $($summary.environmentUrl)

| Check | Result |
| --- | --- |
| Solution found | $(YesNo ([bool]$summary.solutionFound)) |
| App found | $(YesNo ([bool]$summary.appFound)) |
| Required tables found | yes |
| Alternate/replacement keys active | $(YesNo (@($summary.alternateKeys | Where-Object { -not $_.active }).Count -eq 0)) |
| Active staff records | $($summary.liveCounts.activeStaffRecords) |
| Active staff alias records | $($summary.liveCounts.activeStaffAliasRecords) |
| Active AM Number aliases | $($summary.liveCounts.activeAmNumberAliases) |
| Active CSSR Number aliases | $($summary.liveCounts.activeCssrNumberAliases) |
| Active branch memberships | $($summary.liveCounts.activeBranchMemberships) |
| Duplicate alias mapping groups | $($summary.liveCounts.duplicateAliasMappingGroups) |
| Multi-staff same-scope alias groups | $($summary.liveCounts.multiStaffSameScopeAliasGroups) |
| Active staff missing primary email | $($summary.liveCounts.activeStaffMissingPrimaryEmail) |
| Active staff missing Dataverse systemuser | $($summary.liveCounts.activeStaffMissingSystemUser) |

## Key Status

| Table | Key | Found | Index Status | Attributes |
| --- | --- | --- | --- | --- |
$($keyRows -join [Environment]::NewLine)
"@
Write-TextFile -RelativePath "LIVE_STATE_RECHECK.md" -Content $liveState

$aliasMappingReview = @"
# Alias Mapping Review

No mappings were guessed.

| Item | Count |
| --- | ---: |
| Unresolved alias rows requiring human mapping | $($summary.aliasMapping.unresolvedAliasRows) |
| Unresolved AM Number rows | $($summary.aliasMapping.unresolvedAmNumberRows) |
| Unresolved CSSR Number rows | $($summary.aliasMapping.unresolvedCssrNumberRows) |
| Invalid alias rows requiring source/manager review | $($summary.aliasMapping.invalidAliasRows) |
| Guessed mappings | $($summary.aliasMapping.guessedMappings) |

Generated templates:

- ALIAS_MAPPING_TEMPLATES/unresolved-staff-alias-review.csv
- ALIAS_MAPPING_TEMPLATES/invalid-alias-exceptions-review.csv
- ALIAS_MAPPING_TEMPLATES/qfu_staff-import-template.csv
- ALIAS_MAPPING_TEMPLATES/qfu_staffalias-import-template.csv
- ALIAS_MAPPING_TEMPLATES/qfu_branchmembership-import-template.csv

Invalid aliases are excluded from staff mapping suggestions. Names are included only as display/fallback review context and are not trusted for automatic routing.
"@
Write-TextFile -RelativePath "ALIAS_MAPPING_REVIEW.md" -Content $aliasMappingReview

$applyHardening = @"
# Apply Mode Hardening Review

Apply mode was not run.

| Hardening Item | Status |
| --- | --- |
| Assignment exceptions include source document number | implemented |
| Assignment exceptions include source external key | already implemented |
| Assignment exceptions link source quote when available | implemented |
| Assignment exceptions link representative source quote line when available | implemented |
| Assignment exceptions link newly created work item where possible | implemented |
| Existing work item status preserved | implemented |
| Existing owners preserved | implemented |
| Sticky notes preserved | implemented |
| Action history preserved | implemented |
| Existing next follow-up preserved | implemented |
| Existing last followed up / last action preserved | implemented |
| Existing completed attempts preserved | implemented |

If Dataverse ever creates a work item but does not return qfu_workitemid in apply mode, the resolver throws and stops rather than writing unlinked assignment exceptions.
"@
Write-TextFile -RelativePath "APPLY_MODE_HARDENING_REVIEW.md" -Content $applyHardening

$headerLine = @"
# Header Line Completeness Review

| Item | Count |
| --- | ---: |
| Quote header groups | $($summary.headerLineCompleteness.quoteHeaderGroups) |
| Quote line groups | $($summary.headerLineCompleteness.quoteLineGroups) |
| Line groups without header | $($summary.headerLineCompleteness.lineGroupsWithoutHeader) |
| Header groups without lines | $($summary.headerLineCompleteness.headerGroupsWithoutLines) |

Recommendation: $($summary.headerLineCompleteness.recommendation)
"@
Write-TextFile -RelativePath "HEADER_LINE_COMPLETENESS_REVIEW.md" -Content $headerLine

$dryRunResults = @"
# Dry-Run Results

Dry-run completed: yes

Apply mode was not run.

Alerts sent: $($dryRun.counts.alertsSent)

Apply-mode hardening changed write safety only. It did not change dry-run selection counts.

## Counts

| Metric | Count |
| --- | ---: |
$($countRows -join [Environment]::NewLine)

## Sanitized Sample Work Items

~~~json
$(($dryRun.sampleWorkItemPayloads | ConvertTo-Json -Depth 20))
~~~

## Sanitized Sample Assignment Exceptions

~~~json
$(($dryRun.sampleExceptionPayloads | ConvertTo-Json -Depth 20))
~~~

No customer names are included in the sample payloads. Source document values are represented as hashes.
"@
Write-TextFile -RelativePath "DRY_RUN_RESULTS.md" -Content $dryRunResults

$applyResults = @"
# Apply Mode Results

Apply mode was not run.

| Item | Value |
| --- | --- |
| Scope | not run |
| Work items created | 0 |
| Work items updated | 0 |
| Assignment exceptions created | 0 |
| Assignment exceptions updated | 0 |
| Alerts sent | 0 |

No tiny smoke test was run because dry-run and static apply-mode hardening were sufficient for Phase 3.1.
"@
Write-TextFile -RelativePath "APPLY_MODE_RESULTS.md" -Content $applyResults

$adminWorkflow = @"
# Admin Exception Workflow Review

Admins should use the generated templates and the Admin Panel MVP together.

1. Review unresolved-staff-alias-review.csv.
2. Confirm staff identity outside the resolver.
3. Create or import staff records only for confirmed staff.
4. Create or import staff alias rows only after confirming the staff record.
5. Create branch memberships only after confirming branch and role.
6. Do not create mappings for invalid aliases from invalid-alias-exceptions-review.csv.
7. Rerun dry-run after mappings are entered.
8. Confirm TSR/CSSR resolved counts improve before any apply mode.

Missing TSR Alias uses AM Number and maps to a TSR staff identity. Missing CSSR Alias uses CSSR Number and maps to a CSSR staff identity. There is no SSR role.

No alerts or daily digests are sent in Phase 3.1.
"@
Write-TextFile -RelativePath "ADMIN_EXCEPTION_WORKFLOW_REVIEW.md" -Content $adminWorkflow

$openDecisions = @"
# Open Decisions

- Confirm actual staff for each unresolved AM Number.
- Confirm actual staff for each unresolved CSSR Number.
- Decide whether branch-scoped aliases should remain branch-scoped or whether any should intentionally become global.
- Decide how to handle the 45 quote line groups without matching quote headers in a later resolver design.
- Choose first controlled dev apply scope.
- Choose later action rollup implementation pattern.
- Confirm future alert/digest modes before the alert phase.
"@
Write-TextFile -RelativePath "OPEN_DECISIONS.md" -Content $openDecisions

$templatesRoot = Join-Path $auditRoot "ALIAS_MAPPING_TEMPLATES"
New-Item -ItemType Directory -Path $templatesRoot -Force | Out-Null
$templateFiles = @(
    "unresolved-staff-alias-review.csv",
    "invalid-alias-exceptions-review.csv",
    "qfu_staff-import-template.csv",
    "qfu_staffalias-import-template.csv",
    "qfu_branchmembership-import-template.csv"
)
foreach ($file in $templateFiles) {
    Copy-Item -LiteralPath (Join-Path $workspace "results\phase3-1-alias-mapping\$file") -Destination (Join-Path $templatesRoot $file) -Force
}

$safeRoot = Join-Path $auditRoot "SAFE_SOURCE_FILES"
New-Item -ItemType Directory -Path $safeRoot -Force | Out-Null
$safeFiles = @(
    "docs\revenue-follow-up-phase-3-1-alias-mapping-and-apply-hardening.md",
    "docs\revenue-follow-up-admin-exception-workflow.md",
    "docs\revenue-follow-up-resolver-apply-safety.md",
    "scripts\Invoke-RevenueFollowUpPhase3Resolver.ps1",
    "scripts\New-RevenueFollowUpPhase3_1AliasMappingPrep.ps1",
    "scripts\Create-RevenueFollowUpPhase3_1Audit.ps1",
    "results\phase3-1-resolver-dryrun-20260427.json",
    "results\phase3-1-resolver-dryrun-20260427.md",
    "results\phase3-1-alias-mapping\phase3-1-alias-mapping-summary.json",
    "results\phase3-1-alias-mapping\header-line-completeness.json",
    "results\phase3-1-alias-mapping\unresolved-staff-alias-review.csv",
    "results\phase3-1-alias-mapping\invalid-alias-exceptions-review.csv",
    "results\phase3-1-alias-mapping\qfu_staff-import-template.csv",
    "results\phase3-1-alias-mapping\qfu_staffalias-import-template.csv",
    "results\phase3-1-alias-mapping\qfu_branchmembership-import-template.csv"
)
foreach ($relative in $safeFiles) {
    Copy-SafeFile -RelativePath $relative -DestinationRoot $safeRoot
}

$manifestEntries = @(
    "| File | Why It Matters |",
    "| --- | --- |"
)
$auditFiles = Get-ChildItem -LiteralPath $auditRoot -Recurse -File | Sort-Object FullName
foreach ($file in $auditFiles) {
    $relativePath = $file.FullName.Substring($auditRoot.Length + 1).Replace("\", "/")
    if ($relativePath -eq "MANIFEST.md") { continue }
    $reason = switch -Wildcard ($relativePath) {
        "CURRENT_REPO_STATE.md" { "Repo and workspace state at audit time."; break }
        "PHASE_STATUS.md" { "Phase 3.1 status and next steps."; break }
        "LIVE_STATE_RECHECK.md" { "Live Dataverse state and key recheck."; break }
        "ALIAS_MAPPING_REVIEW.md" { "Alias review summary."; break }
        "ALIAS_MAPPING_TEMPLATES/*" { "Generated alias/staff/membership review template."; break }
        "APPLY_MODE_HARDENING_REVIEW.md" { "Resolver apply-mode safety evidence."; break }
        "HEADER_LINE_COMPLETENESS_REVIEW.md" { "Quote header/line completeness audit."; break }
        "DRY_RUN_RESULTS.md" { "Updated dry-run counts and sanitized samples."; break }
        "APPLY_MODE_RESULTS.md" { "Confirms apply mode was not run."; break }
        "ADMIN_EXCEPTION_WORKFLOW_REVIEW.md" { "Admin workflow for templates and exceptions."; break }
        "OPEN_DECISIONS.md" { "Remaining human decisions."; break }
        "SAFE_SOURCE_FILES/docs/*" { "Changed documentation included for source review."; break }
        "SAFE_SOURCE_FILES/scripts/*" { "Changed script included for source review."; break }
        "SAFE_SOURCE_FILES/results/*" { "Safe generated result/template artifact."; break }
        default { "Included Phase 3.1 audit artifact."; break }
    }
    $manifestEntries += "| $relativePath | $reason |"
}
Write-TextFile -RelativePath "MANIFEST.md" -Content ("# Manifest" + [Environment]::NewLine + [Environment]::NewLine + ($manifestEntries -join [Environment]::NewLine))

$markdownFiles = Get-ChildItem -LiteralPath $auditRoot -Recurse -File | Where-Object { $_.Extension -ieq ".md" }
foreach ($markdownFile in $markdownFiles) {
    $content = Get-Content -LiteralPath $markdownFile.FullName -Raw
    if ($content -match "[\x00-\x08\x0B\x0C\x0E-\x1F]") {
        throw "Control character found in $($markdownFile.FullName)"
    }
}

Compress-Archive -Path (Join-Path $auditRoot "*") -DestinationPath $zipPath -Force

[pscustomobject]@{
    auditRoot = $auditRoot
    zipPath = $zipPath
    fileCount = (Get-ChildItem -LiteralPath $auditRoot -Recurse -File).Count
    zipLength = (Get-Item -LiteralPath $zipPath).Length
} | ConvertTo-Json -Depth 5
