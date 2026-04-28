# Risks And Gaps

- Hardcoded staff: Dedicated staff model was not found; TSR/CSSR/manager values are text or implicit in source data.
- Hardcoded branches: 4171, 4172, and 4173 pilot artifacts appear across flow exports, pages, scripts, and docs.
- Manual steps: Replay, repair, seed, and validation scripts are present and need controlled admin workflows.
- Missing logs: qfu_ingestionbatch exists, but dedicated alert, assignment, and admin action logs were not found.
- Missing dedupe logic: Current-state key rules are documented and audited by scripts, but alternate-key solution metadata was not found.
- Missing alert tracking: No central alert log table/export was found.
- Missing security roles: Power Pages web roles exist, but branch-scoped Dataverse security role/team exports were not found.
- Missing branch-level filtering: Current table permissions include broad/global access; route filters alone are insufficient.
- Missing error handling: Stored SA1300 flows contain some error paths, but full flow set and standardized failure handling are not exported.
- Missing audit trails: Assignment changes, quote status changes, follow-up edits, manager overrides, and replay requests need durable audit rows.
- Flow ownership risks: Branch-specific live flows and connector references can fail if owner/connections change; solution-aware service ownership is needed.
- Scale risk: Heavy KPI calculation must stay off page load and use summary tables; missing/stale summary rows should degrade visibly, not show false zeroes.
- ALM risk: Complete Dataverse schema, flows, security, and environment variable exports are needed for repeatable promotion.