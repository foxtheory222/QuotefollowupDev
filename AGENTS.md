# AGENTS.md

## Purpose

Quote Follow Up (QFU) regional rollout is a Power Platform operations project for quote follow-up, overdue backorders, budget pacing, freight/import freshness, and branch/team workbench visibility.

This file is intentionally a map, not the full manual. Keep it short enough to stay useful in agent context. Put durable details in `docs/`, scripts, tests, and `results/` so future agents can inspect and verify the real system.

This follows the OpenAI harness-engineering pattern: humans steer, agents execute, repository knowledge is the system of record, and every fix should improve agent legibility for the next run.

## Current Product Direction

- Power Pages remains the primary monitoring experience for Hub, Region, Branch, and operational drill-downs.
- Dataverse is the source of truth.
- Power Automate is the production ingestion, normalization, and summarization layer.
- Model-driven apps/custom pages are allowed for admin/workbench workflows, not as a wholesale replacement for the monitoring site.
- Keep the system scalable across branches and regions. Prefer configuration over branch-specific copies.

## Environment Map

Always verify the active PAC/Dataverse target before changing anything.

- Current production, to retire later:
  - Power Pages: `https://operationhub.powerappsportals.com/`
  - Dataverse: `https://regionaloperationshub.crm.dynamics.com/`
- Dev / production-candidate:
  - Power Pages: `https://operationscenter.powerappsportals.com/`
  - Dataverse: `https://orga632edd5.crm3.dynamics.com/`

Workspace reality:

- `QuoteFollowUpRegion` is the working operations folder, not the durable git root.
- Durable source copy: `tmp-github-QuoteFollowUp`.
- Mirror durable docs/scripts/solution changes into `tmp-github-QuoteFollowUp` before closing work that should survive the session.
- Do not use `tmp-github-quotefollowupv2/quoteFollowUpV2` as source of truth.

## Start Here

Read only the docs needed for the task:

- Deep guardrails: `docs/agent-operational-guardrails.md`
- Regional rollout/product plan: `docs/QFU_REGIONAL_ROLLOUT_PLAN.md`
- Current state and handoff notes: `docs/CURRENT_STATE_NOTES.md`, `docs/HANDOFF_*.md`
- Power Pages branch pattern: `docs/pages/CANONICAL_BRANCH_PATTERN.md`
- Power Pages runtime: `powerpages-live/operations-hub---operationhub/web-templates/qfu-regional-runtime/QFU-Regional-Runtime.webtemplate.source.html`
- Power Pages site settings: `powerpages-live/operations-hub---operationhub/sitesetting.yml`
- Flow/ops incidents: `docs/ops/`
- Revenue Follow-Up workbench docs: `docs/revenue-follow-up-*.md`
- Results and validation artifacts: `results/`
- Solution artifacts: `solution/`

When touching SA1300 budget ingestion, analytics self-populate logic, or live repair scripts, read `docs/ops/analytics-selfpopulate-incident-20260409.md` first.

## Non-Negotiables

1. Do not rewrite the whole product into a model-driven app.
2. Keep Power Pages as the primary monitoring UX unless explicitly directed otherwise.
3. Use Dataverse as the single source of truth.
4. Use Power Automate for recurring production ingestion, normalization, summaries, and freshness repair.
5. Do not hardcode environment URLs, mailbox addresses, GUIDs, branch IDs, staff, emails, managers, or routing in production logic.
6. No fake data in final implementation code unless clearly marked as fixture/demo data.
7. No UI-only progress. Backend, security, data quality, and validation must stay aligned.
8. Preserve existing behavior when requirements are unclear, and document assumptions.
9. Do not replace `qfu_quote`, `qfu_quoteline`, `qfu_backorder`, or other imported operational source tables unless explicitly instructed.
10. Keep Power Pages on the Enhanced data model path.
11. Do not silently broaden a controlled repair into all branches or all records.
12. Do not send alerts/digests unless the current phase explicitly enables them.

## Default Agent Workflow

1. Identify the requested phase/scope and what is out of scope.
2. Verify the target environment and auth state.
3. Read the smallest relevant doc set from the map above.
4. Inspect live Dataverse/Power Pages/flow state before edits.
5. Make narrow, reversible changes using existing patterns.
6. Validate in this order when flow-backed or portal-backed:
   - generator/scripts/tests,
   - Dataverse rows,
   - portal or app render,
   - Power Automate run history.
7. Record durable evidence in `results/`.
8. Update docs when behavior, assumptions, or repair paths change.
9. Export/unpack solutions or refresh/upload Power Pages only when metadata/site artifacts changed.
10. Mirror durable changes into `tmp-github-QuoteFollowUp` when appropriate.

If a step is blocked by auth, tooling, flow import failures, or browser sign-in, document the exact blocker and the next human action. Do not claim success.

## Power Pages Rules

- Before changing Power Pages artifacts, run `pac pages download ... -mv Enhanced` against the target site/environment and edit that fresh source.
- The runtime is custom web templates plus JavaScript, not classic Basic Forms/Entity Lists by default.
- If adding a `/_api` field read, update the matching `Webapi/<table>/fields` site setting in the same change.
- Authenticated browser evidence matters. Anonymous requests often redirect to Microsoft Entra sign-in and are not proof of failure.
- Pages must degrade gracefully for stale/missing data, but must not silently show zero when source rows exist.

## Dataverse And Power Automate Rules

- Current-state rows must update in place. Missing rows from a new source snapshot should be marked inactive, not duplicated.
- Never leave legacy and replacement writers enabled together for the same branch/source family.
- Use child flows and shared parsing/normalization logic where possible.
- Keep connector names and connection references stable in generated/imported flows.
- After solution import, verify cloud flows are activated before disabling legacy flows.
- For Dataverse/XRM PowerShell work, prefer Windows PowerShell Desktop (`powershell`) when `Microsoft.Xrm.Data.Powershell` is involved.
- If solution import or workflow update hits a flow-server `NullReferenceException` or `TemplateValidationError`, stop retrying the same broad path. Switch to a narrow REST patch or create-new-flow mitigation and document it.

## Revenue Follow-Up Workbench Rules

- There is no SSR role.
- Roles are TSR, CSSR, Manager, GM, and Admin.
- AM Number is the TSR business alias. CSSR Number is the CSSR business alias.
- AM/CSSR aliases are not security identities.
- Routing uses `qfu_staffalias` to `qfu_staff` to optional Dataverse `systemuser`.
- Do not guess emails, Dataverse users, managers, GMs, branch routing, AM numbers, or CSSR numbers.
- Quotes at or above `$3,000` require 3 follow-up attempts.
- Sticky notes live on `qfu_workitem` and must not be overwritten by imports or rollups.
- Follow-up attempts are logged in `qfu_workitemaction`; `qfu_countsasattempt` controls attempt counting.
- Handoff actions do not count as attempts.
- Current-user filtering is not reliable until `qfu_staff` is mapped to `systemuser`.

## Validation And Audit

Every phase or production repair should leave an audit trail:

- current branch and git status,
- target environment/site,
- before/after live counts,
- files changed,
- scripts run,
- solution export/unpack path when relevant,
- Power Pages download/upload paths when relevant,
- validation evidence,
- skipped tests with reasons,
- blockers and unresolved decisions.

Do not include secrets, tokens, credentials, tenant IDs, client secrets, private keys, production customer data, `.git`, `node_modules`, `bin`, `obj`, `dist`, `build`, `.venv`, or `__pycache__` in audit zips.

When returning an audit zip to the user, provide a clickable absolute path link.

## Output Expectations

When making changes, report:

- what changed,
- why it changed,
- what assumptions were made,
- what was validated,
- what could break,
- what remains,
- the audit zip path if an audit was produced.

For Power Pages changes, also report when the site source was downloaded, from which environment/site, and confirm edits were made against that refreshed baseline.

## Garbage Collection

If a rule in this file becomes long, move it to a focused doc and link it here. If a one-off repair becomes repeatable, turn it into a script or validation check. If a failure recurs, encode the durable fix path in `docs/ops/` and `results/` so future agents do not rediscover it.
