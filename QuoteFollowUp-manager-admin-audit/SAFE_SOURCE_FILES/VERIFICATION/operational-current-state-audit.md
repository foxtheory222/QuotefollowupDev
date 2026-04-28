# Operational Current-State Audit

- Generated: 2026-04-09 15:04:23
- Environment: <URL>
- Branches: 4171, 4172, 4173

## qfu_quote

- Table role: current-state
- Canonical key: qfu_sourceid (branch|SP830CA|quotenumber)
- Total rows: 56
- Unique source ids: 56
- Duplicate groups: 0
- Duplicate rows: 0
- Active rows: 56
- Inactive rows: 0
- Rows missing lifecycle fields: 0

## qfu_backorder

- Table role: current-state
- Canonical key: qfu_sourceid (branch|ZBO|salesdoc|line)
- Total rows: 1512
- Unique source ids: 1512
- Duplicate groups: 0
- Duplicate rows: 0
- Active rows: 1512
- Inactive rows: 0
- Rows missing lifecycle fields: 0

## qfu_marginexception

- Table role: snapshot
- Canonical key: qfu_sourceid (branch|SA1300-MARGIN|snapshotdate|billingdoc|reviewtype)
- Total rows: 38
- Unique source ids: 38
- Duplicate groups: 0
- Duplicate rows: 0

## qfu_deliverynotpgi

- Table role: snapshot with active/inactive lifecycle
- Canonical key: branch + delivery number + delivery line
- Total rows: 491
- Unique source ids: 481
- Duplicate groups: 10
- Duplicate rows: 20
- Active rows: 212
- Inactive rows: 279
- Rows missing lifecycle fields: 0

| Duplicate key | Count | Winner | Sample rows |
| --- | ---: | --- | --- |
| 4171, 4171\\|ZBO\\|1522978429\\|10 | 2 | <GUID> | <GUID> / 2026-04-08 16:08:00 / 2026-04-09 20:43:00 / 2026-04-09 20:00:00 / 1522978429 / 10 ; <GUID> / 2026-04-02 21:26:00 / 2026-04-09 20:43:00 / 2026-04-02 21:39:00 / 1522978429 / 10 |
| 4171, 4171\\|ZBO\\|1522915717\\|20 | 2 | <GUID> | <GUID> / 2026-04-08 16:08:00 / 2026-04-09 20:43:00 / 2026-04-09 20:00:00 / 1522915717 / 20 ; <GUID> / 2026-04-02 21:26:00 / 2026-04-09 20:43:00 / 2026-04-02 21:39:00 / 1522915717 / 20 |
| 4171, 4171\\|ZBO\\|1522915717\\|30 | 2 | <GUID> | <GUID> / 2026-04-08 16:08:00 / 2026-04-09 20:43:00 / 2026-04-09 20:00:00 / 1522915717 / 30 ; <GUID> / 2026-04-02 21:26:00 / 2026-04-09 20:43:00 / 2026-04-02 21:39:00 / 1522915717 / 30 |
| 4171, 4171\\|ZBO\\|1522915717\\|40 | 2 | <GUID> | <GUID> / 2026-04-08 16:08:00 / 2026-04-09 20:43:00 / 2026-04-09 20:00:00 / 1522915717 / 40 ; <GUID> / 2026-04-02 21:26:00 / 2026-04-09 20:43:00 / 2026-04-02 21:39:00 / 1522915717 / 40 |
| 4171, 4171\\|ZBO\\|1522963047\\|40 | 2 | <GUID> | <GUID> / 2026-04-08 16:08:00 / 2026-04-09 20:43:00 / 2026-04-09 20:00:00 / 1522963047 / 40 ; <GUID> / 2026-04-02 21:26:00 / 2026-04-09 20:43:00 / 2026-04-02 21:39:00 / 1522963047 / 40 |
| 4171, 4171\\|ZBO\\|1522963047\\|50 | 2 | <GUID> | <GUID> / 2026-04-08 16:08:00 / 2026-04-09 20:43:00 / 2026-04-09 20:00:00 / 1522963047 / 50 ; <GUID> / 2026-04-02 21:26:00 / 2026-04-09 20:43:00 / 2026-04-02 21:39:00 / 1522963047 / 50 |
| 4171, 4171\\|ZBO\\|1522993700\\|10 | 2 | <GUID> | <GUID> / 2026-04-08 16:07:00 / 2026-04-09 20:43:00 / 2026-04-09 20:00:00 / 1522993700 / 10 ; <GUID> / 2026-04-02 21:26:00 / 2026-04-09 20:43:00 / 2026-04-02 21:39:00 / 1522993700 / 10 |
| 4171, 4171\\|ZBO\\|1523026752\\|10 | 2 | <GUID> | <GUID> / 2026-04-08 16:07:00 / 2026-04-09 20:43:00 / 2026-04-09 20:00:00 / 1523026752 / 10 ; <GUID> / 2026-04-02 21:26:00 / 2026-04-09 20:43:00 / 2026-04-02 21:39:00 / 1523026752 / 10 |
| 4171, 4171\\|ZBO\\|1523026752\\|20 | 2 | <GUID> | <GUID> / 2026-04-08 16:07:00 / 2026-04-09 20:43:00 / 2026-04-09 20:00:00 / 1523026752 / 20 ; <GUID> / 2026-04-02 21:26:00 / 2026-04-09 20:43:00 / 2026-04-02 21:39:00 / 1523026752 / 20 |
| 4171, 4171\\|ZBO\\|1523026752\\|30 | 2 | <GUID> | <GUID> / 2026-04-08 16:07:00 / 2026-04-09 20:43:00 / 2026-04-09 20:00:00 / 1523026752 / 30 ; <GUID> / 2026-04-02 21:26:00 / 2026-04-09 20:43:00 / 2026-04-02 21:39:00 / 1523026752 / 30 |

## Latest Imports

| Branch | Family | Status | Source started | Row created | Seeded | Trigger | File |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 4171 | SP830CA | ready | 2026-03-20 12:33:00 | 2026-04-08 23:51:00 | True | Controlled workbook seed | SP830CA - Quote Follow Up Report.xlsx |
| 4171 | ZBO | ready | 2026-03-20 12:33:00 | 2026-04-08 23:51:00 | True | Controlled workbook seed | CA ZBO 20250320_30_4023207436626456977.xlsx |
| 4171 | SA1300 | ready | 2026-03-20 12:33:00 | 2026-04-08 23:51:00 | True | Controlled workbook seed | SA1300.xlsx |
| 4171 | SA1300-ABNORMALMARGIN | ready | 2026-04-09 01:20:00 | 2026-04-09 01:20:00 | False | 4171-Budget-Update-SA1300 | SA1300.xlsx |
| 4172 | SP830CA | ready | 2026-03-20 13:43:00 | 2026-04-08 23:51:00 | True | Controlled workbook seed | SP830CA - Quote Follow Up Report.xlsx |
| 4172 | ZBO | ready | 2026-03-20 13:43:00 | 2026-04-08 23:51:00 | True | Controlled workbook seed | CA SC ZBO - 20260120_226_6709604248778416599.xlsx |
| 4172 | SA1300 | ready | 2026-03-20 13:43:00 | 2026-04-08 23:51:00 | True | Controlled workbook seed | SA1300.xlsx |
| 4172 | SA1300-ABNORMALMARGIN | ready | 2026-04-09 01:20:00 | 2026-04-09 01:20:00 | False | 4172-Budget-Update-SA1300 | SA1300.xlsx |
| 4173 | SP830CA | ready | 2026-03-20 14:17:00 | 2026-04-08 23:51:00 | True | Controlled workbook seed | SP830CA - Quote Follow Up Report.xlsx |
| 4173 | ZBO | ready | 2026-03-20 12:34:00 | 2026-04-08 23:51:00 | True | Controlled workbook seed | CA SC ZBO - 20260120_209_5473802619978626103.xlsx |
| 4173 | SA1300 | ready | 2026-03-20 12:34:00 | 2026-04-08 23:51:00 | True | Controlled workbook seed | SA1300.xlsx |
| 4173 | SA1300-ABNORMALMARGIN | ready | 2026-04-09 01:19:00 | 2026-04-09 01:19:00 | False | 4173-Budget-Update-SA1300 | SA1300.xlsx |
