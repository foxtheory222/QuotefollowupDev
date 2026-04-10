# Known Limitations

- The exact authoritative base-row writer for `qfu_deliverynotpgi` is still not proven from current source-controlled assets. This pass only hardens the reader, stale warning, and comment-edit path.
- The live operational freshness warning is still real. The latest `qfu_ingestionbatch` evidence for `4171`, `4172`, and `4173` still points to controlled workbook seeds captured on `2026-03-20`, so the portal correctly warns that source freshness is not proven even though the runtime logic is now aligned.
- Canonical quote and backorder flow updates were deployed live. Canonical budget flow updates still fail through the generic workflow-update path with a server-side `InternalServerError`, so the budget-flow source hardening remains partially source-only.
- `qfu_deliverynotpgi` still has 10 canonical-key groups that reappear across inactive history rows. The live repair script intentionally ignores those groups unless more than one active/current row exists.
- Browser smoke tests were run against the live production portal after deployment of the runtime changes.
- The Power Pages host still emits repeated framework warnings in browser console output. No route-level JS crash was detected in the tested routes, but those host warnings remain noisy.
- Analytics visual polish was improved with a narrow spotlight band only. This was not broadened into a full redesign pass.
