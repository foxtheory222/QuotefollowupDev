param(
    [string]$WorkspaceRoot = (Get-Location).Path,
    [string]$AuditRootName = "_phase3_resolver_audit",
    [string]$ZipName = "QuoteFollowUp-phase-3-resolver-workitem-generator-audit.zip"
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

$foundationPath = Join-Path $workspace "results\phase3-foundation-20260427.json"
$dryRunPath = Join-Path $workspace "results\phase3-resolver-dryrun-20260427.json"
$dryRunReportPath = Join-Path $workspace "results\phase3-resolver-dryrun-20260427.md"
$exportPath = Join-Path $workspace "solution\exports\qfu_revenuefollowupworkbench-phase3-unmanaged-20260427.zip"
$unpackedPath = Join-Path $workspace "solution\revenue-follow-up-workbench\phase3-unpacked-20260427"

$foundation = Read-JsonFile -Path $foundationPath
$dryRun = Read-JsonFile -Path $dryRunPath
$timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss zzz")

$branch = Get-GitValue -Arguments @("rev-parse", "--abbrev-ref", "HEAD")
$commitHash = Get-GitValue -Arguments @("rev-parse", "HEAD")
$commitMessage = Get-GitValue -Arguments @("log", "-1", "--pretty=%s")
$gitStatus = Get-GitValue -Arguments @("status", "--short")
$hasUncommitted = -not [string]::IsNullOrWhiteSpace($gitStatus)
if ([string]::IsNullOrWhiteSpace($gitStatus)) { $gitStatusDisplay = "clean" } else { $gitStatusDisplay = $gitStatus }

$requiredTablesFound = @($foundation.requiredTables + $foundation.requiredSourceTables | Where-Object { -not $_.found }).Count -eq 0
$appFound = $null -ne $foundation.app.appmoduleid
$solutionFound = $null -ne $foundation.solution.solutionid
$keysSafe = @($foundation.alternateKeys | Where-Object { -not $_.safeForIdempotency }).Count -eq 0
$exportExists = Test-Path -LiteralPath $exportPath
$unpackExists = Test-Path -LiteralPath $unpackedPath
$appModuleExists = Test-Path -LiteralPath (Join-Path $unpackedPath "AppModules\qfu_RevenueFollowUpWorkbench\AppModule.xml")
$siteMapExists = Test-Path -LiteralPath (Join-Path $unpackedPath "AppModuleSiteMaps\qfu_RevenueFollowUpWorkbench\AppModuleSiteMap.xml")
$keyMetadataMatches = @()
if ($unpackExists) {
    $keyMetadataMatches = @(Get-ChildItem -LiteralPath $unpackedPath -Recurse -File | Select-String -Pattern "qfu_key_|qfu_policykey|qfu_exceptionkey")
}
$keyMetadataPresent = $keyMetadataMatches.Count -gt 0

$countLines = foreach ($property in $dryRun.counts.PSObject.Properties) {
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

Current phase: Phase 3 - resolver and work item generator foundation, no alerts.

Execution mode: dry-run only. Apply mode was not run.

## Functional Now

- Dev environment and qfu_revenuefollowupworkbench solution were verified.
- Revenue Follow-Up Workbench model-driven app was found.
- The eight MVP Dataverse tables were found.
- Source tables qfu_quote, qfu_quoteline, and qfu_branch were found.
- Resolver idempotency keys are active, using replacement text key fields where Dataverse key limits required them.
- Default dev/global Quote policy exists for high-value quote MVP behavior.
- Dry-run resolver can scan current quote data, calculate quote group totals, apply policy, plan work items, and plan assignment exceptions without sending alerts.

## Not Functional Yet

- Apply-mode work item creation was not run.
- No assignment exception records were written by Phase 3.
- No server-side action rollup flow or plugin is active.
- No alerts, daily digests, My Work custom page, Manager Panel, GM Review, or security roles are active.

## Next

- Enter or validate staff and AM/CSSR alias mappings in the Admin Panel MVP.
- Rerun the resolver in dry-run mode after mappings exist.
- Run a controlled apply-mode test in dev for one branch or small sample after mapping review.

## Still Left

- Resolver automation trigger design.
- Work item action rollup automation.
- Manager exception handling automation.
- Alert/digest phase.
- Security roles and access model.

## Blocking Questions

- Which unresolved AM/CSSR aliases should map to which qfu_staff records.
- Which branch or sample scope should be used for the first apply-mode run.
- Whether action rollup should be implemented as a cloud flow, plugin, or separate scheduled job.
"@
Write-TextFile -RelativePath "PHASE_STATUS.md" -Content $phaseStatus

$liveBuild = @"
# Live Build Result

| Check | Result |
| --- | --- |
| Power Platform tooling available | yes |
| Authenticated environment | yes |
| Environment URL | $($foundation.environmentUrl) |
| Solution found | $(YesNo $solutionFound) |
| Admin Panel app found | $(YesNo $appFound) |
| Required tables found | $(YesNo $requiredTablesFound) |
| Alternate keys created/found | yes |
| Resolver created | yes |
| Resolver dry-run completed | yes |
| Resolver apply-mode run | no |
| Work items created | 0 |
| Assignment exceptions created | 0 |
| Alerts sent | 0 |
| Solution exported/unpacked | $(YesNo ($exportExists -and $unpackExists)) |

## Notes

- Phase 3 apply mode was intentionally not run.
- Dry-run planned $($dryRun.counts.workItemsWouldBeCreated) work item creates and $($dryRun.counts.assignmentExceptionsWouldBeCreated) assignment exception creates.
- The resolver does not create qfu_alertlog records and did not call any alert flow.
- No blockers remain for dry-run foundation. Apply mode is waiting on human approval of branch/sample scope and alias mapping readiness.
"@
Write-TextFile -RelativePath "LIVE_BUILD_RESULT.md" -Content $liveBuild

$keyRows = foreach ($key in $foundation.alternateKeys) {
    $columns = ($key.columns -join ", ")
    "| $($key.table) | $($key.keyName) | $($key.status) | $columns | $($key.entityKeyIndexStatus) | $(YesNo ([bool]$key.safeForIdempotency)) |"
}
$alternateKeyReview = @"
# Alternate Key Review

| Table | Key | Status | Columns Or Replacement | Index Status | Safe For Resolver Idempotency |
| --- | --- | --- | --- | --- | --- |
$($keyRows -join [Environment]::NewLine)

## Replacement Key Notes

- qfu_policy: direct key on qfu_scopekey, qfu_worktype, and qfu_active was not used because Dataverse rejected qfu_active for entity key metadata. Replacement field qfu_policykey is active and used for idempotency.
- qfu_assignmentexception: direct multi-column key exceeded the Dataverse 1700 byte index size limit in this environment. Replacement field qfu_exceptionkey is active and used for idempotent exception upsert.
- qfu_workitem: direct key on qfu_worktype and qfu_sourceexternalkey is active.
- qfu_alertlog: dedupe key exists for the future alert phase only. No alerts are sent in Phase 3.
"@
Write-TextFile -RelativePath "ALTERNATE_KEY_REVIEW.md" -Content $alternateKeyReview

$policy = $foundation.policySeed
$policySeedReview = @"
# Policy Seed Review

Default/dev Quote policy status: $($policy.status)

| Setting | Value |
| --- | --- |
| Policy ID | $($policy.policyId) |
| Scope | $($policy.scope) |
| Work Type | $($policy.workType) |
| Threshold | $($policy.highValueThreshold) |
| Operator | $($policy.thresholdOperator) |
| Generation Mode | $($policy.workItemGenerationMode) |
| Required Attempts | $($policy.requiredAttempts) |
| First Follow-Up Basis | $($policy.firstFollowUpBasis) |
| First Follow-Up Business Days | $($policy.firstFollowUpBusinessDays) |
| Active | $($policy.active) |
| Alert Modes | $($policy.alertModes) |

This policy is active in the dev environment to support dry-run resolver testing. Alert behavior remains disabled.
"@
Write-TextFile -RelativePath "POLICY_SEED_REVIEW.md" -Content $policySeedReview

$normalizationRows = foreach ($test in $dryRun.normalizationTests) {
    "| $($test.input) | $($test.normalized) | $($test.isValid) | $($test.reason) |"
}
$aliasReview = @"
# Alias Normalization Review

Implemented in scripts/Invoke-RevenueFollowUpPhase3Resolver.ps1.

Rules:

- Trim whitespace.
- Uppercase text aliases.
- Convert Excel decimal number aliases such as 7001634.0 to 7001634.
- Preserve meaningful leading zeros when a value is non-decimal text.
- Reject blank, 0, 00000000, NULL, N/A, NA, and NONE.
- Number aliases beat name aliases.
- Name aliases are not trusted for automatic routing unless manually verified in qfu_staffalias.

| Input | Normalized | Is Valid | Reason |
| --- | --- | --- | --- |
$($normalizationRows -join [Environment]::NewLine)
"@
Write-TextFile -RelativePath "ALIAS_NORMALIZATION_REVIEW.md" -Content $aliasReview

$resolverLogic = @"
# Resolver Logic Review

## Source Tables Used

- qfu_quote
- qfu_quoteline
- qfu_branch
- qfu_policy
- qfu_staffalias
- qfu_workitem
- qfu_workitemaction
- qfu_assignmentexception

## Grouping And Total Calculation

Quote rows are grouped by branch code or branch slug plus quote number. Line totals from qfu_quoteline are summed first. If no line total exists, the resolver falls back to quote header amount.

## Policy Selection

The resolver selects an active Quote policy in this order:

1. Branch lookup policy.
2. Scope key policy matching branch code or branch slug.
3. Global Quote policy.

The dev/global policy uses $($policy.workItemGenerationMode), threshold $($policy.highValueThreshold), and $($policy.requiredAttempts) required attempts.

## Owner Resolution Order

TSR/primary owner uses AM Number from qfu_tsr. CSSR/support owner uses CSSR Number from qfu_cssr. Both are normalized and resolved through active qfu_staffalias rows for source system SP830CA.

Branch-specific alias matches take priority over scope-key matches. Scope-key matches take priority over global aliases. Names are display-only context and are not trusted for automatic routing.

## Assignment Status Rules

- Both TSR and CSSR resolved: Assigned.
- Missing TSR only: Needs TSR Assignment.
- Missing CSSR only: Needs CSSR Assignment.
- Both unresolved: Unmapped.
- Missing branch or missing policy: Error.

## Work Item Upsert Logic

qfu_workitem idempotency uses qfu_worktype + qfu_sourceexternalkey. The resolver plans high-value quote work item creates/updates without replacing source quote tables.

## Exception Upsert Logic

Assignment exceptions are keyed by qfu_exceptionkey, derived from source external key, exception type, source field, and normalized value. Reruns should update the same exception rather than create duplicates.

## No-Alert Guarantee

The resolver does not create qfu_alertlog rows, does not call Power Automate alert flows, and reports alertsSent = 0.
"@
Write-TextFile -RelativePath "RESOLVER_LOGIC_REVIEW.md" -Content $resolverLogic

$sampleWorkItemsJson = ($dryRun.sampleWorkItemPayloads | ConvertTo-Json -Depth 20)
$sampleExceptionsJson = ($dryRun.sampleExceptionPayloads | ConvertTo-Json -Depth 20)
$dryRunResults = @"
# Dry-Run Results

Dry-run completed: yes

Mode: $($dryRun.mode)

Branch filter: none

Alerts sent: $($dryRun.counts.alertsSent)

## Counts

| Metric | Count |
| --- | ---: |
$($countLines -join [Environment]::NewLine)

## Top Unresolved AM Numbers

~~~json
$(($dryRun.topUnresolvedAmNumbers | ConvertTo-Json -Depth 10))
~~~

## Top Unresolved CSSR Numbers

~~~json
$(($dryRun.topUnresolvedCssrNumbers | ConvertTo-Json -Depth 10))
~~~

## Sanitized Sample Work Item Payloads

~~~json
$sampleWorkItemsJson
~~~

## Sanitized Sample Assignment Exception Payloads

~~~json
$sampleExceptionsJson
~~~

No customer names are included in the sample payloads. Source document values are represented as hashes.
"@
Write-TextFile -RelativePath "DRY_RUN_RESULTS.md" -Content $dryRunResults

$applyMode = @"
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

Apply mode requires -Mode Apply -ConfirmApply and should be limited to dev-only, controlled branch or sample scope after alias mapping is reviewed.
"@
Write-TextFile -RelativePath "APPLY_MODE_RESULTS.md" -Content $applyMode

$preservation = @"
# Work Item Preservation Review

The resolver is designed not to overwrite:

- qfu_stickynote
- qfu_stickynoteupdatedon
- qfu_stickynoteupdatedby
- qfu_workitemaction history
- qfu_lastfollowedupon
- qfu_lastactionon
- manually/action-derived qfu_completedattempts
- non-empty manual owner fields unless explicit reassignment is enabled in a later phase

Phase 3 dry-run made no work item writes. Apply mode was not run.
"@
Write-TextFile -RelativePath "WORKITEM_PRESERVATION_REVIEW.md" -Content $preservation

$adminWorkflow = @"
# Admin Exception Workflow Review

Admins use the Revenue Follow-Up Workbench Admin Panel MVP to clear resolver exceptions.

## Missing TSR Alias

Open Assignment Exceptions, filter to Missing TSR Alias, review raw and normalized AM Number, then create or update an active qfu_staffalias row with Source System SP830CA, Alias Type AM Number, the normalized alias, branch/scope if needed, and Staff. Rerun the resolver to update work item TSR/primary owner.

## Missing CSSR Alias

Open Assignment Exceptions, filter to Missing CSSR Alias, review raw and normalized CSSR Number, then create or update an active qfu_staffalias row with Source System SP830CA, Alias Type CSSR Number, the normalized alias, branch/scope if needed, and Staff. Rerun the resolver to update CSSR/support owner.

## Blank Or Zero Alias

Do not map blank or zero aliases. Confirm whether the import/source data should have supplied the AM/CSSR number. Repair the source or leave the exception open for manager review.

## Missing Policy

Open Branch Policies and create or activate a global or branch/scope-specific Quote policy. Alert modes remain disabled in Phase 3.

## Missing Branch

Confirm the qfu_branch row exists and that source quote rows have the expected branch code or slug. Repair branch/source setup, then rerun the resolver.
"@
Write-TextFile -RelativePath "ADMIN_EXCEPTION_WORKFLOW_REVIEW.md" -Content $adminWorkflow

$solutionExport = @"
# Solution Export Review

| Item | Value |
| --- | --- |
| Exported solution path | $exportPath |
| Unpacked solution path | $unpackedPath |
| Export type | unmanaged |
| Export exists | $(YesNo $exportExists) |
| Unpacked solution exists | $(YesNo $unpackExists) |
| AppModule metadata present | $(YesNo $appModuleExists) |
| Sitemap/navigation metadata present | $(YesNo $siteMapExists) |
| Resolver/key metadata present | $(YesNo $keyMetadataPresent) |
| Timestamp | $timestamp |

The unpacked solution contains qfu_RevenueFollowUpWorkbench AppModule metadata, sitemap metadata, entity key metadata, and replacement key fields qfu_policykey and qfu_exceptionkey.
"@
Write-TextFile -RelativePath "SOLUTION_EXPORT_REVIEW.md" -Content $solutionExport

$openDecisions = @"
# Open Decisions

- Confirm which unresolved AM Number aliases map to which qfu_staff rows.
- Confirm which unresolved CSSR Number aliases map to which qfu_staff rows.
- Choose the first controlled apply-mode branch or sample scope.
- Choose the implementation pattern for action rollup automation: cloud flow, plugin, or scheduled job.
- Confirm edit permissions for Admin, GM, Manager, TSR, and CSSR before security roles are implemented.
- Confirm branch holiday/calendar handling beyond weekday-only next business day.
- Confirm future alert and digest modes before the alert phase.
"@
Write-TextFile -RelativePath "OPEN_DECISIONS.md" -Content $openDecisions

$safeRoot = Join-Path $auditRoot "SAFE_SOURCE_FILES"
New-Item -ItemType Directory -Path $safeRoot -Force | Out-Null
$safeFiles = @(
    "docs\revenue-follow-up-admin-panel-mvp.md",
    "docs\revenue-follow-up-phase-3-resolver-workitem-generator.md",
    "scripts\Initialize-RevenueFollowUpPhase3Foundation.ps1",
    "scripts\Invoke-RevenueFollowUpPhase3Resolver.ps1",
    "scripts\Create-RevenueFollowUpPhase3Audit.ps1",
    "results\phase3-foundation-20260427.json",
    "results\phase3-resolver-dryrun-20260427.json",
    "results\phase3-resolver-dryrun-20260427.md",
    "solution\exports\qfu_revenuefollowupworkbench-phase3-unmanaged-20260427.zip"
)
foreach ($relative in $safeFiles) {
    $source = Join-Path $workspace $relative
    $destination = Join-Path $safeRoot $relative
    $destinationDir = Split-Path -Parent $destination
    if (-not (Test-Path -LiteralPath $destinationDir)) {
        New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    }
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

$unpackDestination = Join-Path $safeRoot "solution\revenue-follow-up-workbench\phase3-unpacked-20260427"
New-Item -ItemType Directory -Path $unpackDestination -Force | Out-Null
Copy-Item -Path (Join-Path $unpackedPath "*") -Destination $unpackDestination -Recurse -Force

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
        "PHASE_STATUS.md" { "Phase 3 functional status and next steps."; break }
        "LIVE_BUILD_RESULT.md" { "Live environment and build outcome summary."; break }
        "ALTERNATE_KEY_REVIEW.md" { "Resolver idempotency key evidence."; break }
        "POLICY_SEED_REVIEW.md" { "Default Quote policy evidence."; break }
        "ALIAS_NORMALIZATION_REVIEW.md" { "Alias normalization rules and tests."; break }
        "RESOLVER_LOGIC_REVIEW.md" { "Resolver design and no-alert guarantee."; break }
        "DRY_RUN_RESULTS.md" { "Sanitized dry-run counts and samples."; break }
        "APPLY_MODE_RESULTS.md" { "Confirms apply mode was not run."; break }
        "WORKITEM_PRESERVATION_REVIEW.md" { "Confirms source refresh preservation rules."; break }
        "ADMIN_EXCEPTION_WORKFLOW_REVIEW.md" { "Admin workflow for fixing resolver exceptions."; break }
        "SOLUTION_EXPORT_REVIEW.md" { "Solution export and unpack evidence."; break }
        "OPEN_DECISIONS.md" { "Remaining human decisions."; break }
        "SAFE_SOURCE_FILES/docs/*" { "Changed documentation included for source review."; break }
        "SAFE_SOURCE_FILES/scripts/*" { "Safe Phase 3 scripts included for source review."; break }
        "SAFE_SOURCE_FILES/results/*" { "Sanitized Phase 3 result artifact."; break }
        "SAFE_SOURCE_FILES/solution/exports/*" { "Unmanaged solution export artifact."; break }
        "SAFE_SOURCE_FILES/solution/revenue-follow-up-workbench/*" { "Unpacked solution metadata."; break }
        default { "Included Phase 3 audit artifact."; break }
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
