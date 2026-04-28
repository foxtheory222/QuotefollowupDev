# Revenue Follow-Up Assignment Exception Validation

Phase 3.2C added a tiny controlled assignment exception test before Phase 4 UX work.

## Controlled Scope

- Environment: dev only
- Branch: 4171
- Quote groups selected: 2
- Expected exceptions: 3
- Alerts sent: 0

The selected cases covered one invalid zero TSR alias and one quote group with both TSR and CSSR blank.

## Required Exception Fields

Assignment exceptions are expected to include:

- `qfu_exceptiontype`
- `qfu_branch`
- `qfu_sourcesystem`
- `qfu_sourcefield`
- `qfu_rawvalue`
- `qfu_normalizedvalue`
- `qfu_sourcedocumentnumber`
- `qfu_sourceexternalkey`
- `qfu_sourcequote`
- `qfu_sourcequoteline` where a representative quote line exists
- `qfu_workitem`
- `qfu_status = Open` unless preserving an existing status

## Resolver Hardening

The resolver now:

- writes `BLANK` as the raw value for blank source aliases
- captures the work item id created in the same apply run
- links assignment exceptions to the work item
- links assignment exceptions to source quote headers
- uses a fallback quote-line lookup by branch and quote number when the grouped quote-line lookup misses
- preserves existing exception rows and updates them by idempotency key

## Validation Result

Final validation output:

| Check | Result |
| --- | --- |
| Assignment exceptions created on first run | 3 |
| Assignment exceptions created on second run | 0 |
| Duplicate assignment exception keys | 0 |
| Source document populated | pass |
| Source external key populated | pass |
| Source quote linked | pass |
| Source quote line linked where available | pass |
| Work item linked | pass |
| Alerts sent | 0 |

The detailed validation file is `results/phase3-2C-ux-ready-dev-data/assignment-exception-linkage-validation.csv`.
