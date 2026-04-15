# QFU Codex Phase Status

Updated: 2026-04-14 America/Edmonton

## Pre-Phase Stabilization

- Status: PASS
- What changed:
  - verified the dev `qfu_deliverynotpgi` runtime logic uses the correct active-row semantics
  - removed the duplicate branch-home Ready-to-Ship render path
  - changed Ready-to-Ship consumers to respect `hasData` and active-order state
  - redeployed the runtime to dev
  - downloaded the live dev site back and confirmed the runtime hash matches the local authoritative source
  - verified the underlying dev Dataverse data for branch `4171` contains `14` active orders, `26` active lines, and `$82,142.52` total unshipped value

## Phase 0

- Status: PASS
- Exit gate reached:
  - authoritative roots identified
  - baseline docs updated
  - safe validation commands executed
  - existing portal smoke harness executed
  - baseline failures separated from introduced failures

## Phase A

- Status: BLOCKED
- Why blocked:
  - the live unmanaged solution export does not contain `qfu_branch`
  - the live unmanaged solution export does not contain `qfu_region`
  - the live unmanaged solution export does not contain any AppModule / SiteMap source for the requested new Admin and Manager model-driven panels
  - the requested end-to-end scope explicitly requires those artifacts to be implemented safely and source-controlled in this run

## Phase B

- Status: NOT STARTED
- Gate reason: Phase A did not pass

## Phase C

- Status: NOT STARTED
- Gate reason: Phase A did not pass

## Phase D

- Status: NOT STARTED
- Gate reason: Phase A did not pass

## Phase E

- Status: NOT STARTED
- Gate reason: Phase A did not pass

## Phase F

- Status: NOT STARTED
- Gate reason: Phase A did not pass

## Baseline Failures Recorded

- `python -m unittest tests.test_freight_parser -v`
  - missing Python dependency `xlrd`
- `python -m unittest tests.test_sa1300_budget_selfpopulate -v`
  - missing example workbooks under `example\\4171\\SA1300.xlsx`, `example\\4172\\SA1300.xlsx`, and `example\\4173\\SA1300.xlsx`
- `scripts\\smoke-portal-routes.ps1`
  - harness runs, but the current `qfu-dev` browser session is unauthenticated and redirects to Microsoft login, so browser route validation is auth-blocked rather than runtime-JS-blocked
