# Overdue Orders Integration Review

Source tables checked:
- qfu_backorder.
- qfu_workitem.
- qfu_branch.

Used qfu_backorder: yes.
Backorder/order work items created: yes, controlled branch 4171 sample.
Counts:
- Active Backorder work items: 5

Source fields:
- Branch linkage.
- Source key/source document style values where available.
- Value/date fields from qfu_backorder where safely available.

Limitations:
- Owner assignment is deferred because no verified backorder staff-number routing source exists.
- No broad all-branch backorder apply was run.
- qfu_backorder was not replaced or structurally modified.
