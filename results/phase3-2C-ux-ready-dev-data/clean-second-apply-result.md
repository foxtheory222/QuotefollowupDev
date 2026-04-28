# Phase 3 Resolver Dry-Run Results

- Checked UTC: 2026-04-27T22:16:09.4384388Z
- Environment: https://orga632edd5.crm3.dynamics.com
- Mode: Apply
- Branch filter: none
- Alerts sent: 0

## Counts

| Metric | Count |
| --- | ---: |
| quoteSourceRecordsScanned | 521 |
| quoteLineRecordsScanned | 1559 |
| quoteGroupsFound | 30 |
| quoteGroupsAtOrAboveThreshold | 30 |
| workItemsWouldBeCreated | 0 |
| workItemsWouldBeUpdated | 30 |
| workItemsCreated | 0 |
| workItemsUpdated | 30 |
| lowValueQuoteGroupsSkipped | 0 |
| tsrAliasesResolved | 30 |
| cssrAliasesResolved | 30 |
| tsrExceptions | 0 |
| cssrExceptions | 0 |
| missingBranchExceptions | 0 |
| missingPolicyExceptions | 0 |
| ambiguousAliasExceptions | 0 |
| assignmentExceptionsWouldBeCreated | 0 |
| assignmentExceptionsWouldBeUpdated | 0 |
| assignmentExceptionsCreated | 0 |
| assignmentExceptionsUpdated | 0 |
| alertsSent | 0 |

## Top Unresolved AM Numbers

| Value | Count |
| --- | ---: |

## Top Unresolved CSSR Numbers

| Value | Count |
| --- | ---: |

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
        "effectiveNextFollowUpOn":  "2026-04-03",
        "calculatedStatus":  "Overdue",
        "existingStatus":  "Overdue",
        "statusWillAutoUpdate":  true,
        "assignmentStatus":  "Assigned",
        "tsrResolution":  "resolved",
        "cssrResolution":  "resolved",
        "existingWorkItem":  true,
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
        "effectiveNextFollowUpOn":  "2026-04-03",
        "calculatedStatus":  "Overdue",
        "existingStatus":  "Overdue",
        "statusWillAutoUpdate":  true,
        "assignmentStatus":  "Assigned",
        "tsrResolution":  "resolved",
        "cssrResolution":  "resolved",
        "existingWorkItem":  true,
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
        "effectiveNextFollowUpOn":  "2026-04-03",
        "calculatedStatus":  "Overdue",
        "existingStatus":  "Overdue",
        "statusWillAutoUpdate":  true,
        "assignmentStatus":  "Assigned",
        "tsrResolution":  "resolved",
        "cssrResolution":  "resolved",
        "existingWorkItem":  true,
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
        "effectiveNextFollowUpOn":  "2026-04-03",
        "calculatedStatus":  "Overdue",
        "existingStatus":  "Overdue",
        "statusWillAutoUpdate":  true,
        "assignmentStatus":  "Assigned",
        "tsrResolution":  "resolved",
        "cssrResolution":  "resolved",
        "existingWorkItem":  true,
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
        "effectiveNextFollowUpOn":  "2026-04-14",
        "calculatedStatus":  "Overdue",
        "existingStatus":  "Overdue",
        "statusWillAutoUpdate":  true,
        "assignmentStatus":  "Assigned",
        "tsrResolution":  "resolved",
        "cssrResolution":  "resolved",
        "existingWorkItem":  true,
        "preservation":  "Does not overwrite sticky note, sticky note timestamps, action history, last followed-up/action dates, or non-empty manual owners."
    }
]
```

## Sanitized Sample Assignment Exception Payloads

```json

```

No customer names are included in this report. Source document values are represented as hashes in samples.
