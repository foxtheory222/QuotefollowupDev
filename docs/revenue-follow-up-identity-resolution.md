# Revenue Follow-Up Identity Resolution

Date: 2026-04-24

## Phase Boundary

Current phase: Phase 1.2 - follow-up date, sticky notes, and Google Stitch UI prompt standard before live Dataverse table creation.

Functional after this phase:

- Resolver rules are documented for AM Number/TSR and CSSR number identity aliases.
- Invalid alias handling is defined for blank, zero, all-zero, `N/A`, `NA`, `NULL`, and `NONE`.
- Live `qfu_quoteline` fields for TSR/CSSR numeric aliases and display names are identified.
- Quote-line-driven assignment exceptions can point to a representative `qfu_sourcequoteline` for traceability.

Not functional yet:

- No `qfu_staffalias` rows have been created by this doc.
- No automatic routing is enabled.
- No assignment exceptions are being written by a production flow.
- No Dataverse `systemuser` security routing is active.
- No live Dataverse tables, model-driven app, resolver flow, or alert flow has been created.
- No custom pages or Google Stitch prototypes have been created.

What comes next:

- Create staff, alias, branch membership, and exception tables.
- Build the alias normalizer/resolver child flows.
- Run a dry run against recent SP830CA quote lines and review unmapped aliases before enabling writes.

Still left:

- Staff mapping data entry, alias verification, exception management UX, dry-run artifacts, and later security role mapping.

Questions that must not be guessed:

- Who may verify aliases before security is implemented.
- Whether name aliases can ever be used automatically outside explicitly verified mappings.
- Whether CSSR receives targeted alerts or digest-only visibility.

## Baseline Finding

The identity audit showed that SP830CA AM Number and CSSR number are still the right business keys, but they are not currently populated into active Dataverse `systemuser.employeeid` rows.

Confirmed result:

- `systemuser.employeeid` cannot be used for automatic routing today.
- Exact name-only matches are not reliable enough for routing.
- AM Number and CSSR number must resolve through `qfu_staffalias`.

The resolution path is:

```text
SP830CA AM Number / CSSR number
        -> qfu_staffalias
        -> qfu_staff
        -> optional Dataverse systemuser / email
        -> alerts, work queue, security later
```

## Role Mapping

| SP830CA Field | Meaning | Resolver Use |
| --- | --- | --- |
| AM Number | TSR business identity alias | Primary TSR resolver key |
| AM Name | TSR display/fallback alias | Display and manual mapping aid only |
| CSSR | CSSR business identity alias | Primary CSSR resolver key |
| CSSR Name | CSSR display/fallback alias | Display and manual mapping aid only |

There is no SSR role in this design.

## Confirmed Live Source Fields

Live metadata and a SP830CA quote-line sample on 2026-04-24 confirm that the current Dataverse fields needed for Phase 1 resolution exist on `qfu_quoteline`.

| Source Meaning | Current Dataverse Field | Notes |
| --- | --- | --- |
| AM Number / TSR number | `qfu_quoteline.qfu_tsr` | Numeric alias, including Excel decimal variants such as `<staff-number>.0` |
| AM Name / TSR name | `qfu_quoteline.qfu_tsrname` | Display/fallback only |
| CSSR number | `qfu_quoteline.qfu_cssr` | Numeric alias, including Excel decimal variants |
| CSSR Name | `qfu_quoteline.qfu_cssrname` | Display/fallback only |

`qfu_quote` also has `qfu_tsr`, `qfu_cssr`, and `qfu_cssrname`, but live metadata did not show a separate `qfu_tsrname` field. For quote work item generation, use grouped `qfu_quoteline` rows as the resolver source and link to `qfu_quote` when a header/current-state row is available.

Validation artifacts:

- `results/revenue-follow-up-source-field-metadata-20260424.json`
- `results/fetch-sp830-identity-sample-20260424.txt`

## Alias Normalization

Every alias value must be normalized before lookup, key creation, or exception creation.

Rules:

- Convert null to empty string.
- Trim leading and trailing whitespace.
- Collapse repeated internal whitespace for text aliases.
- Uppercase text aliases.
- For numeric aliases, remove harmless Excel decimal suffixes:
  - `<staff-number>.0` -> `<staff-number>`
  - `<staff-number>.00` -> `<staff-number>`
- Keep leading zeros only if the business confirms that the source treats them as significant. Until then, reject all-zero aliases as invalid.
- Reject invalid aliases:
  - blank
  - `0`
  - `00000000`
  - `N/A`
  - `NA`
  - `NULL`
  - `NONE`

Pseudo-code:

```text
normalizeAlias(value, aliasType):
    raw = string(value).trim()
    if raw is empty:
        return invalid("Blank Alias")

    upper = uppercase(collapseWhitespace(raw))
    if upper in ["0", "00000000", "N/A", "NA", "NULL", "NONE"]:
        return invalid("Zero Alias" or "Invalid Alias")

    if aliasType is a number alias and upper matches digits + ".0...":
        upper = digits before decimal

    if aliasType is a number alias and upper is all zeros:
        return invalid("Zero Alias")

    return valid(upper)
```

## Resolution Order

Numbers always beat names.

For a TSR from SP830CA:

1. Exact branch-scoped `AM Number` alias.
2. Exact global `AM Number` alias.
3. Exact branch-scoped `AM Name` alias, only if explicitly verified.
4. Exact global `AM Name` alias, only if explicitly verified.
5. Assignment exception.

For a CSSR from SP830CA:

1. Exact branch-scoped `CSSR Number` alias.
2. Exact global `CSSR Number` alias.
3. Exact branch-scoped `CSSR Name` alias, only if explicitly verified.
4. Exact global `CSSR Name` alias, only if explicitly verified.
5. Assignment exception.

Name aliases are mapping aids. They should not be auto-created from source names without review.

## Branch Scope

`qfu_staffalias` supports both branch-specific and global aliases.

Use:

- `qfu_branch` lookup when an alias is branch-specific.
- `qfu_scopekey = <stable branch key>` for branch-specific rows.
- `qfu_branch = null` and `qfu_scopekey = GLOBAL` for global rows.

Branch-scoped aliases should win over global aliases.

## Assignment Exception Rules

Missing or invalid TSR identity:

- Create or update `qfu_assignmentexception`.
- Write `qfu_sourcequoteline` when a representative quote line helps trace the exception.
- Set `qfu_workitem.qfu_assignmentstatus = Needs TSR Assignment`.
- Do not silently assign the quote to CSSR unless the business later decides that is the rule.

Missing or invalid CSSR identity:

- Create or update `qfu_assignmentexception`.
- Write `qfu_sourcequoteline` when a representative quote line helps trace the exception.
- If TSR is resolved, the work item may remain TSR-owned.
- Set `qfu_workitem.qfu_assignmentstatus = Partially Assigned` or `Needs CSSR Assignment` based on implementation choice.

Ambiguous alias:

- Create or update `qfu_assignmentexception` with `qfu_exceptiontype = Ambiguous Alias`.
- Do not pick one automatically.

Missing policy or branch:

- Create or update `qfu_assignmentexception`.
- Do not generate hardcoded fallback ownership or alert behavior.

## Resolver Outputs

For each quote work item candidate, the resolver should return:

| Output | Meaning |
| --- | --- |
| `tsrStaff` | Resolved TSR `qfu_staff`, nullable |
| `cssrStaff` | Resolved CSSR `qfu_staff`, nullable |
| `primaryOwnerStaff` | Usually TSR for quotes |
| `supportOwnerStaff` | Usually CSSR for quotes |
| `assignmentStatus` | Assigned, Partially Assigned, Needs TSR Assignment, Needs CSSR Assignment, Unmapped, Error |
| `exceptions` | Zero or more exception records to upsert |
| `resolutionTrace` | Source field, raw value, normalized value, alias row id, staff row id |

The trace should be written to logs or notes during dry run so incorrect mappings can be audited before alerts are enabled.

## Security Later

Security should not use source aliases directly.

Later security path:

```text
qfu_staff
        -> qfu_systemuser
        -> qfu_branchmembership
        -> branch/team/security role
```

This lets the source import keep using business identities while Dataverse security uses actual users and branch memberships.

## Data Quality Checks

Before enabling resolver automation:

- Count distinct `qfu_tsr` aliases by branch.
- Count distinct `qfu_cssr` aliases by branch.
- Count invalid AM Number aliases.
- Count invalid CSSR aliases.
- Count aliases that normalize to the same value but have different display names.
- Count aliases that map to more than one active staff row.
- Count active staff with no primary email.
- Count branch memberships with no active staff.

All counts should be written to a validation artifact in `results/` before enabling alerts.
