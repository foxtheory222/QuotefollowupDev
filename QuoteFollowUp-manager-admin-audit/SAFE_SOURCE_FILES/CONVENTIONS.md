# QFU Contract Conventions

This file is the contract baseline for the 2026-04-09 reliability pass.

## 1. `qfu_isactive` inversion

- Raw Dataverse meaning is inverted:
  - `false = active`
  - `true = inactive`
- Runtime and flow filters must treat active budget rows as `qfu_isactive eq false`.
- Current portal probe evidence also shows a formatted-label trap:
  - raw `false` rendered as formatted `Yes`
  - raw `true` rendered as formatted `No`
- When raw and formatted values disagree, raw wins.

## 2. Authoritative KPI lineage

- Quote-created logic uses `createdon`.
- Abnormal margins are month-running by `qfu_billingdate`, but branch and analytics views must render the latest branch snapshot only within that billing month.
- Late orders remain latest-snapshot based and current if the latest snapshot is within 7 days.
- CSSR overdue backlog leaderboard cards count distinct overdue sales orders; overdue detail routes remain line-grain.
- Current-month budget actual / pace comes from `qfu_budget`, with branch-summary fallback only when the summary row itself is from the same current calendar month.
- Monthly targets come from `qfu_budgetarchive`.
- Closed-month finance and YTD come from `qfu_financesnapshot` and `qfu_financevariance`.
- Delivery-not-PGI is read from `qfu_deliverynotpgi`; the exact base-row writer is still unproven.

## 2a. Operational current-state classification

- `qfu_quote`
  - role: current-state
  - canonical key: `branch|SP830CA|quotenumber`
  - lifecycle fields: `qfu_active`, `qfu_inactiveon`, `qfu_lastseenon`
- `qfu_backorder`
  - role: current-state
  - canonical key: `branch|ZBO|salesdoc|line`
  - lifecycle fields: `qfu_active`, `qfu_inactiveon`, `qfu_lastseenon`
- `qfu_marginexception`
  - role: snapshot/history
  - canonical key: `branch|SA1300-MARGIN|snapshotdate|billingdoc|reviewtype`
- `qfu_deliverynotpgi`
  - role: snapshot with active/inactive lifecycle
  - canonical key: `branch|ZBO|delivery|line`
  - duplicate inactive history across snapshots is allowed; more than one active row for a canonical key is a defect.
- Migration rule:
  - until `results/live-operational-lifecycle-backfill.json` shows zero candidate updates, writer lookups and runtime filters must treat `qfu_active = null` on `qfu_quote` / `qfu_backorder` as legacy-active rather than invisible.

## 3. Date rules

- Business dates must be parsed as date-only values first.
- Do not rely on implicit `Date(...)` timezone conversion for business calendar logic.
- Region and branch current-month budget selection must use the same month/fiscal-year basis.
- Month-open logic may display `$0` only on day 1 when the target exists and live SA1300 actuals have not landed yet.

## 4. Archive identity rule

- Canonical `qfu_budgetarchive` identity is:
  - branch
  - fiscal year
  - month
- Canonical current-source ID format is:
  - `BRANCH|budgetarchive|FYxx|MM`
- Historical `budgettarget|YYYY-MM` rows may still exist and must be tolerated during lookup.
- Duplicate archive creation is a bug, not a normal state.

## 5. Runtime authority rule

- Before editing Power Pages, refresh the live site source with `pac pages download`.
- For this pass, the refreshed working baseline is:
  - `powerpages-live/operations-hub---operationhub/...`
- Download metadata:
  - date: 2026-04-09
  - environment: `Applied Canada Operations Hub`
  - org URL: `<URL>
  - site URL: `<URL>
  - website id: `<GUID>`
- Durable mirror for long-lived preservation is:
  - `tmp-github-quotefollowupv2/quoteFollowUpV2/site/...`
- Fresh download first, durable mirror second.

## 6. Delivery-not-PGI caution

- The portal is proven to read `qfu_deliverynotpgi` and save comments back to those rows.
- Do not invent a new `qfu_deliverynotpgi` ingestion/writer path in this pass.
- Staleness must be based on base-row freshness, not comment update time.

## 7. Field allow-list maintenance rule

- Any runtime Web API field read must exist in the matching Power Pages Web API allow-list.
- Runtime field additions are incomplete until `lint-runtime-vs-webapi-allowlists.ps1` passes.

## 8. Runtime diagnostics rule

- Critical dataset failures must not collapse silently into a normal empty state.
- Duplicate config rows, duplicate budget candidates, stale datasets, pagination guard trips, and `$top` truncation must emit diagnostics.
- A degraded UI is acceptable; silently wrong numbers are not.

## 9. Verification gates before deploy

- `VERIFICATION/static-checks.md`
- `VERIFICATION/runtime-contract-checks.md`
- `VERIFICATION/analytics-page-contract-checks.md`
- `VERIFICATION/allowlist-lint-results.md`
- `VERIFICATION/polarity-lint-results.md`
- `VERIFICATION/budget-duplicate-audit.md`
- `VERIFICATION/month-boundary-tests.md`
- `VERIFICATION/route-smoke-checks.md`
