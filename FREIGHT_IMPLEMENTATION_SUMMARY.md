# Freight Worklist Implementation Summary

## Scope

This pass implemented a branch-first freight worklist inside the existing QFU runtime architecture for:

- Route: `/southern-alberta/{branch}/detail/?view=freight-worklist`
- Initial live branch: `4171 Calgary`
- Config-ready follow-on branches: `4172 Lethbridge`, `4173 Medicine Hat`

The implementation preserved the existing stack:

- Power Pages shared runtime
- Dataverse source of truth
- Power Automate inbox/queue orchestration
- scriptable local regression path for legacy `.xls` parsing and replay

Update as of April 21, 2026:

- the local queue processor is no longer the intended unattended production path
- the durable replacement is a hosted freight parser contract under `src/freight_parser_host`
- mailbox ingress should create audit rows, call the hosted parser, and stamp `qfu_rawdocument` / `qfu_ingestionbatch` from the hosted result

## What Was Added

### Dataverse

New normalized actionable table:

- `qfu_freightworkitem`

Schema groups added:

- identity/lineage: `qfu_sourceid`, branch/region fields, source family/carrier/file, raw row json, import batch id
- shipment facts: tracking, PRO, invoice, control/reference, ship/invoice/close dates, bill type, service/service code, sender/destination, zone, weights, quantity
- normalized money: total, freight, fuel, tax, GST/HST/QST, accessorial, unrealized savings, charge breakdown text
- operational state: direction, status, priority band, owner name/id, claimed on, comment, comment metadata, last activity, archived flag, archived on, last seen on

Hardening:

- alternate key `qfu_freightworkitem_sourceid_key` on `qfu_sourceid`
- source-feed rows for freight families
- authenticated freight table permission
- Web API allow-list entries for `qfu_freightworkitem`

### Power Pages

Updated:

- `powerpages-live/operations-hub---operationhub/web-templates/qfu-regional-runtime/QFU-Regional-Runtime.webtemplate.source.html`
- `powerpages-live/operations-hub---operationhub/web-files/qfu-phase0.css`
- `powerpages-live/operations-hub---operationhub/sitesetting.yml`
- `powerpages-live/operations-hub---operationhub/table-permissions/operationhub-qfu_freightworkitem-Authenticated-ReadWrite.tablepermission.yml`

Freight runtime features:

- new detail view key: `freight-worklist`
- branch entry point and branch tile
- summary cards for filtered dollars, actionable count, unowned count, high-value count, latest import state
- filters for carrier, status, owner, bill type, service, direction, archived on/off, min/max amount, search
- search coverage for tracking, PRO, invoice, reference, sender, destination
- row actions for take ownership, release ownership, save note/status, archive/unarchive
- CSV export
- stale/latest import diagnostics from `qfu_ingestionbatch`
- targeted server-side filtering for `search` and `item` routes so row-specific freight workbench links pull current records reliably

### Flows / Processing

Source-controlled deployment artifacts:

- `scripts/create-southern-alberta-freight-flow-solution.ps1`
- generated source: `results/safreightflows/`
- packed solution: `results/qfu-southern-alberta-freight-flows.zip`

Live flow names:

- `4171-Freight-Inbox-Ingress`
- `QFU-Freight-Archive-Workitems`

Processing / replay / diagnostics scripts:

- `scripts/freight_parser.py`
- `scripts/parse-freight-report.py`
- `scripts/extract-freight-email-attachments.py`
- `scripts/queue-freight-samples.ps1`
- `scripts/process-freight-inbox-queue.ps1`
- `scripts/archive-freight-workitems.ps1`
- `scripts/seed-freight-verification-rows.ps1`
- `scripts/verify-freight-portal.cjs`
- `tests/test_freight_parser.py`
- `tests/test_freight_hosted_parser_contracts.py`
- `src/freight_parser_host/`

Processing model:

- mailbox/flow stage logs raw attachment + ingestion batch
- hosted parser is the durable unattended parser/upsert target
- deterministic `qfu_sourceid` drives upsert/idempotency; as of the April 24, 2026 freight-ledger correction, legacy carrier `.xls` rows are keyed at shipment/charge-entry grain. Tracking-bearing rows use branch + carrier family + control + invoice + tracking + reference + service, so repeated imports update the same shipment entry while different tracking rows on the same invoice remain separate ledger entries.
- history is preserved; rows are not snapshot-deleted just because a later weekly file omits them
- archive flow moves only `Closed` / `No Action` rows with 60 idle days into archived state

Local processor task:

- scheduled task `QFU-Freight-Inbox-Queue-Processor`
- current observed state from April 21, 2026 repair audit: missing
- role going forward: emergency repair only until the hosted parser path is deployed live

## Deployment Notes

Power Pages source was refreshed from the target environment/site before freight runtime edits in this session:

- Environment: `https://regionaloperationshub.crm.dynamics.com`
- Site folder: `powerpages-live/operations-hub---operationhub`

Live Power Pages uploads succeeded with:

- `pac pages upload --environment https://regionaloperationshub.crm.dynamics.com --path .\\powerpages-live\\operations-hub---operationhub --modelVersion Enhanced`

Known upload warning seen repeatedly but non-blocking in this pass:

- `XRM Network error: Entity 'powerpagecomponent' ... Does Not Exist`
- uploads still completed successfully and live runtime changes were verified afterward

## Live-Tested Outcomes

- real freight samples from `example/vendor direct` were extracted from `.eml`
- legacy `.xls` parsing worked for Loomis, Purolator, and UPS
- Redwood-style `.xlsx` parsing worked
- `qfu_freightworkitem` rows were created from the real samples
- duplicate raw attachments were detected and logged as duplicate batches instead of re-imported
- live portal route loaded and rendered freight rows
- ownership, note/status save, archive/unarchive, CSV export, filters, and archived visibility were all verified with Playwright
- anonymous access was blocked by the private-site auth flow

## Known Limitations

- The provided `4173` sample set did not include a UPS file, so UPS parsing was proven with `4171` and `4172`, not `4173`.
- The broad branch collection endpoint on Power Pages can lag recently created ad hoc verification rows. To keep freight drill-ins reliable, the runtime now pushes `search` / `item` freight detail routes into server-side OData filters.
- The local summary JSON outputs requested by the queue/archive scripts were not reliably materialized on disk by the shared JSON writer helper in this workspace session even though the scripts returned structured console output and the live effects were verified.
