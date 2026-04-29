# Agent Operational Guardrails

This document holds the deeper project rules that should not crowd `AGENTS.md`. Read the sections relevant to the task before changing live Power Platform artifacts.

## Harness Principles For This Repo

- `AGENTS.md` is the map. This file and the rest of `docs/` are the deeper source of truth.
- Make the application legible to agents: record scripts, commands, live counts, screenshots when safe, exported metadata, and validation JSON in the repo workspace.
- Treat failures as missing harness, missing docs, missing validation, or missing mechanical checks. Improve those assets instead of retrying blindly.
- Prefer narrow changes with strong evidence over broad rewrites with weak evidence.
- Write durable repair paths in `docs/ops/` when a production pitfall is found.

## Environment And Workspace Rules

Current production, to be retired later:

- Power Pages: `https://operationhub.powerappsportals.com/`
- Dataverse: `https://regionaloperationshub.crm.dynamics.com/`

Dev / production-candidate:

- Power Pages: `https://operationscenter.powerappsportals.com/`
- Dataverse: `https://orga632edd5.crm3.dynamics.com/`

Rules:

- Do not assume the active PAC profile targets the intended environment.
- Always pass or verify the target URL before Power Pages, Dataverse, or Power Automate changes.
- Keep live-session scratch files out of final artifacts.
- Mirror durable docs/scripts/solution changes into `tmp-github-QuoteFollowUp`.
- Save temporary replay/seed/repair evidence in `results/` with affected row ids and timestamps.

## Data Contracts

Current-state operational tables:

- `qfu_quote` is keyed by `qfu_sourceid = branch|SP830CA|quotenumber`.
- `qfu_backorder` is keyed by `qfu_sourceid = branch|ZBO|salesdoc|line`.
- `qfu_marginexception` is a snapshot/history table, not a current-state queue.
- `qfu_deliverynotpgi` is a snapshot table with explicit active/inactive lifecycle.

Lifecycle rules:

- Current-state lifecycle fields are `qfu_active`, `qfu_inactiveon`, and `qfu_lastseenon`.
- During migration/repair work, `qfu_active = null` on `qfu_quote` or `qfu_backorder` means legacy-active until lifecycle backfill proves zero gaps.
- Re-seeing the same source row must update in place.
- A row that disappears from the latest current-state snapshot must be marked inactive, not left active and not replaced.
- More than one active `qfu_deliverynotpgi` row per canonical key is a defect.
- In this environment, `qfu_deliverynotpgi.qfu_active` can be inverted for live rows. Treat `qfu_inactiveon` as the hard inactive signal until the writer path is fixed.

Dashboard rules:

- Summary tables should feed dashboards. Do not calculate heavy branch/region dashboard KPIs from raw transactional rows on page load.
- Every KPI must have a traceable source.
- Do not silently fall back to zero when source rows exist.
- If analytics, freshness, delivery readiness, or budget pacing looks wrong, validate Dataverse ingestion first.

## Power Automate Rules

Architecture:

- Use child flows for reusable logic.
- Keep mailbox trigger flows thin.
- Use reusable parsing, normalization, upsert, and summarization flows/jobs.
- Keep flows solution-aware.
- Production ingestion must be Power Automate only. Do not reintroduce local scheduled-task or timer-based recurring fallbacks.

Mail/replay:

- Branch mail should continue to land in the main inbox unless the operating rule explicitly changes.
- Replay helpers must assume Inbox-only routing and fail closed if targeting a moved folder or alternate mailbox.
- Replay helpers must require an explicit branch filter and validate it before sending.
- Never infer target branch from display name, subject suffix, or folder name.
- Shared mailbox triggers must tolerate subject and attachment naming variants through configuration, not ad hoc branch-specific hardcoding.

Source-specific flow rules:

- ZBO quantity fields must be normalized before Dataverse upsert.
- Clamp source `qtyNotOnDel` and `qtyOnDelNotPgid` at zero in flow/parser logic because SAP workbooks can emit negative values and `qfu_backorder.qfu_qtynotondel` rejects negatives.
- Current-month SA1300 budget logic must treat a missing `qfu_budgetarchive` row as normal and resolve the target from workbook `Location Summary` Month-End Plan before failing.
- Current-month SA1300 summary sync has the same missing-archive behavior.

Freshness:

- `qfu_ingestionbatch` is the canonical freshness source for analytics.
- If `qfu_ingestionbatch` lags behind fresher live operational rows, treat it as an ingestion defect.
- Runtime analytics may temporarily prefer fresher live backlog or dispatch timestamps to avoid false stale labels, but the permanent fix is the flow that should update stable ingestion rows.

Flow repair:

- Keep flow generators, runtime readiness checks, and live repair scripts in sync.
- Prefer narrow live-flow patches over broad canonical replacements.
- Broad repairs can fail template validation if action dependencies are not on the live `runAfter` path.
- If XRM workflow update or solution import fails with a flow-server `NullReferenceException`, stop retrying the same path.
- After any `TemplateValidationError`, stop retrying the same broad template import/update path.
- Use a narrow Flow REST patch or create-new-flow mitigation and document it.
- After solution import, verify workflow rows are `Activated` before disabling legacy flows.
- Time-box `Add-PowerAppsAccount` and other interactive auth steps.
- PAC auth and Dataverse XRM auth can still be healthy when `Add-PowerAppsAccount` stalls.
- For Dataverse/XRM scripts, use Windows PowerShell Desktop (`powershell`) when `Microsoft.Xrm.Data.Powershell` is involved.
- Legacy SA1300 or ZBO flows should only be disabled after the replacement flow is confirmed enabled and running.
- Never leave legacy and replacement writers enabled together for the same branch/source family.
- Generated replacement flows must preserve stable connector names in both `properties.connectionReferences` and action `host.connectionName`.
- If live repair starts changing `runAfter` topology or the workflow row remains Draft/Unpublished after import, stop patching live graph in place. Regenerate, import, resave, and enable replacement before retiring legacy.

Validation order for flow-backed fixes:

1. generator/tests,
2. Dataverse rows,
3. portal render,
4. Power Automate run history.

Run history and browser token traces are supporting evidence, not primary proof.

## Power Pages Rules

This project uses the Enhanced data model.

Before changing portal artifacts:

1. Verify target environment/site.
2. Run `pac pages download ... -mv Enhanced`.
3. Edit the freshly downloaded local source.
4. Upload only after reviewing changed files.
5. Document download path, environment, site, and timestamp.

Runtime architecture:

- The monitoring experience is custom web templates plus JavaScript runtime.
- Core runtime template: `powerpages-live/operations-hub---operationhub/web-templates/qfu-regional-runtime/QFU-Regional-Runtime.webtemplate.source.html`.
- Default data path is portal `/_api` calls backed by `Webapi/<table>/enabled` and `Webapi/<table>/fields` site settings.
- Matching site settings live in `powerpages-live/operations-hub---operationhub/sitesetting.yml`.
- Do not assume classic Basic Forms, Entity Lists, or non-Enhanced portal export patterns unless refreshed local source proves the page depends on them.

Field whitelist:

- If a change adds a field to any portal `/_api` read, update the corresponding `Webapi/<table>/fields` whitelist in the same change.
- Unauthorized/degraded portal data is often a whitelist or table permission defect, not a rendering defect.

UX/performance:

- The site is Bootstrap V5-enabled.
- Preserve the current custom runtime/CSS approach.
- Optimize dense operational views for desktop first while keeping responsive behavior reasonable.
- Hub KPI shell target: under 2 seconds.
- Region KPI load target: under 3 seconds.
- Branch KPI strip target: under 2 seconds.
- Detail lists should paginate.
- Avoid loading every operational row on first paint.

Verification:

- Authenticated browser proof matters. Public unauthenticated requests can redirect to Microsoft Entra sign-in.
- Use authenticated Playwright/browser evidence or backend/runtime proof.
- Chrome/CDP browser debugging is supporting evidence only, not proof a cloud flow is healthy or activated.

Analytics-specific:

- The analytics view must explicitly load `qfu_deliverynotpgi` for ready-to-ship or shipment-adjacent KPIs.
- If a KPI card shows zero but Dataverse has current rows, verify prefetch and permission scope before changing formulas.
- If `qfu_budget` is newer than current-day `qfu_branchdailysummary`, do not surface a budget actual mismatch as business warning until Dataverse proves the summary is not simply lagging.

## Revenue Follow-Up Workbench Rules

Roles and identities:

- There is no SSR role.
- Roles are TSR, CSSR, Manager, GM, and Admin.
- AM Number is the TSR business identity alias.
- CSSR Number is the CSSR business identity alias.
- Names are display/fallback only and are not trusted for automatic routing.
- AM/CSSR aliases are not security identities.
- Routing uses `qfu_staffalias` to `qfu_staff` to optional Dataverse `systemuser`.
- Emails/systemusers are not required until alerts/security phases.
- Current-user filtering must not be assumed until staff records map to systemusers.

Quote/work item rules:

- Quote threshold is based on total quote value.
- High-value quote threshold is `$3,000`.
- Threshold operator is greater than or equal.
- Low-value quotes under `$3,000` are reporting-only for MVP.
- Quotes at or above `$3,000` require 3 follow-up attempts.
- First follow-up due date is next business day after import.
- Missing TSR ownership goes to manager exception queue.
- Sticky notes live on `qfu_workitem` and must not be overwritten.
- Every real follow-up attempt must log `qfu_workitemaction.qfu_actionon`.
- `qfu_countsasattempt` controls whether an action counts toward required attempts.

Alias handling:

- Invalid aliases must not become staff or staff alias records: blank, `0`, `00000000`, `NULL`, `N/A`, `NA`, `NONE`.
- Normalize Excel decimal aliases such as `7001634.0` to `7001634`.
- Do not guess staff mappings from names.

Queue handoff:

- Queue owner fields do not replace TSR/CSSR identity fields.
- `qfu_currentqueueownerstaff` and `qfu_currentqueuerole` are true queue state.
- Helper fields may be used for stable Power Apps filtering/display:
  - `qfu_currentqueueroletext`
  - `qfu_currentqueueownerstaffkey`
  - `qfu_currentqueueownername`
- Handoff actions must not count as follow-up attempts.
- Handoff should preserve completed attempts and last-followed-up fields.
- Alerts remain off until explicitly enabled.

## Security

- Assume internal-only unless requirements say otherwise.
- Design branch, region, manager, GM, and HQ access intentionally.
- Do not leak cross-branch data accidentally.
- Table permissions and role logic must be documented.
- Role-aware UI fallback is not production security.
- Final security must wait for verified `qfu_staff` to Dataverse `systemuser` mapping.

## Validation And Evidence

For each phase or repair, capture:

- target environment/site,
- PAC profile/auth state,
- current branch and git status,
- before/after live counts,
- exact scripts and commands run,
- row ids for controlled smoke tests or replays,
- flow ids/workflow ids for flow changes,
- solution export and unpack paths,
- Power Pages download/upload paths,
- browser evidence when safe,
- skipped tests and reasons,
- blockers and required human action.

Audit zips must exclude secrets, tokens, credentials, tenant IDs, client secrets, private keys, production customer data, `.git`, `node_modules`, `bin`, `obj`, `dist`, `build`, `.venv`, and `__pycache__`.

When returning an audit zip to the user, use a clickable absolute path link.

## Incident References

- Analytics self-populate guardrails: `docs/ops/analytics-selfpopulate-incident-20260409.md`
- Power Platform environment map: `docs/ops/power-platform-environment-map-20260428.md`
- OperationsCenter flow autonomy unblock: `docs/ops/operationscenter-flow-autonomy-unblock-20260428.md`
- Ready-to-ship flow contract/remediation: `docs/flows/READY_TO_SHIP_NOT_PGID_FLOW_CONTRACT.md`, `docs/flows/READY_TO_SHIP_NOT_PGID_FLOW_REMEDIATION.md`

If a new production pitfall is found, write a focused `docs/ops/` note and a `results/` validation artifact so the defect is not rediscovered in a later session.
