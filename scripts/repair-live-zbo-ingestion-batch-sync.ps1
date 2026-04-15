param(
  [string]$TargetEnvironmentName = "9f2e54c6-c349-e7e1-ac7c-010d3adf3c03",
  [string]$Username = "smcfarlane@applied.com",
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
      Deactivate_Missing_BackOrders     = @("Succeeded", "Skipped")
      Deactivate_Missing_DeliveryNotPgi = @("Succeeded", "Skipped")
    })
}

function Get-ZboBatchSyncState {
  param([object]$Definition)

  $actions = $Definition.actions.Apply_to_each_Attachment.actions.Condition_Is_CA_ZBO_File.actions
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

  $actions = $Definition.actions.Apply_to_each_Attachment.actions.Condition_Is_CA_ZBO_File.actions
  if (-not $actions) {
    throw "Backorder attachment condition was not found."
  }

  if (-not $actions.PSObject.Properties["List_Existing_Backorder_Import_Batch"]) {
    throw "List_Existing_Backorder_Import_Batch action was not found."
  }

  if (-not $actions.PSObject.Properties["Condition_Backorder_Import_Batch_Exists"]) {
    throw "Condition_Backorder_Import_Batch_Exists action was not found."
  }

  $expectedTriggerFlow = "@concat(parameters('qfu_QFU_BranchCode'), '-BackOrder-Update-ZBO-Live')"
  Set-OrderedRunAfter -ActionNode $actions.List_Existing_Backorder_Import_Batch
  $actions.Condition_Backorder_Import_Batch_Exists.actions.Update_Backorder_Import_Batch.inputs.parameters."item/qfu_triggerflow" = $expectedTriggerFlow
  $actions.Condition_Backorder_Import_Batch_Exists.else.actions.Create_Backorder_Import_Batch.inputs.parameters."item/qfu_triggerflow" = $expectedTriggerFlow

  return [pscustomobject]@{
    branch_code = $BranchCode
    expected_triggerflow = $expectedTriggerFlow
  }
}

Import-Module Microsoft.PowerApps.PowerShell

Add-PowerAppsAccount -Endpoint prod -Username $Username | Out-Null

$targetFlows = @($flowCatalog | Where-Object { $_.BranchCode -in $BranchCodes })
$adminFlows = @(Get-Flow -EnvironmentName $TargetEnvironmentName)
$reportRows = New-Object System.Collections.Generic.List[object]

foreach ($targetFlow in $targetFlows) {
  try {
    $adminFlow = $adminFlows | Where-Object { $_.DisplayName -eq $targetFlow.DisplayName } | Select-Object -First 1
    if (-not $adminFlow) {
      throw "Flow not found."
    }

    $route = "https://{flowEndpoint}/providers/Microsoft.ProcessSimple/environments/{environment}/flows/{flowName}?api-version={apiVersion}" `
      | ReplaceMacro -Macro "{environment}" -Value $TargetEnvironmentName `
      | ReplaceMacro -Macro "{flowName}" -Value $adminFlow.FlowName

    $flow = InvokeApi -Method GET -Route $route -ApiVersion "2016-11-01" -Verbose:$false
    $before = Get-ZboBatchSyncState -Definition $flow.properties.definition
    $repairState = Repair-ZboBatchSync -Definition $flow.properties.definition -BranchCode $targetFlow.BranchCode
    $flow.properties.state = "Started"
    $flow.properties.definition.contentVersion = "1.0.{0}" -f (Get-Date -Format "yyyyMMddHHmmss")

    InvokeApi -Method PATCH -Route $route -Body $flow -ApiVersion "2016-11-01" -ThrowOnFailure -Verbose:$false | Out-Null

    if ($RestartAfterPatch) {
      try {
        Disable-Flow -EnvironmentName $TargetEnvironmentName -FlowName $adminFlow.FlowName | Out-Null
        Start-Sleep -Seconds 2
      } catch {
      }

      Enable-Flow -EnvironmentName $TargetEnvironmentName -FlowName $adminFlow.FlowName | Out-Null
      Start-Sleep -Seconds 2
    }

    $afterFlow = InvokeApi -Method GET -Route $route -ApiVersion "2016-11-01" -Verbose:$false
    $after = Get-ZboBatchSyncState -Definition $afterFlow.properties.definition

    $reportRows.Add([pscustomobject]@{
      display_name = $targetFlow.DisplayName
      branch_code = $targetFlow.BranchCode
      flow_name = $adminFlow.FlowName
      repair_state = $repairState
      before = $before
      after = $after
      state_after = [string]$afterFlow.properties.state
      content_version_after = $afterFlow.properties.definition.contentVersion
      last_modified_after = $afterFlow.properties.lastModifiedTime
    }) | Out-Null
  } catch {
    $reportRows.Add([pscustomobject]@{
      display_name = $targetFlow.DisplayName
      branch_code = $targetFlow.BranchCode
      flow_name = if ($adminFlow) { $adminFlow.FlowName } else { $null }
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
