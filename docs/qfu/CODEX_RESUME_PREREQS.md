# QFU Resume Prerequisites

Updated: 2026-04-14 America/Edmonton

This checklist defines what must be true before Phase A-F implementation can safely resume.

## Current Resume Decision

- Can safely resume implementation now: `no`

## Required Preconditions

| Requirement | Current state | Resume gate |
| --- | --- | --- |
| `qfu_branch` exists in the dev environment | Pass | not sufficient alone |
| `qfu_branch` is included in `QuoteFollowUpSystemUnmanaged` | Fail | required |
| `qfu_branch` is present in local unpacked source | Fail | required |
| `qfu_region` exists in the dev environment | Pass | not sufficient alone |
| `qfu_region` is included in `QuoteFollowUpSystemUnmanaged` | Fail | required |
| `qfu_region` is present in local unpacked source | Fail | required |
| custom Admin Panel AppModule exists in the dev environment | Fail | required |
| custom Admin Panel AppModule is included in `QuoteFollowUpSystemUnmanaged` | Fail | required |
| custom Admin Panel app source is present in local unpacked solution | Fail | required |
| custom Manager Panel AppModule exists in the dev environment | Fail | required |
| custom Manager Panel AppModule is included in `QuoteFollowUpSystemUnmanaged` | Fail | required |
| custom Manager Panel app source is present in local unpacked solution | Fail | required |
| repaired solution exports successfully from dev | Fail | required |
| repaired solution unpacks successfully back into source control | Fail | required |
| no unmanaged feature drift was introduced during boundary repair | Pass so far | required |

## Minimum Evidence Required Before Resume

### Tables

These must exist after repair:

- [solution/QuoteFollowUpSystemUnmanaged/src/Entities/qfu_Branch](C:\Dev\QuoteFollowUpComplete\solution\QuoteFollowUpSystemUnmanaged\src\Entities\qfu_Branch)
- [solution/QuoteFollowUpSystemUnmanaged/src/Entities/qfu_Region](C:\Dev\QuoteFollowUpComplete\solution\QuoteFollowUpSystemUnmanaged\src\Entities\qfu_Region)

And also in the freshly exported live solution mirror:

- `...unpacked/Entities/qfu_Branch`
- `...unpacked/Entities/qfu_Region`

### Apps

The dev environment must contain two custom appmodules, and the unpacked solution must contain their exported source.

At minimum, there must be evidence of:

- one Admin Panel AppModule
- one Manager Panel AppModule

Current environment state does not satisfy this. The only live appmodules are:

- `Power Platform Environment Settings`
- `Solution Health Hub`
- `Power Pages Management`

## Verification Commands To Run Before Resuming

### Verify solution contents

```powershell
Get-ChildItem solution\QuoteFollowUpSystemUnmanaged\src\Entities | Select-Object -ExpandProperty Name
Get-ChildItem output\QuoteFollowUpSystemUnmanaged-dev-boundary-repaired-unpacked\Entities | Select-Object -ExpandProperty Name
Get-ChildItem solution\QuoteFollowUpSystemUnmanaged\src -Directory | Where-Object { $_.Name -match 'AppModules|AppModule' }
Get-ChildItem output\QuoteFollowUpSystemUnmanaged-dev-boundary-repaired-unpacked -Directory | Where-Object { $_.Name -match 'AppModules|AppModule' }
```

### Verify environment tables

```powershell
@'
Import-Module Microsoft.Xrm.Data.Powershell
$conn = Connect-CrmOnline -ServerUrl 'https://orgad610d2c.crm3.dynamics.com/' -ForceOAuth -Username 'smcfarlane@applied.com'
$meta = Get-CrmEntityAllMetadata -conn $conn
$meta | Where-Object { $_.LogicalName -in @('qfu_branch','qfu_region') } |
  Select-Object LogicalName,SchemaName,@{n='DisplayName';e={$_.DisplayName.UserLocalizedLabel.Label}}
'@ | powershell.exe -NoProfile -ExecutionPolicy Bypass -
```

### Verify environment appmodules

```powershell
@'
Import-Module Microsoft.Xrm.Data.Powershell
$conn = Connect-CrmOnline -ServerUrl 'https://orgad610d2c.crm3.dynamics.com/' -ForceOAuth -Username 'smcfarlane@applied.com'
Get-CrmRecords -conn $conn -EntityLogicalName appmodule -Fields @('appmoduleid','name','uniquename','statecode') -TopCount 100
'@ | powershell.exe -NoProfile -ExecutionPolicy Bypass -
```

### Verify export / unpack succeeds

```powershell
pac solution export --environment https://orgad610d2c.crm3.dynamics.com/ --name QuoteFollowUpSystemUnmanaged --path C:\Dev\QuoteFollowUpComplete\output\QuoteFollowUpSystemUnmanaged-dev-boundary-repaired.zip --managed false --overwrite
pac solution unpack --zipfile C:\Dev\QuoteFollowUpComplete\output\QuoteFollowUpSystemUnmanaged-dev-boundary-repaired.zip --folder C:\Dev\QuoteFollowUpComplete\output\QuoteFollowUpSystemUnmanaged-dev-boundary-repaired-unpacked --packagetype Unmanaged
```

## Resume Rule

Phase A can resume only when all of the following are true:

1. `qfu_branch` is live, in the unmanaged solution, and in unpacked source.
2. `qfu_region` is live, in the unmanaged solution, and in unpacked source.
3. Admin Panel AppModule exists live, is in the unmanaged solution, and is in unpacked source.
4. Manager Panel AppModule exists live, is in the unmanaged solution, and is in unpacked source.
5. The repo reflects the repaired live dev solution boundary.
6. Phase status docs are updated to show the blocker cleared.

Until then, the correct state is:

- blocker remains active
- Phase A-F remain paused
