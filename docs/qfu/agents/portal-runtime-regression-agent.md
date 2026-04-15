# Portal Runtime / Regression Agent Notes

Date: 2026-04-15
Workspace: `C:\Dev\quotefollowupDev`
Portal under test: `https://quoteoperations.powerappsportals.com/`

## Scope

This note summarizes the current runtime / regression baseline from:

- current shared runtime source
- current page-route source
- current table-permission and Web API site-setting source
- existing smoke scripts
- existing verification artifacts
- fresh dev route smoke from `2026-04-15`

No implementation changes are proposed here beyond minimal likely fix targets.

## Current baseline

### Fresh dev route health

Current smoke evidence comes from:

- `output/phase0/portal-route-smoke-20260415.md`
- `output/phase0/portal-route-smoke-20260415.json`
- script used: `scripts/smoke-portal-routes.ps1`

Current result:

- `/`
- `/southern-alberta/`
- `/southern-alberta/4171-calgary/`
- `/southern-alberta/4171-calgary/detail?view=follow-up-queue`
- `/southern-alberta/4171-calgary/detail?view=quotes`
- `/southern-alberta/4171-calgary/detail?view=overdue-backorders`
- `/southern-alberta/4171-calgary/detail?view=ready-to-ship-not-pgid`
- `/southern-alberta/4171-calgary/detail?view=team-progress`
- `/southern-alberta/4171-calgary/detail?view=analytics`

All currently fail the same way:

- they do not serve the portal
- they do not show portal `Page Not Found`
- they do not show in-portal runtime crash text
- they redirect into Dataverse App Designer:
  - title: `App Designer`
  - H1: `Power Apps`
  - actual URL host: `orgad610d2c.crm3.dynamics.com/designer/app/...`

Interpretation:

- this is currently a host/routing/auth target failure before the Power Pages runtime gets to hydrate
- page-level runtime behavior for the listed pages is therefore blocked, not yet disproven

### Historical live evidence

The strongest committed authenticated browser pass is still older live evidence from:

- `VERIFICATION/route-smoke-checks.md`
- `VERIFICATION/runtime-contract-checks.md`

That older live pass shows:

- hub/root passed
- southern alberta region passed
- branch routes passed
- overdue backorders detail passed
- analytics detail passed
- ops/admin passed

That evidence is useful as a last-known-good portal baseline, but it is not the current dev baseline.

## Shared runtime anchors

The current shared runtime still looks structurally coherent in source:

- detail route registry: `site/web-templates/qfu-regional-runtime/QFU-Regional-Runtime.webtemplate.source.html:65`
- `workload` aliases to `team-progress`: `...:78`
- shared fetch/diagnostics entry point: `safeGetAll(...)` at `...:1132`
- shared operational freshness: `branchOperationalFreshnessMoment(...)` at `...:2063`
- diagnostics renderer: `renderRuntimeDiagnosticsMarkup(...)` at `...:10063`

Current Web API fetch anchors in source include:

- quotes: `...:3549`
- backorders: `...:3550`
- budget archives: `...:3552`
- margin exceptions: `...:3556`
- late order exceptions: `...:3557`
- delivery-not-PGI: `...:3562`

Implication:

- if the portal starts serving again, the first likely regressions will still be shared-runtime regressions, not per-page template regressions
- right now, though, the runtime is probably not the first failing layer

## Current route / page config risks

Route source anchors:

- hub root: `site/web-pages/hub/Hub.webpage.yml`
- southern alberta: `site/web-pages/southern-alberta/Southern-Alberta.webpage.yml`
- branch page: `site/web-pages/4171-calgary/4171-Calgary.webpage.yml`
- detail shell: `site/web-pages/detail-shell_4aa958d9/Detail-Shell_4AA958D9.webpage.yml`

Observed config risk:

- `Hub.webpage.yml` uses `adx_partialurl: /`
- multiple nested pages also currently export with `adx_isroot: true`

This does not prove the YAML is wrong by itself, but it is enough to treat route/binding/config drift as a primary risk area for the current dev failure, ahead of runtime JS.

## Table-permission / allow-list status

### Current table-permission posture

Current table-permission source shows global read/readwrite coverage for the runtime’s main data tables:

- `qfu_quote`
- `qfu_quoteline`
- `qfu_backorder`
- `qfu_deliverynotpgi`
- `qfu_marginexception`
- `qfu_lateorderexception`
- `qfu_branchdailysummary`
- `qfu_financesnapshot`
- `qfu_financevariance`
- `qfu_ingestionbatch`
- `qfu_sourcefeed`

All inspected permission files are global-scope (`adx_scope: 756150000`).

Implication:

- current evidence does not point first to a missing table-permission record for the core read surfaces
- if those routes still fail after the host starts serving the portal, permission republishes are still a valid second check, but not the current first suspect

### Current allow-list posture

Existing allow-list artifact:

- `VERIFICATION/allowlist-lint-results.md`

What it says:

- `Tables missing required fields: 0`

Important limitation:

- that artifact references an older external source path outside this workspace
- it is still useful as last-known evidence, but it is not a fresh in-repo rerun for today

Net:

- there is no current artifact proving an allow-list miss for quotes, quotelines, backorders, delivery-not-PGI, margin, or late orders
- there is also no fresh rerun inside this task

## Data baseline

Current dev operational-state evidence in `VERIFICATION/operational-current-state-dev.md` shows live rows exist:

- `qfu_quote`: 36 active rows
- `qfu_backorder`: 1047 active rows
- `qfu_deliverynotpgi`: 84 active rows

Implication:

- once portal serving is restored, empty Quotes or Ready to Ship pages should be treated as runtime/filter/access regressions, not “no data” situations

## Page-by-page current regression status

| Surface | Current dev status | Evidence | Likely minimal fix if still broken after host recovery |
| --- | --- | --- | --- |
| Dashboard root | FAIL before portal render | `output/phase0/portal-route-smoke-20260415.*` | Fix portal route/auth target or site binding first |
| Follow-Up Queue | FAIL before portal render | `output/phase0/portal-route-smoke-20260415.*` | Then verify `qfu_quote` queue hydration in shared runtime |
| Quotes | FAIL before portal render | `output/phase0/portal-route-smoke-20260415.*` | Then verify `qfu_quote` and `qfu_quoteline` route hydration and detail drill-through |
| Overdue Backorders | FAIL before portal render | `output/phase0/portal-route-smoke-20260415.*` | Then verify route render only; keep `qfu_daysoverdue` authority intact |
| Ready to Ship Not PGI'd | FAIL before portal render | `output/phase0/portal-route-smoke-20260415.*` | Then verify delivery route hydration and lifecycle filtering first |
| Team Progress | FAIL before portal render | `output/phase0/portal-route-smoke-20260415.*` | Then verify owner-summary hydration in shared runtime |
| Workload | FAIL by alias to Team Progress | `DETAIL_VIEWS` alias at runtime line 78 plus smoke gap | Fix alias behavior only; do not fork a separate page |
| Analytics | FAIL before portal render | `output/phase0/portal-route-smoke-20260415.*` | Then verify exception-table access and route hydration |

## Existing smoke coverage

### What is covered now

`scripts/smoke-portal-routes.ps1` currently covers:

- root
- southern alberta region
- branch home
- follow-up queue
- quotes
- overdue backorders
- ready-to-ship-not-pgid
- team-progress
- analytics

This is good coverage for route entry points.

### What it does not prove

The current smoke script only proves what the browser session actually lands on. It does not prove:

- quote detail drill-through
- workload alias route directly
- in-page data correctness
- quote follow-up action behavior
- ready-to-ship summary math
- analytics card integrity

And today it never reaches the portal at all, because every route lands in App Designer first.

## Obvious quote follow-up runtime gaps

Current gaps specific to quote follow-up:

1. There is no current authenticated dev proof that Follow-Up Queue or Quotes render inside the portal at all.
2. There is no current dev proof that quote detail drill-through still works.
3. There is no current dev proof that runtime diagnostics are visible on quote routes, because the host redirect prevents the runtime from loading.

## Minimal likely fixes

Order of operations should stay minimal:

1. Restore the dev portal host so `quoteoperations.powerappsportals.com` serves Power Pages instead of Dataverse App Designer.
2. Re-run `scripts/smoke-portal-routes.ps1` and confirm all covered routes stay on the portal host.
3. Only then evaluate page-level runtime defects.
4. If page-level defects remain after host recovery:
   - quotes / follow-up queue: check shared runtime fetch/filter behavior first
   - ready-to-ship-not-pgid: check delivery lifecycle interpretation and Web API access first
   - analytics: check exception-table access and freshness first
   - workload: treat only as alias verification against team-progress

## Bottom line

- Current dev regression is primarily a portal-host / auth-target / routing failure, not yet a proven runtime-template defect.
- The shared runtime source still has the expected route registry, diagnostics path, and dataset fetch structure.
- Current permission source does not show an obvious missing permission for the core read surfaces.
- Current allow-list evidence is favorable but stale.
- The next honest gate is not redesign. It is getting the dev portal to serve the portal again, then rerunning the same smoke coverage.
