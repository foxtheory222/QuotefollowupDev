# Freight Ledger Row-Grain Review - 2026-04-24

## Scope

Reviewed the freight sample workbooks under `output/freight-samples/attachments` and the portal freight ledger runtime because the live ledger was grouping by invoice and showing confusing duplicates.

## Source Shape

- Redwood `.xlsx`: reviewed samples expose one operational row per invoice.
- Loomis `.xls`: reviewed samples are effectively one tracking row per invoice.
- Purolator `.xls`: one invoice can contain many distinct tracking rows. Example: branch `4171`, invoice `550256777`, file `Purolator Invoices Report [F07] by control# [APICAPIC5141] 8738328.xls` has 49 source rows with 49 distinct tracking entries and a total of `3924.74`.
- UPS `.xls`: the branch `4172` sample has two source rows with the same tracking identity and total `339.72`; those rows should collapse into one shipment/charge entry.

## Decision

Invoice is a searchable/display field, not the freight ledger row grain. The operational row grain is shipment/charge entry:

- if tracking is present, group/upsert by branch + family + control + invoice + tracking + reference + service;
- if tracking is missing, use invoice/reference/shipper/service fallback;
- true duplicate source rows for the same tracking entry may collapse;
- distinct tracking rows under the same invoice must stay visible as separate ledger entries.

## Changes Made

- Updated hosted parser normalization so Purolator same-invoice tracking rows remain separate and UPS same-tracking rows still collapse.
- Removed hosted upsert fallback that matched existing rows by branch/source family/invoice. Existing work is now preserved only when the incoming `qfu_sourceid` matches exactly.
- Updated Power Pages freight ledger runtime to render `freightSourceRows` directly instead of regrouping rows for display.
- Updated freight ledger copy from bill groups to ledger entries and made the primary identifier tracking/PRO/reference before invoice.

## Validation

- `python -m unittest tests.test_freight_parser -v`
- `python -m unittest tests.test_freight_hosted_parser_contracts -v`
- `python -m unittest tests.test_powerpages_runtime_contracts -v`
- Runtime JavaScript parse check with `node`.

## Live Data Follow-Up

Earlier on 2026-04-24, `results/live-freight-current-state-duplicate-repair-applied-20260424.json` archived current-state rows by invoice. That live-data repair conflicts with the row-grain decision above. The durable fix is to replay the affected freight source files through the corrected hosted parser, or run an auditable restore that unarchives the shipment-level rows and restores rolled-up survivor amounts from source payloads. Do not treat the invoice-level survivor totals as final freight-ledger truth.

Post-upload live check `results/live-freight-invoice-sourceid-check-20260424-row-grain.json` still found 11 active `qfu_sourceid` values containing `|invoice|`, including `4171|freight-purolator-f07|invoice|550256777`.

Follow-up repair `scripts/repair-live-freight-invoice-survivors.ps1` was run against live Dataverse on 2026-04-24 after a clean dry-run. It parsed the original freight raw documents already stored in Dataverse, restored 316 shipment-level non-Redwood freight work items, and archived the 11 invoice-level survivor rows. The apply artifact is `results/live-freight-invoice-survivor-restore-applied-20260424.json`.

Post-repair validation `results/live-freight-invoice-survivor-restore-postcheck-20260424.json` found:

- active non-Redwood `|invoice|` source IDs: `0`
- failed repair checks: `0`
- `4171|FREIGHT_PUROLATOR_F07|550256777`: 49 active restored shipment rows totaling `3924.74`

## Remaining Durability Watch

The hosted parser/source code and local queue processor now use shipment-level source IDs. Azure Functions Core Tools `4.9.0` was installed and locally validated on 2026-04-24; `results/func-host-check-20260424-wrapper/func-local-check.json` shows the freight parser host started and registered `POST /api/processfreightdocument`. Because the WinGet Node install path is too long for the Python worker gRPC DLL, `func` now resolves through a short wrapper at `C:\Users\smcfarlane\funcnode`.

This workspace still does not have `az` or `azd`, so cloud publish/Function App deployment was not validated. If live freight ingress is already calling a deployed hosted parser, deploy this parser change before the next unattended freight run. If the controlled local queue repair path is used as a temporary bridge, `scripts/process-freight-inbox-queue.ps1` now shares the corrected exact-source-ID behavior. The durable fix remains Power Automate + hosted parser, not a recurring local scheduled-task fallback.
