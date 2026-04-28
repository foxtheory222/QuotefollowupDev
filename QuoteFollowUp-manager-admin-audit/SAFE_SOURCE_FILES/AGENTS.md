# AGENTS.md

## Project
Quote Follow Up (QFU) regional rollout

This repository is for scaling an existing branch-level Quote Follow Up / Backorder Monitoring solution into a regional and eventually company-wide platform.

Current reality:
- A working Power Pages branch monitoring site already exists.
- The current app is useful, but not fully standardized, not fully hardened, and not yet designed for multi-branch rollout.
- The goal is to keep the existing strengths, centralize the backend, and avoid rebuilding the wrong thing.

Primary objective:
Build a scalable internal monitoring platform for quote follow-up, overdue quotes, overdue backorders, budget pacing, and team progress across regions and branches.

## Non-negotiables
1. Do not rewrite the whole product into a model-driven app.
2. Keep Power Pages as the primary monitoring experience unless explicitly told otherwise.
3. Use Dataverse as the single source of truth.
4. Use Power Automate for ingestion, normalization, and summarization.
5. Prefer configuration-driven design over hard-coded branch-specific logic.
6. No fake data in final implementation code unless clearly marked as fixture/demo data.
7. No branch cloning as a long-term architecture.
8. No hard-coded environment URLs, mailbox addresses, GUIDs, or branch IDs in production code.
9. No UI-only progress. Backend, security, and performance must stay aligned with UI work.
10. If something is unclear, preserve the existing behavior and document assumptions instead of inventing new business rules.

## Product vision
The final product should work like this:

### 1. Hub
A landing page showing regions or divisions with high-level KPI cards and status indicators.

### 2. Region page
A region-level dashboard showing:
- quick KPI summary
- branch cards
- top exceptions
- data freshness / import health
- drill-in to each branch

### 3. Branch page
A branch dashboard showing:
- quote follow-up metrics
- overdue quotes
- overdue backorders
- budget progress
- team workload / ownership visibility
- drill-through detail lists

### 4. Admin / Ops surface
A lightweight internal admin experience for:
- branch configuration
- region configuration
- mailbox mapping
- import failure review
- rerun / replay tools
- user/role mapping
- threshold settings

This admin surface can be model-driven if needed, but the monitoring UX should remain Power Pages unless directed otherwise.

## Architecture direction
Target architecture:

- Front end:
  - Power Pages for Hub / Region / Branch monitoring
  - Optional model-driven admin app for back-office configuration

- Backend:
  - Dataverse centralized schema
  - Raw import tables
  - Normalized operational tables
  - Summary / KPI tables

- Automation:
  - mailbox-specific ingress flows only where necessary
  - shared child flows for parsing and normalization
  - reusable summarization flows/jobs
  - solution-aware flows only

- ALM:
  - source-controlled Power Pages site via pac pages
  - source-controlled solution artifacts
  - environment variables
  - connection references
  - deployment pipeline / repeatable promotion path

## Engineering rules
### General
- Keep solutions simple and auditable.
- Prefer one reusable component over three branch-specific copies.
- If a defect is found in a shared branch pattern, evaluate and fix it uniformly across every affected branch unless it is proven branch-specific.
- Favor deterministic KPI calculations.
- Every KPI must have a traceable source.
- Every page should degrade gracefully if data is stale or missing.

### Data
- Raw import data must not be overwritten destructively unless there is an intentional retention/archive policy.
- Normalized tables should be shaped for reporting and app performance.
- Summary tables should feed dashboards. Do not calculate heavy dashboard KPIs from raw transactional rows on page load.
- Include import timestamps and freshness markers.

### Operational current-state tables
- `qfu_quote` is a current-state table keyed by `qfu_sourceid = branch|SP830CA|quotenumber`.
- `qfu_backorder` is a current-state table keyed by `qfu_sourceid = branch|ZBO|salesdoc|line`.
- `qfu_marginexception` is a snapshot/history table, not a current-state queue.
- `qfu_deliverynotpgi` is a snapshot table with explicit active/inactive lifecycle; inactive history reappearance is allowed, but more than one active row per canonical key is a defect.
- Current-state lifecycle fields for quote/backorder are `qfu_active`, `qfu_inactiveon`, and `qfu_lastseenon`.
- During migration or repair work, `qfu_active = null` on `qfu_quote` or `qfu_backorder` must be treated as legacy-active until the lifecycle backfill artifact shows zero remaining gaps.
- Re-seeing the same source row must update in place. Disappearing from the latest current-state snapshot must mark the row inactive, not leave it active and not create a replacement row.

### Power Automate
- Use child flows for reusable logic.
- Keep mailbox trigger logic thin.
- Log failures with enough context to replay.
- Design for scale across branches.
- Avoid giant monolithic flows that mix trigger, parsing, transformation, upsert, and summary logic in one place.
- Production ingestion must be Power Automate only. Do not reintroduce local scheduled-task or timer-based fallbacks for recurring branch imports, summary sync, or freshness repair.
- Branch mail should continue to land in the main inbox. Do not move source reports to a separate mailbox folder unless the operating rule changes explicitly.
- Replay helpers must assume Inbox-only routing and fail closed if a helper tries to target a moved folder or alternate mailbox.
- Replay helpers must require an explicit branch filter and validate it before sending. Never infer the target branch from display name, subject suffix, or folder name.
- Shared mailbox trigger logic must tolerate subject and attachment naming variants through configuration, not ad hoc branch-specific hard-coding.
- ZBO quantity fields must be normalized before Dataverse upsert. Clamp source `qtyNotOnDel` and `qtyOnDelNotPgid` at zero in the flow/parser layer; SAP workbooks can emit negative `Qty Not On Del`, and `qfu_backorder.qfu_qtynotondel` rejects negatives.
- For current-state writers such as ZBO and SP830, never leave legacy and replacement flows enabled together for the same branch/source family. Overlapping writers create duplicate canonical `qfu_quote` or `qfu_backorder` rows even when both flows individually succeed.
- When the analytics page or budget pacing looks wrong, check Dataverse ingestion first. Do not assume a page defect until the source rows are proven present and fresh.
- `qfu_ingestionbatch` is the canonical freshness source for analytics. If analytics freshness is wrong, fix the flow that writes the stable ingestion row, not the page text.
- If a stable `qfu_ingestionbatch` row lags behind fresher live operational rows, treat that as an ingestion defect to repair and document. The analytics runtime may temporarily prefer the newer live backlog or dispatch snapshot to avoid lying about freshness, but the permanent fix is still the flow that should have refreshed the stable ingestion row.
- Current-month SA1300 budget logic must treat a missing `qfu_budgetarchive` row as a normal case. The flow must be able to resolve the target from the workbook `Location Summary` Month-End Plan before failing.
- Current-month SA1300 summary sync must treat a missing `qfu_budgetarchive` row as a normal case and resolve the target from the workbook month-end plan before failing.
- Keep the flow generator, runtime readiness checks, and live repair scripts in sync. If a flow expression or action name changes in the generator, update every script that validates or patches that flow in the same change.
- Prefer narrow live-flow patches over broad canonical branch replacement. Broad repairs can fail template validation if action dependencies are not on the live `runAfter` path.
- If XRM workflow update or solution import fails with a Microsoft flow-server `NullReferenceException`, stop retrying the same path. Record the artifact, switch to a narrower Flow REST patch or create-new-flow path, and use a documented mitigation if production is blocked.
- After any `TemplateValidationError`, stop retrying the same broad flow template import or update path. Switch to a narrow Flow REST patch or create-new-flow path, then validate the live artifact.
- After any solution import for cloud flows, verify the imported workflow rows are actually `Activated` before disabling the legacy flow. `pac solution import` can succeed while the imported replacement still lands in `Draft`.
- Time-box `Add-PowerAppsAccount` and other interactive auth steps. If shell auth stalls, do not treat that as proof the patch itself is invalid.
- PAC auth and Dataverse XRM auth can still be healthy even when `Add-PowerAppsAccount` stalls. Check the local auth state before assuming the service path is broken.
- For Dataverse/XRM work, use Windows PowerShell Desktop (`powershell`), not PowerShell Core, because `Microsoft.Xrm.Data.Powershell` is not reliably compatible with Core.
- Verify flow-backed fixes in this order: generator/tests, Dataverse rows, portal render, then Power Automate run history. Run history and browser token fetches are supporting evidence, not the primary source of truth.
- Chrome/CDP browser debugging is supporting evidence only. Use it to inspect the authenticated session and flow-network traces when the UI is opaque, but do not treat browser-local state as proof that a cloud flow is healthy or activated.
- If an emergency monthly target seed is required to keep production live, save the seeded values, affected row ids, replay artifact, and validation artifact in `results` instead of treating it as an undocumented manual fix.
- Legacy SA1300 or ZBO flows should only be disabled after the replacement flow is confirmed enabled and running. Do not leave production with both the legacy and replacement paths off.
- Generated replacement flows must preserve the stable live connector names in both `properties.connectionReferences` and action `host.connectionName` values. Mixed suffix variants such as `shared_commondataserviceforapps-1` vs `shared_commondataserviceforapps`, or `shared_excelonlinebusiness` vs `shared_excelonlinebusiness-1`, can import a flow that cannot be started.
- If a live repair starts changing `runAfter` topology or the workflow row remains Draft/Unpublished after import, stop patching the live graph in place. Regenerate, import, resave, and enable a replacement flow before retiring the legacy flow.

### Power Pages
- Build dynamic templates and reusable components.
- Avoid static hard-coded branch pages for long-term rollout.
- Keep security in mind at all times.
- Design for internal use first, polish second.
- Favor responsive layouts but optimize desktop first if that is the primary usage pattern.
- Before changing any Power Pages artifact, run `pac pages download` from the target environment/site and refresh the local site source first.
- For Power Pages work, the freshly downloaded local files are the source of truth. Do not assume the repo copy is current if it has not just been refreshed from the target environment.
- If the latest site source has not been downloaded and confirmed, do not edit or upload Power Pages changes.
- The analytics view must explicitly load `qfu_deliverynotpgi` when it renders ready-to-ship or shipment-adjacent KPIs. Do not assume the branch page data load covers analytics.
- If a KPI card shows zero but Dataverse has current rows, verify the page prefetch and permission scope before changing the KPI formula.
- Analytics freshness, delivery readiness, and overdue counts must degrade gracefully, but they must never silently fall back to zero when source rows exist.
- In this environment, `qfu_deliverynotpgi.qfu_active` can be inverted for live rows. Treat `qfu_inactiveon` as the hard inactive signal, and if `qfu_active` is explicitly `false` / `No` with no `qfu_inactiveon`, treat the row as active for runtime analytics until the writer path is proven fixed.
- If `qfu_budget` is newer than the current-day `qfu_branchdailysummary` row, do not surface a budget actual mismatch as a business warning until Dataverse proves the summary is not simply lagging behind fresher budget data.
- If `qfu_ingestionbatch` lags behind fresher `qfu_backorder` or `qfu_deliverynotpgi` rows, the analytics runtime may use the fresher live operational timestamp to avoid false stale labels, but the flow defect must still be repaired and documented.

### Security
- Assume internal-only unless requirements say otherwise.
- Design branch / region / HQ access intentionally.
- Do not leak cross-branch data accidentally.
- Keep role logic and table permissions documented.

## Performance expectations
These are target gates, not vague aspirations.

### Hub
- initial load target: under 2 seconds for KPI shell
- no heavy raw-table queries directly from page render

### Region page
- initial KPI load target: under 3 seconds
- branch cards should render from summary data
- top exceptions should be capped and query-efficient

### Branch page
- KPI strip under 2 seconds
- detail lists should paginate
- avoid loading every operational row on first paint

### Automation
- ingestion target for standard mailbox events: under 5 minutes from arrival to Dataverse availability
- failures must be visible and traceable
- stale data must be obvious in UI

## Delivery style
Work in tight phases. Do not skip ahead.

For each phase:
1. define scope
2. define deliverables
3. define what is explicitly out of scope
4. define success gates
5. implement only that phase

Do not silently expand scope.

## Phase discipline
### Phase 0
Architecture freeze and foundation decisions

### Phase 1
Pilot backend + shell UI for one region / limited branches

### Phase 2
Dynamic regional dashboard with secure branch drill-down

### Phase 3
Multi-branch rollout and onboarding path

### Phase 4
Hardening, monitoring, replay, support tooling

If asked to "just build everything", still structure work according to phase boundaries and document what belongs where.

## What to avoid
- giant rewrites
- over-designed abstractions
- static cloned pages per branch
- mixing demo assumptions into production logic
- shiny dashboard work without backend readiness
- branch-specific special-case logic unless it is config-driven and documented
- hiding problems instead of surfacing them

## When making changes
Always state:
- what you changed
- why you changed it
- what assumptions you made
- what still needs validation
- what could break
- For Power Pages changes, also state when the site source was last downloaded, from which environment/site, and confirm the edits were made against that refreshed local baseline.

## Preferred outputs
When working on this project, produce:
- architecture docs
- phased implementation plans
- page-level implementation checklists
- data model proposals
- flow decomposition plans
- ALM / deployment notes
- test checklists
- admin onboarding instructions

## Repo structure suggestion
/docs
  /architecture
  /phases
  /pages
  /flows
  /security
  /ops
/powerpages
/solution
/scripts
/fixtures
/results

## Workspace Reality
- `QuoteFollowUpRegion` is the working operations folder, not a Git repository root.
- The current durable repo copy used for long-lived source preservation is nested under `tmp-github-QuoteFollowUp`.
- The current synced branch in that durable repo is `codex/home-sync-20260410-live-state`.
- The older `tmp-github-quotefollowupv2/quoteFollowUpV2` clone is not the current source of truth and its configured remote is no longer usable.
- If script fixes are meant to survive beyond the current workspace session, mirror them into the durable repo copy before closing the task.
- `qfu_ingestionbatch` freshness rows, SA1300 summary rows, and Power Pages analytics must be validated in Dataverse before UI changes are treated as fixed.
- For branch support issues, prefer narrow repairs that preserve the live path and prove the next unattended run, rather than broad rewrites or manual one-off local jobs.
- If a repair requires a temporary replay or seed, record the exact row ids, timestamps, and validation artifacts in `results/`.

## Incident References
- Analytics self-populate incident notes and required guardrails live in `docs/ops/analytics-selfpopulate-incident-20260409.md`.
- Before changing SA1300 budget ingestion, analytics self-populate logic, or live repair scripts, read that incident note first.

## Final instruction
This project has already had planning drift before.
Stay brutally aligned to the actual product goal:
a centralized internal quote follow-up and branch operations monitoring platform that scales cleanly.
When a production pitfall is found, document the durable fix path, the validation artifact, and any required generator/repair-script updates so the same defect cannot recur unnoticed.
For recurring ingestion failures, prefer fixing the shared Power Automate source of truth over local or UI-only workarounds.
