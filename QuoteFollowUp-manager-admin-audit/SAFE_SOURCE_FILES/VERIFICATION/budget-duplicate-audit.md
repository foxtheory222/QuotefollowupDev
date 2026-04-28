# Budget Duplicate Audit

- Probe: C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\results\portal-runtime-data-probe-20260409.json
- As of: 2026-04-09
- Current fiscal year: FY26
- Current month: 4
- Budget groups with duplicates: 3
- Archive groups with duplicates: 3

## Notes

- Raw qfu_isactive = false is treated as active.
- Current portal probe evidence shows formatted Yes on rows where raw qfu_isactive = false.

## Current Month Budget Groups

| Branch | FY | Month | Candidates | Active Candidates | Winner | Winner Reason |
| --- | --- | ---: | ---: | ---: | --- | --- |
| 4171 | FY26 | 4 | 1 | 1 | <GUID> | active, latest=2026-04-08T20:14:34 |
| 4172 | FY26 | 4 | 1 | 1 | <GUID> | active, latest=2026-04-08T20:14:34 |
| 4173 | FY26 | 4 | 1 | 1 | <GUID> | active, latest=2026-04-08T20:14:34 |

## Budget Duplicate Groups

### 4171 | FY26 | Month 3

| Budget Id | Source Id | Active | Formatted Label | Last Updated | Actual Sales | Goal | Reason |
| --- | --- | --- | --- | --- | ---: | ---: | --- |
| <GUID> |  | True | Yes | 2026-03-30T18:00:00 | 563797.99 | 901760 | active, latest=2026-03-30T18:00:00 |
| <GUID> |  | False | No | 2026-03-30T18:00:00 | 563797.99 | 901760 | latest=2026-03-30T18:00:00 |

### 4172 | FY26 | Month 3

| Budget Id | Source Id | Active | Formatted Label | Last Updated | Actual Sales | Goal | Reason |
| --- | --- | --- | --- | --- | ---: | ---: | --- |
| <GUID> |  | True | Yes | 2026-03-30T18:00:00 | 299348.09 | 552410 | active, latest=2026-03-30T18:00:00 |
| <GUID> |  | False | No | 2026-03-30T18:00:00 | 299348.09 | 552410 | latest=2026-03-30T18:00:00 |

### 4173 | FY26 | Month 3

| Budget Id | Source Id | Active | Formatted Label | Last Updated | Actual Sales | Goal | Reason |
| --- | --- | --- | --- | --- | ---: | ---: | --- |
| <GUID> |  | True | Yes | 2026-03-30T18:00:00 | 152727.5 | 445070 | active, latest=2026-03-30T18:00:00 |
| <GUID> |  | False | No | 2026-03-30T18:00:00 | 152727.5 | 445070 | latest=2026-03-30T18:00:00 |

## Current Month Archive Groups

| Branch | FY | Month | Candidates | Winner | Winner Reason |
| --- | --- | ---: | ---: | --- | --- |
| 4171 | FY26 | 4 | 1 | <GUID> | canonical-sourceid, has-goal, latest=2026-04-08T20:14:35 |
| 4172 | FY26 | 4 | 1 | <GUID> | canonical-sourceid, has-goal, latest=2026-04-08T20:14:35 |
| 4173 | FY26 | 4 | 1 | <GUID> | canonical-sourceid, has-goal, latest=2026-04-08T20:14:36 |

## Archive Duplicate Groups

### 4171 | FY26 | Month 3

| Archive Id | Source Id | Last Updated | Goal | Actual | Reason |
| --- | --- | --- | ---: | ---: | --- |
| <GUID> | 4171|budgettarget|2026-03 | 2026-04-08T18:10:41 | 901760 |  | has-goal, latest=2026-04-08T18:10:41 |
| <GUID> | 4171|budgettarget|2026-03 | 2026-04-08T17:51:07 | 901760 |  | has-goal, latest=2026-04-08T17:51:07 |
| <GUID> | 4171|budgettarget|2026-03 | 2026-04-08T17:51:05 | 901760 |  | has-goal, latest=2026-04-08T17:51:05 |

### 4172 | FY26 | Month 3

| Archive Id | Source Id | Last Updated | Goal | Actual | Reason |
| --- | --- | --- | ---: | ---: | --- |
| <GUID> | 4172|budgettarget|2026-03 | 2026-04-08T18:11:07 | 552410 |  | has-goal, latest=2026-04-08T18:11:07 |
| <GUID> | 4172|budgettarget|2026-03 | 2026-04-08T17:51:07 | 552410 |  | has-goal, latest=2026-04-08T17:51:07 |
| <GUID> | 4172|budgettarget|2026-03 | 2026-04-08T17:51:05 | 552410 |  | has-goal, latest=2026-04-08T17:51:05 |

### 4173 | FY26 | Month 3

| Archive Id | Source Id | Last Updated | Goal | Actual | Reason |
| --- | --- | --- | ---: | ---: | --- |
| <GUID> | 4173|budgettarget|2026-03 | 2026-04-08T18:11:28 | 445070 |  | has-goal, latest=2026-04-08T18:11:28 |
| <GUID> | 4173|budgettarget|2026-03 | 2026-04-08T17:51:07 | 445070 |  | has-goal, latest=2026-04-08T17:51:07 |
| <GUID> | 4173|budgettarget|2026-03 | 2026-04-08T17:51:06 | 445070 |  | has-goal, latest=2026-04-08T17:51:06 |
