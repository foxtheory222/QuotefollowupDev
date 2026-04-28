# Phase 4A My Work UX Design

## Recommendation

Build My Work as a Power Apps custom page inside the Revenue Follow-Up Workbench model-driven app. A plain model-driven table view is not sufficient for daily TSR/CSSR follow-up work because the experience needs KPI triage, status lanes, sticky notes, quick actions, and a detail panel in one low-click workspace.

## Header

- Title: My Work
- Date
- Branch/team context
- Refresh timestamp
- Role context
- Compact freshness text
- Branch/team filter
- Staff filter/dropdown fallback

Current-user filtering should wait until `qfu_staff` records are linked to Dataverse `systemuser` records. The Phase 4B MVP should default to branch/team filtered work with an explicit staff dropdown.

## KPI Cards

Use six compact KPI cards:

| Card | Purpose |
| --- | --- |
| Due Today | Work that must be touched today |
| Overdue | Work already late |
| Quotes >= $3K | High-value work item universe |
| Missing Attempts | Items below required attempts |
| Roadblocks | Work needing escalation or intervention |
| Assignment Issues | Unmapped or missing-owner work |

## Priority Tabs

Recommended tabs:

- Overdue
- Due Today
- High Value
- Needs Attempts
- Waiting
- Roadblocks
- All Open

Assignment issues should be visible but not mixed into normal follow-up work by default.

## Main Work List

Recommended columns:

- Priority
- Status
- Quote / Source Document
- Customer
- Value
- Attempts
- Next Follow-Up
- Last Followed Up
- TSR
- CSSR
- Sticky Note Preview
- Next Action

Overdue rows need a strong red treatment. Due Today rows need amber treatment. Attempts should render as simple `0/3`, `1/3`, `2/3`, `3/3` chips or progress markers.

## Detail Panel

Selecting a row opens a right-side panel without leaving the page. The panel should show quote summary, assignment summary, sticky note, action buttons, action history, and source references.

## Quick Action Bar

Buttons:

- Log Call
- Log Email
- Customer Advised
- Set Next Follow-Up
- Sticky Note
- Roadblock
- Escalate
- Won
- Lost

These actions should create or update Dataverse rows only in Phase 4B implementation, not in Phase 4A.

## Sticky Note Behavior

- Always visible near the top of the detail panel.
- Edit without leaving the page.
- Save to `qfu_workitem.qfu_stickynote`.
- Update `qfu_stickynoteupdatedon`.
- Update `qfu_stickynoteupdatedby`.
- Never overwritten by imports.
- Visually distinct from action history notes.

## Follow-Up Logging Behavior

Saving the Log Follow-Up modal should create a `qfu_workitemaction` row with:

- action type
- Followed Up On
- Counts As Attempt
- Follow-Up Notes
- Next Follow-Up On
- Outcome

Attempt actions should update completed attempts later through a rollup flow or server-side automation. Do not claim that rollup is live yet.

## States

Include these states:

- Empty: no due or overdue work
- Loading: skeleton KPI and list rows
- Error: cannot load work items, retry action
- No assignment: current user is not linked to staff, show branch/team and staff dropdown fallback
- Mobile quick review: compact Overdue, Due Today, and High Value list
