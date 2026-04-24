# Revenue Follow-Up Design System

Date: 2026-04-24

## Phase Boundary

Current phase: Phase 1.2 - follow-up date, sticky notes, and Google Stitch UI prompt standard before live Dataverse table creation.

Functional after this phase:

- A shared UI direction exists for future Google Stitch design prompts and Power Apps custom page work.
- The design system documents the operations-focused style expected for My Work, Quote Detail, Manager Panel, Admin Panel, and GM Review.

Not functional yet:

- No live Dataverse tables have been created.
- No model-driven Power App has been created or published.
- No Power Apps custom pages have been created.
- No Google Stitch prototype has been generated.

What comes next:

- Use this design system when writing Google Stitch prompts.
- Use Stitch output only to align UI direction before building Power Apps model-driven forms/views or custom pages.

Still left:

- Final Power Apps form/view creation.
- Custom page scope confirmation for My Work and Quote Detail.
- Accessibility review against the built Power Apps implementation.

Questions that must not be guessed:

- Exact custom page scope for My Work versus model-driven views/forms first.
- Branch/security visibility behavior.
- Alert/CC behavior and first follow-up due-date behavior.

## Product

Product name:

```text
Revenue Follow-Up Workbench
```

Primary users:

- TSR
- CSSR
- Manager
- GM
- Admin

Core objects:

- work item
- quote
- quote line
- backorder
- staff alias
- branch membership
- policy
- assignment exception

## Design Principles

- Operations-first, not marketing-first.
- Fast scanning over decorative layout.
- Desktop-optimized for branch staff, but mobile-friendly enough for quick review.
- Low clicks for common actions.
- Visible next action on every work item.
- Sticky note and Last Followed Up On must be immediately visible on work item detail.
- Attempts should read clearly as `0/3`, `1/3`, `2/3`, or `3/3`.
- Avoid dashboard clutter and decorative cards that hide work.
- Use accessible contrast, readable spacing, predictable navigation, and dense but organized tables/lists.

## Visual Direction

Use a clean internal operations style:

- neutral page background
- white or near-white content surfaces
- restrained borders
- compact toolbar controls
- clear status chips for Due Today, Overdue, Roadblock, Escalated, and Completed
- table/list layout for work queues
- side panel or split detail for quote work item review
- sticky note callout near the top of detail views

Avoid:

- marketing hero layouts
- ornamental gradients
- oversized cards
- hardcoded people, branches, emails, or IDs in examples
- fake production data unless clearly marked as sample

## Important Fields In UI

Work item list/detail should expose:

- Work Item Number
- Work Type
- Source System
- Source Document Number
- Customer Name
- Total Value
- Primary Owner
- Support Owner
- Status
- Priority
- Required Attempts
- Completed Attempts
- Last Followed Up On
- Last Action On
- Next Follow-Up On
- Sticky Note
- Assignment Status

Work item action history should expose:

- Action Type
- Followed Up On / Action On
- Action By
- Counts As Attempt
- Notes / Follow-Up Notes
- Next Follow-Up On

## Power Apps Target

The production implementation target remains:

```text
Power Apps model-driven app / custom pages
        -> Dataverse tables
        -> Power Automate flows
```

Google Stitch is used only to align design direction and UI layout before Power Apps build work begins.
