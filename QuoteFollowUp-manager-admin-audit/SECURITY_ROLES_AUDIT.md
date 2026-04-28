# Security Roles Audit

## Current Users / Roles / Groups In Repo

- Power Pages web roles found: Authenticated Users, Anonymous Users, Administrators.
- Table permissions found: 16 files under site/table-permissions.

## Visibility And Edit Rights

- Several operational tables use Global Read permissions, including quotes, quote lines, backorders, summaries, budgets, finance snapshots, and exceptions.
- Some configuration or operational tables have Global ReadWrite permissions, including branch, region, source feed, budget archive, and delivery-not-PGI.
- Freight work items use Authenticated ReadWrite permission.
- Branch-level access was not proven from source-controlled table permissions.

## Dataverse Security

- Dataverse security role exports, business unit design, owner/access team design, and user/team membership exports were not found.
- Managers, TSRs, and CSSRs are not proven as dedicated role/person records from repo artifacts.

## Risk

The current portal metadata is adequate for a pilot but not enough for 20-branch secure rollout. Branch-level filtering must be enforced at Dataverse/Power Pages permission scope, not only in JavaScript route filters.