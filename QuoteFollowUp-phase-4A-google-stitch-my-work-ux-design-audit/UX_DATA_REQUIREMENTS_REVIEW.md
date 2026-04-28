# Phase 4A UX Data Requirements

## Live Data Recheck

Latest Phase 4A recheck:

| Metric | Count |
| --- | ---: |
| Active work items | 32 |
| Open | 4 |
| Due Today | 4 |
| Overdue | 24 |
| Assigned | 30 |
| Needs TSR Assignment | 1 |
| Needs CSSR Assignment | 0 |
| Unmapped | 1 |
| Open assignment exceptions | 3 |
| Quotes >= $3K | 32 |
| Work Items with Sticky Notes | 0 |
| Recent work item actions | 0 |

The data is sufficient for UX design because it includes normal work, due-today work, overdue work, and assignment exception states.

## qfu_workitem Fields Needed

- Work Item Number
- Work Type
- Source System
- Branch
- Source Document Number
- Source External Key
- Source Quote
- Source Quote Line
- Customer Name
- Total Value
- Status
- Priority
- Assignment Status
- Required Attempts
- Completed Attempts
- Next Follow-Up On
- Last Followed Up On
- Last Action On
- Primary Owner Staff
- Support Owner Staff
- TSR Staff
- CSSR Staff
- Sticky Note
- Sticky Note Updated On
- Sticky Note Updated By

The required UX fields exist, but completed attempts and last followed-up values need action data and rollup automation before they are fully reliable.

## qfu_workitemaction Fields Needed

- Work Item
- Action Type
- Counts As Attempt
- Action By
- Action On
- Attempt Number
- Outcome
- Next Follow-Up On
- Notes

Current action count is 0, so history, completed attempts, and last-followed-up behavior must be built and tested in Phase 4B or a follow-up automation phase.

## qfu_staff Fields Needed

- Staff Name
- Primary Email
- Staff Number
- Dataverse User
- Active

Current limitation: active staff records are missing email and Dataverse systemuser links. Do not assume current-user filtering.

## qfu_assignmentexception Fields Needed

- Exception Type
- Branch
- Source System
- Source Field
- Raw Value
- Normalized Value
- Source Document Number
- Source External Key
- Source Quote
- Source Quote Line
- Work Item
- Status
- Notes

Assignment exception data is sufficient for design and manager-review planning, but Manager Panel is out of scope for Phase 4A.

## qfu_quote and qfu_quoteline Fields Needed

Quote detail should read linked quote and quote-line data for source context only. Work item remains the workflow/control layer.

## Phase 4B Filtering Recommendation

Use branch/team filtering plus a staff dropdown in the MVP. Switch to current-user filtering only after `qfu_staff` records are linked to Dataverse `systemuser` records.
