## GL060 Mailbox Ingress Hardening - 2026-04-20

### Scope

This note records the live repair and validation work for Southern Alberta GL060 mailbox ingress after the user reported that monthly GL060 mail should trigger automatically for every branch.

This pass was limited to the mailbox ingress layer:

- `4171-GL060-Inbox-Ingress`
- `4172-GL060-Inbox-Ingress`
- `4173-GL060-Inbox-Ingress`

It does not claim that the downstream GL060 queue consumer is now hosted or unattended. That remains a separate production gap.

### Shared Defect Repaired

The live GL060 ingress flows were missing key trigger and audit contract fields even after the April 14, 2026 normalization:

- `subjectFilter` was blank
- `hasAttachments` was missing
- `qfu_receivedon` and `qfu_startedon` were using `utcNow()` instead of mailbox `receivedDateTime`
- `qfu_processingnotes` and `qfu_notes` were not carrying mailbox subject, `InternetMessageId`, or received timestamp

That meant the flows were not enforcing the intended GL060 subject gate and were not preserving enough mailbox evidence to prove what had arrived.

### Live Repair

Patched the three live GL060 workflow `clientdata` rows directly through Dataverse XRM using:

- [scripts/repair-live-gl060-mailbox-ingress-xrm.ps1](/C:/Users/smcfarlane/Desktop/WorkBench/QuoteFollowUpRegion/scripts/repair-live-gl060-mailbox-ingress-xrm.ps1)

The repair now forces all three live GL060 ingress flows to use:

- shared mailbox trigger `SharedMailboxOnNewEmailV2`
- folder `Inbox`
- recurrence `1 Minute`
- `subjectFilter = GL060 P&L report`
- `hasAttachments = true`
- `includeAttachments = true`
- `qfu_receivedon = trigger receivedDateTime`
- `qfu_startedon = trigger receivedDateTime`
- audit notes with subject, `InternetMessageId`, and received timestamp

Live repair artifact:

- [gl060-live-mailbox-ingress-xrm-repair-20260420.json](/C:/Users/smcfarlane/Desktop/WorkBench/QuoteFollowUpRegion/results/gl060-live-mailbox-ingress-xrm-repair-20260420.json)

Full before/after workflow JSON backups:

- [results/gl060-live-mailbox-ingress-xrm-repair-20260420](/C:/Users/smcfarlane/Desktop/WorkBench/QuoteFollowUpRegion/results/gl060-live-mailbox-ingress-xrm-repair-20260420)

### Validation

#### Local Contract Validation

- `python -m unittest tests.test_gl060_ingress_contracts -v`
- Passed after adding coverage for:
  - generator contract
  - live XRM repair contract
  - ingress proof query
  - replay sender
  - mailbox finder

#### Live Replay Validation

Used extracted March GL060 PDFs and sent controlled replay mail with:

- [scripts/send-gl060-validation-replay.ps1](/C:/Users/smcfarlane/Desktop/WorkBench/QuoteFollowUpRegion/scripts/send-gl060-validation-replay.ps1)

Replay artifact:

- [gl060-validation-replay-send-20260420.json](/C:/Users/smcfarlane/Desktop/WorkBench/QuoteFollowUpRegion/results/gl060-validation-replay-send-20260420.json)

Mailbox-arrival proof for the working branches:

- [shared-mailbox-find-4172-gl060-20260420.json](/C:/Users/smcfarlane/Desktop/WorkBench/QuoteFollowUpRegion/results/shared-mailbox-find-4172-gl060-20260420.json)
- [shared-mailbox-find-4173-gl060-20260420.json](/C:/Users/smcfarlane/Desktop/WorkBench/QuoteFollowUpRegion/results/shared-mailbox-find-4173-gl060-20260420.json)

Those artifacts show the replay mail actually arrived in the `4172` and `4173` shared inboxes with subject `GL060 P&L report - Last month`.

Dataverse ingress proof:

- [gl060-mailbox-ingress-proof-postsend-20260420.json](/C:/Users/smcfarlane/Desktop/WorkBench/QuoteFollowUpRegion/results/gl060-mailbox-ingress-proof-postsend-20260420.json)
- [gl060-mailbox-ingress-proof-validationreplay-latest-20260420.json](/C:/Users/smcfarlane/Desktop/WorkBench/QuoteFollowUpRegion/results/gl060-mailbox-ingress-proof-validationreplay-latest-20260420.json)

Confirmed live unattended ingress outcomes:

- `4172` created a new `qfu_rawdocument` row with:
  - `qfu_status = queued`
  - `qfu_receivedon = 2026-04-20T16:03:11Z`
  - `qfu_processingnotes` containing subject and `InternetMessageId`
  - `qfu_ingestionbatch.qfu_triggerflow = 4172-GL060-Inbox-Ingress`
- `4173` created a new `qfu_rawdocument` row with the same mailbox evidence pattern
  - `qfu_ingestionbatch.qfu_triggerflow = 4173-GL060-Inbox-Ingress`

Interpretation:

- The shared GL060 ingress repair is real on live production.
- For `4172` and `4173`, the mailbox event now becomes a Dataverse raw queue row automatically.

### 4171 Validation Outcome

`4171` could not be proven by the same local replay because the replay mail never appeared in the `4171` shared inbox.

Relevant artifacts:

- [gl060-validation-replay-send-4171-only-instrumented-20260420.json](/C:/Users/smcfarlane/Desktop/WorkBench/QuoteFollowUpRegion/results/gl060-validation-replay-send-4171-only-instrumented-20260420.json)
- [shared-mailbox-find-4171-gl060-firstwindow-20260420.json](/C:/Users/smcfarlane/Desktop/WorkBench/QuoteFollowUpRegion/results/shared-mailbox-find-4171-gl060-firstwindow-20260420.json)
- [shared-mailbox-find-4171-gl060-secondwindow-20260420.json](/C:/Users/smcfarlane/Desktop/WorkBench/QuoteFollowUpRegion/results/shared-mailbox-find-4171-gl060-secondwindow-20260420.json)
- [gl060-mailbox-ingress-proof-4171-secondwindow-20260420.json](/C:/Users/smcfarlane/Desktop/WorkBench/QuoteFollowUpRegion/results/gl060-mailbox-ingress-proof-4171-secondwindow-20260420.json)

What that evidence shows:

- Outlook resolved `<EMAIL>` successfully as `4171 CALGARY`
- the replay sender reported the mail as sent
- the `4171` mailbox finder returned no matching inbox message after the resend window
- no new `4171` validation replay raw or ingestion rows appeared in Dataverse

Interpretation:

- the remaining `4171` validation blocker in this pass is before the flow
- there was no replay message in the `4171` mailbox for the flow to consume
- this does not disprove the repaired `4171` workflow definition, but it does mean the same local replay method could not fully prove that branch end to end

### Separate Remaining Production Gap

The replay proof also confirms that downstream GL060 processing is still not unattended:

- `4172` validation replay raw row remains `queued`
- `4173` validation replay raw row remains `queued`
- matching ingestion batches remain `queued`

That is a separate gap from mailbox ingress. The retired local processor guardrail is still present in:

- [scripts/register-gl060-processor-task.ps1](/C:/Users/smcfarlane/Desktop/WorkBench/QuoteFollowUpRegion/scripts/register-gl060-processor-task.ps1)

That script explicitly states:

- local scheduled GL060 processing is retired
- the expected production shape is mailbox ingress plus downstream hosted GL060 processing

Interpretation:

- mailbox-trigger hardening is repaired
- full end-to-end GL060 automation is still not complete until a hosted downstream GL060 consumer is in place

### Durable Fix Path

- Keep the live mailbox-ingress hardening in place for all three branches.
- Treat `4171` replay validation as a mailbox-delivery diagnostic, not a flow-definition regression, until a real inbox arrival can be observed and traced.
- Verify `4171` with either:
  - the real monthly GL060 sender
  - or an Exchange/Outlook replay method that is proven to land in the `4171` shared inbox
- Replace the retired local GL060 queue processor with a hosted downstream path. Do not restore the local scheduled task as the normal production solution.
- Keep using mailbox evidence fields (`receivedDateTime`, subject, `InternetMessageId`) in `qfu_rawdocument` and `qfu_ingestionbatch` so future misses are diagnosable from Dataverse alone.
