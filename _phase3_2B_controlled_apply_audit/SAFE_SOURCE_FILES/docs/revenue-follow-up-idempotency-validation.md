# Idempotency Validation

Phase 3.2B validated idempotency by applying the same exact five-row scope twice.

## Mechanism

The resolver used the selected `pre-apply-scope-review.csv` file as an exact allowlist. Work item idempotency used the active `qfu_workitem` source key behavior:

- work type: Quote
- source external key: `SP830CA|branch|quote`

Assignment exception idempotency remained available through `qfu_exceptionkey`, although the selected clean scope did not create exceptions.

## Second Apply Result

- Work items created: 0
- Work items updated: 5
- Assignment exceptions created: 0
- Assignment exceptions updated: 0
- Alerts sent: 0
- Duplicate work item source keys: 0
- Duplicate assignment exception keys: 0

## Preservation Checks

The second apply did not blank or overwrite:

- sticky notes
- last followed-up date
- last action date
- owner lookups
- status

The selected records remained open assigned quote work items after the second apply.
