# Flow Integration Notes

## Scope

This note records the safest current path to add quote follow-up activity and TSR escalation integration without destabilizing the existing quote import path.

Inspected source:

- `solution/QuoteFollowUpSystemUnmanaged/src/Workflows/QuoteFollow-UpImport-Staging_DEV-7742C979-E2EB-F011-8406-000D3AF4C93E.json`
- `solution/QuoteFollowUpSystemUnmanaged/src/Workflows/QFU-RecalculateQueueState_DEV-51E849CB-E1EB-F011-8406-000D3AF4C93E.json`
- `solution/QuoteFollowUpSystemUnmanaged/src/Workflows/QFU-CloseQuoteWhenAnyLineWon_DEV-DA702A80-E2EB-F011-8406-000D3AF4C93E.json`
- `solution/QuoteFollowUpSystemUnmanaged/src/Workflows/QFU-BackfillHeaderFollow-Up_DEV-EA702A80-E2EB-F011-8406-000D3AF4C93E.json`
- `solution/QuoteFollowUpSystemUnmanaged/src/Workflows/QFU-Debug-SendTestEmails_DEV-BACC0A05-6EEE-497E-8144-3E1D98418E89.json`
- `scripts/create-southern-alberta-pilot-flow-solution.ps1`
- `scripts/repair-southern-alberta-mailbox-trigger-definitions.ps1`
- `scripts/check-southern-alberta-flow-health.ps1`
- `RAW/scripts/rebind-qfu-shared-commondataserviceforapps.ps1`

## Current flow boundaries

### 1. Quote import is already the system-of-record ingress

`QuoteFollow-UpImport-Staging_DEV` is the existing mailbox-driven quote ingest. It:

- uses `qfu_shared_office365`, `qfu_shared_onedriveforbusiness`, `qfu_shared_excelonlinebusiness`, and `qfu_shared_commondataserviceforapps`
- triggers from Office 365 mail with `subjectFilter`
- upserts `qfu_quote` and `qfu_quoteline`
- writes core ownership/source fields already needed for follow-up:
  - `qfu_cssr`
  - `qfu_cssrname`
  - `qfu_tsr`
  - `qfu_tsrname`
  - `qfu_amount`
  - `qfu_status`
  - `qfu_rejectionreason`
- already closes quote headers when the import determines a closed state

This flow is the wrong place for portal-originated activity logging or escalation email logic. It is ingress-critical and already carries mailbox, Excel, OneDrive, and Dataverse dependencies.

### 2. Queue state recalculation already exists, but it is narrow

`QFU-RecalculateQueueState_DEV` currently:

- runs on recurrence, not on activity creation
- reads only `qfu_quote`
- computes `qfu_actionstate`, `qfu_expirydate`, `qfu_expiringsoon`, `qfu_overduesince`, `qfu_archivedon`
- auto-expires quotes
- creates a `qfu_activitylog` row only for auto-expire

It does not currently:

- read `qfu_activitylog` for attempt counting
- resolve TSR escalation state
- use branch-specific cadence
- use business-day logic
- use roster matching
- use notification settings

This is a candidate place to keep lifecycle classification, but not the safest place to embed the full follow-up workflow in one edit.

### 3. Auto-close logic is already separated and should stay separated

`QFU-CloseQuoteWhenAnyLineWon_DEV`:

- triggers on `qfu_quoteline` status change
- closes the header when any line is won
- writes a `qfu_activitylog` record for the auto-close
- closes sibling lines

This existing separation is good. Manual close/reopen and escalation should follow the same additive pattern instead of being grafted onto import.

### 4. Header follow-up backfill is legacy glue

`QFU-BackfillHeaderFollow-Up_DEV`:

- is manual button-triggered
- copies follow-up notes and next follow-up from line-level fields back to the quote header
- sets `qfu_followupcount`, `qfu_firsttouchedon`, and `qfu_lasttouchedon`

This is evidence that header follow-up state was historically inferred from quote-line data, not from first-class activity rows. For the new design, this flow should be treated as transitional compatibility logic, not the new integration anchor.

### 5. Email sending exists only as a debug Power Pages pattern

`QFU-Debug-SendTestEmails_DEV` is the strongest existing pattern for portal-triggered email. It already proves:

- `PowerPages` request trigger works in this solution
- caller email can be resolved from trigger headers
- roster rows can be looked up in Dataverse
- Office 365 `SendEmailV2` can be invoked from a portal-triggered flow

It is not production-ready escalation logic. It is a debug pattern with manager-only authorization and direct recipient selection.

## Safest integration path

### Recommended architecture

Keep the current ingest flows untouched for business behavior. Add follow-up behavior in new scoped flows.

#### A. Keep existing quote import and close flows intact

Do not put escalation sending, attempt counting, or portal note actions into:

- `QuoteFollow-UpImport-Staging_DEV`
- `QFU-CloseQuoteWhenAnyLineWon_DEV`

Those flows should keep owning:

- mailbox ingest
- quote/header/line refresh
- import-based won/lost state truth
- line-driven auto-close

#### B. Add a new portal-triggered escalation flow

Safest pattern:

- clone the trigger/auth shape from `QFU-Debug-SendTestEmails_DEV`
- replace debug scenario payload with a quote escalation payload
- resolve recipients from quote + roster/config
- send the email
- log one `qfu_activitylog` row
- update quote escalation fields only after send succeeds

Why this is safest:

- it reuses the only proven portal-to-flow email pattern already in source
- it avoids coupling email delivery to mailbox import
- it gives a clean dev override path before production recipient cutover

#### C. Add a separate activity-to-quote aggregation flow

Safest pattern:

- trigger on `qfu_activitylog` create/update, or run as a tightly scoped recalc flow
- update only quote follow-up fields derived from activity:
  - attempts done
  - last touched
  - next follow-up
  - waiting state
  - queue reason
  - escalation done
  - compliance state

Why this is safer than editing import:

- manual actions and import are different sources of truth
- activity-driven updates should be deterministic and replayable
- import regressions are easier to avoid when the import flow remains focused on source data ingestion

#### D. Preserve import-based close truth

Import-driven won/lost logic should remain authoritative and additive to manual actions, not replaced by them.

The existing source already expects:

- close from import status changes
- close from line-won trigger
- activity log entries for system-generated close events

Manual close/reopen should be added beside that, not instead of it.

## Connection and environment assumptions

### Current connection references in source

The quote-related flows expect embedded connection references with these logical names:

- `qfu_shared_commondataserviceforapps`
- `qfu_shared_office365`
- `qfu_shared_excelonlinebusiness`
- `qfu_shared_onedriveforbusiness`

The Southern Alberta generator script also emits those same logical names into packaged solutions.

### Existing repair and deployment tooling

Current scripts already assume flow patching and rebinding are normal:

- `scripts/create-southern-alberta-pilot-flow-solution.ps1`
  - builds solution-aware cloned flows
  - emits connection references into solution XML
  - normalizes mailbox triggers
- `scripts/repair-southern-alberta-mailbox-trigger-definitions.ps1`
  - patches trigger kind/recurrence/subject filter in-place
  - restarts flows after patch
- `scripts/check-southern-alberta-flow-health.ps1`
  - correlates admin flow enablement with latest `qfu_ingestionbatch`
- `RAW/scripts/rebind-qfu-shared-commondataserviceforapps.ps1`
  - rebinds the Dataverse connection reference

## Current blockers and traps

### 1. No production escalation flow exists yet

There is no current workflow in authoritative source that:

- takes a quote escalation request from the portal
- resolves branch mailbox + TSR + manager/GM recipients
- sends the real escalation email
- logs it back to `qfu_activitylog`

That flow must be added.

### 2. Shared mailbox send behavior is not proven in current source

The current debug email flow uses Office 365 `SendEmailV2`, but it does not prove:

- send-as the branch shared mailbox
- CC fan-out from branch config
- production mailbox permissions in the target environment

This is the main connection boundary to verify before calling escalation complete.

### 3. Roster active semantics are currently inconsistent with global conventions

The repo-level conventions document says `qfu_isactive` is inverted in this environment for some tables. But the existing debug email flow filters roster rows with:

- `qfu_isactive eq true`

That means roster active/inactive semantics are not safe to infer from the global rule alone. Any escalation or manager-resolution flow must preserve current roster behavior until it is explicitly normalized and verified.

### 4. Notification settings are not yet integrated into flow behavior

Current source inspection found no workflow using `qfu_notificationsetting`.

That means:

- branch manager/GM recipient lists are not yet being resolved through notification/config rows
- any escalation flow added now must either
  - read directly from branch/config data, or
  - explicitly become the first consumer of `qfu_notificationsetting`

This is an integration choice, not something already wired.

### 5. Current queue-state flow is calendar-day based, not business-day based

`QFU-RecalculateQueueState_DEV` currently uses numeric day parameters and date math. It does not implement:

- 1 business day
- then 2 business days later
- then 5 business days later

Business-day cadence should not be bolted into mailbox import. It needs separate logic or a dedicated calculator path.

### 6. Import subject filters and mailbox definitions are already a known repair surface

The generator and repair scripts show the shared-mailbox triggers have already needed correction for:

- trigger type
- recurrence
- subject filter
- restart behavior

Any new escalation flow should avoid dependence on those mailbox ingestion triggers. A portal-triggered flow avoids that risk.

## Recommended implementation sequence

1. Leave current import flows unchanged except for additive downstream hooks if absolutely required.
2. Add a new portal-triggered escalation flow based on the `QFU-Debug-SendTestEmails_DEV` trigger/auth pattern.
3. Add a separate quote-follow-up aggregation flow driven by `qfu_activitylog` and quote field changes.
4. Keep `QFU-RecalculateQueueState_DEV` focused on lifecycle classification unless a later pass intentionally consolidates logic.
5. Validate Office 365 send-as/shared-mailbox permissions before relying on branch mailbox send.
6. Treat roster active filtering as a flow-specific contract to verify, not an assumed inherited convention.

## Practical conclusion

The safest path is additive:

- preserve `QuoteFollow-UpImport-Staging_DEV` as import-only
- preserve `QFU-CloseQuoteWhenAnyLineWon_DEV` as close-only
- preserve `QFU-RecalculateQueueState_DEV` as lifecycle/queue classifier unless intentionally refactored later
- introduce new quote-follow-up flows for:
  - portal escalation email
  - activity-driven follow-up aggregation

That path minimizes regression risk against the existing mailbox import contract, reuses the current Power Pages email trigger pattern already in source, and isolates the real unresolved blocker: shared-mailbox send permissions and recipient/config resolution in the target environment.
