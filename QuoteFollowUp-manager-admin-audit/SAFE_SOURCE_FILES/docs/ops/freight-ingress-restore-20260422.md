## Freight Ingress Restore - 2026-04-22

### Scope

This note records the live freight ingress repair performed on April 22, 2026 for Southern Alberta branches `4171`, `4172`, and `4173`.

### Symptom

- Freight Ledger was not reflecting new freight intake.
- Live flow health showed all three freight ingress flows disabled.
- Live workflow rows for:
  - `4171-Freight-Inbox-Ingress`
  - `4172-Freight-Inbox-Ingress`
  - `4173-Freight-Inbox-Ingress`
  were in `Draft` state.
- The imported freight workflow definitions still contained hosted-parser placeholders:
  - `https://<set-freight-parser-host>/api/processfreightdocument`
  - `__SET_FREIGHT_HOSTED_PARSER_KEY__`
- The live draft workflows did not contain the expected queue-writer actions either, so simply enabling them would not have restored a working ingress path.

Validation artifacts:

- [southern-alberta-flow-health-freight-20260422-live.json](/C:/Users/smcfarlane/Desktop/WorkBench/QuoteFollowUpRegion/results/southern-alberta-flow-health-freight-20260422-live.json)
- direct workflow inspection confirmed `Draft` freight workflows with hosted placeholders

### Immediate Repair

Restored the last known working queue-writer freight flow definitions from the committed April 10, 2026 artifact and re-imported them live:

- source artifact: durable repo commit `83fe7e0`
- restore script used:
  - [restore-southern-alberta-freight-queuewriter-20260422.ps1](/C:/Users/smcfarlane/Desktop/WorkBench/QuoteFollowUpRegion/results/restore-southern-alberta-freight-queuewriter-20260422.ps1)

Executed:

```powershell
powershell.exe -NoProfile -File "results\restore-southern-alberta-freight-queuewriter-20260422.ps1"
```

Result:

- solution import succeeded
- workflows were re-published
- freight ingress flows returned to `Activated`
- flow health now reports `flow_enabled = true` for `4171`, `4172`, and `4173`

Post-repair proof:

- [southern-alberta-flow-health-freight-20260422-postrestore.json](/C:/Users/smcfarlane/Desktop/WorkBench/QuoteFollowUpRegion/results/southern-alberta-flow-health-freight-20260422-postrestore.json)

### Email Check

Mailbox scan performed for April 22, 2026 Inbox traffic across:

- `<EMAIL>`
- `<EMAIL>`
- `<EMAIL>`

At the time of the scan, no freight-style workbook candidates were found in the first 200 Inbox messages per mailbox.

Proof:

- [shared-mailbox-freight-candidates-20260422.json](/C:/Users/smcfarlane/Desktop/WorkBench/QuoteFollowUpRegion/results/shared-mailbox-freight-candidates-20260422.json)

### Root Cause

An unfinished hosted-parser rollout replaced the prior queue-writer freight ingress with workflow rows that were never fully deployed:

- freight workflow rows were left in `Draft`
- the hosted parser endpoint and function key were still placeholders
- the real hosted Azure Function deployment had not been completed

This left freight intake with no working unattended cloud path.

### Durable Fix Path

- Do not leave freight flows in `Draft` with placeholder hosted-parser values.
- Before reattempting hosted freight rollout, complete the Azure deployment for `src/freight_parser_host`.
- Validate the actual hosted parser URL, function key, and Dataverse auth path before importing freight flow replacements.
- Confirm imported freight workflows land in `Activated` state before retiring any known-good ingress definition.
- Keep the April 10 queue-writer artifact only as an emergency rollback path, not as the long-term target.

### Remaining Risk

- The restored live freight ingress is the old queue-writer model, not the final hosted unattended parser design.
- The local queue processor was previously observed missing, so same-day unattended freight-to-ledger completion is still not durable until the hosted parser is actually deployed.
