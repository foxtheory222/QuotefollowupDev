param(
  [string]$TargetEnvironmentName = "<GUID>",
  [string]$Username = "<EMAIL>",
  [string[]]$BranchCodes = @("4171", "4172", "4173"),
  [switch]$RestartAfterPatch = $true,
  [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

$flowCatalog = @(
  [pscustomobject]@{ BranchCode = "4171"; DisplayName = "4171-BackOrder-Update-ZBO-Live" },
  [pscustomobject]@{ BranchCode = "4172"; DisplayName = "4172-BackOrder-Update-ZBO-Live" },
  [pscustomobject]@{ BranchCode = "4173"; DisplayName = "4173-BackOrder-Update-ZBO-Live" }
)

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

function ConvertTo-JsonCompact {
  param([object]$Object)

  return ($Object | ConvertTo-Json -Depth 100 -Compress)
}

function Set-OrderedRunAfter {
  param([object]$ActionNode)

  $ActionNode.runAfter = [pscustomobject]([ordered]@{
      Condition_Has_New_Rows            = @("Succeeded", "Skipped")
      Deactivate_Missing_DeliveryNotPgi = @("Succeeded", "Skipped")
    })
}

function Get-BackorderActionScope {
  param([object]$Definition)

  $conditionActions = $Definition.actions.Apply_to_each_Attachment.actions.Condition_Is_CA_ZBO_File.actions
  if (-not $conditionActions) {
    throw "Backorder attachment condition actions were not found."
  }

  $guardScope = $conditionActions.PSObject.Properties["Guard_BackOrder_Row_Limit"]
  if ($guardScope -and $conditionActions.Guard_BackOrder_Row_Limit -and $conditionActions.Guard_BackOrder_Row_Limit.actions) {
    return $conditionActions.Guard_BackOrder_Row_Limit.actions
  }

  return $conditionActions
}

function Get-ZboBatchSyncState {
  param([object]$Definition)

  $actions = Get-BackorderActionScope -Definition $Definition
  return [pscustomobject]@{
    list_runafter = if ($actions.PSObject.Properties["List_Existing_Backorder_Import_Batch"]) { $actions.List_Existing_Backorder_Import_Batch.runAfter } else { $null }
    update_triggerflow = if ($actions.PSObject.Properties["Condition_Backorder_Import_Batch_Exists"]) { [string]$actions.Condition_Backorder_Import_Batch_Exists.actions.Update_Backorder_Import_Batch.inputs.parameters."item/qfu_triggerflow" } else { $null }
    create_triggerflow = if ($actions.PSObject.Properties["Condition_Backorder_Import_Batch_Exists"]) { [string]$actions.Condition_Backorder_Import_Batch_Exists.else.actions.Create_Backorder_Import_Batch.inputs.parameters."item/qfu_triggerflow" } else { $null }
  }
}

function Repair-ZboBatchSync {
  param(
    [object]$Definition,
    [string]$BranchCode
  )

  $actions = Get-BackorderActionScope -Definition $Definition

  if (-not $actions.PSObject.Properties["List_Existing_Backorder_Import_Batch"]) {
    throw "List_Existing_Backorder_Import_Batch action was not found."
  }

  if (-not $actions.PSObject.Properties["Condition_Backorder_Import_Batch_Exists"]) {
    throw "Condition_Backorder_Import_Batch_Exists action was not found."
  }

  $expectedTriggerFlow = "@concat(parameters('qfu_QFU_BranchCode'), '-BackOrder-Update-ZBO-Live-R2')"
  Set-OrderedRunAfter -ActionNode $actions.List_Existing_Backorder_Import_Batch
  $actions.Condition_Backorder_Import_Batch_Exists.actions.Update_Backorder_Import_Batch.inputs.parameters."item/qfu_triggerflow" = $expectedTriggerFlow
  $actions.Condition_Backorder_Import_Batch_Exists.else.actions.Create_Backorder_Import_Batch.inputs.parameters."item/qfu_triggerflow" = $expectedTriggerFlow

  return [pscustomobject]@{
    branch_code = $BranchCode
    expected_triggerflow = $expectedTriggerFlow
  }
}

function Connect-Org {
  param([string]$Url)

  Import-Module Microsoft.Xrm.Data.Powershell

  $connection = Connect-CrmOnline -ServerUrl $Url -ForceOAuth -Username $Username
  if (-not $connection -or -not $connection.IsReady) {
    throw "Dataverse connection failed for $Url : $($connection.LastCrmError)"
  }

  return $connection
}

$targetFlows = @($flowCatalog | Where-Object { $_.BranchCode -in $BranchCodes })
$connection = Connect-Org -Url "<URL>
$reportRows = New-Object System.Collections.Generic.List[object]

foreach ($targetFlow in $targetFlows) {
  try {
    $workflowRecord = @(
      (Get-CrmRecords -conn $connection -EntityLogicalName workflow -FilterAttribute name -FilterOperator eq -FilterValue $targetFlow.DisplayName -Fields workflowid, name, clientdata, modifiedon -TopCount 5).CrmRecords |
        Sort-Object @{ Expression = { if ($_.modifiedon) { [datetime]$_.modifiedon } else { [datetime]::MinValue } }; Descending = $true }
    ) | Select-Object -First 1
    if (-not $workflowRecord -or -not $workflowRecord.workflowid) {
      throw "Flow workflow record not found."
    }

    $flow = $workflowRecord.clientdata | ConvertFrom-Json
    $before = Get-ZboBatchSyncState -Definition $flow.properties.definition
    $repairState = Repair-ZboBatchSync -Definition $flow.properties.definition -BranchCode $targetFlow.BranchCode
    $flow.properties.definition.contentVersion = "1.0.{0}" -f (Get-Date -Format "yyyyMMddHHmmss")
    Set-CrmRecord -conn $connection -EntityLogicalName workflow -Id $workflowRecord.workflowid -Fields @{ clientdata = (ConvertTo-JsonCompact -Object $flow) } | Out-Null
    if ($RestartAfterPatch) {
      Set-CrmRecordState -conn $connection -EntityLogicalName workflow -Id $workflowRecord.workflowid -StateCode Activated -StatusCode Activated | Out-Null
    }

    $afterWorkflow = Get-CrmRecord -conn $connection -EntityLogicalName workflow -Id $workflowRecord.workflowid -Fields workflowid, name, clientdata, modifiedon, statecode, statuscode
    $afterFlow = $afterWorkflow.clientdata | ConvertFrom-Json
    $after = Get-ZboBatchSyncState -Definition $afterFlow.properties.definition

    $reportRows.Add([pscustomobject]@{
      display_name = $targetFlow.DisplayName
      branch_code = $targetFlow.BranchCode
      workflow_id = [string]$workflowRecord.workflowid
      workflow_name = [string]$afterWorkflow.name
      repair_state = $repairState
      before = $before
      after = $after
      content_version_after = $afterFlow.properties.definition.contentVersion
      restart_after_patch = [bool]$RestartAfterPatch
      state_after = [string]$afterWorkflow.statecode
      status_after = [string]$afterWorkflow.statuscode
      last_modified_after = if ($afterWorkflow.modifiedon) { ([datetime]$afterWorkflow.modifiedon).ToString("o") } else { $null }
    }) | Out-Null
  } catch {
    $reportRows.Add([pscustomobject]@{
      display_name = $targetFlow.DisplayName
      branch_code = $targetFlow.BranchCode
      workflow_id = if ($workflowRecord) { [string]$workflowRecord.workflowid } else { $null }
      error = $_.Exception.Message
    }) | Out-Null
  }
}

$report = [pscustomobject]@{
  captured_at = (Get-Date).ToUniversalTime().ToString("o")
  environment_name = $TargetEnvironmentName
  branch_codes = @($BranchCodes)
  restart_after_patch = [bool]$RestartAfterPatch
  rows = @($reportRows.ToArray())
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $OutputPath = Join-Path (Join-Path (Get-Location) "results") "live-zbo-ingestion-batch-sync-repair-$stamp.json"
}

Write-Utf8Json -Path $OutputPath -Object $report

$report.rows |
  Select-Object display_name, @{Name = "after_trigger"; Expression = { if ($_.after) { $_.after.update_triggerflow } else { $null } } }, state_after, last_modified_after, error |
  Format-Table -AutoSize

Write-Host "OUTPUT_PATH=$OutputPath"
