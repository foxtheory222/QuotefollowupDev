[CmdletBinding()]
param(
  [string]$BudgetRowsPath = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "QFU_FINAL_AUDIT_STAGING\DATA\dataverse-rows\qfu_budget.rows.json"),
  [string[]]$BranchCodes = @("4171", "4172", "4173"),
  [datetime]$AsOfDate = (Get-Date),
  [string]$OutputJson = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "VERIFICATION\dryrun-budget-duplicate-report.json"),
  [string]$OutputMarkdown = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "VERIFICATION\dryrun-budget-duplicate-report.md"),
  [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

& (Join-Path $PSScriptRoot "normalize-live-sa1300-current-budgets.ps1") `
  -BudgetRowsPath $BudgetRowsPath `
  -BranchCodes $BranchCodes `
  -AsOfDate $AsOfDate `
  -OutputJson $OutputJson `
  -OutputMarkdown $OutputMarkdown `
  -WhatIf:$WhatIf
