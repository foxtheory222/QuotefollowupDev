# QFU Solution Boundary Repair Plan

Updated: 2026-04-14 America/Edmonton

## Objective

Repair the dev solution boundary so the phased implementation can continue from a source-controlled unmanaged solution without unmanaged drift.

This run does not resume Phase A-F feature work.

## Blocker Status

- Blocker confirmed: `yes`
- Reason:
  - `qfu_branch` exists in the dev environment but is outside the current unmanaged solution
  - `qfu_region` exists in the dev environment but is outside the current unmanaged solution
  - the required Admin Panel AppModule does not exist in the dev environment
  - the required Manager Panel AppModule does not exist in the dev environment

## Repair Split

### Artifacts that already exist in the environment and can be added to the solution

- `qfu_branch`
- `qfu_region`

### Artifacts that do not exist yet and must be created first

- custom Admin Panel model-driven app
- custom Manager Panel model-driven app

## Safest Next Action

### Part 1: Repair the table boundary by composition

These two tables already exist live in Dataverse. They should be added to `QuoteFollowUpSystemUnmanaged` as unmanaged solution components, then exported and unpacked back into source control.

Recommended commands:

```powershell
pac solution add-solution-component --environment https://orgad610d2c.crm3.dynamics.com/ --solutionUniqueName QuoteFollowUpSystemUnmanaged --component qfu_branch --componentType 1 --AddRequiredComponents
pac solution add-solution-component --environment https://orgad610d2c.crm3.dynamics.com/ --solutionUniqueName QuoteFollowUpSystemUnmanaged --component qfu_region --componentType 1 --AddRequiredComponents
```

Then refresh source control from the repaired live solution:

```powershell
pac solution export --environment https://orgad610d2c.crm3.dynamics.com/ --name QuoteFollowUpSystemUnmanaged --path C:\Dev\QuoteFollowUpComplete\output\QuoteFollowUpSystemUnmanaged-dev-boundary-repaired.zip --managed false --overwrite
pac solution unpack --zipfile C:\Dev\QuoteFollowUpComplete\output\QuoteFollowUpSystemUnmanaged-dev-boundary-repaired.zip --folder C:\Dev\QuoteFollowUpComplete\output\QuoteFollowUpSystemUnmanaged-dev-boundary-repaired-unpacked --packagetype Unmanaged
```

After verification, copy or sync the unpacked content back into:

- [solution/QuoteFollowUpSystemUnmanaged/src](C:\Dev\QuoteFollowUpComplete\solution\QuoteFollowUpSystemUnmanaged\src)

If preferred, `pac solution sync` can replace the explicit export/unpack step:

```powershell
pac solution sync --environment https://orgad610d2c.crm3.dynamics.com/ --solution-folder C:\Dev\QuoteFollowUpComplete\solution\QuoteFollowUpSystemUnmanaged\src --packagetype Unmanaged
```

### Part 2: Create the missing model-driven apps

This part cannot be completed by solution composition alone because the required app artifacts do not exist in the environment yet.

Current live `appmodule` rows are only:

- `Power Platform Environment Settings`
- `Solution Health Hub`
- `Power Pages Management`

There is no existing custom Admin Panel app to add.
There is no existing custom Manager Panel app to add.

## Can This Be Resolved Without Maker UI?

- `qfu_branch` / `qfu_region`: `yes`
  - PAC solution composition is sufficient.
- Admin Panel / Manager Panel AppModules: `no`
  - A supported app authoring surface must create them first.
  - The safest path is Power Apps maker UI, inside the unmanaged solution.

## Human Maker Step Required

A human must first create the two missing model-driven apps in the dev environment, preferably directly inside `QuoteFollowUpSystemUnmanaged`:

1. create the Admin Panel model-driven app
2. create the Manager Panel model-driven app
3. include their SiteMap/navigation as part of app creation

Creating them directly inside the unmanaged solution is safer than creating them outside the solution and then trying to back-fill them later.

## After The Apps Exist

Once the apps exist, verify their `appmodule` records, then refresh the solution boundary again.

If the apps were created outside the solution by mistake, add them explicitly:

```powershell
pac solution add-solution-component --environment https://orgad610d2c.crm3.dynamics.com/ --solutionUniqueName QuoteFollowUpSystemUnmanaged --component <AdminAppModuleId> --componentType 80 --AddRequiredComponents
pac solution add-solution-component --environment https://orgad610d2c.crm3.dynamics.com/ --solutionUniqueName QuoteFollowUpSystemUnmanaged --component <ManagerAppModuleId> --componentType 80 --AddRequiredComponents
```

Then export and unpack the solution again.

## Exact Missing Artifacts Right Now

### Missing from current authoritative local source

- [solution/QuoteFollowUpSystemUnmanaged/src/Entities/qfu_Branch](C:\Dev\QuoteFollowUpComplete\solution\QuoteFollowUpSystemUnmanaged\src\Entities\qfu_Branch)
- [solution/QuoteFollowUpSystemUnmanaged/src/Entities/qfu_Region](C:\Dev\QuoteFollowUpComplete\solution\QuoteFollowUpSystemUnmanaged\src\Entities\qfu_Region)
- any unpacked `AppModules` content under [solution/QuoteFollowUpSystemUnmanaged/src](C:\Dev\QuoteFollowUpComplete\solution\QuoteFollowUpSystemUnmanaged\src)

### Missing from current exported live dev solution

- [output/QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked/Entities/qfu_Branch](C:\Dev\QuoteFollowUpComplete\output\QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked\Entities\qfu_Branch)
- [output/QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked/Entities/qfu_Region](C:\Dev\QuoteFollowUpComplete\output\QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked\Entities\qfu_Region)
- any unpacked `AppModules` content under [output/QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked](C:\Dev\QuoteFollowUpComplete\output\QuoteFollowUpSystemUnmanaged-dev-20260414-unpacked)

## Ordered Repair Sequence

1. Add `qfu_branch` to the unmanaged solution with PAC.
2. Add `qfu_region` to the unmanaged solution with PAC.
3. Export and unpack the solution.
4. Verify `Entities/qfu_Branch` and `Entities/qfu_Region` now exist in the unpacked export.
5. Sync those repaired artifacts back into source control.
6. Human creates Admin Panel app inside `QuoteFollowUpSystemUnmanaged`.
7. Human creates Manager Panel app inside `QuoteFollowUpSystemUnmanaged`.
8. Export and unpack the solution again.
9. Verify the unpacked solution now contains the new app artifacts.
10. Update blocker/phase docs and only then resume Phase A.

## Stop Rule

Do not resume implementation until all four blocker artifacts are present in:

- the live dev environment
- the live exported unmanaged solution
- the authoritative local solution source
