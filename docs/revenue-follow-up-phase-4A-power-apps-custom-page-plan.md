# Phase 4A Power Apps Custom Page Plan

## Recommended Approach

Build Phase 4B as a Power Apps custom page inside the existing Revenue Follow-Up Workbench model-driven app.

Why:

- The model-driven app remains the admin/data shell.
- A custom page gives a better daily work UX than plain Dataverse table views.
- Dataverse remains the source of truth.
- Quick actions can create `qfu_workitemaction` rows.
- Sticky notes can save directly to `qfu_workitem`.
- Branch/team filtering is a safe MVP fallback until `qfu_staff` links to `systemuser`.

## Custom Page Components

- My Work page
- KPI card strip
- Priority tabs
- Work item gallery/list
- Selected work item detail panel
- Log Follow-Up modal
- Sticky Note edit control
- Empty/loading/error/no-assignment states
- Mobile quick-review responsive variant

## Dataverse Tables

- `qfu_workitem`
- `qfu_workitemaction`
- `qfu_staff`
- `qfu_branchmembership`
- `qfu_assignmentexception`
- `qfu_quote`
- `qfu_quoteline`
- `qfu_policy`

## Filter Plan

Phase 4B MVP:

- branch/team filter
- staff dropdown filter
- status/priority tabs
- assignment issue lane

Later:

- current-user filtering after `qfu_staff._qfu_systemuser_value` is populated
- role-aware behavior after security roles are designed

## Pseudocode Notes

KPI counts:

- Due Today: active work items where status is Due Today
- Overdue: active work items where status is Overdue
- Quotes >= $3K: active work items where total value is at or above threshold
- Missing Attempts: completed attempts less than required attempts
- Roadblocks: status equals Roadblock
- Assignment Issues: assignment status is Needs TSR Assignment, Needs CSSR Assignment, or Unmapped

List filters:

- start from active `qfu_workitem`
- apply branch/team filter
- apply staff dropdown if selected
- apply selected tab
- sort Overdue first, then Due Today, then high value

Log follow-up save:

- create `qfu_workitemaction`
- set `qfu_actionon`
- set `qfu_countsasattempt`
- set `qfu_nextfollowupon` if provided
- do not send alerts

Sticky note save:

- patch `qfu_workitem.qfu_stickynote`
- patch `qfu_stickynoteupdatedon`
- patch `qfu_stickynoteupdatedby`

## Buildable Now

- My Work custom page shell
- branch/team filter
- staff dropdown filter
- status tabs
- work item list
- detail panel
- sticky note edit
- Log Follow-Up modal that creates action rows

## Must Wait

- current-user default filtering
- alert sending
- daily digest
- Manager Panel
- GM Review
- security-role enforcement
- action rollup automation, unless explicitly added in Phase 4B
