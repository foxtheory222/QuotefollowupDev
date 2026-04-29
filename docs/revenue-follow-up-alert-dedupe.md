# Alert Dedupe

`qfu_alertlog.qfu_dedupekey` is the duplicate-prevention field.

Verified alternate key:
- `qfu_key_alertlog_dedupekey`
- Key attribute: `qfu_dedupekey`
- Status: Active

Dedupe formats:
- Work item alert: `workitemid|alerttype|recipientstaffid|dueDate|escalationLevel|digestDate`
- Staff digest: `staffid|DailyStaffDigest|digestDate`
- Manager digest: `branchid|ManagerDigest|recipientstaffid|digestDate`
- Assignment exception digest: `branchid|AssignmentExceptionDigest|recipientstaffid|digestDate`

Dry-run result:
- First completed run reused 75 existing rows after an interrupted earlier attempt.
- Second run created 0 rows.
- Duplicate dedupe keys after validation: 0.
