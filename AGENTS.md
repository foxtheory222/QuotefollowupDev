Read `CONVENTIONS.md` and `AUTHORITATIVE_FILES_USED.md` before editing.

- Power Pages working source for this pass is the refreshed 2026-04-09 download under `powerpages-live/operations-hub---operationhub`.
- Mirror durable changes into `tmp-github-quotefollowupv2/quoteFollowUpV2`.
- Only edit authoritative current runtime and current scripts. Do not edit `results/**`, `Archive/**`, old audit bundles, or exported evidence files as if they are live source.
- `qfu_isactive` is inverted: raw `false = active`, raw `true = inactive`. Current portal formatted `Yes` corresponds to raw `false`.
- Current-month budget actuals come from `qfu_budget`; targets come from `qfu_budgetarchive`.
- Abnormal margins use `qfu_billingdate`. Late orders are latest-snapshot / 7-day. Quote-created logic uses `createdon`.
- Do not invent a new `qfu_deliverynotpgi` writer.
- Required checks before claiming fixed: allow-list lint, polarity lint, duplicate budget audit, month-boundary checks, route smoke checks.

## Active Dev Environment

- Unless explicitly told otherwise, treat this repo as targeting the dev environment first.
- Default Dataverse org for dev work: `https://orga632edd5.crm3.dynamics.com/`
- Default dev portal for browser/runtime checks: `https://quoteoperations.powerappsportals.com/`
- Do not assume production URLs, production orgs, or production sourcefeeds unless the task explicitly says production.

## Dev Browser Session

- Reuse Playwright session `qfu-dev` for dev portal work against `https://quoteoperations.powerappsportals.com/`.
- Keep that session open across tasks whenever possible instead of creating a new browser.
- If authentication is required, prefer re-authenticating the existing `qfu-dev` session rather than opening another session.

## Task Completion Alert

- Use `scripts/play-task-complete-alert.ps1` at the end of longer tasks when an audible completion alert is useful.
- Default usage:
  - `powershell -ExecutionPolicy Bypass -File scripts\play-task-complete-alert.ps1`
- Voice usage:
  - `powershell -ExecutionPolicy Bypass -File scripts\play-task-complete-alert.ps1 -Voice -Message "Codex task complete"`

