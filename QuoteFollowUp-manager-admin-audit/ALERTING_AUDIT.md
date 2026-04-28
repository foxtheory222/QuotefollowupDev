# Alerting Audit

## Current Alerts / Notifications Found

- Stored SA1300 budget flows use shared mailbox triggers and internal flow failure/error paths. No user-facing reminder/escalation alert flow was proven from the stored workflow exports.
- Scripts and docs reference flow health checks, run history, replay helpers, and diagnostics, but not a centralized quote alerting subsystem.
- Power Pages runtime renders visible diagnostics banners for degraded or stale datasets; these are UI warnings, not delivered notifications.

## Alert Details

| Alert/Notification | Trigger condition | Recipient logic | Dynamic or hardcoded | Duplicate risk | Retry/error handling | Logged | Recommended replacement |
|---|---|---|---|---|---|---|---|
| SA1300 flow failure/internal errors | Budget target missing or connector/action failure | Flow owner/run history unless separately configured live | Not proven from repo | Medium | Flow scopes/connector defaults | Partly through run history and ingestion rows | Write failure to qfu_ingestionbatch plus qfu_alertlog; notify configured branch ops/admin group |
| Portal stale/degraded banners | Missing/failed/stale Web API datasets | Portal viewer | Dynamic UI state | Low | Runtime safe loaders | Not dedicated alert log | Keep UI warning and also persist freshness/health state in Dataverse |
| Quote follow-up reminders | Not found as exported flow | Not proven | Unknown | High if later cloned per branch | Not proven | Not found | Central alert flow keyed by quote + assignee + due date + alert type |
| Overdue escalation | Not found as exported flow | Not proven | Unknown | High | Not proven | Not found | Escalate from alert log after configurable threshold to branch manager/GM records |

## Required Export To Complete Audit

Export all live Power Automate flows that send emails, Teams messages, push notifications, approvals, or reminder messages. Include connection references and environment variables so recipient logic can be verified.