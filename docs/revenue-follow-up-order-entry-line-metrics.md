# Order Entry Line Metrics

Phase 5 audited repo docs, scripts, results, and solution metadata for a verified source of order entry line counts by staff.

Result:
- No verified source was found for per-staff order entry line comparison.
- Existing qfu_branchdailysummary and budget/ops tables provide branch-level operational metrics, not verified per-staff order-entry line ownership.

Decision:
- Order entry line comparison is deferred.
- No fake order-entry metric was created.
- Team Stats uses verified quote, queue, assignment, and controlled backorder work item metrics only.

Required before implementation:
- A Dataverse table or summarized flow output with staff identity, branch, period, and order entry line count.
- Confirmed mapping from source staff identity to qfu_staff.
- Validation that counts match the source report.
