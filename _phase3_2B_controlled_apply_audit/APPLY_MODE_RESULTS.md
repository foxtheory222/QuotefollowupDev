# Apply Mode Results

## Initial Retry Note

Initial first apply attempt was stopped by Dataverse lookup navigation metadata, then a clean-scope empty-exception guard. No broad apply was run. One scoped work item was created before the guard stopped; the corrected first successful apply updated that row and created the remaining four scoped work items.

## First Completed Apply

| Metric | Count |
| --- | ---: |
| Work items created | 4 |
| Work items updated | 1 |
| Assignment exceptions created | 0 |
| Assignment exceptions updated | 0 |
| Alerts sent | 0 |

## Second Apply

| Metric | Count |
| --- | ---: |
| Work items created | 0 |
| Work items updated | 5 |
| Assignment exceptions created | 0 |
| Assignment exceptions updated | 0 |
| Alerts sent | 0 |

Idempotency passed: pass
