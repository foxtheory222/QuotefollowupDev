# Non-Implemented

## Intentionally not implemented in this pass

### No live deployment

- Source changes were made only in authoritative current files.
- No Power Pages upload, flow import, or live Dataverse mutation was performed.

### No security tightening

- Security/table-permission hardening was out of scope for this pass.

### No schema renames

- `qfu_isactive` remains inverted and unchanged at the schema level.

### No new delivery-not-PGI base writer

- This pass explicitly did not create a new `qfu_deliverynotpgi` base-row ingestion path.
- Only stale-data diagnostics and documentation were added around the current reader/comment role.

### No destructive duplicate cleanup

- Live duplicate or inactive rows in Dataverse were not deactivated or deleted.
- The new budget scripts are dry-run/reporting only in this pass.

### No authoritative existing normalize script to modify

- The repo did not contain a current `RAW/scripts/normalize-live-sa1300-current-budgets.ps1`.
- A new current dry-run normalization helper was created instead.
- Because there was no authoritative predecessor in-repo, â€œpreserve behavior otherwiseâ€ could only be satisfied by documenting the gap and creating a minimal current helper rather than editing a missing file.

### No allow-list trimming

- `qfu_quoteline` and other extra allow-list fields were not trimmed in this pass.
- The lint script reports extra allow-list fields, but reliability took priority over cosmetic reduction.

### No browser automation verification

- Browser smoke tests were not run in this pass.
- A manual checklist is included in `VERIFICATION/browser-tests-not-run.md`.
