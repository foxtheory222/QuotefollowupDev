# Log Follow-Up UX Review

The Log Follow-Up modal should be compact and optimized for repeated use.

Fields:

- Action Type
- Followed Up On
- Counts As Attempt
- Outcome
- Follow-Up Notes
- Next Follow-Up On

Defaults:

- Call, Email, and Customer Advised count as attempts by default.
- Note, Roadblock, Escalated, Due Date Updated, Won, Lost, Cancelled, and Sticky Note Updated do not count as attempts by default.

Validation:

- Followed Up On is required when Counts As Attempt is Yes.
- Roadblock requires notes.
- Closing actions should set terminal status.
- Next Follow-Up On before Followed Up On should warn.

Save creates a `qfu_workitemaction` row. Completed attempts and last-followed-up rollups are not live yet.
