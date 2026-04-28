# Live Duplicate Sample Evidence

- Quote duplicate sample: `4171|SP830CA|0515441439` has two rows created `2026-04-08 23:48:00`, same file `SP830CA - Quote Follow Up Report.xlsx`, no import batch id.
- Backorder duplicate sample: `4171|ZBO|1522944165|10` has two rows created `2026-04-08 23:49:00`, same file `CA ZBO 20250320_30_4023207436626456977.xlsx`, no import batch id.
- Delivery lifecycle sample: active current rows return `qfu_active = No` with `qfu_inactiveon = null`; historical rows return `qfu_active = Yes` with populated `qfu_inactiveon`, so `qfu_inactiveon` is the reliable lifecycle signal in PowerShell/XRM here.
- Ingestion batch duplicate sample: `4171|batch|SP830CA`, `4171|batch|ZBO`, and `4171|batch|SA1300` each exist twice with the same `Controlled workbook seed` trigger and the same `2026-04-08 23:51:00` created timestamp.

These samples were collected by safe direct live Dataverse inspection during the 2026-04-09 audit pass.