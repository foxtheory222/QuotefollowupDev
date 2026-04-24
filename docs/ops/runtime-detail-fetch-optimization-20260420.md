# Runtime Detail Fetch Optimization - 2026-04-20

## Scope
- Power Pages regional runtime fetch bundle performance for branch detail routes.

## Problem
- `loadRuntime()` was still issuing large operational reads on detail routes even when the current view did not consume those datasets.
- Examples:
  - Quote-focused detail routes still fetched `qfu_backorder`, `qfu_budget`, `qfu_budgetarchive`, and `qfu_branchdailysummary`.
  - Backorder-focused detail routes still fetched `qfu_quote`.
  - `quote-detail` still paid for the full quote ledger fetch even though the route already has a direct quote-header fallback lookup.
  - Branch and region config reads were not scoped to the active route.

## Change
- Added view-aware fetch gating in `loadRuntime()` so detail routes only request the operational datasets they actually need.
- Scoped `qfu_branch`, `qfu_region`, and `qfu_sourcefeed` reads to the active branch or region when the route context is known.
- Kept branch home, region, hub, analytics, ops, and authenticated freight behavior unchanged.

## Expected Impact
- Fewer `/_api` calls and smaller total payloads on detail routes.
- Biggest gains should show up on:
  - `quote-detail`
  - `quotes`
  - `overdue-quotes`
  - `overdue-backorders`
  - `follow-up-queue`

## Files
- `powerpages-live/operations-hub---operationhub/web-templates/qfu-regional-runtime/QFU-Regional-Runtime.webtemplate.source.html`
- `tests/test_powerpages_runtime_contracts.py`

## Validation
- `python -m unittest tests.test_powerpages_runtime_contracts -v`

## Baseline
- Power Pages site source was refreshed on 2026-04-20 from `https://regionaloperationshub.crm.dynamics.com`, site `2b4aca76-9dc1-4628-af07-20f7617d4115`, using `pac pages download --path powerpages-live --webSiteId 2b4aca76-9dc1-4628-af07-20f7617d4115 --overwrite -mv Enhanced` before editing.
