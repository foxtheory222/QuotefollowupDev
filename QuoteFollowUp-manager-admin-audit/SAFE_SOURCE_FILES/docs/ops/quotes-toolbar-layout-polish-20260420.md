# Quotes Toolbar Layout Polish - 2026-04-20

## Scope
- Branch quote archive toolbar layout in the Power Pages regional runtime.

## Problem
- The `Status`, `Sort`, and `Page Size` dropdowns were packed into a narrow side card, which compressed the controls and made the quote archive toolbar look broken on desktop.

## Change
- Moved the browse controls into a dedicated full-width control rail above the filter grid.
- Kept search filters and value/date filters in separate cards below the rail so each control block has stable width.
- Added runtime contract assertions for the control rail markup and dense desktop CSS.

## Design Direction
- Used a Google Stitch screen concept (`QFU Quotes Archive Toolbar Polish 2026-04-20`) to validate the layout direction before applying the production Power Pages change.
- The implemented production pattern keeps the archive route browse-first, but gives the browsing controls their own wider visual lane.

## Files
- `powerpages-live/operations-hub---operationhub/web-templates/qfu-regional-runtime/QFU-Regional-Runtime.webtemplate.source.html`
- `tests/test_powerpages_runtime_contracts.py`

## Validation
- `python -m unittest tests.test_powerpages_runtime_contracts -v`
- Publish artifact: `results/live-qfu-regional-runtime-template-update-quotes-toolbar-layout-20260420.json`

## Baseline
- Power Pages site source was refreshed on 2026-04-20 from `<URL> site `<GUID>`, using `pac pages download --path powerpages-live --webSiteId <GUID> --overwrite -mv Enhanced` before editing.
