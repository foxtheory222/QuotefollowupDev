# Power Platform Inventory

## Power Apps
- Power Pages site export: site/.
- Refreshed live Power Pages source: powerpages-live/operations-hub---operationhub/.
- No canvas app export or model-driven app source package was found in the repo. Export app packages and solution metadata from Power Apps to complete that portion of the audit.

## Power Automate Flows Stored In Repo
### 4171-Budget-Update-SA1300-<GUID>
- File: results/sapilotflows/src/Workflows/4171-Budget-Update-SA1300-_GUID_.json
- State in export: Unreadable
- Trigger: 
- Main actions: 
- Source data: Office 365 shared mailbox attachments and Excel workbook tables, based on connectors/actions in the export.
- Destination data: Dataverse qfu_budget, qfu_budgetarchive, qfu_branchopsdaily, and related SA1300 summary data.
- Alert/email/Teams logic: No explicit scalable user alerting flow was proven in the stored workflow exports; error handling is mostly flow-level failure and variable/scope checks.
- Error handling: Stored SA1300 flows contain budget-target error handling and conditional failure paths; full run-after/error notification coverage needs live export review.
- Retry logic: Connector default retry policy unless explicit retry policy is present in the flow JSON; no centralized retry table was found.
- Hardcoding risk: Branch defaults, branch slugs, source families, subject filters, and mailbox parameters are present. Some are parameterized, but the branch-specific flow files remain separate pilot artifacts.
### 4172-Budget-Update-SA1300-<GUID>
- File: results/sapilotflows/src/Workflows/4172-Budget-Update-SA1300-_GUID_.json
- State in export: Unreadable
- Trigger: 
- Main actions: 
- Source data: Office 365 shared mailbox attachments and Excel workbook tables, based on connectors/actions in the export.
- Destination data: Dataverse qfu_budget, qfu_budgetarchive, qfu_branchopsdaily, and related SA1300 summary data.
- Alert/email/Teams logic: No explicit scalable user alerting flow was proven in the stored workflow exports; error handling is mostly flow-level failure and variable/scope checks.
- Error handling: Stored SA1300 flows contain budget-target error handling and conditional failure paths; full run-after/error notification coverage needs live export review.
- Retry logic: Connector default retry policy unless explicit retry policy is present in the flow JSON; no centralized retry table was found.
- Hardcoding risk: Branch defaults, branch slugs, source families, subject filters, and mailbox parameters are present. Some are parameterized, but the branch-specific flow files remain separate pilot artifacts.
### 4173-Budget-Update-SA1300-<GUID>
- File: results/sapilotflows/src/Workflows/4173-Budget-Update-SA1300-_GUID_.json
- State in export: Unreadable
- Trigger: 
- Main actions: 
- Source data: Office 365 shared mailbox attachments and Excel workbook tables, based on connectors/actions in the export.
- Destination data: Dataverse qfu_budget, qfu_budgetarchive, qfu_branchopsdaily, and related SA1300 summary data.
- Alert/email/Teams logic: No explicit scalable user alerting flow was proven in the stored workflow exports; error handling is mostly flow-level failure and variable/scope checks.
- Error handling: Stored SA1300 flows contain budget-target error handling and conditional failure paths; full run-after/error notification coverage needs live export review.
- Retry logic: Connector default retry policy unless explicit retry policy is present in the flow JSON; no centralized retry table was found.
- Hardcoding risk: Branch defaults, branch slugs, source families, subject filters, and mailbox parameters are present. Some are parameterized, but the branch-specific flow files remain separate pilot artifacts.

## Dataverse Tables Identified
- qfu_backorder
- qfu_branch
- qfu_branchdailysummary
- qfu_branchopsdaily
- qfu_budget
- qfu_budgetarchive
- qfu_deliverynotpgi
- qfu_financesnapshot
- qfu_financevariance
- qfu_freightworkitem
- qfu_ingestionbatch
- qfu_lateorderexception
- qfu_marginexception
- qfu_quote
- qfu_quoteline
- qfu_region
- qfu_sourcefeed

## SharePoint Lists
- No SharePoint list definitions or exported list schemas were found in the repo. Export list schemas, permissions, and Power Platform connection references if SharePoint is still part of the live app.

## Excel Data Sources
- SA1300 workbook reports: budget and daily ops source.
- ZBO workbook/mailbox captures: backorder source.
- SP830 workbook/mailbox captures: quote source.
- GL060 workbook reports: freight/financial operations source.
- Freight report files: parsed by scripts/freight_parser.py and hosted parser code.

## Connectors And Connection References
- shared_office365 / qfu_shared_office365.
- shared_onedriveforbusiness / qfu_shared_onedriveforbusiness.
- shared_excelonlinebusiness / qfu_shared_excelonlinebusiness.
- shared_commondataserviceforapps / qfu_shared_commondataserviceforapps.

## Environment Variables
- qfu_QFU_OneDriveDriveId
- qfu_QFU_OneDriveFolderPath
- qfu_QFU_ActiveFiscalYear
- qfu_QFU_OutlookFolderId
- qfu_QFU_OfficeScriptId
- qfu_QFU_BranchCode
- qfu_QFU_BranchSlug
- qfu_QFU_BranchName
- qfu_QFU_RegionSlug
- qfu_QFU_SharedMailboxAddress
- qfu_QFU_SharedMailboxFolderId

## Solution Files / Exported Components
- Power Pages Enhanced/source export folders: site/, powerpages-live/operations-hub---operationhub/.
- Unpacked workflow JSON: results/sapilotflows/src/Workflows/.
- Power Pages metadata: web pages, web templates, web files, content snippets, table permissions, web roles, site settings.
