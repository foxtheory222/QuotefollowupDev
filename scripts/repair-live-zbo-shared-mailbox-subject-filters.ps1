param(
  [string]$RepoRoot = "C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion",
  [string]$LiveRefreshRoot = "C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\results\live-refresh-20260407-074015",
  [string]$TargetEnvironmentUrl = "https://regionaloperationshub.crm.dynamics.com",
  [string]$Username = "smcfarlane@applied.com",
  [string]$OutputJson = "results\\live-zbo-shared-mailbox-subject-filter-repair.json"
)

$ErrorActionPreference = "Stop"

Import-Module Microsoft.Xrm.Data.Powershell

$flowCatalog = @(
  [pscustomobject]@{ BranchCode = "4171"; DisplayName = "4171-BackOrder-Update-ZBO"; WorkflowId = "94ae1bae-fe22-455e-bf63-24ba92644dc0" },
  [pscustomobject]@{ BranchCode = "4172"; DisplayName = "4172-BackOrder-Update-ZBO"; WorkflowId = "a5a911cc-1d2d-4e5a-b0ab-da6f52def8b0" },
  [pscustomobject]@{ BranchCode = "4173"; DisplayName = "4173-BackOrder-Update-ZBO"; WorkflowId = "3277dd8e-14f6-4e7b-b627-ebc923ba86ef" }
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

function Connect-Org {
  param([string]$Url)

  $conn = Connect-CrmOnline -ServerUrl $Url -ForceOAuth -Username $Username
  if (-not $conn -or -not $conn.IsReady) {
    throw "Dataverse connection failed for $Url : $($conn.LastCrmError)"
  }

  return $conn
}

function Get-CanonicalWorkflowPath {
  param([object]$Flow)

  $relativePath = "{0}-{1}.json" -f $Flow.DisplayName, $Flow.WorkflowId.ToUpperInvariant()
  $path = Join-Path $LiveRefreshRoot ("solutions\\qfu_sapilotflows\\Workflows\\{0}" -f $relativePath)
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Canonical workflow source not found: $path"
  }

  return $path
}

function Touch-WorkflowDefinition {
  param([object]$WorkflowJson)

  $stamp = Get-Date -Format "yyyyMMdd.HHmmss"
  $WorkflowJson.properties.definition.contentVersion = "1.0.$stamp"
}

function Set-BranchSpecificSharedMailboxTrigger {
  param(
    [object]$WorkflowJson,
    [object]$Flow
  )

  $triggerProperty = @($WorkflowJson.properties.definition.triggers.PSObject.Properties | Select-Object -First 1)[0]
  if (-not $triggerProperty) {
    throw "No trigger found in canonical workflow for $($Flow.DisplayName)"
  }

  $trigger = $triggerProperty.Value
  $trigger.type = "OpenApiConnection"
  $trigger.inputs.host.operationId = "SharedMailboxOnNewEmailV2"
  $trigger.inputs.parameters | Add-Member -NotePropertyName "mailboxAddress" -NotePropertyValue "@parameters('qfu_QFU_SharedMailboxAddress')" -Force
  $trigger.inputs.parameters | Add-Member -NotePropertyName "folderId" -NotePropertyValue "@parameters('qfu_QFU_SharedMailboxFolderId')" -Force
  if ($trigger.inputs.parameters.PSObject.Properties["folderPath"]) {
    $trigger.inputs.parameters.PSObject.Properties.Remove("folderPath")
  }
  $trigger.inputs.parameters | Add-Member -NotePropertyName "includeAttachments" -NotePropertyValue $true -Force
  $trigger.inputs.parameters | Add-Member -NotePropertyName "importance" -NotePropertyValue "Any" -Force
  $trigger.inputs.parameters | Add-Member -NotePropertyName "subjectFilter" -NotePropertyValue "Daily Backorder Report $($Flow.BranchCode)" -Force
  if ($trigger.inputs.parameters.PSObject.Properties["fetchOnlyWithAttachment"]) {
    $trigger.inputs.parameters.PSObject.Properties.Remove("fetchOnlyWithAttachment")
  }
  if (-not $trigger.PSObject.Properties["recurrence"]) {
    $trigger | Add-Member -NotePropertyName "recurrence" -NotePropertyValue ([pscustomobject]@{
      interval = 1
      frequency = "Minute"
    }) -Force
  } else {
    $trigger.recurrence.interval = 1
    $trigger.recurrence.frequency = "Minute"
  }

  if ($triggerProperty.Name -ne "Shared_Mailbox_New_Email") {
    $WorkflowJson.properties.definition.triggers = [pscustomobject]([ordered]@{
      Shared_Mailbox_New_Email = $trigger
    })
  }
}

$connection = Connect-Org -Url $TargetEnvironmentUrl
$summary = New-Object System.Collections.Generic.List[object]

foreach ($flow in $flowCatalog) {
  $path = Get-CanonicalWorkflowPath -Flow $flow
  $workflowJson = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
  Set-BranchSpecificSharedMailboxTrigger -WorkflowJson $workflowJson -Flow $flow
  Touch-WorkflowDefinition -WorkflowJson $workflowJson
  $clientData = ConvertTo-JsonCompact -Object $workflowJson

  try {
    Set-CrmRecord -conn $connection -EntityLogicalName workflow -Id $flow.WorkflowId -Fields @{ clientdata = $clientData } | Out-Null
    Set-CrmRecordState -conn $connection -EntityLogicalName workflow -Id $flow.WorkflowId -StateCode Activated -StatusCode Activated | Out-Null
    $after = Get-CrmRecord -conn $connection -EntityLogicalName workflow -Id $flow.WorkflowId -Fields name, statecode, statuscode, modifiedon, clientdata
    $afterJson = $after.clientdata | ConvertFrom-Json
    $afterTrigger = @($afterJson.properties.definition.triggers.PSObject.Properties | Select-Object -First 1)[0].Value

    $summary.Add([pscustomobject]@{
      display_name = $flow.DisplayName
      workflow_id = $flow.WorkflowId
      branch_code = $flow.BranchCode
      patched = $true
      workflow_state = [string]$after.statecode
      workflow_status = [string]$after.statuscode
      modifiedon = [string]$after.modifiedon
      trigger_type = [string]$afterTrigger.type
      operation_id = [string]$afterTrigger.inputs.host.operationId
      subject_filter = [string]$afterTrigger.inputs.parameters.subjectFilter
    }) | Out-Null
  } catch {
    $summary.Add([pscustomobject]@{
      display_name = $flow.DisplayName
      workflow_id = $flow.WorkflowId
      branch_code = $flow.BranchCode
      patched = $false
      error = $_.Exception.Message
    }) | Out-Null
  }
}

$report = [pscustomobject]@{
  captured_at = (Get-Date).ToUniversalTime().ToString("o")
  target_environment_url = $TargetEnvironmentUrl
  live_refresh_root = $LiveRefreshRoot
  flows = @($summary.ToArray())
}

$outputPath = Join-Path $RepoRoot $OutputJson
Write-Utf8Json -Path $outputPath -Object $report

$summary |
  Select-Object display_name, patched, workflow_state, workflow_status, subject_filter, error |
  Format-Table -AutoSize

Write-Host "OUTPUT_PATH=$outputPath"
