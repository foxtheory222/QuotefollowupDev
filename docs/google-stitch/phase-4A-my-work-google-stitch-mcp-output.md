# Phase 4A Google Stitch MCP Output - My Work UX

## Summary

Google Stitch MCP was used directly on April 27, 2026 to generate design guidance for the Revenue Follow-Up Workbench TSR/CSSR daily work experience.

- Stitch project: `projects/16963969412485526656`
- Project title: QFU Quotes Archive Toolbar Polish 2026-04-20
- Design system generated/used: Metric Industrial / Kinetic Instrument
- Implementation target: Power Apps custom pages inside the Revenue Follow-Up Workbench model-driven app, backed by Dataverse
- Stitch role: design/prototype guidance only
- Production frontend code from Stitch committed: no

## Artifacts

| Artifact | Screen ID | Device | Screenshot File | HTML File |
| --- | --- | --- | --- | --- |
| My Work main page | `f3a937b771704589b32d2c33260f3dbb` | Desktop | `projects/16963969412485526656/files/9e7ecb4e90ca408babc2649f1455caa8` | `projects/16963969412485526656/files/829eee72ca5e4cb682f237e12f8d65a7` |
| Quote Detail side panel | `d0c116c11d6340ba8166e15e9adfa606` | Desktop | `projects/16963969412485526656/files/b83fdbab66f14dff9643ad48bf3ef6bd` | `projects/16963969412485526656/files/d8e998d3b6f6439c9f07a3b33ab330bd` |
| Log Follow-Up modal | `c506afc4410d4e99b322e6eb55da114d` | Desktop | `projects/16963969412485526656/files/9bc1c1e97f804029ba23a6d3de55ba07` | `projects/16963969412485526656/files/9bf6e98e75754678bb5f1211dec0a0ec` |
| Sticky Note edit experience | `2dca25b9a7094e1b9a719c6f92397d9f` | Desktop | `projects/16963969412485526656/files/c4a9898b0df84ee49d3938015301977f` | `projects/16963969412485526656/files/c06506395e1c43998d6f3bf1cc6cac58` |
| Empty/loading/error/mapping states | `9e64033c81e248f6bb1609fc6af8340f` | Desktop | `projects/16963969412485526656/files/0197247900344fb49f3d8114a6a98564` | `projects/16963969412485526656/files/602890a8d56e4c32a625bd721d7bf04f` |
| Mobile quick-review variant | `0a282c6cba1c4729a2f824463e05f88f` | Mobile | `projects/16963969412485526656/files/9f9f5f3e173749a4adbbea198a013808` | `projects/16963969412485526656/files/ba31ac26d125469c830d5e6a042a1388` |

Stitch returned exportable HTML file references and screenshot file references. They are recorded as artifact references only. The generated HTML is not production code and should not be committed or used as the Power Apps implementation.

## Prompt 1 - My Work Main Page

Purpose: create the desktop daily work queue.

Prompt used: Product Revenue Follow-Up Workbench. Page My Work. Implementation target Power Apps custom page inside a model-driven Power App backed by Dataverse. Google Stitch is design guidance only, not production frontend code. Primary user TSR or CSSR. Create a clean, low-click, desktop-first daily work queue with header, branch/team context, refresh timestamp, role context, staff filter/dropdown fallback, KPI cards for Due Today, Overdue, Quotes >= $3K, Missing Attempts, Roadblocks, Assignment Issues, priority tabs for Overdue, Due Today, High Value, Needs Attempts, Waiting, Roadblocks, All Open, a dense work list with priority, status, quote/source document, customer placeholder, value, attempts, next follow-up, last followed up, TSR, CSSR, sticky note preview, next action, a right-side detail panel, quick action bar, and empty/loading/error state representation. Use sanitized sample data only.

Stitch summary: the design uses a precision workbench aesthetic with KPI cards, prominent overdue/due-today treatments, a dense operational table, right-side detail panel, and quick action bar.

## Prompt 2 - Quote Detail Side Panel

Purpose: create the selected quote slide-over pattern.

Prompt used: Product Revenue Follow-Up Workbench. Component Quote Detail side panel / slide-over. Implementation target Power Apps custom page side panel inside a model-driven app. Show source document, customer placeholder, total value, status, assignment status, attempts, next follow-up, last followed up, TSR, CSSR, branch, prominent sticky note near top, edit button, last updated by/on, quick actions, action history, and source quote/line visibility. Use sanitized data only.

Stitch summary: the design provides persistent context, a compact summary grid, prominent sticky note, action buttons, action timeline, and source system section.

## Prompt 3 - Log Follow-Up Modal

Purpose: create the repeated-use follow-up logging dialog.

Prompt used: Product Revenue Follow-Up Workbench. Component Log Follow-Up modal. Implementation target Power Apps custom page modal/dialog. Fields are Action Type, Followed Up On, Counts As Attempt, Outcome, Follow-Up Notes, Next Follow-Up On. Defaults are Call, Email, Customer Advised count as attempt; Note, Roadblock, Escalated, Due Date Updated, Won, Lost, Cancelled, Sticky Note Updated do not count as attempt. Represent validation for required Followed Up On, Roadblock note required, terminal closing behavior, and next follow-up before followed-up warning. Use sanitized data only.

Stitch summary: the design uses a compact two-column form, visible validation states, clear Save Follow-Up and Cancel actions, and a footer note about work item action creation and rollup.

## Prompt 4 - Sticky Note Edit Experience

Purpose: show sticky note preview, inline edit, and modal edit patterns.

Prompt used: Product Revenue Follow-Up Workbench. Component Sticky Note edit experience. Implementation target Power Apps custom page. Sticky note appears near the top of Quote Detail, supports inline or compact modal edit, Save, Cancel, last updated by/on, and clear distinction between persistent sticky note and per-action history notes. Use sanitized data only.

Stitch summary: the design emphasizes sticky note visibility, amber professional treatment, inline editing, compact modal editing, and metadata that reinforces persistence through imports.

## Prompt 5 - Empty, Loading, Error, and Mapping States

Purpose: define operational fallback states.

Prompt used: Product Revenue Follow-Up Workbench. Page/component My Work empty, loading, error, and mobile quick-review states. For desktop states, include no due or overdue work, fetching work items, cannot load work items, and staff mapping missing. Show branch/team filter and staff dropdown fallback because current-user staff mapping is not ready. Use sanitized data only.

Stitch summary: the design includes Queue Clear, loading skeletons, Data Sync Failure with Retry, and Identity Mapping Required with branch/team/staff fallback controls.

## Prompt 6 - Mobile Quick Review

Purpose: create a small-screen quick review, not a full replacement.

Prompt used: Product Revenue Follow-Up Workbench. Mobile quick-review variant. Show header, branch/team context, refresh timestamp, segmented control for Overdue, Due Today, High Value, condensed KPI strip, condensed work cards with status, quote number, value, attempts, next follow-up, sticky note indicator, and quick tap to open detail. Use sanitized data only.

Stitch summary: the design adapts the workbench into compact mobile review cards and a bottom action affordance while keeping desktop as the primary experience.

## What To Use

- Use the My Work layout, KPI strip, priority tabs, table density, status treatments, and right-side detail panel as the Phase 4B design basis.
- Use the Log Follow-Up modal field grouping and validation states for the first action logging build.
- Use the Sticky Note inline edit pattern first; keep compact modal edit as a fallback.
- Use the mapping-missing state as the honest MVP fallback until `qfu_staff` links to `systemuser`.
- Use mobile quick review as a secondary responsive check only.

## What Not To Use

- Do not use generated Stitch HTML as production code.
- Do not hardcode the sanitized sample rows.
- Do not imply current-user filtering until staff/systemuser mapping exists.
- Do not mix assignment exceptions directly into normal work tabs; expose them as a separate assignment issue lane/state.
