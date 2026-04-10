# Runtime Contract Checks

## Contract Coverage

- `CARD_CONTRACTS.md` contains 49 contract entries:
  - Hub: 1
  - Region: 12
  - Branch: 13
  - Detail routes: 7
  - Analytics: 11
  - Ops/Admin: 5
- Every visible current route family in the authoritative runtime is represented:
  - `/`
  - `/southern-alberta`
  - `/southern-alberta/{branch}`
  - `/southern-alberta/{branch}/detail?...`
  - `/ops-admin`

## Runtime Hardening Verified In Source

- Config dedupe is present for `qfu_branchs` and `qfu_regions`.
  - Expected diagnostics:
    - `duplicate-branch-config`
    - `duplicate-region-config`
- Duplicate current-month budget candidate diagnostics are present.
  - Expected diagnostic:
    - `duplicate-budget-candidates`
- Budget archive fetch is branch/region scoped and no longer uses the global archive pool for branch routes.
- Pagination protections are present in `getAll` / `safeGetAll`.
  - Guard classes verified by source search:
    - max-page guard
    - visited-nextLink guard
    - `$top` truncation diagnostics
- Branch freshness is based on operational evidence only:
  - latest branch daily summary
  - latest quote freshness
  - latest backorder freshness
  - latest successful SP830CA/ZBO import
- Delivery-not-PGI stale detection uses base-row `createdon`, not comment-update time.

## Runtime Outcomes

- Live deployment is now visible in the served portal after cache refresh.
  - Browser verification on `2026-04-09` confirmed `/southern-alberta` renders `Configured Branches = 3` and no duplicate `4171` branch card.
  - Browser verification on `2026-04-09` confirmed `/ops-admin` renders `Configured Branches = 3` with one row each for `4171`, `4172`, and `4173`.
  - Browser verification on `2026-04-09` confirmed `/southern-alberta/4171-calgary` renders the CSSR leaderboard as distinct overdue orders with line counts only as secondary metadata.
  - Browser verification on `2026-04-09` confirmed `/southern-alberta/4171-calgary/detail?view=analytics` renders `Abnormal Margin Exceptions = 4` with no duplicate `7034265912` or `7034274546` billing-doc rows.

## Contract-Level Checks

- Silent empty-state masking is no longer treated as an acceptable verification target.
- Duplicate budget conditions are auditable with winner selection evidence in `VERIFICATION/budget-duplicate-audit.md`.
- `qfu_isactive` polarity now has both source lint and live probe evidence in `VERIFICATION/polarity-lint-results.md`.
- Web API field usage is checked against allow-lists in `VERIFICATION/allowlist-lint-results.md`.

## Remaining Gap

- The runtime is now live, but the remaining warnings are upstream data warnings rather than portal-render regressions.
  - `seeded-operational-import` remains visible because the latest operational batches for `4171`, `4172`, and `4173` are still controlled workbook seeds captured on `2026-03-20`.
