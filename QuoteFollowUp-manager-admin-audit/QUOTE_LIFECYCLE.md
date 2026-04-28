# Quote Lifecycle

## Source

Quote follow-up data is expected to come from SAP SP830 workbook/report ingress through mailbox-triggered Power Automate flows. The repo contains parser and repair logic for Southern Alberta report families, but a complete exported SP830 production flow was not found in the stored workflow folder.

## Import / Create / Read

- Production ingestion should be Power Automate, with mailbox trigger logic kept thin and shared child flows used for parsing/normalization.
- qfu_quote is the current-state quote table. Its canonical source key is documented as branch|SP830|quotenumber.
- qfu_quoteline stores quote line/detail data and uses source lineage fields such as source family, source file, source worksheet, unique key, quote number, and branch/region slugs.
- Power Pages reads the tables through Web API allowlists rather than Basic Forms or Entity Lists.

## Status And Dates

- Quote status is stored as qfu_status.
- Follow-up due date is stored as qfu_nextfollowup on qfu_quote and qfu_followupdate on qfu_quoteline.
- Overdue state is represented by qfu_overduesince, summary overdue counts, and runtime filtering.
- The exact business rule that calculates next follow-up dates was not fully proven from stored flow exports; it should be exported from the SP830 flow or documented from the live environment.

## Ownership And Assignment

- Quote owner/assignee fields include qfu_assignedto, qfu_tsr, qfu_cssrname, qfu_followupowner, qfu_tsrname, and related line fields.
- Dedicated TSR, CSSR, branch manager, GM, and staff assignment tables were not found in the repo.
- Assignment appears stored as text/source fields rather than normalized user/staff records.

## Completion, Overdue, Reassignment, Closed/Won/Lost

- Completion is inferred from quote/line status and current-state lifecycle rather than a documented completion/audit table.
- Overdue quotes are surfaced in branch and detail routes from Dataverse rows and summary tables.
- Reassignment workflow was not found as a stored flow or admin component.
- Closed/lost/won statuses are expected to be represented in qfu_status and summary fields such as quotes won/lost/open in the last 30 days. The source-of-truth status mapping should be exported from the live SP830 ingestion flow.