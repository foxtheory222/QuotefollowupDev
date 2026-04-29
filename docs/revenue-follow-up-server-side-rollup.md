# Server-Side Rollup

Flow name: `QFU Work Item Action Rollup - Phase 5`

Implementation type:
Solution-aware Power Automate cloud flow.

Trigger:
Dataverse `qfu_workitemaction` create/update.

Fields updated:
- `qfu_completedattempts`
- `qfu_lastfollowedupon`
- `qfu_lastactionon`

Final fix validation:
- Created an action outside the custom page.
- `qfu_completedattempts` updated to match count of attempt actions.
- `qfu_lastfollowedupon` updated from attempt actions only.
- `qfu_lastactionon` updated from latest action.
- Sticky note was preserved.
- No alerts were sent.

Handoff interaction:
- Handoff actions use `qfu_countsasattempt = false`.
- Handoff actions do not increment completed attempts.
- Handoff actions do not change Last Followed Up On.
- Handoff actions may update Last Action On.

Known limitation:
The flow does not yet implement every ideal status and next-follow-up preservation rule. It is sufficient for Phase 5 rollup acceptance but should be hardened further before alert/escalation phases.
