# Status Rule Review

## Rules

- If qfu_nextfollowupon is before today and the status is system-owned, set status to Overdue.
- If qfu_nextfollowupon is today and the status is system-owned, set status to Due Today.
- If qfu_nextfollowupon is future or blank and the status is blank/system-owned, set status to Open.
- Preserve manual or terminal statuses: Roadblock, Escalated, Completed, Closed Won, Closed Lost, Cancelled, Waiting on Customer, Waiting on Vendor.

## Counts

| State | Before | After |
| --- | ---: | ---: |
| Open | 5 | 4 |
| Due Today | 0 | 4 |
| Overdue | 0 | 24 |

The existing five Phase 3.2B work items were reclassified where appropriate. Sticky notes, owners, manual statuses, and action history were preserved.
