# Operational Current-State Audit

- Generated: 2026-04-14 00:09:10
- Environment: https://orgad610d2c.crm3.dynamics.com
- Branches: 4171, 4172, 4173

## qfu_quote

- Table role: current-state
- Canonical key: qfu_sourceid (branch|SP830CA|quotenumber)
- Total rows: 172
- Unique source ids: 172
- Duplicate groups: 0
- Duplicate rows: 0
- Active rows: 36
- Inactive rows: 136
- Rows missing lifecycle fields: 0

## qfu_backorder

- Table role: current-state
- Canonical key: qfu_sourceid (branch|ZBO|salesdoc|line)
- Total rows: 1993
- Unique source ids: 1993
- Duplicate groups: 0
- Duplicate rows: 0
- Active rows: 1047
- Inactive rows: 946
- Rows missing lifecycle fields: 0

## qfu_marginexception

- Table role: snapshot
- Canonical key: qfu_sourceid (branch|SA1300-MARGIN|snapshotdate|billingdoc|reviewtype)
- Total rows: 58
- Unique source ids: 58
- Duplicate groups: 0
- Duplicate rows: 0

## qfu_deliverynotpgi

- Table role: snapshot with active/inactive lifecycle
- Canonical key: branch + delivery number + delivery line
- Total rows: 590
- Unique source ids: 590
- Duplicate groups: 0
- Duplicate rows: 0
- Active rows: 84
- Inactive rows: 506
- Rows missing lifecycle fields: 0

## Latest Imports

| Branch | Family | Status | Source started | Row created | Seeded | Trigger | File |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 4171 | SP830CA | ready | 2026-04-13 16:17:00 | 2026-04-14 01:04:00 | False | 4171-QuoteFollowUp-Import-Staging | SP830CA - Quote Follow Up Report.xlsx |
| 4171 | ZBO | ready | 2026-04-13 13:26:00 | 2026-04-14 01:04:00 | False | 4171-BackOrder-Update-ZBO | 4171_ZBO_20260410_132603_CA ZBO 20250320_72_1486460619880492027.xlsx |
| 4171 | SA1300 | ready | 2026-04-13 16:18:00 | 2026-04-14 01:04:00 | False | 4171-Budget-Update-SA1300 | SA1300.xlsx |
| 4171 | SA1300-ABNORMALMARGIN | ready | 2026-04-13 16:18:00 | 2026-04-14 01:04:00 | False | 4171-Budget-Update-SA1300 | SA1300.xlsx |
| 4172 | SP830CA | ready | 2026-04-13 16:17:00 | 2026-04-14 01:04:00 | False | 4172-QuoteFollowUp-Import-Staging | SP830CA - Quote Follow Up Report.xlsx |
| 4172 | ZBO | ready | 2026-04-13 16:17:00 | 2026-04-14 01:04:00 | False | 4172-BackOrder-Update-ZBO | CA SC ZBO - 20260120_227_1520796141058127806.xlsx |
| 4172 | SA1300 | ready | 2026-04-13 16:17:00 | 2026-04-14 01:04:00 | False | 4172-Budget-Update-SA1300 | SA1300.xlsx |
| 4172 | SA1300-ABNORMALMARGIN | ready | 2026-04-13 16:17:00 | 2026-04-14 01:04:00 | False | 4172-Budget-Update-SA1300 | SA1300.xlsx |
| 4173 | SP830CA | ready | 2026-04-13 16:17:00 | 2026-04-14 01:04:00 | False | 4173-QuoteFollowUp-Import-Staging | SP830CA - Quote Follow Up Report.xlsx |
| 4173 | ZBO | ready | 2026-04-13 16:18:00 | 2026-04-14 01:04:00 | False | 4173-BackOrder-Update-ZBO | CA SC ZBO - 20260120_239_4306963741963260235.xlsx |
| 4173 | SA1300 | ready | 2026-04-13 16:18:00 | 2026-04-14 01:04:00 | False | 4173-Budget-Update-SA1300 | SA1300.xlsx |
| 4173 | SA1300-ABNORMALMARGIN | ready | 2026-04-13 16:18:00 | 2026-04-14 01:04:00 | False | 4173-Budget-Update-SA1300 | SA1300.xlsx |
