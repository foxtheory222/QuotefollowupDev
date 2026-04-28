# Target Architecture Recommendation

## Keep

- Keep Power Pages as the primary monitoring UX.
- Keep Dataverse as the single source of truth.
- Keep the custom runtime/Web API pattern, but continue hardening it with explicit allowlists, pagination guards, diagnostics, and summary-table reads.
- Keep Power Automate as the production ingestion path.
- Keep parser contract tests and runtime contract tests.

## Change

- Replace branch-cloned flows with source-family flows driven by qfu_branch, qfu_region, and qfu_sourcefeed configuration.
- Add Dataverse tables for staff, branch staff assignment, queue assignment, alert log, escalation policy, flow health, replay request, and audit history.
- Normalize TSR/CSSR/manager/GM ownership to records rather than text-only fields.
- Make quote/backorder current-state upserts depend on canonical alternate keys and prove duplicate-prevention in solution metadata.
- Move all branch/mailbox/folder/threshold/recipient settings to environment variables or Dataverse configuration.

## Remove Or Retire

- Retire local scheduled-task and timer fallback paths for recurring ingestion.
- Retire broad live graph patching as a normal repair path.
- Retire static branch pages and branch-specific special-case logic where a dynamic route and configuration can serve the same purpose.

## Manager Panel

- Power Pages manager route scoped by user-to-branch assignment.
- Staff management surface for branch manager: add/remove TSR/CSSR mappings, set active/inactive, default queues, and escalation backup.
- Dashboard: overdue quotes, due today, unassigned queue, stale source feeds, failed alerts, staff workload.

## Admin Panel

- Internal admin Power Pages or model-driven app for global ops.
- Manage regions, branches, source feeds, thresholds, flow health, replay requests, staff/role mappings, and audit search.

## TSR/CSSR Queues

- Dataverse queue/assignment table keyed by quote/line, branch, role, assignee, status, due date, and escalation state.
- Preserve source owner fields for traceability, but use normalized assignee records for operational ownership.

## Alerts

- Central alert scheduler flow keyed by alert dedupe key: quote/backorder + assignee + alert type + due date.
- Alert result log with recipient, channel, attempt count, sent/failed state, and escalation chain.

## Security

- Use Dataverse security roles/teams plus Power Pages table permissions scoped to branch/region where feasible.
- Branch managers see assigned branches; GMs see their regions; admins see all.
- Do not rely on client-side filtering for confidentiality.

## Deployment / ALM

- Keep pac pages download ... -mv Enhanced source-controlled.
- Export complete managed/unmanaged solutions for Dataverse schema, flows, connection references, environment variables, security roles, and model-driven admin app if used.
- Validate generated flows, Dataverse rows, portal render, and run history in that order.