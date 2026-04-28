## Freight Queue Repair - 2026-04-21

### Scope

This note records the live repair for Southern Alberta freight runtime warnings on branches `4171`, `4172`, and `4173`.

### Symptom

- Portal runtime warnings showed all three freight `qfu_ingestionbatch` rows stuck in `queued`.
- Pre-repair flow health on April 21, 2026 showed:
  - `4171` freight `queued_rawdocument_count = 3`
  - `4172` freight `queued_rawdocument_count = 2`
  - `4173` freight `queued_rawdocument_count = 2`
- Validation artifact:
  - [southern-alberta-flow-health-freight-20260421-prerepair.json](/C:/Users/smcfarlane/Desktop/WorkBench/QuoteFollowUpRegion/results/southern-alberta-flow-health-freight-20260421-prerepair.json)

### Immediate Repair

Executed the controlled queue drain:

```powershell
powershell.exe -NoProfile -File "scripts\process-freight-inbox-queue.ps1"
```

Processed freight raw documents in this repair window:

- `4171|raw|FREIGHT_REDWOOD|<GUID>`
- `4171|raw|FREIGHT_UPS_F06|<GUID>`
- `4171|raw|FREIGHT_PUROLATOR_F07|<GUID>`
- `4172|raw|FREIGHT_REDWOOD|<GUID>`
- `4172|raw|FREIGHT_PUROLATOR_F07|<GUID>`
- `4173|raw|FREIGHT_REDWOOD|<GUID>`
- `4173|raw|FREIGHT_PUROLATOR_F07|<GUID>`

Detailed row-level proof:

- [freight-repair-proof-20260421.json](/C:/Users/smcfarlane/Desktop/WorkBench/QuoteFollowUpRegion/results/freight-repair-proof-20260421.json)

### Validation

Post-repair flow health artifact:

- [southern-alberta-flow-health-freight-postrepair-20260421.json](/C:/Users/smcfarlane/Desktop/WorkBench/QuoteFollowUpRegion/results/southern-alberta-flow-health-freight-postrepair-20260421.json)

Verified post-repair state from that artifact:

- `4171` freight latest batch status: `processed`
- `4171` freight latest batch completed: `Apr 21, 2026, 2:51 p.m.`
- `4171` freight queued raw documents: `0`
- `4172` freight latest batch status: `processed`
- `4172` freight latest batch completed: `Apr 21, 2026, 2:51 p.m.`
- `4172` freight queued raw documents: `0`
- `4173` freight latest batch status: `processed`
- `4173` freight latest batch completed: `Apr 21, 2026, 2:51 p.m.`
- `4173` freight queued raw documents: `0`

### Root Cause

The freight mailbox ingress flows are still only queue writers. They create `qfu_rawdocument` and `qfu_ingestionbatch` rows with `queued` status, but the downstream freight consumer is not operating as a hosted unattended path.

Supporting evidence:

- local task health on April 21, 2026 showed the old workstation task `QFU-Freight-Inbox-Queue-Processor` is missing:
  - [local-task-health-20260421.json](/C:/Users/smcfarlane/Desktop/WorkBench/QuoteFollowUpRegion/results/local-task-health-20260421.json)

### Durable Fix Path

- Do not hide the warning while queued freight rows still exist.
- Keep this queue-drain script as an emergency backlog repair path only.
- Replace the missing downstream freight consumer with the hosted parser contract implemented on April 21, 2026 under `src/freight_parser_host`, then wire the freight ingress flows to call it directly after creating the raw/batch rows.
- Hosted implementation note:
  - [freight-hosted-parser-20260421.md](/C:/Users/smcfarlane/Desktop/WorkBench/QuoteFollowUpRegion/docs/ops/freight-hosted-parser-20260421.md)
- Revalidate the portal after hosted consumer rollout; the runtime warning logic can remain truthful if the pipeline becomes unattended end to end.
