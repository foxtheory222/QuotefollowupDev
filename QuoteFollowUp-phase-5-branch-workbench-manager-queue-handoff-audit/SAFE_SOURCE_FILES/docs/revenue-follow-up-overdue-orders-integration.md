# Overdue Orders Integration

Source checked:
- qfu_backorder exists in the dev Dataverse environment.
- Existing branch operations pages already surface overdue backorder line metrics.
- qfu_worktype includes Backorder.

Implemented:
- Created 5 controlled branch 4171 Backorder work items from qfu_backorder.
- These work items appear in the Branch Workbench list and Overdue Orders tab.
- They are kept in qfu_workitem as workflow/control records and do not replace qfu_backorder.

Counts:
- Active Backorder work items: 5

Owner assignment:
- Deferred for backorder work items because no verified backorder staff-number routing source was available.
- Current queue owner remains unassigned where no verified staff alias exists.

No alerts were sent.
