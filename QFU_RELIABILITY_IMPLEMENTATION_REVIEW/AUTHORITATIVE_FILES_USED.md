# Authoritative Files Used

## Authoritative current source

- Power Pages runtime:
  - `site/web-templates/qfu-regional-runtime/QFU-Regional-Runtime.webtemplate.source.html`
- Power Pages shared CSS:
  - `site/web-files/qfu-phase0.css`
- Current deprecated-but-still-present Phase 0 template:
  - `site/web-templates/qfu-phase-0-renderer/QFU-Phase-0-Renderer.webtemplate.source.html`
- Current page routing/source copies:
  - `site/web-pages/**`
- Current site settings / Web API allow-lists:
  - `site/sitesetting.yml`
- Current patchable flow generator source:
  - `RAW/scripts/create-southern-alberta-pilot-flow-solution.ps1`
- Current reliability scripts added in this pass:
  - `RAW/scripts/normalize-live-sa1300-current-budgets.ps1`
  - `RAW/scripts/audit-live-current-budget-duplicates.ps1`
  - `RAW/scripts/lint-runtime-vs-webapi-allowlists.ps1`

## Archival / evidence only

- `QFU_FINAL_AUDIT_STAGING/**`
- `QFU_FINAL_GAPS_STAGING/**`
- `QFU_FINAL_LAST_GAP_STAGING/**`
- `output/**`
- `RAW/live-refresh-20260407-074015/**`
- older exported portal copies and extracted flow JSON used only as evidence

## Ambiguity resolved

- The repo did not contain a current `RAW/powerpages-current/**` tree. The live-synced current Power Pages source under `site/**` was treated as authoritative.
- The repo did not contain a current `RAW/solution-current/**` tree. The only current patchable flow-generation source available in-repo for Southern Alberta pilot flows was `RAW/scripts/create-southern-alberta-pilot-flow-solution.ps1`, so that was treated as the authoritative generator input for this pass.
- A current `normalize-live-sa1300-current-budgets.ps1` did not exist in the repo. A new current dry-run normalization helper was created under `RAW/scripts/` and this absence is recorded in `NON_IMPLEMENTED.md`.
