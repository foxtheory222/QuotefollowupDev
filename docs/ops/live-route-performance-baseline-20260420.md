# Live Route Performance Baseline - 2026-04-20

## Scope
- Authenticated live Power Pages route timing for Southern Alberta branch `4171`.

## Measurement Path
- Used the persistent Chromium auth browser plus `scripts/measure-operationhub-route-performance.js`.
- Output artifacts were captured under `output/playwright/operationhub-perf-*`.

## What Changed
- Added a measurable live route timing helper for branch and detail pages.
- Tightened runtime fetches earlier in the day so detail routes skip unrelated datasets.
- Removed the `qfu_regions` Dataverse read from branch/detail routes and replaced it with route-based region fallback for those pages.

## Latest Measured Output
- Artifact: `output/playwright/operationhub-perf-2026-04-20T21-25-55-133Z/operationhub-performance.json`

## Latest Route Summary
- `branch-home`: `loadEventEndMs = 9953`, `apiCount = 13`
- `quotes-ledger`: `loadEventEndMs = 6780`, `apiCount = 4`
- `follow-up-queue`: `loadEventEndMs = 5668`, `apiCount = 2`
- `quote-detail`: `loadEventEndMs = 5616`, `apiCount = 3`
- `analytics`: `loadEventEndMs = 5569`, `apiCount = 12`

## Notes
- Branch/detail routes no longer issue `/_api/qfu_regions` requests.
- Branch/detail config queries now use short-lived session cache keys so same-session navigation does not keep reloading slow branch/region/sourcefeed config rows.
- Empty `qfu_branch` / `qfu_region` config responses are not cached, and the cache keys were versioned to avoid stale broken entries.
- The remaining heaviest route is analytics, which still pays for large operational datasets such as `qfu_deliverynotpgi`, `qfu_backorder`, `qfu_ingestionbatch`, `qfu_marginexception`, and `qfu_lateorderexception`.
- Power Pages route timing is noisy run-to-run, so request-level evidence matters more than one raw page-load number.

## Validation
- `python -m unittest tests.test_powerpages_runtime_contracts -v`
- Live publish artifacts:
  - `results/live-qfu-regional-runtime-template-update-detail-fetch-optimization-20260420.json`
  - `results/live-qfu-regional-runtime-template-update-region-scope-perf-20260420.json`
  - `results/live-qfu-regional-runtime-template-update-skip-region-fetch-branch-detail-20260420.json`
  - `results/live-qfu-regional-runtime-template-update-config-cache-perf-20260420.json`
  - `results/live-qfu-regional-runtime-template-update-config-cache-fix-20260420.json`

## Baseline
- Power Pages site source was refreshed on 2026-04-20 from `https://regionaloperationshub.crm.dynamics.com`, site `2b4aca76-9dc1-4628-af07-20f7617d4115`, using `pac pages download --path powerpages-live --webSiteId 2b4aca76-9dc1-4628-af07-20f7617d4115 --overwrite -mv Enhanced` before editing.
