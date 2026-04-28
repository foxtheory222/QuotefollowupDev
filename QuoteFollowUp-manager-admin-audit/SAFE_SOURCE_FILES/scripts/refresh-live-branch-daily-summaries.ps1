param(
  [string]$TargetEnvironmentUrl = "<URL>
  [string]$Username = "<EMAIL>",
  [string[]]$BranchCodes = @("4171", "4172", "4173"),
  [switch]$Apply,
  [string]$OutputJson = "results\\live-branch-summary-refresh.json"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

Import-Module Microsoft.Xrm.Data.Powershell

function Resolve-RepoPath {
  param([string]$Path)

  if ([System.IO.Path]::IsPathRooted($Path)) {
    return $Path
  }

  return Join-Path $RepoRoot $Path
}

function Ensure-Directory {
  param([string]$Path)

  if (-not [string]::IsNullOrWhiteSpace($Path) -and -not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Write-Utf8Json {
  param(
    [string]$Path,
    [object]$Object
  )

  $directory = Split-Path -Parent $Path
  if ($directory) {
    Ensure-Directory -Path $directory
  }

  [System.IO.File]::WriteAllText($Path, ($Object | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
}

function Connect-Target {
  param(
    [string]$Url,
    [string]$User
  )

  $conn = Connect-CrmOnline -ServerUrl $Url -ForceOAuth -Username $User
  if (-not $conn -or -not $conn.IsReady) {
    throw "Dataverse connection failed for $Url : $($conn.LastCrmError)"
  }

  return $conn
}

function Get-DateValue {
  param([object]$Value)

  if ($null -eq $Value) {
    return $null
  }

  try {
    return [datetime]$Value
  } catch {
    return $null
  }
}

function Get-BoolValue {
  param([object]$Value)

  if ($null -eq $Value) {
    return $null
  }

  if ($Value -is [bool]) {
    return [bool]$Value
  }

  $text = ([string]$Value).Trim().ToLowerInvariant()
  if ($text -in @("true", "1", "yes")) {
    return $true
  }
  if ($text -in @("false", "0", "no")) {
    return $false
  }

  return $null
}

function Get-DecimalValue {
  param([object]$Value)

  if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
    return [decimal]0
  }

  try {
    return [decimal]$Value
  } catch {
    return [decimal]0
  }
}

function Get-IntegerValue {
  param([object]$Value)

  if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
    return 0
  }

  try {
    return [int]$Value
  } catch {
    return 0
  }
}

function Days-Between {
  param(
    [datetime]$Later,
    [datetime]$Earlier
  )

  return [math]::Max(0, [int][math]::Floor(($Later.Date - $Earlier.Date).TotalDays))
}

function Test-OperationalRowIsActive {
  param([object]$Row)

  $inactiveOn = Get-DateValue $Row.qfu_inactiveon
  if ($inactiveOn) {
    return $false
  }

  $active = Get-BoolValue $Row.qfu_active
  if ($null -ne $active) {
    return $active
  }

  return $true
}

function Test-BudgetRowIsActive {
  param([object]$Row)

  $value = if ($Row.PSObject.Properties["qfu_isactive"]) { $Row.qfu_isactive } else { $null }
  if ($value -is [bool]) {
    return (-not $value)
  }

  $label = if ($null -eq $value) { "" } else { ([string]$value).Trim().ToLowerInvariant() }
  switch ($label) {
    "no" { return $true }
    "false" { return $true }
    "yes" { return $false }
    "true" { return $false }
    default { return $false }
  }
}

function Get-ActiveFiscalYear {
  param([datetime]$ReferenceDate)

  $yearNumber = if ($ReferenceDate.Month -ge 7) { $ReferenceDate.Year + 1 } else { $ReferenceDate.Year }
  return "FY{0}" -f $yearNumber.ToString().Substring(2, 2)
}

function Normalize-FiscalYear {
  param(
    [object]$Value,
    [datetime]$ReferenceDate
  )

  $text = if ([string]::IsNullOrWhiteSpace([string]$Value)) { "" } else { ([string]$Value).Trim().ToUpperInvariant() }
  if ($text -match "^FY\d{2}$") {
    return $text
  }
  if ($text -match "^\d{4}$") {
    return "FY{0}" -f $text.Substring(2, 2)
  }
  return Get-ActiveFiscalYear -ReferenceDate $ReferenceDate
}

function Get-QuoteSourceMoment {
  param([object]$Row)

  $sourceUpdatedOn = Get-DateValue $Row.qfu_sourceupdatedon
  if ($sourceUpdatedOn) {
    return $sourceUpdatedOn
  }

  $sourceDate = Get-DateValue $Row.qfu_sourcedate
  if ($sourceDate) {
    return $sourceDate
  }

  return Get-DateValue $Row.createdon
}

function Get-QuoteAgeDays {
  param(
    [object]$Row,
    [datetime]$Today
  )

  $overdueSince = Get-DateValue $Row.qfu_overduesince
  if ($overdueSince) {
    return Days-Between -Later $Today -Earlier $overdueSince
  }

  $nextFollowup = Get-DateValue $Row.qfu_nextfollowup
  if ($nextFollowup -and $nextFollowup.Date -lt $Today.Date) {
    return Days-Between -Later $Today -Earlier $nextFollowup
  }

  $sourceMoment = Get-QuoteSourceMoment -Row $Row
  if ($sourceMoment) {
    return Days-Between -Later $Today -Earlier $sourceMoment
  }

  return 0
}

function Test-BackorderReadyToShipOnly {
  param([object]$Row)

  $qtyOnDelivery = Get-DecimalValue $Row.qfu_qtyondelnotpgid
  $qtyNotOnDelivery = Get-DecimalValue $Row.qfu_qtynotondel
  return $qtyOnDelivery -gt 0 -and $qtyNotOnDelivery -le 0
}

function Test-BackorderActionable {
  param([object]$Row)

  $qtyOnDelivery = Get-DecimalValue $Row.qfu_qtyondelnotpgid
  $qtyNotOnDelivery = Get-DecimalValue $Row.qfu_qtynotondel
  return $qtyNotOnDelivery -gt 0 -or $qtyOnDelivery -gt 0
}

function Get-BackorderOverdueDays {
  param(
    [object]$Row,
    [datetime]$Today
  )

  if ($null -ne $Row.qfu_daysoverdue -and -not [string]::IsNullOrWhiteSpace([string]$Row.qfu_daysoverdue)) {
    return [math]::Max(0, (Get-IntegerValue $Row.qfu_daysoverdue))
  }

  $onTimeDate = Get-DateValue $Row.qfu_ontimedate
  if ($onTimeDate -and $onTimeDate.Date -lt $Today.Date) {
    return Days-Between -Later $Today -Earlier $onTimeDate
  }

  return 0
}

function Test-IsOverdueBackorder {
  param(
    [object]$Row,
    [datetime]$Today
  )

  return (Test-BackorderActionable -Row $Row) -and (Get-BackorderOverdueDays -Row $Row -Today $Today) -gt 0
}

function Select-CurrentBudgetRow {
  param(
    [object[]]$Rows,
    [string]$BranchCode,
    [datetime]$Today
  )

  $currentMonth = $Today.Month
  $currentFiscalYear = Get-ActiveFiscalYear -ReferenceDate $Today
  $expectedSourceId = "{0}|SA1300|{1}-{2:00}" -f $BranchCode, $Today.Year, $Today.Month

  return @(
    $Rows |
      Where-Object {
        [string]$_.qfu_branchcode -eq $BranchCode -and
        [int]$_.qfu_month -eq $currentMonth -and
        (Normalize-FiscalYear -Value $(if ($_.qfu_fiscalyear) { $_.qfu_fiscalyear } else { $_.qfu_year }) -ReferenceDate $Today) -eq $currentFiscalYear
      } |
      Sort-Object `
        @{ Expression = { if ([string]$_.qfu_sourceid -eq $expectedSourceId) { 1 } else { 0 } }; Descending = $true }, `
        @{ Expression = { if (Test-BudgetRowIsActive -Row $_) { 1 } else { 0 } }; Descending = $true }, `
        @{ Expression = { Get-DateValue $_.qfu_lastupdated }; Descending = $true }, `
        @{ Expression = { Get-DateValue $_.modifiedon }; Descending = $true }, `
        @{ Expression = { Get-DateValue $_.createdon }; Descending = $true }
  ) | Select-Object -First 1
}

function Select-CurrentBudgetArchiveRow {
  param(
    [object[]]$Rows,
    [string]$BranchCode,
    [datetime]$Today
  )

  $currentMonth = $Today.Month
  $currentFiscalYear = Get-ActiveFiscalYear -ReferenceDate $Today

  return @(
    $Rows |
      Where-Object {
        [string]$_.qfu_branchcode -eq $BranchCode -and
        [int]$_.qfu_month -eq $currentMonth -and
        (Normalize-FiscalYear -Value $(if ($_.qfu_fiscalyear) { $_.qfu_fiscalyear } else { $_.qfu_year }) -ReferenceDate $Today) -eq $currentFiscalYear
      } |
      Sort-Object `
        @{ Expression = { Get-DateValue $_.modifiedon }; Descending = $true }, `
        @{ Expression = { Get-DateValue $_.createdon }; Descending = $true }
  ) | Select-Object -First 1
}

function Upsert-BranchSummary {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [hashtable]$Fields
  )

  $existing = @(
    (Get-CrmRecords -conn $Connection -EntityLogicalName "qfu_branchdailysummary" -FilterAttribute "qfu_sourceid" -FilterOperator eq -FilterValue $Fields.qfu_sourceid -Fields @("qfu_branchdailysummaryid") -TopCount 1).CrmRecords
  ) | Select-Object -First 1

  if ($existing) {
    Set-CrmRecord -conn $Connection -EntityLogicalName "qfu_branchdailysummary" -Id $existing.qfu_branchdailysummaryid -Fields $Fields | Out-Null
    return [pscustomobject]@{
      status = "updated"
      record_id = [string]$existing.qfu_branchdailysummaryid
    }
  }

  $createdId = New-CrmRecord -conn $Connection -EntityLogicalName "qfu_branchdailysummary" -Fields $Fields
  return [pscustomobject]@{
    status = "created"
    record_id = [string]$createdId
  }
}

$connection = Connect-Target -Url $TargetEnvironmentUrl -User $Username
$today = (Get-Date).Date
$todayIso = $today.ToString("yyyy-MM-dd")
$currentFiscalYear = Get-ActiveFiscalYear -ReferenceDate $today

$branchRows = @(
  (Get-CrmRecords -conn $connection -EntityLogicalName "qfu_branch" -Fields @("qfu_branchid", "qfu_branchcode", "qfu_branchslug", "qfu_regionslug", "qfu_branchname") -TopCount 5000).CrmRecords |
    Where-Object { [string]$_.qfu_branchcode -in $BranchCodes }
)
$branchMap = @{}
foreach ($row in $branchRows) {
  $branchMap[[string]$row.qfu_branchcode] = $row
}

$quoteRows = @(
  (Get-CrmRecords -conn $connection -EntityLogicalName "qfu_quote" -Fields @(
      "qfu_quoteid",
      "qfu_branchcode",
      "qfu_sourceid",
      "qfu_status",
      "qfu_amount",
      "qfu_sourcedate",
      "qfu_sourceupdatedon",
      "qfu_nextfollowup",
      "qfu_overduesince",
      "qfu_active",
      "qfu_inactiveon",
      "createdon"
    ) -TopCount 5000).CrmRecords
)

$backorderRows = @(
  (Get-CrmRecords -conn $connection -EntityLogicalName "qfu_backorder" -Fields @(
      "qfu_backorderid",
      "qfu_branchcode",
      "qfu_sourceid",
      "qfu_daysoverdue",
      "qfu_ontimedate",
      "qfu_totalvalue",
      "qfu_qtynotondel",
      "qfu_qtyondelnotpgid",
      "qfu_active",
      "qfu_inactiveon",
      "createdon"
    ) -TopCount 5000).CrmRecords
)

$budgetRows = @(
  (Get-CrmRecords -conn $connection -EntityLogicalName "qfu_budget" -Fields @(
      "qfu_budgetid",
      "qfu_branchcode",
      "qfu_sourceid",
      "qfu_month",
      "qfu_monthname",
      "qfu_year",
      "qfu_fiscalyear",
      "qfu_actualsales",
      "qfu_budgetgoal",
      "qfu_cadsales",
      "qfu_usdsales",
      "qfu_lastupdated",
      "qfu_isactive",
      "createdon",
      "modifiedon"
    ) -TopCount 5000).CrmRecords
)

$budgetArchiveRows = @(
  (Get-CrmRecords -conn $connection -EntityLogicalName "qfu_budgetarchive" -Fields @(
      "qfu_budgetarchiveid",
      "qfu_branchcode",
      "qfu_sourceid",
      "qfu_month",
      "qfu_monthname",
      "qfu_year",
      "qfu_fiscalyear",
      "qfu_budgetgoal",
      "createdon",
      "modifiedon"
    ) -TopCount 5000).CrmRecords
)

$branchResults = New-Object System.Collections.Generic.List[object]

foreach ($branchCode in $BranchCodes) {
  $branch = $branchMap[$branchCode]
  if (-not $branch) {
    $branchResults.Add([pscustomobject]@{
      branch_code = $branchCode
      status = "missing-branch-config"
    }) | Out-Null
    continue
  }

  $activeQuotes = @($quoteRows | Where-Object { [string]$_.qfu_branchcode -eq $branchCode -and (Test-OperationalRowIsActive -Row $_) })
  $activeBackorders = @($backorderRows | Where-Object { [string]$_.qfu_branchcode -eq $branchCode -and (Test-OperationalRowIsActive -Row $_) })
  $actionableBackorders = @($activeBackorders | Where-Object { Test-BackorderActionable -Row $_ })
  $openQuotes = @($activeQuotes | Where-Object { (Get-IntegerValue $_.qfu_status) -eq 1 })
  $overdueQuotes = @($openQuotes | Where-Object { (Get-QuoteAgeDays -Row $_ -Today $today) -gt 0 })
  $quotesLast30 = @($activeQuotes | Where-Object {
      $sourceMoment = Get-QuoteSourceMoment -Row $_
      $sourceMoment -and $sourceMoment.Date -ge $today.AddDays(-30)
    })
  $wonQuotes = @($quotesLast30 | Where-Object { (Get-IntegerValue $_.qfu_status) -eq 2 })
  $lostQuotes = @($quotesLast30 | Where-Object {
      $status = Get-IntegerValue $_.qfu_status
      $status -eq 3 -or $status -eq 4
    })
  $overdueBackorders = @($actionableBackorders | Where-Object { Test-IsOverdueBackorder -Row $_ -Today $today })
  $currentMonthBackorders = @($actionableBackorders | Where-Object {
      $onTimeDate = Get-DateValue $_.qfu_ontimedate
      $onTimeDate -and $onTimeDate.Month -eq $today.Month -and $onTimeDate.Year -eq $today.Year
    })
  $currentMonthLateBackorders = @($currentMonthBackorders | Where-Object { (Get-BackorderOverdueDays -Row $_ -Today $today) -gt 0 })
  $budget = Select-CurrentBudgetRow -Rows $budgetRows -BranchCode $branchCode -Today $today
  $budgetArchive = Select-CurrentBudgetArchiveRow -Rows $budgetArchiveRows -BranchCode $branchCode -Today $today

  $actualSales = if ($budget -and $null -ne $budget.qfu_actualsales -and -not [string]::IsNullOrWhiteSpace([string]$budget.qfu_actualsales)) { [decimal]$budget.qfu_actualsales } else { [decimal]0 }
  $targetSales = if ($budgetArchive) { [decimal]$budgetArchive.qfu_budgetgoal } elseif ($budget -and $null -ne $budget.qfu_budgetgoal -and -not [string]::IsNullOrWhiteSpace([string]$budget.qfu_budgetgoal)) { [decimal]$budget.qfu_budgetgoal } else { [decimal]0 }
  $budgetPace = if ($targetSales -gt 0) { [math]::Round(($actualSales / $targetSales) * 100, 2) } else { [decimal]0 }
  $quoteValueLast30 = @($quotesLast30 | Measure-Object -Property qfu_amount -Sum).Sum
  $averageQuoteValue = if (@($quotesLast30).Count -gt 0) { [math]::Round(([decimal]$quoteValueLast30 / [decimal]@($quotesLast30).Count), 2) } else { [decimal]0 }

  $fields = [ordered]@{
    qfu_name = "$branchCode Daily Summary $todayIso"
    qfu_sourceid = "$branchCode|summary|$todayIso"
    qfu_branchcode = [string]$branchCode
    qfu_branchslug = [string]$branch.qfu_branchslug
    qfu_regionslug = [string]$branch.qfu_regionslug
    qfu_summarydate = $today
    qfu_openquotes = @($openQuotes).Count
    qfu_overduequotes = @($overdueQuotes).Count
    qfu_duetoday = 0
    qfu_unscheduledold = @($overdueQuotes).Count
    qfu_openquotevalue = [math]::Round([decimal](@($openQuotes | Measure-Object -Property qfu_amount -Sum).Sum), 2)
    qfu_quoteslast30days = @($quotesLast30).Count
    qfu_quoteswon30days = @($wonQuotes).Count
    qfu_quoteslost30days = @($lostQuotes).Count
    qfu_quotesopen30days = [math]::Max(0, @($quotesLast30).Count - @($wonQuotes).Count - @($lostQuotes).Count)
    qfu_avgquotevalue30days = $averageQuoteValue
    qfu_backordercount = @($actionableBackorders).Count
    qfu_overduebackordercount = @($overdueBackorders).Count
    qfu_currentmonthforecastvalue = [math]::Round([decimal](@($currentMonthBackorders | Measure-Object -Property qfu_totalvalue -Sum).Sum), 2)
    qfu_currentmonthlatevalue = [math]::Round([decimal](@($currentMonthLateBackorders | Measure-Object -Property qfu_totalvalue -Sum).Sum), 2)
    qfu_allbackordersvalue = [math]::Round([decimal](@($actionableBackorders | Measure-Object -Property qfu_totalvalue -Sum).Sum), 2)
    qfu_overduebackordersvalue = [math]::Round([decimal](@($overdueBackorders | Measure-Object -Property qfu_totalvalue -Sum).Sum), 2)
    qfu_budgetactual = [math]::Round($actualSales, 2)
    qfu_budgettarget = [math]::Round($targetSales, 2)
    qfu_budgetpace = $budgetPace
    qfu_cadsales = if ($budget) { [math]::Round((Get-DecimalValue $budget.qfu_cadsales), 2) } else { [decimal]0 }
    qfu_usdsales = if ($budget) { [math]::Round((Get-DecimalValue $budget.qfu_usdsales), 2) } else { [decimal]0 }
    qfu_lastcalculatedon = (Get-Date)
  }

  $writeResult = [pscustomobject]@{
    status = "planned"
    record_id = $null
  }
  if ($Apply) {
    $writeResult = Upsert-BranchSummary -Connection $connection -Fields $fields
  }

  $branchResults.Add([pscustomobject]@{
    branch_code = $branchCode
    branch_slug = [string]$branch.qfu_branchslug
    region_slug = [string]$branch.qfu_regionslug
    source_id = [string]$fields.qfu_sourceid
    status = $writeResult.status
    record_id = $writeResult.record_id
    open_quotes = [int]$fields.qfu_openquotes
    overdue_quotes = [int]$fields.qfu_overduequotes
    backorder_count = [int]$fields.qfu_backordercount
    overdue_backorder_count = [int]$fields.qfu_overduebackordercount
    budget_actual = [decimal]$fields.qfu_budgetactual
    budget_target = [decimal]$fields.qfu_budgettarget
    budget_pace = [decimal]$fields.qfu_budgetpace
    budget_actual_source = if ($budget -and $null -ne $budget.qfu_actualsales -and -not [string]::IsNullOrWhiteSpace([string]$budget.qfu_actualsales)) { "qfu_budget" } else { "missing" }
    budget_target_source = if ($budgetArchive) { "qfu_budgetarchive" } elseif ($budget -and $null -ne $budget.qfu_budgetgoal -and -not [string]::IsNullOrWhiteSpace([string]$budget.qfu_budgetgoal)) { "qfu_budget" } else { "missing" }
  }) | Out-Null
}

$report = [pscustomobject]@{
  generated_on = (Get-Date).ToUniversalTime().ToString("o")
  target_environment_url = $TargetEnvironmentUrl
  branch_codes = @($BranchCodes)
  apply = [bool]$Apply
  current_fiscal_year = $currentFiscalYear
  branches = @($branchResults.ToArray())
}

$outputPath = Resolve-RepoPath -Path $OutputJson
Write-Utf8Json -Path $outputPath -Object $report

Write-Host "OUTPUT_PATH=$outputPath"
Write-Host "APPLY=$([bool]$Apply)"
