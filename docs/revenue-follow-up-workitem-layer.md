# Revenue Follow-Up Work Item Layer

Date: 2026-04-24

## Phase Boundary

Current phase: Phase 1.2 - follow-up date, sticky notes, and Google Stitch UI prompt standard before live Dataverse table creation.

Functional after this phase:

- `qfu_workitem` is defined as the workflow/control layer.
- Quote work item grain, idempotency, source references, assignment status, attempts, and lifecycle rules are documented.
- The imported operational tables remain the source of truth.
- Source system and action attempt counting are hardened before live table creation.
- Actual follow-up timestamps, last-followed-up rollup, and persistent sticky notes are documented before live table creation.

Not functional yet:

- No live `qfu_workitem` records are created by this doc.
- No user action buttons, custom pages, or live work queues are active.
- No backorder work item generation is enabled.
- No live attempt counting or escalation flow is active.
- No live Dataverse tables, model-driven app, resolver flow, or alert flow has been created.
- No custom pages or Google Stitch prototypes have been created.

What comes next:

- Create the work item and action tables.
- Add model-driven views/forms for Work Items and Work Item Actions.
- Build quote work item generation after staff alias and policy tables exist.

Still left:

- Live table creation, action UX, resolver integration, manager reassignment behavior, My Work custom page, and alert/escalation integration.

Questions that must not be guessed:

- Backorder work item grain.
- First follow-up due-date rule.
- When source closure should close or cancel open work items.

## Purpose

`qfu_workitem` is the workflow/control layer for follow-up work. It is not a replacement for imported operational tables.

The existing source tables keep their role:

| Table | Role |
| --- | --- |
| `qfu_quote` | Current-state imported quote header/source state |
| `qfu_quoteline` | Imported quote line details and quote total calculation source |
| `qfu_backorder` | Current-state imported backorder/source state |
| `qfu_freightworkitem` | Freight current-state workflow source, where present |
| `qfu_deliverynotpgi` | Delivery readiness source, where present |

## Work Item Contract

A work item stores:

- work type
- source system
- branch
- source document number
- stable source external key
- source record lookups
- total value used for prioritization
- owner staff lookups
- assignment status
- due/follow-up dates
- required and completed attempts
- latest actual follow-up date/time
- persistent sticky note and sticky note audit fields
- status, priority, and escalation state
- policy used to generate the work item

It should not duplicate every source field. Denormalized display fields such as customer name and total value are acceptable for list performance and filtering, but the source record remains the audit path.

## Quote Work Item Grain

For SP830CA high-value quote follow-up:

```text
work item grain = branch + quote number
```

Quote total is:

```text
sum of Value for all active/current quote lines with the same branch + quote number
```

The work item key should be stable:

```text
qfu_worktype = Quote
qfu_sourcesystem = SP830CA
qfu_sourceexternalkey = branch|SP830CA|quote|<quote-number>
```

The work item should reference:

- `qfu_sourcequote` when a header/current-state quote row exists.
- `qfu_sourcequoteline` only as a representative line if needed for navigation.
- Quote line detail views should still query `qfu_quoteline` by branch and quote number.

## Backorder Work Item Grain

Backorder work item grain is not locked for Phase 1.

Candidate options:

- sales document header
- sales document + line
- customer + material group
- high-value customer backlog group

Until this is decided, Phase 1 should only design the backorder fields and avoid enabling automatic backorder work item generation.

## Lifecycle

Recommended work item lifecycle:

```text
Open
Due Today
Overdue
Waiting on Customer
Waiting on Vendor
Roadblock
Escalated
Completed
Closed Won
Closed Lost
Cancelled
```

Lifecycle rules:

- Re-importing the same source record updates the existing work item by alternate key.
- Work item owner/status/action state is not overwritten by source import unless the policy explicitly says to reset it.
- Import/re-import must not overwrite sticky notes, completed attempts, last followed-up date, status, next follow-up date, or owner fields unless a controlled reset/reassignment process is explicitly run.
- Disappearing source rows should not automatically delete work items.
- Source closure/cancellation should move work item to a terminal status only when the source state proves it.
- All user follow-up actions write `qfu_workitemaction` rows.

## Assignment Status

Recommended assignment status behavior:

| Status | Meaning |
| --- | --- |
| Assigned | TSR and required support ownership resolved |
| Partially Assigned | Primary owner exists but support owner is missing |
| Needs TSR Assignment | TSR alias is blank, zero, unmapped, or ambiguous |
| Needs CSSR Assignment | CSSR alias is blank, zero, unmapped, or ambiguous |
| Unmapped | Neither owner can be resolved |
| Error | Resolver/policy failed unexpectedly |

Missing TSR should go to the manager exception queue. Do not silently assign TSR ownership to CSSR.

## Attempts

For high-value quotes:

- Required attempts come from `qfu_policy.qfu_requiredattempts`.
- Completed attempts should be calculated from related `qfu_workitemaction` rows where `qfu_countsasattempt = Yes`, or maintained by an idempotent flow using that same rule.
- Do not hardcode attempt counting from action type names alone.
- `qfu_lastfollowedupon` should be the max `qfu_actionon` across related actions where `qfu_countsasattempt = Yes`.
- `qfu_lastactionon` should be the max `qfu_actionon` across all related actions.
- `qfu_lastfollowedupon` is different from `qfu_lastactionon`; admin edits, roadblocks, escalations, assignments, notes, and sticky note updates may update last action without counting as follow-up attempts.

MVP action defaults:

| Action Type | Default Counts As Attempt |
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
| Assignment/Reassignment | No |
| Sticky Note Updated | No |

Admins can change these defaults later through policy or configuration if needed, but the MVP should use this default map.

## Sticky Notes

`qfu_workitem.qfu_stickynote` is the persistent, always-visible quote/work item note.

Rules:

- Sticky notes live on `qfu_workitem`, not imported `qfu_quote`, so source report refreshes do not wipe them.
- Sticky note updates should set `qfu_stickynoteupdatedon` and `qfu_stickynoteupdatedby`.
- The sticky note is the current visible note shown near the top of My Work, Quote Detail, Manager Panel, and Admin review screens.
- Action notes live on `qfu_workitemaction.qfu_notes` and remain the historical/audit trail for specific actions.

## Policy Use

Each generated work item should store the policy row used at generation time in `qfu_policy`.

Policy changes after generation should:

- apply to newly generated work items immediately
- update open work items only through a deliberate policy refresh flow
- never rewrite completed/closed work items silently

## Source Traceability

Every work item list/detail page should show source traceability:

- work type
- source system
- source document number
- source external key
- source import timestamp when available
- link/drill-through to source quote/backorder lines

Do not make workflow actions the only audit source. Source rows and import batches remain the proof of what came from the system of record.

## Idempotency

Work item upsert should use:

```text
qfu_worktype + qfu_sourceexternalkey
```

Flows should update in place when the same quote appears again.

They should preserve:

- current owner overrides
- completed attempts
- last followed-up date
- last action
- roadblock/escalation state
- sticky note fields
- action history

They may refresh:

- customer display name
- total value
- source record lookups
- policy lookup when a deliberate policy refresh is running
- assignment status if unresolved aliases become resolved

## Phase 1 Non-Goals

- No custom staff "My Work" page yet.
- No live alert sending.
- No automatic reassignment based on name-only matches.
- No security enforcement beyond schema readiness.
