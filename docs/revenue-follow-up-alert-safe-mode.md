# Alert Safe Mode

Phase 6 uses `qfu_policy.qfu_alertmode`.

Supported modes:
- `Disabled`: no alert work should be performed.
- `DryRunOnly`: create or reuse `qfu_alertlog` records, but send no email or Teams messages.
- `TestRecipientOnly`: reserved for a verified test recipient only.
- `Live`: reserved for a later approved activation step.

Current dev mode:
- `DryRunOnly`

Safety results:
- Production emails sent: 0.
- Teams messages sent: 0.
- Live digests sent: 0.
- Test recipient send: skipped because no verified test recipient was configured.
- Phase 6 flow definitions were checked for Office/Teams send connector actions and none were present.

Dry-run status mapping:
- `qfu_alertlog.qfu_status = Skipped` is used when a recipient email or recipient staff mapping is missing.
- `qfu_alertlog.qfu_status = Suppressed` is available for dry-run candidates with valid recipient email.
- In this dev pass all 75 candidates were skipped because active staff email readiness is 0 of 19.
