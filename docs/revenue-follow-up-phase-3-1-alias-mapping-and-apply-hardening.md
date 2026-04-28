# Revenue Follow-Up Phase 3.1 Alias Mapping And Apply Hardening

Date: 2026-04-27

Environment: `https://orga632edd5.crm3.dynamics.com/`

Current phase: Phase 3.1 - alias mapping prep and apply-mode hardening before controlled resolver apply.

## Scope

Phase 3.1 keeps the resolver in dry-run mode and prepares for a controlled future apply-mode run.

In scope:

- Recheck live solution, app, table, key, staff, alias, and branch membership state.
- Generate unresolved alias review and import templates.
- Separate invalid aliases from valid alias mapping candidates.
- Harden resolver apply-mode behavior before any broad write.
- Re-run dry-run to confirm counts did not change.

Out of scope:

- Broad apply mode.
- Alerts and daily digests.
- TSR/CSSR My Work page.
- Manager Panel.
- GM Review.
- Old Power Pages ops-admin workflow changes.
- Replacing `qfu_quote`, `qfu_quoteline`, or `qfu_backorder`.

Google Stitch remains design/prototype guidance only. The implementation target is still the Power Apps model-driven app backed by Dataverse; no frontend code was generated from Stitch.

## Live State

Phase 3.1 found no active staff/alias/membership setup yet:

| Item | Count |
| --- | ---: |
| Active `qfu_staff` records | 0 |
| Active `qfu_staffalias` records | 0 |
| Active AM Number aliases | 0 |
| Active CSSR Number aliases | 0 |
| Active branch memberships | 0 |
| Duplicate alias mapping groups | 0 |
| Multi-staff same-scope alias groups | 0 |

Because no active mappings exist, Phase 3.1 did not infer or create any mappings.

## Generated Templates

Templates were generated under:

```text
results/phase3-1-alias-mapping/
```

Files:

- `unresolved-staff-alias-review.csv`
- `invalid-alias-exceptions-review.csv`
- `qfu_staff-import-template.csv`
- `qfu_staffalias-import-template.csv`
- `qfu_branchmembership-import-template.csv`

The unresolved alias review contains valid AM Number and CSSR Number aliases from high-value quote groups. The invalid alias review contains blank and zero aliases and explicitly directs source/manager review instead of staff mapping.

## Mapping Rules

Admins must not map blank, zero, `00000000`, `NULL`, `N/A`, `NA`, or `NONE` aliases to staff.

Admins must not trust AM Name or CSSR Name for automatic routing. Names are review context only.

Valid mappings must resolve through:

```text
qfu_staffalias -> qfu_staff -> optional Dataverse systemuser
```

AM Number maps to TSR identity. CSSR Number maps to CSSR identity.

## How To Fill Templates

1. Open `unresolved-staff-alias-review.csv`.
2. Review `alias_type`, `normalized_alias`, branch, display examples, count, and value.
3. Confirm the actual staff member externally or through known internal staff records.
4. Create or update the staff record in the Admin Panel, or fill `qfu_staff-import-template.csv` for import.
5. Fill `qfu_staffalias-import-template.csv` with `qfu_staff_name_or_key` only after the staff identity is confirmed.
6. Fill `qfu_branchmembership-import-template.csv` only after the staff identity and branch/role relationship are confirmed.
7. Enter or import records in the Admin Panel MVP.
8. Re-run resolver dry-run.
9. Confirm TSR/CSSR resolved counts increase and assignment exception counts decrease before apply mode.

## Apply Hardening

The resolver apply path now:

- Sets `qfu_sourcedocumentnumber` on assignment exceptions from the source quote number.
- Sets `qfu_sourceexternalkey` on assignment exceptions.
- Links `qfu_sourcequote` when the quote header exists.
- Links `qfu_sourcequoteline` to a representative quote line when available.
- Captures newly created `qfu_workitemid` values and links related assignment exceptions before exception writes.
- Sets `qfu_status = Open` only for new work items or existing work items where status is blank/null.
- Preserves existing owner fields.
- Preserves existing `qfu_nextfollowupon`.
- Preserves sticky notes, action history, last-followed-up/action dates, and existing completed attempts.

Apply mode still requires explicit `-Mode Apply -ConfirmApply` and was not run in Phase 3.1.

## Header And Line Completeness

Phase 3.1 found:

| Item | Count |
| --- | ---: |
| Quote header groups | 521 |
| Quote line groups | 566 |
| Line groups without header | 45 |
| Header groups without lines | 0 |

The current resolver continues to use quote header groups for MVP dry-run behavior. Do not guess how to process line-only quote groups. A later resolver design decision should explicitly decide whether to process the union of quote header groups and quote line groups.

## Dry-Run Result

After hardening, dry-run counts stayed aligned with Phase 3:

| Metric | Count |
| --- | ---: |
| Quote groups found | 521 |
| Quote groups at or above $3,000 | 109 |
| Work items that would be created | 109 |
| Work items that would be updated | 0 |
| Assignment exceptions that would be created | 218 |
| Assignment exceptions that would be updated | 0 |
| TSR aliases resolved | 0 |
| CSSR aliases resolved | 0 |
| Alerts sent | 0 |

Apply-mode hardening changed write safety only. It did not change dry-run selection counts.

## Solution Export

No solution export was required in Phase 3.1 because no Dataverse fields, keys, forms, views, app metadata, or other solution components were changed. The changes were limited to scripts, documentation, CSV templates, and dry-run evidence.
