# Authoritative Files Used

## Primary working baseline

- Fresh Power Pages download captured on 2026-04-09:
  - `C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\powerpages-live\operations-hub---operationhub\web-templates\qfu-regional-runtime\QFU-Regional-Runtime.webtemplate.source.html`
  - `C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\powerpages-live\operations-hub---operationhub\web-pages\**\*.webpage.yml`
  - `C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\powerpages-live\operations-hub---operationhub\sitesetting.yml`

## Durable mirrored source

- Runtime mirror:
  - `site/web-templates/qfu-regional-runtime/QFU-Regional-Runtime.webtemplate.source.html`
- Durable scripts mirror:
  - `RAW/scripts/normalize-live-sa1300-current-budgets.ps1`
  - `RAW/scripts/repair-southern-alberta-live-dashboard-data.ps1`
  - `RAW/scripts/lint-runtime-vs-webapi-allowlists.ps1`
  - `RAW/scripts/audit-live-current-budget-duplicates.ps1`
  - `RAW/scripts/polarity-lint.ps1`
  - `RAW/scripts/standardize-sa1300-budget-flows.py`
  - `RAW/scripts/branch_analytics_semantic.py`

## Current source-of-truth scripts in the working folder

- `scripts/create-southern-alberta-pilot-flow-solution.ps1`
- `scripts/normalize-live-sa1300-current-budgets.ps1`
- `scripts/repair-southern-alberta-live-dashboard-data.ps1`
- `scripts/lint-runtime-vs-webapi-allowlists.ps1`
- `scripts/audit-live-current-budget-duplicates.ps1`
- `scripts/polarity-lint.ps1`
- `scripts/standardize-sa1300-budget-flows.py`
- `scripts/branch_analytics_semantic.py`

## Evidence files used for verification, not implementation

- `docs/ops/analytics-selfpopulate-incident-20260409.md`
- `results/portal-runtime-data-probe-20260409.json`
- `results/portal-runtime-data-summary-20260409.json`
- `results/region-4171-duplicate-probe-20260409.json`
- `results/southern-alberta-runtime-readiness-20260409-101610.json`
- `VERIFICATION/allowlist-lint-results.md`
- `VERIFICATION/polarity-lint-results.md`
- `VERIFICATION/budget-duplicate-audit.md`

## Explicitly non-authoritative / do not edit

- `results/**` as live source
- `Archive/**`
- `audit-bundle-2026-04-02/**`
- `phase0_audit_bundle/**`
- `phase1_audit_bundle/**`
- `QFU_RELIABILITY_IMPLEMENTATION_REVIEW/**`
- `.tmp*`
- old temporary Power Pages snapshots such as `tmp-post-*`, `tmp-pre-*`, and `tmp-current-site`

## Deprecated implementation targets

- `scripts/standardize-sa1300-budget-flows.py`
  - now intentionally hard-fails to stop edits against archived flow JSON
- Any earlier bundle copy of `QFU-Regional-Runtime.webtemplate.source.html`
  - evidence only, not the current live baseline

