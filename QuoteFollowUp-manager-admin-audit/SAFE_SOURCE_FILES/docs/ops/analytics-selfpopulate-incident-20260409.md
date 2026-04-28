# Analytics Self-Populate Incident Notes

Date: 2026-04-09  
Scope: Branch Analytics self-populate / SA1300 current-month budget target path

## Why this note exists

This incident exposed several repeatable failure modes in the repo, the live Power Automate deployment path, and the verification workflow.

Future work on analytics, SA1300 budget ingestion, or live-flow repair should start here before changing code or touching production.

## Incident summary

The analytics page itself was not the missing piece.

The page already self-populates from Dataverse rows created by report-ingestion flows. The live failure was in the current-month SA1300 budget target path:

- the live SA1300 budget flows expected a current-month `qfu_budgetarchive` row to exist
- when that row did not exist for April 2026, the flow failed with `BudgetGoalMissing`
- the analytics page then had no trustworthy current-month target to read

The permanent source fix is to let the SA1300 flow fall back to the workbook `Location Summary` Month-End Plan before failing.

## Exact issues encountered

### 1. Workspace root is not a Git repository

Symptom:

- `git status` at `QuoteFollowUpRegion` failed with `fatal: not a git repository`

Impact:

- source edits in the working folder can drift from the durable repo copy
- it is easy to think changes are â€œsaved in the repoâ€ when they are only in the workspace

What to do from now on:

- treat `QuoteFollowUpRegion` as the working operations folder
- treat `tmp-github-QuoteFollowUp` as the current durable repo copy that must be kept in sync when scripts are changed

### 2. The analytics page was already Dataverse-driven

Symptom:

- it was tempting to patch the analytics page itself when the page showed stale targets

Actual state:

- the runtime already reads:
  - `qfu_budget` and `qfu_budgetarchive` for budget target/actual context
  - `qfu_financesnapshot` and `qfu_financevariance` for GL060 finance
  - `qfu_quote` and `qfu_quoteline` for SP830 quote analytics
  - `qfu_backorder` for ZBO backlog analytics
  - `qfu_marginexception` and `qfu_lateorderexception` for SA1300 review snapshots

Impact:

- patching the page would have treated a data-ingestion failure as a UI problem

What to do from now on:

- for analytics defects, inspect the Dataverse inputs first
- only change the page if the required Dataverse rows are present and the rendering is still wrong

### 3. Current-month SA1300 target path depended on `qfu_budgetarchive`

Symptom:

- live SA1300 flow failure: `BudgetGoalMissing`
- current month had `qfu_budget` rows but no target source the flow accepted

Root cause:

- the live flow only accepted `qfu_budgetarchive.qfu_budgetgoal`
- it did not fall back to the SA1300 workbookâ€™s Month-End Plan value

Permanent fix:

- the generator now creates a dedicated `Location Summary` Month-End Plan table using:
  - range: `'Location Summary'!H2:H500`
- the resolved goal expression is now:
  - `@coalesce(first(outputs('Get_Budget_Goal_From_Archives')?['body/value'])?['qfu_budgetgoal'], outputs('Resolve_Budget_Goal_From_SA1300_Plan'), outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_budgetgoal'])`

What to do from now on:

- never ship a SA1300 budget flow that can only succeed when a current-month archive row already exists
- treat â€œnew month without pre-seeded archive rowâ€ as a standard case, not an edge case

### 4. Validation scripts drifted behind the generator

Symptom:

- readiness/repair scripts still expected `@outputs('Resolve_Budget_Goal')`
- generator had already moved to the coalesced live expression above

Impact:

- validation could falsely report the new correct shape as wrong

What to do from now on:

- whenever the flow generator changes an expression or action name, update all dependent readiness/repair scripts in the same change
- specifically keep these in sync:
  - `scripts/create-southern-alberta-pilot-flow-solution.ps1`
  - `scripts/check-southern-alberta-runtime-readiness.ps1`
  - `scripts/repair-live-sa1300-abnormal-margin-sync-xrm.ps1`
  - any new targeted repair scripts

### 4b. ZBO workbook quantities can violate Dataverse field ranges

Symptom:

- live `4171-BackOrder-Update-ZBO-Live-R2` failed on April 15, 2026 even though the mailbox trigger and attachment path were healthy

Root cause:

- the workbook row for `4171|ZBO|1522849703|170` contained `Qty On Del Not PGI'd = 8` and `Qty Not On Del = -7`
- the flow passed that raw negative `qtyNotOnDel` into `qfu_backorder.qfu_qtynotondel`
- Dataverse rejected the update with `0x80044330` because `qfu_qtynotondel` only accepts `0` and above

What to do from now on:

- clamp ZBO `qtyNotOnDel` and `qtyOnDelNotPgid` at zero in the parser/generator layer before any Dataverse create or update
- if a ZBO replacement flow fails, inspect the run action repetition inputs directly before rewriting the flow; a bad workbook quantity can look like a generic flow failure until the exact row is isolated

### 4c. Overlapping legacy and replacement current-state flows create duplicate canonical rows

Symptom:

- the analytics runtime raised duplicate operational row warnings for `qfu_backorder`
- direct Dataverse checks showed more than one active row for the same canonical `qfu_sourceid`

Root cause:

- both legacy and replacement ZBO flows were allowed to write the same current-state table for the same branch during cutover
- each flow could succeed independently while still creating duplicate `qfu_backorder` rows

What to do from now on:

- never leave legacy and replacement current-state writers enabled together for the same branch/source family
- confirm the replacement flow is enabled and processing successfully, then disable the legacy flow in the same cutover
- if overlap already happened, repair the duplicate current-state rows in Dataverse and save the delete artifact in `results`

### 5. Dataverse workflow update path failed with Microsoft-side `NullReferenceException`

Symptom:

- in-place workflow update through Dataverse/XRM failed even with valid source JSON

Artifacts:

- `results/live-refresh-20260408-branch-fixes/sa1300-budget-selfpopulate-live-repair-20260409.json`
- `results/live-refresh-20260408-branch-fixes/sa1300-budget-selfpopulate-live-repair-20260409b.json`

Impact:

- the permanent source-controlled fix could not simply be pushed into the existing live flows using the XRM clientdata update path

What to do from now on:

- if XRM workflow update returns a Microsoft flow-server `NullReferenceException`, stop retrying the same path
- record the artifact immediately
- switch to one of:
  - narrower Flow REST PATCH
  - create-new-flow deployment
  - explicit monthly mitigation seed if production is blocked

### 6. Broad Flow REST canonical patching can fail with `InvalidOpenApiFlow`

Symptom:

- broader live patch attempts failed with:
  - `Select_CAD_Ops_Daily_Rows` cannot reference `Filter_CAD_Ops_Daily_Rows` because it is not on the `runAfter` path

Artifacts:

- `results/sa1300-live-repair-with-opsdaily-budget-payload-20260408c.json`

Impact:

- broad â€œreplace the whole SA1300 branch from canonicalâ€ repairs are unsafe unless the canonical workflow itself validates against the live action graph

What to do from now on:

- prefer narrow live repairs that patch only the required actions
- if you must apply a broader canonical branch, validate action dependency order first
- do not assume canonical JSON is saveable just because it is locally generated

### 7. `Add-PowerAppsAccount` can hang in unattended shell runs

Symptom:

- the new Flow REST repair script stalled at `Add-PowerAppsAccount`
- no PATCH was reached

Impact:

- a valid repair path can still fail operationally due to interactive auth behavior

What to do from now on:

- time-box shell auth steps
- log progress before and after `Add-PowerAppsAccount`
- if it stalls, do not leave orphan shell sessions running
- prefer a known-good authenticated context when available

### 8. `Microsoft.Xrm.Data.Powershell` requires Windows PowerShell Desktop

Symptom:

- PowerShell Core emitted compatibility warnings for the XRM module

Impact:

- Dataverse checks can fail or behave inconsistently when run under the wrong shell host

What to do from now on:

- use `powershell`, not PowerShell Core, for:
  - `Microsoft.Xrm.Data.Powershell`
  - Dataverse XRM probes
  - repair scripts that depend on that module

### 9. Browser-based Flow API verification was unreliable

Symptom:

- direct fetches from the authenticated Power Automate tab later returned `403`
- the UI could still render while API fetches were blocked

Impact:

- run-history verification can look broken even when the flow is functioning

What to do from now on:

- do not treat browser/localStorage Flow API fetches as the primary source of truth
- use them only as supporting evidence

### 10a. Chrome/CDP is debugging only

What to do from now on:

- use Chrome/CDP only to inspect an authenticated Power Automate session, the browser-visible network trace, and opaque run-state details that are hard to reach from the UI
- do not treat browser-local tokens, request bodies, or run panes as proof that a cloud flow is healthy
- keep Dataverse rows and confirmed admin-flow state as the primary evidence

### 10. Dataverse row verification was the most reliable proof

What worked:

- checking live `qfu_budget` rows directly proved April state after replay:
  - one row per branch
  - non-null budget goal
  - fresh `qfu_lastupdated`

Artifacts:

- `results/live-refresh-20260408-branch-fixes/sa1300-april-target-seed.json`
- `results/live-refresh-20260408-branch-fixes/example-branch-replay-send-summary-sa1300-after-target-seed.json`
- `results/live-refresh-20260408-branch-fixes/analytics-selfpopulate-validation-20260409.md`

What to do from now on:

- verify in this order:
  1. generator/test output
  2. Dataverse rows
  3. portal rendering
  4. Power Automate run history

### 11. Emergency mitigation was valid and should be recorded, not hidden

What had to be done:

- seed current-month `qfu_budgetarchive` rows from the actual SA1300 Month-End Plan values
- update the matching `qfu_budget` rows
- replay the branch SA1300 examples

Impact:

- production behavior was restored for April 2026
- this does not replace deployment of the permanent flow definition fix

What to do from now on:

- if production is blocked and the root cause is a missing current-month target row, a documented seed is acceptable
- always save:
  - the seeded values
  - row ids created/updated
  - replay artifact
  - validation artifact

### 12. Durable repo copy must be mirrored after script fixes

What changed this time:

- the working-folder script fixes were copied into:
  - `tmp-github-QuoteFollowUp/scripts/create-southern-alberta-pilot-flow-solution.ps1`
  - `tmp-github-QuoteFollowUp/scripts/repair-live-sa1300-abnormal-margin-sync-xrm.ps1`
  - `tmp-github-QuoteFollowUp/scripts/repair-live-sa1300-budget-selfpopulate.ps1`

What to do from now on:

- when a fix is intended to survive beyond the current workspace, mirror it into the durable repo copy before closing the task

### 13. Main Inbox routing is the contract

What to do from now on:

- the branch mailboxes should stay on the main Inbox unless the operating rule changes explicitly
- replay helpers and live trigger repairs should treat folder moves as out of scope
- a branch-filter mismatch in a replay helper is a defect, not a valid fallback

### 14. Prefer replacement over graph surgery

What to do from now on:

- if a live cloud-flow repair would change `runAfter` topology, stop patching the live graph in place
- if an imported replacement remains Draft/Unpublished, regenerate or resave it until it can be enabled before disabling the legacy flow
- only use a narrow live patch when it preserves the existing dependency graph and connector bindings exactly

## Mandatory commands and artifacts for future work

### Regression test

- `python -m unittest tests.test_sa1300_budget_selfpopulate -v`

### Current-month budget health probe

- `powershell -ExecutionPolicy Bypass -File results\\tmp-check-all-branch-budget-health.ps1`

### SA1300 freshness probe

- `powershell -ExecutionPolicy Bypass -File results\\tmp-sa1300-refresh-check.ps1`

### Key artifacts

- `results/live-refresh-20260408-branch-fixes/sa1300-budget-selfpopulate-live-repair-20260409b.json`
- `results/live-refresh-20260408-branch-fixes/sa1300-april-target-seed.json`
- `results/live-refresh-20260408-branch-fixes/example-branch-replay-send-summary-sa1300-after-target-seed.json`
- `results/live-refresh-20260408-branch-fixes/analytics-selfpopulate-validation-20260409.md`

## Current truth as of this note

- The analytics page is working for April 2026 because the current-month Dataverse rows are now populated.
- The permanent source fix exists and is tested.
- The permanent live deployment into the existing SA1300 flows is still blocked by Microsoft-side flow-save behavior.
- The next month rollover is still a risk until the live flow definitions themselves are updated successfully.
