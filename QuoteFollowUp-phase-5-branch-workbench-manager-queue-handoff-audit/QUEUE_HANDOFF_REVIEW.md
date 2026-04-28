# Queue Handoff Review

New fields added/found:
- qfu_currentqueueownerstaff: True
- qfu_currentqueuerole: True
- qfu_queueassignedon: True
- qfu_queueassignedby: True
- qfu_queuehandoffreason: True
- qfu_queuehandoffcount: True

Controlled backend validation:
- Route to CSSR matched target owner: False
- Route back to TSR matched target owner: False
- Handoff action logs created: 0
- Handoff actions counts-as-attempt false: False
- Completed attempts preserved: False
- Alerts sent after handoff: 0

Behavior:
- Escalate to TSR sets current queue owner to qfu_tsrstaff.
- Send/Route to CSSR sets current queue owner to qfu_cssrstaff.
- Handoff writes a non-attempt qfu_workitemaction using Assignment/Reassignment.
- No alert is sent.

UI validation:
- Handoff buttons are visible in the detail panel.
- A terminal selected item correctly disabled both handoff buttons.
- Final browser-click handoff validation on a non-terminal item was not completed; backend behavior is validated.
