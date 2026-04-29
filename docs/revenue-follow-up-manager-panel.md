# Manager Panel

Manager Panel is visible in dev navigation and can reuse Workbench Team View as the simple manager experience.

Validated behavior:
- Manager Panel navigation exists.
- Team View is available in Workbench.
- Team Stats section is available.
- Counts by queue role are backed by Dataverse helper fields.

Production role-aware access remains deferred until qfu_staff is mapped to Dataverse systemuser records. No users were hardcoded.
