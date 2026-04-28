# Revenue Follow-Up Phase 4 My Work UX Readiness

Phase 3.2C prepared enough real dev data states to design and build the next My Work and quote detail experience without fake rows.

## Ready Data States

The dev environment now has:

- 32 active high-value quote work items
- 30 assigned work items
- 4 open work items
- 4 due-today work items
- 24 overdue work items
- 1 work item needing TSR assignment
- 1 unmapped work item
- 3 open assignment exceptions
- 0 alert logs
- 0 sent alerts

## Admin Panel Readiness

These views are present and query-validated:

- Work Items
- Open Work Items
- Due Today Work Items
- Overdue Work Items
- Quotes >= $3K
- Needs TSR Assignment
- Needs CSSR Assignment
- Work Items with Sticky Notes
- Assignment Exceptions
- Open Assignment Exceptions

## Phase 4 UX Requirements

The future My Work page must expose:

- Due Today
- Overdue
- Quotes >= $3K
- Missing Attempts
- Roadblocks
- Assignment Status
- Sticky Note
- Last Followed Up On
- Completed Attempts / Required Attempts

## Google Stitch Note

Phase 4 will use Google Stitch for My Work and Quote Detail design guidance. Stitch output is design and prototype guidance only. The actual implementation target remains Power Apps model-driven app/custom pages backed by Dataverse.

No frontend code from Stitch was generated or committed in Phase 3.2C.

## Remaining Before Broad Rollout

- Review provisional staff, aliases, and branch memberships in the Admin Panel.
- Decide controlled apply scope for broader branch or regional testing.
- Build My Work only after Phase 4 design is approved.
- Build Manager Panel and GM Review in later phases.
- Keep alerts disabled until alert consent, recipients, and dedupe behavior are explicitly validated.
