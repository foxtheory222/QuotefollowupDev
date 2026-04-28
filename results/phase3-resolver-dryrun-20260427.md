# Phase 3 Resolver Dry-Run Results

- Checked UTC: 2026-04-27T19:39:57.8414235Z
- Environment: https://orga632edd5.crm3.dynamics.com
- Mode: DryRun
- Branch filter: none
- Alerts sent: 0

## Counts

| Metric | Count |
| --- | ---: |
| quoteSourceRecordsScanned | 521 |
| quoteLineRecordsScanned | 1559 |
| quoteGroupsFound | 521 |
| quoteGroupsAtOrAboveThreshold | 109 |
| workItemsWouldBeCreated | 109 |
| workItemsWouldBeUpdated | 0 |
| workItemsCreated | 0 |
| workItemsUpdated | 0 |
| lowValueQuoteGroupsSkipped | 412 |
| tsrAliasesResolved | 0 |
| cssrAliasesResolved | 0 |
| tsrExceptions | 109 |
| cssrExceptions | 109 |
| missingBranchExceptions | 0 |
| missingPolicyExceptions | 0 |
| ambiguousAliasExceptions | 0 |
| assignmentExceptionsWouldBeCreated | 218 |
| assignmentExceptionsWouldBeUpdated | 0 |
| assignmentExceptionsCreated | 0 |
| assignmentExceptionsUpdated | 0 |
| alertsSent | 0 |

## Top Unresolved AM Numbers

| Value | Count |
| --- | ---: |
| BLANK | 41 |
| 7001634 | 18 |
| 7003604 | 16 |
| 7003309 | 13 |
| 0 | 10 |
| 7003448 | 8 |
| 7000807 | 2 |
| 7003381 | 1 |

## Top Unresolved CSSR Numbers

| Value | Count |
| --- | ---: |
| BLANK | 41 |
| 7003771 | 20 |
| 7003604 | 10 |
| 7003309 | 7 |
| 7002464 | 7 |
| 7004134 | 6 |
| 7002470 | 5 |
| 7003740 | 5 |
| 7003201 | 3 |
| 7003593 | 2 |

## Sanitized Sample Work Item Payloads

```json
[
    {
        "sampleId":  "c8cda2c22098",
        "sourceExternalKeyHash":  "c8cda2c22098",
        "sourceDocumentHash":  "b767302230d6",
        "branchCode":  "4171",
        "workType":  "Quote",
        "sourceSystem":  "SP830CA",
        "totalValue":  5189.05,
        "requiredAttempts":  3,
        "completedAttemptsActionRollup":  null,
        "nextFollowUpOn":  "2026-04-03",
        "assignmentStatus":  "Unmapped",
        "tsrResolution":  "unmapped",
        "cssrResolution":  "unmapped",
        "existingWorkItem":  false,
        "preservation":  "Does not overwrite sticky note, sticky note timestamps, action history, last followed-up/action dates, or non-empty manual owners."
    },
    {
        "sampleId":  "0dd6567c4d9f",
        "sourceExternalKeyHash":  "0dd6567c4d9f",
        "sourceDocumentHash":  "e9058bbc532f",
        "branchCode":  "4171",
        "workType":  "Quote",
        "sourceSystem":  "SP830CA",
        "totalValue":  3070.57,
        "requiredAttempts":  3,
        "completedAttemptsActionRollup":  null,
        "nextFollowUpOn":  "2026-04-03",
        "assignmentStatus":  "Unmapped",
        "tsrResolution":  "unmapped",
        "cssrResolution":  "unmapped",
        "existingWorkItem":  false,
        "preservation":  "Does not overwrite sticky note, sticky note timestamps, action history, last followed-up/action dates, or non-empty manual owners."
    },
    {
        "sampleId":  "33e17d55c46f",
        "sourceExternalKeyHash":  "33e17d55c46f",
        "sourceDocumentHash":  "edadd345e835",
        "branchCode":  "4171",
        "workType":  "Quote",
        "sourceSystem":  "SP830CA",
        "totalValue":  4178.86,
        "requiredAttempts":  3,
        "completedAttemptsActionRollup":  null,
        "nextFollowUpOn":  "2026-04-03",
        "assignmentStatus":  "Unmapped",
        "tsrResolution":  "unmapped",
        "cssrResolution":  "unmapped",
        "existingWorkItem":  false,
        "preservation":  "Does not overwrite sticky note, sticky note timestamps, action history, last followed-up/action dates, or non-empty manual owners."
    },
    {
        "sampleId":  "700ab127c1e9",
        "sourceExternalKeyHash":  "700ab127c1e9",
        "sourceDocumentHash":  "6d008de868d1",
        "branchCode":  "4171",
        "workType":  "Quote",
        "sourceSystem":  "SP830CA",
        "totalValue":  9568.57,
        "requiredAttempts":  3,
        "completedAttemptsActionRollup":  null,
        "nextFollowUpOn":  "2026-04-03",
        "assignmentStatus":  "Unmapped",
        "tsrResolution":  "unmapped",
        "cssrResolution":  "unmapped",
        "existingWorkItem":  false,
        "preservation":  "Does not overwrite sticky note, sticky note timestamps, action history, last followed-up/action dates, or non-empty manual owners."
    },
    {
        "sampleId":  "1c1138ac5bfd",
        "sourceExternalKeyHash":  "1c1138ac5bfd",
        "sourceDocumentHash":  "8129df9c3d07",
        "branchCode":  "4171",
        "workType":  "Quote",
        "sourceSystem":  "SP830CA",
        "totalValue":  9968.58,
        "requiredAttempts":  3,
        "completedAttemptsActionRollup":  null,
        "nextFollowUpOn":  "2026-04-14",
        "assignmentStatus":  "Unmapped",
        "tsrResolution":  "unmapped",
        "cssrResolution":  "unmapped",
        "existingWorkItem":  false,
        "preservation":  "Does not overwrite sticky note, sticky note timestamps, action history, last followed-up/action dates, or non-empty manual owners."
    }
]
```

## Sanitized Sample Assignment Exception Payloads

```json
[
    {
        "sampleId":  "fcd165b2b9ba",
        "sourceDocumentHash":  "b767302230d6",
        "exceptionType":  "Missing TSR Alias",
        "sourceField":  "qfu_tsr",
        "normalizedValue":  "7003309",
        "existingException":  false
    },
    {
        "sampleId":  "55e30cc62dc4",
        "sourceDocumentHash":  "b767302230d6",
        "exceptionType":  "Missing CSSR Alias",
        "sourceField":  "qfu_cssr",
        "normalizedValue":  "7002464",
        "existingException":  false
    },
    {
        "sampleId":  "85f455efc457",
        "sourceDocumentHash":  "e9058bbc532f",
        "exceptionType":  "Missing TSR Alias",
        "sourceField":  "qfu_tsr",
        "normalizedValue":  "7003309",
        "existingException":  false
    },
    {
        "sampleId":  "6fc787247f41",
        "sourceDocumentHash":  "e9058bbc532f",
        "exceptionType":  "Missing CSSR Alias",
        "sourceField":  "qfu_cssr",
        "normalizedValue":  "7003771",
        "existingException":  false
    },
    {
        "sampleId":  "1ff123fbec29",
        "sourceDocumentHash":  "edadd345e835",
        "exceptionType":  "Missing TSR Alias",
        "sourceField":  "qfu_tsr",
        "normalizedValue":  "7001634",
        "existingException":  false
    }
]
```

No customer names are included in this report. Source document values are represented as hashes in samples.
