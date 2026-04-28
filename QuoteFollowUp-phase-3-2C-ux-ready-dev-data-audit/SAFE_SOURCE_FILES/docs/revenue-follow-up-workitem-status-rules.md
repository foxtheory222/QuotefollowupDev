# Revenue Follow-Up Work Item Status Rules

These rules were added to the Phase 3 resolver for MVP UX readiness. They make the Admin Panel and future My Work surface show useful `Open`, `Due Today`, and `Overdue` states without waiting for a later scheduled status refresh flow.

## System-Owned Statuses

The resolver may recalculate these statuses:

- Open
- Due Today
- Overdue

## Manual or Terminal Statuses

The resolver preserves these statuses and does not overwrite them:

- Roadblock
- Escalated
- Completed
- Closed Won
- Closed Lost
- Cancelled
- Waiting on Customer
- Waiting on Vendor

## Date Rules

The resolver uses the current environment date.

| Condition | Status |
| --- | --- |
| `qfu_nextfollowupon` is before today | Overdue |
| `qfu_nextfollowupon` is today | Due Today |
| `qfu_nextfollowupon` is in the future | Open |
| `qfu_nextfollowupon` is blank and status is blank | Open |

For existing work items, only system-owned statuses are recalculated. Manual and terminal statuses are preserved.

## Preservation Rules

The resolver does not overwrite:

- `qfu_stickynote`
- `qfu_stickynoteupdatedon`
- `qfu_stickynoteupdatedby`
- `qfu_lastfollowedupon`
- `qfu_lastactionon`
- `qfu_workitemaction` history
- non-empty owner fields
- manual or terminal statuses

## Phase 3.2C Result

After Phase 3.2C validation:

| Status | Count |
| --- | ---: |
| Open | 4 |
| Due Today | 4 |
| Overdue | 24 |

The five Phase 3.2B work items were reclassified by the same system-owned status rules without changing sticky notes, owners, or action history.
