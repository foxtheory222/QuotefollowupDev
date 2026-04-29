# Queue Handoff Flow

Flow name: `QFU Queue Handoff - Workbench`

Implementation type:
Solution-aware Power Automate cloud flow.

Trigger:
Dataverse `qfu_workitemaction` create/update where:
- `qfu_actiontype = Assignment/Reassignment`
- `qfu_outcome = TSR` or `CSSR`

Reason for this trigger:
Direct Power Fx patching of queue lookup/choice fields failed browser validation. The Workbench now creates a non-attempt handoff action row, and the server-side flow owns the queue owner update.

Flow behavior:
- Loads the parent `qfu_workitem`.
- Resolves target staff from `qfu_tsrstaff` or `qfu_cssrstaff`.
- Skips terminal work items.
- Updates `qfu_currentqueueownerstaff`.
- Updates `qfu_currentqueuerole`.
- Updates helper text fields.
- Updates queue assigned timestamp and handoff reason/count.
- Sends no alert.

Validation:
Controlled Dataverse validation passed for both TSR and CSSR routing.

Limitations:
The requested Power Apps V2 instant-trigger binding was not completed because safely adding a new flow data source into the existing packed custom page was not available through PAC in this session. The implemented server-side flow still removes queue writes from direct Power Fx and validates the same business behavior.
