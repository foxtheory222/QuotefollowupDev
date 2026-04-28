# Action Rollup Behavior

## Implemented in Phase 4B
Rollup is implemented app-side in the My Work custom page save path.

When a follow-up action is saved from My Work:
- `qfu_completedattempts` increments only for attempt actions.
- `qfu_lastfollowedupon` updates only for attempt actions.
- `qfu_lastactionon` updates for all saved actions.
- `qfu_nextfollowupon` updates when the action provides a next follow-up date.
- Roadblock, Escalated, Closed Won, Closed Lost, Cancelled, Waiting on Customer, and Waiting on Vendor statuses are preserved during next-follow-up updates.

## Limitation
No server-side rollup flow/plugin was created in Phase 4B. Actions created outside My Work will not automatically roll up until a server-side rollup is added.

