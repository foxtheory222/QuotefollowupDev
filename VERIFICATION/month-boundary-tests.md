# Month-Boundary Tests

| Case | What Was Checked | Outcome |
| --- | --- | --- |
| `MB-001 month-open-zero` | Branch budget progress may show `$0` only on day 1 when the target exists and current-month live actuals have not landed yet. | Passed by source review. |
| `MB-002 branch-current-period-selection` | Branch budget selection uses current month and active fiscal year for `qfu_budget` and `qfu_budgetarchive`. | Passed by source review. |
| `MB-003 region-branch-date-basis-alignment` | Region rollup uses the same current-month budget basis as each branch budget block. | Passed by source review. |
| `MB-004 archive-preferred-fallback` | Target prefers `qfu_budgetarchive`; if missing, branch logic falls back to summary or budget row instead of hard-failing. | Passed by source review. |
| `MB-005 duplicate-current-budget-groups` | March FY26 current-budget duplicates exist for 4171 / 4172 / 4173 with one active and one inactive candidate each. | Detection passed; live data cleanliness failed. See `VERIFICATION/budget-duplicate-audit.md`. |
| `MB-006 duplicate-archive-groups` | March FY26 archive duplicates exist for 4171 / 4172 / 4173. | Detection passed; live data cleanliness failed. See `VERIFICATION/budget-duplicate-audit.md`. |
| `MB-007 april-canonical-archive-identity` | April FY26 archive rows use canonical `branch|budgetarchive|FY26|04` identity for 4171 / 4172 / 4173. | Passed from audit evidence. |
| `MB-008 previous-month-summary-lag` | If the latest SA1300 row is from a prior month, the branch budget state stays `awaiting`/`stale` instead of pretending the current month is live. | Passed by source review. |
| `MB-009 margin-membership-billingdate` | Abnormal margin membership is current-month by `qfu_billingdate`, not by snapshot timestamp alone. | Passed by source review. |
| `MB-010 late-orders-7d` | Late orders remain latest-snapshot based and current only when the latest snapshot is within 7 days. | Passed by source review. |

## Notes

- These tests are a mix of live duplicate-audit evidence and source-proven selection logic.
- No live deployment occurred in this task, so month-boundary source fixes are not yet validated on the production portal.

