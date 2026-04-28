# Provisional Bootstrap Review

| Result | Count |
| --- | ---: |
| Quote headers scanned | 1130 |
| Quote lines scanned | 1559 |
| Distinct valid staff numbers found | 19 |
| Provisional staff created by completed bootstrap run | 19 |
| Net active provisional staff after cleanup | 19 |
| Provisional aliases created | 39 |
| Provisional branch memberships created | 39 |
| Mappings skipped because invalid | 6 |
| Mappings skipped because conflicting | 0 |
| Emails guessed | 0 |
| System users guessed | 0 |
| Entra IDs guessed | 0 |

The bootstrap created provisional records only from valid report number/name pairs. It did not use names alone for routing.

An orphan duplicate staff row was created during the initial lookup-bind failure and then deactivated after confirming it had no alias or membership references. Cleanup details are in SAFE_SOURCE_FILES/results/phase3-2A-revised/orphan-duplicate-cleanup.json.
