# Power Apps Maker Admin Panel Build Checklist

Date: 2026-04-27

Environment URL: `https://orga632edd5.crm3.dynamics.com/`

Portal URL for the same dev copy: `https://operationscenter.powerappsportals.com`

Solution: `qfu_revenuefollowupworkbench`

App name: Revenue Follow-Up Workbench

Phase: Phase 2.1 - Admin Panel MVP app, forms, views, and navigation

Status: manual-required. PAC and the available safe tooling can export, unpack, and verify the solution, but do not provide a supported, stable command path for creating the model-driven app shell, sitemap navigation, forms, and required views. Do not create fragile raw app metadata through direct Web API writes for this phase.

## Scope

In scope:

- Create or validate the model-driven app shell.
- Create the Admin Panel MVP area.
- Add navigation for the eight Phase 2 tables.
- Create the documented main forms.
- Create the documented model-driven views.
- Publish customizations.
- Export and unpack the unmanaged solution after manual build.

Out of scope:

- Old Power Pages ops-admin workflow changes.
- Resolver flows.
- Alerts and digests.
- TSR/CSSR My Work custom page.
- Manager Panel.
- GM Review.
- Security roles.
- Command bar customizations beyond default model-driven commands.
- Hardcoded staff, emails, branch routing, AM numbers, CSSR numbers, thresholds, or people.

## Precheck

1. Open [Power Apps Maker Portal](https://make.powerapps.com/).
2. Select the environment whose organization URL is `https://orga632edd5.crm3.dynamics.com/`.
3. Open Solutions.
4. Confirm solution `qfu_revenuefollowupworkbench` exists.
5. Confirm these tables exist in the solution:
   - `qfu_staff`
   - `qfu_branchmembership`
   - `qfu_staffalias`
   - `qfu_policy`
   - `qfu_assignmentexception`
   - `qfu_workitem`
   - `qfu_workitemaction`
   - `qfu_alertlog`

## Create The App

1. Open solution `qfu_revenuefollowupworkbench`.
2. Select New > App > Model-driven app.
3. Set Name to `Revenue Follow-Up Workbench`.
4. Use the modern app designer.
5. Add one area named `Admin Panel MVP`.
6. Add these navigation pages in this order:
   - Staff
   - Branch Memberships
   - Staff Alias Mapping
   - Branch Policies
   - Assignment Exceptions
   - Work Items
   - Work Item Actions
   - Alert Logs
7. Map the navigation labels to these tables:

| Navigation label | Table logical name |
| --- | --- |
| Staff | `qfu_staff` |
| Branch Memberships | `qfu_branchmembership` |
| Staff Alias Mapping | `qfu_staffalias` |
| Branch Policies | `qfu_policy` |
| Assignment Exceptions | `qfu_assignmentexception` |
| Work Items | `qfu_workitem` |
| Work Item Actions | `qfu_workitemaction` |
| Alert Logs | `qfu_alertlog` |

## Forms

Create or update one main form per table. Use concise section names such as Summary, Ownership, Policy, Resolution, Activity, and Notes. Keep the fields below visible without requiring custom frontend code.

### Staff

Fields:

- Staff Name: `qfu_name`
- Primary Email: `qfu_primaryemail`
- Staff Number: `qfu_staffnumber`
- Dataverse User: `qfu_systemuser`
- Entra Object ID: `qfu_entraobjectid`
- Default Branch: `qfu_defaultbranch`
- Active: `qfu_active`
- Notes: `qfu_notes`

### Branch Membership

Fields:

- Branch: `qfu_branch`
- Staff: `qfu_staff`
- Role: `qfu_role`
- Active: `qfu_active`
- Start Date: `qfu_startdate`
- End Date: `qfu_enddate`
- Is Primary: `qfu_isprimary`
- Notes: `qfu_notes`

### Staff Alias Mapping

Fields:

- Source System: `qfu_sourcesystem`
- Alias Type: `qfu_aliastype`
- Raw Alias: `qfu_rawalias`
- Normalized Alias: `qfu_normalizedalias`
- Role Hint: `qfu_rolehint`
- Branch: `qfu_branch`
- Scope Key: `qfu_scopekey`
- Staff: `qfu_staff`
- Active: `qfu_active`
- Verified By: `qfu_verifiedby`
- Verified On: `qfu_verifiedon`
- Notes: `qfu_notes`

### Branch Policy

Fields:

- Policy Name: `qfu_name`
- Branch: `qfu_branch`
- Scope Key: `qfu_scopekey`
- Work Type: `qfu_worktype`
- High-Value Threshold: `qfu_highvaluethreshold`
- Threshold Operator: `qfu_thresholdoperator`
- Work Item Generation Mode: `qfu_workitemgenerationmode`
- Required Attempts: `qfu_requiredattempts`
- First Follow-Up Basis: `qfu_firstfollowupbasis`
- First Follow-Up Business Days: `qfu_firstfollowupbusinessdays`
- Primary Owner Strategy: `qfu_primaryownerstrategy`
- Support Owner Strategy: `qfu_supportownerstrategy`
- GM CC Mode: `qfu_gmccmode`
- Manager CC Mode: `qfu_managerccmode`
- CSSR Alert Mode: `qfu_cssralertmode`
- Escalate After Business Days: `qfu_escalateafterbusinessdays`
- Digest Enabled: `qfu_digestenabled`
- Targeted Alert Enabled: `qfu_targetedalertenabled`
- Active: `qfu_active`

### Assignment Exception

Fields:

- Exception Type: `qfu_exceptiontype`
- Branch: `qfu_branch`
- Source System: `qfu_sourcesystem`
- Source Field: `qfu_sourcefield`
- Raw Value: `qfu_rawvalue`
- Normalized Value: `qfu_normalizedvalue`
- Display Name: `qfu_displayname`
- Source Document Number: `qfu_sourcedocumentnumber`
- Source External Key: `qfu_sourceexternalkey`
- Source Quote: `qfu_sourcequote`
- Source Quote Line: `qfu_sourcequoteline`
- Source Backorder: `qfu_sourcebackorder`
- Work Item: `qfu_workitem`
- Status: `qfu_status`
- Resolved Staff: `qfu_resolvedstaff`
- Resolved By: `qfu_resolvedby`
- Resolved On: `qfu_resolvedon`
- Notes: `qfu_notes`

### Work Item

Put these fields near the top:

- Work Item Number: `qfu_workitemnumber`
- Work Type: `qfu_worktype`
- Source System: `qfu_sourcesystem`
- Branch: `qfu_branch`
- Source Document Number: `qfu_sourcedocumentnumber`
- Sticky Note: `qfu_stickynote`
- Sticky Note Updated On: `qfu_stickynoteupdatedon`
- Sticky Note Updated By: `qfu_stickynoteupdatedby`
- Customer Name: `qfu_customername`
- Total Value: `qfu_totalvalue`
- Primary Owner Staff: `qfu_primaryownerstaff`
- Support Owner Staff: `qfu_supportownerstaff`
- TSR Staff: `qfu_tsrstaff`
- CSSR Staff: `qfu_cssrstaff`
- Required Attempts: `qfu_requiredattempts`
- Completed Attempts: `qfu_completedattempts`
- Status: `qfu_status`
- Priority: `qfu_priority`
- Next Follow-Up On: `qfu_nextfollowupon`
- Last Followed Up On: `qfu_lastfollowedupon`
- Last Action On: `qfu_lastactionon`
- Overdue Since: `qfu_overduesince`
- Escalation Level: `qfu_escalationlevel`
- Policy: `qfu_policy`
- Assignment Status: `qfu_assignmentstatus`
- Notes: `qfu_notes`

### Work Item Action

Fields:

- Work Item: `qfu_workitem`
- Action Type: `qfu_actiontype`
- Counts As Attempt: `qfu_countsasattempt`
- Action By: `qfu_actionby`
- Action On: `qfu_actionon`
- Attempt Number: `qfu_attemptnumber`
- Outcome: `qfu_outcome`
- Next Follow-Up On: `qfu_nextfollowupon`
- Related Alert: `qfu_relatedalert`
- Notes: `qfu_notes`

### Alert Log

Fields:

- Work Item: `qfu_workitem`
- Alert Type: `qfu_alerttype`
- Recipient Staff: `qfu_recipientstaff`
- Recipient Email: `qfu_recipientemail`
- CC Emails: `qfu_ccemails`
- Dedupe Key: `qfu_dedupekey`
- Status: `qfu_status`
- Sent On: `qfu_senton`
- Failure Message: `qfu_failuremessage`
- Flow Run ID: `qfu_flowrunid`
- Notes: `qfu_notes`

## Views

Create these public views. Keep columns dense and operational, with owner/status/date fields visible where relevant.

### Staff

- Active Staff
- Staff Missing Email
- Staff Missing Dataverse User

### Branch Memberships

- Active Branch Memberships
- Memberships by Branch
- Memberships by Role

### Staff Alias Mapping

- Active Aliases
- Unverified Aliases
- Aliases by Source System
- Potential Duplicate Aliases

### Branch Policies

- Active Policies
- Draft/Inactive Policies
- Policies by Branch
- Quote Policies

### Assignment Exceptions

- Open Assignment Exceptions
- Missing TSR Alias
- Missing CSSR Alias
- Blank/Zero Alias Exceptions
- Resolved Exceptions

### Work Items

- Open Work Items
- Needs TSR Assignment
- Needs CSSR Assignment
- Quotes >= $3K
- Overdue Work Items
- Work Items with Sticky Notes

### Work Item Actions

- Recent Actions
- Attempt Actions
- Non-Attempt Actions

### Alert Logs

- Pending Alerts
- Failed Alerts
- Sent Alerts
- Suppressed/Skipped Alerts

## Publish And Verify

1. Save each form.
2. Save each view.
3. Save and publish the model-driven app.
4. Publish all customizations in the solution.
5. Open the app as an Admin or Maker.
6. Verify the Admin Panel MVP area opens.
7. Verify every navigation item opens its table.
8. Verify the Work Item form shows Sticky Note, Last Followed Up On, Completed Attempts, Required Attempts, and Assignment Status near the top.
9. Verify no hardcoded people, emails, branches, routing rules, AM numbers, CSSR numbers, or thresholds were added to app metadata.

## Export And Unpack

After the manual build is published, run these from the workspace:

```powershell
pac solution export --environment "https://orga632edd5.crm3.dynamics.com/" --name qfu_revenuefollowupworkbench --path ".\solution\exports\qfu_revenuefollowupworkbench-phase2-1-unmanaged.zip" --managed false --overwrite
pac solution unpack --zipfile ".\solution\exports\qfu_revenuefollowupworkbench-phase2-1-unmanaged.zip" --folder ".\solution\revenue-follow-up-workbench\phase2-1-unpacked" --packagetype Unmanaged --allowDelete true --allowWrite true
```

Then confirm the unpacked solution contains app module and sitemap metadata before marking Phase 2.1 live-functional.
