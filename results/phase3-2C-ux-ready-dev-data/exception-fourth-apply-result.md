# Phase 3 Resolver Dry-Run Results

- Checked UTC: 2026-04-27T22:22:00.9638106Z
- Environment: https://orga632edd5.crm3.dynamics.com
- Mode: Apply
- Branch filter: none
- Alerts sent: 0

## Counts

| Metric | Count |
| --- | ---: |
| quoteSourceRecordsScanned | 521 |
| quoteLineRecordsScanned | 1559 |
| quoteGroupsFound | 2 |
| quoteGroupsAtOrAboveThreshold | 2 |
| workItemsWouldBeCreated | 0 |
| workItemsWouldBeUpdated | 2 |
| workItemsCreated | 0 |
| workItemsUpdated | 2 |
| lowValueQuoteGroupsSkipped | 0 |
| tsrAliasesResolved | 0 |
| cssrAliasesResolved | 1 |
| tsrExceptions | 2 |
| cssrExceptions | 1 |
| missingBranchExceptions | 0 |
| missingPolicyExceptions | 0 |
| ambiguousAliasExceptions | 0 |
| assignmentExceptionsWouldBeCreated | 0 |
| assignmentExceptionsWouldBeUpdated | 3 |
| assignmentExceptionsCreated | 0 |
| assignmentExceptionsUpdated | 3 |
| alertsSent | 0 |

## Top Unresolved AM Numbers

| Value | Count |
| --- | ---: |
| 0 | 1 |
| BLANK | 1 |

## Top Unresolved CSSR Numbers

| Value | Count |
| --- | ---: |
| BLANK | 1 |

## Sanitized Sample Work Item Payloads

```json
[
    {
        "sampleId":  "2b5001d9291b",
        "sourceExternalKeyHash":  "2b5001d9291b",
        "sourceDocumentHash":  "f494573bd96c",
        "branchCode":  "4171",
        "workType":  "Quote",
        "sourceSystem":  "SP830CA",
        "totalValue":  3268.80,
        "requiredAttempts":  3,
        "completedAttemptsActionRollup":  null,
        "nextFollowUpOn":  "2026-04-28",
        "effectiveNextFollowUpOn":  "2026-04-28",
        "calculatedStatus":  "Open",
        "existingStatus":  "Open",
        "statusWillAutoUpdate":  true,
        "assignmentStatus":  "Unmapped",
        "tsrResolution":  "not-attempted",
        "cssrResolution":  "not-attempted",
        "existingWorkItem":  true,
        "preservation":  "Does not overwrite sticky note, sticky note timestamps, action history, last followed-up/action dates, or non-empty manual owners."
    },
    {
        "sampleId":  "b2fb80e21b2d",
        "sourceExternalKeyHash":  "b2fb80e21b2d",
        "sourceDocumentHash":  "a29007e1adbd",
        "branchCode":  "4171",
        "workType":  "Quote",
        "sourceSystem":  "SP830CA",
        "totalValue":  10469.00,
        "requiredAttempts":  3,
        "completedAttemptsActionRollup":  null,
        "nextFollowUpOn":  "2026-04-15",
        "effectiveNextFollowUpOn":  "2026-04-15",
        "calculatedStatus":  "Overdue",
        "existingStatus":  "Overdue",
        "statusWillAutoUpdate":  true,
        "assignmentStatus":  "Needs TSR Assignment",
        "tsrResolution":  "not-attempted",
        "cssrResolution":  "resolved",
        "existingWorkItem":  true,
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
        "existingException":  true
    },
    {
        "sampleId":  "bec55145770d",
        "sourceDocumentHash":  "f494573bd96c",
        "exceptionType":  "Blank Alias",
        "sourceField":  "qfu_cssr",
        "normalizedValue":  "BLANK",
        "existingException":  true
    },
    {
        "sampleId":  "d7ed980818da",
        "sourceDocumentHash":  "a29007e1adbd",
        "exceptionType":  "Zero Alias",
        "sourceField":  "qfu_tsr",
        "normalizedValue":  "0",
        "existingException":  true
    }
]
```

No customer names are included in this report. Source document values are represented as hashes in samples.
