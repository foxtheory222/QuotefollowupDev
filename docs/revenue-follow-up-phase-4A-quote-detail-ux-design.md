# Phase 4A Quote Detail UX Design

## Intent

The Quote Detail side panel should let a TSR or CSSR understand and act on a quote work item without navigating away from My Work.

## Layout

The panel should open from the right side of the My Work custom page.

Top summary:

- Source document / quote number
- Customer
- Total value
- Status
- Assignment status
- Attempts `0/3`, `1/3`, `2/3`, `3/3`
- Next follow-up
- Last followed up
- TSR
- CSSR
- Branch

## Sticky Note

The sticky note belongs near the top of the panel, directly under the summary.

Required elements:

- Sticky note preview or full text
- Edit button
- Last updated by/on
- Clear visual treatment
- Reminder that sticky note persists across imports

The sticky note is not the same as action history notes. Sticky note is the current always-visible memory for the work item. Action notes belong to individual follow-up actions.

## Actions

Quick actions:

- Log Call
- Log Email
- Customer Advised
- Set Next Follow-Up
- Roadblock
- Escalate
- Won
- Lost

High-frequency actions should be easiest to reach. Terminal actions should be available but visually less dominant than call/email/customer-advised.

## History

Action history should show:

- Action type
- Followed up on
- Action by
- Counts as attempt
- Outcome
- Notes
- Next follow-up

If there are no actions yet, show a compact empty history state.

## Source Section

Show enough source context for auditability:

- Linked quote
- Quote lines
- Source system
- Source external key
- Source document number

Do not expose unnecessary raw technical fields in the primary visible area. Keep source details collapsed or visually secondary.
