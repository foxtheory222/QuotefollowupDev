param(
    [string]$AuditRoot = 'QuoteFollowUp-phase-5-branch-workbench-manager-queue-handoff-audit',
    [string]$ZipPath = 'QuoteFollowUp-phase-5-branch-workbench-manager-queue-handoff-audit.zip',
    [string]$RepoPath = 'tmp-github-QuoteFollowUp'
)

$ErrorActionPreference = 'Stop'

$workspace = (Get-Location).Path
$auditFull = Join-Path $workspace $AuditRoot
$zipFull = Join-Path $workspace $ZipPath

function Assert-UnderWorkspace {
    param([string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($workspace, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to operate outside workspace: $full"
    }
    return $full
}

$auditFull = Assert-UnderWorkspace $auditFull
$zipFull = Assert-UnderWorkspace $zipFull

if (Test-Path -LiteralPath $auditFull) {
    Remove-Item -LiteralPath $auditFull -Recurse -Force
}
if (Test-Path -LiteralPath $zipFull) {
    Remove-Item -LiteralPath $zipFull -Force
}

New-Item -ItemType Directory -Force -Path $auditFull | Out-Null

function Write-TextFile {
    param(
        [string]$Path,
        [string]$Content
    )
    $full = Assert-UnderWorkspace (Join-Path $workspace $Path)
    $dir = Split-Path -Parent $full
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Set-Content -LiteralPath $full -Value $Content.TrimStart() -Encoding utf8
}

function Copy-SafeFile {
    param(
        [string]$Source,
        [string]$DestinationRelative
    )
    $DestinationRelative = $DestinationRelative.Replace(
        'SAFE_SOURCE_FILES\solution\revenue-follow-up-workbench\phase5-final-unpacked-20260428\',
        'SAFE_SOURCE_FILES\solution-unpacked\'
    ).Replace(
        'SAFE_SOURCE_FILES\powerpages-dev-refresh-phase5-20260428\operations-hub---operationscenter\',
        'SAFE_SOURCE_FILES\powerpages\dev-refresh\'
    ).Replace(
        'SAFE_SOURCE_FILES\powerpages-dev-postupload-phase5-20260428\operations-hub---operationscenter\',
        'SAFE_SOURCE_FILES\powerpages\dev-postupload\'
    )
    $sourceFull = Join-Path $workspace $Source
    if (-not (Test-Path -LiteralPath $sourceFull)) {
        return
    }
    $destFull = Assert-UnderWorkspace (Join-Path $auditFull $DestinationRelative)
    $destDir = Split-Path -Parent $destFull
    if ($destDir -and -not (Test-Path -LiteralPath $destDir)) {
        [System.IO.Directory]::CreateDirectory($destDir) | Out-Null
    }
    Copy-Item -LiteralPath $sourceFull -Destination $destFull -Force
}

function To-PlainCount {
    param($Value)
    if ($null -eq $Value) { return 0 }
    return [int]$Value
}

$validation = Get-Content -LiteralPath 'results\phase5-validation-final-20260428.json' -Raw | ConvertFrom-Json
$setup = Get-Content -LiteralPath 'results\phase5-dataverse-setup-20260428.json' -Raw | ConvertFrom-Json
$handoff = Get-Content -LiteralPath 'results\phase5-validation-posthandoff-20260428.json' -Raw | ConvertFrom-Json

$branch = (& git -C $RepoPath branch --show-current).Trim()
$commitHash = (& git -C $RepoPath rev-parse HEAD).Trim()
$commitMessage = (& git -C $RepoPath log -1 --pretty=%s).Trim()
$gitStatus = (& git -C $RepoPath status --short)
$gitStatusSummary = if ($gitStatus) { ($gitStatus -join "`n") } else { 'clean' }
$hasUncommitted = [bool]$gitStatus
$timestamp = (Get-Date).ToString('o')

$counts = $validation.counts
$activeWorkItems = To-PlainCount $counts.activeWorkItems
$quoteWorkItems = To-PlainCount $counts.activeQuoteWorkItems
$backorderWorkItems = To-PlainCount $counts.activeBackorderWorkItems
$assignmentExceptions = To-PlainCount $counts.activeAssignmentExceptions
$activeAlerts = To-PlainCount $counts.activeAlertLogs
$sentAlerts = To-PlainCount $counts.sentAlertLogs
$workItemActions = To-PlainCount $counts.workItemActions
$handoffActions = To-PlainCount $counts.handoffActions
$dueToday = To-PlainCount $counts.dueToday
$overdue = To-PlainCount $counts.overdue
$open = To-PlainCount $counts.open
$roadblocks = To-PlainCount $counts.roadblocks
$assignmentIssues = To-PlainCount $counts.assignmentIssues
$missingAttempts = To-PlainCount $counts.missingAttempts
$stickyCount = To-PlainCount $counts.workItemsWithStickyNotes
$stickyMarker = To-PlainCount $counts.phase5StickyMarkerFound
$queueTsr = To-PlainCount $counts.currentQueueTsr
$queueCssr = To-PlainCount $counts.currentQueueCssr
$queueUnassigned = To-PlainCount $counts.currentQueueUnassigned
$duplicateWorkItems = To-PlainCount $validation.duplicateWorkItemSourceKeys
$duplicateExceptions = To-PlainCount $validation.duplicateAssignmentExceptionKeys

$fieldResults = @($setup.fieldResults | ForEach-Object { "- $($_.name): $($_.status)" }) -join "`n"
$queueFields = @($validation.queueFieldsPresent.PSObject.Properties | ForEach-Object { "- $($_.Name): $($_.Value)" }) -join "`n"

$docs = [ordered]@{}

$docs['docs/google-stitch/phase-5-branch-workbench-google-stitch-mcp-output.md'] = @"
# Phase 5 Google Stitch MCP Output

Current phase: Phase 5 consolidated - Branch Workbench, manager/team view, queue handoff, overdue orders, metrics, test/fix/regression.

Google Stitch MCP was used for new Branch Workbench UX refinement.

Artifact:
- Project: projects/16963969412485526656
- Screen: projects/16963969412485526656/screens/12ffaf20e71e44bfa46b43b06f8298d8
- Screen title: Branch Workbench - Main View
- HTML file id: projects/16963969412485526656/files/a110d899797640529de65958a75cd812
- Screenshot file id: projects/16963969412485526656/files/9555d8788a54420c856ba7370a1b4ee0
- Design system asset: assets/ebb8c4e0c56a42d29baa7371a9989aa1

Prompt summary:
- Product: Revenue Follow-Up Workbench.
- Page: Branch Workbench.
- Implementation target: Power Apps custom page inside a model-driven app backed by Dataverse.
- Core tabs: My Queue, Team View, Quote Follow-Up, Overdue Orders, Assignment Issues, Team Stats.
- Required interactions: Escalate to TSR, Send to CSSR, Log Follow-Up, Sticky Note, Roadblock, Won, Lost.
- Design priority: clean, low-click, desktop-first, manager-friendly, staff-friendly, and no clutter.

Returned design direction:
- Quiet operational workbench layout.
- KPI cards and dense queue table remain the primary scan pattern.
- Assignment issues are visible but separated from clean daily work.
- Team View is secondary and manager-oriented.
- Queue handoff should feel like a simple routing action, not a workflow wizard.

Use in Power Apps:
- Keep the existing My Work custom page as the implementation foundation.
- Surface the visible title and navigation label as Workbench / Branch Workbench.
- Keep My Queue first and Team View second.
- Use cards and tables before charts.

Do not use:
- Generated Stitch HTML as production Power Apps code.
- Customer-sensitive sample values in docs, screenshots, or audit evidence.

Stitch remains design/prototype guidance only. The implementation target remains Power Apps custom pages/model-driven app backed by Dataverse.
"@

$docs['docs/revenue-follow-up-phase-5-branch-workbench-build.md'] = @"
# Phase 5 Branch Workbench Build

Environment: https://orga632edd5.crm3.dynamics.com/

Phase 5 expanded the Phase 4B My Work custom page into a Branch Workbench surface while preserving the existing Admin Panel and quote follow-up behavior.

What changed:
- Added/verified queue-owner fields on qfu_workitem.
- Initialized queue ownership for existing quote work items where safe.
- Created 5 controlled branch 4171 Backorder work items from qfu_backorder for the Overdue Orders tab.
- Updated the existing custom page qfu_mywork_6e7ed so the visible title is Branch Workbench.
- Added My Queue / Team View mode labels, Workbench KPI cards, work type tabs, handoff buttons, and an Overdue Orders tab.
- Replaced Team Progress with Workbench in the dev Operations Hub branch navigation.
- Exported and unpacked the unmanaged solution after the final app import.

Important naming note:
- The internal custom page logical name remains qfu_mywork_6e7ed.
- The visible navigation/page label is Workbench / Branch Workbench.
- The portal route key remains view=team-progress for compatibility, but the label and page title now render as Workbench.

Current live counts:
- Active work items: $activeWorkItems
- Active quote work items: $quoteWorkItems
- Active backorder work items: $backorderWorkItems
- Active assignment exceptions: $assignmentExceptions
- Active alert logs: $activeAlerts
- Sent alert logs: $sentAlerts

Known limitations:
- Server-side action rollup is not implemented. App-side rollup remains active for actions saved through the custom page.
- The queue role textbox is present as a Phase 5 filter control, but the final gallery formula avoids direct queue role field filtering because those new field references caused the gallery to fail in browser testing.
- UI handoff buttons are present; controlled handoff behavior was validated through Dataverse API rather than a final browser button click.
"@

$docs['docs/revenue-follow-up-workbench-ux.md'] = @"
# Branch Workbench UX

The Branch Workbench is a simple daily operations surface, not a broad analytics dashboard.

Primary layout:
- Header with Branch Workbench title, refresh timestamp, branch/team filter, staff fallback filter, and queue role control.
- KPI cards for Due Today, Overdue, Quote Follow-Up, Missing Attempts, Roadblocks, and Assignment Issues.
- Tabs for Overdue, Due Today, My Queue, Team Stats, Quote Follow-Up, Overdue Orders, High Value, Needs Attempts, Waiting, Roadblocks, All Open, and Assignment Issues.
- Dense work item list.
- Right-side detail panel with sticky note, action buttons, and handoff controls.

Current-user filtering:
- Not assumed in Phase 5 because qfu_staff to systemuser mapping is not ready.
- Branch/team plus staff fallback filters remain the MVP path.

Queue UX:
- My Queue is the staff-first view.
- Team View is the manager/team view.
- Assignment issues are visible but should not be mixed into the clean daily queue accidentally.

Portal UX:
- Operations Hub branch navigation now labels the old Team Progress slot as Workbench.
- The portal Workbench route remains compatible with the existing branch detail runtime.
"@

$docs['docs/revenue-follow-up-queue-handoff-behavior.md'] = @"
# Queue Handoff Behavior

Queue handoff moves current action ownership without changing the underlying TSR/CSSR identity fields.

Fields on qfu_workitem:
$queueFields

Preserved fields:
- qfu_tsrstaff
- qfu_cssrstaff
- qfu_primaryownerstaff
- qfu_supportownerstaff
- sticky note fields
- action history
- terminal/manual status values

Escalate to TSR:
- Sets qfu_currentqueueownerstaff to qfu_tsrstaff.
- Sets qfu_currentqueuerole to TSR.
- Updates qfu_queueassignedon.
- Increments qfu_queuehandoffcount.
- Writes a non-attempt qfu_workitemaction using Assignment/Reassignment.
- Sends no alert.

Send to CSSR:
- Sets qfu_currentqueueownerstaff to qfu_cssrstaff.
- Sets qfu_currentqueuerole to CSSR.
- Updates qfu_queueassignedon.
- Increments qfu_queuehandoffcount.
- Writes a non-attempt qfu_workitemaction using Assignment/Reassignment.
- Sends no alert.

Controlled validation:
- Two controlled handoff actions were created.
- Both were non-attempt actions.
- Completed attempts were preserved.
- Alerts sent remained 0.

UI note:
- Buttons exist in the Branch Workbench detail panel.
- The final handoff validation used Dataverse API because the selected browser item was terminal and handoff buttons were disabled by design.
"@

$docs['docs/revenue-follow-up-manager-team-view.md'] = @"
# Manager Team View

Team View is a simple manager scan, not a scorecard-heavy dashboard.

Available verified metrics in Phase 5:
- Open work items by queue state.
- Overdue work items.
- Due today work items.
- Assignment issues.
- Missing attempts.
- High-value quote work item count.
- Backorder work item count for controlled branch 4171 sample.

Current counts:
- Open: $open
- Due Today: $dueToday
- Overdue: $overdue
- Missing Attempts: $missingAttempts
- Roadblocks: $roadblocks
- Assignment Issues: $assignmentIssues
- Queue TSR: $queueTsr
- Queue CSSR: $queueCssr
- Queue Unassigned: $queueUnassigned

Limitations:
- Current-user staff mapping is not ready, so Team View does not enforce user-specific filtering.
- Order entry line comparison is deferred until a verified per-staff order-entry metric source exists.
"@

$docs['docs/revenue-follow-up-overdue-orders-integration.md'] = @"
# Overdue Orders Integration

Source checked:
- qfu_backorder exists in the dev Dataverse environment.
- Existing branch operations pages already surface overdue backorder line metrics.
- qfu_worktype includes Backorder.

Implemented:
- Created 5 controlled branch 4171 Backorder work items from qfu_backorder.
- These work items appear in the Branch Workbench list and Overdue Orders tab.
- They are kept in qfu_workitem as workflow/control records and do not replace qfu_backorder.

Counts:
- Active Backorder work items: $backorderWorkItems

Owner assignment:
- Deferred for backorder work items because no verified backorder staff-number routing source was available.
- Current queue owner remains unassigned where no verified staff alias exists.

No alerts were sent.
"@

$docs['docs/revenue-follow-up-order-entry-line-metrics.md'] = @"
# Order Entry Line Metrics

Phase 5 audited repo docs, scripts, results, and solution metadata for a verified source of order entry line counts by staff.

Result:
- No verified source was found for per-staff order entry line comparison.
- Existing qfu_branchdailysummary and budget/ops tables provide branch-level operational metrics, not verified per-staff order-entry line ownership.

Decision:
- Order entry line comparison is deferred.
- No fake order-entry metric was created.
- Team Stats uses verified quote, queue, assignment, and controlled backorder work item metrics only.

Required before implementation:
- A Dataverse table or summarized flow output with staff identity, branch, period, and order entry line count.
- Confirmed mapping from source staff identity to qfu_staff.
- Validation that counts match the source report.
"@

$docs['docs/revenue-follow-up-server-side-rollup.md'] = @"
# Server-Side Rollup

Phase 5 attempted to identify a safe automated path for server-side rollup.

Required behavior:
- When qfu_workitemaction is created or updated, recalculate qfu_completedattempts.
- Update qfu_lastfollowedupon from attempt actions.
- Update qfu_lastactionon from all actions.
- Respect terminal/manual statuses.
- Do not overwrite sticky notes or owners.
- Send no alerts.

Current implementation:
- App-side rollup remains active in the Branch Workbench custom page for actions saved through the page.

Blocker:
- PAC in this session did not expose a supported cloud-flow creation command.
- dotnet/plugin build tooling was not installed, so a Dataverse plugin could not be safely built and registered.
- Creating fragile raw flow metadata was intentionally avoided.

Status:
- Server-side rollup is deferred and must be implemented before relying on qfu_workitemaction rows created outside the custom page.
"@

$docs['docs/revenue-follow-up-phase-5-test-plan.md'] = @"
# Phase 5 Test Plan

Required test groups:
- Navigation/menu.
- Workbench load.
- KPI counts against Dataverse.
- My Queue.
- Team View.
- Escalate to TSR.
- Send to CSSR.
- Handoff disabled/error states.
- Quote follow-up regression.
- Server-side rollup.
- Overdue Orders.
- Order entry line metrics.
- No-alert validation.
- Admin Panel regression.
- Data safety regression.
- Refresh/persistence.

Safe evidence policy:
- Browser snapshots contained real customer/order data.
- Audit evidence is sanitized textual proof and Dataverse query results only.
"@

$docs['docs/revenue-follow-up-phase-5-regression-results.md'] = @"
# Phase 5 Regression Results

Final result: partial pass with documented blockers.

Passed:
- Workbench custom page opens in the Revenue Follow-Up Workbench app.
- Admin Panel navigation remains present.
- Operations Hub branch navigation shows Workbench instead of Team Progress.
- Branch portal Workbench detail route opens.
- KPI counts match final Dataverse validation counts.
- Workbench list loads 37 active work items.
- Team View summary loads.
- Sticky note marker persists.
- Overdue Orders tab shows the controlled 5 Backorder work items.
- Controlled queue handoff API validation passed.
- No alerts were sent.
- Duplicate work item source keys: $duplicateWorkItems.
- Duplicate assignment exception keys: $duplicateExceptions.

Partial or deferred:
- Server-side action rollup is deferred.
- Queue role filtering is visual only in the final gallery build.
- Browser click validation of handoff buttons was not completed; backend handoff logic was validated with Dataverse API.
- Order entry line metrics are deferred pending a verified source.

Fix/test cycles run: 3.
"@

$docs['docs/revenue-follow-up-phase-5-user-test-guide.md'] = @"
# Phase 5 User Test Guide

1. Open https://operationscenter.powerappsportals.com/
2. Open Southern Alberta, then a branch such as 4171 Calgary.
3. Confirm the branch navigation shows Workbench instead of Team Progress.
4. Open Workbench.
5. Open the Revenue Follow-Up Workbench Power App and choose Workbench.
6. Review My Queue and Team View.
7. Pick a safe dev item, add a sticky note, and confirm it persists after refresh.
8. Log a call on a safe dev item and confirm attempts update if using the custom page action.
9. Confirm no alert/email is sent.
10. Report anything confusing, too slow, or too cluttered.

Do not use this as a production security test. Current-user staff mapping and final roles are still future work.
"@

foreach ($entry in $docs.GetEnumerator()) {
    Write-TextFile -Path $entry.Key -Content $entry.Value
}

$auditFiles = [ordered]@{}

$auditFiles['CURRENT_REPO_STATE.md'] = @"
# Current Repo State

- Current branch: $branch
- Latest commit hash: $commitHash
- Latest commit message: $commitMessage
- Timestamp: $timestamp
- Uncommitted changes: $hasUncommitted

Git status summary:

```
$gitStatusSummary
```
"@

$phaseStatusContent = @"
# Phase Status

- Current phase: Phase 5 consolidated - Branch Workbench, manager/team view, queue handoff, overdue orders, metrics, test/fix/regression.
- Workbench created/updated: yes.
- Team Progress replaced: yes, visible branch navigation label is Workbench.
- Queue handoff implemented: partial. Fields and backend behavior are live; UI buttons are present; final browser button-click validation was not completed.
- Server-side rollup implemented: no, blocked/deferred.
- Overdue orders integrated: yes, controlled branch 4171 Backorder work items were created.
- Order entry line metrics: deferred pending verified source.
- All tests passed: no. Final status is partial pass with blockers documented.
- Fix/test cycles run: 3.

What should be functional now:
- Workbench opens in the model-driven app.
- Portal branch navigation shows Workbench.
- My Queue list loads real dev work items.
- Team View summary is visible.
- Sticky notes persist.
- Controlled queue ownership fields exist and backend handoff works.
- Overdue Orders has controlled dev Backorder work items.

What is not functional yet:
- Server-side rollup for actions created outside the custom page.
- Final current-user filtering by qfu_staff/systemuser.
- Production security roles.
- Alerts/digests.
- Verified order entry line comparison.
- Full browser-click validation of queue handoff buttons.

Blocking questions:
- Which implementation path should be used for server-side rollup: Power Automate flow, Dataverse plugin, or approved raw solution workflow authoring?
- What is the verified order-entry line count source by staff?
- Should the portal Workbench link remain the portal detail view or deep-link to the Power Apps custom page?
- When will qfu_staff to systemuser mapping be completed for current-user filtering/security?
"@

$auditFiles['PHASE_STATUS.md'] = $phaseStatusContent
$phaseStatusContent = @(
    '# Phase Status',
    '',
    '- Current phase: Phase 5 consolidated - Branch Workbench, manager/team view, queue handoff, overdue orders, metrics, test/fix/regression.',
    '- Workbench created/updated: yes.',
    '- Team Progress replaced: yes, visible branch navigation label is Workbench.',
    '- Queue handoff implemented: partial. Fields and backend behavior are live; UI buttons are present; final browser button-click validation was not completed.',
    '- Server-side rollup implemented: no, blocked/deferred.',
    '- Overdue orders integrated: yes, controlled branch 4171 Backorder work items were created.',
    '- Order entry line metrics: deferred pending verified source.',
    '- All tests passed: no. Final status is partial pass with blockers documented.',
    '- Fix/test cycles run: 3.',
    '',
    'What should be functional now:',
    '- Workbench opens in the model-driven app.',
    '- Portal branch navigation shows Workbench.',
    '- My Queue list loads real dev work items.',
    '- Team View summary is visible.',
    '- Sticky notes persist.',
    '- Controlled queue ownership fields exist and backend handoff works.',
    '- Overdue Orders has controlled dev Backorder work items.',
    '',
    'What is not functional yet:',
    '- Server-side rollup for actions created outside the custom page.',
    '- Final current-user filtering by qfu_staff/systemuser.',
    '- Production security roles.',
    '- Alerts/digests.',
    '- Verified order entry line comparison.',
    '- Full browser-click validation of queue handoff buttons.',
    '',
    'Blocking questions:',
    '- Which implementation path should be used for server-side rollup: Power Automate flow, Dataverse plugin, or approved raw solution workflow authoring?',
    '- What is the verified order-entry line count source by staff?',
    '- Should the portal Workbench link remain the portal detail view or deep-link to the Power Apps custom page?',
    '- When will qfu_staff to systemuser mapping be completed for current-user filtering/security?'
) -join "`n"
$auditFiles['PHASE_STATUS.md'] = $phaseStatusContent

$auditFiles['LIVE_BUILD_RESULT.md'] = @"
# Live Build Result

- Power Platform tooling available: yes.
- Authenticated environment: yes.
- Target environment: https://orga632edd5.crm3.dynamics.com/
- Solution found: $($validation.solutionFound).
- Model-driven app found: $($validation.appFound).
- Workbench custom page found: $($validation.canvasAppFound).
- Branch navigation Workbench link found: yes, browser-validated on the 4171 branch page.
- Admin Panel navigation still found: yes.
- Queue-owner fields created/found: yes.
$fieldResults
- Queue handoff implemented: partial; backend validated through Dataverse API.
- Server-side rollup created/found: no.
- App published: yes.
- Solution exported/unpacked: yes.
- Blockers/failures: server-side rollup tooling path unavailable; queue role filter not wired in final gallery formula; handoff UI button click not fully validated.
"@

$auditFiles['NAVIGATION_REVIEW.md'] = @"
# Navigation Review

- Team Progress removed/replaced status: replaced by Workbench label in dev Operations Hub branch navigation.
- Workbench menu/link status: browser-validated on the 4171 branch page.
- Target destination: existing portal branch detail route view=team-progress, now relabeled Workbench.
- Operations Hub branch navigation updated: yes.
- Model-driven app navigation updated/found: yes, Workbench appears in Revenue Follow-Up Workbench.
- Admin Panel navigation preserved: yes.

Evidence:
- Fresh dev Power Pages source was downloaded before editing.
- Updated source was uploaded with pac pages upload using Enhanced model.
- Post-upload download confirmed the runtime template no longer contains Team Progress and does contain Workbench.
- Browser validation showed Workbench in the branch nav and clicking it opened the Workbench detail page.

Screenshots are not included because raw browser snapshots exposed real customer/order details.
"@

$auditFiles['WORKBENCH_COMPONENT_REVIEW.md'] = @"
# Workbench Component Review

- My Queue present: yes.
- Team View present: yes.
- Quote Follow-Up present: yes.
- Overdue Orders present: yes.
- Assignment Issues present: yes.
- Team Stats present: yes.
- KPI cards present: yes.
- Filters present: branch/team, staff fallback, queue role text control.
- Handoff buttons present: yes.
- Sticky note present: yes.
- Follow-up logging present: inherited from Phase 4B custom page.
- Detail panel present: yes.

Current Workbench counts:
- Active work items: $activeWorkItems
- Quote work items: $quoteWorkItems
- Backorder work items: $backorderWorkItems
- Due Today: $dueToday
- Overdue: $overdue
- Missing Attempts: $missingAttempts
- Assignment Issues: $assignmentIssues

Limitation:
- Queue role filtering was left as a visible control but not wired into the final gallery formula because direct references to the newly added queue choice/lookup fields caused the gallery to fail in browser testing.
"@

$auditFiles['QUEUE_HANDOFF_REVIEW.md'] = @"
# Queue Handoff Review

New fields added/found:
$queueFields

Controlled backend validation:
- Route to CSSR matched target owner: $($handoff.controlledHandoff.afterCssrOwnerMatched)
- Route back to TSR matched target owner: $($handoff.controlledHandoff.afterTsrOwnerMatched)
- Handoff action logs created: $($handoff.controlledHandoff.actionLogsCreated)
- Handoff actions counts-as-attempt false: $($handoff.controlledHandoff.countsAsAttemptFalse)
- Completed attempts preserved: $($handoff.controlledHandoff.completedAttemptsPreserved)
- Alerts sent after handoff: $($handoff.controlledHandoff.alertsSentAfter)

Behavior:
- Escalate to TSR sets current queue owner to qfu_tsrstaff.
- Send/Route to CSSR sets current queue owner to qfu_cssrstaff.
- Handoff writes a non-attempt qfu_workitemaction using Assignment/Reassignment.
- No alert is sent.

UI validation:
- Handoff buttons are visible in the detail panel.
- A terminal selected item correctly disabled both handoff buttons.
- Final browser-click handoff validation on a non-terminal item was not completed; backend behavior is validated.
"@

$auditFiles['MANAGER_TEAM_VIEW_REVIEW.md'] = @"
# Manager Team View Review

Manager/team stats shown:
- Team View summary label.
- Active/open counts.
- Overdue count.
- Due today count.
- Assignment issues.
- Missing attempts.
- Work type tabs and queue list.

Current values:
- Open: $open
- Overdue: $overdue
- Due Today: $dueToday
- Missing Attempts: $missingAttempts
- Roadblocks: $roadblocks
- Assignment Issues: $assignmentIssues

Limitations:
- No final security role enforcement in Phase 5.
- Current-user filtering remains deferred until qfu_staff links to systemuser.
- Order entry line comparison is deferred.
"@

$auditFiles['OVERDUE_ORDERS_INTEGRATION_REVIEW.md'] = @"
# Overdue Orders Integration Review

Source tables checked:
- qfu_backorder.
- qfu_workitem.
- qfu_branch.

Used qfu_backorder: yes.
Backorder/order work items created: yes, controlled branch 4171 sample.
Counts:
- Active Backorder work items: $backorderWorkItems

Source fields:
- Branch linkage.
- Source key/source document style values where available.
- Value/date fields from qfu_backorder where safely available.

Limitations:
- Owner assignment is deferred because no verified backorder staff-number routing source exists.
- No broad all-branch backorder apply was run.
- qfu_backorder was not replaced or structurally modified.
"@

$auditFiles['ORDER_ENTRY_LINE_METRICS_REVIEW.md'] = @"
# Order Entry Line Metrics Review

Source tables/docs/flows checked:
- Repo docs and scripts for order entry, order lines, line count, productivity, and branch daily summary references.
- Existing branch summary and operational tables.

Verified source exists: no.
Metrics implemented or deferred: deferred.

Exact missing source/field:
- A per-staff, per-period order entry line count source was not found.
- qfu_branchdailysummary has branch-level summary metrics, not verified staff-level order entry lines.

No fake data confirmation:
- No fake order entry comparison was created.
"@

$auditFiles['SERVER_SIDE_ROLLUP_REVIEW.md'] = @"
# Server-Side Rollup Review

- Implementation type: deferred.
- Trigger: not created.
- Fields intended: qfu_completedattempts, qfu_lastfollowedupon, qfu_lastactionon, qfu_nextfollowupon, system-owned status values.
- Tests run: tooling check and final validation; app-side rollup remains live.
- Limitation: actions created outside the custom page may not update rollup fields until a server-side flow/plugin is implemented.
- No-alert confirmation: alert logs remain 0 and sent alert logs remain 0.

Blocker:
- PAC did not expose a supported cloud-flow create command in this session.
- dotnet/plugin tooling was unavailable.
- Raw flow metadata creation was intentionally avoided.
"@

$auditFiles['TEST_RUN_SUMMARY.md'] = @"
# Test Run Summary

- Total test groups: 16.
- Passed: 9.
- Partial: 5.
- Skipped/deferred: 2.
- Failed: 0.
- Fix/test cycles run: 3.
- Final result: partial pass with documented blockers.

Passed:
- Navigation/menu source and browser validation.
- Workbench load.
- KPI query count validation.
- Team View summary.
- Overdue Orders controlled sample.
- No-alert validation.
- Admin Panel navigation regression.
- Data safety duplicate checks.
- Refresh/sticky persistence query validation.

Partial:
- My Queue filtering: list loads; queue role control is not wired into final gallery formula.
- Escalate to TSR: backend validated, final UI click not completed.
- Send to CSSR: backend validated, final UI click not completed.
- Handoff missing-target UX: terminal-item disabled state observed, missing-target case not fully exercised.
- Quote follow-up regression: sticky note retested; full Log Call/Email/Note retest not repeated after Phase 5.

Skipped/deferred:
- Server-side rollup.
- Order entry line comparison.
"@

$auditFiles['FIX_TEST_LOOP_REVIEW.md'] = @"
# Fix/Test Loop Review

Cycle 1:
- Failed test: Workbench gallery loaded but showed no work items.
- Root cause: final custom page formula referenced newly added queue lookup/choice fields in a way the canvas runtime did not evaluate safely.
- Fix: changed blank checks to Power Fx Not(IsBlank(...)).
- Retest: still empty.

Cycle 2:
- Failed test: My Queue remained empty.
- Root cause: queue field references were still blocking gallery evaluation.
- Fix: made My Queue default permissive.
- Retest: still empty.

Cycle 3:
- Failed test: My Queue remained empty.
- Root cause: direct queue field filtering was still the culprit.
- Fix: removed new queue lookup/choice field references from the gallery filter while preserving Workbench list, KPIs, and visible queue role control.
- Retest: passed; gallery loaded 37 items and Overdue Orders loaded 5 items.

Regression after fixes:
- Admin Panel navigation remained present.
- Portal Workbench menu validated.
- Final Dataverse validation showed no duplicate work items or assignment exceptions and 0 alert logs.
"@

$auditFiles['NO_ALERT_VALIDATION.md'] = @"
# No-Alert Validation

- Emails sent: 0 verified by no Phase 5 alert/digest implementation and qfu_alertlog Sent count 0.
- Teams messages sent: 0.
- Sent alert logs: $sentAlerts.
- Active alert logs: $activeAlerts.
- Daily digests: 0.

No alert or digest flow was created in Phase 5.
"@

$auditFiles['REGRESSION_REVIEW.md'] = @"
# Regression Review

- Admin Panel still works: navigation present for Staff, Staff Alias Mapping, Branch Policies, Work Items, Assignment Exceptions, and Alert Logs.
- My Work/Workbench quote follow-up still works: custom page opens and list loads real records.
- qfu_quote not replaced: confirmed no structural replacement.
- qfu_quoteline not replaced: confirmed no structural replacement.
- qfu_backorder not replaced: used as source for controlled Backorder work items only.
- No unintended broad resolver apply: confirmed.
- Duplicate work item source keys: $duplicateWorkItems.
- Duplicate assignment exception keys: $duplicateExceptions.
- Sticky notes preserved: marker found count $stickyMarker; work items with sticky notes $stickyCount.
- Action history preserved: active qfu_workitemaction count $workItemActions.
- App navigation intact: yes.
- Solution export/unpack completed: yes.
"@

$auditFiles['SOLUTION_EXPORT_REVIEW.md'] = @"
# Solution Export Review

- Exported solution path: solution/exports/qfu_revenuefollowupworkbench-phase5-final-unmanaged-20260428.zip
- Unpacked solution path: solution/revenue-follow-up-workbench/phase5-final-unpacked-20260428
- Unmanaged/managed: unmanaged.
- Workbench/custom page metadata present: yes, CanvasApps/qfu_mywork_6e7ed.
- Model-driven app metadata present: yes, AppModules/qfu_RevenueFollowUpWorkbench.
- Power Pages/menu files changed: yes, dev refreshed runtime source was updated and uploaded.
- Flow/plugin/rollup metadata present if created: no; server-side rollup deferred.
- New queue fields metadata present: yes in qfu_WorkItem entity metadata.
- Timestamp: $timestamp.
"@

$auditFiles['USER_REAL_WORLD_TEST_GUIDE.md'] = $docs['docs/revenue-follow-up-phase-5-user-test-guide.md']

$auditFiles['OPEN_DECISIONS.md'] = @"
# Open Decisions

- Choose and authorize the server-side rollup implementation path.
- Confirm the verified order entry line count source by staff.
- Decide whether the Operations Hub Workbench link should stay as the portal Workbench route or deep-link to the Power Apps custom page.
- Complete qfu_staff to systemuser mapping for current-user filtering and security.
- Decide when to enable alerts/digests after follow-up logging and rollup are server-side reliable.
"@

$auditFiles['TEST_EVIDENCE/navigation-menu-test.md'] = @"
# Navigation/Menu Test Evidence

Browser validation on the dev Operations Hub showed:
- Branch page navigation includes Dashboard, Follow-Up Queue, Quotes, Overdue Quotes, Backorder Lines, Ready to Ship, Not PGI'd, Freight Ledger, Workbench, and Analytics.
- Team Progress was not shown.
- Clicking Workbench opened the branch detail route with the visible page title Workbench.

Screenshots are omitted because raw browser snapshots included real customer/order details.
"@

$auditFiles['TEST_EVIDENCE/workbench-load-test.md'] = @"
# Workbench Load Test Evidence

Browser validation on the model-driven app showed:
- Page title: Branch Workbench.
- Navigation item: Workbench.
- Branch/team filter present.
- Staff fallback filter present.
- Queue role control present.
- KPI cards present.
- Gallery loaded 37 items.
- Detail panel present.
"@

$auditFiles['TEST_EVIDENCE/kpi-count-test.md'] = @"
# KPI Count Test Evidence

Final Dataverse validation:
- Due Today: $dueToday.
- Overdue: $overdue.
- Quote Follow-Up: $quoteWorkItems.
- Missing Attempts: $missingAttempts.
- Roadblocks: $roadblocks.
- Assignment Issues: $assignmentIssues.
- Overdue Orders/Backorder work items: $backorderWorkItems.

Browser-visible KPI cards matched these counts after the final import.
"@

$auditFiles['TEST_EVIDENCE/my-queue-test.md'] = @"
# My Queue Test Evidence

Result: partial pass.

Observed:
- My Queue label and tab are present.
- Work item gallery loaded 37 active items.
- Staff fallback and queue role controls are visible.

Limitation:
- Queue role filter is not wired into the final gallery formula because direct references to newly added queue fields broke gallery loading during test cycles.
"@

$auditFiles['TEST_EVIDENCE/team-view-manager-test.md'] = @"
# Team View Manager Test Evidence

Observed:
- Team View toggle is present.
- Team summary text is visible.
- Summary counts reflect final Dataverse counts: open $open, overdue $overdue, due today $dueToday, assignment issues $assignmentIssues.

No current-user mapping is assumed.
"@

$auditFiles['TEST_EVIDENCE/queue-handoff-test.md'] = @"
# Queue Handoff Test Evidence

Backend controlled handoff validation:
- CSSR route matched: $($handoff.controlledHandoff.afterCssrOwnerMatched).
- TSR route matched: $($handoff.controlledHandoff.afterTsrOwnerMatched).
- Handoff action logs created: $($handoff.controlledHandoff.actionLogsCreated).
- Handoff actions counts-as-attempt false: $($handoff.controlledHandoff.countsAsAttemptFalse).
- Completed attempts preserved: $($handoff.controlledHandoff.completedAttemptsPreserved).
- Alerts sent: $($handoff.controlledHandoff.alertsSentAfter).

UI:
- Handoff buttons are present.
- Terminal item disabled state observed.
- Final browser click of non-terminal handoff was not completed.
"@

$auditFiles['TEST_EVIDENCE/quote-followup-regression-test.md'] = @"
# Quote Follow-Up Regression Test Evidence

Observed:
- Sticky note marker PHASE5_UI_TEST_STICKY_NOTE persisted.
- Work items with sticky notes: $stickyCount.
- Active action history rows: $workItemActions.
- Phase 4B action logging controls remain present in the detail panel.

Limitation:
- Full Log Call, Log Email, Note, Roadblock, and terminal-status browser regression was not repeated after Phase 5. Phase 4B had passed these behaviors; Phase 5 did not intentionally modify those save formulas.
"@

$auditFiles['TEST_EVIDENCE/server-side-rollup-test.md'] = @"
# Server-Side Rollup Test Evidence

Result: skipped/deferred due blocker.

Reason:
- No safe automated server-side flow/plugin creation path was available.
- App-side rollup remains live for custom page actions.
"@

$auditFiles['TEST_EVIDENCE/overdue-orders-test.md'] = @"
# Overdue Orders Test Evidence

Observed:
- Overdue Orders tab exists.
- Browser validation showed the tab loading 5 items.
- Final Dataverse validation shows active Backorder work items: $backorderWorkItems.

No broad all-branch apply was run.
"@

$auditFiles['TEST_EVIDENCE/order-entry-line-metrics-test.md'] = @"
# Order Entry Line Metrics Test Evidence

Result: deferred.

Reason:
- No verified per-staff order entry line metric source was found.
- No fake metric was shown.
"@

$auditFiles['TEST_EVIDENCE/no-alert-test.md'] = $auditFiles['NO_ALERT_VALIDATION.md']

$auditFiles['TEST_EVIDENCE/admin-panel-regression-test.md'] = @"
# Admin Panel Regression Test Evidence

Browser validation showed model-driven app navigation still includes:
- Staff.
- Branch Memberships.
- Staff Alias Mapping.
- Branch Policies.
- Assignment Exceptions.
- Work Items.
- Work Item Actions.
- Alert Logs.
- Workbench.
"@

$auditFiles['TEST_EVIDENCE/data-safety-regression-test.md'] = @"
# Data Safety Regression Test Evidence

- qfu_quote was not replaced.
- qfu_quoteline was not replaced.
- qfu_backorder was not replaced.
- No broad resolver apply was run.
- Duplicate work item source keys: $duplicateWorkItems.
- Duplicate assignment exception keys: $duplicateExceptions.
- Alert logs: $activeAlerts.
- Sent alert logs: $sentAlerts.
"@

$auditFiles['TEST_EVIDENCE/refresh-persistence-test.md'] = @"
# Refresh/Persistence Test Evidence

- Sticky note marker found after refresh/query validation: $stickyMarker.
- Work items with sticky notes: $stickyCount.
- Active action rows: $workItemActions.
- Queue ownership counts persisted: TSR $queueTsr, CSSR $queueCssr, Unassigned $queueUnassigned.
"@

foreach ($entry in $auditFiles.GetEnumerator()) {
    Write-TextFile -Path (Join-Path $AuditRoot $entry.Key) -Content $entry.Value
}

# Defensive write: required by the phase audit contract. Some older PowerShell
# OrderedDictionary enumerations have skipped this key in long generated runs.
Write-TextFile -Path (Join-Path $AuditRoot 'PHASE_STATUS.md') -Content $phaseStatusContent

$safeRoot = 'SAFE_SOURCE_FILES'

$sourceFiles = @(
    'scripts\Ensure-RevenueFollowUpPhase5Workbench.ps1',
    'scripts\New-RevenueFollowUpPhase5WorkbenchCanvasSource.ps1',
    'scripts\Test-RevenueFollowUpPhase5Validation.ps1',
    'scripts\Create-RevenueFollowUpPhase5Audit.ps1',
    'docs\google-stitch\phase-5-branch-workbench-google-stitch-mcp-output.md',
    'docs\revenue-follow-up-phase-5-branch-workbench-build.md',
    'docs\revenue-follow-up-workbench-ux.md',
    'docs\revenue-follow-up-queue-handoff-behavior.md',
    'docs\revenue-follow-up-manager-team-view.md',
    'docs\revenue-follow-up-overdue-orders-integration.md',
    'docs\revenue-follow-up-order-entry-line-metrics.md',
    'docs\revenue-follow-up-server-side-rollup.md',
    'docs\revenue-follow-up-phase-5-test-plan.md',
    'docs\revenue-follow-up-phase-5-regression-results.md',
    'docs\revenue-follow-up-phase-5-user-test-guide.md',
    'results\phase5-dataverse-setup-20260428.json',
    'results\phase5-validation-final-20260428.json',
    'solution\exports\qfu_revenuefollowupworkbench-phase5-final-unmanaged-20260428.zip',
    'solution\revenue-follow-up-workbench\phase5-final-unpacked-20260428\AppModules\qfu_RevenueFollowUpWorkbench\AppModule.xml',
    'solution\revenue-follow-up-workbench\phase5-final-unpacked-20260428\AppModuleSiteMaps\qfu_RevenueFollowUpWorkbench\AppModuleSiteMap.xml',
    'solution\revenue-follow-up-workbench\phase5-final-unpacked-20260428\CanvasApps\qfu_mywork_6e7ed.meta.xml',
    'solution\revenue-follow-up-workbench\phase5-final-unpacked-20260428\CanvasApps\qfu_mywork_6e7ed_DocumentUri.msapp',
    'solution\revenue-follow-up-workbench\phase5-final-unpacked-20260428\Entities\qfu_WorkItem\Entity.xml',
    'solution\revenue-follow-up-workbench\phase5-final-unpacked-20260428\Other\Solution.xml',
    'powerpages-dev-refresh-phase5-20260428\operations-hub---operationscenter\web-templates\qfu-regional-runtime\QFU-Regional-Runtime.webtemplate.source.html',
    'powerpages-dev-postupload-phase5-20260428\operations-hub---operationscenter\web-templates\qfu-regional-runtime\QFU-Regional-Runtime.webtemplate.source.html'
)

foreach ($source in $sourceFiles) {
    $dest = Join-Path $safeRoot $source
    Copy-SafeFile -Source $source -DestinationRelative $dest
}

$manifestLines = @(
    '# Manifest',
    '',
    'Every file included in this audit and why it matters:',
    ''
)

Get-ChildItem -LiteralPath $auditFull -Recurse -File |
    Sort-Object FullName |
    ForEach-Object {
        $relative = $_.FullName.Substring($auditFull.Length + 1).Replace('\','/')
        $why = 'Audit artifact.'
        if ($relative -like 'TEST_EVIDENCE/*') { $why = 'Sanitized test evidence.' }
        elseif ($relative -like 'SAFE_SOURCE_FILES/docs/*') { $why = 'Changed documentation.' }
        elseif ($relative -like 'SAFE_SOURCE_FILES/scripts/*') { $why = 'Phase 5 automation script.' }
        elseif ($relative -like 'SAFE_SOURCE_FILES/results/*') { $why = 'Safe validation output.' }
        elseif ($relative -like 'SAFE_SOURCE_FILES/solution/*') { $why = 'Safe solution export/unpack metadata.' }
        elseif ($relative -like 'SAFE_SOURCE_FILES/powerpages-*') { $why = 'Safe Power Pages runtime source proving menu label update.' }
        $manifestLines += "- $relative - $why"
    }

Write-TextFile -Path (Join-Path $AuditRoot 'MANIFEST.md') -Content ($manifestLines -join "`n")

Compress-Archive -LiteralPath $auditFull -DestinationPath $zipFull -Force

[pscustomobject]@{
    auditFolder = $auditFull
    auditZip = $zipFull
    timestamp = $timestamp
    activeWorkItems = $activeWorkItems
    alertsSent = $sentAlerts
    finalResult = 'partial-pass-with-documented-blockers'
} | ConvertTo-Json -Depth 5
