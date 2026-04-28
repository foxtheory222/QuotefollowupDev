# Revenue Follow-Up Resolver Apply Safety

Date: 2026-04-27

Environment: `https://orga632edd5.crm3.dynamics.com/`

## Current Gate

Apply mode was not run in Phase 3.1. The resolver remains dry-run by default and requires:

```powershell
-Mode Apply -ConfirmApply
```

Broad apply mode should wait until staff, alias, and branch membership mappings have been reviewed.

## Work Item Status Preservation

For new work items:

- Set `qfu_status = Open`.

For existing work items:

- Only set `qfu_status` when it is blank/null.
- Do not overwrite manual or terminal statuses such as Roadblock, Escalated, Completed, Closed Won, Closed Lost, Cancelled, Waiting on Customer, or Waiting on Vendor.

The resolver may update `qfu_assignmentstatus` because it reflects current ownership resolution. A later phase may need a manual override flag if business users need to freeze assignment status.

## Owner Preservation

The resolver only fills blank owner fields:

- `qfu_primaryownerstaff`
- `qfu_supportownerstaff`
- `qfu_tsrstaff`
- `qfu_cssrstaff`

Existing non-empty owner fields are preserved unless a later explicit reassignment mode is added.

## Date And Attempt Preservation

For existing work items, apply mode preserves:

- Existing `qfu_nextfollowupon`
- `qfu_lastfollowedupon`
- `qfu_lastactionon`
- Existing `qfu_completedattempts`
- `qfu_workitemaction` history

For new work items, apply mode sets `qfu_completedattempts = 0` and calculates first `qfu_nextfollowupon` from the policy.

## Sticky Note Preservation

The resolver never writes:

- `qfu_stickynote`
- `qfu_stickynoteupdatedon`
- `qfu_stickynoteupdatedby`

Sticky notes live on `qfu_workitem` and must persist across source refreshes and resolver reruns.

## Assignment Exception Links

Apply mode now prepares assignment exceptions with:

- `qfu_sourcedocumentnumber`
- `qfu_sourceexternalkey`
- `qfu_sourcequote`
- `qfu_sourcequoteline` when a representative quote line exists
- `qfu_workitem` when an existing or newly created work item is available

If a new work item is created, the resolver captures the returned `qfu_workitemid` and links related exception plans before writing exceptions. If Dataverse ever returns a created work item without an id, the resolver throws and stops rather than creating unlinked exceptions.

## No-Alert Guarantee

Phase 3.1 does not create alert rows, call alert flows, send daily digests, or trigger real notifications. Dry-run reports must show:

```text
alertsSent = 0
```

## Recommended Apply Path

1. Complete staff and alias mapping review.
2. Rerun dry-run.
3. Confirm resolved counts improved and exceptions decreased.
4. Pick one dev branch or one small quote-group sample.
5. Run controlled apply only after reviewing the dry-run payload.
6. Validate created work item, linked exceptions, status preservation, owner preservation, sticky note preservation, and zero alerts.
