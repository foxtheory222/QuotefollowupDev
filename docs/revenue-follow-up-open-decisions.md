# Revenue Follow-Up Open Decisions

Date: 2026-04-24

## Phase Boundary

Current phase: Phase 2 - live Dataverse tables and Power Apps Admin Panel MVP.

Functional after this phase:

- Locked decisions and remaining human decisions are separated.
- Known blockers are documented without inventing answers.
- The flow-audit CSV boundary is recorded.
- Phase 2 no longer treats the first follow-up due date rule as open.
- Live Dataverse table creation can proceed from the hardened schema.

Not functional yet:

- This file does not implement tables, flows, apps, alerts, custom pages, or security.
- Open decisions still require human confirmation before related implementation paths are enabled.
- Resolver flow, alert flow, TSR/CSSR My Work, Manager Panel, GM Review, and security are not active yet.
- Google Stitch remains design guidance only.

What comes next:

- Use this file as the gate before resolver flows, alerts, custom pages, and security are enabled.
- Move decisions out of this file only after the user confirms them or the repo/live metadata proves them.

Still left:

- Final decisions on alert/CC modes, backorder grain, pickup source, alias verification ownership, duplicate policy enforcement, and exact Power Apps custom page scope.

Questions that must not be guessed:

- Every item listed under blocking decisions.
- Any branch-specific ownership, GM, manager, email, threshold, or source-rule detail not already confirmed by the user or live metadata.

## Decisions Already Locked

| Area | Decision |
| --- | --- |
| Roles | TSR, CSSR, Manager, GM, Admin. No SSR role. |
| Dedicated solution | Use `qfu_revenuefollowupworkbench`. |
| TSR source identity | SP830CA AM Number |
| TSR display/fallback | SP830CA AM Name |
| CSSR source identity | SP830CA CSSR number |
| CSSR display/fallback | SP830CA CSSR Name |
| Security identity | Not the SP830CA number directly |
| Identity mapping | `qfu_staffalias -> qfu_staff -> optional systemuser` |
| Name matching | Not safe for automatic routing |
| Alias cleanup | Normalize Excel decimal aliases such as `<staff-number>.0` |
| Invalid aliases | Blank, `0`, `00000000`, `N/A`, `NA`, `NULL`, and `NONE` become assignment exceptions |
| Quote threshold basis | Total quote value |
| High-value quote threshold operator | `GreaterThanOrEqual` |
| High-value quote threshold amount | `$3,000` |
| Required attempts for high-value quotes | `3` |
| MVP low-value quote behavior | Reporting only; no TSR follow-up work item unless later confirmed. |
| First follow-up due date | High-value quote work items use `qfu_firstfollowupbasis = ImportDate` and `qfu_firstfollowupbusinessdays = 1`, meaning next business day after import. |
| Attempt-bearing MVP defaults | Call, Email, and Customer Advised count as attempts by default. |
| Non-attempt MVP defaults | Note, Roadblock, Escalated, Due Date Updated, Won, Lost, Cancelled, Assignment/Reassignment, and Sticky Note Updated do not count as attempts by default. |
| Actual follow-up date/time | `qfu_workitemaction.qfu_actionon` is the action date/time and is labeled Followed Up On for attempt actions. |
| Last followed-up rollup | `qfu_workitem.qfu_lastfollowedupon` is calculated from attempt-bearing actions only. |
| Sticky notes | Persistent current note lives on `qfu_workitem.qfu_stickynote`, not imported source tables. |
| Missing TSR | Manager assignment exception queue, not silent CSSR ownership |
| GM CC | Branch/admin policy, not hardcoded |
| Source tables | `qfu_quote`, `qfu_quoteline`, and `qfu_backorder` remain traceable operational source |
| Work item table | Workflow/control layer only |
| Admin/workflow app | Model-driven Power App backed by Dataverse |
| UI design prompting | Google Stitch is required for UI design/prototype prompts, but production remains Power Apps backed by Dataverse. |
| Old Power Pages ops-admin | Do not expand it for this workflow |

## Artifact Boundaries

- `FLOW_AUDIT_MATRIX.cleaned.csv` is an audit-cleanup artifact only.
- It is not implementation progress for the Revenue Follow-Up Workbench.
- Do not use it as evidence that Phase 1 tables, resolver flows, or model-driven app work have been implemented.

## Blocking Decisions Before Resolver, Alert, And Custom Page Work

Only unresolved decisions are listed here. Do not infer an answer from the order of the options.

| Decision | Options / Notes |
| --- | --- |
| CSSR alert mode | Confirm `VisibilityOnly`, `DailyDigestOnly`, `TargetedAlerts`, `CCOnly`, or `Disabled` for `qfu_policy.qfu_cssralertmode`. |
| GM CC mode | Confirm `Disabled`, `NewHighValue`, `DueToday`, `Overdue`, `EscalatedOrRoadblock`, or `DailyDigestOnly` for `qfu_policy.qfu_gmccmode`. |
| Manager CC mode | Confirm `Disabled`, `NewHighValue`, `DueToday`, `Overdue`, `EscalatedOrRoadblock`, or `DailyDigestOnly` for `qfu_policy.qfu_managerccmode`. |
| Backorder work item grain | Confirm whether backorder work items are sales-document, sales-document-line, customer, material, or backlog-group based. |
| Customer pickup source | Confirm the report/source that will drive pickup aging before building pickup flows. |
| Alias verification ownership before security | Confirm who can verify aliases before branch/role security is implemented. |
| Duplicate active policy enforcement | Confirm whether enforcement is through Dataverse validation/plugin, Power Automate guard, admin duplicate view, or a combination. |
| Exact Power Apps custom page scope | Confirm whether My Work and Quote Detail start as custom pages or model-driven views/forms first. |

## Previously Resolved Source-Field Check

Status:

```text
Resolved for quote-line driven Phase 1.2 schema hardening.
```

Live metadata/sample findings:

- `qfu_quoteline.qfu_tsr` stores the AM Number / TSR numeric alias.
- `qfu_quoteline.qfu_tsrname` stores the AM Name / TSR display name.
- `qfu_quoteline.qfu_cssr` stores the CSSR numeric alias.
- `qfu_quoteline.qfu_cssrname` stores the CSSR display name.
- `qfu_quote` has `qfu_tsr`, `qfu_cssr`, and `qfu_cssrname`, but no separate `qfu_tsrname` field was found in live metadata.

Decision for Phase 1.2 documentation:

- Use grouped `qfu_quoteline` rows for quote total and staff identity resolution.
- Link to `qfu_quote` where a current-state quote row exists.
- Allow assignment exceptions to reference a representative `qfu_sourcequoteline`.

## Non-Blocking Later Decisions

- Exact custom page visual layout for the TSR/CSSR My Work screen.
- Manager dashboard KPI design.
- GM Review screen layout.
- Alert template wording.
- Bulk staff import tooling.
- Branch onboarding wizard.
- Replay/reprocess controls.
- Security role/team implementation details.
