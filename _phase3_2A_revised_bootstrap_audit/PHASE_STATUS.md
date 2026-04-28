# Phase Status

- Current phase: Phase 3.2A revised - provisional staff, alias, and branch membership bootstrap.
- Provisional mappings created: yes.
- Resolver apply mode run: no.
- Work items created: 0.
- Assignment exceptions created: 0.
- Alerts sent: 0.

## Functional Now

- Provisional qfu_staff records exist for clean source report number/name pairs.
- Branch-scoped qfu_staffalias records exist for clean AM Number and CSSR Number aliases.
- TSR/CSSR qfu_branchmembership records exist where source branch data was valid.
- Resolver dry-run now resolves valid TSR/CSSR aliases and leaves only blank/zero alias exceptions.

## Not Functional Yet

- Controlled resolver apply has not created qfu_workitem rows.
- Assignment exceptions have not been written.
- Alerts and digests remain disabled.
- Emails and Dataverse system users are still blank for provisional staff.
- Manager and GM memberships are still not configured.

## Next

- Select a limited Phase 3.2B controlled apply scope in dev.
- Run resolver apply against that small scope only.
- Validate work item creation, exception linking, and no-alert behavior.

## Still Left

- Review provisional staff and aliases in the Admin Panel before production use.
- Resolve blank/zero aliases through source or manager review.
- Add email/system user mappings later when alert/security phases start.

## Blocking Questions

- Which branch and quote-group limit should be used for the first Phase 3.2B controlled apply?
