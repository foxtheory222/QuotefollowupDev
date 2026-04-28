# Handoff 2026-04-10 Home Sync

This branch is a home-working snapshot of the current Quote Follow Up regional workspace, including the live freight rollout and the earlier reliability hardening artifacts.

## Remote

- Repo: `<URL>
- Branch: `codex/home-sync-20260410-live-state`
- Local clone: `C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\tmp-github-QuoteFollowUp`

## What Is Included

- Current Power Pages site source under `site/`
- Current scripts and repair tooling under `scripts/`
- Reliability/contract docs at repo root
- Verification artifacts under `VERIFICATION/`
- Recent run artifacts under `results/`
- Raw/source-oriented helpers under `RAW/`

## Latest Live-State Notes

### Freight

- Freight inbox ingestion is live for `4171`, `4172`, and `4173`.
- Live flows now include:
  - `4171-Freight-Inbox-Ingress`
  - `4172-Freight-Inbox-Ingress`
  - `4173-Freight-Inbox-Ingress`
  - `QFU-Freight-Archive-Workitems`
- The freight worklist redesign is live on:
  - `/southern-alberta/4171-calgary/detail/?view=freight-worklist`
  - `/southern-alberta/4172-lethbridge/detail/?view=freight-worklist`
  - `/southern-alberta/4173-medicine-hat/detail/?view=freight-worklist`
- Freight runtime warnings were hardened so `processed` and `duplicate` ingestion batches are treated as healthy states, not degraded states.

### Reliability Work Already In Repo

- Contract and conventions docs for KPI/runtime hardening
- Quote-line integrity repair tooling and verification artifacts
- Budget/backorder diagnostics and repair helpers
- Browser smoke and contract verification outputs

## Most Important Files

### Runtime / Site

- `site/web-templates/qfu-regional-runtime/QFU-Regional-Runtime.webtemplate.source.html`
- `site/web-files/qfu-phase0.css`

### Freight

- `scripts/create-southern-alberta-freight-flow-solution.ps1`
- `scripts/deploy-freight-worklist.ps1`
- `scripts/process-freight-inbox-queue.ps1`
- `scripts/archive-freight-workitems.ps1`
- `scripts/verify-freight-portal.cjs`
- `FREIGHT_IMPLEMENTATION_SUMMARY.md`
- `FREIGHT_FIELD_MAPPING.md`
- `TEST_RESULTS_FREIGHT.md`

### Reliability / Ops

- `CONVENTIONS.md`
- `AGENTS.md`
- `CARD_CONTRACTS.md`
- `CHANGE_MAP.md`
- `KNOWN_LIMITATIONS.md`
- `AUTHORITATIVE_FILES_USED.md`
- `scripts/invoke-qfu-reliability-diagnostics.ps1`
- `scripts/run-live-qfu-health-check.ps1`

## Verification To Review First

- `TEST_RESULTS_FREIGHT.md`
- `VERIFICATION/browser/freight-branch-smoke.json`
- `VERIFICATION/browser/freight-verify-20260410B/`
- `VERIFICATION/runtime-contract-checks.md`
- `VERIFICATION/route-smoke-checks.md`

## Where To Continue Next

1. Re-audit live quote headers vs `qfu_quoteline` after the next real SP830CA mailbox run.
2. Finish the remaining live non-freight fixes:
   - quote-line availability
   - current-month budget correctness
   - overdue backorder freshness/idempotency
   - duplicate operational row prevention
3. Keep Power Pages edits aligned to a fresh `pac pages download` before any new site change.
4. Mirror important fixes back into the durable repo/workspace if you branch off elsewhere.

## Power Pages Baseline Note

The current site files in this snapshot were edited against a refreshed local download of:

- Environment: `<URL>
- Site: `operations-hub---operationhub`

## Notes

- This repository is a synced working snapshot for continued development from home.
- `gh` CLI was not available in the current office environment, so branch publishing used plain `git`.
