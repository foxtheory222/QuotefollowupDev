# QFU Codex Run Log

Updated: 2026-04-14 America/Edmonton

## Repo + Environment Baseline

- Working directory: `C:\Dev\QuoteFollowUpComplete`
- Git branch: `codex/dev-env-sync-20260413`
- Git commit: `f761ccba0d6af69c7a9ee2e9fae58fa9c9c4daa5`
- Dev portal: `https://quoteoperations.powerappsportals.com/`
- Dev Dataverse: `https://orgad610d2c.crm3.dynamics.com/`

## Commands Run

### Repo / baseline inspection

- `git status --short`
- `git branch --show-current`
- `git rev-parse HEAD`
- `Get-ChildItem -Path solution\\QuoteFollowUpSystemUnmanaged\\src\\Entities -Directory`
- `Get-ChildItem -Path solution\\QuoteFollowUpSystemUnmanaged\\src\\Workflows -File`
- `pac solution list --environment https://orgad610d2c.crm3.dynamics.com/`

### Ready-to-Ship runtime repair and verification

- targeted `Select-String` / `Get-Content` inspections against:
  - [QFU-Regional-Runtime.webtemplate.source.html](C:\Dev\QuoteFollowUpComplete\site\web-templates\qfu-regional-runtime\QFU-Regional-Runtime.webtemplate.source.html)
- `node --check` against the extracted runtime JS
- `Copy-Item` from the authoritative runtime into the dev upload package
- `pac pages upload --environment https://orgad610d2c.crm3.dynamics.com/ --path C:\Dev\QuoteFollowUpComplete\powerpages-upload-dev\quotefollowup\quotefollowup---quotefollowup --modelVersion 2 --forceUploadAll`
- `pac pages download --environment https://orgad610d2c.crm3.dynamics.com/ --websiteId 7d15dda2-9ad5-430e-ae7e-0fdab0630b2f --path C:\Dev\QuoteFollowUpComplete\output\dev-verify-current-live --modelVersion 2`
- `Get-FileHash` comparison between:
  - [site/web-templates/qfu-regional-runtime/QFU-Regional-Runtime.webtemplate.source.html](C:\Dev\QuoteFollowUpComplete\site\web-templates\qfu-regional-runtime\QFU-Regional-Runtime.webtemplate.source.html)
  - [output/dev-verify-current-live/quotefollowup---quotefollowup/web-templates/qfu-regional-runtime/QFU-Regional-Runtime.webtemplate.source.html](C:\Dev\QuoteFollowUpComplete\output\dev-verify-current-live\quotefollowup---quotefollowup\web-templates\qfu-regional-runtime\QFU-Regional-Runtime.webtemplate.source.html)
- direct Dataverse row query for `qfu_deliverynotpgi` branch `4171` via `Microsoft.Xrm.Data.Powershell`
- `powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\\audit-live-operational-current-state.ps1 -TargetEnvironmentUrl https://orgad610d2c.crm3.dynamics.com -OutputJson VERIFICATION\\operational-current-state-dev.json -OutputMarkdown VERIFICATION\\operational-current-state-dev.md`

### Phase 0 safe validations

- `python -m unittest tests.test_freight_parser -v`
- `python -m unittest tests.test_sa1300_budget_selfpopulate -v`
- `powershell -ExecutionPolicy Bypass -File scripts\\lint-runtime-vs-webapi-allowlists.ps1`
- `powershell -ExecutionPolicy Bypass -File RAW\\scripts\\polarity-lint.ps1`
- `powershell -ExecutionPolicy Bypass -File scripts\\smoke-portal-routes.ps1 -BaseUrl https://quoteoperations.powerappsportals.com -Session qfu-dev -OutputJson output\\phase0\\portal-route-smoke-dev.json -OutputMarkdown output\\phase0\\portal-route-smoke-dev.md`

### Solution-boundary proof for the blocker

- `pac solution export --environment https://orgad610d2c.crm3.dynamics.com/ --name QuoteFollowUpSystemUnmanaged --path C:\Dev\QuoteFollowUpComplete\output\QuoteFollowUpSystemUnmanaged-dev-20260414.zip --managed false --overwrite`
- `pac solution unpack --zipfile C:\Dev\QuoteFollowUpComplete\output\QuoteFollowUpSystemUnmanaged-dev-20260414.zip --folder C:\Dev\QuoteFollowUpComplete\output\QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked --packagetype Unmanaged`
- `Get-ChildItem` inspections against the unpacked export root and `Entities`
- `Get-Content` against [output/QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked/Other/Solution.xml](C:\Dev\QuoteFollowUpComplete\output\QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked\Other\Solution.xml)

## Results

### Ready-to-Ship fix

- PASS at source/deploy verification level
- live downloaded dev runtime hash matches the local authoritative runtime exactly
- live downloaded dev runtime contains:
  - `readyToShip.hasData`
  - `statusNote`
  - `No Active Live Orders`
  - no duplicate branch-home Ready-to-Ship render path
- direct dev Dataverse verification for branch `4171`:
  - active orders: `14`
  - active lines: `26`
  - total unshipped value: `$82,142.52`

### Phase 0

- PASS
- `scripts\\lint-runtime-vs-webapi-allowlists.ps1`: PASS
- `RAW\\scripts\\polarity-lint.ps1`: PASS
- `tests.test_freight_parser`: baseline fail (`xlrd` missing)
- `tests.test_sa1300_budget_selfpopulate`: baseline fail (missing example SA1300 workbooks)
- `smoke-portal-routes.ps1`: harness PASS, route verification blocked by current Microsoft sign-in state in session `qfu-dev`

### Phase A blocker evidence

- the live exported unmanaged solution contains only:
  - `qfu_activitylog`
  - `qfu_backorder`
  - `qfu_budget`
  - `qfu_budgetarchive`
  - `qfu_financevariance`
  - `qfu_freightworkitem`
  - `qfu_lateorderexception`
  - `qfu_marginexception`
  - `qfu_notificationsetting`
  - `qfu_quote`
  - `qfu_quoteline`
  - `qfu_rosterentry`
- the live exported unmanaged solution does **not** contain:
  - `qfu_branch`
  - `qfu_region`
  - any AppModule / SiteMap source for the requested Admin and Manager model-driven panels
- because the request explicitly requires source-controlled, production-safe Admin / Manager panels and branch-config ownership in the same run, the implementation cannot continue honestly past Phase A from the current solution boundary
