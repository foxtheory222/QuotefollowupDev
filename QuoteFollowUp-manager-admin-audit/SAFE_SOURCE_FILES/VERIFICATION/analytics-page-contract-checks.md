# Analytics Page Contract Checks

## Inventory Confirmed In Source

The authoritative runtime inventory for `/southern-alberta/{branch}/detail?view=analytics` contains all of the following surfaces:

- freshness strip
- analytics spotlight band
- Financial Snapshot
- Operational Snapshot
- Finance Bridge
- Daily Operations Trend
- Quote Pipeline
- Orders / Execution
- Abnormal Margin Exceptions
- Late Orders
- Freight / Logistics
- Definitions / Trust Notes

## Source Lineage Verified

- Analytics spotlight band
  - source: derived analytics payload from `qfu_financesnapshot`, budget-embedded SA1300 ops-daily JSON, `qfu_quotelines`, `qfu_backorders`, `qfu_marginexceptions`, and `qfu_lateorderexceptions`
  - rule: highlights the current source watch, quote conversion, backlog pressure, margin review, and late-order risk without introducing a new data source or a separate business rule
- Financial Snapshot
  - source: `qfu_financesnapshot`, `qfu_financevariance`
  - rule: closed-month finance only
- Operational Snapshot
  - source: budget-embedded SA1300 ops-daily JSON, `qfu_quotelines`, `qfu_backorders`, current margin/late modules
  - rule: daily operations remain separate from GL060 close
- Daily Operations Trend
  - source: `qfu_opsdailycadjson` / `qfu_opsdailyusdjson` on the current `qfu_budget` row
- Quote Pipeline
  - source: `qfu_quotelines`
  - rule: prefer `Monthly` worksheet slice if present, else `Daily`
- Orders / Execution
  - source: `qfu_backorders`
  - rule: open rows only, overdue backlog by `onTimeDate < today`, freshness by latest line-item-created date
- Abnormal Margin Exceptions
  - source: `qfu_marginexceptions`
  - rule: current calendar month by `qfu_billingdate`, latest branch snapshot only
- Late Orders
  - source: `qfu_lateorderexceptions`
  - rule: latest snapshot only, current if latest snapshot <= 7 days old
- Freight / Logistics
  - source: none live yet
  - rule: explicitly awaiting feed, no fabricated freight fact table

## Route-Isolation Check

- Source gate:
  - analytics rendering is only entered when `viewKey === "analytics"`
- Source-only hardening:
  - the new spotlight band is rendered inside `renderAnalyticsDetail(...)` and does not alter the route-selection logic shared by hub, region, branch-home, or non-analytics detail views
- Smoke evidence:
  - analytics route loaded successfully
  - hub, region, branch home, one detail route, and ops/admin also loaded successfully in the same browser pass
- Result:
  - analytics-path verification did not reveal a global route crash regression

## Live Smoke Result

- Route tested:
  - `/southern-alberta/4171-calgary/detail?view=analytics`
- Result:
  - loaded hydrated content
  - `hasLoadingShell = false`
  - `hasJsCrashText = false`
  - `cardCount = 12`
- Screenshot:
  - `VERIFICATION/browser/analytics-4171.png`
- Production-state note:
  - live browser verification was rerun after runtime deployment and cache refresh
  - the live route now serves the analytics spotlight band and the latest-snapshot abnormal-margin filter
  - `VERIFICATION/live-browser-verification.md` confirms `Abnormal Margin Exceptions = 4` with no duplicate `7034265912` / `7034274546` billing-doc rows

## Analytics Fixture Path

- `scripts/branch_analytics_semantic.py` completed end-to-end fixture generation against the current example workbook set.
- Output artifact:
  - `VERIFICATION/analytics-semantic-fixture.json`
- Effect:
  - analytics source lineage is proven from the runtime, the live route inventory, and the current example workbook fixtures
