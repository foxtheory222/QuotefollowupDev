# Audit Summary

QuoteFollowUp is a centralized internal branch operations monitoring project. The repo preserves the Power Pages monitoring experience, Power Pages Web API configuration, Dataverse table permission metadata, Power Automate workflow exports for the Southern Alberta pilot, repair/verification scripts, and a hosted freight parser Function app.

## What The Project Currently Does

- Presents a Power Pages operations hub with hub, region, branch, analytics, detail, freight, and admin-style routes concentrated in site/web-templates/qfu-regional-runtime/QFU-Regional-Runtime.webtemplate.source.html and the refreshed live copy under powerpages-live/operations-hub---operationhub.
- Reads operational data through Power Pages /_api calls guarded by Webapi/<table>/enabled and Webapi/<table>/fields site settings.
- Uses Dataverse qfu_* tables as the operating data store for regions, branches, quotes, quote lines, backorders, budgets, summaries, ingestion batches, delivery-not-PGI rows, freight work items, finance snapshots, and exception data.
- Uses Power Automate workflow exports in esults/sapilotflows/src/Workflows for SA1300 budget ingestion for branches 4171, 4172, and 4173.
- Uses scripts under scripts/ and RAW/scripts/ for generation, diagnostics, repair, replay, and local validation. Several scripts are live repair helpers and should not be treated as recurring production ingestion.
- Includes an Azure Functions-style hosted freight parser under src/freight_parser_host.

## Current Quote Follow-Up Process

Quotes are represented in Dataverse as qfu_quote current-state rows and qfu_quoteline detail rows. The documented source family for quote follow-up is SP830. The expected current-state key is branch|SP830|quotenumber. The portal reads quote rows and quote line rows through Web API allowlists, calculates operational views and overdue/follow-up indicators in the runtime, and surfaces branch/region/dashboard summaries. Re-seen quotes should update in place; missing quotes from a latest snapshot should become inactive via qfu_active, qfu_inactiveon, and qfu_lastseenon.

## Component Split

- Code: Power Pages runtime HTML/JS/CSS, Python parsers, PowerShell repair/generator scripts, JavaScript browser checks, tests.
- Power Apps: No canvas or model-driven app source export was found in this repo. The monitoring UX is Power Pages.
- Power Automate: Three stored workflow JSON exports for SA1300 budget update flows are present. Other live flows referenced by scripts and docs are not fully exported here.
- SharePoint: No SharePoint list schema export was found. SharePoint appears only as a related platform concern and possible file/storage dependency, not as stored list definitions.
- Dataverse: Dataverse is the primary source of truth; table names and columns are documented from Power Pages Web API allowlists, table permissions, scripts, and flow JSON.
- Excel: SAP report workbooks such as SA1300, ZBO, SP830, GL060, and freight workbooks are source files; production workbooks are not included.
- SQL: No SQL database schema or code path was found in the repo.
- Email: Shared mailbox triggers and replay helpers are used for report ingress. Stored workflow exports include Office 365 shared mailbox triggers.
- API: Power Pages Web API, Dataverse connector actions, Graph/Office/Excel connectors, and the hosted freight parser HTTP/function contract are present.
- Manual: Replay, repair, validation, and emergency seed scripts indicate manual operations still exist and need formal admin tooling.