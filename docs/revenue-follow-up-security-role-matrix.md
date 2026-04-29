# Revenue Follow-Up Security Role Matrix

Status: Partial.

Phase 8 created QFU security role shells and documented the intended privilege matrix. Final table privileges were not applied because the verified roster and production privilege approval are not complete.

## Role Matrix

| Role | Purpose | Phase 8 State |
| --- | --- | --- |
| QFU Staff | Daily Workbench users who own or act on assigned queue items. | Role shell exists. Final privileges pending. |
| QFU Manager | Branch/team oversight, Manager Panel, assignment review. | Role shell exists. Final privileges pending. |
| QFU GM | Broader branch/region oversight. | Role shell exists. Final privileges pending. |
| QFU Admin | Setup, staff, aliases, policies, alert logs, and assignment exceptions. | Role shell exists. Final privileges pending. |
| QFU Service Account | Flow/import/resolver/rollup/alert processing. | Role shell exists. Final ownership and connection plan pending. |

## Minimum Intended Privileges

- Staff can read required Workbench data, create work item actions, and update allowed work item fields such as sticky notes.
- Managers can view and act on branch/team work items and assignment exceptions.
- GMs can view broader assigned branch/region data.
- Admins can manage configuration and operational setup tables.
- Service Account can run resolver, import, rollup, alert, and digest automation.

## Production Blockers

- Final privilege matrix needs approval.
- Verified staff, manager, GM, and admin roster is incomplete.
- Role-specific users are needed for least-privilege validation.
- Branch team membership and sharing rules must be tested before enforcement.
