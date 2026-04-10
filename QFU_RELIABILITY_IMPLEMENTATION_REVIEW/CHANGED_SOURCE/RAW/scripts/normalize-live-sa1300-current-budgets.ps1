[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [string]$BudgetRowsPath = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "QFU_FINAL_AUDIT_STAGING\DATA\dataverse-rows\qfu_budget.rows.json"),
  [string[]]$BranchCodes = @("4171", "4172", "4173"),
  [datetime]$AsOfDate = (Get-Date),
  [string]$OutputJson,
  [string]$OutputMarkdown,
  [switch]$Apply
)

$ErrorActionPreference = "Stop"

function Ensure-Directory {
  param([string]$Path)
  if (-not [string]::IsNullOrWhiteSpace($Path) -and -not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Write-Utf8File {
  param(
    [string]$Path,
    [string]$Content
  )

  $parent = Split-Path -Parent $Path
  Ensure-Directory $parent
  [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-ActiveFiscalYearLabel {
  param([datetime]$ReferenceDate)
  $date = $ReferenceDate
  $fiscalYear = if ($date.Month -ge 7) { $date.Year + 1 } else { $date.Year }
  return "FY{0}" -f ($fiscalYear % 100).ToString("00")
}

function Normalize-FiscalYearLabel {
  param(
    [object]$Value,
    [datetime]$FallbackDate
  )

  $text = [string]::IsNullOrWhiteSpace([string]$Value) ? "" : ([string]$Value).Trim().ToUpperInvariant()
  if ($text -match '^FY\d{2}$') {
    return $text
  }
  if ($text -match '^\d{4}$') {
    return "FY{0}" -f $text.Substring(2, 2)
  }
  return Get-ActiveFiscalYearLabel -ReferenceDate $FallbackDate
}

function Get-QfuBudgetTimestamp {
  param([object]$Row)

  foreach ($field in @('qfu_lastupdated__raw', 'qfu_lastupdated', 'modifiedon__raw', 'modifiedon', 'createdon__raw', 'createdon')) {
    if ($Row.PSObject.Properties[$field] -and -not [string]::IsNullOrWhiteSpace([string]$Row.$field)) {
      try {
        return [datetime]$Row.$field
      } catch {
      }
    }
  }

  return [datetime]::MinValue
}

function Get-QfuBudgetId {
  param([object]$Row)
  foreach ($field in @('qfu_budgetid__raw', 'qfu_budgetid', '_primaryid')) {
    if ($Row.PSObject.Properties[$field] -and -not [string]::IsNullOrWhiteSpace([string]$Row.$field)) {
      return [string]$Row.$field
    }
  }
  return ""
}

function Get-QfuSourceId {
  param([object]$Row)
  foreach ($field in @('qfu_sourceid__raw', 'qfu_sourceid')) {
    if ($Row.PSObject.Properties[$field] -and -not [string]::IsNullOrWhiteSpace([string]$Row.$field)) {
      return [string]$Row.$field
    }
  }
  return ""
}

function Get-QfuFieldValue {
  param(
    [object]$Row,
    [string]$PreferredRawField,
    [string]$DisplayField
  )

  if ($PreferredRawField -and $Row.PSObject.Properties[$PreferredRawField] -and $null -ne $Row.$PreferredRawField -and -not [string]::IsNullOrWhiteSpace([string]$Row.$PreferredRawField)) {
    return $Row.$PreferredRawField
  }
  if ($DisplayField -and $Row.PSObject.Properties[$DisplayField] -and $null -ne $Row.$DisplayField -and -not [string]::IsNullOrWhiteSpace([string]$Row.$DisplayField)) {
    return $Row.$DisplayField
  }
  return $null
}

function Test-QfuBudgetRowIsActive {
  param([object]$Row)

  # INVERTED ENVIRONMENT: qfu_isactive "No" = active, "Yes" = inactive.
  $label = if ($Row.PSObject.Properties['qfu_isactive'] -and $null -ne $Row.qfu_isactive) { ([string]$Row.qfu_isactive).Trim() } else { "" }
  if ($label) {
    switch -Regex ($label.ToLowerInvariant()) {
      '^no$' { return $true }
      '^yes$' { return $false }
      '^false$' { return $true }
      '^true$' { return $false }
    }
  }

  $raw = if ($Row.PSObject.Properties['qfu_isactive__raw']) { $Row.qfu_isactive__raw } else { $null }
  if ($raw -is [bool]) {
    return (-not $raw)
  }
  if ($null -ne $raw -and -not [string]::IsNullOrWhiteSpace([string]$raw)) {
    $rawText = ([string]$raw).Trim().ToLowerInvariant()
    if ($rawText -eq 'false') {
      return $true
    }
    if ($rawText -eq 'true') {
      return $false
    }
  }

  return $false
}

function Get-BudgetRepairCandidates {
  param(
    [object[]]$Rows,
    [string[]]$BranchCodes,
    [datetime]$AsOfDate
  )

  $monthNumber = $AsOfDate.Month
  $fiscalYear = Get-ActiveFiscalYearLabel -ReferenceDate $AsOfDate

  return @($Rows | Where-Object {
      $branchCode = [string](Get-QfuFieldValue -Row $_ -PreferredRawField 'qfu_branchcode__raw' -DisplayField 'qfu_branchcode')
      $rowMonth = [int](Get-QfuFieldValue -Row $_ -PreferredRawField 'qfu_month__raw' -DisplayField 'qfu_month')
      $rowFiscalYear = Normalize-FiscalYearLabel -Value (Get-QfuFieldValue -Row $_ -PreferredRawField 'qfu_fiscalyear__raw' -DisplayField 'qfu_fiscalyear') -FallbackDate $AsOfDate
      return $BranchCodes -contains $branchCode -and $rowMonth -eq $monthNumber -and $rowFiscalYear -eq $fiscalYear
    })
}

if (-not (Test-Path -LiteralPath $BudgetRowsPath)) {
  throw "Budget row evidence file not found: $BudgetRowsPath"
}

$rows = @(Get-Content -LiteralPath $BudgetRowsPath -Raw | ConvertFrom-Json)
$candidates = Get-BudgetRepairCandidates -Rows $rows -BranchCodes $BranchCodes -AsOfDate $AsOfDate

$groups = foreach ($group in ($candidates | Group-Object {
      $branchCode = [string](Get-QfuFieldValue -Row $_ -PreferredRawField 'qfu_branchcode__raw' -DisplayField 'qfu_branchcode')
      $monthNumber = [int](Get-QfuFieldValue -Row $_ -PreferredRawField 'qfu_month__raw' -DisplayField 'qfu_month')
      $fiscalYear = Normalize-FiscalYearLabel -Value (Get-QfuFieldValue -Row $_ -PreferredRawField 'qfu_fiscalyear__raw' -DisplayField 'qfu_fiscalyear') -FallbackDate $AsOfDate
      "{0}|{1}|{2}" -f $branchCode, $fiscalYear, $monthNumber
    })) {
  $sorted = @($group.Group | Sort-Object `
      @{ Expression = { if (Test-QfuBudgetRowIsActive -Row $_) { 0 } else { 1 } } }, `
      @{ Expression = { if (([string](Get-QfuFieldValue -Row $_ -PreferredRawField 'qfu_sourcefamily__raw' -DisplayField 'qfu_sourcefamily')).Trim().ToUpperInvariant() -eq 'SA1300') { 0 } else { 1 } } }, `
      @{ Expression = { -1 * (Get-QfuBudgetTimestamp -Row $_).Ticks } }, `
      @{ Expression = { -1 * [double](Get-QfuFieldValue -Row $_ -PreferredRawField 'qfu_actualsales__raw' -DisplayField 'qfu_actualsales') } }, `
      @{ Expression = { Get-QfuSourceId -Row $_ } })

  $chosen = $sorted | Select-Object -First 1
  $chosenId = Get-QfuBudgetId -Row $chosen

  # INVERTED ENVIRONMENT: active rows are the rows with qfu_isactive = "No" (or raw false when only raw data exists).
  $otherActiveRows = @($sorted | Where-Object {
      (Test-QfuBudgetRowIsActive -Row $_) -and (Get-QfuBudgetId -Row $_) -ne $chosenId
    })

  [pscustomobject]@{
    branchCode = [string](Get-QfuFieldValue -Row $chosen -PreferredRawField 'qfu_branchcode__raw' -DisplayField 'qfu_branchcode')
    fiscalYear = Normalize-FiscalYearLabel -Value (Get-QfuFieldValue -Row $chosen -PreferredRawField 'qfu_fiscalyear__raw' -DisplayField 'qfu_fiscalyear') -FallbackDate $AsOfDate
    monthNumber = [int](Get-QfuFieldValue -Row $chosen -PreferredRawField 'qfu_month__raw' -DisplayField 'qfu_month')
    candidateCount = $group.Count
    activeCandidateCount = @($sorted | Where-Object { Test-QfuBudgetRowIsActive -Row $_ }).Count
    chosen = [pscustomobject]@{
      budgetId = $chosenId
      sourceId = Get-QfuSourceId -Row $chosen
      active = Test-QfuBudgetRowIsActive -Row $chosen
      sourceFamily = [string](Get-QfuFieldValue -Row $chosen -PreferredRawField 'qfu_sourcefamily__raw' -DisplayField 'qfu_sourcefamily')
      lastUpdated = (Get-QfuBudgetTimestamp -Row $chosen).ToString("s")
      actualSales = [double](Get-QfuFieldValue -Row $chosen -PreferredRawField 'qfu_actualsales__raw' -DisplayField 'qfu_actualsales')
    }
    wouldDeactivate = @($otherActiveRows | ForEach-Object {
        [pscustomobject]@{
          budgetId = Get-QfuBudgetId -Row $_
          sourceId = Get-QfuSourceId -Row $_
          active = Test-QfuBudgetRowIsActive -Row $_
          lastUpdated = (Get-QfuBudgetTimestamp -Row $_).ToString("s")
          actualSales = [double](Get-QfuFieldValue -Row $_ -PreferredRawField 'qfu_actualsales__raw' -DisplayField 'qfu_actualsales')
        }
      })
    candidates = @($sorted | ForEach-Object {
        [pscustomobject]@{
          budgetId = Get-QfuBudgetId -Row $_
          sourceId = Get-QfuSourceId -Row $_
          active = Test-QfuBudgetRowIsActive -Row $_
          sourceFamily = [string](Get-QfuFieldValue -Row $_ -PreferredRawField 'qfu_sourcefamily__raw' -DisplayField 'qfu_sourcefamily')
          lastUpdated = (Get-QfuBudgetTimestamp -Row $_).ToString("s")
          actualSales = [double](Get-QfuFieldValue -Row $_ -PreferredRawField 'qfu_actualsales__raw' -DisplayField 'qfu_actualsales')
        }
      })
  }
}

$report = [pscustomobject]@{
  generatedOn = (Get-Date).ToString("s")
  mode = if ($Apply) { "apply-blocked" } else { "dry-run" }
  asOfDate = $AsOfDate.ToString("yyyy-MM-dd")
  branchCodes = $BranchCodes
  groups = @($groups)
}

if ($Apply) {
  throw "Live Dataverse repair is intentionally disabled in this reliability pass. Use the dry-run plan and explicit later approval before enabling writes."
}

$markdown = @(
  "# SA1300 Current Budget Normalization Plan"
  ""
  "- Generated: $((Get-Date).ToString("s"))"
  "- Mode: dry-run only"
  "- As of: $($AsOfDate.ToString("yyyy-MM-dd"))"
  ""
)

foreach ($group in $groups) {
  $markdown += @(
    "## $($group.branchCode) | $($group.fiscalYear) | Month $($group.monthNumber)"
    ""
    "- Candidate rows: $($group.candidateCount)"
    "- Active candidate rows: $($group.activeCandidateCount)"
    "- Runtime/repair choice: $($group.chosen.budgetId) ($($group.chosen.sourceId))"
    "- Would deactivate: $((@($group.wouldDeactivate).Count))"
    ""
    "| Budget Id | Source Id | Active | Source Family | Last Updated | Actual Sales |"
    "| --- | --- | --- | --- | --- | ---: |"
  )

  foreach ($candidate in $group.candidates) {
    $markdown += "| $($candidate.budgetId) | $($candidate.sourceId) | $($candidate.active) | $($candidate.sourceFamily) | $($candidate.lastUpdated) | $([math]::Round($candidate.actualSales, 2)) |"
  }

  $markdown += ""
}

if ($OutputJson) {
  Write-Utf8File -Path $OutputJson -Content ($report | ConvertTo-Json -Depth 8)
}

if ($OutputMarkdown) {
  Write-Utf8File -Path $OutputMarkdown -Content ($markdown -join [Environment]::NewLine)
}

$report | ConvertTo-Json -Depth 8
