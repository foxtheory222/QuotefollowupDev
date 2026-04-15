# Operational Current-State Audit

- Generated: 2026-04-09 17:33:14
- Environment: https://regionaloperationshub.crm.dynamics.com
- Branches: 4171, 4172, 4173

## qfu_quote

- Table role: current-state
- Canonical key: qfu_sourceid (branch|SP830CA|quotenumber)
- Total rows: 71
- Unique source ids: 71
- Duplicate groups: 0
- Duplicate rows: 0
- Active rows: 30
- Inactive rows: 41
- Rows missing lifecycle fields: 0

## qfu_backorder

- Table role: current-state
- Canonical key: qfu_sourceid (branch|ZBO|salesdoc|line)
- Total rows: 1726
- Unique source ids: 1726
- Duplicate groups: 0
- Duplicate rows: 0
- Active rows: 1141
- Inactive rows: 585
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
- Total rows: 571
- Unique source ids: 513
- Duplicate groups: 58
- Duplicate rows: 116
- Active rows: 266
- Inactive rows: 305
- Rows missing lifecycle fields: 0

| Duplicate key | Count | Winner | Sample rows |
| --- | ---: | --- | --- |
| 4171, 4171\\|ZBO\\|1522978429\\|10 | 2 | 76ad8224-6533-f111-88b4-000d3a59294a | 76ad8224-6533-f111-88b4-000d3a59294a / 2026-04-08 16:08:00 / 2026-04-09 22:34:00 / 2026-04-09 22:31:00 / 1522978429 / 10 ; 1a24538a-da2e-f111-88b4-000d3a59294a / 2026-04-02 21:26:00 / 2026-04-09 20:43:00 / 2026-04-02 21:39:00 / 1522978429 / 10 |
| 4171, 4171\\|ZBO\\|1522915717\\|20 | 2 | 03ab8224-6533-f111-88b4-000d3a59294a | 03ab8224-6533-f111-88b4-000d3a59294a / 2026-04-08 16:08:00 / 2026-04-09 22:34:00 / 2026-04-09 22:31:00 / 1522915717 / 20 ; 481a9f90-da2e-f111-88b4-000d3a59294a / 2026-04-02 21:26:00 / 2026-04-09 20:43:00 / 2026-04-02 21:39:00 / 1522915717 / 20 |
| 4171, 4171\\|ZBO\\|1522915717\\|30 | 2 | 19ab8224-6533-f111-88b4-000d3a59294a | 19ab8224-6533-f111-88b4-000d3a59294a / 2026-04-08 16:08:00 / 2026-04-09 22:34:00 / 2026-04-09 22:31:00 / 1522915717 / 30 ; 491a9f90-da2e-f111-88b4-000d3a59294a / 2026-04-02 21:26:00 / 2026-04-09 20:43:00 / 2026-04-02 21:39:00 / 1522915717 / 30 |
| 4171, 4171\\|ZBO\\|1522915717\\|40 | 2 | d6ab8224-6533-f111-88b4-000d3a59294a | d6ab8224-6533-f111-88b4-000d3a59294a / 2026-04-08 16:08:00 / 2026-04-09 22:34:00 / 2026-04-09 22:31:00 / 1522915717 / 40 ; 4a1a9f90-da2e-f111-88b4-000d3a59294a / 2026-04-02 21:26:00 / 2026-04-09 20:43:00 / 2026-04-02 21:39:00 / 1522915717 / 40 |
| 4171, 4171\\|ZBO\\|1522963047\\|40 | 2 | 6ead8224-6533-f111-88b4-000d3a59294a | 6ead8224-6533-f111-88b4-000d3a59294a / 2026-04-08 16:08:00 / 2026-04-09 22:34:00 / 2026-04-09 22:31:00 / 1522963047 / 40 ; 4d1a9f90-da2e-f111-88b4-000d3a59294a / 2026-04-02 21:26:00 / 2026-04-09 20:43:00 / 2026-04-02 21:39:00 / 1522963047 / 40 |
| 4171, 4171\\|ZBO\\|1522963047\\|50 | 2 | 70ad8224-6533-f111-88b4-000d3a59294a | 70ad8224-6533-f111-88b4-000d3a59294a / 2026-04-08 16:08:00 / 2026-04-09 22:34:00 / 2026-04-09 22:31:00 / 1522963047 / 50 ; 4e1a9f90-da2e-f111-88b4-000d3a59294a / 2026-04-02 21:26:00 / 2026-04-09 20:43:00 / 2026-04-02 21:39:00 / 1522963047 / 50 |
| 4171, 4171\\|ZBO\\|1522993700\\|10 | 2 | 73d9170c-6533-f111-88b4-000d3a59294a | 73d9170c-6533-f111-88b4-000d3a59294a / 2026-04-08 16:07:00 / 2026-04-09 22:33:00 / 2026-04-09 22:31:00 / 1522993700 / 10 ; 188eaf96-da2e-f111-88b4-000d3a59294a / 2026-04-02 21:26:00 / 2026-04-09 20:43:00 / 2026-04-02 21:39:00 / 1522993700 / 10 |
| 4171, 4171\\|ZBO\\|1523026752\\|10 | 2 | 76d9170c-6533-f111-88b4-000d3a59294a | 76d9170c-6533-f111-88b4-000d3a59294a / 2026-04-08 16:07:00 / 2026-04-09 22:33:00 / 2026-04-09 22:31:00 / 1523026752 / 10 ; 198eaf96-da2e-f111-88b4-000d3a59294a / 2026-04-02 21:26:00 / 2026-04-09 20:43:00 / 2026-04-02 21:39:00 / 1523026752 / 10 |
| 4171, 4171\\|ZBO\\|1523026752\\|20 | 2 | 79d9170c-6533-f111-88b4-000d3a59294a | 79d9170c-6533-f111-88b4-000d3a59294a / 2026-04-08 16:07:00 / 2026-04-09 22:33:00 / 2026-04-09 22:31:00 / 1523026752 / 20 ; 1a8eaf96-da2e-f111-88b4-000d3a59294a / 2026-04-02 21:26:00 / 2026-04-09 20:43:00 / 2026-04-02 21:39:00 / 1523026752 / 20 |
| 4171, 4171\\|ZBO\\|1523026752\\|30 | 2 | 05451512-6533-f111-88b4-000d3a59294a | 05451512-6533-f111-88b4-000d3a59294a / 2026-04-08 16:07:00 / 2026-04-09 22:33:00 / 2026-04-09 22:31:00 / 1523026752 / 30 ; 86f2109d-da2e-f111-88b4-000d3a59294a / 2026-04-02 21:26:00 / 2026-04-09 20:43:00 / 2026-04-02 21:39:00 / 1523026752 / 30 |

## Latest Imports

| Branch | Family | Status | Source started | Row created | Seeded | Trigger | File |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 4171 | SP830CA | ready | 2026-04-09 16:29:00 | 2026-04-08 23:51:00 | False | Captured workbook replay | SP830CA - Quote Follow Up Report.xlsx |
| 4171 | ZBO | ready | 2026-04-09 16:29:00 | 2026-04-08 23:51:00 | False | Captured workbook replay | CA ZBO 20250320_719_2965954137580406575.xlsx |
| 4171 | SA1300 | ready | 2026-04-09 16:29:00 | 2026-04-08 23:51:00 | False | Captured workbook replay | SA1300.xlsx |
| 4171 | SA1300-ABNORMALMARGIN | ready | 2026-04-09 01:20:00 | 2026-04-09 01:20:00 | False | 4171-Budget-Update-SA1300 | SA1300.xlsx |
| 4172 | SP830CA | ready | 2026-04-09 16:29:00 | 2026-04-08 23:51:00 | False | Captured workbook replay | SP830CA - Quote Follow Up Report.xlsx |
| 4172 | ZBO | ready | 2026-04-09 16:29:00 | 2026-04-08 23:51:00 | False | Captured workbook replay | CA SC ZBO - 20260120_243_4269750294371077189.xlsx |
| 4172 | SA1300 | ready | 2026-04-09 16:29:00 | 2026-04-08 23:51:00 | False | Captured workbook replay | SA1300.xlsx |
| 4172 | SA1300-ABNORMALMARGIN | ready | 2026-04-09 01:20:00 | 2026-04-09 01:20:00 | False | 4172-Budget-Update-SA1300 | SA1300.xlsx |
| 4173 | SP830CA | ready | 2026-04-09 16:29:00 | 2026-04-08 23:51:00 | False | Captured workbook replay | SP830CA - Quote Follow Up Report.xlsx |
| 4173 | ZBO | ready | 2026-04-09 16:29:00 | 2026-04-08 23:51:00 | False | Captured workbook replay | CA SC ZBO - 20260120_30_5427988465983970409.xlsx |
| 4173 | SA1300 | ready | 2026-04-09 16:29:00 | 2026-04-08 23:51:00 | False | Captured workbook replay | SA1300.xlsx |
| 4173 | SA1300-ABNORMALMARGIN | ready | 2026-04-09 01:19:00 | 2026-04-09 01:19:00 | False | 4173-Budget-Update-SA1300 | SA1300.xlsx |
