# Quote Retention Repair - 2026-04-20

## Scope

Stop Southern Alberta SP830 quote imports from archiving quotes before the intentional cleanup phase, and restore missing quote-line visibility for quotes that had already been archived without retained `qfu_quoteline` rows.

Representative production defect:

- `https://operationhub.powerappsportals.com/southern-alberta/4171-calgary/detail/?view=quote-detail&quote=0515438274`

## Root cause

The regional SP830 import path was treating `qfu_quote` as a strict current-state snapshot:

- if a quote header disappeared from the latest SP830 workbook, the live flow deactivated the matching `qfu_quote` row immediately
- the platform did not keep archived `qfu_quoteline` history once the quote left the live workbook slice

That behavior is controlled in the generated quote flow by `Deactivate_Missing_Quotes`. In live Southern Alberta SP830 flows, this meant quote headers were archived before the business cleanup step, and archived quote detail pages could no longer show lines because the current model had already dropped them.

The old branch-level 90-day validity concept still exists in legacy artifacts, but it is not wired into the current regional SP830 import path.

## Changes

Generator and repair changes:

- `scripts/create-southern-alberta-pilot-flow-solution.ps1`
  - added quote-flow parameter `qfu_QFU_EnableQuoteCleanup`
  - default is `false`
  - gated `Deactivate_Missing_Quotes.foreach` behind that parameter so quote cleanup is off by default
- `scripts/repair-southern-alberta-live-flow-defects.ps1`
  - aligned expected live quote cleanup state with cleanup disabled
- `scripts/repair-live-quote-retention-xrm.ps1`
  - added narrow XRM workflow patch path for live SP830 quote flows
  - patches `Deactivate_Missing_Quotes.foreach` to `@json('[]')`
  - updates the action description to state cleanup is intentionally disabled
  - re-activates the workflow row after patching
- `scripts/repair-live-quote-line-integrity.ps1`
  - backfills missing `qfu_quoteline` rows from the saved SP830 example workbooks
  - reactivates inactive quote headers when recovered line history exists
  - preserves quote headers by default instead of deactivating them again
  - normalizes Dataverse create-field types for line inserts

Test coverage:

- `tests/test_pilot_flow_generator_contracts.py`
- `tests/test_verification_script_contracts.py`

## Live repair

### 1. Live quote retention flows

Live Southern Alberta quote flows were patched through Dataverse/XRM so quote cleanup is disabled:

- `4171 QuoteFollowUp-Import-Staging`
- `4172 QuoteFollowUp-Import-Staging`
- `4173 QuoteFollowUp-Import-Staging`

Validation artifact:

- `results/quote-live-retention-xrm-repair-20260420.json`

Per-flow before/after artifacts:

- `results/quote-live-retention-xrm-repair-20260420/`

### 2. Live quote-line/header backfill

Backfill command:

- `powershell -NoProfile -File scripts/repair-live-quote-line-integrity.ps1 -ExampleRoot .tmp-github-quotefollowup/example -Apply`

Validation artifact:

- `results/live-quote-line-integrity/repair-summary.json`

Representative repaired quote:

- `4171 | 0515438274`
- header reactivated in `qfu_quote`
- line rows restored:
  - `4171|SP830CA|0515438274|10`
  - `4171|SP830CA|0515438274|20`
  - `4171|SP830CA|0515438274|30`

Representative live Dataverse proof after repair:

- `qfu_quote.qfu_sourceid = 4171|SP830CA|0515438274`
- `qfu_active = Yes`
- `qfu_inactiveon = null`
- three `qfu_quoteline` rows exist for quote `0515438274`

## Validation

Static validation:

- `python -m unittest tests.test_pilot_flow_generator_contracts tests.test_verification_script_contracts -v`
- result: passed

Runtime display validation:

- `python -m unittest tests.test_powerpages_runtime_contracts -v`
- result: passed

Live branch-wide Dataverse validation after repair:

- `4171`: `MISSING_COUNT=0`, `ACTIVE_MISSING=0`, `ARCHIVED_MISSING=0`
- `4172`: `MISSING_COUNT=0`, `ACTIVE_MISSING=0`, `ARCHIVED_MISSING=0`
- `4173`: `MISSING_COUNT=0`, `ACTIVE_MISSING=0`, `ARCHIVED_MISSING=0`

Representative quote proof:

- `0515438274` now has one active header and three live line rows in Dataverse

## Follow-up: quote age vs created-date mismatch

After the retention repair, the quotes ledger showed examples such as `0515438274` with:

- `Created = Apr 8, 2026`
- age badge = `32D`

That mismatch came from two different date bases:

- `qfu_overduesince` and `qfu_sourcedate` still reflected the original workbook quote-created date (`Mar 19, 2026`)
- the Power Pages runtime had drifted to prefer Dataverse `createdon` for the visible `Created` column

Because the quotes ledger age badge is intentionally based on `qfu_overduesince`, the portal was mixing:

- business quote age for the badge
- Dataverse row insert time for the created column

Portal fix applied on `2026-04-20` against a freshly refreshed Power Pages baseline:

- `pac pages download --path powerpages-live --webSiteId 2b4aca76-9dc1-4628-af07-20f7617d4115 --overwrite -mv Enhanced`
- `QFU-Regional-Runtime.webtemplate.source.html`
  - `quoteCreatedMoment(record)` now prefers `qfu_sourcedate` before Dataverse `createdon`
  - `buildAnalyticsQuoteLine(record)` now does the same so quote performance cards stay aligned with the business quote-created date

Live proof inputs:

- `0515438274` current quote header row had:
  - `qfu_overduesince = Mar 19, 2026`
  - `qfu_sourcedate = Mar 19, 2026`
  - `createdon = Apr 8, 2026`
- live template publish artifact:
  - `results/live-qfu-regional-runtime-template-update-quote-created-date-20260420.json`

Expected result after portal refresh:

- the created column will show the source quote-created date, which aligns with the age badge
- quotes like `0515438274` will read as March-created quotes rather than appearing to be April-created quotes with a 32-day age

## Durable implications

- Quote cleanup now stays off until the business intentionally enables it.
- When cleanup is eventually introduced, it must be an explicit phase change, not an accidental side effect of the current SP830 import.
- The saved example SP830 workbooks were sufficient to repair the current live gap for `4171`, `4172`, and `4173`. If future historical gaps appear outside those saved seeds, another history source will be required for backfill.

## Durable mirror

Mirror the following into `tmp-github-QuoteFollowUp`:

- `docs/ops/quote-retention-repair-20260420.md`
- `scripts/create-southern-alberta-pilot-flow-solution.ps1`
- `scripts/repair-live-quote-line-integrity.ps1`
- `scripts/repair-southern-alberta-live-flow-defects.ps1`
- `scripts/repair-live-quote-retention-xrm.ps1`
- `tests/test_pilot_flow_generator_contracts.py`
- `tests/test_verification_script_contracts.py`
