# Revenue Follow-Up Workbench Solution Scaffold

Date: 2026-04-24

## Purpose

This folder is the source-control home for the Revenue Follow-Up Workbench Power Platform solution.

The target runtime is:

```text
Power Apps model-driven app
    -> Dataverse tables
    -> Power Automate flows
    -> Email / Teams / dashboards / alerts
```

The Admin Panel is an area inside the model-driven app. It is not a Power Pages ops-admin expansion and not a custom React/web app.

## Dedicated Solution

This folder contains the local scaffold plus exported metadata for the dedicated Revenue Follow-Up Workbench solution.

| Setting | Value |
| --- | --- |
| Display Name | Revenue Follow-Up Workbench |
| Unique Name | `qfu_revenuefollowupworkbench` |
| Publisher Prefix | `qfu` |
| Initial Version | `1.0.0.0` |
| Environment | Regional operations Dataverse environment |

Create live Revenue Follow-Up Workbench assets in `qfu_revenuefollowupworkbench`, then export/unpack the solution back into this folder.

## Phase 2 Status

Phase 2 is live Dataverse tables and Power Apps Admin Panel MVP.

The live Dataverse foundation was created or verified on 2026-04-24 for:

- global choices used by the workbench tables
- `qfu_staff`
- `qfu_staffalias`
- `qfu_branchmembership`
- `qfu_policy`
- `qfu_workitem`
- `qfu_workitemaction`
- `qfu_alertlog`
- `qfu_assignmentexception`

The automated Phase 2 pass did not create the model-driven app shell, forms, views, command bar behavior, security roles, resolver flows, or alerts. Those must not be described as live-functional until they are created and exported.

Key Phase 2 fields include:

- `qfu_policy`: threshold operator, work item generation mode, first follow-up basis/days, GM CC mode, manager CC mode, and CSSR alert mode.
- `qfu_workitem`: source system, last followed up on, sticky note, sticky note updated on, and sticky note updated by.
- `qfu_workitemaction`: counts as attempt and actual action/follow-up date-time.
- `qfu_assignmentexception`: source quote line.

Google Stitch prompt standards now live in docs. Stitch output is design/prototype guidance only; the production implementation target remains Power Apps model-driven app/custom pages backed by Dataverse.

## Phase 1 Components

Phase 1 focuses on these Dataverse tables:

- `qfu_staff`
- `qfu_staffalias`
- `qfu_branchmembership`
- `qfu_policy`
- `qfu_workitem`
- `qfu_workitemaction`
- `qfu_alertlog`
- `qfu_assignmentexception`

The model-driven app should be named:

```text
Revenue Follow-Up Workbench
```

Initial app areas:

- My Work
- Manager Panel
- Admin Panel
- GM Review

Only the Admin Panel MVP needs working table-driven views/forms in the first pass.

## ALM Rule

Create Power Platform artifacts inside the solution, then export/unpack the solution back into this folder. Do not build the Admin MVP as loose unmanaged default-solution assets.

## Current State

This folder includes a PAC solution scaffold and a Phase 2 unmanaged solution export/unpack under:

```text
solution/qfu_revenuefollowupworkbench
```

The older scaffold remains under:

```text
solution/revenue-follow-up-workbench/src/src
```

The nested `src/src` path is the default output shape from `pac solution init` when the project folder is named `src`.

The export zip is stored under:

```text
solution/exports/qfu_revenuefollowupworkbench-phase2-unmanaged.zip
```
