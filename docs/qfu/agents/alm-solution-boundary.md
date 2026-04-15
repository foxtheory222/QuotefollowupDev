# ALM Solution Boundary Notes

Date: 2026-04-14

## Scope

This note is a read-only inspection of the current workspace, the authoritative unpacked Dataverse solution source, prior blocker docs, and the live unmanaged solution export artifacts already present in the repo.

Goal:

- determine whether `qfu_branch`, `qfu_region`, Admin/Manager app assets, and related SiteMap/app artifacts currently exist:
  - in local source
  - in live/exported environment artifacts
  - or in neither
- identify the safest repair path for the solution boundary

## Inspected Sources

- `solution/QuoteFollowUpSystemUnmanaged/src`
- `output/QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked`
- `docs/qfu/CODEX_BLOCKER_REPORT.md`
- `docs/qfu/CODEX_EXECUTION_PLAN.md`
- `site/table-permissions/operationhub-qfu_branch-Global-ReadWrite.tablepermission.yml`
- `site/table-permissions/operationhub-qfu_region-Global-ReadWrite.tablepermission.yml`
- `QFU_FINAL_AUDIT_STAGING/DATA/dataverse-metadata/qfu_branch.metadata.json`
- `QFU_FINAL_AUDIT_STAGING/DATA/dataverse-metadata/qfu_region.metadata.json`
- `QFU_FINAL_AUDIT_STAGING/DATA/dataverse-rows/qfu_branch.rows.json`
- `QFU_FINAL_AUDIT_STAGING/DATA/dataverse-rows/qfu_region.rows.json`
- `powerpages-live-dev/quotefollowup/quotefollowup---quotefollowup`
- `powerpages-verify-dev/quotefollowup/quotefollowup---quotefollowup`
- `powerpages-verify-dev-postsync/quotefollowup---quotefollowup`

## Commands Used

The environment blocks `rg.exe`, so inspection used PowerShell-native commands instead.

```powershell
Get-Content -Raw AGENTS.md
Get-Content -Raw CONVENTIONS.md
Get-Content -Raw AUTHORITATIVE_FILES_USED.md
Get-Content -Raw docs\qfu\CODEX_BLOCKER_REPORT.md
Get-Content -Raw docs\qfu\CODEX_EXECUTION_PLAN.md

Select-String -Path docs\qfu\CODEX_BLOCKER_REPORT.md,docs\qfu\CODEX_EXECUTION_PLAN.md `
  -Pattern 'qfu_branch|qfu_region|Admin Panel|Manager Panel|AppModule|SiteMap|it does \*\*not\*\* contain'

Select-String -Path solution\QuoteFollowUpSystemUnmanaged\src\Other\Solution.xml,`
  output\QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked\Other\Solution.xml `
  -Pattern 'qfu_activitylog|qfu_notificationsetting|qfu_quote|qfu_quoteline|qfu_rosterentry|qfu_branch|qfu_region'

Test-Path solution\QuoteFollowUpSystemUnmanaged\src\Entities\qfu_Branch
Test-Path solution\QuoteFollowUpSystemUnmanaged\src\Entities\qfu_Region
Test-Path solution\QuoteFollowUpSystemUnmanaged\src\AppModules
Test-Path output\QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked\Entities\qfu_Branch
Test-Path output\QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked\Entities\qfu_Region
Test-Path output\QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked\AppModules

Get-ChildItem -Path . -Recurse -Directory -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -in @('qfu_Branch','qfu_Region','AppModules') } |
  Select-Object -ExpandProperty FullName

Get-ChildItem -Path . -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match 'SiteMap|Sitemap|AppModule|appmodule' } |
  Select-Object -ExpandProperty FullName

Select-String -Path solution\QuoteFollowUpSystemUnmanaged\src\environmentvariabledefinitions\qfu_QFU_EnvironmentSettingsAppModuleId\environmentvariabledefinition.xml,`
  solution\QuoteFollowUpSystemUnmanaged\src\environmentvariabledefinitions\qfu_QFU_PowerPagesManagementAppModuleId\environmentvariabledefinition.xml,`
  output\QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked\environmentvariabledefinitions\qfu_QFU_EnvironmentSettingsAppModuleId\environmentvariabledefinition.xml,`
  output\QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked\environmentvariabledefinitions\qfu_QFU_PowerPagesManagementAppModuleId\environmentvariabledefinition.xml `
  -Pattern 'defaultvalue|displayname|description'
```

## Prior Blocker Docs Still Match the Workspace

The prior blocker docs correctly describe the current gap.

- `docs/qfu/CODEX_BLOCKER_REPORT.md:65` lists `qfu_branch` as missing.
- `docs/qfu/CODEX_BLOCKER_REPORT.md:66` lists `qfu_region` as missing.
- `docs/qfu/CODEX_BLOCKER_REPORT.md:67` lists missing AppModule / SiteMap source for the Admin Panel.
- `docs/qfu/CODEX_BLOCKER_REPORT.md:68` lists missing AppModule / SiteMap source for the Manager Panel.
- `docs/qfu/CODEX_BLOCKER_REPORT.md:88` through `docs/qfu/CODEX_BLOCKER_REPORT.md:91` repeat the same missing artifacts in the repair prerequisites.
- `docs/qfu/CODEX_EXECUTION_PLAN.md:61` through `docs/qfu/CODEX_EXECUTION_PLAN.md:63` state the unpacked solution does not contain `qfu_branch`, `qfu_region`, or unpacked Admin/Manager AppModule / SiteMap source.

The current workspace inspection confirms those statements are still accurate.

## Current Boundary Status

### Control artifacts that do exist in both local source and live solution export

The solution unpack itself is valid. Quote-follow-up core entities are present in both the authoritative local source and the live unmanaged export:

- `solution/QuoteFollowUpSystemUnmanaged/src/Other/Solution.xml:81` includes `qfu_activitylog`
- `solution/QuoteFollowUpSystemUnmanaged/src/Other/Solution.xml:89` includes `qfu_notificationsetting`
- `solution/QuoteFollowUpSystemUnmanaged/src/Other/Solution.xml:90` includes `qfu_quote`
- `solution/QuoteFollowUpSystemUnmanaged/src/Other/Solution.xml:91` includes `qfu_quoteline`
- `solution/QuoteFollowUpSystemUnmanaged/src/Other/Solution.xml:92` includes `qfu_rosterentry`

The same entities are present in the live unmanaged export:

- `output/QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked/Other/Solution.xml:81`
- `output/QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked/Other/Solution.xml:89`
- `output/QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked/Other/Solution.xml:90`
- `output/QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked/Other/Solution.xml:91`
- `output/QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked/Other/Solution.xml:92`

Implication:

- the unpacked solution source is real and usable
- the boundary problem is selective, not a full export failure

### Artifact classification

| Artifact | Exists in local unpacked solution source | Exists in live/exported environment artifacts already in workspace | Classification | Evidence |
| --- | --- | --- | --- | --- |
| `qfu_branch` entity | No | Yes, but only outside the current Dataverse solution boundary | Exists in environment artifacts only | `solution/QuoteFollowUpSystemUnmanaged/src/Entities/qfu_Branch` is absent; `output/QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked/Entities/qfu_Branch` is absent; `QFU_FINAL_AUDIT_STAGING/DATA/dataverse-metadata/qfu_branch.metadata.json` exists; `QFU_FINAL_AUDIT_STAGING/DATA/dataverse-rows/qfu_branch.rows.json` exists |
| `qfu_region` entity | No | Yes, but only outside the current Dataverse solution boundary | Exists in environment artifacts only | `solution/QuoteFollowUpSystemUnmanaged/src/Entities/qfu_Region` is absent; `output/QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked/Entities/qfu_Region` is absent; `QFU_FINAL_AUDIT_STAGING/DATA/dataverse-metadata/qfu_region.metadata.json` exists; `QFU_FINAL_AUDIT_STAGING/DATA/dataverse-rows/qfu_region.rows.json` exists |
| Admin Panel AppModule | No | No | Missing from both | no `AppModules` folder under `solution/QuoteFollowUpSystemUnmanaged/src`; no `AppModules` folder under `output/QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked`; workspace-wide file search found no AppModule asset files |
| Manager Panel AppModule | No | No | Missing from both | same evidence as Admin Panel AppModule |
| Admin / Manager SiteMap assets | No | No | Missing from both | workspace-wide file search found no `SiteMap` / `Sitemap` files under the solution source or live export artifacts |

## Important Distinction: Present In Portal Config Is Not Present In The Dataverse Solution Boundary

`qfu_branch` and `qfu_region` are clearly referenced by Power Pages configuration already in the workspace:

- `site/table-permissions/operationhub-qfu_branch-Global-ReadWrite.tablepermission.yml:5` uses `adx_entitylogicalname: qfu_branch`
- `site/table-permissions/operationhub-qfu_region-Global-ReadWrite.tablepermission.yml:5` uses `adx_entitylogicalname: qfu_region`

The same portal table-permission artifacts also exist in downloaded dev portal packages:

- `powerpages-live-dev/quotefollowup/quotefollowup---quotefollowup/table-permissions/operationhub-qfu_branch-Global-ReadWrite.tablepermission.yml`
- `powerpages-live-dev/quotefollowup/quotefollowup---quotefollowup/table-permissions/operationhub-qfu_region-Global-ReadWrite.tablepermission.yml`
- `powerpages-verify-dev-postsync/quotefollowup---quotefollowup/table-permissions/operationhub-qfu_branch-Global-ReadWrite.tablepermission.yml`
- `powerpages-verify-dev-postsync/quotefollowup---quotefollowup/table-permissions/operationhub-qfu_region-Global-ReadWrite.tablepermission.yml`

Implication:

- `qfu_branch` and `qfu_region` exist in the environment and are already used by the portal layer
- but they are still not inside the current unpacked Dataverse solution boundary
- editing Power Pages files alone will not repair the ALM gap

## AppModule Evidence

The only app-related artifacts currently present in the solution are optional environment variable definitions for linking out to existing Microsoft apps:

- `solution/QuoteFollowUpSystemUnmanaged/src/environmentvariabledefinitions/qfu_QFU_EnvironmentSettingsAppModuleId/environmentvariabledefinition.xml:2` sets `<defaultvalue>disabled</defaultvalue>`
- `solution/QuoteFollowUpSystemUnmanaged/src/environmentvariabledefinitions/qfu_QFU_EnvironmentSettingsAppModuleId/environmentvariabledefinition.xml:6` labels it `OPTIONAL: Environment Settings App ID`
- `solution/QuoteFollowUpSystemUnmanaged/src/environmentvariabledefinitions/qfu_QFU_PowerPagesManagementAppModuleId/environmentvariabledefinition.xml:2` sets `<defaultvalue>disabled</defaultvalue>`
- `solution/QuoteFollowUpSystemUnmanaged/src/environmentvariabledefinitions/qfu_QFU_PowerPagesManagementAppModuleId/environmentvariabledefinition.xml:6` labels it `OPTIONAL: Power Pages Management App ID`

The same optional environment variable definitions are present in the live unmanaged export:

- `output/QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked/environmentvariabledefinitions/qfu_QFU_EnvironmentSettingsAppModuleId/environmentvariabledefinition.xml:2`
- `output/QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked/environmentvariabledefinitions/qfu_QFU_PowerPagesManagementAppModuleId/environmentvariabledefinition.xml:2`

This is not evidence of a custom Admin Panel or Manager Panel AppModule. It is only evidence of optional app-id plumbing for existing external apps.

## Strongest Root Cause

The missing artifacts are not primarily a file-sync problem. They are a solution-boundary problem.

Specifically:

- `qfu_branch` and `qfu_region` exist in the environment, but were not included in the current `QuoteFollowUpSystemUnmanaged` export boundary that produced:
  - `solution/QuoteFollowUpSystemUnmanaged/src`
  - `output/QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked`
- Admin Panel / Manager Panel AppModules and their SiteMap assets are not present in the current local source or the current live export artifacts at all

That means the current repo cannot safely implement those items by editing the unpacked solution as if the missing artifacts were already under source control.

## Safest Repair Path

### 1. Treat this as an ALM boundary repair, not as a portal-file repair

Do not try to hand-author `qfu_Branch`, `qfu_Region`, AppModule, or SiteMap folders into `solution/QuoteFollowUpSystemUnmanaged/src` from scratch based on audit artifacts. That is the highest-risk path because it would create unverified source that does not round-trip from the environment.

### 2. Repair the solution boundary in Dataverse first

In the source/dev environment, update `QuoteFollowUpSystemUnmanaged` so it explicitly contains:

- `qfu_branch`
- `qfu_region`
- Admin Panel AppModule
- Manager Panel AppModule
- the SiteMap and app assets those apps depend on

This is the smallest safe repair because it makes the environment export authoritative again.

### 3. Re-export and re-unpack

After the environment boundary is corrected, re-run the normal export/unpack path. The existing blocker docs already use this shape of command:

```powershell
pac solution export `
  --environment https://orgad610d2c.crm3.dynamics.com/ `
  --name QuoteFollowUpSystemUnmanaged `
  --path C:\Dev\QuoteFollowUpComplete\output\QuoteFollowUpSystemUnmanaged-dev-YYYYMMDD.zip `
  --managed false `
  --overwrite

pac solution unpack `
  --zipfile C:\Dev\QuoteFollowUpComplete\output\QuoteFollowUpSystemUnmanaged-dev-YYYYMMDD.zip `
  --folder C:\Dev\QuoteFollowUpComplete\output\QuoteFollowUpSystemUnmanaged-dev-YYYYMMDD-unpacked `
  --packagetype Unmanaged
```

### 4. Verify the repair before implementing feature work

The boundary is only repaired if all of the following become true in the fresh export/unpack:

- `solution/QuoteFollowUpSystemUnmanaged/src/Entities/qfu_Branch` exists
- `solution/QuoteFollowUpSystemUnmanaged/src/Entities/qfu_Region` exists
- `solution/QuoteFollowUpSystemUnmanaged/src/AppModules` exists
- the unpacked solution contains the Admin/Manager app assets and SiteMap assets
- `solution/QuoteFollowUpSystemUnmanaged/src/Other/Solution.xml` includes the corresponding root components

### 5. Only then resume source-controlled changes

Until that export exists, the safest implementation stance is:

- portal references to `qfu_branch` / `qfu_region` can be inspected and maintained
- but Dataverse schema/app work for those artifacts should not be claimed as source-controlled inside the current solution tree

## Bottom Line

- `qfu_branch`: exists in environment artifacts already present in the workspace, but not in the current unpacked solution source or live unmanaged solution export boundary
- `qfu_region`: same status as `qfu_branch`
- Admin Panel AppModule: missing from both local source and current live/export artifacts
- Manager Panel AppModule: missing from both local source and current live/export artifacts
- Admin / Manager SiteMap assets: missing from both local source and current live/export artifacts

Safest next move:

- repair the Dataverse solution membership first
- re-export unmanaged
- re-unpack
- verify the missing artifacts are now present
- only then implement feature work against those assets
