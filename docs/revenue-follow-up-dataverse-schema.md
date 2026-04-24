# Revenue Follow-Up Dataverse Schema

Date: 2026-04-24

## Phase Boundary

Current phase: Phase 2 - live Dataverse tables and Power Apps Admin Panel MVP.

Functional after this phase:

- Reviewed table definitions for `qfu_staff`, `qfu_staffalias`, `qfu_branchmembership`, `qfu_policy`, `qfu_workitem`, `qfu_workitemaction`, `qfu_alertlog`, and `qfu_assignmentexception`.
- Documented source-table boundaries showing `qfu_workitem` references `qfu_quote`, `qfu_quoteline`, and `qfu_backorder` rather than replacing them.
- Confirmed `qfu_quoteline` identity fields for SP830CA quote resolver design.
- Hardened policy, attempt counting, work item source-system, and quote-line exception fields.
- Added explicit fields for actual follow-up date/time logging and persistent work item sticky notes.
- Locked the dedicated solution name, threshold operator, low-value reporting behavior, MVP attempt-bearing action defaults, and first follow-up rule.

Not functional yet:

- No data migration or backfill has run.
- No resolver or work item generator has been enabled.
- No model-driven Power App has been created or published.
- No custom pages or Google Stitch prototypes have been created.

What comes next:

- Validate the Dataverse tables/choices in the dedicated `qfu_revenuefollowupworkbench` Power Platform solution.
- Add forms/views for the model-driven Admin Panel MVP.
- Export/unpack the created solution back into source control.

Still left:

- Model-driven app shell/forms/views, alternate keys where appropriate, validation against live metadata, and non-alerting resolver dry runs.

Questions that must not be guessed:

- Backorder work item grain.
- GM, manager, and CSSR alert mode values.
- Which optional source lookups are present in the target solution at table-creation time.

## Design Rules

- Imported operational tables remain the source of truth and traceability layer.
- `qfu_workitem` stores follow-up state and references imported records; it does not replace imported records.
- Staff numbers from SP830CA are business aliases, not Dataverse security identities.
- Branch lookups should point to the existing `qfu_branch` table.
- Tables that support branch-scoped and global rows should include a text `qfu_scopekey` in addition to a nullable branch lookup. Use `GLOBAL` for global rows and a stable branch key for branch rows. This avoids alternate-key ambiguity around null branch values.
- Choice values should be created as reusable global choices where practical so model-driven app filters and flows stay consistent.

## Proposed Global Choices

| Choice | Values |
| --- | --- |
| Work Type | Quote, Backorder, Freight, Pickup, General |
| Staff Role | TSR, CSSR, Manager, GM, Admin |
| Alias Type | AM Number, AM Name, CSSR Number, CSSR Name, Created By, Email, Other |
| Role Hint | TSR, CSSR, Manager, GM, Admin, Unknown |
| Work Status | Open, Due Today, Overdue, Waiting on Customer, Waiting on Vendor, Roadblock, Escalated, Completed, Closed Won, Closed Lost, Cancelled |
| Priority | Low, Normal, High, Critical |
| Assignment Status | Assigned, Partially Assigned, Needs TSR Assignment, Needs CSSR Assignment, Unmapped, Error |
| Escalation Level | None, Manager, GM, Admin |
| Action Type | Call, Email, Customer Advised, Vendor Contacted, Due Date Updated, Follow-Up Scheduled, Roadblock, Escalated, Won, Lost, Cancelled, Assignment/Reassignment, Sticky Note Updated, Note |
| Alert Type | New Assignment, Due Today, Overdue, Escalation, Daily Digest, Assignment Exception, Flow Failure |
| Alert Status | Pending, Sent, Failed, Suppressed, Skipped |
| Exception Type | Missing TSR Alias, Missing CSSR Alias, Blank Alias, Zero Alias, Ambiguous Alias, Missing Branch, Missing Policy, Other |
| Exception Status | Open, In Review, Resolved, Ignored |
| Threshold Operator | GreaterThan, GreaterThanOrEqual |
| Work Item Generation Mode | HighValueOnly, AllQuotes, ReportingOnly |
| First Follow-Up Basis | ImportDate, QuoteDate, SourceDueDate, Manual, Disabled |
| GM CC Mode | Disabled, NewHighValue, DueToday, Overdue, EscalatedOrRoadblock, DailyDigestOnly |
| Manager CC Mode | Disabled, NewHighValue, DueToday, Overdue, EscalatedOrRoadblock, DailyDigestOnly |
| CSSR Alert Mode | VisibilityOnly, DailyDigestOnly, TargetedAlerts, CCOnly, Disabled |

## `qfu_staff`

Purpose: one row per real staff person who may own work, receive alerts, belong to a branch, or later map to a Dataverse user.

| Column | Type | Required | Notes |
| --- | --- | --- | --- |
| `qfu_name` | Text | Yes | Display name used in admin and work queues |
| `qfu_primaryemail` | Email/Text | No | Used for alerts when populated |
| `qfu_staffnumber` | Text | No | Optional primary business staff number; aliases remain in `qfu_staffalias` |
| `qfu_systemuser` | Lookup to `systemuser` | No | Nullable until security identity is mapped |
| `qfu_entraobjectid` | Text/GUID | No | Optional Entra object id for later reconciliation |
| `qfu_defaultbranch` | Lookup to `qfu_branch` | No | Convenience default only, not security by itself |
| `qfu_active` | Yes/No | Yes | Active staff can be assigned work |
| `qfu_notes` | Multiline Text | No | Admin notes |

Relationships:

- One `qfu_staff` to many `qfu_staffalias`.
- One `qfu_staff` to many `qfu_branchmembership`.
- One `qfu_staff` to many `qfu_workitem` owner lookups.
- One `qfu_staff` to many `qfu_workitemaction` rows.
- One `qfu_staff` to many `qfu_alertlog` recipient rows.

Alternate keys:

- Optional: `qfu_primaryemail` when populated and normalized.
- Do not rely on `qfu_staffnumber` as the only key because one person can have multiple source aliases.

Illustrative example only:

| `qfu_name` | `qfu_primaryemail` | `qfu_staffnumber` | `qfu_active` |
| --- | --- | --- | --- |
| Example Staff | `<staff-email>` | `<staff-number>` | Yes |

Relation to existing operational tables:

- `qfu_quote`, `qfu_quoteline`, and `qfu_backorder` continue to store imported source identity/display fields.
- `qfu_staff` is linked to generated work items, not written back as the source of imported quote/backorder ownership.

## `qfu_staffalias`

Purpose: maps source aliases from SP830CA, ZBO, and future sources to `qfu_staff`.

| Column | Type | Required | Notes |
| --- | --- | --- | --- |
| `qfu_sourcesystem` | Text or Choice | Yes | Examples: `SP830CA`, `ZBO` |
| `qfu_aliastype` | Choice | Yes | AM Number, AM Name, CSSR Number, CSSR Name, etc. |
| `qfu_rawalias` | Text | Yes | Source value as received |
| `qfu_normalizedalias` | Text | Yes | Normalized lookup value |
| `qfu_rolehint` | Choice | Yes | TSR, CSSR, Manager, GM, Admin, Unknown |
| `qfu_branch` | Lookup to `qfu_branch` | No | Null only for global aliases |
| `qfu_scopekey` | Text | Yes | `GLOBAL` or stable branch code/key |
| `qfu_staff` | Lookup to `qfu_staff` | Yes | Target person |
| `qfu_active` | Yes/No | Yes | Inactive aliases are ignored |
| `qfu_verifiedby` | Lookup to `systemuser` | No | Admin/system user who verified mapping |
| `qfu_verifiedon` | Date/Time | No | Verification timestamp |
| `qfu_notes` | Multiline Text | No | Reason/source for mapping |

Relationships:

- Many aliases to one staff row.
- Optional branch scope through `qfu_branch`.

Alternate keys:

- Recommended active integration key: `qfu_sourcesystem + qfu_aliastype + qfu_normalizedalias + qfu_scopekey`.
- Do not use raw alias in the key because `<staff-number>` and `<staff-number>.0` must resolve to the same normalized value.

Illustrative example only:

| `qfu_sourcesystem` | `qfu_aliastype` | `qfu_rawalias` | `qfu_normalizedalias` | `qfu_scopekey` | `qfu_rolehint` |
| --- | --- | --- | --- | --- | --- |
| SP830CA | AM Number | `<staff-number>.0` | `<staff-number>` | `<branch-key>` | TSR |

Relation to existing operational tables:

- SP830CA AM Number and CSSR number from imported quote rows are looked up here.
- Existing quote/backorder rows should not be assigned directly to `systemuser` from source numbers.

## `qfu_branchmembership`

Purpose: connects staff to branches and roles.

| Column | Type | Required | Notes |
| --- | --- | --- | --- |
| `qfu_branch` | Lookup to `qfu_branch` | Yes | Branch membership scope |
| `qfu_staff` | Lookup to `qfu_staff` | Yes | Staff member |
| `qfu_role` | Choice | Yes | TSR, CSSR, Manager, GM, Admin |
| `qfu_active` | Yes/No | Yes | Active memberships are used by policy/security |
| `qfu_startdate` | Date Only | No | Effective date |
| `qfu_enddate` | Date Only | No | End date for historical membership |
| `qfu_isprimary` | Yes/No | No | Preferred role/person when multiple match |
| `qfu_notes` | Multiline Text | No | Admin notes |

Relationships:

- Many memberships to one staff row.
- Many memberships to one branch.

Alternate keys:

- `qfu_branch + qfu_staff + qfu_role`.

Illustrative example only:

| `qfu_branch` | `qfu_staff` | `qfu_role` | `qfu_active` | `qfu_isprimary` |
| --- | --- | --- | --- | --- |
| `<branch>` | Example Staff | TSR | Yes | Yes |

Relation to existing operational tables:

- This table controls branch role visibility and later security. It does not change source quote/backorder ownership fields.

## `qfu_policy`

Purpose: configurable branch/source policy for thresholds, attempts, ownership, CC, escalation, and alerts.

| Column | Type | Required | Notes |
| --- | --- | --- | --- |
| `qfu_name` | Text | Yes | Human-readable policy name |
| `qfu_branch` | Lookup to `qfu_branch` | No | Null for global default |
| `qfu_scopekey` | Text | Yes | `GLOBAL` or stable branch code/key |
| `qfu_worktype` | Choice | Yes | Quote, Backorder, Freight, Pickup, General |
| `qfu_highvaluethreshold` | Currency/Decimal | Yes | Default design value for quotes is `3000`, but store as policy data |
| `qfu_thresholdoperator` | Choice | Yes | GreaterThan or GreaterThanOrEqual; MVP quote threshold uses GreaterThanOrEqual |
| `qfu_workitemgenerationmode` | Choice | Yes | HighValueOnly, AllQuotes, or ReportingOnly; MVP quote work item creation is high-value only and below-threshold quotes remain reporting-only |
| `qfu_requiredattempts` | Whole Number | Yes | Default design value is `3`, but store as policy data |
| `qfu_firstfollowupbasis` | Choice | Yes | ImportDate, QuoteDate, SourceDueDate, Manual, or Disabled |
| `qfu_firstfollowupbusinessdays` | Whole Number | No | Nullable offset used when first follow-up is calculated from import date or quote date; Phase 2 MVP default is `1` |
| `qfu_primaryownerstrategy` | Text/Choice | Yes | Example: `TSR_FROM_AM_NUMBER` |
| `qfu_supportownerstrategy` | Text/Choice | Yes | Example: `CSSR_FROM_CSSR_NUMBER` |
| `qfu_gmccmode` | Choice | Yes | Disabled, NewHighValue, DueToday, Overdue, EscalatedOrRoadblock, or DailyDigestOnly |
| `qfu_managerccmode` | Choice | Yes | Disabled, NewHighValue, DueToday, Overdue, EscalatedOrRoadblock, or DailyDigestOnly |
| `qfu_cssralertmode` | Choice | Yes | VisibilityOnly, DailyDigestOnly, TargetedAlerts, CCOnly, or Disabled |
| `qfu_escalateafterbusinessdays` | Whole Number | No | Used by escalation flows later |
| `qfu_digestenabled` | Yes/No | Yes | Controls digest eligibility |
| `qfu_targetedalertenabled` | Yes/No | Yes | Controls targeted alerts |
| `qfu_active` | Yes/No | Yes | Only active policies apply |

Policy hardening note:

- Use `qfu_thresholdoperator`, `qfu_workitemgenerationmode`, `qfu_gmccmode`, `qfu_managerccmode`, and `qfu_cssralertmode` as the flow-driving policy controls.
- Earlier enabled-only booleans for GM, manager, and CSSR alert behavior should not be created if the mode fields are implemented; modes avoid hiding open business decisions behind vague true/false flags.
- `qfu_digestenabled` and `qfu_targetedalertenabled` can remain useful as broad kill switches, but they should not replace recipient-specific mode fields.
- Phase 2 MVP quote policy defaults are `qfu_firstfollowupbasis = ImportDate` and `qfu_firstfollowupbusinessdays = 1`, meaning next business day after import for high-value quote work items. Branch holiday handling is a later flow concern and is not invented in this schema.

Relationships:

- Optional branch lookup to `qfu_branch`.
- One policy to many work items.

Alternate keys:

- `qfu_scopekey + qfu_worktype + qfu_active` is not sufficient because only one active row should exist. Enforce uniqueness with either an active-policy rule in flow/plugin validation or a key on `qfu_scopekey + qfu_worktype + qfu_name` plus an operational duplicate check.

Illustrative example only:

| `qfu_scopekey` | `qfu_worktype` | `qfu_highvaluethreshold` | `qfu_thresholdoperator` | `qfu_workitemgenerationmode` | `qfu_requiredattempts` |
| --- | --- | --- | --- | --- | --- |
| GLOBAL | Quote | `3000` | GreaterThanOrEqual | HighValueOnly | `3` |

First follow-up default for the illustrative quote policy:

| `qfu_firstfollowupbasis` | `qfu_firstfollowupbusinessdays` |
| --- | --- |
| ImportDate | `1` |

Relation to existing operational tables:

- Policies decide whether imported quote/backorder records become work items and how attempts/escalation are handled.

## `qfu_workitem`

Purpose: workflow/control layer for follow-up work. It references source records and stores owner, status, attempts, due dates, priority, and escalation state.

It must not replace `qfu_quote`, `qfu_quoteline`, or `qfu_backorder`.

| Column | Type | Required | Notes |
| --- | --- | --- | --- |
| `qfu_workitemnumber` | Text/Autonumber | Yes | Human-readable work item number |
| `qfu_worktype` | Choice | Yes | Quote, Backorder, Freight, Pickup, General |
| `qfu_sourcesystem` | Text or Choice | Yes | Source family such as SP830CA, ZBO, Freight, or Pickup; do not parse this from `qfu_sourceexternalkey` |
| `qfu_branch` | Lookup to `qfu_branch` | Yes | Branch ownership |
| `qfu_customername` | Text | No | Denormalized display value from source |
| `qfu_sourcequote` | Lookup to `qfu_quote` | No | Quote header/current-state source |
| `qfu_sourcequoteline` | Lookup to `qfu_quoteline` | No | Optional representative or line-level source |
| `qfu_sourcebackorder` | Lookup to `qfu_backorder` | No | Backorder source |
| `qfu_sourcefreightworkitem` | Lookup to `qfu_freightworkitem` | No | Freight source if table exists in target solution |
| `qfu_sourcedeliverynotpgi` | Lookup to `qfu_deliverynotpgi` | No | Delivery source if table exists in target solution |
| `qfu_sourcedocumentnumber` | Text | Yes | Quote number, sales document, invoice, etc. |
| `qfu_sourceexternalkey` | Text | Yes | Stable source key used for upsert |
| `qfu_totalvalue` | Currency/Decimal | No | Quote total is sum of all quote lines for same quote number |
| `qfu_primaryownerstaff` | Lookup to `qfu_staff` | No | Primary worker, usually TSR for quotes |
| `qfu_supportownerstaff` | Lookup to `qfu_staff` | No | Support/visibility owner, usually CSSR for quotes |
| `qfu_tsrstaff` | Lookup to `qfu_staff` | No | Explicit TSR mapping |
| `qfu_cssrstaff` | Lookup to `qfu_staff` | No | Explicit CSSR mapping |
| `qfu_requiredattempts` | Whole Number | Yes | Policy-derived |
| `qfu_completedattempts` | Whole Number | Yes | Calculated from actions or maintained by flow |
| `qfu_status` | Choice | Yes | Open, Due Today, Overdue, etc. |
| `qfu_priority` | Choice | Yes | Low, Normal, High, Critical |
| `qfu_nextfollowupon` | Date/Time or Date Only | No | Next due date |
| `qfu_lastfollowedupon` | Date/Time | No | Latest actual follow-up attempt date/time, calculated from action rows where `qfu_countsasattempt = Yes` |
| `qfu_lastactionon` | Date/Time | No | Latest action timestamp across all action rows |
| `qfu_overduesince` | Date/Time or Date Only | No | Set when work becomes overdue |
| `qfu_stickynote` | Multiline Text | No | Persistent always-visible work item / quote note shown in work and review screens |
| `qfu_stickynoteupdatedon` | Date/Time | No | When sticky note was last updated |
| `qfu_stickynoteupdatedby` | Lookup to `qfu_staff` | No | Staff member who last updated sticky note; nullable for system context |
| `qfu_escalationlevel` | Choice | Yes | None, Manager, GM, Admin |
| `qfu_policy` | Lookup to `qfu_policy` | No | Policy used when generated |
| `qfu_assignmentstatus` | Choice | Yes | Assigned, Partially Assigned, Needs TSR Assignment, etc. |
| `qfu_notes` | Multiline Text | No | Internal/admin notes; use `qfu_stickynote` for the persistent visible quote/work item note |

Phase 1.2 persistence rules:

- `qfu_stickynote` must live on `qfu_workitem`, not imported `qfu_quote`, so report refreshes do not wipe user notes.
- Import/re-import flows must not overwrite `qfu_stickynote`, `qfu_stickynoteupdatedon`, `qfu_stickynoteupdatedby`, `qfu_lastfollowedupon`, `qfu_completedattempts`, `qfu_status`, `qfu_nextfollowupon`, or owner fields unless an explicit controlled reset/reassignment process is used.
- `qfu_lastfollowedupon` is different from `qfu_lastactionon`. Notes, assignments, roadblocks, escalations, sticky note updates, and admin edits may update last action but should not automatically count as follow-up attempts.

Relationships:

- Optional source lookups to operational records.
- Staff owner lookups to `qfu_staff`.
- Policy lookup to `qfu_policy`.
- One work item to many actions.
- One work item to many alerts.
- One work item to many assignment exceptions.

Alternate keys:

- `qfu_worktype + qfu_sourceexternalkey`.
- For quotes, source external key should be stable at quote-header grain, for example `branch|SP830CA|quote|<quote-number>`.

Illustrative example only:

| `qfu_worktype` | `qfu_sourcesystem` | `qfu_sourcedocumentnumber` | `qfu_sourceexternalkey` | `qfu_totalvalue` | `qfu_assignmentstatus` |
| --- | --- | --- | --- | --- | --- |
| Quote | SP830CA | `<quote-number>` | `<branch>|SP830CA|quote|<quote-number>` | `3500` | Assigned |

Relation to existing operational tables:

- `qfu_quote` provides current quote header state.
- `qfu_quoteline` provides line-level total calculation and drill-through.
- `qfu_backorder` provides current backorder state.
- `qfu_workitem` stores follow-up workflow status only.

## `qfu_workitemaction`

Purpose: history of follow-up attempts and user actions.

| Column | Type | Required | Notes |
| --- | --- | --- | --- |
| `qfu_workitem` | Lookup to `qfu_workitem` | Yes | Parent work item |
| `qfu_actiontype` | Choice | Yes | Call, Email, Customer Advised, Vendor Contacted, etc. |
| `qfu_countsasattempt` | Yes/No | Yes | Controls whether this action contributes to `qfu_workitem.qfu_completedattempts` |
| `qfu_actionby` | Lookup to `qfu_staff` | No | Nullable for system/import actions |
| `qfu_actionon` | Date/Time | Yes | Actual date/time the action happened; label as Followed Up On for attempt actions |
| `qfu_attemptnumber` | Whole Number | No | Attempt sequence for follow-up actions |
| `qfu_outcome` | Text/Choice | No | Optional action result |
| `qfu_nextfollowupon` | Date/Time or Date Only | No | Next due date after this action |
| `qfu_notes` | Multiline Text | No | Action note |
| `qfu_relatedalert` | Lookup to `qfu_alertlog` | No | Alert that caused the action, if any |

Relationships:

- Many actions to one work item.
- Optional staff lookup.
- Optional alert lookup.

Alternate keys:

- No primary alternate key required in Phase 1.
- Optional dedupe for imported/system actions: `qfu_workitem + qfu_actiontype + qfu_actionon + qfu_actionby`.

Attempt counting:

- Later flows should calculate `qfu_workitem.qfu_completedattempts` from related `qfu_workitemaction` rows where `qfu_countsasattempt = Yes`.
- `qfu_actionon` should default to now for new manual actions, but users should be able to edit it when logging a follow-up that happened earlier.
- Any action where `qfu_countsasattempt = Yes` must require `qfu_actionon`.
- `qfu_notes` on `qfu_workitemaction` is the note for that specific action.
- `qfu_workitem.qfu_stickynote` is the persistent quote/work item note shown prominently across screens.
- `qfu_workitemaction` rows are the audit/history trail.
- `qfu_workitem.qfu_stickynote` is the current visible sticky note.

MVP attempt defaults:

| Action Type | Default `qfu_countsasattempt` |
| --- | --- |
| Call | Yes |
| Email | Yes |
| Customer Advised | Yes |
| Note | No |
| Roadblock | No |
| Escalated | No |
| Due Date Updated | No |
| Won | No |
| Lost | No |
| Cancelled | No |
| Assignment/Reassignment | No |
| Sticky Note Updated | No |

Admins can change defaults later through policy or configuration if needed, but the MVP defaults above should be used.

Illustrative example only:

| `qfu_actiontype` | `qfu_attemptnumber` | `qfu_outcome` |
| --- | --- | --- |
| Call | `1` | Left message |

Relation to existing operational tables:

- Actions are workflow history, not source import history.

## `qfu_alertlog`

Purpose: alert delivery history and duplicate prevention.

| Column | Type | Required | Notes |
| --- | --- | --- | --- |
| `qfu_workitem` | Lookup to `qfu_workitem` | No | Nullable for digest or flow-failure alerts |
| `qfu_alerttype` | Choice | Yes | New Assignment, Due Today, Overdue, etc. |
| `qfu_recipientstaff` | Lookup to `qfu_staff` | No | Nullable for raw email/system destinations |
| `qfu_recipientemail` | Email/Text | No | Final recipient email used |
| `qfu_ccemails` | Multiline Text | No | Resolved CC list at send time |
| `qfu_dedupekey` | Text | Yes | Stable alert idempotency key |
| `qfu_status` | Choice | Yes | Pending, Sent, Failed, Suppressed, Skipped |
| `qfu_senton` | Date/Time | No | Send timestamp |
| `qfu_failuremessage` | Multiline Text | No | Failure detail |
| `qfu_flowrunid` | Text | No | Flow run id for traceability |
| `qfu_notes` | Multiline Text | No | Additional context |

Relationships:

- Optional work item lookup.
- Optional staff recipient lookup.
- Referenced by work item actions when an alert causes a user action.

Alternate keys:

- `qfu_dedupekey`.

Illustrative example only:

| `qfu_alerttype` | `qfu_dedupekey` | `qfu_status` |
| --- | --- | --- |
| Daily Digest | `<date>|<branch>|<staff>|daily-digest` | Pending |

Relation to existing operational tables:

- Alerts should reference work items, which in turn reference source records.
- Do not alert directly from raw quote rows without writing a dedupe record.

## `qfu_assignmentexception`

Purpose: queue for missing or ambiguous staff mappings, missing branch, bad aliases, and unresolved ownership.

| Column | Type | Required | Notes |
| --- | --- | --- | --- |
| `qfu_exceptiontype` | Choice | Yes | Missing TSR Alias, Blank Alias, Ambiguous Alias, etc. |
| `qfu_branch` | Lookup to `qfu_branch` | No | Nullable if branch cannot be resolved |
| `qfu_sourcesystem` | Text/Choice | Yes | Example: `SP830CA` |
| `qfu_sourcefield` | Text | Yes | Example: `AM Number`, `CSSR` |
| `qfu_rawvalue` | Text | No | Source value before normalization |
| `qfu_normalizedvalue` | Text | No | Normalized candidate value |
| `qfu_displayname` | Text | No | Display name from source, not trusted for automatic routing |
| `qfu_sourcedocumentnumber` | Text | No | Quote number, sales document, etc. |
| `qfu_sourceexternalkey` | Text | No | Source work key |
| `qfu_exceptionkey` | Text | Yes | Stable idempotency key for repeated imports/errors |
| `qfu_sourcequote` | Lookup to `qfu_quote` | No | Related quote |
| `qfu_sourcequoteline` | Lookup to `qfu_quoteline` | No | Optional representative quote line for quote-line-driven resolver exceptions |
| `qfu_sourcebackorder` | Lookup to `qfu_backorder` | No | Related backorder |
| `qfu_workitem` | Lookup to `qfu_workitem` | No | Related work item |
| `qfu_status` | Choice | Yes | Open, In Review, Resolved, Ignored |
| `qfu_resolvedstaff` | Lookup to `qfu_staff` | No | Staff selected by admin/manager |
| `qfu_resolvedby` | Lookup to `systemuser` | No | User who resolved |
| `qfu_resolvedon` | Date/Time | No | Resolution timestamp |
| `qfu_notes` | Multiline Text | No | Context and resolution notes |

Relationships:

- Optional source record lookups.
- Optional work item lookup.
- Optional resolved staff lookup.

Alternate keys:

- Recommended key: `qfu_exceptionkey`.
- Suggested key value: `sourcesystem|sourcefield|normalizedvalue|sourceexternalkey|branch-scope`.
- Without this key, repeated imports can create repeated exception rows.

Illustrative example only:

| `qfu_exceptiontype` | `qfu_sourcefield` | `qfu_rawvalue` | `qfu_normalizedvalue` | `qfu_exceptionkey` | `qfu_status` |
| --- | --- | --- | --- | --- | --- |
| Zero Alias | AM Number | `0` | `0` | `<exception-key>` | Open |

Relation to existing operational tables:

- Exceptions point back to imported rows or generated work items so managers can fix mappings without losing traceability.

## Source Table Relationships

Current relationship contract:

```text
qfu_quote / qfu_quoteline / qfu_backorder
        -> source and traceability
qfu_workitem
        -> workflow state and owner assignment
qfu_workitemaction
        -> follow-up history
qfu_alertlog
        -> alert history and dedupe
qfu_assignmentexception
        -> unresolved mapping/ownership cleanup queue
```

## Confirmed SP830CA Source Fields

For quote work item generation, Phase 1 should use `qfu_quoteline` as the source for total value and staff identity resolution.

| Meaning | Field |
| --- | --- |
| Quote number | `qfu_quoteline.qfu_quotenumber` |
| Branch code | `qfu_quoteline.qfu_branchcode` |
| Quote line value | `qfu_quoteline.qfu_amount` |
| AM Number / TSR numeric alias | `qfu_quoteline.qfu_tsr` |
| AM Name / TSR display name | `qfu_quoteline.qfu_tsrname` |
| CSSR numeric alias | `qfu_quoteline.qfu_cssr` |
| CSSR display name | `qfu_quoteline.qfu_cssrname` |

`qfu_quote` remains the current-state quote header/source row. Live metadata has `qfu_tsr`, `qfu_cssr`, and `qfu_cssrname` on `qfu_quote`, but no separate `qfu_tsrname` field was found. Do not require `qfu_quote` to carry the full identity display set before Phase 1 quote work item generation can proceed from `qfu_quoteline`.

For high-value quote generation:

```text
qfu_quoteline rows grouped by branch + quote number
        -> total quote value
        -> qfu_policy threshold
        -> qfu_staffalias resolver
        -> qfu_workitem upsert
```

## Implementation Notes Before Table Creation

- Use the confirmed `qfu_quoteline` identity fields for Phase 1 quote resolver dry runs.
- Add `qfu_scopekey` to scoped tables even though it was not in the first draft prompt; it reduces duplicate/default-row risk.
- Review Dataverse alternate-key limits before building compound keys.
