# Controlled Apply Readiness

Phase 3.2B controlled resolver apply is not approved yet. Phase 3.2A revised only created provisional staff, alias, and branch membership records, then reran resolver dry-run.

## Current Readiness

- Revenue Follow-Up Workbench app exists in dev.
- Required Phase 3 tables exist.
- Phase 3 alternate/replacement keys are active.
- Provisional TSR and CSSR mappings now resolve clean valid source aliases.
- Duplicate active alias groups: 0.
- Duplicate active staff-number groups after cleanup: 0.
- Alerts remain disabled.
- Resolver apply mode was not run.

## Dry-Run Proof

Post-bootstrap dry-run:

- Quote groups scanned: 521.
- Quote groups at or above $3,000: 109.
- Work items that would be created: 109.
- Work items that would be updated: 0.
- TSR aliases resolved: 58.
- CSSR aliases resolved: 68.
- Assignment exceptions that would be created: 92.
- Alerts sent: 0.

The remaining exceptions are source blanks or zero aliases, not unresolved valid staff numbers.

## Before Phase 3.2B

Select a controlled apply scope before writing work items. Recommended first apply scope:

- Dev environment only.
- One branch.
- Small quote-group limit.
- Confirm expected work item count.
- Confirm assignment exceptions are linked to work items where applicable.
- Confirm no alert flow or digest path runs.

## Still Later

- Fill emails where alerts will eventually be needed.
- Map Dataverse system users when security identity work starts.
- Add Manager and GM memberships manually or from a verified administrative source.
- Review provisional records before production promotion.
- Keep resolver apply disabled until a specific controlled scope is approved.
