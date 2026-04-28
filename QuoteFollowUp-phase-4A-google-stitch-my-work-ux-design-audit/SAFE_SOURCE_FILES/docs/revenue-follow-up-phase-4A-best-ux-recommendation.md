# Phase 4A Best UX Recommendation

## Recommended Phase 4B Build Path

Build My Work as a Power Apps custom page, not as a plain model-driven table view.

The best UX is:

- My Work custom page inside Revenue Follow-Up Workbench
- branch/team filter first
- staff dropdown filter as MVP fallback
- KPI cards for daily triage
- priority tabs for work modes
- dense work item list
- right-side Quote Detail panel
- Log Follow-Up modal
- inline sticky note edit
- assignment issues visible but separate from normal daily work

## Why This Path

TSRs and CSSRs need to answer these questions immediately:

- What do I need to work today?
- What is overdue?
- Which quotes are high value?
- Which quotes still need attempts?
- What is the next best action?
- What has already been done?
- What sticky note needs to stay with this quote?

A model-driven view can show rows, but it cannot provide this daily work rhythm without too many clicks.

## Defer

- Current-user filtering until staff/systemuser mapping exists.
- Manager Panel until the staff work UX works.
- GM Review until Manager Panel exists.
- Alerts until follow-up logging and dedupe behavior are proven.
- Broad resolver apply until the MVP UX is verified against the controlled dev data.

## Keep Simple

Use the fewest concepts possible:

- Due Today
- Overdue
- High Value
- Missing Attempts
- Assignment Issues
- Sticky Note
- Follow-Up Action

Do not add alert complexity, manager review, or security assumptions to Phase 4B.
