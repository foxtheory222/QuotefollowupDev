# Queue Handoff Behavior

Queue handoff moves current action ownership without changing the underlying TSR/CSSR identity fields.

Fields on qfu_workitem:
- qfu_currentqueueownerstaff: True
- qfu_currentqueuerole: True
- qfu_queueassignedon: True
- qfu_queueassignedby: True
- qfu_queuehandoffreason: True
- qfu_queuehandoffcount: True

Preserved fields:
- qfu_tsrstaff
- qfu_cssrstaff
- qfu_primaryownerstaff
- qfu_supportownerstaff
- sticky note fields
- action history
- terminal/manual status values

Escalate to TSR:
- Sets qfu_currentqueueownerstaff to qfu_tsrstaff.
- Sets qfu_currentqueuerole to TSR.
- Updates qfu_queueassignedon.
- Increments qfu_queuehandoffcount.
- Writes a non-attempt qfu_workitemaction using Assignment/Reassignment.
- Sends no alert.

Send to CSSR:
- Sets qfu_currentqueueownerstaff to qfu_cssrstaff.
- Sets qfu_currentqueuerole to CSSR.
- Updates qfu_queueassignedon.
- Increments qfu_queuehandoffcount.
- Writes a non-attempt qfu_workitemaction using Assignment/Reassignment.
- Sends no alert.

Controlled validation:
- Two controlled handoff actions were created.
- Both were non-attempt actions.
- Completed attempts were preserved.
- Alerts sent remained 0.

UI note:
- Buttons exist in the Branch Workbench detail panel.
- The final handoff validation used Dataverse API because the selected browser item was terminal and handoff buttons were disabled by design.
