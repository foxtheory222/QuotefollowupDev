# Freight Test Results

## Environment

- Dataverse / Power Pages environment: `https://regionaloperationshub.crm.dynamics.com`
- Live portal: `https://operationhub.powerappsportals.com`
- Branch under test: `4171 Calgary`
- Date executed: `2026-04-10`

## Test Inputs

Source sample root:

- `C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\example\vendor direct`

Extracted attachment manifest:

- `C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\results\freight-sample-attachment-manifest.json`

Extracted attachment folder:

- `C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\output\freight-samples\attachments`

Observed coverage:

- `4171`: Redwood, Loomis, Purolator, UPS
- `4172`: Redwood, Loomis, Purolator, UPS
- `4173`: Redwood, Loomis, Purolator
- `4173` UPS sample: not present in provided input set

## Parser / Normalization Tests

Command:

```powershell
python -m unittest tests.test_freight_parser -v
```

Result:

- Passed

Additional parser spot checks:

- `results/freight-parser-loomis-4171.json`
- `results/freight-parser-ups-4172.json`

## Real Import Path Tests

### Attachment extraction from real `.eml`

Command path:

- `scripts/extract-freight-email-attachments.py`

Result:

- Passed
- Real weekly freight attachments were extracted from the provided mailbox samples

### Queue seeding

Command path:

- `scripts/queue-freight-samples.ps1`

Result:

- Passed during live regression setup
- Raw freight documents and ingestion batches were created from the extracted sample attachments

### Queue processor with real `.xlsx` and `.xls`

Command path:

- `scripts/process-freight-inbox-queue.ps1`

Observed processed outcomes from the real sample set:

- `4171 FREIGHT_REDWOOD`: `input_rows=3`, `normalized_records=3`, `inserted=3`
- `4171 FREIGHT_LOOMIS_F15`: `input_rows=2`, `normalized_records=2`, `inserted=2`
- `4171 FREIGHT_PUROLATOR_F07`: `input_rows=49`, `normalized_records=49`, `inserted=49`
- `4172 FREIGHT_UPS_F06`: `input_rows=2`, `normalized_records=1`, `collapsed_group_rows=1`, `inserted=1`
- `4173 FREIGHT_REDWOOD`: `input_rows=0`, `normalized_records=0`, `inserted=0`

Interpretation:

- legacy `.xls` families were handled through the real parser/upsert path
- grouped/aggregated UPS rows were collapsed deterministically instead of creating duplicate work items

### Duplicate protection

Re-run outcome:

- duplicate attachments were detected by content hash
- batches were marked `duplicate`
- rows were not reinserted

Observed note example:

- `Duplicate freight attachment matched existing source ... No reprocess required.`

## Web API / Permission Tests

Allow-list lint artifact:

- `results/freight-allowlist-lint.md`
- `results/freight-allowlist-lint.json`

Result:

- `qfu_freightworkitem` runtime fields missing from allow-list: `0`

Anonymous security check:

- live detail route redirected to Microsoft sign-in
- anonymous `_api/qfu_freightworkitems?$top=1` returned sign-in HTML rather than freight JSON payload

Playwright artifact:

- `output/playwright/freight-portal-anonymous-check.json`
- `output/playwright/freight-portal-anonymous-check.png`

## Portal Rendering / Mutation Tests

Verifier command:

```powershell
node .\scripts\verify-freight-portal.cjs --portalMarker=QFU-FREIGHT-PORTAL-VERIFY-E2E20260410A --archiveMarker=QFU-FREIGHT-ARCHIVE-VERIFY-E2E20260410A
```

Verifier artifact:

- `output/playwright/freight-portal-verification-combined.json`
- `output/playwright/freight-portal-verification.json`
- `output/playwright/freight-portal-verify-baseline.png`
- `output/playwright/freight-portal-verify-final.png`

Authenticated checks:

- baseline worklist row load: passed
- take ownership: passed
- save note + status change: passed
- status filter: passed
- owner filter: passed
- release ownership: passed
- carrier filter: passed
- amount filter: passed
- CSV export: passed
- archive row: passed
- archived hidden by default: passed
- archived visible when `archived=1`: passed
- unarchive row: passed
- archive candidate hidden by default: passed
- archive candidate visible when `archived=1`: passed

Observed verifier output summary:

- authenticated checks: all passed
- anonymous check: sign-in challenge observed as expected

## Archive Flow Tests

Archive command path:

- `scripts/archive-freight-workitems.ps1`

Archive verification:

- seeded eligible `Closed` row older than 60 days
- archive script archived the candidate row
- archived row disappeared from the default active view
- archived row reappeared when archived items were included

## Portal Behavior Notes

Freight workbench behavior proven live:

- `/southern-alberta/4171-calgary/detail/?view=freight-worklist`
- branch entry point visible from the `4171` branch experience
- summary cards populate
- recent import panel renders
- workbench actions patch Dataverse rows

Additional runtime hardening used for verification:

- targeted freight `search` and `item` routes now push filters into the server-side OData query
- this keeps row-specific workbench links current even when the broad branch collection endpoint lags newly created verification rows

## 2026-04-10 Multi-Branch Enablement And Redesign Verification

Scope:

- enabled freight inbox automation for `4172` and `4173`
- verified freight source-feed configuration for `4171`, `4172`, and `4173`
- updated runtime import-status logic so `processed` and `duplicate` batches do not surface as false warnings
- redesigned the freight worklist hero, summary strip, filter bench, and row treatment using a Stitch-driven visual pass

Live deployment steps executed:

- `scripts/deploy-freight-worklist.ps1`
- `scripts/create-southern-alberta-freight-flow-solution.ps1 -ImportToTarget true`
- `pac pages upload --environment https://regionaloperationshub.crm.dynamics.com --path .\\powerpages-live\\operations-hub---operationhub --modelVersion Enhanced`

Live smoke artifacts:

- `output/playwright/freight-branch-smoke.json`
- `output/playwright/freight-smoke-4171-calgary.png`
- `output/playwright/freight-smoke-4172-lethbridge.png`
- `output/playwright/freight-smoke-4173-medicine-hat.png`

Observed live route results:

- `4171 Calgary`: redesigned freight route rendered, hero rendered, toolbar rendered, `25` visible paged rows, latest batch `duplicate`, no freight runtime diagnostics on the route
- `4172 Lethbridge`: redesigned freight route rendered, hero rendered, toolbar rendered, `25` visible paged rows, latest batch `processed`, no freight runtime diagnostics on the route
- `4173 Medicine Hat`: redesigned freight route rendered, hero rendered, toolbar rendered, `25` visible paged rows, latest batch `processed`, no freight runtime diagnostics on the route

Region / branch warning verification:

- `https://operationhub.powerappsportals.com/southern-alberta/`: no `freight-import-status` warning after the runtime status patch
- `https://operationhub.powerappsportals.com/southern-alberta/4171-calgary/`: no `freight-import-status` warning after the runtime status patch

Verification note:

- the existing mutation verifier `scripts/verify-freight-portal.cjs` was tightened during this pass to scope archive/unarchive actions to the specific row under test instead of whichever archive button happened to be first in the DOM

Deterministic rerun after the multi-branch Stitch redesign:

- seeded rows: `results/freight-verification-seed-20260410B.json`
- archive job evidence: `results/freight-archive-summary-20260410B.json`
- deterministic verifier evidence: `output/playwright/freight-verify-20260410B/freight-portal-verification-combined.json`

Seeded markers:

- portal marker: `QFU-FREIGHT-PORTAL-VERIFY-20260410B`
- archive marker: `QFU-FREIGHT-ARCHIVE-VERIFY-20260410B`

Deterministic verifier results:

- baseline targeted search: passed
- take ownership: passed
- save note + status update: passed
- status filter: passed
- owner filter: passed
- release ownership: passed
- carrier filter: passed
- amount filter: passed
- CSV export: passed
- archive selected row: passed
- archived row hidden by default: passed
- archived row visible with `archived=1`: passed
- unarchive selected row: passed
- archive candidate hidden by default after archive job: passed
- archive candidate visible with `archived=1`: passed
- anonymous route/API challenge: passed

## Known Limitations Remaining

- The provided `4173` input set did not include a UPS sample file.
- The broad Power Pages freight collection endpoint can lag ad hoc newly created verification rows. The targeted `search` / `item` route mitigation is live and verified; the underlying portal collection cache behavior is still a platform limitation to watch.
- The shared JSON writer helper did not reliably materialize the queue/archive summary files in this workspace session even though the scripts returned structured console output and the live portal/Dataverse results were verified directly.
