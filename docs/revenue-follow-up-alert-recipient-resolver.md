# Alert Recipient Resolver

Recipient resolution is policy-driven and does not guess emails.

Resolver order for work item alerts:
- Current queue owner staff.
- TSR staff fallback for quote work.
- CSSR staff fallback when CSSR routing/visibility applies.
- Branch Manager membership for escalation/digest.
- Branch GM membership only when policy enables it.
- Admin membership for configuration/failure review when available.

Validation state:
- Active staff: 19.
- Active staff with primary email: 0.
- Active staff missing primary email: 19.
- Manager memberships: 0.
- GM memberships: 0.
- Admin memberships: 0.

Behavior:
- Missing recipient staff or email creates a skipped `qfu_alertlog`.
- No blank email is sent.
- No hardcoded managers, GMs, admins, or staff emails are used.

Evidence:
- `results/phase6/staff-email-readiness.csv`
- `results/phase6/missing-recipient-email-review.csv`
- `results/phase6/recipient-resolver-dry-run.csv`
