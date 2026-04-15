# Polarity Lint Results

- Authoritative files checked: 4
- Suspicious polarity hits: 0

## active-aware

- C:\Dev\QuoteFollowUpComplete\RAW\scripts\create-southern-alberta-pilot-flow-solution.ps1:2051: Set-FieldValue -Map $getActiveBudgetParameters -Name '$filter' -Value "qfu_isactive eq false and qfu_branchcode eq '@{parameters('qfu_QFU_BranchCode')}' and qfu_sourcefamily eq 'SA1300'"
- C:\Dev\QuoteFollowUpComplete\RAW\scripts\normalize-live-sa1300-current-budgets.ps1:177: qfu_isactive = $false
- C:\Dev\QuoteFollowUpComplete\RAW\scripts\repair-southern-alberta-live-dashboard-data.ps1:359: qfu_isactive = $false

## explicit-inactive-write

- C:\Dev\QuoteFollowUpComplete\RAW\scripts\normalize-live-sa1300-current-budgets.ps1:212: qfu_isactive = $true
- C:\Dev\QuoteFollowUpComplete\RAW\scripts\repair-southern-alberta-live-dashboard-data.ps1:367: qfu_isactive = $true

## manual-review

- C:\Dev\QuoteFollowUpComplete\RAW\scripts\create-southern-alberta-pilot-flow-solution.ps1:2127: Set-FieldValue -Map $itemMap -Name "qfu_isactive" -Value $false
- C:\Dev\QuoteFollowUpComplete\RAW\scripts\create-southern-alberta-pilot-flow-solution.ps1:2148: Set-FieldValue -Map $updateCurrent -Name "qfu_isactive" -Value $false
- C:\Dev\QuoteFollowUpComplete\RAW\scripts\create-southern-alberta-pilot-flow-solution.ps1:2289: Add-Note -Notes $Notes -Text "Budget flow now enforces trigger concurrency = 1, treats qfu_isactive false as active, resolves current-month rows by qfu_sourceid plus active fiscal year, falls back from qfu_budgetarchive to the SA1300 Month-End Plan before flagging a missing target, checks branch+month+fiscal year before creating qfu_budgetarchive, replaces the current branch's same-day qfu_marginexception snapshot directly from the SA1300 abnormal margin sheet, refreshes qfu_branchopsdaily rows from branch-configured SA1300 Daily Sales- Location ranges without overlapping USD/CAD temporary tables, and stores the latest CAD/USD Daily Sales- Location payload on the current qfu_budget row for analytics."
- C:\Dev\QuoteFollowUpComplete\RAW\scripts\normalize-live-sa1300-current-budgets.ps1:83: function Test-BudgetRowIsActive {
- C:\Dev\QuoteFollowUpComplete\RAW\scripts\normalize-live-sa1300-current-budgets.ps1:86: $value = if ($Row.PSObject.Properties['qfu_isactive']) { $Row.qfu_isactive } else { $null }
- C:\Dev\QuoteFollowUpComplete\RAW\scripts\normalize-live-sa1300-current-budgets.ps1:91: # Current portal/Web API evidence shows formatted "Yes" on rows where raw qfu_isactive = false.
- C:\Dev\QuoteFollowUpComplete\RAW\scripts\normalize-live-sa1300-current-budgets.ps1:114: @{ Expression = { if (Test-BudgetRowIsActive -Row $_) { 1 } else { 0 } }; Descending = $true }, `
- C:\Dev\QuoteFollowUpComplete\RAW\scripts\normalize-live-sa1300-current-budgets.ps1:150: "qfu_isactive",
- C:\Dev\QuoteFollowUpComplete\RAW\scripts\normalize-live-sa1300-current-budgets.ps1:193: "qfu_isactive",
- C:\Dev\QuoteFollowUpComplete\RAW\scripts\normalize-live-sa1300-current-budgets.ps1:199: (Test-BudgetRowIsActive -Row $_) -and
- C:\Dev\QuoteFollowUpComplete\RAW\scripts\repair-southern-alberta-live-dashboard-data.ps1:98: function Test-BudgetRowIsActive {
- C:\Dev\QuoteFollowUpComplete\RAW\scripts\repair-southern-alberta-live-dashboard-data.ps1:101: $value = if ($Row.PSObject.Properties['qfu_isactive']) { $Row.qfu_isactive } else { $null }
- C:\Dev\QuoteFollowUpComplete\RAW\scripts\repair-southern-alberta-live-dashboard-data.ps1:106: # Current portal/Web API evidence shows formatted "Yes" on rows where raw qfu_isactive = false.
- C:\Dev\QuoteFollowUpComplete\RAW\scripts\repair-southern-alberta-live-dashboard-data.ps1:331: "qfu_isactive",
- C:\Dev\QuoteFollowUpComplete\RAW\scripts\repair-southern-alberta-live-dashboard-data.ps1:339: @{ Expression = { if (Test-BudgetRowIsActive -Row $_) { 1 } else { 0 } }; Descending = $true }, `
