## Freight Queue Repair - 2026-04-20

### Scope

This note records the live repair for freight runtime warnings on Southern Alberta branches `4171` and `4172`.

### Symptom

- Portal runtime warnings showed freight `qfu_ingestionbatch` rows stuck in `queued`.
- As of April 20, 2026, live Dataverse showed:
  - `4171` freight `queued_rawdocument_count = 2`
  - `4172` freight `queued_rawdocument_count = 1`
- The freight inbox ingress flows were enabled, but the queued freight raw documents were not being consumed.

### Immediate Repair

Executed the controlled queue drain:

```powershell
powershell.exe -NoProfile -File "scripts\process-freight-inbox-queue.ps1"
```

Observed processed source ids:

- `4172|raw|FREIGHT_LOOMIS_F15|<GUID>`
  `Loomis Invoices Report [F15] by control# [APICAPIC1098] 42204594.xls`
  `input_rows=1`, `normalized_records=1`, `inserted=1`
- `4171|raw|FREIGHT_LOOMIS_F15|<GUID>`
  `Loomis Invoices Report [F15] by control# [APICAPIC1098] 42200176.xls`
  `input_rows=1`, `normalized_records=1`, `inserted=1`
- `4171|raw|FREIGHT_LOOMIS_F15|<GUID>`
  `Loomis Invoices Report [F15] by control# [APICAPIC1098] G67703.xls`
  `input_rows=2`, `normalized_records=2`, `inserted=2`

### Validation

Validation artifact:

- [southern-alberta-flow-health-freight-4171-4172-postrepair-20260420.json](/C:/Users/smcfarlane/Desktop/WorkBench/QuoteFollowUpRegion/results/southern-alberta-flow-health-freight-4171-4172-postrepair-20260420.json)

Verified post-repair state from that artifact:

- `4171` freight latest batch status: `processed`
- `4171` freight latest batch completed: `Apr 20, 2026, 2:23 p.m.`
- `4171` freight queued raw documents: `0`
- `4172` freight latest batch status: `processed`
- `4172` freight latest batch completed: `Apr 20, 2026, 2:22 p.m.`
- `4172` freight queued raw documents: `0`

### Root Cause

The freight mailbox ingress flow is only a queue writer. It creates `qfu_rawdocument` and `qfu_ingestionbatch` rows with `queued` status for legacy freight workbooks, but the downstream consumer was not active when this incident occurred.

### Durable Fix Path

- Do not rely on an unattended workstation scheduled task as the production consumer.
- Keep the current narrow repair path for emergency backlog drains only.
- Replace the missing freight queue consumer with an approved hosted downstream processor so freight normalization is no longer dependent on local task state.
- Keep the runtime warning logic truthful: suppressing the warning without clearing the queue would hide a real ingestion defect.

### Related Runtime Note

Earlier on April 20, 2026, the regional runtime was also patched so freight warning timestamps use the queued batch's own timestamp instead of borrowing the previous successful freight batch timestamp. That change fixed misleading dates, but it did not clear the real queued condition described in this note.
