# Revenue Follow-Up Phase 2 Admin Panel MVP Build

Date: 2026-04-24

## Phase Boundary

Current phase: Phase 2 - live Dataverse tables and Power Apps Admin Panel MVP.

Functional after this phase:

- The dedicated unmanaged solution is present as `qfu_revenuefollowupworkbench`.
- The Phase 2 Dataverse table foundation is created or scaffolded for `qfu_staff`, `qfu_staffalias`, `qfu_branchmembership`, `qfu_policy`, `qfu_workitem`, `qfu_workitemaction`, `qfu_alertlog`, and `qfu_assignmentexception`.
- The solution export/unpack path is documented so metadata can be source-controlled.
- The Admin Panel MVP navigation, forms, and views are documented for model-driven Power Apps build-out.

Not functional yet:

- No resolver flow generates work items from imported quotes.
- No alerts, digests, or escalation emails are sent.
- No TSR/CSSR My Work custom page, Manager Panel, GM Review page, or security model is active.
- If the model-driven app shell/forms/views were not created by the automated pass, they are manual build steps and must not be described as live-functional.

What comes next:

- Complete or validate the model-driven app shell in Power Apps.
- Create the documented views/forms for each Phase 2 table.
- Add command behavior only after the basic forms/views are confirmed usable.
- Build disabled resolver-flow scaffolding in the next phase after admin metadata is reviewed.

Still left:

- Alternate key enforcement.
- Duplicate active policy enforcement.
- Branch/role security.
- Flow-based alias resolver and quote work item generator.
- App UX validation with the actual Dataverse forms and table permissions.

Questions that must not be guessed:

- CSSR alert mode.
- GM CC mode.
- Manager CC mode.
- Backorder work item grain.
- Customer pickup source.
- Alias verification ownership before security.
- Exact custom-page scope for My Work versus model-driven views.

## Confirmed Defaults

| Area | Confirmed Phase 2 value |
| --- | --- |
| Solution | `qfu_revenuefollowupworkbench` |
| Threshold operator | `GreaterThanOrEqual` |
| High-value quote threshold | `3000` |
| Low-value quote behavior | Reporting only |
| Required attempts | `3` |
| First follow-up basis | `ImportDate` |
| First follow-up business days | `1` |
| Meaning | Next business day after import for high-value quote work items |

Business-day timezone and branch holiday rules are later flow concerns. Do not invent branch holiday logic in Phase 2.

## Live Build Notes

Power Platform CLI authentication was available for the regional operations environment on 2026-04-24.

The automated live build created or verified:

- global choices for roles, work types, source systems, alias types, policy modes, statuses, action types, alert types/statuses, and exception types/statuses
- the eight Phase 2 tables
- the Phase 2 scalar columns
- lookup relationships to `systemuser`, `qfu_branch`, `qfu_quote`, `qfu_quoteline`, `qfu_backorder`, `qfu_freightworkitem`, `qfu_deliverynotpgi`, and the new workbench tables

The automated pass did not create the model-driven app shell, forms, views, command bar customizations, or security roles. Those remain manual Power Apps steps or a later automated solution-authoring pass.

## Manual Power Apps Admin MVP Build Steps

1. Open the `qfu_revenuefollowupworkbench` unmanaged solution.
2. Create a model-driven app named `Revenue Follow-Up Workbench`.
3. Add one area named `Admin Panel MVP`.
4. Add these navigation items:
   - Staff
   - Branch Memberships
   - Staff Alias Mapping
   - Branch Policies
   - Assignment Exceptions
   - Work Items
   - Work Item Actions
   - Alert Logs
5. Add main forms for each table using the fields documented in `docs/revenue-follow-up-admin-panel-mvp.md`.
6. Put `qfu_workitem.qfu_stickynote`, `qfu_lastfollowedupon`, `qfu_completedattempts`, `qfu_requiredattempts`, and `qfu_assignmentstatus` near the top of the Work Item form.
7. Put `qfu_actionon`, `qfu_countsasattempt`, `qfu_attemptnumber`, `qfu_nextfollowupon`, and `qfu_notes` on the Work Item Action form.
8. Create the documented views for each table.
9. Keep all command behavior as documented placeholders unless explicitly building Phase 3/4 command customizations.
10. Publish, export, and unpack the solution again after app/forms/views are created.

## Export Path

Use unmanaged export for source preservation:

```powershell
pac solution export --name qfu_revenuefollowupworkbench --path .\solution\exports\qfu_revenuefollowupworkbench-phase2-unmanaged.zip --managed false --overwrite
pac solution unpack --zipfile .\solution\exports\qfu_revenuefollowupworkbench-phase2-unmanaged.zip --folder .\solution\qfu_revenuefollowupworkbench --packagetype Unmanaged
```

Do not commit exported metadata that contains secrets, production data, or environment-specific credentials.
