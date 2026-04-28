# Log Follow-Up Behavior

## Modal Fields
- Action Type is set by the quick action button.
- Followed Up On defaults to the current time and can be edited.
- Follow-Up Notes captures per-action notes.
- Outcome is optional.
- Next Follow-Up On is optional.
- Counts As Attempt displays Yes for Call, Email, and Customer Advised; otherwise No.

## Save Behavior
Saving creates a `qfu_workitemaction` row and patches the selected `qfu_workitem`.

Attempt actions:
- Call
- Email
- Customer Advised

Non-attempt actions:
- Note
- Roadblock
- Escalated
- Due Date Updated
- Won
- Lost
- Cancelled
- Assignment/Reassignment
- Sticky Note Updated

## Validation
- Roadblock requires notes.
- Attempt actions require Followed Up On.
- Next Follow-Up On cannot be before Followed Up On.
- Won and Lost set terminal statuses.

