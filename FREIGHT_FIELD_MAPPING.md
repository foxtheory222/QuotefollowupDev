# Freight Field Mapping

## Normalization Rules Shared Across Families

- `qfu_sourceid`
  Deterministic current-state key. For legacy carrier `.xls` files, invoice is not the operational row grain. Rows with a tracking number use branch + source family + control + invoice + tracking + reference + service so distinct tracking rows under one invoice remain separate ledger entries. Re-seen rows with the same tracking identity update in place. Rows without tracking fall back to invoice/reference/shipper/service, and the Redwood invoice workbook remains invoice-row grain because the reviewed samples expose one operational row per invoice.
- `qfu_totalamount`
  Best operational review amount for the row. Prefer explicit total; otherwise sum parsed component charges.
- `qfu_direction`
  `Internal` when sender and destination both look like Applied/internal locations, `Outbound` when sender looks Applied and destination does not, else `Inbound`.
- `qfu_priorityband`
  defaults to `High Value` when total is at/above the runtime threshold, otherwise `Standard`.
- `qfu_status`
  defaults to `Open` on ingest; portal users can update later.
- `qfu_lastseenon`
  set to the observation/import time on every successful re-seen row.
- `qfu_rawrowjson`
  stores the normalized parser input/debug payload for row-level troubleshooting.

## FREIGHT_REDWOOD

Source shape:

- Applied / Redwood invoice workbook (`.xlsx`)

Primary input fields:

- `Cost Center`
- `Invoice Number`
- `Primary Reference`
- `Ref1`, `Ref2`, `Ref3`
- `Invoice SCAC`
- `Invoice Carrier`
- `Carrier Mode`
- `PRO`
- `Target Ship`, `Actual Ship`
- `Target Delivery`, `Actual Delivery`
- `Origin`, `Destination`
- `Total Invoice Amount Tax Included`
- `Freight Cost Only`
- `Fuel`
- `GST`, `HST`, `QST`
- accessorial columns
- least-cost / normalized savings columns

Normalized mapping:

- invoice number -> `qfu_invoicenumber`
- primary / secondary references -> `qfu_reference`
- PRO -> `qfu_pronumber`
- carrier -> `qfu_sourcecarrier`
- mode -> `qfu_service`
- ship/delivery timing -> `qfu_shipdate`, `qfu_closedate`
- origin/destination -> `qfu_sender`, `qfu_destination`
- explicit total -> `qfu_totalamount`
- freight / fuel / GST-HST-QST -> matching money fields
- accessorial columns -> `qfu_accessorialamount`, `qfu_accessorialpresent`
- normalized savings -> `qfu_unrealizedsavings`

Transform notes:

- when multiple references exist, the normalization keeps the operationally useful joined reference text
- explicit totals win over recomputed totals
- least-cost carrier comparison is preserved as savings/debug context, not as a replacement source of truth

## FREIGHT_LOOMIS_F15

Source shape:

- Loomis legacy invoice report (`.xls`)

Primary input fields:

- `Shipper`
- `Tracking`
- `Invoice`
- `Invoice Date`
- `Ship Date`
- `Close Date`
- `Bill Type`
- `Service`
- `Sender`
- `Destination`
- `Zone`
- `Bill Wgt`
- `Reference`
- `Billed Charges`
- `Charge Description`
- tax/accessorial fields when present

Normalized mapping:

- tracking -> `qfu_trackingnumber`
- invoice -> `qfu_invoicenumber`
- invoice date / ship date / close date -> matching date fields
- bill type / service -> `qfu_billtype`, `qfu_service`
- sender / destination -> `qfu_sender`, `qfu_destination`
- zone / billed weight -> `qfu_zone`, `qfu_billedweight`
- reference -> `qfu_reference`
- billed charges -> `qfu_totalamount`
- parsed line items from charge description -> freight/fuel/tax/accessorial breakdown fields

Transform notes:

- when Loomis exposes component charges in descriptive text, the parser classifies freight, fuel, GST, and accessorials and then reconciles against billed total
- `qfu_totalamount` remains the billed total even when components are parsed separately

## FREIGHT_PUROLATOR_F07

Source shape:

- Purolator legacy invoice report (`.xls`)

Primary input fields:

- `Shipper`
- `Tracking`
- `Invoice`
- `Invoice Date`
- `Ship Date`
- `Bill Type`
- `Service`
- `Sender`
- `Destination`
- `Zone`
- `Act Wgt`
- `Bill Wgt`
- `Reference`
- `Charge Description With Extended Bill Amount`
- GST/HST/QST extended fields

Normalized mapping:

- tracking -> `qfu_trackingnumber`
- invoice -> `qfu_invoicenumber`
- dates -> `qfu_invoicedate`, `qfu_shipdate`
- bill type / service -> `qfu_billtype`, `qfu_service`
- sender / destination / zone -> `qfu_sender`, `qfu_destination`, `qfu_zone`
- actual/billed weight -> `qfu_actualweight`, `qfu_billedweight`
- reference -> `qfu_reference`
- parsed extended bill amounts -> total/freight/fuel/tax/accessorial fields

Transform notes:

- Purolator rows often need text parsing because component amounts are embedded in extended charge descriptions
- GST/HST/QST are normalized separately when explicitly present
- if only parsed components exist, `qfu_totalamount` is derived from the usable component sum instead of leaving a false zero
- rows sharing the same invoice stay separate when the tracking number is different; invoice number is display/search metadata, not the ledger entry grain

## FREIGHT_UPS_F06

Source shape:

- UPS legacy invoice report (`.xls`)

Primary input fields:

- `Shipper`
- `Tracking`
- `Invoice`
- `Invoice Date`
- `Ship Date`
- `Close Date`
- `Bill Type`
- `Service`
- `Code`
- `Desc`
- `Sender`
- `Destination`
- `Zone`
- `Act Wgt`
- `Bill Wgt`
- `Qty`
- `Reference`
- `Billed Charges`
- `Charge Description`
- GST/HST/QST fields

Normalized mapping:

- tracking -> `qfu_trackingnumber`
- invoice -> `qfu_invoicenumber`
- dates -> `qfu_invoicedate`, `qfu_shipdate`, `qfu_closedate`
- bill type / service / service code -> `qfu_billtype`, `qfu_service`, `qfu_servicecode`
- sender / destination / zone -> `qfu_sender`, `qfu_destination`, `qfu_zone`
- weights / qty -> `qfu_actualweight`, `qfu_billedweight`, `qfu_quantity`
- reference -> `qfu_reference`
- billed charges -> `qfu_totalamount`
- charge description / code rows -> `qfu_chargebreakdowntext`, component money fields

Transform notes:

- UPS sample groups can collapse multiple raw rows into one operational row when they belong to the same logical tracking entry
- the parser reports collapsed row counts so aggregation is visible in test output

## Source Coverage Proven In This Pass

- `4171`
  - Redwood `.xlsx`
  - Loomis `.xls`
  - Purolator `.xls`
  - UPS `.xls`
- `4172`
  - Redwood `.xlsx`
  - Loomis `.xls`
  - Purolator `.xls`
  - UPS `.xls`
- `4173`
  - Redwood `.xlsx`
  - Loomis `.xls`
  - Purolator `.xls`
  - no UPS sample was present in the provided folder
