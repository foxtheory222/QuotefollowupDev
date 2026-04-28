# Revenue Follow-Up Workbench Admin Panel MVP Google Stitch Prompt

Date: 2026-04-27

## Scope

Product: Revenue Follow-Up Workbench

Page: Admin Panel MVP

Implementation target: Power Apps model-driven app backed by Dataverse.

Google Stitch is design/prototype guidance only, not production frontend code. Do not generate or commit frontend code from Stitch for this phase.

Roles for this Admin Panel MVP prompt: Admin, GM, Manager.

## Prompt

```text
Design a Google Stitch screen for Revenue Follow-Up Workbench: Admin Panel MVP.

Implementation target: Power Apps model-driven app backed by Dataverse.

Google Stitch is design/prototype guidance only. It is not the production frontend implementation, and no frontend code should be generated or committed from this prompt.

Roles: Admin, GM, Manager.

Navigation:
- Staff
- Branch Memberships
- Staff Alias Mapping
- Branch Policies
- Assignment Exceptions
- Work Items
- Work Item Actions
- Alert Logs

Create a clean, simple, low-click, operations-focused admin experience. Optimize for desktop use, accessible contrast, readable spacing, and no clutter. The design should feel like a practical Dataverse admin panel, not a marketing dashboard.

Staff and branch membership screens should make ownership, role, active state, and branch association easy to scan. Staff Alias Mapping should make source system, alias type, raw alias, normalized alias, role hint, branch, staff, active state, and verification state easy to review.

Branch Policies should make high-value quote threshold, threshold operator, required attempts, first follow-up basis, first follow-up business days, owner strategies, alert modes, escalation timing, digest enabled, targeted alert enabled, and active state easy to review and edit.

Assignment Exceptions should emphasize exception type, branch, source system, raw and normalized value, source document number, source external key, linked source record, work item, status, resolved staff, and resolution dates.

Work Items must put Sticky Note prominently near the top. Last Followed Up On must be visible. Completed Attempts / Required Attempts must be visible. Assignment Status must be visible. Also show work item number, work type, source system, branch, source document number, customer, total value, primary owner staff, support owner staff, TSR staff, CSSR staff, status, priority, next follow-up, last action, overdue since, escalation level, policy, and notes.

Work Item Actions should show action type, counts as attempt, action by, action on, attempt number, outcome, next follow-up, related alert, and notes.

Alert Logs should show alert type, recipient staff, recipient email, CC emails, dedupe key, status, sent on, failure message, flow run ID, and notes.

Do not hardcode people, emails, branches, IDs, routing, AM numbers, CSSR numbers, thresholds, or production customer data.
```

## Phase 2.1 Status

No Google Stitch prototype was generated in Phase 2.1. This prompt exists so a future design pass can use Stitch for guidance while the actual implementation remains a Power Apps model-driven app backed by Dataverse.
