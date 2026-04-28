# Route Smoke Checks

## Browser Pass

- Browser automation was available and used.
- Screenshots were captured under `VERIFICATION/browser/`.
- A second live verification pass was run on `2026-04-09` after the runtime cache refresh to confirm the served portal matched the deployed runtime source.

| Route | Result | Notes | Screenshot |
| --- | --- | --- | --- |
| `/` | Passed | No loading shell, no page-crash text. | `VERIFICATION/browser/hub.png` |
| `/southern-alberta` | Passed | No loading shell, no page-crash text, and the live region route now renders `Configured Branches = 3` / `Live Branches = 3` without a duplicate `4171` branch card. | `VERIFICATION/browser/region-southern-alberta.png` |
| `/southern-alberta/4171-calgary` | Passed | No loading shell or page-crash text. Live branch page now shows CSSR cards ranked by distinct overdue orders and the current-month abnormal margin card at 4 rows from the latest snapshot. | `VERIFICATION/browser/branch-4171-calgary.png` |
| `/southern-alberta/4172-lethbridge` | Passed | No loading shell, no page-crash text. | `VERIFICATION/browser/branch-4172-lethbridge.png` |
| `/southern-alberta/4173-medicine-hat` | Passed | No loading shell, no page-crash text. | `VERIFICATION/browser/branch-4173-medicine-hat.png` |
| `/southern-alberta/4171-calgary/detail?view=analytics` | Passed | Analytics page hydrated with 12 analytics cards. Live pass confirmed `Abnormal Margin Exceptions` renders 4 rows and no duplicate `7034265912` / `7034274546` billing-doc rows. | `VERIFICATION/browser/analytics-4171.png` |
| `/southern-alberta/4171-calgary/detail?view=overdue-backorders` | Passed | Detail route loaded without crash text. | `VERIFICATION/browser/detail-overdue-backorders-4171.png` |
| `/ops-admin` | Passed | Manager panel loaded. Live pass confirmed `Configured Branches = 3` and one row each for `4171`, `4172`, and `4173`. | `VERIFICATION/browser/ops-admin.png` |

## Console Summary

- Repeated Power Pages host warnings were present:
  - unsatisfied `react-dom` singleton version warning
  - repeated `Invariant failed` warning from host bundle
  - repeated icon re-registration warning
- No tested route rendered obvious crash text in-page.

## Production-State Reminder

- These smoke checks were run against the live portal after the runtime deployment and cache refresh.
- They prove route reachability and confirm the served runtime is now applying the duplicate-config collapse, distinct-order CSSR ranking, and latest-snapshot abnormal-margin filtering.
- They do not change the underlying ingestion reality: seeded-operational-import warnings remain live because the latest operational batches are still controlled workbook seeds.
