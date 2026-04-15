# Schema / App Model Inspection

Date: 2026-04-15

Scope reviewed:
- current unpacked solution source under `solution/QuoteFollowUpSystemUnmanaged/src`
- existing local environment metadata already present in the repo, mainly `QFU_FINAL_AUDIT_STAGING/DATA/**`

## Current state

The solution boundary is better than the earlier snapshot.

Current source now includes entity metadata, forms, and saved views for all of the core tables relevant to Phase E:
- `qfu_quote`
- `qfu_activitylog`
- `qfu_rosterentry`
- `qfu_notificationsetting`
- `qfu_branch`
- `qfu_region`
- `qfu_sourcefeed`

For each of those tables, source currently includes:
- 1 main form
- 1 quick form
- 1 card form
- 7 saved queries

Local environment metadata already present in the repo aligns with that source picture for:
- `qfu_branch`
- `qfu_region`
- `qfu_sourcefeed`

That means the earlier blocker "branch/config tables exist only in local exports" is no longer true in this repo.

## Focused table status

### `qfu_quote`

Ownership:
- `UserOwned`

Already present and useful:
- quote identity and source fields
- branch/region fields
- CSSR / TSR source fields
- next-follow-up and touched timestamps
- current lightweight action / status fields

Still missing for deterministic quote follow-up:
- explicit landed/imported-on cadence anchor
- explicit attempts required / attempts done
- explicit escalation required / escalation done
- explicit compliance state
- explicit queue reason
- explicit waiting reason
- explicit manual close reason / transition source

### `qfu_activitylog`

Ownership:
- `UserOwned`

Already present and useful:
- quote lookup
- activity type
- performed-on
- performed-by name
- notes / description

Still missing for provable attempt logic:
- performed-by email
- performed-by role
- counts-as-attempt flag
- escalation flag
- waiting reason snapshot
- manual close reason
- source / system marker
- optional next-follow-up snapshot

### `qfu_rosterentry`

Ownership:
- `UserOwned`

Already present and useful:
- staff name
- work email
- branch code
- CSSR number
- TSR number
- active flag

Current weakness:
- `qfu_role` is still a single text field
- no durable multi-role model for CSSR / TSR / Manager / GM / Admin
- `qfu_manageremail` is not a normalized team-management structure

Minimum safe extension:
- add explicit role flags or a multi-select role choice
- keep `qfu_email` as the portal user match key

### `qfu_notificationsetting`

Ownership:
- `UserOwned`

Already present and useful:
- generic notification switch fields
- recipient type / role / email
- email subject template
- threshold / trigger time / timezone

Assessment:
- usable for notification templates and generic settings
- not a clean replacement for branch config or branch recipient maintenance

### `qfu_branch`

Ownership:
- `OrgOwned`

Already present and useful:
- branch code / name / slug
- region slug / name
- mailbox address
- warning thresholds
- stale threshold
- sort order

Assessment:
- now source-controlled and suitable as the primary branch config table

### `qfu_region`

Ownership:
- `OrgOwned`

Already present and useful:
- region slug / name
- warning thresholds
- stale threshold
- sort order / status

Assessment:
- source-controlled and sufficient for basic region config

### `qfu_sourcefeed`

Ownership:
- `OrgOwned`

Already present and useful:
- branch / region linkage
- source family
- mailbox address
- subject filter
- filename pattern
- folder id
- enabled flag

Assessment:
- source-controlled and suitable for feed-level mailbox/import config

## Admin / Manager model-driven app status

What exists:
- table metadata
- forms
- views
- ribbon diffs

What does not exist in current source:
- no app module artifacts
- no sitemap artifacts
- no model-driven app packaging for Admin Panel
- no model-driven app packaging for Manager Panel
- no Dataverse security role artifacts

Evidence:
- `solution/QuoteFollowUpSystemUnmanaged/src/Other/Solution.xml` lists only entity root components and workflow root components
- `solution/QuoteFollowUpSystemUnmanaged/src/Other/Customizations.xml` still has `<Roles />`
- repo-wide search in this workspace did not find `appmodule` or `sitemap` artifacts

Conclusion:
- Admin Panel does not exist in source
- Manager Panel does not exist in source
- the remaining Phase E gap is now app-layer and security-layer, not missing core config entities

## Minimum safe Phase E metadata/app work

### Tables

Already sufficient as the base table set:
- `qfu_quote`
- `qfu_activitylog`
- `qfu_rosterentry`
- `qfu_notificationsetting`
- `qfu_branch`
- `qfu_region`
- `qfu_sourcefeed`

Recommended additive schema work only:
1. Extend `qfu_quote` for deterministic queue/compliance state
2. Extend `qfu_activitylog` for counted attempt / escalation / close auditability
3. Extend `qfu_rosterentry` for real multi-role staff matching
4. Add one normalized child table for multi-recipient branch contacts

Recommended new child entity:
- `qfu_branchrecipient`

Minimum fields:
- branch lookup
- recipient email
- recipient name
- recipient role (`Manager`, `GM`, optional escalation CC)
- active
- sort order

### Forms / Views

No table-level UI blocker exists for day-one app build because the focused tables already have forms and saved views in source.

Recommended additions:
- app-specific quote compliance views
- app-specific roster/config views
- manager-focused queue views

### App artifacts

Still required:
1. `QFU Admin Panel` model-driven app module
2. `QFU Manager Panel` model-driven app module
3. sitemap for each app
4. app-scoped navigation around:
   - roster
   - branch config
   - source feeds
   - quote compliance
   - activity log
   - notification settings

### Security

Still required:
- Dataverse security role artifacts for app access

Minimum roles:
- `QFU Admin`
- `QFU Manager`
- optional `QFU GM` if not handled as a broader manager/admin role

## Practical feasibility

Phase E is now feasible from this repo with one important caveat:
- the repo has the table layer needed for Admin/Manager foundations
- it still does not have the app module, sitemap, or role artifacts needed to ship the model-driven apps themselves

So the remaining exact blocker is:
- missing source-controlled model-driven app and role components

Not blocked anymore:
- missing source-controlled `qfu_branch`
- missing source-controlled `qfu_region`
- missing source-controlled `qfu_sourcefeed`

## Bottom line

This refreshed repo is materially closer to Phase E than the older snapshot.

Current minimum safe path:
1. keep the existing focused tables
2. extend `qfu_quote`, `qfu_activitylog`, and `qfu_rosterentry` additively
3. add a normalized branch-recipient child table
4. add Admin / Manager app modules
5. add sitemaps
6. add Dataverse role artifacts

That is the minimum clean source-controlled foundation for Admin Panel / Manager Panel from this repo.
