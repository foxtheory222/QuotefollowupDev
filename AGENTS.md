Read `CONVENTIONS.md` and `AUTHORITATIVE_FILES_USED.md` before editing.

- Power Pages working source for this pass is the refreshed 2026-04-09 download under `powerpages-live/operations-hub---operationhub`.
- Mirror durable changes into `tmp-github-quotefollowupv2/quoteFollowUpV2`.
- Only edit authoritative current runtime and current scripts. Do not edit `results/**`, `Archive/**`, old audit bundles, or exported evidence files as if they are live source.
- `qfu_isactive` is inverted: raw `false = active`, raw `true = inactive`. Current portal formatted `Yes` corresponds to raw `false`.
- Current-month budget actuals come from `qfu_budget`; targets come from `qfu_budgetarchive`.
- Abnormal margins use `qfu_billingdate`. Late orders are latest-snapshot / 7-day. Quote-created logic uses `createdon`.
- Do not invent a new `qfu_deliverynotpgi` writer.
- Required checks before claiming fixed: allow-list lint, polarity lint, duplicate budget audit, month-boundary checks, route smoke checks.

