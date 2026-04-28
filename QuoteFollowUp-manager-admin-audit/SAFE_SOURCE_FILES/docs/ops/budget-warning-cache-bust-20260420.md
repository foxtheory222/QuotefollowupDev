# Budget Warning Cache Bust - 2026-04-20

## Scope
- Remove stale branch-page runtime cache as a possible source of false budget warning banners after live Dataverse budget lineage was repaired.

## Why
- Live Dataverse and authenticated portal `/_api` reads showed all three branches had:
  - current April 2026 `qfu_budget` rows
  - full FY26 `qfu_budgetarchive` coverage
  - valid branch/region identity on the archive rows
- The live authenticated branch pages rendered clean in the validation browser, but the reported user-facing banners still matched the old missing-target state.
- The safest low-risk mitigation is to invalidate prior session-storage runtime bundles so older branch tabs cannot keep reusing stale warning-state results.

## Change
- Added `RUNTIME_CACHE_VERSION = "20260420c"` to the regional runtime.
- Updated the branch/detail runtime bundle cache key to use the versioned prefix:
  - `qfu-runtime-<version>:<pageType>:<branchSlug>:<regionSlug>:<viewKey>`
- Added a one-time purge for any older `qfu-runtime-*` session-storage keys that do not match the current runtime version before reading the current runtime bundle cache.

## Validation
- `python -m unittest tests.test_powerpages_runtime_contracts -v`
- Authenticated portal `/_api` checks confirmed:
  - `4171`, `4172`, `4173` each returned `12` `qfu_budgetarchive` rows for FY26
  - each branch returned an April 2026 `qfu_budget` row
- Authenticated browser checks on all three branch pages showed no `budget-target-missing` or `annual-budget-target-incomplete` warning text.

## Follow-up Repair
- The false warning still reproduced on the signed-in quotes detail route:
  - `<URL>
- Root cause: the runtime optimization intentionally skipped `qfu_budget`, `qfu_budgetarchive`, and `qfu_branchdailysummary` fetches on non-analytics detail routes, but `buildBranchWorkspaceLive(...)` still ran budget lineage and annual archive diagnostics against those intentionally empty arrays.
- Durable fix:
  - added `budgetDataLoaded` and `summaryDataLoaded` options to `buildBranchWorkspaceLive(...)`
  - gated `diagnoseCurrentBudgetCandidates(...)`, `diagnoseBudgetConsistency(...)`, and `annualTargetWarning` behind those load flags
  - kept branch home and analytics diagnostics unchanged because those routes still load the budget inputs
- Cache hardening:
  - `purgeLegacyRuntimeCacheKeys()` and `invalidateRuntime()` now remove any stale `qfu-runtime-*` bundle whose prefix does not match the current runtime version, instead of only clearing the older `qfu-runtime-v2:*` pattern
- Regression coverage now asserts that detail routes can skip budget fetches without fabricating budget warnings.

## Baseline
- Power Pages site source was refreshed on 2026-04-20 from `<URL> site `<GUID>`, using `pac pages download --path powerpages-live --webSiteId <GUID> --overwrite -mv Enhanced` before editing.
