# OperationsCenter Flow Autonomy Unblock - 2026-04-28

## Scope

Target portal:

- `https://operationscenter.powerappsportals.com/`

Target Dataverse environment:

- `https://orga632edd5.crm3.dynamics.com/`

This is the production-candidate copy of the Operations Hub site. The goal is for it to run autonomously like the current `operationhub.powerappsportals.com` source site.

## Finding

The Power Pages site and copied Dataverse rows are present, but the imported Power Automate cloud flows did not run because they are not active in the target environment.

Live checks on 2026-04-28 showed:

- Target environment has 29 cloud-flow workflow rows.
- Target active cloud flows: 0.
- Target draft/stopped cloud flows: 29.
- User connector connections visible to the current account in the target environment: 0.
- Imported connection reference rows exist for Office 365 Outlook, Dataverse, Excel Online, OneDrive, and Content Conversion, but the solution flows are not authenticated/saved against real target-environment connections.
- Follow-up connection-reference checks showed the source production environment has bound connection IDs on the same connection reference logical names, while the target `operationscenter` environment has blank `connectionid` values for those same references.
- `pac connection list --environment https://orga632edd5.crm3.dynamics.com/` returned no user connections in the target environment for the current account.

The copied operational data is present but is a point-in-time copy from 2026-04-27, not a fresh autonomous run on 2026-04-28. Current target table counts observed during the check:

| Table | Count | Latest Modified |
|---|---:|---|
| `qfu_region` | 3 | 2026-04-27 17:00 |
| `qfu_branch` | 3 | 2026-04-27 17:00 |
| `qfu_sourcefeed` | 24 | 2026-04-27 17:00 |
| `qfu_ingestionbatch` | 127 | 2026-04-27 17:00 |
| `qfu_quote` | 1130 | 2026-04-27 17:01 |
| `qfu_quoteline` | 1559 | 2026-04-27 17:01 |
| `qfu_backorder` | 3607 | 2026-04-27 17:03 |
| `qfu_deliverynotpgi` | 1655 | 2026-04-27 17:03 |
| `qfu_freightworkitem` | 397 | 2026-04-27 17:04 |
| `qfu_marginexception` | 196 | 2026-04-27 17:03 |
| `qfu_lateorderexception` | 349 | 2026-04-27 17:04 |

## Activation Attempt

Codex attempted to enable the operational flow set only:

- Quote import flows for branches 4171, 4172, 4173
- Backorder R2 flows for branches 4171, 4172, 4173
- SA1300 budget flows for branches 4171, 4172, 4173
- GL060 inbox ingress flows for branches 4171, 4172, 4173
- Freight inbox ingress flows for branches 4171, 4172, 4173
- `QFU-Freight-Archive-Workitems`

Legacy, temp, and diagnostic flows were intentionally left disabled to avoid overlapping writers.

Power Automate returned this exact blocker when enabling `4171-QuoteFollowUp-Import-Staging`:

```text
CannotStartUnpublishedSolutionFlow
An unpublished solution flow cannot be activated. Please authenticate the flow connections and save the flow to enable activation.
```

This is a connector authentication/save blocker. It is not a portal rendering issue and not a Dataverse table-copy issue.

The connector definitions are the same, but the actual connection instances are environment-scoped. Production connection IDs cannot be copied directly into the dev/production-candidate environment. A direct patch attempt against the target connection reference failed with:

```text
ConnectionNotFound
Could not find connection '...' for API 'shared_office365'
```

That confirms the target environment needs its own authenticated connection instances and a flow save/publish step.

## Production Freight Queue Repair

Current production:

- Power Pages: `https://operationhub.powerappsportals.com/`
- Dataverse: `https://regionaloperationshub.crm.dynamics.com/`

The production portal showed queued freight import warnings for 4171, 4172, and 4173. Backend validation found three queued `FREIGHT_REDWOOD` raw documents. Codex drained the queued freight documents with the existing freight queue processor against the production Dataverse environment.

Post-repair validation on 2026-04-28 showed:

| Branch | Latest Freight Batch Status | Inserted | Updated |
|---|---|---:|---:|
| 4171 | `processed` | 6 | 0 |
| 4172 | `processed` | 10 | 0 |
| 4173 | `processed` | 0 | 0 |

Queued freight raw documents after repair: `0`.

Evidence:

- `results/operationscenter-flow-autonomy-20260428/production-freight-queue-drain-20260428-summary.json`
- `results/operationscenter-flow-autonomy-20260428/production-freight-post-drain-validation.json`

This clears the current production `freight-import-status` queued condition in Dataverse. The durable fix is still to keep the hosted freight parser/queue processor autonomous so new queued freight raw documents do not sit unprocessed.

## Smallest Human Action Needed

In the target environment, a maker/admin must authenticate the imported solution flow connections and save the flows once.

Recommended path:

1. Open Power Automate or Maker Portal.
2. Switch environment to `Applied Canada Operations` / `orga632edd5.crm3.dynamics.com`.
3. Open the imported solution flow `4171-QuoteFollowUp-Import-Staging`.
4. Resolve the connection prompts for:
   - Office 365 Outlook
   - Microsoft Dataverse
   - Excel Online (Business)
   - OneDrive for Business
   - Content Conversion, if prompted by flows that use it
5. Save the flow.
6. Repeat or use the same authenticated connection references across the imported operational flows.
7. Run the retry script:

```powershell
.\scripts\enable-operationscenter-operational-flows.ps1
```

The retry script enables only the operational flow set and reports any remaining activation failures.

If the flow editor still reports unpublished connection references, open the flow, select the target environment `Applied Canada Operations`, fix each connection prompt, save, and then retry the script. Do not enable legacy/temp/diagnostic flows while doing this; only the operational flow set should be activated.

## Validation After Unblock

After the connection/authentication save step and the retry script:

1. Confirm operational flows show enabled in Power Automate.
2. Confirm `workflow.statecode = 1` / activated for the enabled operational flows.
3. Send or wait for the next real branch mailbox reports.
4. Confirm new `qfu_ingestionbatch` rows are written in the target environment.
5. Confirm `qfu_quote`, `qfu_backorder`, `qfu_deliverynotpgi`, `qfu_marginexception`, `qfu_lateorderexception`, and `qfu_freightworkitem` get fresh `modifiedon`/`last seen` evidence.
6. Confirm the OperationsCenter portal freshness labels move forward from the copied 2026-04-27 data.

## Artifacts

Generated evidence is under:

- `results/operationscenter-flow-autonomy-20260428/`

Key files:

- `dev-prod-flow-data-recheck.json`
- `dev-flow-summary.json`
- `dev-qfu-table-counts.json`
- `dev-latest-ingestionbatches.json`
- `enable-operational-flows-result.json`
- `enable-operational-flows-retry.json`
- `enable-operational-flows-after-browser-open.json`
- `dev-connectionreferences-with-connectionid.json`
- `prod-connectionreferences-with-connectionid.json`
- `production-freight-queue-drain-20260428-summary.json`
- `production-freight-post-drain-validation.json`

## What Was Not Changed

- No old Power Pages ops-admin workflow was modified.
- No broad resolver apply was run.
- No production source flow was changed.
- No legacy/diagnostic/temp flow was enabled in the target environment.
- No customer data was added to this document.
