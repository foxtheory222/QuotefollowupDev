# Phase 3.2B Controlled Apply

Phase 3.2B ran a controlled dev-only resolver apply against a five-quote scope.

## Scope Selected

- Environment: `https://orga632edd5.crm3.dynamics.com/`
- Branch: `4171`
- Scope size: 5 quote groups
- Selection reason: branch `4171` had at least 5 high-value quote groups where both TSR and CSSR aliases resolved.
- Expected exceptions: 0
- Expected alerts: 0

The exact scope was written to `results/phase3-2B-controlled-apply/pre-apply-scope-review.csv` and reused for dry-run, first apply, and second apply.

## Pre-Apply Dry Run

- Quote groups found: 5
- Quote groups at or above $3,000: 5
- Work items that would be created: 5
- Work items that would be updated: 0
- TSR aliases resolved: 5
- CSSR aliases resolved: 5
- Assignment exceptions that would be created: 0
- Alerts sent: 0

## Apply Result

The corrected first completed apply created or updated only records inside the selected scope:

- Work items created: 4
- Work items updated: 1
- Assignment exceptions created: 0
- Assignment exceptions updated: 0
- Alerts sent: 0

One scoped work item had been created during an earlier guarded retry before the clean-scope empty-exception guard stopped the run. The corrected run updated that scoped row and created the remaining four. No broad apply was run.

## Idempotency Result

The same scope was applied a second time:

- Work items created: 0
- Work items updated: 5
- Assignment exceptions created: 0
- Assignment exceptions updated: 0
- Alerts sent: 0
- Duplicate work item source keys: 0

## Broad Apply Status

Broad apply remains deferred. Phase 3.2B proves that a small clean scope can create work items idempotently without alerts. It does not approve creating all 109 high-value work items yet.
