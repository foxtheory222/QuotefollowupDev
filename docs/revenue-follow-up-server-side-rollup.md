# Server-Side Rollup

Phase 5 attempted to identify a safe automated path for server-side rollup.

Required behavior:
- When qfu_workitemaction is created or updated, recalculate qfu_completedattempts.
- Update qfu_lastfollowedupon from attempt actions.
- Update qfu_lastactionon from all actions.
- Respect terminal/manual statuses.
- Do not overwrite sticky notes or owners.
- Send no alerts.

Current implementation:
- App-side rollup remains active in the Branch Workbench custom page for actions saved through the page.

Blocker:
- PAC in this session did not expose a supported cloud-flow creation command.
- dotnet/plugin build tooling was not installed, so a Dataverse plugin could not be safely built and registered.
- Creating fragile raw flow metadata was intentionally avoided.

Status:
- Server-side rollup is deferred and must be implemented before relying on qfu_workitemaction rows created outside the custom page.
