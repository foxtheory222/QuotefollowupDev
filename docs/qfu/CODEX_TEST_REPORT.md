# QFU Codex Test Report

Updated: 2026-04-14 America/Edmonton

## Ready-to-Ship Runtime Verification

### Commands

1. `node --check` against the extracted runtime JS from [QFU-Regional-Runtime.webtemplate.source.html](C:\Dev\QuoteFollowUpComplete\site\web-templates\qfu-regional-runtime\QFU-Regional-Runtime.webtemplate.source.html)
2. `pac pages upload --environment https://orgad610d2c.crm3.dynamics.com/ --path C:\Dev\QuoteFollowUpComplete\powerpages-upload-dev\quotefollowup\quotefollowup---quotefollowup --modelVersion 2 --forceUploadAll`
3. `pac pages download --environment https://orgad610d2c.crm3.dynamics.com/ --websiteId 7d15dda2-9ad5-430e-ae7e-0fdab0630b2f --path C:\Dev\QuoteFollowUpComplete\output\dev-verify-current-live --modelVersion 2`
4. `Get-FileHash` comparison between the local authoritative runtime and the downloaded live dev runtime
5. direct `Microsoft.Xrm.Data.Powershell` query against `qfu_deliverynotpgi` for branch `4171`
6. `powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\\audit-live-operational-current-state.ps1 -TargetEnvironmentUrl https://orgad610d2c.crm3.dynamics.com -OutputJson VERIFICATION\\operational-current-state-dev.json -OutputMarkdown VERIFICATION\\operational-current-state-dev.md`

### Result

- PASS at source/deploy verification level

### Verified markers in downloaded live dev runtime

- `readyToShip.hasData`
- `statusNote`
- `No Active Live Orders`
- `Dispatch snapshot pending`
- duplicate branch-home Ready-to-Ship render path removed from the deployed runtime

### Verified underlying dev data for branch `4171`

- active orders: `14`
- active lines: `26`
- total unshipped value: `$82,142.52`

## Phase 0 Baseline Validation

### Commands

1. `python -m unittest tests.test_freight_parser -v`
2. `python -m unittest tests.test_sa1300_budget_selfpopulate -v`
3. `powershell -ExecutionPolicy Bypass -File scripts\\lint-runtime-vs-webapi-allowlists.ps1`
4. `powershell -ExecutionPolicy Bypass -File RAW\\scripts\\polarity-lint.ps1`
5. `powershell -ExecutionPolicy Bypass -File scripts\\smoke-portal-routes.ps1 -BaseUrl https://quoteoperations.powerappsportals.com -Session qfu-dev -OutputJson output\\phase0\\portal-route-smoke-dev.json -OutputMarkdown output\\phase0\\portal-route-smoke-dev.md`

### Results

| Command | Result | Notes |
| --- | --- | --- |
| `python -m unittest tests.test_freight_parser -v` | FAIL (baseline) | Missing Python dependency `xlrd` |
| `python -m unittest tests.test_sa1300_budget_selfpopulate -v` | FAIL (baseline) | Example workbooks missing under `example\\4171`, `example\\4172`, `example\\4173` |
| `scripts\\lint-runtime-vs-webapi-allowlists.ps1` | PASS | `missingFieldTableCount = 0` |
| `RAW\\scripts\\polarity-lint.ps1` | PASS | `suspiciousCount = 0` |
| `scripts\\smoke-portal-routes.ps1` | PASS as harness execution | All routes redirected to Microsoft login because the current `qfu-dev` browser session is unauthenticated |

## Solution Boundary Verification

### Commands

1. `pac solution export --environment https://orgad610d2c.crm3.dynamics.com/ --name QuoteFollowUpSystemUnmanaged --path C:\Dev\QuoteFollowUpComplete\output\QuoteFollowUpSystemUnmanaged-dev-20260414.zip --managed false --overwrite`
2. `pac solution unpack --zipfile C:\Dev\QuoteFollowUpComplete\output\QuoteFollowUpSystemUnmanaged-dev-20260414.zip --folder C:\Dev\QuoteFollowUpComplete\output\QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked --packagetype Unmanaged`
3. inspection of the unpacked export root and [Other/Solution.xml](C:\Dev\QuoteFollowUpComplete\output\QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked\Other\Solution.xml)

### Result

- PASS as blocker proof
- the live unmanaged solution export does not contain:
  - `qfu_branch`
  - `qfu_region`
  - AppModule / SiteMap source for the requested Admin and Manager model-driven panels

## Baseline vs Introduced Failures

- Baseline failures:
  - missing `xlrd`
  - missing example SA1300 workbooks
  - browser route validation blocked by current Microsoft sign-in state
- Introduced failures:
  - none proven in this run

## Artifacts

- [portal-route-smoke-dev.md](C:\Dev\QuoteFollowUpComplete\output\phase0\portal-route-smoke-dev.md)
- [portal-route-smoke-dev.json](C:\Dev\QuoteFollowUpComplete\output\phase0\portal-route-smoke-dev.json)
- [operational-current-state-dev.md](C:\Dev\QuoteFollowUpComplete\VERIFICATION\operational-current-state-dev.md)
- [operational-current-state-dev.json](C:\Dev\QuoteFollowUpComplete\VERIFICATION\operational-current-state-dev.json)
- [dev-verify-current-live](C:\Dev\QuoteFollowUpComplete\output\dev-verify-current-live)
- [QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked](C:\Dev\QuoteFollowUpComplete\output\QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked)
