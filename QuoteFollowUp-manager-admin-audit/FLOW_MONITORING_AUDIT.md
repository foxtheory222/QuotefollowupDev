# Flow Monitoring Audit

## Current Monitoring

- Flow run history is referenced in scripts/docs and remains supporting evidence.
- qfu_ingestionbatch is the canonical freshness source for analytics and import status.
- Health check scripts exist, including Southern Alberta flow health, runtime readiness, local task health, route performance, and live QFU health checks.
- Verification artifacts under VERIFICATION/ record duplicate audits, freshness checks, runtime contracts, and route smoke checks.

## Gaps

- Flow failures are not consistently visible inside Power Pages as actionable admin records.
- Failed alert detection is not represented by a dedicated alert log.
- Failed import detection depends on ingestion batch freshness and manual/run-history checks.
- No unified monitoring dashboard table was found for flow health, last success, last failure, retry count, replay status, owner, and impacted branch/source.

## Recommended Monitoring Changes

- Standardize every ingestion flow to write stable qfu_ingestionbatch rows with status, source family, branch, started/completed timestamps, counts, error code, and replay pointer.
- Add qfu_flowhealth or extend ingestion batch summaries for latest success/failure per branch/source.
- Add qfu_alertlog for reminder/escalation sends, dedupe keys, recipients, attempts, and delivery results.
- Surface failures in the Ops/Admin Power Pages route with branch/source filters.
- Keep run history as supporting evidence, not the primary monitoring surface.