# Revenue Follow-Up Admin Exception Workflow

Date: 2026-04-27

Implementation target: Power Apps model-driven app backed by Dataverse.

Google Stitch is design/prototype guidance only for any future visual pass. This workflow is implemented through the model-driven Admin Panel MVP and Dataverse records, not generated frontend code.

## Purpose

Admins use the Revenue Follow-Up Workbench Admin Panel MVP to resolve assignment exceptions by maintaining staff, alias, and branch membership data. The resolver should then be rerun so work items update from configuration, not hardcoded routing.

## Inputs

Phase 3.1 generated these review files:

- `results/phase3-1-alias-mapping/unresolved-staff-alias-review.csv`
- `results/phase3-1-alias-mapping/invalid-alias-exceptions-review.csv`
- `results/phase3-1-alias-mapping/qfu_staff-import-template.csv`
- `results/phase3-1-alias-mapping/qfu_staffalias-import-template.csv`
- `results/phase3-1-alias-mapping/qfu_branchmembership-import-template.csv`

## Missing TSR Alias

1. Open Assignment Exceptions in the Admin Panel MVP.
2. Filter to Missing TSR Alias.
3. Review Source System, Source Field, Raw Value, Normalized Value, Branch, Source Document Number, and Display Name.
4. Open Staff Alias Mapping.
5. Create or import an active alias:
   - Source System: SP830CA
   - Alias Type: AM Number
   - Normalized Alias: reviewed AM Number
   - Role Hint: TSR
   - Branch and Scope Key: use the reviewed branch/scope unless a global alias is intentionally approved
   - Staff: confirmed `qfu_staff` record
6. Rerun resolver dry-run.
7. Confirm TSR resolved count increases before apply mode.

## Missing CSSR Alias

1. Open Assignment Exceptions in the Admin Panel MVP.
2. Filter to Missing CSSR Alias.
3. Review Source System, Source Field, Raw Value, Normalized Value, Branch, Source Document Number, and Display Name.
4. Open Staff Alias Mapping.
5. Create or import an active alias:
   - Source System: SP830CA
   - Alias Type: CSSR Number
   - Normalized Alias: reviewed CSSR Number
   - Role Hint: CSSR
   - Branch and Scope Key: use the reviewed branch/scope unless a global alias is intentionally approved
   - Staff: confirmed `qfu_staff` record
6. Rerun resolver dry-run.
7. Confirm CSSR resolved count increases before apply mode.

## Blank Or Zero Alias

Blank, zero, `00000000`, `NULL`, `N/A`, `NA`, and `NONE` aliases must not be mapped to staff.

Use `invalid-alias-exceptions-review.csv` for manager/source review. The correct fix is source-data cleanup, source-owner confirmation, or explicit exception disposition, not a staff alias mapping.

## Staff Records

Create `qfu_staff` only when the person is confirmed. Do not guess:

- Primary email
- Dataverse user lookup
- Entra object ID
- Default branch
- Staff number

If those values are unknown, leave them blank and mark notes for follow-up.

## Branch Memberships

Create branch membership records only when branch and role are confirmed.

Allowed roles for this workbench are:

- TSR
- CSSR
- Manager
- GM
- Admin

There is no SSR role.

## Rerun Pattern

After staff/alias/membership updates:

1. Rerun resolver dry-run.
2. Compare resolved TSR/CSSR counts and planned exception counts.
3. Fix duplicate or ambiguous mappings before apply mode.
4. Run only a controlled dev apply after mapping review.

No alerts or daily digests are sent in Phase 3.1.
