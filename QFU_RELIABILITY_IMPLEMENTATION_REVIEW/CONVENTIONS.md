# QFU Reliability Conventions

This file is authoritative for the current Southern Alberta reliability pass.

## 1. `qfu_isactive` inversion

- Environment meaning is inverted:
  - `false = active`
  - `true = inactive`
- JavaScript:
  - `parseBoolean(val) === false` means active
  - runtime helpers must treat `qfu_isactive eq false` as active
- OData:
  - active row filter is `qfu_isactive eq false`
- PowerShell / CRM Yes-No mapping:
  - `"No"` = active
  - `"Yes"` = inactive
- Power Automate:
  - active current-month budget rows must write `qfu_isactive = false`
  - month rollover deactivation must write `qfu_isactive = true`

## 2. Authoritative KPI lineage

- current-month budget pace comes from `qfu_budget`
- monthly targets come from `qfu_budgetarchive`
- closed-month finance and YTD come from:
  - `qfu_financesnapshot`
  - `qfu_financevariance`

## 3. Authoritative date usage

- quote-created logic uses `createdon`
- abnormal margins use `qfu_billingdate`
- late orders remain snapshot-based / 7-day

## 4. Date-only parsing rule

- Never parse business dates with raw `new Date(isoWithZ)` semantics.
- Treat business dates as date-only values and normalize through explicit date-only helpers first.

## 5. Archive identity rule

- Canonical future `qfu_budgetarchive` identity is logical first:
  - branch
  - month
  - fiscal year
- Lookup/resolution must use branch + month + fiscal year before falling back to `qfu_sourceid`.
- Canonical future archive `qfu_sourceid` scheme:
  - `BRANCH|budgetarchive|FYxx|MM`
- Historical rows may still use:
  - `budgettarget|YYYY-MM`
- Historical rows are not rewritten in this pass.

## 6. Runtime/file authority rule

- Current regional runtime is authoritative:
  - `site/web-templates/qfu-regional-runtime/QFU-Regional-Runtime.webtemplate.source.html`
- Current live Power Pages source under `site/` is authoritative for this repo.
- Archival or exported copies are evidence only.
- Do not edit archival `live-refresh` or audit-bundle copies when implementing behavior changes.

## 7. Delivery-not-PGI caution

- Power Pages is proven as:
  - reader
  - comment patcher
- Exact base-row writer for `qfu_deliverynotpgi` remains unproven in exported/source-controlled assets.
- Do not invent a new writer in routine edits.

## 8. Field allow-list rule

- If runtime reads a Dataverse field, the matching Power Pages Web API allow-list must be updated and linted.
- Runtime field additions are not complete until allow-list lint passes.

## 9. Required pre-merge checks

- polarity lint
- runtime allow-list lint
- route smoke checks
- budget duplicate warning check
