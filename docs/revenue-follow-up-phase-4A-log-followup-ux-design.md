# Phase 4A Log Follow-Up UX Design

## Intent

The Log Follow-Up modal should let TSRs and CSSRs record a follow-up quickly without leaving My Work.

## Fields

- Action Type
- Followed Up On
- Counts As Attempt
- Outcome
- Follow-Up Notes
- Next Follow-Up On

## Defaults

| Action Type | Counts As Attempt Default |
| --- | --- |
| Call | Yes |
| Email | Yes |
| Customer Advised | Yes |
| Note | No |
| Roadblock | No |
| Escalated | No |
| Due Date Updated | No |
| Won | No |
| Lost | No |
| Cancelled | No |
| Sticky Note Updated | No |

## Validation

- If Counts As Attempt is Yes, Followed Up On is required.
- If Action Type is Roadblock, Follow-Up Notes are required.
- If closing quote, status should become terminal.
- If Next Follow-Up On is before Followed Up On, show a warning.

## Save Behavior

Save creates a `qfu_workitemaction` row.

The action row should include:

- `qfu_workitem`
- `qfu_actiontype`
- `qfu_countsasattempt`
- `qfu_actionby`
- `qfu_actionon`
- `qfu_outcome`
- `qfu_nextfollowupon`
- `qfu_notes`

Completed attempts and last followed-up values should be updated by a later rollup flow or server-side automation. That rollup is not live in Phase 4A.
