# Escalation Rules

Phase 6 escalation candidates are driven by `qfu_policy`.

Policy fields used:
- `qfu_escalateafterbusinessdays`
- `qfu_gmccmode`
- `qfu_managerccmode`
- `qfu_cssralertmode`
- `qfu_requiredattempts`
- `qfu_highvaluethreshold`
- `qfu_alertmode`

Candidate rules:
- Overdue work items.
- Roadblocks.
- Missing attempts.
- Assignment issues.
- Open assignment exceptions.

Current dry-run result:
- Escalation candidates: 36.
- Sent escalations: 0.
- Skipped escalations: all, because Manager recipient membership/email is not configured.

Escalation actions do not change sticky notes, owners, work item source rows, or attempt counts.
