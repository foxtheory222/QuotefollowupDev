# Phase 3.2A Revised Provisional Staff Bootstrap

Phase 3.2A revised created provisional staff identity data in the dev Dataverse environment before any controlled resolver apply run.

## Scope

- Environment: `https://orga632edd5.crm3.dynamics.com/`
- Solution: `qfu_revenuefollowupworkbench`
- Source data: active `qfu_quoteline` SP830CA quote line rows.
- Tables written: `qfu_staff`, `qfu_staffalias`, `qfu_branchmembership`.
- Tables not written: `qfu_workitem`, `qfu_assignmentexception`, `qfu_alertlog`.

## Bootstrap Rules Used

- AM Number is the TSR business alias.
- AM Name is the TSR display name from the source report.
- CSSR Number is the CSSR business alias.
- CSSR Name is the CSSR display name from the source report.
- Names were not used alone for routing.
- Emails, Dataverse users, and Entra object IDs were not guessed.
- Invalid aliases were not mapped: blank, `0`, `00000000`, `NULL`, `N/A`, `NA`, and `NONE`.
- Excel decimal aliases such as `7001634.0` normalize to `7001634`.
- A number with multiple conflicting names is skipped for review.
- A number appearing as both TSR and CSSR is allowed only when the name pairing is consistent.

## Result

- Active provisional staff after cleanup: 19.
- Active branch-scoped aliases: 39.
- Active AM Number aliases: 16.
- Active CSSR Number aliases: 23.
- Active branch memberships: 39.
- Duplicate active staff-number groups: 0.
- Duplicate active alias groups: 0.
- Staff records missing email: 19.
- Staff records missing Dataverse user: 19.

One orphan duplicate `qfu_staff` row was created during the first lookup-bind retry. It had no alias or branch membership references and was deactivated immediately. The cleanup is recorded in `results/phase3-2A-revised/orphan-duplicate-cleanup.json`.

## Post-Bootstrap Dry Run

Resolver dry-run was rerun after mappings were created:

- Quote groups scanned: 521.
- Quote groups at or above $3,000: 109.
- Work items that would be created: 109.
- Work items that would be updated: 0.
- TSR aliases resolved: 58.
- CSSR aliases resolved: 68.
- TSR exceptions remaining: 51.
- CSSR exceptions remaining: 41.
- Assignment exceptions that would be created: 92.
- Alerts sent: 0.

The remaining exceptions are blank or zero source aliases. They should go to source or manager review, not staff alias mapping.

## Admin Review

Admins should review the provisional staff, aliases, and branch memberships in the Revenue Follow-Up Workbench Admin Panel before production use. The records are intentionally marked as source-generated provisional data. Security identity mapping, email completion, Manager memberships, and GM memberships are still later setup work.
