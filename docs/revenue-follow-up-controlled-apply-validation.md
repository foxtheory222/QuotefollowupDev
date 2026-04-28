# Controlled Apply Validation

Phase 3.2B validation used Dataverse queries against the selected scope. Browser validation was not required for this phase because the goal was backend creation, idempotency, and no-alert proof.

## Work Item Validation

For every selected controlled work item, validation confirmed:

- `qfu_worktype = Quote`
- `qfu_sourcesystem = SP830CA`
- `qfu_sourceexternalkey` populated
- `qfu_sourcedocumentnumber` populated
- `qfu_sourcequote` lookup populated
- `qfu_sourcequoteline` lookup populated
- `qfu_totalvalue >= 3000`
- `qfu_requiredattempts = 3`
- `qfu_completedattempts = 0`
- `qfu_nextfollowupon` populated
- primary owner, support owner, TSR staff, and CSSR staff populated
- `qfu_assignmentstatus = Assigned`
- `qfu_status = Open`
- sticky note remained blank/preserved
- `qfu_lastfollowedupon` not set
- `qfu_lastactionon` not set

Validation details are in `results/phase3-2B-controlled-apply/workitem-validation.csv`.

## Assignment Exception Validation

No assignment exceptions were expected or created for the controlled scope because all selected groups had both TSR and CSSR resolved.

Validation details are in `results/phase3-2B-controlled-apply/assignment-exception-validation.csv`.

## No-Alert Validation

- Emails sent: 0
- Teams messages sent: 0
- Sent alert logs: 0
- Active alert logs: 0
- Daily digests: 0

Validation details are in `results/phase3-2B-controlled-apply/no-alert-validation.json`.

## Admin Panel Visibility

Admin Panel visibility was validated by Dataverse metadata and table queries:

- Revenue Follow-Up Workbench app found.
- Open Work Items view found.
- Quotes >= $3K view found.
- Needs TSR Assignment view found.
- Needs CSSR Assignment view found.
- Five selected work items visible by Dataverse query.

Browser UI validation was not run in this phase.
