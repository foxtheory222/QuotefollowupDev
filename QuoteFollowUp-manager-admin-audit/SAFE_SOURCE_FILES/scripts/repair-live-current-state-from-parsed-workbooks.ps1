param(
  [string]$TargetEnvironmentUrl = "<URL>
  [string]$Username = "<EMAIL>",
  [string]$ParsedWorkbookJson = "results\\apr9-replay\\parsed-apr9.json",
  [string[]]$BranchCodes = @("4171", "4172", "4173"),
  [string]$ReplayLabel = "Captured workbook replay",
  [string]$OutputJson = "results\\live-current-state-from-parsed-workbooks.json",
  [switch]$SkipBackorders,
  [switch]$SkipOpsDaily,
  [switch]$SkipBudget,
  [switch]$SkipSummary,
  [switch]$SkipBatches
)

$ErrorActionPreference = "Stop"

Import-Module Microsoft.Xrm.Data.Powershell

function Resolve-RepoPath {
  param([string]$Path)

  if ([System.IO.Path]::IsPathRooted($Path)) {
    return $Path
  }

  return Join-Path (Get-Location) $Path
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

  if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
    return $null
  }

  try {
    return [datetime]$Value
  } catch {
    return $null
  }
}

function Get-NullableDecimal {
  param([object]$Value)

  if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
    return $null
  }

  return [decimal]$Value
}

function Get-NullableInt {
  param([object]$Value)

  if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
    return $null
  }

  return [int]$Value
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
  switch ($text) {
    "true" { return $true }
    "false" { return $false }
    "yes" { return $true }
    "no" { return $false }
    "1" { return $true }
    "0" { return $false }
    default { return $null }
  }
}

function Test-BudgetRowIsActive {
  param([object]$Row)

  $value = if ($Row.PSObject.Properties["qfu_isactive"]) { $Row.qfu_isactive } else { $null }
  $boolValue = Get-BoolValue -Value $value
  if ($null -ne $boolValue) {
    return (-not $boolValue)
  }

  return $false
}

function Get-FiscalYearLabel {
  param(
    [int]$MonthNumber,
    [int]$YearNumber
  )

  $fiscalYear = if ($MonthNumber -ge 7) { $YearNumber + 1 } else { $YearNumber }
  return "FY{0}" -f $fiscalYear.ToString().Substring(2, 2)
}

function Get-DateTicks {
  param([object]$Value)

  $dateValue = Get-DateValue $Value
  if ($dateValue) {
    return $dateValue.Ticks
  }

  return 0
}

function Get-EffectiveRowActiveRank {
  param(
    [object]$Row,
    [string]$ActiveField,
    [bool]$BudgetPolarity = $false
  )

  if (-not $ActiveField) {
    return 0
  }

  if ($BudgetPolarity) {
    if (Test-BudgetRowIsActive -Row $Row) {
      return 1
    }
    return 0
  }

  $isActive = (Get-BoolValue -Value $Row.$ActiveField) -eq $true
  if ($isActive -and -not (Get-DateValue $Row.qfu_inactiveon)) {
    return 1
  }

  return 0
}

function Select-PreferredLiveRow {
  param(
    [object[]]$Rows,
    [string]$IdField,
    [string]$ActiveField = "",
    [string]$SnapshotField = "",
    [bool]$BudgetPolarity = $false
  )

  return @(
    $Rows |
      Sort-Object `
        @{ Expression = { Get-EffectiveRowActiveRank -Row $_ -ActiveField $ActiveField -BudgetPolarity $BudgetPolarity }; Descending = $true },
        @{ Expression = { if ([string]::IsNullOrWhiteSpace($SnapshotField)) { 0 } else { Get-DateTicks -Value $_.$SnapshotField } }; Descending = $true },
        @{ Expression = { Get-DateTicks -Value $_.modifiedon }; Descending = $true },
        @{ Expression = { Get-DateTicks -Value $_.createdon }; Descending = $true },
        @{ Expression = { [string]($_.$IdField) }; Descending = $false }
  ) | Select-Object -First 1
}

function Get-RetiredBudgetSourceId {
  param(
    [string]$CurrentSourceId,
    [string]$BudgetId
  )

  $suffix = if ([string]::IsNullOrWhiteSpace($BudgetId)) { [guid]::NewGuid().Guid.Substring(0, 8) } else { $BudgetId.Substring(0, 8) }
  return "{0}|retired|{1}" -f $CurrentSourceId, $suffix
}

function Get-ListValues {
  param(
    [hashtable]$Map,
    [string]$Key
  )

  if ($Map.ContainsKey($Key) -and $null -ne $Map[$Key]) {
    return @($Map[$Key].ToArray())
  }

  return @()
}

function Build-BackorderFields {
  param(
    [object]$Record,
    [datetime]$CapturedOn
  )

  $qtyOnDelivery = Get-NullableDecimal $Record.qfu_qtyondelnotpgid
  if ($null -ne $qtyOnDelivery -and $qtyOnDelivery -lt 0) {
    $qtyOnDelivery = [decimal]0
  }

  $qtyNotOnDelivery = Get-NullableDecimal $Record.qfu_qtynotondel
  if ($null -ne $qtyNotOnDelivery -and $qtyNotOnDelivery -lt 0) {
    $qtyNotOnDelivery = [decimal]0
  }

  return @{
    qfu_name = [string]$Record.qfu_name
    qfu_sourceid = [string]$Record.qfu_sourceid
    qfu_customername = [string]$Record.qfu_customername
    qfu_totalvalue = Get-NullableDecimal $Record.qfu_totalvalue
    qfu_ontimedate = Get-DateValue $Record.qfu_ontimedate
    qfu_cssrname = [string]$Record.qfu_cssrname
    qfu_daysoverdue = Get-NullableInt $Record.qfu_daysoverdue
    qfu_salesdocnumber = [string]$Record.qfu_salesdocnumber
    qfu_material = [string]$Record.qfu_material
    qfu_description = [string]$Record.qfu_description
    qfu_quantity = Get-NullableDecimal $Record.qfu_quantity
    qfu_qtybilled = Get-NullableDecimal $Record.qfu_qtybilled
    qfu_qtyondelnotpgid = $qtyOnDelivery
    qfu_qtynotondel = $qtyNotOnDelivery
    qfu_branchcode = [string]$Record.qfu_branchcode
    qfu_branchslug = [string]$Record.qfu_branchslug
    qfu_regionslug = [string]$Record.qfu_regionslug
    qfu_sourcefamily = [string]$Record.qfu_sourcefamily
    qfu_sourcefile = [string]$Record.qfu_sourcefile
    qfu_sourceline = [string]$Record.qfu_sourceline
    qfu_active = $true
    qfu_inactiveon = $null
    qfu_lastseenon = $CapturedOn
  }
}

function Test-BackorderRecordIsActionable {
  param([object]$Row)

  $qtyOnDelivery = Get-NullableDecimal $Row.qfu_qtyondelnotpgid
  $qtyNotOnDelivery = Get-NullableDecimal $Row.qfu_qtynotondel
  return $qtyNotOnDelivery -gt 0 -or $qtyOnDelivery -gt 0
}

function Build-BudgetFields {
  param([object]$Record)

  $monthNumber = Get-NullableInt $Record.qfu_month
  $yearNumber = Get-NullableInt $Record.qfu_year
  $goal = Get-NullableDecimal $Record.qfu_budgetgoal
  $actual = Get-NullableDecimal $Record.qfu_actualsales
  $pace = if ($goal -and $goal -gt 0 -and $null -ne $actual) { [math]::Round(([decimal]$actual / [decimal]$goal) * 100, 2) } else { [decimal]0 }

  $fields = @{
    qfu_name = [string]$Record.qfu_name
    qfu_sourceid = [string]$Record.qfu_sourceid
    qfu_budgetname = [string]$Record.qfu_budgetname
    qfu_actualsales = $actual
    qfu_budgetamount = $goal
    qfu_budgetgoal = $goal
    qfu_percentachieved = $pace
    qfu_lastupdated = Get-DateValue $Record.qfu_lastupdated
    qfu_cadsales = Get-NullableDecimal $Record.qfu_cadsales
    qfu_usdsales = Get-NullableDecimal $Record.qfu_usdsales
    qfu_month = $monthNumber
    qfu_monthname = [string]$Record.qfu_monthname
    qfu_year = $yearNumber
    qfu_fiscalyear = Get-FiscalYearLabel -MonthNumber $monthNumber -YearNumber $yearNumber
    qfu_sourcefile = [string]$Record.qfu_sourcefile
    qfu_branchcode = [string]$Record.qfu_branchcode
    qfu_branchslug = [string]$Record.qfu_branchslug
    qfu_regionslug = [string]$Record.qfu_regionslug
    qfu_sourcefamily = [string]$Record.qfu_sourcefamily
    qfu_isactive = $false
  }

  if ($Record.PSObject.Properties["qfu_opsdailycadjson"]) {
    $fields.qfu_opsdailycadjson = [string]$Record.qfu_opsdailycadjson
  }

  if ($Record.PSObject.Properties["qfu_opsdailyusdjson"]) {
    $fields.qfu_opsdailyusdjson = [string]$Record.qfu_opsdailyusdjson
  }

  return $fields
}

function Build-BranchOpsDailyFields {
  param([object]$Record)

  return @{
    qfu_name = [string]$Record.qfu_name
    qfu_sourceid = [string]$Record.qfu_sourceid
    qfu_branchcode = [string]$Record.qfu_branchcode
    qfu_branchslug = [string]$Record.qfu_branchslug
    qfu_regionslug = [string]$Record.qfu_regionslug
    qfu_sourcefamily = [string]$Record.qfu_sourcefamily
    qfu_sourcefile = [string]$Record.qfu_sourcefile
    qfu_sourceworksheet = [string]$Record.qfu_sourceworksheet
    qfu_snapshotdate = Get-DateValue $Record.qfu_snapshotdate
    qfu_billingday = Get-DateValue $Record.qfu_billingday
    qfu_billinglabel = [string]$Record.qfu_billinglabel
    qfu_istotalrow = Get-BoolValue $Record.qfu_istotalrow
    qfu_currencytype = [string]$Record.qfu_currencytype
    qfu_sales = Get-NullableDecimal $Record.qfu_sales
    qfu_gp = Get-NullableDecimal $Record.qfu_gp
    qfu_gppct = Get-NullableDecimal $Record.qfu_gppct
    qfu_ontimedelivery = Get-NullableDecimal $Record.qfu_ontimedelivery
    qfu_sortorder = Get-NullableInt $Record.qfu_sortorder
  }
}

function Build-SummaryFields {
  param([object]$Record)

  return @{
    qfu_name = [string]$Record.qfu_name
    qfu_sourceid = [string]$Record.qfu_sourceid
    qfu_branchcode = [string]$Record.qfu_branchcode
    qfu_branchslug = [string]$Record.qfu_branchslug
    qfu_regionslug = [string]$Record.qfu_regionslug
    qfu_summarydate = Get-DateValue $Record.qfu_summarydate
    qfu_openquotes = Get-NullableInt $Record.qfu_openquotes
    qfu_overduequotes = Get-NullableInt $Record.qfu_overduequotes
    qfu_duetoday = Get-NullableInt $Record.qfu_duetoday
    qfu_unscheduledold = Get-NullableInt $Record.qfu_unscheduledold
    qfu_openquotevalue = Get-NullableDecimal $Record.qfu_openquotevalue
    qfu_quoteslast30days = Get-NullableInt $Record.qfu_quoteslast30days
    qfu_quoteswon30days = Get-NullableInt $Record.qfu_quoteswon30days
    qfu_quoteslost30days = Get-NullableInt $Record.qfu_quoteslost30days
    qfu_quotesopen30days = Get-NullableInt $Record.qfu_quotesopen30days
    qfu_avgquotevalue30days = Get-NullableDecimal $Record.qfu_avgquotevalue30days
    qfu_backordercount = Get-NullableInt $Record.qfu_backordercount
    qfu_overduebackordercount = Get-NullableInt $Record.qfu_overduebackordercount
    qfu_currentmonthforecastvalue = Get-NullableDecimal $Record.qfu_currentmonthforecastvalue
    qfu_currentmonthlatevalue = Get-NullableDecimal $Record.qfu_currentmonthlatevalue
    qfu_allbackordersvalue = Get-NullableDecimal $Record.qfu_allbackordersvalue
    qfu_overduebackordersvalue = Get-NullableDecimal $Record.qfu_overduebackordersvalue
    qfu_budgetactual = Get-NullableDecimal $Record.qfu_budgetactual
    qfu_budgettarget = Get-NullableDecimal $Record.qfu_budgettarget
    qfu_budgetpace = Get-NullableDecimal $Record.qfu_budgetpace
    qfu_cadsales = Get-NullableDecimal $Record.qfu_cadsales
    qfu_usdsales = Get-NullableDecimal $Record.qfu_usdsales
    qfu_lastcalculatedon = Get-DateValue $Record.qfu_lastcalculatedon
  }
}

function Build-BatchFields {
  param(
    [object]$Record,
    [string]$Label
  )

  return @{
    qfu_name = [string]$Record.qfu_name
    qfu_sourceid = [string]$Record.qfu_sourceid
    qfu_branchcode = [string]$Record.qfu_branchcode
    qfu_branchslug = [string]$Record.qfu_branchslug
    qfu_regionslug = [string]$Record.qfu_regionslug
    qfu_sourcefamily = [string]$Record.qfu_sourcefamily
    qfu_sourcefilename = [string]$Record.qfu_sourcefilename
    qfu_status = [string]$Record.qfu_status
    qfu_insertedcount = Get-NullableInt $Record.qfu_insertedcount
    qfu_updatedcount = Get-NullableInt $Record.qfu_updatedcount
    qfu_startedon = Get-DateValue $Record.qfu_startedon
    qfu_completedon = Get-DateValue $Record.qfu_completedon
    qfu_triggerflow = $Label
    qfu_notes = "Replayed from captured workbook evidence for $([string]$Record.qfu_branchcode) using $([string]$Record.qfu_sourcefilename)."
  }
}

function Sync-Backorders {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [object]$BranchPayload
  )

  $branchCode = [string]$BranchPayload.branch.branch_code
  $capturedOn = Get-DateValue $BranchPayload.backorders.captured_on
  if (-not $capturedOn) {
    $capturedOn = Get-Date
  }

  $liveRows = @(
    (Get-CrmRecords -conn $Connection -EntityLogicalName "qfu_backorder" -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $branchCode -Fields @(
        "qfu_backorderid",
        "qfu_sourceid",
        "qfu_active",
        "qfu_inactiveon",
        "qfu_lastseenon",
        "createdon",
        "modifiedon"
      ) -TopCount 5000
    ).CrmRecords |
      Where-Object { $_.qfu_sourceid }
  )

  $liveBySource = @{}
  foreach ($row in $liveRows) {
    $sourceId = [string]$row.qfu_sourceid
    if (-not $liveBySource.ContainsKey($sourceId)) {
      $liveBySource[$sourceId] = New-Object System.Collections.Generic.List[object]
    }
    $liveBySource[$sourceId].Add($row) | Out-Null
  }

  $parsedSourceIds = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)
  $updated = 0
  $created = 0
  $deactivated = 0
  $deduped = 0
  $parsedBackorders = @($BranchPayload.backorders.records | Where-Object { Test-BackorderRecordIsActionable -Row $_ })
  $skippedNonActionable = @($BranchPayload.backorders.records).Count - @($parsedBackorders).Count

  foreach ($record in $parsedBackorders) {
    $sourceId = [string]$record.qfu_sourceid
    [void]$parsedSourceIds.Add($sourceId)
    $fields = Build-BackorderFields -Record $record -CapturedOn $capturedOn
    $existing = Get-ListValues -Map $liveBySource -Key $sourceId
    $winner = Select-PreferredLiveRow -Rows $existing -IdField "qfu_backorderid" -ActiveField "qfu_active" -SnapshotField "qfu_lastseenon"

    if ($winner) {
      Set-CrmRecord -conn $Connection -EntityLogicalName "qfu_backorder" -Id $winner.qfu_backorderid -Fields $fields | Out-Null
      $updated += 1

      foreach ($duplicate in @($existing | Where-Object { [string]$_.qfu_backorderid -ne [string]$winner.qfu_backorderid })) {
        Set-CrmRecord -conn $Connection -EntityLogicalName "qfu_backorder" -Id $duplicate.qfu_backorderid -Fields @{
          qfu_active = $false
          qfu_inactiveon = $capturedOn
          qfu_lastseenon = $capturedOn
        } | Out-Null
        $deduped += 1
      }
    } else {
      New-CrmRecord -conn $Connection -EntityLogicalName "qfu_backorder" -Fields $fields | Out-Null
      $created += 1
    }
  }

  foreach ($row in $liveRows) {
    $sourceId = [string]$row.qfu_sourceid
    if ($parsedSourceIds.Contains($sourceId)) {
      continue
    }

    $isEffectivelyActive = ((Get-BoolValue -Value $row.qfu_active) -eq $true) -or ($null -eq (Get-BoolValue -Value $row.qfu_active) -and -not (Get-DateValue $row.qfu_inactiveon))
    if (-not $isEffectivelyActive) {
      continue
    }

    Set-CrmRecord -conn $Connection -EntityLogicalName "qfu_backorder" -Id $row.qfu_backorderid -Fields @{
      qfu_active = $false
      qfu_inactiveon = $capturedOn
      qfu_lastseenon = $capturedOn
    } | Out-Null
    $deactivated += 1
  }

  return [pscustomobject]@{
    branch_code = $branchCode
    captured_on = $capturedOn.ToString("o")
    raw_parsed_count = @($BranchPayload.backorders.records).Count
    parsed_count = @($parsedBackorders).Count
    updated = $updated
    created = $created
    deactivated = $deactivated
    deduped = $deduped
    skipped_non_actionable = $skippedNonActionable
  }
}

function Sync-OpsDaily {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [object]$BranchPayload
  )

  $opsDailyPayload = if ($BranchPayload.PSObject.Properties["ops_daily"]) { $BranchPayload.ops_daily } else { $null }
  if (-not $opsDailyPayload) {
    return $null
  }

  $branchCode = [string]$BranchPayload.branch.branch_code
  $liveRows = @(
    (Get-CrmRecords -conn $Connection -EntityLogicalName "qfu_branchopsdaily" -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $branchCode -Fields @(
        "qfu_branchopsdailyid",
        "qfu_sourceid",
        "qfu_snapshotdate",
        "qfu_billingday",
        "createdon",
        "modifiedon"
      ) -TopCount 1000
    ).CrmRecords |
      Where-Object { $_.qfu_sourceid }
  )

  $liveBySource = @{}
  foreach ($row in $liveRows) {
    $sourceId = [string]$row.qfu_sourceid
    if (-not $liveBySource.ContainsKey($sourceId)) {
      $liveBySource[$sourceId] = New-Object System.Collections.Generic.List[object]
    }
    $liveBySource[$sourceId].Add($row) | Out-Null
  }

  $parsedSourceIds = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)
  $updated = 0
  $created = 0
  $removed = 0

  foreach ($record in @($opsDailyPayload.records)) {
    $sourceId = [string]$record.qfu_sourceid
    [void]$parsedSourceIds.Add($sourceId)
    $fields = Build-BranchOpsDailyFields -Record $record
    $existing = Get-ListValues -Map $liveBySource -Key $sourceId
    $winner = Select-PreferredLiveRow -Rows $existing -IdField "qfu_branchopsdailyid" -SnapshotField "qfu_snapshotdate"

    if ($winner) {
      Set-CrmRecord -conn $Connection -EntityLogicalName "qfu_branchopsdaily" -Id $winner.qfu_branchopsdailyid -Fields $fields | Out-Null
      $updated += 1

      foreach ($duplicate in @($existing | Where-Object { [string]$_.qfu_branchopsdailyid -ne [string]$winner.qfu_branchopsdailyid })) {
        Remove-CrmRecord -conn $Connection -EntityLogicalName "qfu_branchopsdaily" -Id $duplicate.qfu_branchopsdailyid | Out-Null
        $removed += 1
      }
    } else {
      New-CrmRecord -conn $Connection -EntityLogicalName "qfu_branchopsdaily" -Fields $fields | Out-Null
      $created += 1
    }
  }

  foreach ($row in $liveRows) {
    $sourceId = [string]$row.qfu_sourceid
    if ($parsedSourceIds.Contains($sourceId)) {
      continue
    }

    Remove-CrmRecord -conn $Connection -EntityLogicalName "qfu_branchopsdaily" -Id $row.qfu_branchopsdailyid | Out-Null
    $removed += 1
  }

  return [pscustomobject]@{
    branch_code = $branchCode
    parsed_count = @($opsDailyPayload.records).Count
    updated = $updated
    created = $created
    removed = $removed
    latest_billing_day = [string]$opsDailyPayload.latest_billing_day
  }
}

function Sync-Budget {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [object]$BranchPayload
  )

  $budgetRecord = @($BranchPayload.budgets.records) | Select-Object -First 1
  if (-not $budgetRecord) {
    return $null
  }

  $branchCode = [string]$BranchPayload.branch.branch_code
  $sourceId = [string]$budgetRecord.qfu_sourceid
  $budgetRows = @(
    (Get-CrmRecords -conn $Connection -EntityLogicalName "qfu_budget" -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $branchCode -Fields @(
        "qfu_budgetid",
        "qfu_sourceid",
        "qfu_isactive",
        "createdon",
        "modifiedon",
        "qfu_lastupdated"
      ) -TopCount 50
    ).CrmRecords |
      Where-Object { [string]$_.qfu_sourceid -like "$branchCode|SA1300|*" }
  )

  $currentRows = @($budgetRows | Where-Object { [string]$_.qfu_sourceid -eq $sourceId })
  $winner = Select-PreferredLiveRow -Rows $currentRows -IdField "qfu_budgetid" -SnapshotField "qfu_lastupdated"

  $fields = Build-BudgetFields -Record $budgetRecord
  $updated = 0
  $created = 0
  $retired = 0

  if ($winner) {
    Set-CrmRecord -conn $Connection -EntityLogicalName "qfu_budget" -Id $winner.qfu_budgetid -Fields $fields | Out-Null
    $updated += 1

    foreach ($duplicate in @($currentRows | Where-Object { [string]$_.qfu_budgetid -ne [string]$winner.qfu_budgetid })) {
      Set-CrmRecord -conn $Connection -EntityLogicalName "qfu_budget" -Id $duplicate.qfu_budgetid -Fields @{
        qfu_isactive = $true
        qfu_lastupdated = Get-DateValue $budgetRecord.qfu_lastupdated
        qfu_sourceid = Get-RetiredBudgetSourceId -CurrentSourceId $sourceId -BudgetId ([string]$duplicate.qfu_budgetid)
      } | Out-Null
      $retired += 1
    }
  } else {
    $recordId = New-CrmRecord -conn $Connection -EntityLogicalName "qfu_budget" -Fields $fields
    $winner = [pscustomobject]@{ qfu_budgetid = [string]$recordId }
    $created += 1
  }

  return [pscustomobject]@{
    branch_code = $branchCode
    source_id = $sourceId
    updated = $updated
    created = $created
    retired = $retired
    actual_sales = Get-NullableDecimal $budgetRecord.qfu_actualsales
    budget_goal = Get-NullableDecimal $budgetRecord.qfu_budgetgoal
  }
}

function Sync-Summary {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [object]$BranchPayload
  )

  $summaryRecord = $BranchPayload.summary
  if (-not $summaryRecord) {
    return $null
  }

  $sourceId = [string]$summaryRecord.qfu_sourceid
  $existing = @(
    (Get-CrmRecords -conn $Connection -EntityLogicalName "qfu_branchdailysummary" -FilterAttribute "qfu_sourceid" -FilterOperator eq -FilterValue $sourceId -Fields @(
        "qfu_branchdailysummaryid",
        "createdon",
        "modifiedon"
      ) -TopCount 20
    ).CrmRecords
  )

  $winner = @(
    $existing |
      Sort-Object modifiedon, createdon -Descending
  ) | Select-Object -First 1

  $fields = Build-SummaryFields -Record $summaryRecord
  $updated = 0
  $created = 0

  if ($winner) {
    Set-CrmRecord -conn $Connection -EntityLogicalName "qfu_branchdailysummary" -Id $winner.qfu_branchdailysummaryid -Fields $fields | Out-Null
    $updated += 1
  } else {
    New-CrmRecord -conn $Connection -EntityLogicalName "qfu_branchdailysummary" -Fields $fields | Out-Null
    $created += 1
  }

  return [pscustomobject]@{
    branch_code = [string]$BranchPayload.branch.branch_code
    source_id = $sourceId
    updated = $updated
    created = $created
    backorder_count = Get-NullableInt $summaryRecord.qfu_backordercount
    overdue_backorder_count = Get-NullableInt $summaryRecord.qfu_overduebackordercount
    budget_actual = Get-NullableDecimal $summaryRecord.qfu_budgetactual
  }
}

function Sync-Batches {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [object]$BranchPayload,
    [string]$Label
  )

  $updated = 0
  $created = 0
  $rows = @()

  foreach ($batchRecord in @($BranchPayload.batches)) {
    $sourceId = [string]$batchRecord.qfu_sourceid
    $existing = @(
      (Get-CrmRecords -conn $Connection -EntityLogicalName "qfu_ingestionbatch" -FilterAttribute "qfu_sourceid" -FilterOperator eq -FilterValue $sourceId -Fields @(
          "qfu_ingestionbatchid",
          "createdon",
          "modifiedon"
        ) -TopCount 20
      ).CrmRecords
    ) | Sort-Object modifiedon, createdon -Descending | Select-Object -First 1

    $fields = Build-BatchFields -Record $batchRecord -Label $Label
    if ($existing) {
      Set-CrmRecord -conn $Connection -EntityLogicalName "qfu_ingestionbatch" -Id $existing.qfu_ingestionbatchid -Fields $fields | Out-Null
      $updated += 1
    } else {
      New-CrmRecord -conn $Connection -EntityLogicalName "qfu_ingestionbatch" -Fields $fields | Out-Null
      $created += 1
    }

    $rows += [pscustomobject]@{
      source_id = $sourceId
      source_family = [string]$batchRecord.qfu_sourcefamily
      source_filename = [string]$batchRecord.qfu_sourcefilename
      started_on = (Get-DateValue $batchRecord.qfu_startedon).ToString("o")
      completed_on = (Get-DateValue $batchRecord.qfu_completedon).ToString("o")
    }
  }

  return [pscustomobject]@{
    branch_code = [string]$BranchPayload.branch.branch_code
    updated = $updated
    created = $created
    rows = $rows
  }
}

$parsedPath = Resolve-RepoPath -Path $ParsedWorkbookJson
$outputPath = Resolve-RepoPath -Path $OutputJson
$payload = Get-Content -LiteralPath $parsedPath -Raw | ConvertFrom-Json
$connection = Connect-Target -Url $TargetEnvironmentUrl -User $Username

$branchReports = @()
foreach ($branchPayload in @($payload.branches | Where-Object { [string]$_.branch.branch_code -in $BranchCodes })) {
  $backorderResult = if (-not $SkipBackorders) { Sync-Backorders -Connection $connection -BranchPayload $branchPayload } else { $null }
  $opsDailyResult = if (-not $SkipOpsDaily) { Sync-OpsDaily -Connection $connection -BranchPayload $branchPayload } else { $null }
  $budgetResult = if (-not $SkipBudget) { Sync-Budget -Connection $connection -BranchPayload $branchPayload } else { $null }
  $summaryResult = if (-not $SkipSummary) { Sync-Summary -Connection $connection -BranchPayload $branchPayload } else { $null }
  $batchResult = if (-not $SkipBatches) { Sync-Batches -Connection $connection -BranchPayload $branchPayload -Label $ReplayLabel } else { $null }

  $branchReports += [pscustomobject]@{
    branch_code = [string]$branchPayload.branch.branch_code
    backorders = $backorderResult
    ops_daily = $opsDailyResult
    budget = $budgetResult
    summary = $summaryResult
    batches = $batchResult
  }
}

$report = [pscustomobject]@{
  repaired_at = (Get-Date).ToString("o")
  target_environment_url = $TargetEnvironmentUrl
  parsed_workbook_json = $parsedPath
  replay_label = $ReplayLabel
  branches = $branchReports
}

Write-Utf8Json -Path $outputPath -Object $report
$branchReports |
  Select-Object `
    branch_code,
    @{ Name = "backorders_updated"; Expression = { if ($_.backorders) { $_.backorders.updated } else { $null } } },
    @{ Name = "backorders_created"; Expression = { if ($_.backorders) { $_.backorders.created } else { $null } } },
    @{ Name = "backorders_deactivated"; Expression = { if ($_.backorders) { $_.backorders.deactivated } else { $null } } },
    @{ Name = "budget_actual"; Expression = { if ($_.budget) { $_.budget.actual_sales } else { $null } } } |
  Format-Table -AutoSize
Write-Host "OUTPUT_PATH=$outputPath"
