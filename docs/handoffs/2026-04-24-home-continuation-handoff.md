# Home Continuation Handoff - 2026-04-24

## Purpose

This handoff captures the current Quote Follow Up workspace state so the work can continue from another machine.

Repository used for durable source:

```text
C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\tmp-github-QuoteFollowUp
```

Remote:

```text
https://github.com/foxtheory222/QuoteFollowUp.git
```

## Branch

Planned handoff branch:

```text
codex/home-handoff-20260424-phase2-workbench
```

This branch is intended to preserve the current files without committing directly to `main`.

## High-Level State

Two work streams are present in the working tree:

1. Freight duplicate/current-state repair and regional runtime fixes.
2. Revenue Follow-Up Workbench Phase 1/2 planning, Dataverse schema, and partial live Dataverse foundation.

No commit was made before this handoff request. This handoff branch should be treated as a continuation snapshot, not a polished release branch.

## Freight / Regional Runtime Work

Current tracked modifications include:

- `FREIGHT_FIELD_MAPPING.md`
- `FREIGHT_IMPLEMENTATION_SUMMARY.md`
- `scripts/process-freight-inbox-queue.ps1`
- `src/freight_parser_host/qfu_freight_parser/core.py`
- `src/freight_parser_host/qfu_freight_parser/processor.py`
- freight parser tests
- regional runtime template and CSS under both `powerpages-live/...` and `site/...`

Related result artifacts are under `results/` and include duplicate repair dry runs, applied repair results, postchecks, runtime allowlist/runtime upload artifacts, and freight row-grain notes.

Important context:

- The regional/branch freight UI issue was duplicate freight rows showing repeatedly.
- The durable fix direction was to repair current-state freight source ids and make the runtime group/display freight rows more cleanly.
- Validate from Dataverse and authenticated Power Pages, not anonymous page requests.
- For Power Pages work, the canonical local source is `powerpages-live/operations-hub---operationhub` only after a fresh `pac pages download -mv Enhanced`.

## Revenue Follow-Up Workbench Phase 2

Phase 2 request:

```text
Live Dataverse tables and Power Apps Admin Panel MVP.
```

Live Dataverse outcome:

- Power Platform CLI auth was available.
- Dedicated solution `qfu_revenuefollowupworkbench` was created or found live.
- Global choices were created/verified.
- These tables were created/verified live:
  - `qfu_staff`
  - `qfu_staffalias`
  - `qfu_branchmembership`
  - `qfu_policy`
  - `qfu_workitem`
  - `qfu_workitemaction`
  - `qfu_alertlog`
  - `qfu_assignmentexception`
- Scalar columns and lookup relationships were created/verified.
- Solution export/unpack succeeded.

Not live-functional yet:

- The model-driven app shell was not created by automation.
- Admin forms and views were not created by automation.
- Command bar actions were not created.
- Resolver flows were not built or enabled.
- Alerts were not sent.
- My Work, Manager Panel, GM Review, and security are not implemented.

Phase 2 is therefore a partial live build:

```text
Dataverse foundation = live
Power Apps Admin Panel UX = scaffold/manual-build only
```

## Confirmed Business Decisions

- No SSR role.
- Roles are TSR, CSSR, Manager, GM, and Admin.
- Dedicated solution is `qfu_revenuefollowupworkbench`.
- AM Number is the TSR business identity alias.
- CSSR number is the CSSR business identity alias.
- Names are display/fallback only and not trusted for automatic routing.
- Routing uses `qfu_staffalias -> qfu_staff -> optional systemuser`.
- `systemuser.employeeid` is not currently usable for direct routing.
- Quote threshold is based on total quote value.
- High-value quote threshold is `$3,000`.
- Threshold operator is `GreaterThanOrEqual`.
- Quotes at or above `$3,000` require `3` attempts.
- Low-value quotes are reporting-only for MVP.
- First follow-up for high-value quote work items is next business day after import:

```text
qfu_firstfollowupbasis = ImportDate
qfu_firstfollowupbusinessdays = 1
```

- Sticky notes live on `qfu_workitem`, not imported quote rows.
- `qfu_workitemaction.qfu_actionon` is the actual follow-up/action date.
- No real alerts should be sent until later explicitly enabled.

## Key Phase 2 Files

Docs:

- `docs/revenue-follow-up-admin-panel-mvp.md`
- `docs/revenue-follow-up-dataverse-schema.md`
- `docs/revenue-follow-up-flow-plan-phase-1.md`
- `docs/revenue-follow-up-google-stitch-ui-brief.md`
- `docs/revenue-follow-up-open-decisions.md`
- `docs/revenue-follow-up-phase-2-admin-panel-mvp-build.md`
- `docs/revenue-follow-up-identity-resolution.md`
- `docs/revenue-follow-up-workitem-layer.md`

Build script:

- `scripts/create-revenue-followup-phase2-dataverse.ps1`

Live build result:

- `results/phase2-live-build-result-20260424-final2.json`

Solution export/unpack:

- `solution/exports/qfu_revenuefollowupworkbench-phase2-unmanaged.zip`
- `solution/qfu_revenuefollowupworkbench/`

Audit zip outside the repo workspace:

```text
C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\Audits\QuoteFollowUp-phase-2-admin-panel-mvp-build-audit.zip
```

## Open Decisions

Do not guess these:

- CSSR alert mode.
- GM CC mode.
- Manager CC mode.
- Backorder work item grain.
- Customer pickup source.
- Who can verify aliases before security exists.
- Duplicate active policy enforcement method.
- Exact My Work / Quote Detail custom page scope versus model-driven views/forms.

## Recommended Next Steps From Home

1. Pull the handoff branch.
2. Review `docs/revenue-follow-up-phase-2-admin-panel-mvp-build.md`.
3. Review the live build result JSON for created tables/columns/lookups.
4. Open the Power Platform solution `qfu_revenuefollowupworkbench`.
5. Create or validate the model-driven app named `Revenue Follow-Up Workbench`.
6. Add the Admin Panel MVP navigation:
   - Staff
   - Branch Memberships
   - Staff Alias Mapping
   - Branch Policies
   - Assignment Exceptions
   - Work Items
   - Work Item Actions
   - Alert Logs
7. Create the documented views/forms.
8. Export and unpack the solution again.
9. Only after the app shell is validated, move to disabled resolver-flow scaffolding.

## Validation Notes

Before treating the branch as production-ready:

- Run the Python/unit tests for freight parser and runtime contracts.
- Validate Dataverse metadata in the live solution.
- Validate the Power Pages freight runtime with authenticated browser proof if touching portal artifacts again.
- Confirm no old Power Pages ops-admin route was expanded for the Revenue Follow-Up workflow.

## Known Tooling Limitations

- `gh` was not installed in the desktop environment at handoff time.
- Branch push can still work through `git` if stored Git credentials are available.
- PR creation may need to be done from GitHub web or from a machine with GitHub CLI installed.
