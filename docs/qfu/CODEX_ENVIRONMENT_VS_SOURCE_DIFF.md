# QFU Environment vs Source Diff

Updated: 2026-04-14 America/Edmonton

## Scope

This report answers the current solution-boundary blocker only.

It compares:

- the authoritative local solution source at [solution/QuoteFollowUpSystemUnmanaged/src](C:\Dev\QuoteFollowUpComplete\solution\QuoteFollowUpSystemUnmanaged\src)
- the live dev unmanaged solution export at [output/QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked](C:\Dev\QuoteFollowUpComplete\output\QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked)
- the live dev environment at `https://orgad610d2c.crm3.dynamics.com/`

## Truth Inputs Used

- [CODEX_BLOCKER_REPORT.md](C:\Dev\QuoteFollowUpComplete\docs\qfu\CODEX_BLOCKER_REPORT.md)
- [CODEX_PHASE_STATUS.md](C:\Dev\QuoteFollowUpComplete\docs\qfu\CODEX_PHASE_STATUS.md)

## Missing Truth Input

- `QFU_DISCOVERY_ANSWERS.md` was not present anywhere in this workspace at the time of inspection.
- This diff is therefore based on the two available truth files above plus fresh environment and solution evidence collected during this run.

## Current Gap Matrix

| Artifact | Exists in live dev environment | Exists in authoritative local solution source | Exists in exported live dev solution | Classification |
| --- | --- | --- | --- | --- |
| `qfu_branch` table | Yes | No | No | Exists in environment but not in solution |
| `qfu_region` table | Yes | No | No | Exists in environment but not in solution |
| Admin Panel AppModule | No | No | No | Missing from both |
| Manager Panel AppModule | No | No | No | Missing from both |

## Evidence

### `qfu_branch`

- Present in the live environment metadata and data.
- Verified live records:
  - `4171 Calgary`
  - `4172 Lethbridge`
  - `4173 Medicine Hat`
- Not present in local source:
  - missing folder [solution/QuoteFollowUpSystemUnmanaged/src/Entities/qfu_Branch](C:\Dev\QuoteFollowUpComplete\solution\QuoteFollowUpSystemUnmanaged\src\Entities\qfu_Branch)
- Not present in exported live dev solution:
  - missing folder [output/QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked/Entities/qfu_Branch](C:\Dev\QuoteFollowUpComplete\output\QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked\Entities\qfu_Branch)
- Not present in solution root components:
  - [solution/QuoteFollowUpSystemUnmanaged/src/Other/Solution.xml](C:\Dev\QuoteFollowUpComplete\solution\QuoteFollowUpSystemUnmanaged\src\Other\Solution.xml#L81)
  - [output/QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked/Other/Solution.xml](C:\Dev\QuoteFollowUpComplete\output\QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked\Other\Solution.xml#L81)

### `qfu_region`

- Present in the live environment metadata and data.
- Verified live records:
  - `Southern Alberta`
  - `Northern Alberta`
  - `Saskatchewan`
- Not present in local source:
  - missing folder [solution/QuoteFollowUpSystemUnmanaged/src/Entities/qfu_Region](C:\Dev\QuoteFollowUpComplete\solution\QuoteFollowUpSystemUnmanaged\src\Entities\qfu_Region)
- Not present in exported live dev solution:
  - missing folder [output/QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked/Entities/qfu_Region](C:\Dev\QuoteFollowUpComplete\output\QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked\Entities\qfu_Region)
- Not present in solution root components:
  - [solution/QuoteFollowUpSystemUnmanaged/src/Other/Solution.xml](C:\Dev\QuoteFollowUpComplete\solution\QuoteFollowUpSystemUnmanaged\src\Other\Solution.xml#L81)
  - [output/QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked/Other/Solution.xml](C:\Dev\QuoteFollowUpComplete\output\QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked\Other\Solution.xml#L81)

### Admin / Manager AppModules

- Live environment `appmodule` records currently contain only:
  - `Power Platform Environment Settings`
  - `Solution Health Hub`
  - `Power Pages Management`
- There is no custom appmodule for an Admin Panel.
- There is no custom appmodule for a Manager Panel.
- Local source contains no unpacked `AppModules` folder under:
  - [solution/QuoteFollowUpSystemUnmanaged/src](C:\Dev\QuoteFollowUpComplete\solution\QuoteFollowUpSystemUnmanaged\src)
- Exported live dev solution also contains no unpacked `AppModules` folder under:
  - [output/QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked](C:\Dev\QuoteFollowUpComplete\output\QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked)

## Source-Only Check

For the four blocker artifacts above, there are no cases of:

- exists only in authoritative local source
- exists only in exported dev solution

The only related local-source traces are optional environment variable definitions for deep links to standard Microsoft apps:

- [qfu_QFU_PowerPagesManagementAppModuleId](C:\Dev\QuoteFollowUpComplete\solution\QuoteFollowUpSystemUnmanaged\src\environmentvariabledefinitions\qfu_QFU_PowerPagesManagementAppModuleId\environmentvariabledefinition.xml)
- [qfu_QFU_EnvironmentSettingsAppModuleId](C:\Dev\QuoteFollowUpComplete\solution\QuoteFollowUpSystemUnmanaged\src\environmentvariabledefinitions\qfu_QFU_EnvironmentSettingsAppModuleId\environmentvariabledefinition.xml)

Those are not the required Admin / Manager app artifacts.

## Exact Inspection Commands Used

### Solution roots

```powershell
Get-ChildItem solution\QuoteFollowUpSystemUnmanaged\src\Entities | Select-Object -ExpandProperty Name
Get-ChildItem output\QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked\Entities | Select-Object -ExpandProperty Name
Select-String -Path solution\QuoteFollowUpSystemUnmanaged\src\Other\Solution.xml -Pattern '<RootComponent type="1" schemaName="qfu_'
Select-String -Path output\QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked\Other\Solution.xml -Pattern '<RootComponent type="1" schemaName="qfu_'
```

### Environment table existence

```powershell
@'
Import-Module Microsoft.Xrm.Data.Powershell
$conn = Connect-CrmOnline -ServerUrl 'https://orgad610d2c.crm3.dynamics.com/' -ForceOAuth -Username 'smcfarlane@applied.com'
$meta = Get-CrmEntityAllMetadata -conn $conn
$meta | Where-Object { $_.LogicalName -in @('qfu_branch','qfu_region','qfu_branchopsdaily','qfu_branchdailysummary') } |
  Select-Object LogicalName,SchemaName,@{n='DisplayName';e={$_.DisplayName.UserLocalizedLabel.Label}},@{n='OwnershipType';e={[string]$_.OwnershipType}}
'@ | powershell.exe -NoProfile -ExecutionPolicy Bypass -
```

### Environment table rows

```powershell
@'
Import-Module Microsoft.Xrm.Data.Powershell
$conn = Connect-CrmOnline -ServerUrl 'https://orgad610d2c.crm3.dynamics.com/' -ForceOAuth -Username 'smcfarlane@applied.com'
Get-CrmRecords -conn $conn -EntityLogicalName qfu_branch -Fields @('qfu_branchid','qfu_branchcode','qfu_branchname','qfu_branchslug','qfu_regionname','qfu_regionslug','statecode') -TopCount 20
Get-CrmRecords -conn $conn -EntityLogicalName qfu_region -Fields @('qfu_regionid','qfu_regionname','qfu_regionslug','statecode') -TopCount 20
'@ | powershell.exe -NoProfile -ExecutionPolicy Bypass -
```

### Environment appmodules

```powershell
@'
Import-Module Microsoft.Xrm.Data.Powershell
$conn = Connect-CrmOnline -ServerUrl 'https://orgad610d2c.crm3.dynamics.com/' -ForceOAuth -Username 'smcfarlane@applied.com'
Get-CrmRecords -conn $conn -EntityLogicalName appmodule -Fields @('appmoduleid','name','uniquename','statecode') -TopCount 100
'@ | powershell.exe -NoProfile -ExecutionPolicy Bypass -
```
