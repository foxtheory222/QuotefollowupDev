# Static Checks

- Extracted the JavaScript from `site/web-templates/qfu-regional-runtime/QFU-Regional-Runtime.webtemplate.source.html` and ran `node --check`.
  - Result: passed
- Parsed these PowerShell scripts with `[scriptblock]::Create(...)`:
  - `RAW/scripts/create-southern-alberta-pilot-flow-solution.ps1`
  - `RAW/scripts/normalize-live-sa1300-current-budgets.ps1`
  - `RAW/scripts/audit-live-current-budget-duplicates.ps1`
  - `RAW/scripts/lint-runtime-vs-webapi-allowlists.ps1`
  - Result: passed
- Searched authoritative current source for `preferActiveRows`.
  - Result: no remaining hits
- Searched authoritative current source for `qfu_isactive` usage.
  - Result: current runtime and current scripts now use the inverted `false = active` convention
- Executed the runtime-vs-Web-API allow-list lint.
  - Result: no missing runtime-read fields; extra allow-list fields remain and were intentionally not trimmed in this pass
- Executed the dry-run current-budget duplicate audit against exported row evidence.
  - Result: duplicate logical current-month groups exist for 4171 / 4172 / 4173, but each group currently has one active candidate and one inactive candidate
