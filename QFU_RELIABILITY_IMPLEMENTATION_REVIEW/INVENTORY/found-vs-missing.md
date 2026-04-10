# Found vs Missing

## Implemented

- `CONVENTIONS.md`
- repo-root `AGENTS.md` guardrail summary
- runtime hardening in the authoritative current regional runtime
- runtime diagnostics banner styling
- deprecated Phase 0 banner in the current deprecated template
- current dry-run budget normalization helper
- current dry-run budget duplicate audit helper
- runtime-vs-Web-API allow-list lint
- current budget flow generator hardening
- verification outputs for polarity search, runtime diagnostics, budget flow checks, allow-list lint, Phase 0 references, and dry-run budget duplicate audit
- changed-source copies and combined diff bundle

## Intentionally Not Implemented

- security tightening
- schema renames
- live deployment
- live Dataverse mutation
- destructive duplicate cleanup
- allow-list trimming for extra-but-currently-safe fields
- new `qfu_deliverynotpgi` base-row writer
- deletion/removal of the deprecated Phase 0 template

## Could Not Verify

- browser smoke tests against deployed pages were not run in this pass
- generated budget-flow JSON/solution output was not imported into a live environment in this pass
- runtime diagnostics visual rendering on a deployed portal was not browser-verified because no deployment occurred in this pass

## Remaining Known Unknowns

- exact `qfu_deliverynotpgi` base-row writer remains unproven
- live historical duplicate/archive state in Dataverse was not cleaned in this pass
- the repo did not contain a pre-existing authoritative `RAW/scripts/normalize-live-sa1300-current-budgets.ps1`; a new current helper was created instead
