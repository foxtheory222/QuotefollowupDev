# Archived Quote Detail Repair - 2026-04-20

## Scope

Repair the Southern Alberta archived quote detail experience for `4171` so archived quote links no longer land on a broken/blank detail shell, and tighten the `Status and paging` layout in the quotes ledger.

Target route:

- `<URL>

## Refreshed baseline

- Power Pages source refreshed on `2026-04-20` from `<URL>
- Website id: `<GUID>`
- Command: `pac pages download --path powerpages-live --webSiteId <GUID> --overwrite -mv Enhanced`

## Root cause

Two runtime defects were present in the refreshed `QFU Regional Runtime` template:

1. `quote-detail` only trusted the preloaded workspace quote arrays and had no direct `qfu_quote` fetch fallback for archived quotes that were not present in the branch workspace cache.
2. `quote-detail` filtered `qfu_quoteline` by `qfu_branchcode` only, while the broader runtime already treats branch identity as `branch slug OR branch code`.

That made archived/header-only quotes brittle. The detail route could preserve the quote number but still render an incomplete shell if the quote header was not cached or if matching lines were keyed by slug.

The quotes ledger spacing issue was separate:

- `.qfu-phase0-quotes-toolbar__group--status` was inheriting stretched grid-row behavior from the outer card layout, which pushed the status/sort/page-size controls downward and left excess empty space above them.

## Changes

Edited refreshed local baseline:

- `powerpages-live/operations-hub---operationhub/web-templates/qfu-regional-runtime/QFU-Regional-Runtime.webtemplate.source.html`
- `tests/test_powerpages_runtime_contracts.py`

Runtime changes:

- added `branchIdentityOdataFilter(...)` helper so detail queries can use branch slug or branch code consistently
- added direct `qfu_quote` fallback fetch in `renderQuoteDetailLive(...)` when the quote header is not already cached in workspace arrays
- changed the detail `qfu_quoteline` query to use `(qfu_branchcode eq ... or qfu_branchslug eq ...)`
- changed the no-line empty state copy so archived quotes say they have no current `qfu_quoteline` rows instead of claiming the header is live
- added `align-content:start;` to `.qfu-phase0-quotes-toolbar__group--status`

## Validation

Static validation:

- `python -m unittest tests.test_powerpages_runtime_contracts`
- result: passed

Live publish:

- published with `scripts/update-live-qfu-regional-runtime-template.ps1`
- proof artifact: `results/live-qfu-regional-runtime-template-update.json`

Authenticated browser proof:

- quotes ledger search route loaded: `.../detail/?view=quotes&name=0515438274`
- archived quote link rendered with href `.../detail?view=quote-detail&quote=0515438274`
- clicking that link navigated to `.../detail/?view=quote-detail&quote=0515438274`
- archived quote detail rendered with `State: Archived` and the line empty state copy:
  - `This archived quote header has no current qfu_quoteline rows for the selected quote.`
- network proof showed the live detail query:
  - `/_api/qfu_quotelines ... $filter=qfu_quotenumber eq '0515438274' and (qfu_branchcode eq '4171' or qfu_branchslug eq '4171-calgary')`

## Follow-up: archived header-only quotes

On `2026-04-20`, a live Dataverse audit confirmed the remaining quote-detail pages with no lines are archived headers only, not active quote-line regressions:

- `4171`: `15` quotes missing lines, `0` active, `15` archived
- `4172`: `18` quotes missing lines, `0` active, `18` archived
- `4173`: `8` quotes missing lines, `0` active, `8` archived

Proof artifact:

- `results/quote-line-missing-live-summary-20260420.json`

Those rows trace back to the April 9 quote-line integrity cleanup. The current platform keeps archived quote headers in `qfu_quote`, but it does not retain archived `qfu_quoteline` history after the quote leaves the live SP830 workbook.

Portal follow-up applied against the refreshed runtime baseline:

- archived header-only quote detail now renders `Archived line history unavailable`
- the module copy explains that archived `qfu_quoteline` snapshots are not retained in the current model
- the footer source note now points to the archived `qfu_quote` header instead of misleadingly claiming a live line-row source

Durable implication:

- If the business wants archived quotes to always show historical line items, this requires a new quote-line history / snapshot model and matching ingestion/backfill path. It is not a current-state `qfu_quoteline` cleanup issue anymore.

## Durable mirror

Mirror the runtime template, runtime contract test, and this note into:

- `tmp-github-QuoteFollowUp/site/web-templates/qfu-regional-runtime/QFU-Regional-Runtime.webtemplate.source.html`
- `tmp-github-QuoteFollowUp/tests/test_powerpages_runtime_contracts.py`
- `tmp-github-QuoteFollowUp/docs/ops/quote-detail-archived-route-repair-20260420.md`

## Remaining watch items

- The Power Pages host still emits the existing Microsoft-side `Invariant failed` warning in console, but it did not block either the quotes ledger or the repaired archived quote detail render in the authenticated session.
- Stitch MCP was checked for this UI pass, but the available tool surface here edits existing Stitch screens rather than importing a live portal screenshot directly, so the production fix was applied in the Power Pages runtime template itself.
