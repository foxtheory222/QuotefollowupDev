# Phase 6 Blockers And Limits

Blocking live/test send activation:
- No active staff have `qfu_primaryemail` populated.
- Manager, GM, and Admin branch memberships are not configured.
- No verified test recipient was provided for `TestRecipientOnly`.

Intentional deferrals:
- Live alert sends.
- Live daily digests.
- Teams messages.
- Production security and staff-to-systemuser mapping.
- Final production recipient policy activation.

No external blocker prevented dry-run validation.

Smallest next administrative action:
Populate verified dev/test recipient data first, then run `TestRecipientOnly` with a single targeted alert and one digest before any live mode is considered.
