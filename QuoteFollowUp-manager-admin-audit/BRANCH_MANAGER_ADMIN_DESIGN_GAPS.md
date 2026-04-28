# Branch Manager Admin Design Gaps

## Scaling To 20 Branches

- Current stored flow artifacts are pilot-oriented and branch-specific for 4171, 4172, and 4173. Scaling needs configuration-driven source feed and branch metadata, not cloned branch flows.
- The portal has reusable runtime structure, but table permissions are broad/global for many operational tables.

## Staff Administration

- No dedicated branch staff table was found for branch managers to add/remove TSRs, CSSRs, managers, or GMs.
- Managers, TSRs, CSSRs, and users are not fully modeled as first-class Dataverse records in the repo evidence.
- A branch-manager admin panel needs controlled CRUD over branch staff assignment records, not direct edits to quote rows.

## Queues And Dashboards

- TSR/CSSR queues can be built from qfu_quote and qfu_quoteline, but normalized assignee records and queue ownership fields are missing.
- Manager dashboards exist conceptually in the Power Pages runtime, but manager-specific security and escalation/audit records are not proven.
- Admin/global dashboard needs ingestion health, alert history, duplicate audits, stale data, and replay status surfaced from Dataverse.

## Visibility And Role-Based Access

- Current Power Pages table permissions include global read/read-write patterns. Branch-specific visibility is not proven.
- Dataverse security roles, business units, owner teams, access teams, or scoped table permissions need explicit design and export.

## Reassignment, Alerts, Escalation, Audit

- Quote reassignment is not proven as a managed workflow.
- Alerts to assigned TSR/CSSR and escalation to manager/GM are not present as scalable stored alert flows.
- A dedicated alert/audit history table is missing.
- Assignment changes, follow-up changes, and manager overrides need audit rows with actor, timestamp, old/new value, reason, and source.