# Test / Smoke Baseline

Scope: current baseline from existing repo scripts, docs, and verification artifacts only. Commands were not re-run for this task so the write set could stay limited to this file.

## Baseline Matrix

| Command / artifact | Purpose | Current state | Evidence | Phase relevance |
| --- | --- | --- | --- | --- |
| `python -m unittest tests.test_freight_parser -v` | Parser unit test for freight ingestion logic | `FAIL` baseline | `docs/qfu/CODEX_TEST_REPORT.md` records missing `xlrd` | Regression guard for non-quote surfaces in Phase F |
| `python -m unittest tests.test_sa1300_budget_selfpopulate -v` | Budget self-population unit test | `FAIL` baseline | `docs/qfu/CODEX_TEST_REPORT.md` records missing example workbooks for 4171/4172/4173 | Budget/no-regression guard for Phases A-F |
| `powershell -ExecutionPolicy Bypass -File scripts\\lint-runtime-vs-webapi-allowlists.ps1` | Runtime `$select` vs Web API allow-list lint | `PASS` | `VERIFICATION/allowlist-lint-results.md` shows `Tables missing required fields: 0` | Required pre-claim check; protects portal reads in Phases A-F |
| `powershell -ExecutionPolicy Bypass -File RAW\\scripts\\polarity-lint.ps1` | `qfu_isactive` polarity guard | `PASS` | `docs/qfu/CODEX_TEST_REPORT.md` | Required pre-claim check; protects active/inactive logic in Phases A-F |
| `powershell -ExecutionPolicy Bypass -File scripts\\smoke-portal-routes.ps1 -BaseUrl https://quoteoperations.powerappsportals.com -Session qfu-dev` | Current dev portal route smoke | Harness `PASS`, browser result auth-blocked | `output/phase0/portal-route-smoke-dev.md` shows all checked routes reaching Microsoft sign-in, not route crash/404 | Phase 0 / C / F smoke coverage exists, but current dev proof is incomplete |
| `node scripts\\smoke-portal-routes.cjs ...` | Playwright route smoke with screenshots and JSON summary | Available; no separate current recorded run inspected beyond the PowerShell wrapper output | `scripts/smoke-portal-routes.cjs` | Useful for current dev authenticated smoke in Phases C-F |
| `node scripts\\verify-freight-portal.cjs ...` | Authenticated freight worklist interaction smoke | Available; no current recorded result inspected | `scripts/verify-freight-portal.cjs` | Regression coverage for freight/ready-to-ship adjacent surfaces in Phase F |
| `VERIFICATION/route-smoke-checks.md` | Historical live browser smoke on production routes | Historical `PASS` | Routes `/`, `/southern-alberta`, `/southern-alberta/4171-calgary`, `/4172`, `/4173`, analytics, overdue backorders, `/ops-admin` passed on 2026-04-09 | Useful no-regression reference, but not a substitute for current dev smoke |
| `VERIFICATION/live-browser-verification.md` | Historical authenticated live browser verification | Historical `PASS` with non-fatal warnings | Verified real portal rendering and data presence on 2026-04-09 | Good baseline for portal behavior; stale for current dev implementation work |
| `VERIFICATION/runtime-diagnostics-checks.md` | Source-level runtime hardening verification | `PASS` at source level | Confirms `safeGetAll`, diagnostics banner paths, scoped budget archives, duplicate budget diagnostics, freshness logic, delivery-not-PGI stale logic in the authoritative runtime | Relevant to Phase 0 / F hardening, not quote follow-up feature validation |
| `VERIFICATION/flow-budget-checks.md` | Source-level budget flow hardening verification | `PASS` at source/generator level | Confirms concurrency `runs = 1`, active polarity, deterministic `qfu_sourceid`, archive duplicate prevention in generator | Relevant to no-regression budget protections during quote work |
| `scripts\\check-local-qfu-task-health.ps1` | Scheduled task health check | Available; no current recorded result inspected | `scripts/check-local-qfu-task-health.ps1` | Operational baseline aid; not enough alone for phased quote validation |
| `scripts\\check-southern-alberta-runtime-readiness.ps1` | Runtime readiness check | Available; no current recorded result inspected | script present under `scripts/` | Useful before portal smoke in Phases C-F |
| `scripts\\check-southern-alberta-flow-health.ps1` | Flow health snapshot | Available; no current recorded result inspected | script present under `scripts/` | Relevant to Phase D and Phase F |
| `scripts\\run-live-qfu-health-check.ps1` | Aggregated live health check | Available; no current recorded result inspected | script present under `scripts/` | Useful final regression wrapper if kept read-only |

## Current Read

- The repo has working lint coverage for allow-lists and polarity.
- The repo has route smoke harnesses and a richer Playwright freight verifier.
- Current dev portal smoke is not proving page behavior yet because the last recorded run is auth-blocked at Microsoft sign-in.
- Historical production browser smoke exists and passed, but it is reference evidence, not current-dev proof.
- Existing Python unit coverage is thin and currently broken by local dependency / fixture gaps, not by a known business-rule failure.

## Missing Coverage Relevant To The Phased Implementation

### Phase 0

- No fresh authenticated dev-browser smoke proving current routes after login.
- No current console-error baseline recorded for the dev portal session.

### Phase A

- No current schema validation harness for quote-follow-up additions, roster/staff model additions, or branch-config additions.
- No metadata diff/validation test recorded for new table/field additions beyond generic solution inspection.

### Phase B

- No automated business-rule tests recorded for:
  - business-day cadence calculation
  - attempt-count eligibility rules
  - queue-reason generation
  - compliance-state transitions
  - manual close / reopen transitions

### Phase C

- No current browser/action smoke for:
  - Follow-Up Queue mutations
  - `Mine` vs `All`
  - role-badge resolution
  - quote activity timeline drill-through
  - Admin / Manager header link visibility

### Phase D

- No current integration test coverage for:
  - escalation email dispatch
  - branch mailbox resolution
  - manager/GM recipient expansion
  - dev recipient override to `smcfarlane@applied.com`
  - activity-log side effects after escalation

### Phase E

- No model-driven app smoke coverage for Admin or Manager panels.
- No current evidence in the inspected baseline that AppModule artifacts already exist and are testable from source.

### Phase F

- No current authenticated end-to-end no-regression run covering:
  - Dashboard
  - Follow-Up Queue
  - Quotes
  - Overdue Backorders
  - Ready to Ship Not PGI'd
  - Team Progress
  - Workload
  - Analytics
- Freight / ready-to-ship interaction coverage exists as a script, but there is no current recorded pass for the dev environment.

## Recommended Baseline Gate Before Feature Work

1. Re-establish an authenticated dev Playwright session for `https://quoteoperations.powerappsportals.com`.
2. Re-run route smoke against the dev portal and save fresh route evidence.
3. Restore Python test prerequisites:
   - install `xlrd`
   - restore or point tests at the expected SA1300 example workbooks
4. Add quote-follow-up business-rule tests before Phase B logic changes.
5. Add browser smoke for Follow-Up Queue, Quotes, and role-link visibility before Phase C-E changes.
