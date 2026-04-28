# Phase 3 Resolver Dry-Run Results

- Checked UTC: 2026-04-27T21:47:02.7310503Z
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
| tsrAliasesResolved | 58 |
| cssrAliasesResolved | 68 |
| tsrExceptions | 51 |
| cssrExceptions | 41 |
| missingBranchExceptions | 0 |
| missingPolicyExceptions | 0 |
| ambiguousAliasExceptions | 0 |
| assignmentExceptionsWouldBeCreated | 92 |
| assignmentExceptionsWouldBeUpdated | 0 |
| assignmentExceptionsCreated | 0 |
| assignmentExceptionsUpdated | 0 |
| alertsSent | 0 |

## Top Unresolved AM Numbers

| Value | Count |
| --- | ---: |
| BLANK | 41 |
| 0 | 10 |

## Top Unresolved CSSR Numbers

| Value | Count |
| --- | ---: |
| BLANK | 41 |

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
        "assignmentStatus":  "Assigned",
        "tsrResolution":  "resolved",
        "cssrResolution":  "resolved",
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
        "assignmentStatus":  "Assigned",
        "tsrResolution":  "resolved",
        "cssrResolution":  "resolved",
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
        "assignmentStatus":  "Assigned",
        "tsrResolution":  "resolved",
        "cssrResolution":  "resolved",
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
        "assignmentStatus":  "Assigned",
        "tsrResolution":  "resolved",
        "cssrResolution":  "resolved",
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
        "assignmentStatus":  "Assigned",
        "tsrResolution":  "resolved",
        "cssrResolution":  "resolved",
        "existingWorkItem":  false,
        "preservation":  "Does not overwrite sticky note, sticky note timestamps, action history, last followed-up/action dates, or non-empty manual owners."
    }
]
```

## Sanitized Sample Assignment Exception Payloads

```json
[
    {
        "sampleId":  "6ec3e725675d",
        "sourceDocumentHash":  "f494573bd96c",
        "exceptionType":  "Blank Alias",
        "sourceField":  "qfu_tsr",
        "normalizedValue":  "BLANK",
        "existingException":  false
    },
    {
        "sampleId":  "bec55145770d",
        "sourceDocumentHash":  "f494573bd96c",
        "exceptionType":  "Blank Alias",
        "sourceField":  "qfu_cssr",
        "normalizedValue":  "BLANK",
        "existingException":  false
    },
    {
        "sampleId":  "084fbbc54ced",
        "sourceDocumentHash":  "d9e02a390c0f",
        "exceptionType":  "Blank Alias",
        "sourceField":  "qfu_tsr",
        "normalizedValue":  "BLANK",
        "existingException":  false
    },
    {
        "sampleId":  "7d5d7f160135",
        "sourceDocumentHash":  "d9e02a390c0f",
        "exceptionType":  "Blank Alias",
        "sourceField":  "qfu_cssr",
        "normalizedValue":  "BLANK",
        "existingException":  false
    },
    {
        "sampleId":  "9ba570e160e7",
        "sourceDocumentHash":  "b3101bad154c",
        "exceptionType":  "Blank Alias",
        "sourceField":  "qfu_tsr",
        "normalizedValue":  "BLANK",
        "existingException":  false
    }
]
```

No customer names are included in this report. Source document values are represented as hashes in samples.
