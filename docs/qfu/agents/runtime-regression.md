# Portal Runtime Regression Notes

Date: 2026-04-15
Portal: `https://quoteoperations.powerappsportals.com/`
Repo: `C:\Dev\quotefollowupDev`

## Current evidence

Fresh route smoke was rerun today with the existing `qfu-dev` Playwright session:

- command: `powershell -ExecutionPolicy Bypass -File scripts\smoke-portal-routes.ps1 -BaseUrl 'https://quoteoperations.powerappsportals.com' -Session 'qfu-dev' -OutputJson 'output\phase0\portal-route-smoke-20260415.json' -OutputMarkdown 'output\phase0\portal-route-smoke-20260415.md'`
- result artifact:
  - `output/phase0/portal-route-smoke-20260415.md`
  - `output/phase0/portal-route-smoke-20260415.json`

This is the current route baseline:

- `/`
- `/southern-alberta/`
- `/southern-alberta/4171-calgary/`
- `/southern-alberta/4171-calgary/detail?view=follow-up-queue`
- `/southern-alberta/4171-calgary/detail?view=quotes`
- `/southern-alberta/4171-calgary/detail?view=overdue-backorders`
- `/southern-alberta/4171-calgary/detail?view=ready-to-ship-not-pgid`
- `/southern-alberta/4171-calgary/detail?view=team-progress`
- `/southern-alberta/4171-calgary/detail?view=analytics`

All of them are currently failing the same way:

- they do not return the portal
- they do not return portal `Page Not Found`
- they do not show runtime crash text
- they redirect into Dataverse / model-driven app designer instead:
  - `https://orgad610d2c.crm3.dynamics.com/designer/app/.../AppDesignerCanvas/...`
- page title resolves to `App Designer`
- H1 resolves to `Power Apps`

That means current dev route health is:

- root dashboard: FAIL
- follow-up queue: FAIL
- quotes: FAIL
- overdue backorders: FAIL
- ready-to-ship-not-pgid: FAIL
- team progress: FAIL
- workload: FAIL by alias, because `workload -> team-progress`
- analytics: FAIL

## What this means

This is no longer an in-portal runtime regression first. It is a host / site-resolution / auth-routing regression in the dev environment.

Because every route lands in the same App Designer URL, the shared runtime is not currently getting a chance to hydrate. Until that redirect is fixed, page-level runtime behavior for follow-up queue, quotes, ready-to-ship, team progress, workload, and analytics cannot be honestly verified in-browser.

## Current source guardrails still present

The current shared runtime is still wired correctly in source:

- detail route registry exists in `site/web-templates/qfu-regional-runtime/QFU-Regional-Runtime.webtemplate.source.html:65`
- `workload` aliases to `team-progress` at `site/web-templates/qfu-regional-runtime/QFU-Regional-Runtime.webtemplate.source.html:78`
- shared data fetch and diagnostics live in `safeGetAll(...)` at `site/web-templates/qfu-regional-runtime/QFU-Regional-Runtime.webtemplate.source.html:1132`
- branch operational freshness is centralized at `site/web-templates/qfu-regional-runtime/QFU-Regional-Runtime.webtemplate.source.html:2063`
- route dispatch remains centralized:
  - analytics: `...:10362`
  - ready-to-ship-not-pgid: `...:10366`
  - follow-up-queue: `...:10374`
  - quotes: `...:10397`
  - overdue-backorders: `...:10503`
  - team-progress: `...:10566`

The supporting route shell is also still in place:

- hub root page: `site/web-pages/hub/Hub.webpage.yml`
- southern alberta region page: `site/web-pages/southern-alberta/Southern-Alberta.webpage.yml`
- branch page: `site/web-pages/4171-calgary/4171-Calgary.webpage.yml`
- detail shell: `site/web-pages/detail-shell_4aa958d9/Detail-Shell_4AA958D9.webpage.yml`

## Current data baseline

The dev operational tables are not empty:

- `qfu_quote`: 36 active rows
- `qfu_backorder`: 1047 active rows
- `qfu_deliverynotpgi`: 84 active rows

Source:

- `VERIFICATION/operational-current-state-dev.md`

Implication:

- if the portal starts serving again and Quotes or Ready to Ship still render empty, that would then point to portal Web API access, runtime filtering, or lifecycle interpretation
- right now the blocker is earlier than that

## Current page-specific regression readout

### Dashboard root and region

Status:

- both currently fail before portal render
- root no longer shows classic portal 404 in this smoke run
- both routes land in App Designer instead

Minimal likely fix:

- repair dev portal host routing / auth redirect target first
- do not touch dashboard runtime code until the host serves the portal again

### Follow-Up Queue

Status:

- route exists in source and is included in the smoke harness
- current browser evidence cannot validate queue hydration because the host redirects to App Designer first

Minimal likely fix after host recovery:

- verify `qfu_quote` read path and queue table hydration first
- then verify quote-follow-up row ordering and empty-state text

### Quotes

Status:

- route exists in source and is included in the smoke harness
- current browser evidence cannot validate quotes workbench or quote detail because of the same host redirect

Minimal likely fix after host recovery:

- verify `qfu_quote` and `qfu_quoteline` Web API access
- verify quote detail drill-through still resolves and does not loop back

### Overdue Backorders

Status:

- route currently blocked by host redirect like the rest
- no new evidence today that the overdue-backorder runtime itself regressed

Guardrail:

- overdue logic should still use `qfu_daysoverdue` as authority
- `VERIFICATION/overdue-backorder-consistency.md` remains the controlling evidence

Minimal likely fix after host recovery:

- confirm route render only
- avoid changing overdue authority rules unless the consistency audit regresses too

### Ready to Ship, Not PGI'd

Status:

- route currently blocked by host redirect
- this page remains the highest-risk false-empty-state surface once portal serving resumes because active `qfu_deliverynotpgi` rows do exist in dev

Minimal likely fix after host recovery:

- first verify `qfu_deliverynotpgi` route hydration
- then verify lifecycle filtering and Web API field access
- only then adjust empty-state or summary-card copy if still needed

### Team Progress / Workload

Status:

- both currently blocked by host redirect
- `workload` is still just the `team-progress` alias in source

Minimal likely fix after host recovery:

- verify owner-summary hydration once
- if `workload` behaves differently from `team-progress`, treat that as alias normalization drift, not a separate page bug

### Analytics

Status:

- route currently blocked by host redirect
- no new evidence today that the analytics renderer itself regressed

Minimal likely fix after host recovery:

- verify route hydration
- if it loads partially blank, check exception-table Web API access before changing analytics rendering

## Obvious quote follow-up runtime gaps

These remain real gaps until the portal serves again:

1. There is no current authenticated browser proof that Follow-Up Queue or Quotes are hydrating in dev.
2. Quote-detail drill-through is not revalidated in the current dev baseline.
3. Because the host never reaches the portal runtime right now, any quote follow-up UI regression below the redirect layer is still unmeasured today.

## Most likely minimal fixes needed

In order:

1. Fix the dev portal redirect/binding/auth routing so `quoteoperations.powerappsportals.com` serves the actual portal instead of Dataverse App Designer.
2. Re-run `scripts/smoke-portal-routes.ps1` and confirm the same routes land on portal pages, not login or designer.
3. Once portal serving is restored:
   - verify Follow-Up Queue and Quotes first
   - verify Ready to Ship next
   - verify Team Progress / Workload alias
   - verify Analytics last
4. Only if a route then hydrates incorrectly should runtime/template fixes be considered.

## Bottom line

- Today’s dev regression is primarily a host-routing failure, not a proven shared-runtime rendering failure.
- Every tracked route currently lands in App Designer instead of the portal.
- The portal runtime source still looks structurally intact.
- The next honest fix is to restore portal serving first, then re-run the route smoke and only then chase any page-level runtime defects.
