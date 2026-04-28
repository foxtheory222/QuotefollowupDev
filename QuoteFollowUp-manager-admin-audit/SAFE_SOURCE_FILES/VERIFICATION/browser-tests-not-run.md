# Browser Tests Not Run

This file is superseded by live browser verification that was completed on `2026-04-09`.

Use these artifacts instead:

- `VERIFICATION/route-smoke-checks.md`
- `VERIFICATION/live-browser-verification.md`
- `VERIFICATION/live-browser-verification.json`

The current pass included authenticated live checks for:

1. `/`
2. `/southern-alberta`
3. `/southern-alberta/4171-calgary`
4. `/southern-alberta/4171-calgary/detail?view=analytics`
5. `/ops-admin`

Current follow-up manual focus if a future regression appears:

1. Confirm `seeded-operational-import` warnings still match Dataverse ingestion-batch reality.
2. Confirm `/southern-alberta` still renders `Configured Branches = 3` with no duplicate `4171` card.
3. Confirm `/southern-alberta/4171-calgary` still shows `OVERDUE ORDERS` in the CSSR panel and `Abnormal Margin Exceptions (MTD) = 4`.
4. Confirm `/southern-alberta/4171-calgary/detail?view=analytics` still shows one row each for billing docs `7034265912` and `7034274546`.
5. Confirm `/ops-admin` still renders one row each for `4171`, `4172`, and `4173`.
