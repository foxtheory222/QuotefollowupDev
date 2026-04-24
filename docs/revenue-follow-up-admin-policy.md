# Revenue Follow-Up Admin Policy Notes

Date: 2026-04-24

## Phase Boundary

Current phase: Phase 1.2 - follow-up date, sticky notes, and Google Stitch UI prompt standard before live Dataverse table creation.

Functional after this phase:

- Policy fields and admin intent are documented for threshold, attempts, CC, digest, targeted alert, and escalation behavior.
- Policy lookup order is defined as branch policy first, then global default, then missing-policy exception.
- The design blocks hardcoded GM, manager, staff, email, branch, and threshold logic in flows.
- Policy control is hardened around explicit operator/mode fields rather than ambiguous enabled-only booleans.
- The dedicated solution name, quote threshold operator, low-value reporting behavior, and MVP attempt defaults are confirmed.

Not functional yet:

- No live `qfu_policy` table or policy rows are created by this note.
- No branch policy screen is available yet.
- No alerts, digests, escalations, or CC resolution are active.
- No live Dataverse tables, model-driven app, resolver flow, or alert flow has been created.
- No custom pages or Google Stitch prototypes have been created.

What comes next:

- Create `qfu_policy` in the selected solution.
- Add Branch Policies views/forms to the model-driven Admin Panel.
- Require policy lookup in resolver/work item flows before alert sending is enabled.

Still left:

- Live table creation, policy data entry, duplicate active policy validation, alert template decisions, and dry-run validation.

Questions that must not be guessed:

- GM/manager CC trigger rules.
- CSSR targeted alert behavior.
- First follow-up due-date rule.
- Which branch roles can edit policy before security is implemented.

This file preserves the policy-specific part of the Phase 1 decision set. The canonical schema is in `docs/revenue-follow-up-dataverse-schema.md`; this file explains how admins should use policy rows.

## Policy Role

`qfu_policy` controls business behavior that must not be hardcoded in flows:

- high-value thresholds
- threshold operator
- work item generation mode
- required follow-up attempts
- first follow-up basis and business-day offset
- primary owner strategy
- support owner strategy
- GM CC mode
- Manager CC mode
- CSSR alert mode
- digest behavior
- targeted alert behavior
- escalation timing

Mode fields should drive recipient and generation behavior:

| Field | Purpose |
| --- | --- |
| `qfu_thresholdoperator` | Controls whether the threshold is strict or inclusive. |
| `qfu_workitemgenerationmode` | Controls high-value-only, all-quotes, or reporting-only behavior. |
| `qfu_firstfollowupbasis` | Controls whether initial due date comes from import date, quote date, source due date, manual entry, or is disabled. |
| `qfu_firstfollowupbusinessdays` | Nullable business-day offset used with import date or quote date. |
| `qfu_gmccmode` | Controls GM CC/digest/escalation behavior. |
| `qfu_managerccmode` | Controls manager CC/digest/escalation behavior. |
| `qfu_cssralertmode` | Controls CSSR visibility, digest, targeted alerts, CC-only behavior, or disablement. |

Avoid creating earlier enabled-only fields such as `qfu_gmccenabled`, `qfu_managerccenabled`, and `qfu_alertcssrenabled` when these mode fields are available. Modes make the open business decision explicit instead of hiding it behind a true/false flag.

## Resolution Order

Policy lookup order:

1. Active branch policy for branch + work type.
2. Active global default policy for work type.
3. Missing Policy assignment exception.

No flow should silently fall back to hardcoded values when policy lookup fails.

## Initial Quote Policy Intent

The current business baseline is:

```text
work type = Quote
high value threshold = 3000
threshold operator = GreaterThanOrEqual
MVP low-value behavior = ReportingOnly
required attempts = 3
primary owner strategy = TSR_FROM_AM_NUMBER
support owner strategy = CSSR_FROM_CSSR_NUMBER
```

These values belong in `qfu_policy`; they should not be embedded in Power Automate expressions except as test fixtures.

For MVP quote work item creation, quotes at or above `$3,000` require 3 follow-up attempts. Below-threshold quotes remain reporting-only and should not become TSR follow-up work items unless a later confirmed policy changes that behavior.

## Dedicated Solution

Live Revenue Follow-Up Workbench assets should be created in the dedicated solution:

```text
qfu_revenuefollowupworkbench
```

This includes the Dataverse tables, choices, model-driven app, custom pages, and future flows for this workbench.

## CC Policy

GM and manager CC behavior should resolve through:

```text
qfu_policy
        -> qfu_branchmembership
        -> qfu_staff
        -> qfu_primaryemail
```

Do not hardcode individual GM, manager, or admin email addresses.

## Alert Policy

Phase 1 should not send live alerts. It should only prepare the policy and `qfu_alertlog` design.

Every alert must write `qfu_alertlog` with a dedupe key.
