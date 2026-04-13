param(
  [string]$TargetEnvironmentUrl = "https://regionaloperationshub.crm.dynamics.com",
  [string]$TargetEnvironmentName = "9f2e54c6-c349-e7e1-ac7c-010d3adf3c03",
  [string]$Username = "smcfarlane@applied.com",
  [string[]]$BranchCodes = @("4171", "4172", "4173"),
  [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

$flowCatalog = @(
  [pscustomobject]@{ BranchCode = "4171"; SourceFamily = "SP830CA"; DisplayName = "4171-QuoteFollowUp-Import-Staging" },
  [pscustomobject]@{ BranchCode = "4171"; SourceFamily = "ZBO"; DisplayName = "4171-BackOrder-Update-ZBO" },
  [pscustomobject]@{ BranchCode = "4171"; SourceFamily = "SA1300"; DisplayName = "4171-Budget-Update-SA1300" },
  [pscustomobject]@{ BranchCode = "4171"; SourceFamily = "GL060"; DisplayName = "4171-GL060-Inbox-Ingress" },
  [pscustomobject]@{ BranchCode = "4172"; SourceFamily = "SP830CA"; DisplayName = "4172-QuoteFollowUp-Import-Staging" },
  [pscustomobject]@{ BranchCode = "4172"; SourceFamily = "ZBO"; DisplayName = "4172-BackOrder-Update-ZBO" },
  [pscustomobject]@{ BranchCode = "4172"; SourceFamily = "SA1300"; DisplayName = "4172-Budget-Update-SA1300" },
  [pscustomobject]@{ BranchCode = "4172"; SourceFamily = "GL060"; DisplayName = "4172-GL060-Inbox-Ingress" },
  [pscustomobject]@{ BranchCode = "4173"; SourceFamily = "SP830CA"; DisplayName = "4173-QuoteFollowUp-Import-Staging" },
  [pscustomobject]@{ BranchCode = "4173"; SourceFamily = "ZBO"; DisplayName = "4173-BackOrder-Update-ZBO" },
  [pscustomobject]@{ BranchCode = "4173"; SourceFamily = "SA1300"; DisplayName = "4173-Budget-Update-SA1300" },
  [pscustomobject]@{ BranchCode = "4173"; SourceFamily = "GL060"; DisplayName = "4173-GL060-Inbox-Ingress" }
)

$expectedBudgetTableExpression = "@coalesce(body('Create_Budget_Table')?['name'], body('Create_Budget_Table')?['id'], body('Create_Budget_Table')?['Id'])"
$expectedBudgetTargetTableRange = "'Location Summary'!H2:H500"
$expectedResolvedBudgetGoalOutputExpression = "@coalesce(first(outputs('Get_Budget_Goal_From_Archives')?['body/value'])?['qfu_budgetgoal'], outputs('Resolve_Budget_Goal_From_SA1300_Plan'), outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_budgetgoal'])"
$expectedActiveBudgetSelect = "qfu_budgetid,qfu_sourceid,qfu_budgetgoal,qfu_actualsales,qfu_cadsales,qfu_usdsales,qfu_opsdailycadjson,qfu_opsdailyusdjson,qfu_sourcefile,qfu_lastupdated,qfu_month,qfu_monthname,qfu_year,qfu_fiscalyear"
$expectedPreservedActualSalesExpression = "@if(and(equals(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_sourceid'], concat(parameters('qfu_QFU_BranchCode'), '|SA1300|', formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'yyyy-MM'))), greater(float(coalesce(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_actualsales'], 0)), float(coalesce(variables('TotalSales'), 0)))), outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_actualsales'], variables('TotalSales'))"
$expectedPreservedCadOpsDailyExpression = "@if(and(equals(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_sourceid'], concat(parameters('qfu_QFU_BranchCode'), '|SA1300|', formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'yyyy-MM'))), greater(float(coalesce(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_actualsales'], 0)), float(coalesce(variables('TotalSales'), 0)))), coalesce(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_opsdailycadjson'], string(json('[]'))), string(coalesce(body('Filter_CAD_Ops_Daily_Rows'), json('[]'))))"
$expectedPreservedUsdOpsDailyExpression = "@if(and(equals(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_sourceid'], concat(parameters('qfu_QFU_BranchCode'), '|SA1300|', formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'yyyy-MM'))), greater(float(coalesce(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_actualsales'], 0)), float(coalesce(variables('TotalSales'), 0)))), coalesce(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_opsdailyusdjson'], string(json('[]'))), string(coalesce(outputs('Filter_USD_Ops_Daily_Rows')?['body'], json('[]'))))"
$expectedDeleteOpsDailyForeachExpression = "@if(and(equals(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_sourceid'], concat(parameters('qfu_QFU_BranchCode'), '|SA1300|', formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'yyyy-MM'))), greater(float(coalesce(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_actualsales'], 0)), float(coalesce(variables('TotalSales'), 0)))), json('[]'), coalesce(outputs('List_Existing_Branch_Ops_Daily')?['body/value'], json('[]')))"
$expectedApplyCadOpsDailyForeachExpression = "@if(and(equals(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_sourceid'], concat(parameters('qfu_QFU_BranchCode'), '|SA1300|', formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'yyyy-MM'))), greater(float(coalesce(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_actualsales'], 0)), float(coalesce(variables('TotalSales'), 0)))), json('[]'), coalesce(body('Filter_CAD_Ops_Daily_Rows'), json('[]')))"

function Ensure-Directory {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
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

  $json = $Object | ConvertTo-Json -Depth 20
  [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Get-TargetConnection {
  param(
    [string]$Url,
    [string]$User
  )

  Import-Module Microsoft.Xrm.Data.Powershell

  $conn = Connect-CrmOnline -ServerUrl $Url -ForceOAuth -Username $User
  if (-not $conn -or -not $conn.IsReady) {
    throw "Dataverse connection failed for $Url : $($conn.LastCrmError)"
  }

  return $conn
}

function Get-BatchMoment {
  param([object]$Row)

  foreach ($fieldName in @("qfu_completedon", "qfu_startedon", "createdon")) {
    if (-not $Row -or -not $Row.PSObject.Properties[$fieldName]) {
      continue
    }

    $value = $Row.$fieldName
    if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) {
      continue
    }

    try {
      return [datetime]$value
    } catch {
    }
  }

  return [datetime]::MinValue
}

function Get-FlowSnapshot {
  param(
    [string]$EnvironmentName,
    [string]$User
  )

  Import-Module Microsoft.PowerApps.PowerShell
  Add-PowerAppsAccount -Endpoint prod -Username $User | Out-Null

  $rows = New-Object System.Collections.Generic.List[object]
  $adminFlows = @(Get-Flow -EnvironmentName $EnvironmentName)

  foreach ($catalogEntry in $flowCatalog | Where-Object { $_.BranchCode -in $BranchCodes }) {
    $flow = $adminFlows | Where-Object { $_.DisplayName -eq $catalogEntry.DisplayName } | Select-Object -First 1
    if (-not $flow) {
      $rows.Add([pscustomobject]@{
        branch_code = $catalogEntry.BranchCode
        source_family = $catalogEntry.SourceFamily
        display_name = $catalogEntry.DisplayName
        found = $false
      }) | Out-Null
      continue
    }

    $flowRoute = "https://{flowEndpoint}/providers/Microsoft.ProcessSimple/environments/{environment}/flows/{flowName}?api-version={apiVersion}" `
      | ReplaceMacro -Macro "{environment}" -Value $EnvironmentName `
      | ReplaceMacro -Macro "{flowName}" -Value $flow.FlowName
    $runRoute = "https://{flowEndpoint}/providers/Microsoft.ProcessSimple/environments/{environment}/flows/{flowName}/runs?api-version={apiVersion}" `
      | ReplaceMacro -Macro "{environment}" -Value $EnvironmentName `
      | ReplaceMacro -Macro "{flowName}" -Value $flow.FlowName

    $detail = InvokeApi -Method GET -Route $flowRoute -ApiVersion "2016-11-01" -Verbose:$false
    $runPayload = InvokeApi -Method GET -Route $runRoute -ApiVersion "2016-11-01" -Verbose:$false
    $latestRun = @($runPayload.value | Sort-Object { [datetime]$_.properties.startTime } -Descending | Select-Object -First 1)
    $trigger = @($detail.properties.definition.triggers.PSObject.Properties)[0].Value
    $subjectFilter = if ($trigger.inputs.parameters.PSObject.Properties["subjectFilter"]) { [string]$trigger.inputs.parameters.subjectFilter } else { $null }
    $sa1300Actions = if ($catalogEntry.SourceFamily -eq "SA1300") { $detail.properties.definition.actions.Apply_to_each_Attachment.actions.Condition_Is_SA1300_File.actions } else { $null }
    $budgetTableExpression = if ($sa1300Actions) { [string]$sa1300Actions.List_Budget_Rows.inputs.parameters.table } else { $null }
    $budgetTargetTableRange = if (
      $sa1300Actions -and
      $sa1300Actions.PSObject.Properties["Create_Budget_Target_Table"]
    ) {
      [string]$sa1300Actions.Create_Budget_Target_Table.inputs.parameters."table/Range"
    } else {
      $null
    }
    $budgetGoalOutputExpression = if (
      $sa1300Actions -and
      $sa1300Actions.PSObject.Properties["Guard_Budget_Row_Limit"] -and
      $sa1300Actions.Guard_Budget_Row_Limit.actions.PSObject.Properties["Condition_Check_Month_Changed"] -and
      $sa1300Actions.Guard_Budget_Row_Limit.actions.Condition_Check_Month_Changed.else.actions.PSObject.Properties["Condition_Budget_Exists_Same_Month"]
    ) {
      [string]$sa1300Actions.Guard_Budget_Row_Limit.actions.Condition_Check_Month_Changed.else.actions.Condition_Budget_Exists_Same_Month.actions.Update_Current_Month_Budget.inputs.parameters.item.qfu_budgetgoal
    } else {
      $null
    }
    $activeBudgetSelect = if (
      $sa1300Actions -and
      $sa1300Actions.PSObject.Properties["Guard_Budget_Row_Limit"] -and
      $sa1300Actions.Guard_Budget_Row_Limit.actions.PSObject.Properties["Get_Active_Budget"]
    ) {
      [string]$sa1300Actions.Guard_Budget_Row_Limit.actions.Get_Active_Budget.inputs.parameters.'$select'
    } else {
      $null
    }
    $sameMonthActualExpression = if (
      $sa1300Actions -and
      $sa1300Actions.PSObject.Properties["Guard_Budget_Row_Limit"] -and
      $sa1300Actions.Guard_Budget_Row_Limit.actions.PSObject.Properties["Condition_Check_Month_Changed"] -and
      $sa1300Actions.Guard_Budget_Row_Limit.actions.Condition_Check_Month_Changed.else.actions.PSObject.Properties["Condition_Budget_Exists_Same_Month"]
    ) {
      [string]$sa1300Actions.Guard_Budget_Row_Limit.actions.Condition_Check_Month_Changed.else.actions.Condition_Budget_Exists_Same_Month.actions.Update_Current_Month_Budget.inputs.parameters.item.qfu_actualsales
    } else {
      $null
    }
    $deleteOpsDailyForeachExpression = if ($sa1300Actions -and $sa1300Actions.PSObject.Properties["Delete_Existing_Branch_Ops_Daily"]) {
      [string]$sa1300Actions.Delete_Existing_Branch_Ops_Daily.foreach
    } else {
      $null
    }
    $applyCadOpsDailyForeachExpression = if ($sa1300Actions -and $sa1300Actions.PSObject.Properties["Apply_to_each_CAD_Ops_Daily_Row"]) {
      [string]$sa1300Actions.Apply_to_each_CAD_Ops_Daily_Row.foreach
    } else {
      $null
    }
    $analyticsCadOpsDailyExpression = if (
      $sa1300Actions -and
      $sa1300Actions.PSObject.Properties["Condition_Current_Month_Budget_Record_For_Analytics_Exists"]
    ) {
      [string]$sa1300Actions.Condition_Current_Month_Budget_Record_For_Analytics_Exists.actions.Update_Current_Month_Budget_Analytics_Payload.inputs.parameters.item.qfu_opsdailycadjson
    } else {
      $null
    }
    $analyticsUsdOpsDailyExpression = if (
      $sa1300Actions -and
      $sa1300Actions.PSObject.Properties["Condition_Current_Month_Budget_Record_For_Analytics_Exists"]
    ) {
      [string]$sa1300Actions.Condition_Current_Month_Budget_Record_For_Analytics_Exists.actions.Update_Current_Month_Budget_Analytics_Payload.inputs.parameters.item.qfu_opsdailyusdjson
    } else {
      $null
    }

    $rows.Add([pscustomobject]@{
      branch_code = $catalogEntry.BranchCode
      source_family = $catalogEntry.SourceFamily
      display_name = $catalogEntry.DisplayName
      found = $true
      flow_name = $flow.FlowName
      state = [string]$detail.properties.state
      created_time = $detail.properties.createdTime
      last_modified_time = $detail.properties.lastModifiedTime
      trigger_type = [string]$trigger.type
      trigger_operation = [string]$trigger.inputs.host.operationId
      subject_filter = $subjectFilter
      has_recurrence = [bool]($trigger.PSObject.Properties["recurrence"])
      budget_table_expression = $budgetTableExpression
      budget_table_expression_ok = if ($catalogEntry.SourceFamily -eq "SA1300") { [bool]($budgetTableExpression -eq $expectedBudgetTableExpression) } else { $null }
      budget_target_table_range = $budgetTargetTableRange
      budget_target_table_range_ok = if ($catalogEntry.SourceFamily -eq "SA1300") { [bool]($budgetTargetTableRange -eq $expectedBudgetTargetTableRange) } else { $null }
      budget_goal_output_expression = $budgetGoalOutputExpression
      budget_goal_output_expression_ok = if ($catalogEntry.SourceFamily -eq "SA1300") { [bool]($budgetGoalOutputExpression -eq $expectedResolvedBudgetGoalOutputExpression) } else { $null }
      active_budget_select = $activeBudgetSelect
      active_budget_select_ok = if ($catalogEntry.SourceFamily -eq "SA1300") { [bool]($activeBudgetSelect -eq $expectedActiveBudgetSelect) } else { $null }
      same_month_actual_expression = $sameMonthActualExpression
      same_month_actual_expression_ok = if ($catalogEntry.SourceFamily -eq "SA1300") { [bool]($sameMonthActualExpression -eq $expectedPreservedActualSalesExpression) } else { $null }
      delete_ops_daily_foreach_expression = $deleteOpsDailyForeachExpression
      delete_ops_daily_foreach_expression_ok = if ($catalogEntry.SourceFamily -eq "SA1300") { [bool]($deleteOpsDailyForeachExpression -eq $expectedDeleteOpsDailyForeachExpression) } else { $null }
      apply_cad_ops_daily_foreach_expression = $applyCadOpsDailyForeachExpression
      apply_cad_ops_daily_foreach_expression_ok = if ($catalogEntry.SourceFamily -eq "SA1300") { [bool]($applyCadOpsDailyForeachExpression -eq $expectedApplyCadOpsDailyForeachExpression) } else { $null }
      analytics_cad_ops_daily_expression = $analyticsCadOpsDailyExpression
      analytics_cad_ops_daily_expression_ok = if ($catalogEntry.SourceFamily -eq "SA1300") { [bool]($analyticsCadOpsDailyExpression -eq $expectedPreservedCadOpsDailyExpression) } else { $null }
      analytics_usd_ops_daily_expression = $analyticsUsdOpsDailyExpression
      analytics_usd_ops_daily_expression_ok = if ($catalogEntry.SourceFamily -eq "SA1300") { [bool]($analyticsUsdOpsDailyExpression -eq $expectedPreservedUsdOpsDailyExpression) } else { $null }
      latest_run_start = if ($latestRun) { $latestRun.properties.startTime } else { $null }
      latest_run_status = if ($latestRun) { $latestRun.properties.status } else { $null }
      run_count = @($runPayload.value).Count
    }) | Out-Null
  }

  return @($rows.ToArray())
}

function Get-LatestIngestionBatch {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$BranchCode,
    [string]$SourceFamily
  )

  $rows = @(
    (Get-CrmRecords -conn $Connection -EntityLogicalName "qfu_ingestionbatch" -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $BranchCode -Fields @(
      "qfu_name",
      "qfu_branchcode",
      "qfu_sourcefamily",
      "qfu_triggerflow",
      "qfu_status",
      "qfu_sourcefilename",
      "qfu_startedon",
      "qfu_completedon",
      "createdon"
    ) -TopCount 5000).CrmRecords
  )

  return @(
    $rows |
      Where-Object { $_.qfu_sourcefamily -eq $SourceFamily } |
      Sort-Object { Get-BatchMoment -Row $_ } -Descending
  ) | Select-Object -First 1
}

function Get-LatestSnapshotBatch {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$BranchCode,
    [string]$SourceFamily
  )

  $rows = @(
    (Get-CrmRecords -conn $Connection -EntityLogicalName "qfu_ingestionbatch" -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $BranchCode -Fields @(
      "qfu_name",
      "qfu_branchcode",
      "qfu_sourcefamily",
      "qfu_triggerflow",
      "qfu_status",
      "qfu_sourcefilename",
      "qfu_startedon",
      "qfu_completedon",
      "createdon"
    ) -TopCount 5000).CrmRecords
  )

  return @(
    $rows |
      Where-Object { $_.qfu_sourcefamily -eq $SourceFamily } |
      Sort-Object { Get-BatchMoment -Row $_ } -Descending
  ) | Select-Object -First 1
}

function Get-LatestDeliveryRow {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$BranchCode
  )

  $rows = @(
    (Get-CrmRecords -conn $Connection -EntityLogicalName "qfu_deliverynotpgi" -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $BranchCode -Fields @(
      "qfu_deliverynotpgiid",
      "qfu_branchcode",
      "createdon"
    ) -TopCount 5000).CrmRecords
  )

  return @($rows | Sort-Object createdon -Descending) | Select-Object -First 1
}

function Get-LatestSnapshotRow {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$EntityLogicalName,
    [string]$BranchCode
  )

  $fieldMap = @{
    "qfu_marginexception" = @("qfu_snapshotdate", "qfu_sourcefamily", "qfu_sourcefile", "qfu_reviewtype", "createdon")
    "qfu_lateorderexception" = @("qfu_snapshotdate", "qfu_sourcefamily", "qfu_sourcefile", "qfu_billingdocumentnumber", "createdon")
  }

  $fields = @("createdon")
  if ($fieldMap.ContainsKey($EntityLogicalName)) {
    $fields = $fieldMap[$EntityLogicalName]
  }

  $rows = @(
    (Get-CrmRecords -conn $Connection -EntityLogicalName $EntityLogicalName -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $BranchCode -Fields $fields -TopCount 5000).CrmRecords
  )

  return @($rows | Sort-Object createdon -Descending) | Select-Object -First 1
}

function Get-ActiveFiscalYear {
  param([datetime]$ReferenceDate)

  $yearNumber = if ($ReferenceDate.Month -ge 7) { $ReferenceDate.Year + 1 } else { $ReferenceDate.Year }
  return "FY{0}" -f $yearNumber.ToString().Substring(2, 2)
}

function Test-BudgetRowIsActive {
  param([object]$Row)

  $value = if ($Row.PSObject.Properties['qfu_isactive']) { $Row.qfu_isactive } else { $null }
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

function Normalize-FiscalYearLabel {
  param(
    [object]$Value,
    [datetime]$FallbackDate
  )

  $text = if ([string]::IsNullOrWhiteSpace([string]$Value)) { "" } else { ([string]$Value).Trim().ToUpperInvariant() }
  if ($text -match '^FY\d{2}$') {
    return $text
  }
  if ($text -match '^\d{4}$') {
    return "FY{0}" -f $text.Substring(2, 2)
  }
  return Get-ActiveFiscalYear -ReferenceDate $FallbackDate
}

function Get-CurrentBudgetCandidates {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$BranchCode
  )

  $now = Get-Date
  $sourceId = "{0}|SA1300|{1}-{2}" -f $BranchCode, ('{0:d4}' -f $now.Year), ('{0:d2}' -f $now.Month)
  $fiscalYear = Get-ActiveFiscalYear -ReferenceDate $now

  $rows = @(
    (Get-CrmRecords -conn $Connection -EntityLogicalName "qfu_budget" -FilterAttribute "qfu_sourceid" -FilterOperator eq -FilterValue $sourceId -Fields @(
      "qfu_budgetid",
      "qfu_branchcode",
      "qfu_year",
      "qfu_name",
      "qfu_sourceid",
      "qfu_month",
      "qfu_monthname",
      "qfu_fiscalyear",
      "qfu_isactive",
      "statecode",
      "createdon"
    ) -TopCount 5000).CrmRecords
  )

  $branchRows = @(
    (Get-CrmRecords -conn $Connection -EntityLogicalName "qfu_budget" -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $BranchCode -Fields @(
      "qfu_budgetid",
      "qfu_branchcode",
      "qfu_year",
      "qfu_name",
      "qfu_sourceid",
      "qfu_month",
      "qfu_monthname",
      "qfu_fiscalyear",
      "qfu_isactive",
      "statecode",
      "createdon"
    ) -TopCount 5000).CrmRecords
  )

  $logicalCandidates = @(
    $branchRows |
      Where-Object {
        [int]$_.qfu_month -eq $now.Month -and
        (Normalize-FiscalYearLabel -Value $(if ($_.qfu_fiscalyear) { $_.qfu_fiscalyear } else { $_.qfu_year }) -FallbackDate $now) -eq $fiscalYear
      }
  )

  return [pscustomobject]@{
    source_id = $sourceId
    fiscal_year = $fiscalYear
    current_sourceid_rows = @($rows).Count
    total_candidates = @($logicalCandidates).Count
    active_candidates = @($logicalCandidates | Where-Object { Test-BudgetRowIsActive -Row $_ }).Count
    latest_createdon = if ($logicalCandidates) { (@($logicalCandidates | Sort-Object createdon -Descending | Select-Object -First 1)[0]).createdon } else { $null }
  }
}

$connection = Get-TargetConnection -Url $TargetEnvironmentUrl -User $Username
$flowRows = @(Get-FlowSnapshot -EnvironmentName $TargetEnvironmentName -User $Username)
$branchRows = New-Object System.Collections.Generic.List[object]

foreach ($branchCode in $BranchCodes) {
  $delivery = Get-LatestDeliveryRow -Connection $connection -BranchCode $branchCode
  $budget = Get-CurrentBudgetCandidates -Connection $connection -BranchCode $branchCode
  $latestMargin = Get-LatestSnapshotRow -Connection $connection -EntityLogicalName "qfu_marginexception" -BranchCode $branchCode
  $latestLateOrder = Get-LatestSnapshotRow -Connection $connection -EntityLogicalName "qfu_lateorderexception" -BranchCode $branchCode
  $latestMarginBatch = Get-LatestSnapshotBatch -Connection $connection -BranchCode $branchCode -SourceFamily "SA1300-ABNORMALMARGIN"
  $latestLateOrderBatch = Get-LatestSnapshotBatch -Connection $connection -BranchCode $branchCode -SourceFamily "SA1300-LATEORDER"

  $familyRows = foreach ($family in @("SP830CA", "ZBO", "SA1300", "GL060")) {
    $batch = Get-LatestIngestionBatch -Connection $connection -BranchCode $branchCode -SourceFamily $family
    $flow = $flowRows | Where-Object { $_.branch_code -eq $branchCode -and $_.source_family -eq $family } | Select-Object -First 1

    [pscustomobject]@{
      source_family = $family
      flow_found = if ($flow) { [bool]$flow.found } else { $false }
      flow_state = if ($flow) { $flow.state } else { $null }
      trigger_type = if ($flow) { $flow.trigger_type } else { $null }
      trigger_operation = if ($flow) { $flow.trigger_operation } else { $null }
      subject_filter = if ($flow) { $flow.subject_filter } else { $null }
      has_recurrence = if ($flow) { [bool]$flow.has_recurrence } else { $false }
      budget_table_expression = if ($flow) { $flow.budget_table_expression } else { $null }
      budget_table_expression_ok = if ($flow) { $flow.budget_table_expression_ok } else { $null }
      latest_run_start = if ($flow) { $flow.latest_run_start } else { $null }
      latest_run_status = if ($flow) { $flow.latest_run_status } else { $null }
      latest_batch_name = if ($batch) { $batch.qfu_name } else { $null }
      latest_batch_status = if ($batch) { $batch.qfu_status } else { $null }
      latest_batch_file = if ($batch) { $batch.qfu_sourcefilename } else { $null }
      latest_batch_trigger = if ($batch) { $batch.qfu_triggerflow } else { $null }
      latest_batch_createdon = if ($batch) { $batch.createdon } else { $null }
    }
  }

  $branchRows.Add([pscustomobject]@{
    branch_code = $branchCode
    delivery_latest_createdon = if ($delivery) { $delivery.createdon } else { $null }
    current_month_budget_source_id = $budget.source_id
    current_month_budget_fiscal_year = $budget.fiscal_year
    current_month_budget_source_id_rows = [int]$budget.current_sourceid_rows
    current_month_budget_candidates = [int]$budget.total_candidates
    current_month_budget_active_candidates = [int]$budget.active_candidates
    current_month_budget_latest_createdon = $budget.latest_createdon
    abnormal_margin = [pscustomobject]@{
      latest_createdon = if ($latestMargin) { $latestMargin.createdon } else { $null }
      latest_snapshotdate = if ($latestMargin) { $latestMargin.qfu_snapshotdate } else { $null }
      latest_sourcefile = if ($latestMargin) { $latestMargin.qfu_sourcefile } else { $null }
      latest_reviewtype = if ($latestMargin) { $latestMargin.qfu_reviewtype } else { $null }
      latest_batch_name = if ($latestMarginBatch) { $latestMarginBatch.qfu_name } else { $null }
      latest_batch_status = if ($latestMarginBatch) { $latestMarginBatch.qfu_status } else { $null }
      latest_batch_file = if ($latestMarginBatch) { $latestMarginBatch.qfu_sourcefilename } else { $null }
      latest_batch_trigger = if ($latestMarginBatch) { $latestMarginBatch.qfu_triggerflow } else { $null }
      latest_batch_createdon = if ($latestMarginBatch) { $latestMarginBatch.createdon } else { $null }
    }
    late_order = [pscustomobject]@{
      latest_createdon = if ($latestLateOrder) { $latestLateOrder.createdon } else { $null }
      latest_snapshotdate = if ($latestLateOrder) { $latestLateOrder.qfu_snapshotdate } else { $null }
      latest_sourcefile = if ($latestLateOrder) { $latestLateOrder.qfu_sourcefile } else { $null }
      latest_billingdocumentnumber = if ($latestLateOrder) { $latestLateOrder.qfu_billingdocumentnumber } else { $null }
      latest_batch_name = if ($latestLateOrderBatch) { $latestLateOrderBatch.qfu_name } else { $null }
      latest_batch_status = if ($latestLateOrderBatch) { $latestLateOrderBatch.qfu_status } else { $null }
      latest_batch_file = if ($latestLateOrderBatch) { $latestLateOrderBatch.qfu_sourcefilename } else { $null }
      latest_batch_trigger = if ($latestLateOrderBatch) { $latestLateOrderBatch.qfu_triggerflow } else { $null }
      latest_batch_createdon = if ($latestLateOrderBatch) { $latestLateOrderBatch.createdon } else { $null }
    }
    families = @($familyRows)
  }) | Out-Null
}

$report = [pscustomobject]@{
  captured_at = (Get-Date).ToUniversalTime().ToString("o")
  environment_url = $TargetEnvironmentUrl
  environment_name = $TargetEnvironmentName
  branch_codes = @($BranchCodes)
  expected_budget_table_expression = $expectedBudgetTableExpression
  expected_budget_target_table_range = $expectedBudgetTargetTableRange
  expected_budget_goal_output_expression = $expectedResolvedBudgetGoalOutputExpression
  branches = @($branchRows.ToArray())
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $OutputPath = Join-Path (Join-Path (Get-Location) "results") "southern-alberta-runtime-readiness-$stamp.json"
}

Write-Utf8Json -Path $OutputPath -Object $report

$report.branches |
  Select-Object branch_code, delivery_latest_createdon, current_month_budget_candidates, current_month_budget_active_candidates |
  Format-Table -AutoSize

Write-Host "OUTPUT_PATH=$OutputPath"
