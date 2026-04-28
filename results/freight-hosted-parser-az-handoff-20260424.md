# Freight Hosted Parser Azure Handoff - 2026-04-24

## Paste This Prompt Later

Continue from `C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion`.

Read `AGENTS.md` first and follow the Power Pages / Dataverse / Power Automate rules. The immediate goal is to finish Azure deployment readiness for the freight hosted parser after I install `az` and `azd`.

Current state:

- Freight ledger row grain has been corrected in code and live Dataverse.
- Non-Redwood freight should not group by invoice. Invoice is metadata/search only.
- Active non-Redwood `|invoice|` freight survivors were repaired on 2026-04-24.
- Postcheck artifact: `results/live-freight-invoice-survivor-restore-postcheck-20260424.json`
- Active non-Redwood invoice source IDs after repair: `0`
- `4171|FREIGHT_PUROLATOR_F07|550256777` validated as 49 active shipment rows totaling `$3,924.74`.
- Azure Functions Core Tools `4.9.0` is installed.
- Because the WinGet Node path is too long for the Python worker gRPC DLL, `func` resolves through a short wrapper at `C:\Users\smcfarlane\funcnode`.
- Local Function host validation passed:
  `results/func-host-check-20260424-wrapper/func-local-check.json`
- `az` and `azd` were not installed at the time of handoff, so cloud publish/deployment was not done.

Files involved:

- Hosted parser app: `src/freight_parser_host`
- Parser core: `src/freight_parser_host/qfu_freight_parser/core.py`
- Hosted upsert: `src/freight_parser_host/qfu_freight_parser/processor.py`
- Local queue bridge: `scripts/process-freight-inbox-queue.ps1`
- Live repair helper: `scripts/repair-live-freight-invoice-survivors.ps1`
- Live repair verifier: `scripts/verify-live-freight-invoice-survivor-restore.ps1`
- Freight row-grain notes: `results/freight-ledger-row-grain-review-20260424.md`
- Durable repo copy: `tmp-github-QuoteFollowUp`

Start by verifying tools:

```powershell
az --version
azd version
func --version
python -m unittest tests.test_freight_parser tests.test_freight_hosted_parser_contracts -v
```

Then determine the existing Azure target before publishing anything:

```powershell
az login
az account show
az functionapp list --query "[].{name:name, resourceGroup:resourceGroup, state:state, defaultHostName:defaultHostName}" -o table
```

Do not guess the subscription, resource group, or Function App name. If there is an existing freight parser Function App, inspect it first. If none exists, propose the smallest deployment plan before creating resources.

Deployment checklist:

- Confirm target subscription/resource group/Function App.
- Deploy `src/freight_parser_host` only after confirming the target.
- Ensure app settings include `QFU_DATAVERSE_URL=https://regionaloperationshub.crm.dynamics.com`.
- Confirm Dataverse auth path: managed identity or service principal.
- Validate the hosted route: `POST /api/processfreightdocument`.
- Confirm the function key / URL that Power Automate should call.
- If updating freight ingress flows, keep Power Automate as the production ingestion path and avoid recurring local scheduled-task fallbacks.
- Do not rerun `scripts/repair-live-freight-current-state-duplicates.ps1`; it was the invoice-grouping direction and conflicts with the corrected row grain.
- If any live repair/replay is required, require explicit branch/source filters and write row IDs/timestamps to `results`.

Validation order:

1. Unit tests and local Function host.
2. Function App deployment status and app settings.
3. Controlled hosted parser request or controlled raw document replay.
4. Dataverse `qfu_freightworkitem` rows: exact shipment-level `qfu_sourceid`, no active non-Redwood `|invoice|` survivors.
5. `qfu_ingestionbatch` and `qfu_rawdocument` status stamping.
6. Authenticated portal render if browser auth is available.

After any deploy or live repair, update:

- `results/freight-ledger-row-grain-review-20260424.md`
- a new validation artifact under `results/`
- mirror durable files into `tmp-github-QuoteFollowUp`

Important assumptions:

- Redwood `.xlsx` rows remain invoice-level because reviewed samples expose one operational row per invoice.
- Loomis/Purolator/UPS carrier `.xls` rows use shipment/charge-entry source IDs.
- Existing owner/comment/status should be preserved only on exact `qfu_sourceid` matches or through a documented targeted repair.
