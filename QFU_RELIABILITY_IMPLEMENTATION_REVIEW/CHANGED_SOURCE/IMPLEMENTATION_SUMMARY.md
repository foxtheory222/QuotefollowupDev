# Implementation Summary

## Implemented

### Runtime hardening

Authoritative file:

- `site/web-templates/qfu-regional-runtime/QFU-Regional-Runtime.webtemplate.source.html`

Implemented:

- added a top-of-file conventions block
- removed the dead `preferActiveRows` trap
- added loud inverted-polarity comments for `qfu_isactive`
- hardened `getAll` with visited-nextLink and max-page guards
- hardened `safeGetAll` with dataset failure diagnostics and `$top` truncation warnings
- scoped the `qfu_budgetarchives` query with `scopedFilter`
- aligned branch and region current-budget month selection to `today`
- added duplicate logical-current-budget diagnostics
- separated operational freshness from budget freshness
- added delivery-not-PGI stale-data diagnostics using base-row `createdon`
- rendered visible diagnostics banners instead of silently presenting failed datasets as normal zero states

Evidence source:

- both Claude phase-2 audit and prior audit evidence

### Shared CSS support

Authoritative file:

- `site/web-files/qfu-phase0.css`

Implemented:

- added explicit styling for runtime diagnostics banners so degraded-data signals are visibly rendered

Evidence source:

- both

### Budget normalization / duplicate tooling

Authoritative files:

- `RAW/scripts/normalize-live-sa1300-current-budgets.ps1`
- `RAW/scripts/audit-live-current-budget-duplicates.ps1`

Implemented:

- created a current dry-run budget normalization helper with explicit inverted `qfu_isactive` handling
- created a read-only duplicate audit script that reports logical current-month duplicates, the chosen row, and the rows a repair path would deactivate

Evidence source:

- prior audit evidence

### Budget flow/generator hardening

Authoritative file:

- `RAW/scripts/create-southern-alberta-pilot-flow-solution.ps1`

Implemented:

- corrected current-month budget polarity to `qfu_isactive = false` for active rows
- corrected active-row lookup to `qfu_isactive eq false`
- added SA1300 budget trigger concurrency control (`runs = 1`)
- aligned current-month budget resolution to deterministic `qfu_sourceid`
- changed the current generator’s archive sourceid scheme to canonical `budgetarchive`
- added logical archive existence lookup by branch + month + fiscal year
- added update-vs-create guard for archive writes in the current generator

Evidence source:

- both

### Phase 0 confusion hardening

Authoritative file:

- `site/web-templates/qfu-phase-0-renderer/QFU-Phase-0-Renderer.webtemplate.source.html`

Implemented:

- added a loud deprecation banner to the deprecated Phase 0 template

Evidence source:

- prior audit evidence

### Allow-list lint

Authoritative file:

- `RAW/scripts/lint-runtime-vs-webapi-allowlists.ps1`

Implemented:

- added runtime-vs-Web-API allow-list linting for the current regional runtime and current site settings

Evidence source:

- prior audit evidence

## Files changed

- `CONVENTIONS.md`
- `AGENTS.md`
- `README_IMPLEMENTATION.md`
- `IMPLEMENTATION_SUMMARY.md`
- `CHANGE_MAP.md`
- `AUTHORITATIVE_FILES_USED.md`
- `NON_IMPLEMENTED.md`
- `KNOWN_LIMITATIONS.md`
- `site/web-templates/qfu-regional-runtime/QFU-Regional-Runtime.webtemplate.source.html`
- `site/web-files/qfu-phase0.css`
- `site/web-templates/qfu-phase-0-renderer/QFU-Phase-0-Renderer.webtemplate.source.html`
- `RAW/scripts/create-southern-alberta-pilot-flow-solution.ps1`
- `RAW/scripts/normalize-live-sa1300-current-budgets.ps1`
- `RAW/scripts/audit-live-current-budget-duplicates.ps1`
- `RAW/scripts/lint-runtime-vs-webapi-allowlists.ps1`
