# Revenue Follow-Up Admin Panel MVP

Date: 2026-04-24

## Phase Boundary

Current phase: Phase 2 - live Dataverse tables and Power Apps Admin Panel MVP.

Functional after this phase:

- The model-driven Power Apps Admin Panel MVP structure is documented.
- Required Admin Panel areas/views/forms are defined for staff, memberships, aliases, policy, exceptions, work items, actions, and alert logs.
- The old Power Pages ops-admin workflow is explicitly out of scope for this workflow.
- Branch Policy, Work Item Actions, Work Items, and Assignment Exceptions are hardened for mode-driven policy behavior.
- Work Item and Work Item Action forms now include sticky notes, last followed-up date, and attempt-history UX requirements.
- The confirmed first follow-up MVP default is shown on the Branch Policy form as `ImportDate` plus `1` business day.

Not functional yet:

- If the model-driven app shell is not created by automation, this document remains the manual build specification for the Power Apps maker experience.
- Admin screens are not yet available to users.
- No staff/alias/policy data has been entered through the app.
- Import Health is placeholder/later unless implemented in a later pass.
- Resolver flow and alert flow are not created.
- No custom pages or Google Stitch prototypes have been created.

What comes next:

- Create or validate the forms, views, and model-driven app sitemap inside the selected solution.
- Export/unpack app metadata back into the repo.
- Use the Admin Panel to configure staff, aliases, branch memberships, policy, and exceptions before enabling alerts.

Still left:

- Live app shell if not created by automation, UX validation, permissions, model-driven command behavior, custom pages for My Work/Manager/GM, and security.

Questions that must not be guessed:

- Which users can edit Admin Panel data before security is implemented.
- Which screens should be read-only for managers versus admins.
- Whether Import Health is included in Admin MVP or deferred.
- Alert/CC modes.

## Purpose

The Admin Panel MVP is a model-driven Power Apps area for configuring the Revenue Follow-Up Workbench. It should be simple, auditable, and available before alerts and the polished staff work screen are enabled.

This admin surface should not be built into the old Power Pages ops-admin route.
It should not be a custom React/web app and should not rely on editing Power Automate flow settings for normal branch/staff configuration.

## App Name

Recommended app name:

```text
Revenue Follow-Up Workbench
```

## App Areas

The model-driven app should contain these top-level areas:

| Area | Purpose | Phase |
| --- | --- | --- |
| My Work | Daily TSR/CSSR work queue and action surface | Later Phase 1/Phase 2 after admin data works |
| Manager Panel | Branch/team workload, unmapped staff, overdue work, roadblocks | Later Phase 1/Phase 2 |
| Admin Panel MVP | Staff, aliases, branch memberships, policy, exceptions, work items, actions, alert logs | Phase 2 MVP |
| GM Review | GM escalations, roadblocks, branch policy review | Later Phase 2 |

## Admin Panel Sitemap

| Area | Views |
| --- | --- |
| Staff | Active Staff, Staff Missing Email, Staff Missing Dataverse User |
| Branch Memberships | Active Branch Memberships, Memberships by Branch, Memberships by Role |
| Staff Alias Mapping | Active Aliases, Unverified Aliases, Aliases by Source System, Potential Duplicate Aliases |
| Branch Policies | Active Policies, Draft/Inactive Policies, Policies by Branch, Quote Policies |
| Assignment Exceptions | Open Assignment Exceptions, Missing TSR Alias, Missing CSSR Alias, Blank/Zero Alias Exceptions, Resolved Exceptions |
| Work Items | Open Work Items, Needs TSR Assignment, Needs CSSR Assignment, Quotes >= $3K, Overdue Work Items, Work Items with Sticky Notes |
| Work Item Actions | Recent Actions, Attempt Actions, Non-Attempt Actions |
| Alert Logs | Pending Alerts, Sent Alerts, Failed Alerts, Suppressed/Skipped Alerts |
| Import Health | Deferred from Phase 2 unless explicitly added later |

## Forms

### Staff

Primary form fields:

- Staff Name
- Primary Email
- Staff Number
- Dataverse User
- Entra Object ID
- Default Branch
- Active
- Notes

Subgrids:

- Staff Aliases
- Branch Memberships
- Open Work Items
- Recent Actions

### Staff Alias Mapping

Primary form fields:

- Source System
- Alias Type
- Raw Alias
- Normalized Alias
- Role Hint
- Branch
- Scope Key
- Staff
- Active
- Verified By
- Verified On
- Notes

Commands:

- Normalize Alias
- Verify Alias
- Deactivate Alias

The normalize command should use the same normalization logic as the resolver flow.

### Branch Membership

Primary form fields:

- Branch
- Staff
- Role
- Active
- Start Date
- End Date
- Is Primary
- Notes

Validation:

- A staff member can have more than one branch and more than one role.
- More than one active GM or Manager can exist if the business wants group coverage.
- `Is Primary` should be used only when a flow needs one preferred recipient.

### Branch Policy

Primary form fields:

- Policy Name
- Branch
- Scope Key
- Work Type
- High-Value Threshold
- Threshold Operator
- Work Item Generation Mode
- Required Attempts
- First Follow-Up Basis
- First Follow-Up Business Days
- Primary Owner Strategy
- Support Owner Strategy
- GM CC Mode
- Manager CC Mode
- CSSR Alert Mode
- Escalate After Business Days
- Digest Enabled
- Targeted Alert Enabled
- Active

Validation:

- Require a global default policy for Quote before quote work item generation is enabled.
- Branch-specific policy overrides global policy.
- Active duplicate policies for the same scope/work type should be blocked by validation or surfaced as an admin error.
- The form should use mode fields rather than vague enabled-only booleans for GM, manager, and CSSR alert behavior.
- Threshold comparison and low-value work item behavior must remain configurable; do not bake either into a flow expression.
- For MVP quote policy defaults, show `First Follow-Up Basis = ImportDate` and `First Follow-Up Business Days = 1`. This means next business day after import for high-value quote work items; branch holiday logic is deferred.

### Assignment Exception

Primary form fields:

- Exception Type
- Branch
- Source System
- Source Field
- Raw Value
- Normalized Value
- Display Name
- Source Document Number
- Source External Key
- Source Quote
- Source Quote Line
- Source Backorder
- Work Item
- Status
- Resolved Staff
- Resolved By
- Resolved On
- Notes

Commands:

- Create Staff
- Map Alias to Existing Staff
- Resolve Exception
- Ignore Exception

Resolution behavior:

- Resolving a missing alias should create or update `qfu_staffalias`.
- Resolving a work item exception should trigger a re-resolution of the affected work item.

### Work Item

Primary form fields:

- Work Item Number
- Work Type
- Source System
- Branch
- Source Document Number
- Sticky Note
- Sticky Note Updated On
- Sticky Note Updated By
- Customer Name
- Total Value
- Primary Owner Staff
- Support Owner Staff
- TSR Staff
- CSSR Staff
- Required Attempts
- Completed Attempts
- Status
- Priority
- Next Follow-Up On
- Last Followed Up On
- Last Action On
- Overdue Since
- Escalation Level
- Policy
- Assignment Status
- Notes

Layout behavior:

- Show Sticky Note near the top of quote/work item detail, not buried in a tab.
- Sticky Note should be visible in My Work, Quote Detail, Manager Panel, and Admin review screens.
- Show Last Followed Up On near Attempts so staff can quickly see the actual last follow-up date/time.

Subgrids:

- Work Item Actions
- Alert Logs
- Assignment Exceptions

Commands:

- Reassign TSR
- Reassign CSSR
- Add Note
- Create Action
- Mark Roadblock
- Close Won
- Close Lost

### Work Item Action

Primary form fields:

- Work Item
- Action Type
- Counts As Attempt
- Action By
- Action On
- Attempt Number
- Outcome
- Next Follow-Up On
- Related Alert
- Notes

Validation:

- Completed attempts should be calculated from actions where `Counts As Attempt = Yes`.
- `Action On` is the actual date/time the action happened.
- For attempt actions, label `Action On` as `Followed Up On`.
- For attempt actions, label `Notes` as `Follow-Up Notes`.
- `Action On` should default to now for new manual actions, but users should be able to edit it if they are logging a follow-up that happened earlier.
- Any action where `Counts As Attempt = Yes` must require `Action On`.
- Use MVP defaults: Call, Email, and Customer Advised count as attempts; Note, Roadblock, Escalated, Due Date Updated, Won, Lost, Cancelled, Assignment/Reassignment, and Sticky Note Updated do not.

Timeline/subgrid behavior:

- Show action date, action type, action by, counts as attempt, and notes.
- Work item action rows are the audit/history trail.
- The work item sticky note is the current visible note.

### Alert Log

Primary form fields:

- Work Item
- Alert Type
- Recipient Staff
- Recipient Email
- CC Emails
- Dedupe Key
- Status
- Sent On
- Failure Message
- Flow Run ID
- Notes

Commands:

- Retry Failed Alert, later phase only
- Suppress Alert, later phase only

## Admin Workflows

### Map Unmapped Staff

1. Admin opens Open Assignment Exceptions.
2. Admin filters to Missing TSR Alias or Missing CSSR Alias.
3. Admin reviews source field, raw value, normalized value, display name, branch, and row count.
4. Admin maps the alias to an existing staff row or creates a staff row.
5. System creates/updates `qfu_staffalias`.
6. System re-runs resolver for affected open work items.

### Configure Branch Policy

1. Admin creates or edits a branch policy.
2. Admin sets threshold, attempts, owner strategy, digest, targeted alert, and CC behavior.
3. Policy validation checks for duplicate active policies.
4. Work item generator uses branch policy first, then global default.

### Maintain Branch Roles

1. Admin opens Branch Memberships.
2. Admin adds staff to branch with role TSR, CSSR, Manager, GM, or Admin.
3. Admin sets Active and Is Primary if needed.
4. Later security and CC resolution read this table.

## UX Principles

- Keep the admin MVP table-driven and dense.
- Use views and forms first; custom pages come later for the daily staff work UX.
- Do not hide mapping failures. Surface them in Assignment Exceptions.
- Avoid hardcoded people or branch-specific flow logic. Admin data should drive behavior.
- Make duplicate and unverified mappings easy to find.
- Configuration must be editable in Dataverse through the model-driven app without changing flow definitions.

## Later Custom Pages

The staff-facing "My Work" screen should be a later custom page inside the model-driven Power App after the admin foundation works.

Future pages:

- My Work
- Quote work item side panel
- Manager Panel
- GM Review

These should use `qfu_workitem`, `qfu_workitemaction`, and source record drill-throughs after the ownership model is proven.

## ALM Notes

- Create the app and tables inside a managed solution path, not loose default-solution work.
- Export/unpack the solution into the repo after creation.
- Keep model-driven app metadata, forms, views, choices, tables, and cloud flows source-controlled together.
