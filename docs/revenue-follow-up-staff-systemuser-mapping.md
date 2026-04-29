# Staff to Systemuser Mapping

Phase 7 mapping rules:
- Exact staff email to active `systemuser.internalemailaddress` or `domainname` can be auto-linked.
- Exact Entra object id can be auto-linked.
- Exact staff number to populated `systemuser.employeeid` can be auto-linked.
- Name-only matches are candidates only and are not production-verified.
- Fuzzy names and guessed emails are not allowed.

Phase 7 result:
- Active staff: 19.
- Active staff linked to systemuser: 1.
- Active staff with primary email: 1.
- Active staff still missing systemuser: 18.
- Active staff still missing email: 18.
- Exact production matches applied: 0.
- Dev-only current-maker mapping applied: 1.

Evidence:
- `results/phase7/systemuser-readiness.csv`
- `results/phase7/staff-systemuser-match-review.csv`
- `results/phase7/staff-identity-updates.csv`

Production next step:
Load a human-verified staff identity roster with staff number, primary email, and either systemuser/email or Entra object id.
