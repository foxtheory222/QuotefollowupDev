# Static Checks

## Passed

- Extracted the JavaScript from `powerpages-live/operations-hub---operationhub/web-templates/qfu-regional-runtime/QFU-Regional-Runtime.webtemplate.source.html` and ran `node --check`.
  - Result: passed
- Parsed these PowerShell scripts with `[scriptblock]::Create(...)`:
  - `scripts/normalize-live-sa1300-current-budgets.ps1`
  - `scripts/repair-southern-alberta-live-dashboard-data.ps1`
  - `scripts/lint-runtime-vs-webapi-allowlists.ps1`
  - `scripts/audit-live-current-budget-duplicates.ps1`
  - `scripts/polarity-lint.ps1`
  - Result: passed
- `scripts/lint-runtime-vs-webapi-allowlists.ps1`
  - Result: no missing runtime-read fields in current Web API allow-lists
- `scripts/polarity-lint.ps1`
  - Result: `suspiciousCount = 0`
- `scripts/audit-live-current-budget-duplicates.ps1`
  - Result: duplicate March FY26 groups detected for 4171 / 4172 / 4173 in both `qfu_budget` and `qfu_budgetarchive`, and canonical April FY26 archive rows detected for all three branches
- `python scripts/branch_analytics_semantic.py --example-root example --output VERIFICATION/analytics-semantic-fixture.json`
  - Result: passed
  - Output artifact: `VERIFICATION/analytics-semantic-fixture.json`
  - Hardening now tolerates the current example-set drift by auto-detecting dual-block SA1300 daily-sheet starts from the header row instead of assuming fixed offsets.

## Notes

- `scripts/branch_analytics_semantic.py` was hardened in this pass so missing freight example workbooks no longer abort generation, missing non-core GL060 detail labels are recorded instead of immediately failing, and SA1300 dual-block parsing adapts to the current per-branch workbook layout.
- `openpyxl` still emits a non-fatal warning that some example workbooks contain no default style. Generation completed successfully despite that warning.
