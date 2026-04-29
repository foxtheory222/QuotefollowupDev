# Revenue Follow-Up Security Roles

Status: Partial.

Phase 8 created or verified security role shells in Dataverse:

- QFU Staff
- QFU Manager
- QFU GM
- QFU Admin
- QFU Service Account

The role shells were added to the `qfu_revenuefollowupworkbench` solution export.

## Intended Privilege Matrix

QFU Staff:
- Read assigned/current queue work items where feasible.
- Create work item actions.
- Update sticky notes and action fields where allowed.
- Read staff, branch, alias, and policy lookup data needed by the Workbench.

QFU Manager:
- QFU Staff privileges.
- Branch/team visibility.
- Read/update branch work items.
- View assignment exceptions.
- Use Manager Panel.

QFU GM:
- QFU Manager privileges across assigned branches/region.

QFU Admin:
- Manage staff.
- Manage aliases.
- Manage branch memberships.
- Manage policies.
- Manage alert logs.
- Manage assignment exceptions.
- Use Admin Panel.

QFU Service Account:
- Resolver/work item updates.
- Rollups.
- Alert logs.
- Alert/digest dry-run/live flows.
- Import/source processing as needed.

## Current Limitation

Only role shells are created. Final privilege levels, table scopes, and assignment strategy require approval before production enforcement. No maker/admin lockout was introduced.
