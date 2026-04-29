# Queue Filter Helper Fields

The Workbench queue-role filter now uses text helper fields instead of direct choice and lookup predicates.

Fields added to `qfu_workitem`:
- `qfu_currentqueueroletext`
- `qfu_currentqueueownerstaffkey`
- `qfu_currentqueueownername`

The true routing fields remain:
- `qfu_currentqueueownerstaff`
- `qfu_currentqueuerole`

Reason:
Direct Power Fx filtering against the new queue choice and lookup fields caused the gallery to load zero rows. The helper fields provide stable text values for Power Apps filtering and display without replacing the authoritative queue owner fields.

Backfill result:
- Active work items processed: 38
- TSR helper rows: 30
- CSSR helper rows: 2
- Unassigned helper rows: 6

Expected filter behavior:
- `All` shows all work items in the selected branch/staff context.
- `TSR` filters to `qfu_currentqueueroletext = TSR`.
- `CSSR` filters to `qfu_currentqueueroletext = CSSR`.
- `Unassigned` filters to blank or `Unassigned` role text.
