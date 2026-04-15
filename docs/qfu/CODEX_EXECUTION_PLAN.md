# QFU Codex Execution Plan

Updated: 2026-04-14 America/Edmonton

## Run Intent

This run started with a broken dev branch surface and then moved into the requested phase-gated quote follow-up implementation.

Execution order for this run:

1. Fix `Ready to Ship, Not PGI'd` in the dev portal without regressing the branch home page.
2. Complete Phase 0 baseline inspection, docs, and safe validation.
3. Verify the authoritative dev solution boundary before making schema/app changes.
4. Continue into quote follow-up implementation only if the live unmanaged solution actually contains the source-controlled components required for the requested end-to-end scope.

## Active Environment

- Dev portal: `https://quoteoperations.powerappsportals.com/`
- Dev Dataverse: `https://orgad610d2c.crm3.dynamics.com/`
- Browser session name to reuse: `qfu-dev`

## Authoritative Current Source Roots

- Power Pages source root: [site](C:\Dev\QuoteFollowUpComplete\site)
- Main runtime template: [QFU-Regional-Runtime.webtemplate.source.html](C:\Dev\QuoteFollowUpComplete\site\web-templates\qfu-regional-runtime\QFU-Regional-Runtime.webtemplate.source.html)
- Scripts root: [scripts](C:\Dev\QuoteFollowUpComplete\scripts)
- Durable mirrored scripts: [RAW/scripts](C:\Dev\QuoteFollowUpComplete\RAW\scripts)
- Unpacked solution source: [solution/QuoteFollowUpSystemUnmanaged/src](C:\Dev\QuoteFollowUpComplete\solution\QuoteFollowUpSystemUnmanaged\src)
- Current dev upload package: [powerpages-upload-dev](C:\Dev\QuoteFollowUpComplete\powerpages-upload-dev)

## Verification / Evidence Roots

These were inspected only as evidence or deployment mirrors, not as the editable source of truth:

- [results](C:\Dev\QuoteFollowUpComplete\results)
- [output](C:\Dev\QuoteFollowUpComplete\output)
- [powerpages-live-dev](C:\Dev\QuoteFollowUpComplete\powerpages-live-dev)
- [powerpages-verify-dev-current](C:\Dev\QuoteFollowUpComplete\powerpages-verify-dev-current)
- [output/QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked](C:\Dev\QuoteFollowUpComplete\output\QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked)

## Phase Gates

### Pre-Phase Stabilization

- Goal: restore correct Ready-to-Ship behavior in the dev portal before broader work
- Status: PASS

### Phase 0

- Goal: baseline the repo, tooling, environment, tests, and smoke harness
- Status: PASS

### Phase A

- Goal: establish production-safe quote follow-up data/config foundations
- Status: BLOCKED

The blocker is now proven from the live unmanaged solution export, not just the local workspace copy:

- the exported unmanaged solution contains only quote-side entities plus current operational workflows
- it does **not** contain `qfu_branch`
- it does **not** contain `qfu_region`
- it does **not** contain any unpacked AppModule / SiteMap source for the requested new Admin Panel and Manager Panel

Because the request explicitly requires source-controlled, production-safe Admin and Manager model-driven panels and branch-config ownership in the same run, continuing past Phase A from the current solution boundary would create unmanaged drift instead of a safe implementation.

### Phases B-F

- Status: NOT STARTED
- Gate reason: Phase A did not pass honestly for the requested end-to-end scope

## Safe Next Action

1. Expand the Dataverse solution boundary in dev so the required artifacts are actually in the solution:
   - `qfu_branch`
   - `qfu_region`
   - Admin / Manager AppModule artifacts
2. Export that updated unmanaged solution.
3. Unpack it back into source control.
4. Re-run Phase A from that refreshed source boundary.
