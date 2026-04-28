# Branch Workbench UX

The Branch Workbench is a simple daily operations surface, not a broad analytics dashboard.

Primary layout:
- Header with Branch Workbench title, refresh timestamp, branch/team filter, staff fallback filter, and queue role control.
- KPI cards for Due Today, Overdue, Quote Follow-Up, Missing Attempts, Roadblocks, and Assignment Issues.
- Tabs for Overdue, Due Today, My Queue, Team Stats, Quote Follow-Up, Overdue Orders, High Value, Needs Attempts, Waiting, Roadblocks, All Open, and Assignment Issues.
- Dense work item list.
- Right-side detail panel with sticky note, action buttons, and handoff controls.

Current-user filtering:
- Not assumed in Phase 5 because qfu_staff to systemuser mapping is not ready.
- Branch/team plus staff fallback filters remain the MVP path.

Queue UX:
- My Queue is the staff-first view.
- Team View is the manager/team view.
- Assignment issues are visible but should not be mixed into the clean daily queue accidentally.

Portal UX:
- Operations Hub branch navigation now labels the old Team Progress slot as Workbench.
- The portal Workbench route remains compatible with the existing branch detail runtime.
