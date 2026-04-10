param(
  [string]$RepoRoot = "C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion",
  [string]$TargetEnvironmentUrl = "https://regionaloperationshub.crm.dynamics.com",
  [string]$Username = "smcfarlane@applied.com",
  [string[]]$BranchCodes = @("4171", "4172", "4173"),
  [string]$OutputPath = "",
  [string]$ProgressPath = ""
)

$ErrorActionPreference = "Stop"

$flowCatalog = @(
  [pscustomobject]@{
    BranchCode = "4171"
    DisplayName = "4171-Budget-Update-SA1300"
    WorkflowId = "6db19ff3-c313-4db6-9a57-f3335fe55558"
  },
  [pscustomobject]@{
    BranchCode = "4172"
    DisplayName = "4172-Budget-Update-SA1300"
    WorkflowId = "078cea4c-84f6-4c4f-b73b-62ad838f7cae"
  },
  [pscustomobject]@{
    BranchCode = "4173"
    DisplayName = "4173-Budget-Update-SA1300"
    WorkflowId = "3c2ebd80-35d9-4e3c-bdbe-70be98a82ae6"
  }
)

$expectedBudgetTableExpression = "@coalesce(body('Create_Budget_Table')?['name'], body('Create_Budget_Table')?['id'], body('Create_Budget_Table')?['Id'])"
$expectedBudgetTargetTableRange = "'Location Summary'!H2:H500"
$expectedResolvedBudgetGoalOutputExpression = "@coalesce(first(outputs('Get_Budget_Goal_From_Archives')?['body/value'])?['qfu_budgetgoal'], outputs('Resolve_Budget_Goal_From_SA1300_Plan'), outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_budgetgoal'])"
$expectedAbnormalMarginBillingDateExpression = "@if(empty(items('Apply_to_each_Abnormal_Margin_Row')?['Billing Date']), null, if(or(contains(string(items('Apply_to_each_Abnormal_Margin_Row')?['Billing Date']), '-'), contains(string(items('Apply_to_each_Abnormal_Margin_Row')?['Billing Date']), '/')), formatDateTime(items('Apply_to_each_Abnormal_Margin_Row')?['Billing Date'], 'yyyy-MM-dd'), formatDateTime(addDays('1899-12-30', int(float(items('Apply_to_each_Abnormal_Margin_Row')?['Billing Date']))), 'yyyy-MM-dd')))"

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

function Write-ProgressLog {
  param(
    [string]$Path,
    [string]$Message
  )

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return
  }

  $directory = Split-Path -Parent $Path
  if ($directory) {
    Ensure-Directory -Path $directory
  }

  $line = "{0} {1}" -f (Get-Date).ToString("o"), $Message
  [System.IO.File]::AppendAllText($Path, $line + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}

function ConvertTo-JsonCompact {
  param([object]$Object)

  return ($Object | ConvertTo-Json -Depth 100 -Compress)
}

function Get-CanonicalWorkflowPath {
  param(
    [string]$RepoRootPath,
    [string]$DisplayName,
    [string]$WorkflowId
  )

  $pattern = "{0}-{1}.json" -f $DisplayName, $WorkflowId.ToUpperInvariant()
  $workflowRoot = Join-Path $RepoRootPath "results\sapilotflows\src\Workflows"
  $path = Join-Path $workflowRoot $pattern
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Canonical workflow JSON not found: $path"
  }

  return $path
}

function Get-HostConnectionMap {
  param([object]$Node)

  $map = @{}

  function Walk-Node {
    param([object]$Current)

    if ($null -eq $Current) {
      return
    }

    if ($Current -is [System.Collections.IEnumerable] -and -not ($Current -is [string])) {
      foreach ($item in $Current) {
        Walk-Node -Current $item
      }
      return
    }

    if ($Current -isnot [System.Management.Automation.PSCustomObject]) {
      return
    }

    if (
      $Current.PSObject.Properties["inputs"] -and
      $Current.inputs -and
      $Current.inputs.PSObject.Properties["host"] -and
      $Current.inputs.host
    ) {
      $hostInfo = $Current.inputs.host
      $apiId = if ($hostInfo.PSObject.Properties["apiId"]) { [string]$hostInfo.apiId } else { $null }
      $connectionName = if ($hostInfo.PSObject.Properties["connectionName"]) { [string]$hostInfo.connectionName } else { $null }
      if (-not [string]::IsNullOrWhiteSpace($apiId) -and -not [string]::IsNullOrWhiteSpace($connectionName)) {
        $map[$apiId] = $connectionName
      }
    }

    foreach ($property in @($Current.PSObject.Properties)) {
      Walk-Node -Current $property.Value
    }
  }

  Walk-Node -Current $Node
  return $map
}

function Apply-HostConnectionMap {
  param(
    [object]$Node,
    [hashtable]$HostConnectionMap
  )

  function Walk-Node {
    param([object]$Current)

    if ($null -eq $Current) {
      return
    }

    if ($Current -is [System.Collections.IEnumerable] -and -not ($Current -is [string])) {
      foreach ($item in $Current) {
        Walk-Node -Current $item
      }
      return
    }

    if ($Current -isnot [System.Management.Automation.PSCustomObject]) {
      return
    }

    if (
      $Current.PSObject.Properties["inputs"] -and
      $Current.inputs -and
      $Current.inputs.PSObject.Properties["host"] -and
      $Current.inputs.host -and
      $Current.inputs.host.PSObject.Properties["apiId"]
    ) {
      $apiId = [string]$Current.inputs.host.apiId
      if ($HostConnectionMap.ContainsKey($apiId)) {
        $Current.inputs.host.connectionName = $HostConnectionMap[$apiId]
      }
    }

    foreach ($property in @($Current.PSObject.Properties)) {
      Walk-Node -Current $property.Value
    }
  }

  Walk-Node -Current $Node
}

function Get-Sa1300DefinitionState {
  param([object]$Definition)

  $rootActions = $Definition.actions.Apply_to_each_Attachment.actions.Condition_Is_SA1300_File.actions
  $snapshotVariable = $Definition.actions.PSObject.Properties["Initialize_Variable_SA1300_Snapshot_Date"]
  $filterRunAfter = if (
    $Definition.actions.PSObject.Properties["Filter_SA1300_Attachments"] -and
    $Definition.actions.Filter_SA1300_Attachments.PSObject.Properties["runAfter"]
  ) {
    $Definition.actions.Filter_SA1300_Attachments.runAfter
  } else {
    $null
  }

  return [pscustomobject]@{
    has_snapshot_variable = [bool]$snapshotVariable
    snapshot_variable_name = if ($snapshotVariable) { [string]$Definition.actions.Initialize_Variable_SA1300_Snapshot_Date.inputs.variables[0].name } else { $null }
    filter_waits_for_snapshot_variable = [bool](
      $filterRunAfter -and
      $filterRunAfter.PSObject.Properties["Initialize_Variable_SA1300_Snapshot_Date"]
    )
    has_abnormal_margin_table = [bool]($rootActions.PSObject.Properties["Create_Abnormal_Margin_Table"])
    has_abnormal_margin_row_loop = [bool]($rootActions.PSObject.Properties["Apply_to_each_Abnormal_Margin_Row"])
    has_abnormal_margin_batch = [bool]($rootActions.PSObject.Properties["Create_Abnormal_Margin_Batch"])
    has_usd_ops_daily_table = [bool]($rootActions.PSObject.Properties["Create_USD_Ops_Daily_Table"])
    has_usd_ops_daily_row_loop = [bool]($rootActions.PSObject.Properties["Apply_to_each_USD_Ops_Daily_Row"])
    has_cad_ops_daily_table = [bool]($rootActions.PSObject.Properties["Create_CAD_Ops_Daily_Table"])
    has_cad_ops_daily_row_loop = [bool]($rootActions.PSObject.Properties["Apply_to_each_CAD_Ops_Daily_Row"])
    has_cad_ops_daily_fallback_table = [bool]($rootActions.PSObject.Properties["Create_CAD_Ops_Daily_Fallback_Table"])
    has_cad_ops_daily_fallback_row_loop = [bool]($rootActions.PSObject.Properties["Apply_to_each_CAD_Ops_Daily_Fallback_Row"])
    branch_ops_daily_list_entity = if ($rootActions.PSObject.Properties["List_Existing_Branch_Ops_Daily"]) { [string]$rootActions.List_Existing_Branch_Ops_Daily.inputs.parameters.entityName } else { $null }
    branch_ops_daily_delete_entity = if (
      $rootActions.PSObject.Properties["Delete_Existing_Branch_Ops_Daily"] -and
      $rootActions.Delete_Existing_Branch_Ops_Daily.actions.PSObject.Properties["Delete_Branch_Ops_Daily_Record"]
    ) {
      [string]$rootActions.Delete_Existing_Branch_Ops_Daily.actions.Delete_Branch_Ops_Daily_Record.inputs.parameters.entityName
    } else {
      $null
    }
    branch_ops_daily_usd_create_entity = if (
      $rootActions.PSObject.Properties["Apply_to_each_USD_Ops_Daily_Row"] -and
      $rootActions.Apply_to_each_USD_Ops_Daily_Row.actions.PSObject.Properties["Create_USD_Branch_Ops_Daily_Record"]
    ) {
      [string]$rootActions.Apply_to_each_USD_Ops_Daily_Row.actions.Create_USD_Branch_Ops_Daily_Record.inputs.parameters.entityName
    } else {
      $null
    }
    branch_ops_daily_cad_create_entity = if (
      $rootActions.PSObject.Properties["Apply_to_each_CAD_Ops_Daily_Row"] -and
      $rootActions.Apply_to_each_CAD_Ops_Daily_Row.actions.PSObject.Properties["Create_CAD_Branch_Ops_Daily_Record"]
    ) {
      [string]$rootActions.Apply_to_each_CAD_Ops_Daily_Row.actions.Create_CAD_Branch_Ops_Daily_Record.inputs.parameters.entityName
    } else {
      $null
    }
    branch_ops_daily_entity_ok = [bool](
      $rootActions.PSObject.Properties["List_Existing_Branch_Ops_Daily"] -and
      [string]$rootActions.List_Existing_Branch_Ops_Daily.inputs.parameters.entityName -eq "qfu_branchopsdailies" -and
      $rootActions.PSObject.Properties["Delete_Existing_Branch_Ops_Daily"] -and
      $rootActions.Delete_Existing_Branch_Ops_Daily.actions.PSObject.Properties["Delete_Branch_Ops_Daily_Record"] -and
      [string]$rootActions.Delete_Existing_Branch_Ops_Daily.actions.Delete_Branch_Ops_Daily_Record.inputs.parameters.entityName -eq "qfu_branchopsdailies" -and
      $rootActions.PSObject.Properties["Apply_to_each_USD_Ops_Daily_Row"] -and
      $rootActions.Apply_to_each_USD_Ops_Daily_Row.actions.PSObject.Properties["Create_USD_Branch_Ops_Daily_Record"] -and
      [string]$rootActions.Apply_to_each_USD_Ops_Daily_Row.actions.Create_USD_Branch_Ops_Daily_Record.inputs.parameters.entityName -eq "qfu_branchopsdailies" -and
      $rootActions.PSObject.Properties["Apply_to_each_CAD_Ops_Daily_Row"] -and
      $rootActions.Apply_to_each_CAD_Ops_Daily_Row.actions.PSObject.Properties["Create_CAD_Branch_Ops_Daily_Record"] -and
      [string]$rootActions.Apply_to_each_CAD_Ops_Daily_Row.actions.Create_CAD_Branch_Ops_Daily_Record.inputs.parameters.entityName -eq "qfu_branchopsdailies"
    )
    budget_table_expression = if ($rootActions.PSObject.Properties["List_Budget_Rows"]) { [string]$rootActions.List_Budget_Rows.inputs.parameters.table } else { $null }
    budget_table_expression_ok = [bool](
      $rootActions.PSObject.Properties["List_Budget_Rows"] -and
      [string]$rootActions.List_Budget_Rows.inputs.parameters.table -eq $expectedBudgetTableExpression
    )
    has_budget_target_table = [bool]($rootActions.PSObject.Properties["Create_Budget_Target_Table"])
    budget_target_table_range = if (
      $rootActions.PSObject.Properties["Create_Budget_Target_Table"]
    ) {
      [string]$rootActions.Create_Budget_Target_Table.inputs.parameters."table/Range"
    } else {
      $null
    }
    budget_target_table_range_ok = [bool](
      $rootActions.PSObject.Properties["Create_Budget_Target_Table"] -and
      [string]$rootActions.Create_Budget_Target_Table.inputs.parameters."table/Range" -eq $expectedBudgetTargetTableRange
    )
    has_budget_goal_resolver = [bool]($rootActions.PSObject.Properties["Resolve_Budget_Goal_From_SA1300_Plan"])
    budget_goal_output_expression = if (
      $rootActions.PSObject.Properties["Guard_Budget_Row_Limit"] -and
      $rootActions.Guard_Budget_Row_Limit.actions.PSObject.Properties["Condition_Check_Month_Changed"] -and
      $rootActions.Guard_Budget_Row_Limit.actions.Condition_Check_Month_Changed.else.actions.PSObject.Properties["Condition_Budget_Exists_Same_Month"]
    ) {
      [string]$rootActions.Guard_Budget_Row_Limit.actions.Condition_Check_Month_Changed.else.actions.Condition_Budget_Exists_Same_Month.actions.Update_Current_Month_Budget.inputs.parameters.item.qfu_budgetgoal
    } else {
      $null
    }
    budget_goal_output_expression_ok = [bool](
      $rootActions.PSObject.Properties["Guard_Budget_Row_Limit"] -and
      $rootActions.Guard_Budget_Row_Limit.actions.PSObject.Properties["Condition_Check_Month_Changed"] -and
      $rootActions.Guard_Budget_Row_Limit.actions.Condition_Check_Month_Changed.else.actions.PSObject.Properties["Condition_Budget_Exists_Same_Month"] -and
      [string]$rootActions.Guard_Budget_Row_Limit.actions.Condition_Check_Month_Changed.else.actions.Condition_Budget_Exists_Same_Month.actions.Update_Current_Month_Budget.inputs.parameters.item.qfu_budgetgoal -eq $expectedResolvedBudgetGoalOutputExpression
    )
    abnormal_margin_billingdate_expression = if (
      $rootActions.PSObject.Properties["Apply_to_each_Abnormal_Margin_Row"] -and
      $rootActions.Apply_to_each_Abnormal_Margin_Row.actions.PSObject.Properties["Create_Abnormal_Margin_Record"]
    ) {
      [string]$rootActions.Apply_to_each_Abnormal_Margin_Row.actions.Create_Abnormal_Margin_Record.inputs.parameters."item/qfu_billingdate"
    } else {
      $null
    }
    abnormal_margin_billingdate_expression_ok = [bool](
      $rootActions.PSObject.Properties["Apply_to_each_Abnormal_Margin_Row"] -and
      $rootActions.Apply_to_each_Abnormal_Margin_Row.actions.PSObject.Properties["Create_Abnormal_Margin_Record"] -and
      [string]$rootActions.Apply_to_each_Abnormal_Margin_Row.actions.Create_Abnormal_Margin_Record.inputs.parameters."item/qfu_billingdate" -eq $expectedAbnormalMarginBillingDateExpression
    )
  }
}

function Repair-LiveBudgetDefinition {
  param(
    [object]$LiveDefinition,
    [object]$CanonicalDefinition
  )

  $liveHostConnectionMap = Get-HostConnectionMap -Node $LiveDefinition
  $canonicalSnapshotVariable = $CanonicalDefinition.actions.Initialize_Variable_SA1300_Snapshot_Date | ConvertTo-Json -Depth 100 | ConvertFrom-Json
  $canonicalFilterRunAfter = $CanonicalDefinition.actions.Filter_SA1300_Attachments.runAfter | ConvertTo-Json -Depth 100 | ConvertFrom-Json
  $canonicalBudgetRoot = $CanonicalDefinition.actions.Apply_to_each_Attachment.actions.Condition_Is_SA1300_File.actions

  Apply-HostConnectionMap -Node $canonicalSnapshotVariable -HostConnectionMap $liveHostConnectionMap

  $snapshotActionNames = @(
    "Create_Abnormal_Margin_Table",
    "List_Abnormal_Margin_Rows",
    "Filter_Abnormal_Margin_Rows",
    "List_Existing_Abnormal_Margin_Snapshot",
    "Filter_Existing_Abnormal_Margin_Snapshot",
    "Delete_Existing_Abnormal_Margin_Snapshot",
    "Apply_to_each_Abnormal_Margin_Row",
    "List_Existing_Abnormal_Margin_Batches",
    "Filter_Existing_Abnormal_Margin_Batches",
    "Delete_Existing_Abnormal_Margin_Batches",
    "Create_Abnormal_Margin_Batch",
    "Create_USD_Ops_Daily_Table",
    "List_USD_Ops_Daily_Rows",
    "Filter_USD_Ops_Daily_Rows",
    "Initialize_CAD_Ops_Daily_Rows",
    "Create_CAD_Ops_Daily_Table",
    "List_CAD_Ops_Daily_Rows",
    "Filter_CAD_Ops_Daily_Rows",
    "Condition_CAD_Ops_Daily_Rows_Resolved",
    "Create_CAD_Ops_Daily_Fallback_Table",
    "List_CAD_Ops_Daily_Fallback_Rows",
    "Filter_CAD_Ops_Daily_Fallback_Rows",
    "Select_CAD_Ops_Daily_Rows",
    "List_Existing_Branch_Ops_Daily",
    "Delete_Existing_Branch_Ops_Daily",
    "Apply_to_each_USD_Ops_Daily_Row",
    "Apply_to_each_CAD_Ops_Daily_Row",
    "Get_Current_Month_Budget_Record_For_Analytics",
    "Condition_Current_Month_Budget_Record_For_Analytics_Exists"
  )
  $budgetTargetActionNames = @(
    "Create_Budget_Target_Table",
    "List_Budget_Target_Rows",
    "Filter_Budget_Target_Rows",
    "Resolve_Budget_Goal_From_SA1300_Plan"
  )
  $staleActionNames = @(
    "Apply_to_each_CAD_Ops_Daily_Fallback_Row"
  )
  $snapshotActionSet = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($actionName in $snapshotActionNames) {
    [void]$snapshotActionSet.Add($actionName)
  }
  foreach ($actionName in $staleActionNames) {
    [void]$snapshotActionSet.Add($actionName)
  }

  $updatedTopLevelActions = [ordered]@{}
  foreach ($property in @($LiveDefinition.actions.PSObject.Properties)) {
    if ($property.Name -eq "Initialize_Variable_SA1300_Snapshot_Date") {
      continue
    }

    $updatedTopLevelActions[$property.Name] = $property.Value
    if ($property.Name -eq "Initialize_Variable_BudgetGoalError") {
      $updatedTopLevelActions.Initialize_Variable_SA1300_Snapshot_Date = $canonicalSnapshotVariable
    }
  }
  if (-not $updatedTopLevelActions.Contains("Initialize_Variable_SA1300_Snapshot_Date")) {
    $updatedTopLevelActions.Initialize_Variable_SA1300_Snapshot_Date = $canonicalSnapshotVariable
  }
  $LiveDefinition.actions = [pscustomobject]$updatedTopLevelActions
  $LiveDefinition.actions.Filter_SA1300_Attachments.runAfter = $canonicalFilterRunAfter

  $liveBudgetRoot = $LiveDefinition.actions.Apply_to_each_Attachment.actions.Condition_Is_SA1300_File.actions
  $updatedBudgetRootActions = [ordered]@{}
  foreach ($property in @($liveBudgetRoot.PSObject.Properties)) {
    if ($snapshotActionSet.Contains($property.Name)) {
      continue
    }

    if (
      $property.Name -eq "List_Budget_Rows" -and
      $property.Value -and
      $property.Value.inputs -and
      $property.Value.inputs.parameters
    ) {
      $property.Value.inputs.parameters.table = $expectedBudgetTableExpression
    }

    if ($property.Name -eq "Guard_Budget_Row_Limit") {
      foreach ($actionName in $budgetTargetActionNames) {
        $canonicalProperty = $canonicalBudgetRoot.PSObject.Properties[$actionName]
        if (-not $canonicalProperty) {
          continue
        }

        $canonicalAction = $canonicalProperty.Value | ConvertTo-Json -Depth 100 | ConvertFrom-Json
        Apply-HostConnectionMap -Node $canonicalAction -HostConnectionMap $liveHostConnectionMap
        $updatedBudgetRootActions[$actionName] = $canonicalAction
      }

      $liveGuard = $property.Value
      $canonicalGuard = $canonicalBudgetRoot.Guard_Budget_Row_Limit
      $liveGuard.runAfter = $canonicalGuard.runAfter | ConvertTo-Json -Depth 20 | ConvertFrom-Json
      foreach ($guardActionName in @("Get_Budget_Goal_From_Archives", "Get_Active_Budget", "Ensure_Budget_Goal_Found", "Condition_Check_Month_Changed")) {
        if (-not $canonicalGuard.actions.PSObject.Properties[$guardActionName]) {
          continue
        }

        $canonicalGuardAction = $canonicalGuard.actions.PSObject.Properties[$guardActionName].Value | ConvertTo-Json -Depth 100 | ConvertFrom-Json
        Apply-HostConnectionMap -Node $canonicalGuardAction -HostConnectionMap $liveHostConnectionMap
        $liveGuard.actions | Add-Member -NotePropertyName $guardActionName -NotePropertyValue $canonicalGuardAction -Force
      }

      $updatedBudgetRootActions[$property.Name] = $liveGuard
      foreach ($actionName in $snapshotActionNames) {
        $canonicalProperty = $canonicalBudgetRoot.PSObject.Properties[$actionName]
        if (-not $canonicalProperty) {
          continue
        }

        $canonicalAction = $canonicalProperty.Value | ConvertTo-Json -Depth 100 | ConvertFrom-Json
        Apply-HostConnectionMap -Node $canonicalAction -HostConnectionMap $liveHostConnectionMap
        $updatedBudgetRootActions[$actionName] = $canonicalAction
      }
      continue
    }

    $updatedBudgetRootActions[$property.Name] = $property.Value
  }

  $LiveDefinition.actions.Apply_to_each_Attachment.actions.Condition_Is_SA1300_File.actions = [pscustomobject]$updatedBudgetRootActions
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $OutputPath = Join-Path (Join-Path (Get-Location) "results") "sa1300-abnormal-margin-live-repair-xrm-$stamp.json"
}

if ([string]::IsNullOrWhiteSpace($ProgressPath)) {
  $ProgressPath = [System.IO.Path]::ChangeExtension($OutputPath, ".log")
}

Import-Module Microsoft.Xrm.Data.Powershell

Write-ProgressLog -Path $ProgressPath -Message "Import complete. Starting Connect-CrmOnline."
$connection = Connect-CrmOnline -ServerUrl $TargetEnvironmentUrl -ForceOAuth -Username $Username
if (-not $connection -or -not $connection.IsReady) {
  throw "Dataverse connection failed for $TargetEnvironmentUrl : $($connection.LastCrmError)"
}
Write-ProgressLog -Path $ProgressPath -Message "Connect-CrmOnline complete."

$targetFlows = @($flowCatalog | Where-Object { $_.BranchCode -in $BranchCodes })
$reportRows = New-Object System.Collections.Generic.List[object]

foreach ($targetFlow in $targetFlows) {
  try {
    Write-ProgressLog -Path $ProgressPath -Message ("[{0}] Loading canonical JSON." -f $targetFlow.BranchCode)
    $canonicalPath = Get-CanonicalWorkflowPath -RepoRootPath $RepoRoot -DisplayName $targetFlow.DisplayName -WorkflowId $targetFlow.WorkflowId
    $canonicalJson = Get-Content -LiteralPath $canonicalPath -Raw | ConvertFrom-Json

    Write-ProgressLog -Path $ProgressPath -Message ("[{0}] Reading live workflow clientdata." -f $targetFlow.BranchCode)
    $workflowRecord = Get-CrmRecord -conn $connection -EntityLogicalName workflow -Id $targetFlow.WorkflowId -Fields clientdata, name, statecode, statuscode, modifiedon
    if (-not $workflowRecord.clientdata) {
      throw "Workflow $($targetFlow.WorkflowId) has no clientdata."
    }

    $liveJson = $workflowRecord.clientdata | ConvertFrom-Json
    $beforeState = Get-Sa1300DefinitionState -Definition $liveJson.properties.definition

    Write-ProgressLog -Path $ProgressPath -Message ("[{0}] Applying abnormal-margin repair." -f $targetFlow.BranchCode)
    Repair-LiveBudgetDefinition -LiveDefinition $liveJson.properties.definition -CanonicalDefinition $canonicalJson.properties.definition

    $stamp = Get-Date -Format "yyyyMMdd.HHmmss"
    if ($liveJson.PSObject.Properties["properties"] -and $liveJson.properties.PSObject.Properties["state"]) {
      $liveJson.properties.state = "Started"
    }
    $liveJson.properties.definition.contentVersion = "1.0.$stamp"
    $clientData = ConvertTo-JsonCompact -Object $liveJson

    Write-ProgressLog -Path $ProgressPath -Message ("[{0}] Writing clientdata back to Dataverse." -f $targetFlow.BranchCode)
    Set-CrmRecord -conn $connection -EntityLogicalName workflow -Id $targetFlow.WorkflowId -Fields @{ clientdata = $clientData } | Out-Null
    Set-CrmRecordState -conn $connection -EntityLogicalName workflow -Id $targetFlow.WorkflowId -StateCode Activated -StatusCode Activated | Out-Null

    Write-ProgressLog -Path $ProgressPath -Message ("[{0}] Reading repaired workflow clientdata." -f $targetFlow.BranchCode)
    $afterWorkflow = Get-CrmRecord -conn $connection -EntityLogicalName workflow -Id $targetFlow.WorkflowId -Fields clientdata, name, statecode, statuscode, modifiedon
    $afterJson = $afterWorkflow.clientdata | ConvertFrom-Json
    $afterState = Get-Sa1300DefinitionState -Definition $afterJson.properties.definition

    $reportRows.Add([pscustomobject]@{
      branch_code = $targetFlow.BranchCode
      display_name = $targetFlow.DisplayName
      workflow_id = $targetFlow.WorkflowId
      canonical_path = $canonicalPath
      patched = $true
      before = $beforeState
      after = $afterState
      workflow_state_after = $afterWorkflow.statecode
      workflow_status_after = $afterWorkflow.statuscode
      workflow_modifiedon_after = $afterWorkflow.modifiedon
    }) | Out-Null
    Write-ProgressLog -Path $ProgressPath -Message ("[{0}] Repair verified successfully." -f $targetFlow.BranchCode)
  } catch {
    Write-ProgressLog -Path $ProgressPath -Message ("[{0}] Repair failed: {1}" -f $targetFlow.BranchCode, $_.Exception.Message)
    $reportRows.Add([pscustomobject]@{
      branch_code = $targetFlow.BranchCode
      display_name = $targetFlow.DisplayName
      workflow_id = $targetFlow.WorkflowId
      patched = $false
      error = $_.Exception.Message
    }) | Out-Null
  }
}

$report = [pscustomobject]@{
  captured_at = (Get-Date).ToUniversalTime().ToString("o")
  target_environment_url = $TargetEnvironmentUrl
  branch_codes = @($BranchCodes)
  expected_budget_table_expression = $expectedBudgetTableExpression
  rows = @($reportRows.ToArray())
}

Write-ProgressLog -Path $ProgressPath -Message "Writing repair summary."
Write-Utf8Json -Path $OutputPath -Object $report

  $report.rows |
  Select-Object branch_code, patched,
    @{ Name = "snapshot_var"; Expression = { if ($_.after) { $_.after.has_snapshot_variable } else { $null } } },
    @{ Name = "margin_table"; Expression = { if ($_.after) { $_.after.has_abnormal_margin_table } else { $null } } },
    @{ Name = "margin_batch"; Expression = { if ($_.after) { $_.after.has_abnormal_margin_batch } else { $null } } },
    @{ Name = "usd_ops"; Expression = { if ($_.after) { $_.after.has_usd_ops_daily_row_loop } else { $null } } },
    @{ Name = "cad_ops"; Expression = { if ($_.after) { $_.after.has_cad_ops_daily_row_loop } else { $null } } },
    @{ Name = "budget_expr_ok"; Expression = { if ($_.after) { $_.after.budget_table_expression_ok } else { $null } } },
    workflow_modifiedon_after |
  Format-Table -AutoSize

Write-Host "OUTPUT_PATH=$OutputPath"
