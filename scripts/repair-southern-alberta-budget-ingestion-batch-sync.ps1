param(
  [string]$RepoRoot = "C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion",
  [string]$TargetEnvironmentName = "9f2e54c6-c349-e7e1-ac7c-010d3adf3c03",
  [string]$Username = "smcfarlane@applied.com",
  [switch]$RestartAfterPatch = $true,
  [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

$flowCatalog = @(
  [pscustomobject]@{ DisplayName = "4171-Budget-Update-SA1300"; WorkflowId = "6db19ff3-c313-4db6-9a57-f3335fe55558" },
  [pscustomobject]@{ DisplayName = "4172-Budget-Update-SA1300"; WorkflowId = "078cea4c-84f6-4c4f-b73b-62ad838f7cae" },
  [pscustomobject]@{ DisplayName = "4173-Budget-Update-SA1300"; WorkflowId = "3c2ebd80-35d9-4e3c-bdbe-70be98a82ae6" }
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

function Copy-DeepObject {
  param([object]$Source)

  if ($null -eq $Source) {
    return $null
  }

  return ($Source | ConvertTo-Json -Depth 100 | ConvertFrom-Json)
}

function Set-FieldValue {
  param(
    [object]$Map,
    [string]$Name,
    [object]$Value
  )

  if ($Map -is [System.Collections.IDictionary]) {
    $Map[$Name] = $Value
    return
  }

  if ($Map.PSObject.Properties[$Name]) {
    $Map.$Name = $Value
  } else {
    $Map | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
  }
}

Import-Module Microsoft.PowerApps.PowerShell

Add-PowerAppsAccount -Endpoint prod -Username $Username | Out-Null

$liveFlows = @(Get-Flow -EnvironmentName $TargetEnvironmentName)
$reportRows = New-Object System.Collections.Generic.List[object]

foreach ($catalogEntry in $flowCatalog) {
  $result = [ordered]@{
    display_name = $catalogEntry.DisplayName
    workflow_id = $catalogEntry.WorkflowId
    flow_name = $null
    donor_path = $null
    patch = "pending"
    restart = if ($RestartAfterPatch) { "pending" } else { "skipped" }
  }

  try {
    $liveFlow = $liveFlows | Where-Object { $_.DisplayName -eq $catalogEntry.DisplayName } | Select-Object -First 1
    if (-not $liveFlow) {
      throw "Live flow not found."
    }

    $result.flow_name = $liveFlow.FlowName
    $donorPath = Join-Path $RepoRoot ("results\sapilotflows\src\Workflows\{0}-{1}.json" -f $catalogEntry.DisplayName, $catalogEntry.WorkflowId.ToUpperInvariant())
    if (-not (Test-Path -LiteralPath $donorPath)) {
      throw "Donor workflow JSON not found: $donorPath"
    }

    $result.donor_path = $donorPath
    $donor = Get-Content -LiteralPath $donorPath -Raw | ConvertFrom-Json
    $donorActions = $donor.properties.definition.actions.Apply_to_each_Attachment.actions.Condition_Is_SA1300_File.actions

    $route = "https://{flowEndpoint}/providers/Microsoft.ProcessSimple/environments/{environment}/flows/{flowName}?api-version={apiVersion}" `
      | ReplaceMacro -Macro "{environment}" -Value $TargetEnvironmentName `
      | ReplaceMacro -Macro "{flowName}" -Value $liveFlow.FlowName

    $flow = InvokeApi -Method GET -Route $route -ApiVersion "2016-11-01" -Verbose:$false
    $liveActions = $flow.properties.definition.actions.Apply_to_each_Attachment.actions.Condition_Is_SA1300_File.actions
    $connectionName = [string]$liveActions.Create_Abnormal_Margin_Batch.inputs.host.connectionName

    $listAction = Copy-DeepObject $donorActions.List_Existing_Budget_Import_Batch
    $conditionAction = Copy-DeepObject $donorActions.Condition_Budget_Import_Batch_Exists

    $listAction.inputs.host.connectionName = $connectionName
    $conditionAction.actions.Update_Budget_Import_Batch.inputs.host.connectionName = $connectionName
    $conditionAction.else.actions.Create_Budget_Import_Batch.inputs.host.connectionName = $connectionName

    Set-FieldValue -Map $liveActions -Name "List_Existing_Budget_Import_Batch" -Value $listAction
    Set-FieldValue -Map $liveActions -Name "Condition_Budget_Import_Batch_Exists" -Value $conditionAction

    $flow.properties.state = "Started"
    $flow.properties.definition.contentVersion = "1.0.{0}" -f (Get-Date -Format "yyyyMMddHHmmss")

    InvokeApi -Method PATCH -Route $route -Body $flow -ApiVersion "2016-11-01" -ThrowOnFailure -Verbose:$false | Out-Null
    $result.patch = "patched"

    if ($RestartAfterPatch) {
      try {
        Disable-Flow -EnvironmentName $TargetEnvironmentName -FlowName $liveFlow.FlowName | Out-Null
        Start-Sleep -Seconds 2
      } catch {
      }

      Enable-Flow -EnvironmentName $TargetEnvironmentName -FlowName $liveFlow.FlowName | Out-Null
      $result.restart = "restarted"
    }

    $after = InvokeApi -Method GET -Route $route -ApiVersion "2016-11-01" -Verbose:$false
    $result.last_modified_time = $after.properties.lastModifiedTime
    $result.content_version = $after.properties.definition.contentVersion
  } catch {
    $result.patch = "failed"
    $result.restart = if ($RestartAfterPatch) { "failed" } else { "skipped" }
    $result.error = $_.Exception.Message
  }

  $reportRows.Add([pscustomobject]$result) | Out-Null
}

$report = [pscustomobject]@{
  captured_at = (Get-Date).ToUniversalTime().ToString("o")
  environment_name = $TargetEnvironmentName
  restart_after_patch = [bool]$RestartAfterPatch
  rows = @($reportRows.ToArray())
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $OutputPath = Join-Path (Join-Path (Get-Location) "results") "southern-alberta-budget-ingestion-batch-sync-$stamp.json"
}

Write-Utf8Json -Path $OutputPath -Object $report

$report.rows |
  Select-Object display_name, patch, restart, last_modified_time |
  Format-Table -AutoSize

Write-Host "OUTPUT_PATH=$OutputPath"
