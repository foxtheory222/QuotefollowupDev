param(
  [string]$TargetEnvironmentUrl = "<URL>
  [string]$Username = "<EMAIL>",
  [string[]]$BranchCodes = @("4171", "4172", "4173"),
  [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

Import-Module Microsoft.Xrm.Data.Powershell

$flowCatalog = @(
  [pscustomobject]@{
    BranchCode = "4171"
    DisplayName = "4171-Budget-Update-SA1300"
    WorkflowId = "<GUID>"
  },
  [pscustomobject]@{
    BranchCode = "4172"
    DisplayName = "4172-Budget-Update-SA1300"
    WorkflowId = "<GUID>"
  },
  [pscustomobject]@{
    BranchCode = "4173"
    DisplayName = "4173-Budget-Update-SA1300"
    WorkflowId = "<GUID>"
  }
)

$expectedCreateCadExpression = "@string(coalesce(body('Filter_CAD_Ops_Daily_Rows'), json('[]')))"
$expectedCreateUsdExpression = "@string(coalesce(outputs('Filter_USD_Ops_Daily_Rows')?['body'], json('[]')))"
$expectedActiveBudgetSelect = "qfu_budgetid,qfu_sourceid,qfu_budgetgoal,qfu_actualsales,qfu_cadsales,qfu_usdsales,qfu_opsdailycadjson,qfu_opsdailyusdjson,qfu_sourcefile,qfu_lastupdated,qfu_month,qfu_monthname,qfu_year,qfu_fiscalyear"
$expectedPreservedActualSalesExpression = "@if(and(equals(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_sourceid'], concat(parameters('qfu_QFU_BranchCode'), '|SA1300|', formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'yyyy-MM'))), greater(float(coalesce(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_actualsales'], 0)), float(coalesce(variables('TotalSales'), 0)))), outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_actualsales'], variables('TotalSales'))"
$expectedPreservedCadSalesExpression = "@if(and(equals(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_sourceid'], concat(parameters('qfu_QFU_BranchCode'), '|SA1300|', formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'yyyy-MM'))), greater(float(coalesce(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_actualsales'], 0)), float(coalesce(variables('TotalSales'), 0)))), outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_cadsales'], variables('CADSales'))"
$expectedPreservedUsdSalesExpression = "@if(and(equals(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_sourceid'], concat(parameters('qfu_QFU_BranchCode'), '|SA1300|', formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'yyyy-MM'))), greater(float(coalesce(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_actualsales'], 0)), float(coalesce(variables('TotalSales'), 0)))), outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_usdsales'], variables('USDSales'))"
$expectedPreservedSourceFileExpression = "@if(and(equals(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_sourceid'], concat(parameters('qfu_QFU_BranchCode'), '|SA1300|', formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'yyyy-MM'))), greater(float(coalesce(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_actualsales'], 0)), float(coalesce(variables('TotalSales'), 0)))), outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_sourcefile'], items('Apply_to_each_Attachment')?['name'])"
$expectedPreservedLastUpdatedExpression = "@if(and(equals(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_sourceid'], concat(parameters('qfu_QFU_BranchCode'), '|SA1300|', formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'yyyy-MM'))), greater(float(coalesce(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_actualsales'], 0)), float(coalesce(variables('TotalSales'), 0)))), outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_lastupdated'], utcNow())"
$expectedUpdateCadExpression = "@if(and(equals(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_sourceid'], concat(parameters('qfu_QFU_BranchCode'), '|SA1300|', formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'yyyy-MM'))), greater(float(coalesce(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_actualsales'], 0)), float(coalesce(variables('TotalSales'), 0)))), coalesce(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_opsdailycadjson'], string(json('[]'))), string(coalesce(body('Filter_CAD_Ops_Daily_Rows'), json('[]'))))"
$expectedUpdateUsdExpression = "@if(and(equals(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_sourceid'], concat(parameters('qfu_QFU_BranchCode'), '|SA1300|', formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'yyyy-MM'))), greater(float(coalesce(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_actualsales'], 0)), float(coalesce(variables('TotalSales'), 0)))), coalesce(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_opsdailyusdjson'], string(json('[]'))), string(coalesce(outputs('Filter_USD_Ops_Daily_Rows')?['body'], json('[]'))))"
$expectedDeleteOpsDailyForeachExpression = "@if(and(equals(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_sourceid'], concat(parameters('qfu_QFU_BranchCode'), '|SA1300|', formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'yyyy-MM'))), greater(float(coalesce(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_actualsales'], 0)), float(coalesce(variables('TotalSales'), 0)))), json('[]'), coalesce(outputs('List_Existing_Branch_Ops_Daily')?['body/value'], json('[]')))"
$expectedApplyCadOpsDailyForeachExpression = "@if(and(equals(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_sourceid'], concat(parameters('qfu_QFU_BranchCode'), '|SA1300|', formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'yyyy-MM'))), greater(float(coalesce(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_actualsales'], 0)), float(coalesce(variables('TotalSales'), 0)))), json('[]'), coalesce(body('Filter_CAD_Ops_Daily_Rows'), json('[]')))"
$expectedApplyUsdOpsDailyForeachExpression = "@if(and(equals(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_sourceid'], concat(parameters('qfu_QFU_BranchCode'), '|SA1300|', formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'yyyy-MM'))), greater(float(coalesce(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_actualsales'], 0)), float(coalesce(variables('TotalSales'), 0)))), json('[]'), coalesce(body('Filter_USD_Ops_Daily_Rows'), json('[]')))"

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

  $json = $Object | ConvertTo-Json -Depth 50
  [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function ConvertTo-JsonCompact {
  param([object]$Object)

  return ($Object | ConvertTo-Json -Depth 100 -Compress)
}

function Connect-Org {
  param([string]$Url)

  $conn = Connect-CrmOnline -ServerUrl $Url -ForceOAuth -Username $Username
  if (-not $conn -or -not $conn.IsReady) {
    throw "Dataverse connection failed for $Url : $($conn.LastCrmError)"
  }

  return $conn
}

function Set-ObjectProperty {
  param(
    [object]$Object,
    [string]$Name,
    [object]$Value
  )

  if ($Object -is [System.Collections.IDictionary]) {
    $Object[$Name] = $Value
    return
  }

  $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

function Get-ActionIfPresent {
  param(
    [object]$Parent,
    [string]$Name
  )

  if ($null -eq $Parent) {
    return $null
  }

  if (-not $Parent.PSObject.Properties[$Name]) {
    return $null
  }

  return $Parent.PSObject.Properties[$Name].Value
}

function Test-OpsDailyExpressions {
  param([object]$Definition)

  $rootActions = $Definition.actions.Apply_to_each_Attachment.actions.Condition_Is_SA1300_File.actions
  $budgetActions = $rootActions.Guard_Budget_Row_Limit.actions
  $createActions = @()
  $updateActions = @()
  $currentMonthRecordExists = Get-ActionIfPresent -Parent $budgetActions.Condition_Check_Month_Changed.actions -Name "Condition_Current_Month_Budget_Record_Exists"
  if ($currentMonthRecordExists) {
    $createActions += @(Get-ActionIfPresent -Parent $currentMonthRecordExists.else.actions -Name "Create_New_Month_Budget_Record")
    $updateActions += @(Get-ActionIfPresent -Parent $currentMonthRecordExists.actions -Name "Update_Current_Month_Budget_Record")
  }
  $createActions += @(Get-ActionIfPresent -Parent $budgetActions.Condition_Check_Month_Changed.else.actions.Condition_Budget_Exists_Same_Month.else.actions -Name "Create_First_Budget_Record")
  $updateActions += @(Get-ActionIfPresent -Parent $budgetActions.Condition_Check_Month_Changed.else.actions.Condition_Budget_Exists_Same_Month.actions -Name "Update_Current_Month_Budget")
  $createActions = @($createActions | Where-Object { $null -ne $_ })
  $updateActions = @($updateActions | Where-Object { $null -ne $_ })
  $createOk = $true
  foreach ($action in $createActions) {
    if (
      [string]$action.inputs.parameters."item/qfu_opsdailycadjson" -ne $expectedCreateCadExpression -or
      [string]$action.inputs.parameters."item/qfu_opsdailyusdjson" -ne $expectedCreateUsdExpression -or
      [string]$action.inputs.parameters.item.qfu_opsdailycadjson -ne $expectedCreateCadExpression -or
      [string]$action.inputs.parameters.item.qfu_opsdailyusdjson -ne $expectedCreateUsdExpression
    ) {
      $createOk = $false
    }
  }

  $updateOk = $true
  foreach ($action in $updateActions) {
    $updateItem = $action.inputs.parameters.item
    if (
      [string]$updateItem.qfu_actualsales -ne $expectedPreservedActualSalesExpression -or
      [string]$updateItem.qfu_cadsales -ne $expectedPreservedCadSalesExpression -or
      [string]$updateItem.qfu_usdsales -ne $expectedPreservedUsdSalesExpression -or
      [string]$updateItem.qfu_sourcefile -ne $expectedPreservedSourceFileExpression -or
      [string]$updateItem.qfu_lastupdated -ne $expectedPreservedLastUpdatedExpression -or
      [string]$updateItem.qfu_opsdailycadjson -ne $expectedUpdateCadExpression -or
      [string]$updateItem.qfu_opsdailyusdjson -ne $expectedUpdateUsdExpression
    ) {
      $updateOk = $false
    }
  }

  return [pscustomobject]@{
    create_actions_ok = $createOk
    update_action_ok = $updateOk
    active_budget_select_ok = [bool]([string]$budgetActions.Get_Active_Budget.inputs.parameters.'$select' -eq $expectedActiveBudgetSelect)
    delete_foreach_ok = [bool]([string]$rootActions.Delete_Existing_Branch_Ops_Daily.foreach -eq $expectedDeleteOpsDailyForeachExpression)
    apply_cad_foreach_ok = [bool]([string]$rootActions.Apply_to_each_CAD_Ops_Daily_Row.foreach -eq $expectedApplyCadOpsDailyForeachExpression)
    apply_usd_foreach_ok = [bool]([string]$rootActions.Apply_to_each_USD_Ops_Daily_Row.foreach -eq $expectedApplyUsdOpsDailyForeachExpression)
    analytics_update_ok = [bool](
      [string]$rootActions.Condition_Current_Month_Budget_Record_For_Analytics_Exists.actions.Update_Current_Month_Budget_Analytics_Payload.inputs.parameters.item.qfu_opsdailycadjson -eq $expectedUpdateCadExpression -and
      [string]$rootActions.Condition_Current_Month_Budget_Record_For_Analytics_Exists.actions.Update_Current_Month_Budget_Analytics_Payload.inputs.parameters.item.qfu_opsdailyusdjson -eq $expectedUpdateUsdExpression
    )
  }
}

function Repair-OpsDailyExpressions {
  param([object]$Definition)

  $rootActions = $Definition.actions.Apply_to_each_Attachment.actions.Condition_Is_SA1300_File.actions
  $budgetActions = $rootActions.Guard_Budget_Row_Limit.actions
  $createActions = @()
  $updateActions = @()
  $currentMonthRecordExists = Get-ActionIfPresent -Parent $budgetActions.Condition_Check_Month_Changed.actions -Name "Condition_Current_Month_Budget_Record_Exists"
  if ($currentMonthRecordExists) {
    $createActions += @(Get-ActionIfPresent -Parent $currentMonthRecordExists.else.actions -Name "Create_New_Month_Budget_Record")
    $updateActions += @(Get-ActionIfPresent -Parent $currentMonthRecordExists.actions -Name "Update_Current_Month_Budget_Record")
  }
  $createActions += @(Get-ActionIfPresent -Parent $budgetActions.Condition_Check_Month_Changed.else.actions.Condition_Budget_Exists_Same_Month.else.actions -Name "Create_First_Budget_Record")
  $updateActions += @(Get-ActionIfPresent -Parent $budgetActions.Condition_Check_Month_Changed.else.actions.Condition_Budget_Exists_Same_Month.actions -Name "Update_Current_Month_Budget")
  $createActions = @($createActions | Where-Object { $null -ne $_ })
  $updateActions = @($updateActions | Where-Object { $null -ne $_ })

  foreach ($action in $createActions) {
    Set-ObjectProperty -Object $action.inputs.parameters -Name "item/qfu_opsdailycadjson" -Value $expectedCreateCadExpression
    Set-ObjectProperty -Object $action.inputs.parameters -Name "item/qfu_opsdailyusdjson" -Value $expectedCreateUsdExpression
    if (-not $action.inputs.parameters.item) {
      $action.inputs.parameters | Add-Member -NotePropertyName item -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    Set-ObjectProperty -Object $action.inputs.parameters.item -Name "qfu_opsdailycadjson" -Value $expectedCreateCadExpression
    Set-ObjectProperty -Object $action.inputs.parameters.item -Name "qfu_opsdailyusdjson" -Value $expectedCreateUsdExpression
  }

  foreach ($action in $updateActions) {
    $updateItem = $action.inputs.parameters.item
    if (-not $updateItem) {
      $action.inputs.parameters | Add-Member -NotePropertyName item -NotePropertyValue ([pscustomobject]@{}) -Force
      $updateItem = $action.inputs.parameters.item
    }
    Set-ObjectProperty -Object $updateItem -Name "qfu_actualsales" -Value $expectedPreservedActualSalesExpression
    Set-ObjectProperty -Object $updateItem -Name "qfu_cadsales" -Value $expectedPreservedCadSalesExpression
    Set-ObjectProperty -Object $updateItem -Name "qfu_usdsales" -Value $expectedPreservedUsdSalesExpression
    Set-ObjectProperty -Object $updateItem -Name "qfu_sourcefile" -Value $expectedPreservedSourceFileExpression
    Set-ObjectProperty -Object $updateItem -Name "qfu_lastupdated" -Value $expectedPreservedLastUpdatedExpression
    Set-ObjectProperty -Object $updateItem -Name "qfu_opsdailycadjson" -Value $expectedUpdateCadExpression
    Set-ObjectProperty -Object $updateItem -Name "qfu_opsdailyusdjson" -Value $expectedUpdateUsdExpression
  }

  Set-ObjectProperty -Object $budgetActions.Get_Active_Budget.inputs.parameters -Name '$select' -Value $expectedActiveBudgetSelect
  $rootActions.Delete_Existing_Branch_Ops_Daily.foreach = $expectedDeleteOpsDailyForeachExpression
  $rootActions.Apply_to_each_CAD_Ops_Daily_Row.foreach = $expectedApplyCadOpsDailyForeachExpression
  $rootActions.Apply_to_each_USD_Ops_Daily_Row.foreach = $expectedApplyUsdOpsDailyForeachExpression
  Set-ObjectProperty -Object $rootActions.Condition_Current_Month_Budget_Record_For_Analytics_Exists.actions.Update_Current_Month_Budget_Analytics_Payload.inputs.parameters.item -Name "qfu_opsdailycadjson" -Value $expectedUpdateCadExpression
  Set-ObjectProperty -Object $rootActions.Condition_Current_Month_Budget_Record_For_Analytics_Exists.actions.Update_Current_Month_Budget_Analytics_Payload.inputs.parameters.item -Name "qfu_opsdailyusdjson" -Value $expectedUpdateUsdExpression
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $OutputPath = "results\sa1300-budget-opsdaily-json-live-repair-$stamp.json"
}

$connection = Connect-Org -Url $TargetEnvironmentUrl
$targets = @($flowCatalog | Where-Object { $_.BranchCode -in $BranchCodes })
$summary = New-Object System.Collections.Generic.List[object]

foreach ($target in $targets) {
  $workflow = Get-CrmRecord -conn $connection -EntityLogicalName workflow -Id $target.WorkflowId -Fields clientdata, name, statecode, statuscode, modifiedon
  if (-not $workflow.clientdata) {
    throw "Workflow $($target.WorkflowId) has no clientdata."
  }

  $workflowJson = $workflow.clientdata | ConvertFrom-Json
  $before = Test-OpsDailyExpressions -Definition $workflowJson.properties.definition
  Repair-OpsDailyExpressions -Definition $workflowJson.properties.definition
  $clientData = ConvertTo-JsonCompact -Object $workflowJson

  Set-CrmRecord -conn $connection -EntityLogicalName workflow -Id $target.WorkflowId -Fields @{ clientdata = $clientData } | Out-Null
  Set-CrmRecordState -conn $connection -EntityLogicalName workflow -Id $target.WorkflowId -StateCode Activated -StatusCode Activated | Out-Null

  $afterWorkflow = Get-CrmRecord -conn $connection -EntityLogicalName workflow -Id $target.WorkflowId -Fields clientdata, name, statecode, statuscode, modifiedon
  $afterJson = $afterWorkflow.clientdata | ConvertFrom-Json
  $after = Test-OpsDailyExpressions -Definition $afterJson.properties.definition

  $summary.Add([pscustomobject]@{
      branch_code = $target.BranchCode
      display_name = $target.DisplayName
      workflow_id = $target.WorkflowId
      before = $before
      after = $after
      modifiedon = $afterWorkflow.modifiedon
    }) | Out-Null
}

$report = [ordered]@{
  captured_at = (Get-Date).ToUniversalTime().ToString("o")
  target_environment_url = $TargetEnvironmentUrl
  branches = @($BranchCodes)
  flows = @($summary.ToArray())
}

Write-Utf8Json -Path $OutputPath -Object $report
$report | ConvertTo-Json -Depth 20
