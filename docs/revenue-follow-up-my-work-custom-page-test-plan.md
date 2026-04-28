# My Work Custom Page Test Plan

## Browser Tests
- Open Revenue Follow-Up Workbench in dev.
- Confirm My Work appears in navigation.
- Open My Work and verify active work items load.
- Verify branch/team filter and staff filter are visible.
- Verify KPI cards against Dataverse counts.
- Verify tabs: Overdue, Due Today, High Value, Needs Attempts, Roadblocks, Assignment Issues.
- Select a work item and confirm the detail panel opens.
- Save sticky note marker `PHASE4B_UI_TEST_STICKY_NOTE`.
- Log Call marker `PHASE4B_UI_TEST_LOG_CALL`.
- Log Email marker `PHASE4B_UI_TEST_LOG_EMAIL`.
- Log non-attempt Note marker `PHASE4B_UI_TEST_NOTE_BLANK_ACTIONON`.
- Validate Roadblock requires notes and then saves marker `PHASE4B_UI_TEST_ROADBLOCK`.
- Set Next Follow-Up marker `PHASE4B_UI_TEST_NEXT_FOLLOWUP_V4`.
- Mark a dev item Lost using marker `PHASE4B_UI_TEST_LOST`.

## Dataverse Regression Tests
- Confirm sent alert logs remain zero.
- Confirm active alert logs remain zero.
- Confirm no duplicate work item source keys.
- Confirm no duplicate assignment exception composite keys.
- Confirm Admin Panel navigation still opens Staff, Staff Alias Mapping, Work Items, and Assignment Exceptions.

