# Staff Alias Bootstrap Rules

These rules govern provisional staff and alias bootstrap for Phase 3.2A revised.

## Source Identity

The bootstrap uses report-provided number/name pairs from SP830CA source rows:

- TSR identity: AM Number plus AM Name.
- CSSR identity: CSSR Number plus CSSR Name.

Names are display/fallback evidence only. They are not trusted for automatic routing without a valid business alias number.

## Alias Normalization

- Trim whitespace.
- Convert Excel decimal whole-number aliases such as `7001634.0` to `7001634`.
- Uppercase nonnumeric text aliases.
- Preserve meaningful leading zeros in non-decimal aliases.
- Reject blank, `0`, `00000000`, `NULL`, `N/A`, `NA`, and `NONE`.

Invalid aliases create review output only. They must not become `qfu_staff` or `qfu_staffalias` rows.

## Conflict Rules

- Same normalized number with multiple different names: skip and review.
- Same source alias already mapped to a different staff record: skip and review.
- Same branch/staff/role membership already exists: update only when unambiguous.
- Same number used as both TSR and CSSR: allowed only when the number/name pairing is consistent.

## Records Created

For clean valid identities, dev bootstrap may create:

- `qfu_staff` with `qfu_name`, `qfu_staffnumber`, `qfu_active = true`, and source-generated provisional notes.
- `qfu_staffalias` with source system `SP830CA`, branch-scoped `qfu_scopekey`, alias type `AM Number` or `CSSR Number`, and active status.
- `qfu_branchmembership` for TSR or CSSR only.

Manager and GM memberships are not inferred from source quote reports.

## Fields Not Guessed

The bootstrap does not guess:

- `qfu_primaryemail`
- `qfu_systemuser`
- `qfu_entraobjectid`
- Manager or GM routing
- alert recipients

Those are Admin Panel or later security-phase tasks.
