param(
  [string]$RepoRoot = "C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion",
  [string]$TargetEnvironmentName = "9f2e54c6-c349-e7e1-ac7c-010d3adf3c03",
  [string]$Username = "smcfarlane@applied.com",
  [string[]]$BranchCodes = @("4171", "4172", "4173"),
  [bool]$RestartAfterPatch = $true,
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

  return [pscustomobject]@{
    budget_table_expression = if ($rootActions.PSObject.Properties["List_Budget_Rows"]) { [string]$rootActions.List_Budget_Rows.inputs.parameters.table } else { $null }
    budget_table_expression_ok = [bool](
      $rootActions.PSObject.Properties["List_Budget_Rows"] -and
      [string]$rootActions.List_Budget_Rows.inputs.parameters.table -eq $expectedBudgetTableExpression
    )
    has_budget_target_table = [bool]($rootActions.PSObject.Properties["Create_Budget_Target_Table"])
    budget_target_table_range = if ($rootActions.PSObject.Properties["Create_Budget_Target_Table"]) { [string]$rootActions.Create_Budget_Target_Table.inputs.parameters."table/Range" } else { $null }
    budget_target_table_range_ok = [bool](
      $rootActions.PSObject.Properties["Create_Budget_Target_Table"] -and
      [string]$rootActions.Create_Budget_Target_Table.inputs.parameters."table/Range" -eq $expectedBudgetTargetTableRange
    )
    has_budget_goal_resolver = [bool]($rootActions.PSObject.Properties["Resolve_Budget_Goal_From_SA1300_Plan"])
    guard_waits_for_plan_resolver = [bool](
      $rootActions.PSObject.Properties["Guard_Budget_Row_Limit"] -and
      $rootActions.Guard_Budget_Row_Limit.PSObject.Properties["runAfter"] -and
      $rootActions.Guard_Budget_Row_Limit.runAfter.PSObject.Properties["Resolve_Budget_Goal_From_SA1300_Plan"]
    )
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
  }
}

function Repair-LiveBudgetDefinition {
  param(
    [object]$LiveDefinition,
    [object]$CanonicalDefinition
  )

  $liveHostConnectionMap = Get-HostConnectionMap -Node $LiveDefinition
  $canonicalBudgetRoot = $CanonicalDefinition.actions.Apply_to_each_Attachment.actions.Condition_Is_SA1300_File.actions
  $budgetTargetActionNames = @(
    "Create_Budget_Target_Table",
    "List_Budget_Target_Rows",
    "Filter_Budget_Target_Rows",
    "Resolve_Budget_Goal_From_SA1300_Plan"
  )

  $liveBudgetRoot = $LiveDefinition.actions.Apply_to_each_Attachment.actions.Condition_Is_SA1300_File.actions
  $updatedBudgetRootActions = [ordered]@{}
  foreach ($property in @($liveBudgetRoot.PSObject.Properties)) {
    if ($property.Name -in $budgetTargetActionNames) {
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
      continue
    }

    $updatedBudgetRootActions[$property.Name] = $property.Value
  }

  $LiveDefinition.actions.Apply_to_each_Attachment.actions.Condition_Is_SA1300_File.actions = [pscustomobject]$updatedBudgetRootActions

  if ($LiveDefinition.actions.PSObject.Properties["Terminate_If_No_Budget_Goal"]) {
    $terminateAction = $LiveDefinition.actions.Terminate_If_No_Budget_Goal.actions.Terminate_No_Budget_Goal_Found
    if ($terminateAction -and $terminateAction.inputs -and $terminateAction.inputs.runError) {
      $terminateAction.inputs.runError.message = "No budget target was found from qfu_budgetarchive or the SA1300 Month-End Plan."
    }
  }
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $OutputPath = Join-Path (Join-Path (Get-Location) "results") "sa1300-budget-selfpopulate-live-repair-$stamp.json"
}

if ([string]::IsNullOrWhiteSpace($ProgressPath)) {
  $ProgressPath = [System.IO.Path]::ChangeExtension($OutputPath, ".log")
}

Import-Module Microsoft.PowerApps.PowerShell

Write-ProgressLog -Path $ProgressPath -Message "Starting Add-PowerAppsAccount."
Add-PowerAppsAccount -Endpoint prod -Username $Username | Out-Null
Write-ProgressLog -Path $ProgressPath -Message "Add-PowerAppsAccount complete."

$targetFlows = @($flowCatalog | Where-Object { $_.BranchCode -in $BranchCodes })
$adminFlows = @(Get-Flow -EnvironmentName $TargetEnvironmentName)
$reportRows = New-Object System.Collections.Generic.List[object]

foreach ($targetFlow in $targetFlows) {
  $adminFlow = $null

  try {
    Write-ProgressLog -Path $ProgressPath -Message ("[{0}] Resolving admin flow." -f $targetFlow.BranchCode)
    $adminFlow = $adminFlows | Where-Object { $_.DisplayName -eq $targetFlow.DisplayName } | Select-Object -First 1
    if (-not $adminFlow) {
      throw "Flow not found."
    }

    Write-ProgressLog -Path $ProgressPath -Message ("[{0}] Loading canonical JSON." -f $targetFlow.BranchCode)
    $canonicalPath = Get-CanonicalWorkflowPath -RepoRootPath $RepoRoot -DisplayName $targetFlow.DisplayName -WorkflowId $targetFlow.WorkflowId
    $canonicalJson = Get-Content -LiteralPath $canonicalPath -Raw | ConvertFrom-Json

    $route = "https://{flowEndpoint}/providers/Microsoft.ProcessSimple/environments/{environment}/flows/{flowName}?api-version={apiVersion}" `
      | ReplaceMacro -Macro "{environment}" -Value $TargetEnvironmentName `
      | ReplaceMacro -Macro "{flowName}" -Value $adminFlow.FlowName

    Write-ProgressLog -Path $ProgressPath -Message ("[{0}] Fetching live flow definition." -f $targetFlow.BranchCode)
    $liveFlow = InvokeApi -Method GET -Route $route -ApiVersion "2016-11-01" -Verbose:$false
    $beforeState = Get-Sa1300DefinitionState -Definition $liveFlow.properties.definition

    Write-ProgressLog -Path $ProgressPath -Message ("[{0}] Applying budget self-populate repair." -f $targetFlow.BranchCode)
    Repair-LiveBudgetDefinition -LiveDefinition $liveFlow.properties.definition -CanonicalDefinition $canonicalJson.properties.definition

    $stamp = Get-Date -Format "yyyyMMdd.HHmmss"
    $liveFlow.properties.state = "Started"
    $liveFlow.properties.definition.contentVersion = "1.0.$stamp"

    Write-ProgressLog -Path $ProgressPath -Message ("[{0}] Sending PATCH." -f $targetFlow.BranchCode)
    InvokeApi -Method PATCH -Route $route -Body $liveFlow -ApiVersion "2016-11-01" -ThrowOnFailure -Verbose:$false | Out-Null
    Write-ProgressLog -Path $ProgressPath -Message ("[{0}] PATCH complete." -f $targetFlow.BranchCode)

    if ($RestartAfterPatch) {
      try {
        Disable-Flow -EnvironmentName $TargetEnvironmentName -FlowName $adminFlow.FlowName | Out-Null
        Start-Sleep -Seconds 2
      } catch {
        Write-ProgressLog -Path $ProgressPath -Message ("[{0}] Disable-Flow failed: {1}" -f $targetFlow.BranchCode, $_.Exception.Message)
      }

      Enable-Flow -EnvironmentName $TargetEnvironmentName -FlowName $adminFlow.FlowName | Out-Null
      Start-Sleep -Seconds 3
    }

    Write-ProgressLog -Path $ProgressPath -Message ("[{0}] Fetching repaired flow definition." -f $targetFlow.BranchCode)
    $afterFlow = InvokeApi -Method GET -Route $route -ApiVersion "2016-11-01" -Verbose:$false
    $afterState = Get-Sa1300DefinitionState -Definition $afterFlow.properties.definition

    $reportRows.Add([pscustomobject]@{
      branch_code = $targetFlow.BranchCode
      display_name = $targetFlow.DisplayName
      flow_name = $adminFlow.FlowName
      canonical_path = $canonicalPath
      patched = $true
      restart_after_patch = [bool]$RestartAfterPatch
      before = $beforeState
      after = $afterState
      state_after = [string]$afterFlow.properties.state
      content_version_after = $afterFlow.properties.definition.contentVersion
      last_modified_after = $afterFlow.properties.lastModifiedTime
    }) | Out-Null
  } catch {
    Write-ProgressLog -Path $ProgressPath -Message ("[{0}] Repair failed: {1}" -f $targetFlow.BranchCode, $_.Exception.Message)
    $reportRows.Add([pscustomobject]@{
      branch_code = $targetFlow.BranchCode
      display_name = $targetFlow.DisplayName
      flow_name = if ($adminFlow) { [string]$adminFlow.FlowName } else { $null }
      patched = $false
      error = $_.Exception.Message
    }) | Out-Null
  }
}

$report = [pscustomobject]@{
  captured_at = (Get-Date).ToUniversalTime().ToString("o")
  environment_name = $TargetEnvironmentName
  branch_codes = @($BranchCodes)
  restart_after_patch = [bool]$RestartAfterPatch
  expected_budget_table_expression = $expectedBudgetTableExpression
  expected_budget_target_table_range = $expectedBudgetTargetTableRange
  expected_budget_goal_output_expression = $expectedResolvedBudgetGoalOutputExpression
  rows = @($reportRows.ToArray())
}

Write-ProgressLog -Path $ProgressPath -Message "Writing repair summary."
Write-Utf8Json -Path $OutputPath -Object $report

$report.rows |
  Select-Object branch_code, patched,
    @{ Name = "budget_expr_ok"; Expression = { if ($_.after) { $_.after.budget_table_expression_ok } else { $null } } },
    @{ Name = "target_table_ok"; Expression = { if ($_.after) { $_.after.budget_target_table_range_ok } else { $null } } },
    @{ Name = "goal_expr_ok"; Expression = { if ($_.after) { $_.after.budget_goal_output_expression_ok } else { $null } } },
    state_after, last_modified_after |
  Format-Table -AutoSize

Write-Host "OUTPUT_PATH=$OutputPath"
