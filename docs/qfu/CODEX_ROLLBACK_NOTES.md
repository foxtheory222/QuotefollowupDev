# QFU Codex Rollback Notes

Updated: 2026-04-13 America/Edmonton

## Scope Covered

These rollback notes cover only the changes actually implemented in this run:

- the Ready-to-Ship runtime hardening in [QFU-Regional-Runtime.webtemplate.source.html](C:\Dev\QuoteFollowUpComplete\site\web-templates\qfu-regional-runtime\QFU-Regional-Runtime.webtemplate.source.html)
- documentation updates under [docs/qfu](C:\Dev\QuoteFollowUpComplete\docs\qfu)

No Dataverse schema, flow, or model-driven app changes were implemented in this run.

## Runtime Rollback

### File

- [QFU-Regional-Runtime.webtemplate.source.html](C:\Dev\QuoteFollowUpComplete\site\web-templates\qfu-regional-runtime\QFU-Regional-Runtime.webtemplate.source.html)

### Changes covered

- Ready-to-Ship consumers now use `readyToShip.hasData`
- duplicate dead branch-home Ready-to-Ship functions were removed
- deployed runtime distinguishes:
  - `Dispatch snapshot pending`
  - `No Active Live Orders`

### Safe rollback steps

1. Restore the prior runtime file from git history or the last known-good commit.
2. Copy the restored runtime into:
   - [powerpages-upload-dev/quotefollowup/quotefollowup---quotefollowup/web-templates/qfu-regional-runtime](C:\Dev\QuoteFollowUpComplete\powerpages-upload-dev\quotefollowup\quotefollowup---quotefollowup\web-templates\qfu-regional-runtime)
3. Re-upload the dev site with:
   - `pac pages upload --environment https://orgad610d2c.crm3.dynamics.com/ --path C:\Dev\QuoteFollowUpComplete\powerpages-upload-dev\quotefollowup\quotefollowup---quotefollowup --modelVersion 2 --forceUploadAll`
4. Re-download the dev site and confirm the expected prior runtime markers are back.

## Documentation Rollback

- Files under [docs/qfu](C:\Dev\QuoteFollowUpComplete\docs\qfu) are local run artifacts.
- They can be edited or removed without changing runtime behavior.
