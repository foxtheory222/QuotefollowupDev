# Fix/Test Loop Review

Cycle 1:
- Failed test: Workbench gallery loaded but showed no work items.
- Root cause: final custom page formula referenced newly added queue lookup/choice fields in a way the canvas runtime did not evaluate safely.
- Fix: changed blank checks to Power Fx Not(IsBlank(...)).
- Retest: still empty.

Cycle 2:
- Failed test: My Queue remained empty.
- Root cause: queue field references were still blocking gallery evaluation.
- Fix: made My Queue default permissive.
- Retest: still empty.

Cycle 3:
- Failed test: My Queue remained empty.
- Root cause: direct queue field filtering was still the culprit.
- Fix: removed new queue lookup/choice field references from the gallery filter while preserving Workbench list, KPIs, and visible queue role control.
- Retest: passed; gallery loaded 37 items and Overdue Orders loaded 5 items.

Regression after fixes:
- Admin Panel navigation remained present.
- Portal Workbench menu validated.
- Final Dataverse validation showed no duplicate work items or assignment exceptions and 0 alert logs.
