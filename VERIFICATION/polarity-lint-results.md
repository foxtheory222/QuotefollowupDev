# Polarity Lint Results

- Authoritative files checked: 5
- Suspicious polarity hits: 0

## Current Portal Probe Evidence

| Branch | Budget Id | Raw qfu_isactive | Formatted Label |
| --- | --- | --- | --- |
| 4171 | 7584c6c8-a533-f111-88b4-000d3a59294a | False | Yes |
| 4172 | 7984c6c8-a533-f111-88b4-000d3a59294a | False | Yes |
| 4173 | 7b84c6c8-a533-f111-88b4-000d3a59294a | False | Yes |
| 4171 | 82fac0ce-a533-f111-88b4-000d3a59294a | True | No |
| 4172 | 84fac0ce-a533-f111-88b4-000d3a59294a | True | No |
| 4173 | 86fac0ce-a533-f111-88b4-000d3a59294a | True | No |

## active-aware

- C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\powerpages-live\operations-hub---operationhub\web-templates\qfu-regional-runtime\QFU-Regional-Runtime.webtemplate.source.html:176: return parseBoolean(record && record.qfu_isactive) === false;
- C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\scripts\create-southern-alberta-pilot-flow-solution.ps1:1609: Set-FieldValue -Map $getActiveBudgetParameters -Name '$filter' -Value "qfu_isactive eq false and qfu_branchcode eq '@{parameters('qfu_QFU_BranchCode')}' and qfu_sourcefamily eq 'SA1300'"
- C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\scripts\normalize-live-sa1300-current-budgets.ps1:177: qfu_isactive = $false
- C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\scripts\repair-southern-alberta-live-dashboard-data.ps1:359: qfu_isactive = $false

## explicit-inactive-write

- C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\scripts\normalize-live-sa1300-current-budgets.ps1:212: qfu_isactive = $true
- C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\scripts\repair-southern-alberta-live-dashboard-data.ps1:367: qfu_isactive = $true

## manual-review

- C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\powerpages-live\operations-hub---operationhub\web-templates\qfu-regional-runtime\QFU-Regional-Runtime.webtemplate.source.html:7: * - INVERTED ENVIRONMENT: qfu_isactive false = active, true = inactive.
- C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\powerpages-live\operations-hub---operationhub\web-templates\qfu-regional-runtime\QFU-Regional-Runtime.webtemplate.source.html:174: // INVERTED ENVIRONMENT: qfu_isactive false = active, true = inactive.
- C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\powerpages-live\operations-hub---operationhub\web-templates\qfu-regional-runtime\QFU-Regional-Runtime.webtemplate.source.html:2419: safeGetAll(withFilter("/_api/qfu_budgets?$select=qfu_budgetid,qfu_budgetname,qfu_actualsales,qfu_budgetgoal,qfu_lastupdated,qfu_cadsales,qfu_usdsales,qfu_month,qfu_monthname,qfu_year,qfu_fiscalyear,qfu_isactive,qfu_sourcefamily,qfu_branchcode,qfu_branchslug,qfu_regionslug,qfu_opsdailycadjson,qfu_opsdailyusdjson,createdon&$top=" + BUDGETS_FETCH_TOP, scopedFilter), "qfu_budgets", runtimeDiagnostics, { top: BUDGETS_FETCH_TOP, critical: true, branchSlug: context.branchSlug, regionSlug: context.regionSlug }),
- C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\scripts\create-southern-alberta-pilot-flow-solution.ps1:1685: Set-FieldValue -Map $itemMap -Name "qfu_isactive" -Value $false
- C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\scripts\create-southern-alberta-pilot-flow-solution.ps1:1706: Set-FieldValue -Map $updateCurrent -Name "qfu_isactive" -Value $false
- C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\scripts\create-southern-alberta-pilot-flow-solution.ps1:1847: Add-Note -Notes $Notes -Text "Budget flow now enforces trigger concurrency = 1, treats qfu_isactive false as active, resolves current-month rows by qfu_sourceid plus active fiscal year, falls back from qfu_budgetarchive to the SA1300 Month-End Plan before flagging a missing target, checks branch+month+fiscal year before creating qfu_budgetarchive, replaces the current branch's same-day qfu_marginexception snapshot directly from the SA1300 abnormal margin sheet, refreshes qfu_branchopsdaily rows from branch-configured SA1300 Daily Sales- Location ranges without overlapping USD/CAD temporary tables, and stores the latest CAD/USD Daily Sales- Location payload on the current qfu_budget row for analytics."
- C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\scripts\normalize-live-sa1300-current-budgets.ps1:83: function Test-BudgetRowIsActive {
- C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\scripts\normalize-live-sa1300-current-budgets.ps1:86: $value = if ($Row.PSObject.Properties['qfu_isactive']) { $Row.qfu_isactive } else { $null }
- C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\scripts\normalize-live-sa1300-current-budgets.ps1:91: # Current portal/Web API evidence shows formatted "Yes" on rows where raw qfu_isactive = false.
- C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\scripts\normalize-live-sa1300-current-budgets.ps1:114: @{ Expression = { if (Test-BudgetRowIsActive -Row $_) { 1 } else { 0 } }; Descending = $true }, `
- C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\scripts\normalize-live-sa1300-current-budgets.ps1:150: "qfu_isactive",
- C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\scripts\normalize-live-sa1300-current-budgets.ps1:193: "qfu_isactive",
- C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\scripts\normalize-live-sa1300-current-budgets.ps1:199: (Test-BudgetRowIsActive -Row $_) -and
- C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\scripts\repair-southern-alberta-live-dashboard-data.ps1:98: function Test-BudgetRowIsActive {
- C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\scripts\repair-southern-alberta-live-dashboard-data.ps1:101: $value = if ($Row.PSObject.Properties['qfu_isactive']) { $Row.qfu_isactive } else { $null }
- C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\scripts\repair-southern-alberta-live-dashboard-data.ps1:106: # Current portal/Web API evidence shows formatted "Yes" on rows where raw qfu_isactive = false.
- C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\scripts\repair-southern-alberta-live-dashboard-data.ps1:331: "qfu_isactive",
- C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\scripts\repair-southern-alberta-live-dashboard-data.ps1:339: @{ Expression = { if (Test-BudgetRowIsActive -Row $_) { 1 } else { 0 } }; Descending = $true }, `
