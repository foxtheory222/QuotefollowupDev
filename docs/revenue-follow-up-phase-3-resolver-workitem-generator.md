# Revenue Follow-Up Phase 3 Resolver And Work Item Generator

Date: 2026-04-27

Environment: `https://orga632edd5.crm3.dynamics.com/`

Solution: `qfu_revenuefollowupworkbench`

Current phase: Phase 3 - resolver and work item generator foundation, no alerts.

## Scope

Phase 3 creates the safe resolver foundation that sits between imported quote source data and the Revenue Follow-Up Workbench Admin Panel MVP.

In scope:

- Verify the existing Dataverse foundation, Admin Panel app, quote source tables, and branch table.
- Create or verify resolver idempotency keys.
- Create or verify a default dev Quote policy.
- Add reusable alias normalization and resolver scripts.
- Run resolver dry-run evidence against imported quote data.
- Document how admins clear assignment exceptions.

Out of scope:

- Old Power Pages ops-admin workflow changes.
- Alert sending, daily digests, and alert flow activation.
- TSR/CSSR My Work custom page.
- Manager Panel.
- GM Review.
- Security roles.
- Replacing `qfu_quote`, `qfu_quoteline`, or `qfu_backorder`.

Google Stitch remains design/prototype guidance only. The implementation target for the Admin Panel is the Power Apps model-driven app backed by Dataverse, and no frontend code was generated from Stitch for this phase.

## Resolver Behavior

The Phase 3 resolver reads imported quote source rows from `qfu_quote` and `qfu_quoteline`. It groups lines by branch and quote number, calculates the quote total from line totals when available, and falls back to the quote header amount when needed.

The resolver then selects an active Quote policy. Branch-specific policies win over scope-key matches, and scope-key matches win over the global default. The default dev policy is:

| Setting | Value |
| --- | --- |
| Work Type | Quote |
| Scope Key | GLOBAL |
| High-Value Threshold | 3000 |
| Threshold Operator | GreaterThanOrEqual |
| Work Item Generation Mode | HighValueOnly |
| Required Attempts | 3 |
| First Follow-Up Basis | ImportDate |
| First Follow-Up Business Days | 1 |
| Alert Modes | Disabled |

When policy mode is `HighValueOnly`, quotes under the configured threshold are skipped for MVP work item generation. They remain reporting-only.

## Owner Resolution

The resolver uses business identity aliases, not names and not `systemuser.employeeid`.

Primary owner resolution:

- Source field: AM Number from `qfu_tsr`
- Alias type: AM Number
- Result: TSR staff, primary owner staff

Support owner resolution:

- Source field: CSSR Number from `qfu_cssr`
- Alias type: CSSR Number
- Result: CSSR staff, support owner staff

Alias matching uses `qfu_staffalias` where source system is SP830CA, alias type matches the field, normalized alias matches, alias is active, and branch/scope is compatible. Branch lookup match has highest priority, then branch/scope key, then global alias.

AM Name and CSSR Name are display/fallback context only. They are not trusted for automatic routing unless a staff alias has been manually verified in `qfu_staffalias`.

## Alias Normalization

Reusable normalization is implemented in `scripts/Invoke-RevenueFollowUpPhase3Resolver.ps1`.

Rules:

- Trim whitespace.
- Uppercase text aliases.
- Convert Excel decimal aliases such as `7001634.0` to `7001634`.
- Preserve meaningful leading zeros when the value is non-decimal text.
- Reject blank, `0`, `00000000`, `NULL`, `N/A`, `NA`, and `NONE`.
- Prefer number aliases over name aliases.
- Do not route from names unless a verified alias row exists.

## Work Item Upsert

Qualifying high-value quotes create or update `qfu_workitem` by idempotent key:

```text
qfu_worktype + qfu_sourceexternalkey
```

The source external key format is:

```text
SP830CA|{branch code}|{quote number}
```

The resolver plans these work item values:

- `qfu_worktype = Quote`
- `qfu_sourcesystem = SP830CA`
- `qfu_branch`
- `qfu_sourcequote`
- `qfu_sourcedocumentnumber`
- `qfu_sourceexternalkey`
- `qfu_totalvalue`
- `qfu_requiredattempts`
- `qfu_completedattempts` from action rollup when available
- `qfu_nextfollowupon` as next business day after import if not already set
- `qfu_primaryownerstaff` when TSR resolves
- `qfu_supportownerstaff` when CSSR resolves
- `qfu_tsrstaff` when TSR resolves
- `qfu_cssrstaff` when CSSR resolves
- `qfu_assignmentstatus`
- `qfu_status = Open` for new/open resolver-owned rows
- `qfu_priority = High`
- `qfu_policy`

The resolver is conservative on preservation. It does not overwrite:

- `qfu_stickynote`
- `qfu_stickynoteupdatedon`
- `qfu_stickynoteupdatedby`
- `qfu_lastfollowedupon`
- `qfu_lastactionon`
- manually/action-derived `qfu_completedattempts`
- `qfu_workitemaction` history
- non-empty manual owner fields unless a later explicit reassignment mode is enabled

## Assignment Exceptions

The resolver creates idempotent exception plans for:

- Missing TSR Alias
- Missing CSSR Alias
- Blank Alias
- Zero Alias
- Ambiguous Alias
- Missing Branch
- Missing Policy

`qfu_assignmentexception` uses the text key `qfu_exceptionkey` for safe idempotency because the direct multi-column key exceeded Dataverse index size limits in this environment.

No `qfu_alertlog` rows are created in Phase 3.

## Admin Exception Workflow

Admins use the Admin Panel MVP to clear resolver exceptions.

For Missing TSR Alias:

1. Open Assignment Exceptions.
2. Filter to Missing TSR Alias.
3. Review Source Field, Raw Value, Normalized Value, Branch, Source Document Number, and Display Name.
4. Open Staff Alias Mapping.
5. Create or update an active `qfu_staffalias` row with Source System SP830CA, Alias Type AM Number, the normalized alias, scope/branch if needed, and the resolved Staff.
6. Rerun the resolver. The work item should update to the resolved TSR/primary owner without creating duplicate work items.

For Missing CSSR Alias:

1. Filter Assignment Exceptions to Missing CSSR Alias.
2. Create or update an active `qfu_staffalias` row with Source System SP830CA, Alias Type CSSR Number, normalized alias, scope/branch if needed, and Staff.
3. Rerun the resolver. The support/CSSR owner should fill where the mapping is unambiguous.

For Blank or Zero Alias:

1. Confirm the source field is actually blank, `0`, or equivalent invalid source content.
2. If the source system should have supplied a number, repair the source/import path rather than mapping a blank alias.
3. If the row is a legitimate exception, keep it open for manager review or resolve/ignore with notes.

For Missing Policy:

1. Open Branch Policies.
2. Confirm a global Quote policy exists and is active, or create a branch/scope-specific Quote policy.
3. Use mode fields, not alert-sending flags, for any future alert behavior.
4. Rerun the resolver.

For Missing Branch:

1. Confirm `qfu_branch` has the required branch code or branch slug.
2. Confirm source quote rows carry the expected branch code/slug.
3. Repair branch source data or branch setup, then rerun.

## Work Item Action Rollup

The resolver dry-run calculates rollup expectations for existing actions, but no server-side rollup flow or plugin was activated in Phase 3.

Target behavior for a later automation phase:

- `qfu_completedattempts` equals the count of related `qfu_workitemaction` rows where `qfu_countsasattempt = true`.
- `qfu_lastfollowedupon` equals the maximum `qfu_actionon` where `qfu_countsasattempt = true`.
- `qfu_lastactionon` equals the maximum `qfu_actionon` across all related actions.

Phase 3 does not claim this rollup is live automation.

## Dry-Run Result

The corrected Phase 3 dry-run scanned the dev environment without applying work item or assignment exception writes.

| Metric | Count |
| --- | ---: |
| Quote source records scanned | 521 |
| Quote line records scanned | 1559 |
| Quote groups found | 521 |
| Quote groups at or above threshold | 109 |
| Work items that would be created | 109 |
| Work items that would be updated | 0 |
| Low-value quote groups skipped | 412 |
| TSR aliases resolved | 0 |
| CSSR aliases resolved | 0 |
| TSR exceptions planned | 109 |
| CSSR exceptions planned | 109 |
| Missing branch exceptions | 0 |
| Missing policy exceptions | 0 |
| Assignment exceptions that would be created | 218 |
| Alerts sent | 0 |

The dry-run report intentionally sanitizes samples by hashing source document values and excluding customer names.

## Apply Mode

Apply mode exists in the resolver script but was not run for Phase 3. It requires `-Mode Apply -ConfirmApply` and should be limited to dev-only, controlled branch or sample scopes until alias mapping and manager exception review are ready.

## Source Files

- `scripts/Initialize-RevenueFollowUpPhase3Foundation.ps1`
- `scripts/Invoke-RevenueFollowUpPhase3Resolver.ps1`
- `results/phase3-foundation-20260427.json`
- `results/phase3-resolver-dryrun-20260427.json`
- `results/phase3-resolver-dryrun-20260427.md`
