# Live Browser Verification

- Date: `2026-04-09`
- Environment: `<URL>
- Method: authenticated Playwright browser pass after runtime deployment and cache refresh

## Confirmed Live Outcomes

- `/southern-alberta`
  - `Configured Branches = 3`
  - `Live Branches = 3`
  - duplicate `4171` branch-card rendering did not reproduce
- `/southern-alberta/4171-calgary`
  - `Abnormal Margin Exceptions (MTD) = 4`
  - current-month abnormal margin panel no longer repeats billing docs `7034265912` or `7034274546`
  - CSSR leaderboard now shows `OVERDUE ORDERS`
  - CSSR counts are distinct-order based, with line counts shown only as secondary metadata
- `/southern-alberta/4171-calgary/detail?view=analytics`
  - `Abnormal Margin Exceptions` card shows `Rows = 4`
  - latest snapshot label is `Apr 8, 2026`
  - duplicate billing-doc rows for `7034265912` and `7034274546` did not reproduce
- `/ops-admin`
  - `Configured Branches = 3`
  - one row each for `4171`, `4172`, and `4173`

## Remaining Live Warnings

- `seeded-operational-import` remains visible for:
  - `4171` captured `Mar 20, 2026, 6:33 a.m.`
  - `4172` captured `Mar 20, 2026, 7:43 a.m.`
  - `4173` captured `Mar 20, 2026, 8:17 a.m.`
- These warnings are consistent with the live ingestion-batch records and indicate stale source provenance, not a portal rendering defect.

## Interpretation

- The runtime fixes for duplicate branch config collapse, distinct-order CSSR ranking, and latest-snapshot abnormal-margin filtering are now live.
- The remaining correctness risk is upstream freshness and replay provenance, not the served branch/region runtime logic.
