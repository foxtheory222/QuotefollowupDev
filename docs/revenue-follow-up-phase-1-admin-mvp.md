# Revenue Follow-Up Workbench - Phase 1 Admin MVP

Date: 2026-04-24

## Phase Boundary

Current phase: Phase 1.2 - follow-up date, sticky notes, and Google Stitch UI prompt standard before live Dataverse table creation.

Functional after this phase:

- Source-controlled Phase 1 schema, resolver, work item, flow, and Admin Panel MVP plan.
- Local PAC solution scaffold for the future model-driven Power App solution.
- Confirmed quote-line source fields for SP830CA TSR/CSSR numeric aliases and display names.
- Hardened policy mode fields, threshold operator, work item generation mode, first follow-up fields, attempt-counting field, source-system field, and quote-line exception lookup.
- Added follow-up timestamp logging, last followed-up rollup, persistent sticky notes, and Google Stitch UI prompt standards before live table creation.

Not functional yet:

- No live Dataverse tables are created by this documentation/scaffold pass.
- No model-driven app is imported into Dataverse yet.
- No resolver flow creates work items yet.
- No real alerts or digests are sent.
- No security model is enforced.
- No custom pages or Google Stitch prototypes are created yet.

What comes next:

- Create the Dataverse tables and choices inside the dedicated `qfu_revenuefollowupworkbench` solution.
- Create the first model-driven app shell and Admin Panel area.
- Run resolver dry runs before enabling writes or alerts.

Still left:

- Live table creation, forms, views, app sitemap, flows, security, dry-run validation, alert enablement, and Power Platform solution export/unpack.

Questions that must not be guessed:

- First follow-up due-date rule.
- GM, manager, and CSSR alert mode values.
- Backorder work item grain.
- Customer pickup source.
- Alert/CC behavior details beyond the current policy placeholders.
- Exact Power Apps custom page scope for My Work versus model-driven views/forms first.

## Purpose

This is the working baseline for the Revenue Follow-Up Workbench. The goal is to add a workflow and ownership layer on top of the existing imported operational data without replacing the import tables that already provide traceability.

The actual admin, manager, GM, and staff workflow application is a Power Apps model-driven app backed by Dataverse. The old Power Pages ops-admin route should stop expanding for this workflow. Power Pages can continue to serve monitoring/reporting experiences, but administrative configuration and daily follow-up workflow belong in the model-driven Power App solution.

The data model direction is:

```text
Imported data tables = source of truth / traceability
qfu_workitem = workflow and follow-up control layer
qfu_staffalias = source identity mapping layer
qfu_staff + qfu_branchmembership = human ownership layer
qfu_policy = configurable business rules
qfu_alertlog = alert history and dedupe
qfu_assignmentexception = cleanup queue
```

## Phase 1 Scope

Phase 1 begins the Dataverse and model-driven app foundation for:

- staff identity mapping from SP830CA and future sources
- branch membership and role assignment
- configurable branch policies
- quote work item generation rules
- assignment exception handling
- alert history and dedupe design
- Revenue Follow-Up Workbench model-driven app shell
- Admin Panel MVP views and forms inside the model-driven app

The implementation track is:

```text
Power Apps model-driven app
    -> Dataverse tables
    -> Power Automate flows
    -> Email / Teams / dashboards / alerts
```

This phase should create or scaffold solution artifacts only after the live environment, publisher, and existing source fields are confirmed.

## Out Of Scope

- No changes to the existing Power Pages ops-admin route.
- No replacement of `qfu_quote`, `qfu_quoteline`, or `qfu_backorder`.
- No live Power Automate alert sending in Phase 1.
- No security rollout beyond including the fields needed for later staff-to-user and branch membership security.
- No polished TSR/CSSR "My Work" custom page yet.
- No custom React/web app for this workflow.
- No Power Pages admin rebuild for this workflow.
- `FLOW_AUDIT_MATRIX.cleaned.csv` remains an audit-cleanup artifact only and is not Revenue Follow-Up implementation progress.

## Locked Decisions

| Area | Decision |
| --- | --- |
| TSR identity from SP830CA | `AM Number` is the primary business identity alias |
| TSR display from SP830CA | `AM Name` is display/fallback only |
| CSSR identity from SP830CA | `CSSR` number is the primary business identity alias |
| CSSR display from SP830CA | `CSSR Name` is display/fallback only |
| Security identity | Do not route directly from SP830CA number to `systemuser` |
| Staff mapping | Resolve through `qfu_staffalias -> qfu_staff -> optional systemuser` |
| Dataverse `systemuser.employeeid` | Not currently usable for automatic routing |
| Quote threshold | Based on total quote value, not line value |
| High-value quote rule | Quotes at or above `$3,000` require `3` attempts |
| Threshold comparison | MVP uses `qfu_policy.qfu_thresholdoperator = GreaterThanOrEqual` |
| Low-value quote behavior | Reporting-only in MVP; no TSR work item unless later confirmed |
| Attempt counting | Must use `qfu_workitemaction.qfu_countsasattempt`; Call, Email, and Customer Advised count by default |
| Followed up on | `qfu_workitemaction.qfu_actionon` stores the actual follow-up/action date-time |
| Last followed up on | `qfu_workitem.qfu_lastfollowedupon` is calculated from attempt-bearing actions only |
| Sticky notes | Persistent note lives on `qfu_workitem.qfu_stickynote`, not imported source tables |
| Missing TSR | Manager assignment exception queue |
| Blank / zero aliases | Assignment exceptions, not staff records |
| GM CC | Configured through `qfu_policy`, not hardcoded |
| Work item role | Workflow/control layer only |
| Source record role | `qfu_quote`, `qfu_quoteline`, and `qfu_backorder` remain traceable operational sources |
| Admin/workflow app | Power Apps model-driven app backed by Dataverse |
| UI design prompts | Use Google Stitch for design/prototype prompts only |
| Power Pages role | Monitoring/reporting remains allowed; do not expand old ops-admin for this workflow |

## Deliverables

Create and maintain these documents as the build baseline:

- `docs/revenue-follow-up-dataverse-schema.md`
- `docs/revenue-follow-up-identity-resolution.md`
- `docs/revenue-follow-up-workitem-layer.md`
- `docs/revenue-follow-up-admin-panel-mvp.md`
- `docs/revenue-follow-up-flow-plan-phase-1.md`
- `docs/revenue-follow-up-open-decisions.md`
- `docs/revenue-follow-up-admin-policy.md`
- `docs/revenue-follow-up-google-stitch-ui-brief.md`
- `docs/revenue-follow-up-design-system.md`

Create or scaffold these solution assets in Phase 1 after metadata confirmation:

- Dataverse tables and choices for the Admin MVP.
- Model-driven app named `Revenue Follow-Up Workbench`.
- App areas:
  - My Work
  - Manager Panel
  - Admin Panel
  - GM Review
- Admin Panel tables/views:
  - Staff
  - Branch Memberships
  - Staff Alias Mapping
  - Branch Policies
  - Assignment Exceptions
  - Work Items
  - Work Item Actions
  - Alert Logs
  - Import Health, later or placeholder only

## Phase 1 Success Gates

- The schema describes each proposed table, required fields, relationships, alternate keys, and example rows.
- The resolver rules reject blank, `0`, `00000000`, `N/A`, `NA`, `NULL`, and `NONE` aliases.
- Excel-decimal number aliases such as `<staff-number>.0` normalize to `<staff-number>`.
- Number aliases beat name aliases in every automatic resolution path.
- Policy schema includes `qfu_thresholdoperator`, `qfu_workitemgenerationmode`, `qfu_firstfollowupbasis`, `qfu_firstfollowupbusinessdays`, `qfu_gmccmode`, `qfu_managerccmode`, and `qfu_cssralertmode`.
- Work item schema includes `qfu_sourcesystem`, `qfu_lastfollowedupon`, `qfu_stickynote`, `qfu_stickynoteupdatedon`, and `qfu_stickynoteupdatedby`.
- Work item action schema includes `qfu_countsasattempt`, and action date/time logging through `qfu_actionon`.
- Assignment exception schema includes optional `qfu_sourcequoteline`.
- Missing TSR ownership creates a manager-facing assignment exception.
- CSSR mapping failures create assignment exceptions but do not block a TSR-owned quote work item.
- `qfu_workitem` references source records instead of duplicating source-of-truth data.
- Alert flows remain disabled/stubbed until policy, ownership, and dedupe are reviewed.
- The model-driven app is the target admin/workflow surface.
- Admin Panel configuration can be changed in Dataverse without editing flows.
- Google Stitch prompts exist for future UI design alignment, while production implementation remains Power Apps backed by Dataverse.
- Any created solution artifacts are exportable/unpackable for Git tracking.

## Admin MVP Build Order

1. Create reviewed Dataverse tables and choices.
2. Create model-driven app shell named `Revenue Follow-Up Workbench`.
3. Add app areas:
   - My Work
   - Manager Panel
   - Admin Panel
   - GM Review
4. Add Admin Panel MVP tables/views:
   - Staff
   - Branch Memberships
   - Staff Alias Mapping
   - Branch Policies
   - Assignment Exceptions
   - Work Items
   - Work Item Actions
   - Alert Logs
   - Import Health, later or placeholder only
5. Add Power Automate child-flow scaffolding for policy lookup, alias normalization/resolution, quote total calculation, work item upsert, and exception writing.
6. Validate with a non-alerting dry run against recent SP830CA rows.
7. Review unmapped staff and policy output before enabling any digest or targeted alert behavior.

## Implementation Prompt V2

Use this scoped prompt for the next build pass after the documents are approved:

```text
Implement the Phase 1 Admin MVP Dataverse solution artifacts for the Revenue Follow-Up Workbench.

Do not modify the old Power Pages ops-admin route.
Create the actual admin/workflow surface as a Power Apps model-driven app backed by Dataverse, not Power Pages, React, or flow settings.
Do not replace qfu_quote, qfu_quoteline, or qfu_backorder.
Use qfu_workitem only as a workflow/control layer that references imported source records.
Use qfu_staffalias -> qfu_staff -> optional systemuser for ownership resolution.
Use AM Number and CSSR number as business identity aliases, not security identities.
Create assignment exceptions for blank, zero, invalid, missing, or ambiguous aliases.
Use branch policy for thresholds, attempts, CC, digest, targeted alert, and escalation behavior.
Use qfu_thresholdoperator and qfu_workitemgenerationmode from policy instead of hardcoded threshold comparisons.
Use qfu_firstfollowupbasis and qfu_firstfollowupbusinessdays for initial due-date calculation.
Use qfu_gmccmode, qfu_managerccmode, and qfu_cssralertmode instead of enabled-only alert booleans.
Use qfu_workitemaction.qfu_countsasattempt to calculate completed attempts.
Use qfu_workitemaction.qfu_actionon as the actual action/follow-up date-time.
Use qfu_workitem.qfu_lastfollowedupon as the rollup of latest attempt-bearing action date-time.
Use qfu_workitem.qfu_stickynote for persistent visible notes and do not overwrite it on source import refresh.
Do not send live alerts until qfu_alertlog dedupe and policy output are validated.
Do not hardcode staff, email addresses, GMs, managers, branch IDs, AM numbers, CSSR numbers, or thresholds in flows.
```

## Assumptions

- `qfu_branch` is the existing branch configuration table. The portal reads it through `/_api/qfu_branchs`.
- Imported quote/backorder rows already carry enough branch and source identity to link work items back to their sources.
- Live metadata and sample rows confirm `qfu_quoteline.qfu_tsr` and `qfu_quoteline.qfu_cssr` carry the SP830CA numeric aliases used for TSR and CSSR resolution.
- Live metadata and sample rows confirm `qfu_quoteline.qfu_tsrname` and `qfu_quoteline.qfu_cssrname` carry the display names used for review and fallback mapping.
- `qfu_quote` has `qfu_tsr`, `qfu_cssr`, and `qfu_cssrname`, but no separate `qfu_tsrname` field was found in live metadata. Quote work item generation should use grouped `qfu_quoteline` rows for identity and total calculation.
- Model-driven app assets should live in a Power Platform solution and be exported/unpacked back into the durable repo after creation.

## What Could Break

- If future import changes stop populating `qfu_quoteline.qfu_tsr` or `qfu_quoteline.qfu_cssr`, the resolver must fail into assignment exceptions rather than route by name.
- If branch policy defaults are missing, work item generation must fail into `qfu_assignmentexception` instead of silently using hardcoded behavior.
- If a nullable branch lookup is used directly in alternate keys for global rows, duplicate global/default rows can slip through. Use an explicit scope key where global rows are allowed.
- If app/table artifacts are created outside a solution, ALM becomes brittle. Create inside the confirmed solution or create a dedicated Revenue Follow-Up solution before building.
