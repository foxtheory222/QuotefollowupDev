# Revenue Follow-Up Workbench Phase 3.2C UX-Ready Dev Data

Phase 3.2C created realistic dev work item states for the next My Work UX phase. This was a controlled dev-only apply against `https://orga632edd5.crm3.dynamics.com/`.

## Scope

- Clean apply scope: branch 4171, 30 high-value quote groups where both TSR and CSSR resolved.
- Exception apply scope: branch 4171, 2 high-value quote groups with controlled invalid or blank AM/CSSR aliases.
- Broad apply was not run.
- Alerts, daily digests, My Work, Manager Panel, GM Review, and security roles were not created.

## Results

| Area | Result |
| --- | ---: |
| Active work items before | 5 |
| Active work items after | 32 |
| Active assignment exceptions before | 0 |
| Active assignment exceptions after | 3 |
| Active alert logs after | 0 |
| Sent alerts | 0 |
| Duplicate work item source keys | 0 |
| Duplicate assignment exception keys | 0 |

## Clean Apply

The clean branch-limited apply created 25 new work items and updated the 5 existing Phase 3.2B work items. The second clean apply created 0 work items and updated 30 existing work items, confirming idempotent upsert behavior.

All 30 clean work items have resolved TSR and CSSR ownership and `Assigned` assignment status.

## Exception Apply

The controlled exception apply created 2 work items and 3 assignment exceptions. The selected exception cases covered:

- invalid zero TSR alias
- blank TSR alias
- blank CSSR alias

The second exception apply created 0 work items and 0 exceptions, updating existing rows only. A final validation repair rerun updated the same 2 work items and 3 exceptions after adding a representative quote-line fallback in the resolver. No duplicate records and no alerts were created.

## UX State Counts

| Work item state | Count |
| --- | ---: |
| Open | 4 |
| Due Today | 4 |
| Overdue | 24 |
| Quotes >= $3K | 32 |
| Needs TSR Assignment | 1 |
| Needs CSSR Assignment | 0 |
| Unmapped | 1 |
| Open Assignment Exceptions | 3 |

## Validation Artifacts

Validation outputs live under `results/phase3-2C-ux-ready-dev-data/`.

- `phase3-2C-validation-summary.json`
- `workitem-ux-validation.csv`
- `assignment-exception-linkage-validation.csv`
- `admin-panel-view-readiness.csv`
- `status-counts-before-after.csv`

Final validation showed 0 work item validation failures, 0 assignment exception validation failures, 0 missing Admin Panel views, and 0 sent alerts.

## Assumptions

- Current environment date was used for Due Today and Overdue behavior.
- No branch holiday logic was introduced.
- Email and Dataverse systemuser lookup gaps remain acceptable until alert and security phases.
- Google Stitch is reserved for Phase 4 design guidance only; no Stitch frontend code was generated or committed.
