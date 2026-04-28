# Freight Current-State Dedupe Fix - 2026-04-24

## Issue

Purolator invoice `550256777` for branch `4171` was imported as many separate `qfu_freightworkitem` rows because the freight source ID included tracking/reference/service details. The UI can group those rows, but the durable fix belongs in ingestion so repeated imports behave like quote current-state imports.

## Durable Fix Path

- Parser now uses branch + source family + invoice as the `qfu_sourceid` when an invoice number exists.
- Carrier report rows with the same invoice now collapse into one normalized freight bill work item.
- Hosted parser upsert now falls back from source ID lookup to branch + source family + invoice lookup, so the first canonical import updates an existing legacy detailed row instead of creating another active row.
- Local emergency queue processor was updated with the same fallback lookup.

## Validation

- `python -m unittest tests.test_freight_parser tests.test_freight_hosted_parser_contracts -v`
- PowerShell parser check for `scripts/process-freight-inbox-queue.ps1`
- Sample parse: `4171` Purolator file with 49 rows for invoice `550256777` now normalizes to 1 work item with source ID `4171|freight-purolator-f07|invoice|550256777`.

## Still Required

- Deploy the updated hosted freight parser before the next unattended freight import.
- Run a live duplicate repair or allow the next canonical import to update one legacy row; older legacy rows will remain until intentionally archived/merged.
- Verify the next live freight ingestion batch has `updatedcount > 0` for previously seen invoices instead of creating a new set of tracking-line rows.
- Deployment was not attempted in this workspace because neither `azd` nor `az` is installed, and the Azure subscription/location for the hosted parser still needs confirmation.
