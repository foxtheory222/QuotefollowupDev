# Revenue Follow-Up Google Stitch UI Brief

Date: 2026-04-24

## Phase Boundary

Current phase: Phase 1.2 - follow-up date, sticky notes, and Google Stitch UI prompt standard before live Dataverse table creation.

Functional after this phase:

- Future UI/design prompts have a required Google Stitch standard.
- Stitch prompt blocks exist for My Work, Quote Work Item detail, Manager Panel, Admin Panel MVP, and GM Review.
- The implementation target remains Power Apps model-driven app/custom pages backed by Dataverse.

Not functional yet:

- No Google Stitch prototype has been generated.
- No frontend code has been generated or committed.
- No Power Apps custom pages have been created.
- No live Dataverse tables, flows, or app metadata have been created.

What comes next:

- Use these prompts only when design/prototype work is requested.
- Review Stitch output as design guidance before implementing the final Power Apps experience.

Still left:

- Confirm exact Power Apps custom page scope.
- Build Dataverse tables and model-driven app assets.
- Validate final Power Apps screens with real permissions and Dataverse data.

Questions that must not be guessed:

- Whether My Work and Quote Detail should start as custom pages or model-driven views/forms first.
- First follow-up due date rule.
- CSSR, GM, and Manager alert/CC modes.

## Standard

Google Stitch is required for any future UI design/prototype prompts for the Revenue Follow-Up Workbench.

Stitch output is design guidance only. Do not generate or commit frontend code from Stitch as the production Power Apps implementation unless explicitly requested later.

The actual implementation target remains:

```text
Power Apps model-driven app / custom pages
        -> Dataverse
        -> Power Automate
```

Admin Panel MVP can use mostly model-driven table views and forms. My Work and Quote Detail side panel may use Power Apps custom page design if a cleaner daily UX is needed.

## Shared Prompt Requirements

Every Stitch prompt should include:

- product name: Revenue Follow-Up Workbench
- roles: TSR, CSSR, Manager, GM, Admin
- core objects: work item, quote, quote line, backorder, staff alias, branch membership, policy, assignment exception
- key metrics: Due Today, Overdue, Quotes >= $3K, Missing Attempts, Roadblocks
- sticky note shown prominently
- Last Followed Up On shown prominently
- Attempts shown as `0/3`, `1/3`, `2/3`, or `3/3`
- quick actions: Log Call, Log Email, Customer Advised, Set Next Follow-Up, Add Sticky Note, Roadblock, Escalate, Won, Lost
- clean table/list layout
- mobile-friendly enough for quick review, optimized for desktop branch staff
- no hardcoded people, emails, branches, IDs, or live production customer data
- accessible contrast and readable spacing

## Prompt 1 - My Work Page

```text
Design a Google Stitch screen for Revenue Follow-Up Workbench: My Work.

Create a clean, operations-focused Power Apps custom page concept for TSR and CSSR users. The screen should be optimized for desktop branch staff but usable on mobile for quick review.

Roles: TSR, CSSR, Manager, GM, Admin.

Core objects: work item, quote, quote line, backorder, staff alias, branch membership, policy, assignment exception.

Show top summary filters for Due Today, Overdue, Quotes >= $3K, Missing Attempts, and Roadblocks. Use a dense worklist/table layout with columns for customer, source document, total value, owner, status, Last Followed Up On, next follow-up, sticky note indicator, and Attempts as 0/3, 1/3, 2/3, or 3/3.

Primary actions should be visible and low-click: Log Call, Log Email, Customer Advised, Set Next Follow-Up, Add Sticky Note, Roadblock, Escalate, Won, Lost.

Show sticky note content prominently when a work item is selected. Keep the design simple, readable, accessible, and free of hardcoded people, emails, branch names, IDs, or production customer data. Avoid dashboard clutter and decorative marketing-style visuals.
```

## Prompt 2 - Quote Work Item Detail / Side Panel

```text
Design a Google Stitch screen for Revenue Follow-Up Workbench: Quote Work Item detail side panel.

Create a compact Power Apps custom page side panel concept for reviewing and acting on a quote work item. It should support TSR, CSSR, Manager, GM, and Admin roles.

Core objects: work item, quote, quote line, backorder, staff alias, branch membership, policy, assignment exception.

At the top, show quote number, customer, total value, status, owner, support owner, Attempts 0/3 through 3/3, Last Followed Up On, and Next Follow-Up On. Show the Sticky Note prominently near the top with an Add/Edit Sticky Note action.

Include action buttons: Log Call, Log Email, Customer Advised, Set Next Follow-Up, Roadblock, Escalate, Won, Lost.

Below the summary, show action history with action date, action type, action by, counts as attempt, and notes. Include quote line drill-through or a compact quote line summary. Make it readable, low-click, accessible, and optimized for desktop operations staff with mobile-friendly review behavior. Do not include hardcoded people, emails, branches, IDs, or production customer data.
```

## Prompt 3 - Manager Panel

```text
Design a Google Stitch screen for Revenue Follow-Up Workbench: Manager Panel.

Create a clean operations dashboard and worklist for branch managers. The goal is not a decorative dashboard; it is a practical management view for workload, exceptions, and follow-up risk.

Roles: TSR, CSSR, Manager, GM, Admin.

Core objects: work item, quote, quote line, backorder, staff alias, branch membership, policy, assignment exception.

Show summary filters/cards for Due Today, Overdue, Quotes >= $3K, Missing Attempts, Roadblocks, and Unassigned/Assignment Exceptions. The main area should be a dense table grouped by owner or branch team, showing work item, customer, total value, owner, support owner, status, Last Followed Up On, Attempts 0/3 through 3/3, sticky note preview, and next follow-up.

Manager actions: reassign owner, map staff alias, resolve assignment exception, add sticky note, escalate, mark roadblock, send reminder as a future placeholder.

Use accessible contrast, readable spacing, clear status chips, and no hardcoded people, emails, branches, IDs, or production customer data.
```

## Prompt 4 - Admin Panel MVP

```text
Design a Google Stitch screen for Revenue Follow-Up Workbench: Admin Panel MVP.

Create a model-driven Power Apps admin area concept using simple Dataverse-style tables, filters, and forms. This is an admin configuration surface, not a polished staff work queue.

Roles: Admin, Manager, GM, TSR, CSSR.

Core objects: work item, quote, quote line, backorder, staff alias, branch membership, policy, assignment exception.

Include navigation for Staff, Branch Memberships, Staff Alias Mapping, Branch Policies, Assignment Exceptions, Work Items, Work Item Actions, and Alert Logs. Branch Policy should expose threshold operator, work item generation mode, first follow-up basis, first follow-up business days, GM CC mode, Manager CC mode, and CSSR alert mode.

Work Item admin review should show Sticky Note, Sticky Note Updated On, Sticky Note Updated By, Last Followed Up On, Last Action On, Completed Attempts, and Required Attempts. Work Item Actions should show action date, action type, action by, counts as attempt, and notes.

Keep it simple, dense, readable, and suitable for Dataverse model-driven forms/views. Do not include hardcoded people, emails, branches, IDs, or production customer data.
```

Phase 2.1 dedicated Admin Panel MVP prompt:

- `docs/revenue-follow-up-admin-panel-mvp-google-stitch-prompt.md`
- Product: Revenue Follow-Up Workbench
- Page: Admin Panel MVP
- Implementation target: Power Apps model-driven app backed by Dataverse
- Stitch remains design/prototype guidance only, not production frontend code.
- Roles for the Admin Panel MVP prompt: Admin, GM, Manager.

## Prompt 5 - GM Review Page

```text
Design a Google Stitch screen for Revenue Follow-Up Workbench: GM Review.

Create a focused review screen for GM users who need to see escalations, roadblocks, overdue high-value quotes, and branch-level follow-up risk.

Roles: GM, Manager, Admin, TSR, CSSR.

Core objects: work item, quote, quote line, backorder, staff alias, branch membership, policy, assignment exception.

Show sections for Escalated/Roadblock, Overdue, Quotes >= $3K, Missing Attempts, and Branch Exceptions. Use a table/list layout with branch, customer, work item, total value, owner, support owner, status, Attempts 0/3 through 3/3, Last Followed Up On, Sticky Note preview, and next follow-up.

GM actions should be restrained: review detail, add sticky note, request manager action, escalate, mark reviewed. Keep the design executive-readable but operational, with accessible contrast and no decorative clutter. Do not include hardcoded people, emails, branches, IDs, or production customer data.
```
