param(
  [string]$RepoRoot = "C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion",
  [string]$TargetEnvironmentUrl = "<URL>
  [string]$Username = "<EMAIL>",
  [string[]]$BranchCodes = @("4171", "4172", "4173"),
  [string]$OutputPath = "",
  [string]$ArtifactRoot = ""
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "shared-mailbox-routing.ps1")

$flowCatalog = @(
  [pscustomobject]@{
    BranchCode = "4171"
    DisplayName = "4171-GL060-Inbox-Ingress"
    WorkflowId = "<GUID>"
  },
  [pscustomobject]@{
    BranchCode = "4172"
    DisplayName = "4172-GL060-Inbox-Ingress"
    WorkflowId = "<GUID>"
  },
  [pscustomobject]@{
    BranchCode = "4173"
    DisplayName = "4173-GL060-Inbox-Ingress"
    WorkflowId = "<GUID>"
  }
)

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

  $json = $Object | ConvertTo-Json -Depth 100
  [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function ConvertTo-JsonCompact {
  param([object]$Object)

  return ($Object | ConvertTo-Json -Depth 100 -Compress)
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

function Remove-ObjectProperty {
  param(
    [object]$Object,
    [string]$Name
  )

  if ($null -eq $Object) {
    return
  }

  if ($Object -is [System.Collections.IDictionary]) {
    if ($Object.Contains($Name)) {
      $Object.Remove($Name)
    }
    return
  }

  if ($Object.PSObject.Properties[$Name]) {
    $Object.PSObject.Properties.Remove($Name)
  }
}

function Touch-WorkflowDefinition {
  param([object]$WorkflowJson)

  $stamp = Get-Date -Format "yyyyMMdd.HHmmss"
  $WorkflowJson.properties.definition.contentVersion = "1.0.$stamp"
}

function Connect-Org {
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

function Resolve-WorkflowRecord {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [object]$Flow
  )

  $fields = @("name", "workflowid", "statecode", "statuscode", "modifiedon", "clientdata")

  $byId = $null
  try {
    $byId = Get-CrmRecord -conn $Connection -EntityLogicalName workflow -Id $Flow.WorkflowId -Fields $fields
  } catch {
  }

  if ($byId -and [string]$byId.name -eq $Flow.DisplayName) {
    return $byId
  }

  $byName = @(
    (Get-CrmRecords -conn $Connection -EntityLogicalName workflow -FilterAttribute "name" -FilterOperator eq -FilterValue $Flow.DisplayName -Fields $fields -TopCount 10).CrmRecords |
      Sort-Object { if ($_.modifiedon) { [datetime]$_.modifiedon } else { [datetime]::MinValue } } -Descending
  ) | Select-Object -First 1

  if ($byName) {
    return $byName
  }

  throw "Workflow not found for $($Flow.DisplayName)"
}

function Get-TriggerProperty {
  param([object]$Definition)

  return @($Definition.triggers.PSObject.Properties | Select-Object -First 1)[0]
}

function Get-FlowStateSummary {
  param(
    [object]$WorkflowRecord,
    [object]$WorkflowJson
  )

  $triggerProperty = Get-TriggerProperty -Definition $WorkflowJson.properties.definition
  if (-not $triggerProperty) {
    throw "No trigger found in $($WorkflowRecord.name)"
  }

  $trigger = $triggerProperty.Value
  $definition = $WorkflowJson.properties.definition
  $gl060Actions = $definition.actions.Apply_to_each_GL060_Attachment.actions
  $rawParameters = $gl060Actions.Create_Raw_Document.inputs.parameters
  $batchParameters = $gl060Actions.Create_Ingestion_Batch.inputs.parameters

  return [pscustomobject]@{
    workflow_name = [string]$WorkflowRecord.name
    workflow_id = [string]$WorkflowRecord.workflowid
    workflow_state = [string]$WorkflowRecord.statecode
    workflow_status = [string]$WorkflowRecord.statuscode
    workflow_modifiedon = [string]$WorkflowRecord.modifiedon
    trigger_name = [string]$triggerProperty.Name
    trigger_type = [string]$trigger.type
    operation_id = [string]$trigger.inputs.host.operationId
    subject_filter = if ($trigger.inputs.parameters.PSObject.Properties["subjectFilter"]) { [string]$trigger.inputs.parameters.subjectFilter } else { $null }
    has_attachments = if ($trigger.inputs.parameters.PSObject.Properties["hasAttachments"]) { [bool]$trigger.inputs.parameters.hasAttachments } else { $null }
    include_attachments = if ($trigger.inputs.parameters.PSObject.Properties["includeAttachments"]) { [bool]$trigger.inputs.parameters.includeAttachments } else { $null }
    mailbox_address = if ($definition.parameters.PSObject.Properties["qfu_QFU_SharedMailboxAddress"]) { [string]$definition.parameters.qfu_QFU_SharedMailboxAddress.defaultValue } else { $null }
    folder_id = if ($definition.parameters.PSObject.Properties["qfu_QFU_SharedMailboxFolderId"]) { [string]$definition.parameters.qfu_QFU_SharedMailboxFolderId.defaultValue } else { $null }
    recurrence_interval = if ($trigger.PSObject.Properties["recurrence"]) { [int]$trigger.recurrence.interval } else { $null }
    recurrence_frequency = if ($trigger.PSObject.Properties["recurrence"]) { [string]$trigger.recurrence.frequency } else { $null }
    split_on = if ($trigger.PSObject.Properties["splitOn"]) { [string]$trigger.splitOn } else { $null }
    raw_received_on = [string]$rawParameters."item/qfu_receivedon"
    raw_content_base64 = [string]$rawParameters."item/qfu_rawcontentbase64"
    raw_processing_notes = [string]$rawParameters."item/qfu_processingnotes"
    batch_started_on = [string]$batchParameters."item/qfu_startedon"
    batch_notes = [string]$batchParameters."item/qfu_notes"
    content_version = [string]$definition.contentVersion
  }
}

function Repair-Gl060WorkflowJson {
  param(
    [object]$WorkflowJson,
    [string]$BranchCode,
    [string]$DisplayName
  )

  $state = [ordered]@{
    trigger_fixed = $false
    mailbox_route_fixed = $false
    audit_fields_fixed = $false
  }

  $route = Get-SouthernAlbertaSharedMailboxRoute -BranchCode $BranchCode -MailboxAddress ("{0}@applied.com" -f $BranchCode)
  $definition = $WorkflowJson.properties.definition
  $triggerProperty = Get-TriggerProperty -Definition $definition
  if (-not $triggerProperty) {
    throw "No trigger found in $DisplayName"
  }

  $trigger = $triggerProperty.Value
  $expectedReceivedOn = "@coalesce(triggerOutputs()?['body/receivedDateTime'], utcNow())"
  $expectedRawContent = "@base64(base64ToBinary(items('Apply_to_each_GL060_Attachment')?['contentBytes']))"
  $expectedProcessingNotes = "@concat('Queued from the configured shared mailbox folder by GL060 ingress flow. Subject=', coalesce(triggerOutputs()?['body/subject'], ''), '; InternetMessageId=', coalesce(triggerOutputs()?['body/internetMessageId'], ''), '; ReceivedDateTime=', string(coalesce(triggerOutputs()?['body/receivedDateTime'], utcNow())))"
  $expectedBatchNotes = "@concat('Queued from the configured shared mailbox folder. Subject=', coalesce(triggerOutputs()?['body/subject'], ''), '; InternetMessageId=', coalesce(triggerOutputs()?['body/internetMessageId'], ''), '; ReceivedDateTime=', string(coalesce(triggerOutputs()?['body/receivedDateTime'], utcNow())), '. Awaiting downstream GL060 processing.')"

  if ([string]$trigger.type -ne "OpenApiConnection") {
    $trigger.type = "OpenApiConnection"
    $state.trigger_fixed = $true
  }

  if ([string]$trigger.inputs.host.operationId -ne "SharedMailboxOnNewEmailV2") {
    $trigger.inputs.host.operationId = "SharedMailboxOnNewEmailV2"
    $state.trigger_fixed = $true
  }

  if (-not $trigger.inputs.PSObject.Properties["parameters"] -or -not $trigger.inputs.parameters) {
    $trigger.inputs | Add-Member -NotePropertyName "parameters" -NotePropertyValue ([pscustomobject]@{}) -Force
    $state.trigger_fixed = $true
  }

  $parameters = $trigger.inputs.parameters
  if ([string]$parameters.mailboxAddress -ne "@parameters('qfu_QFU_SharedMailboxAddress')") {
    Set-ObjectProperty -Object $parameters -Name "mailboxAddress" -Value "@parameters('qfu_QFU_SharedMailboxAddress')"
    $state.trigger_fixed = $true
  }
  if ([string]$parameters.folderId -ne "@parameters('qfu_QFU_SharedMailboxFolderId')") {
    Set-ObjectProperty -Object $parameters -Name "folderId" -Value "@parameters('qfu_QFU_SharedMailboxFolderId')"
    $state.trigger_fixed = $true
  }
  if (-not $parameters.PSObject.Properties["hasAttachments"] -or [bool]$parameters.hasAttachments -ne $true) {
    Set-ObjectProperty -Object $parameters -Name "hasAttachments" -Value $true
    $state.trigger_fixed = $true
  }
  if (-not $parameters.PSObject.Properties["includeAttachments"] -or [bool]$parameters.includeAttachments -ne $true) {
    Set-ObjectProperty -Object $parameters -Name "includeAttachments" -Value $true
    $state.trigger_fixed = $true
  }
  if ([string]$parameters.importance -ne "Any") {
    Set-ObjectProperty -Object $parameters -Name "importance" -Value "Any"
    $state.trigger_fixed = $true
  }
  if ([string]$parameters.subjectFilter -ne "GL060 P&L report") {
    Set-ObjectProperty -Object $parameters -Name "subjectFilter" -Value "GL060 P&L report"
    $state.trigger_fixed = $true
  }
  if ($parameters.PSObject.Properties["folderPath"]) {
    Remove-ObjectProperty -Object $parameters -Name "folderPath"
    $state.trigger_fixed = $true
  }
  if ($parameters.PSObject.Properties["fetchOnlyWithAttachment"]) {
    Remove-ObjectProperty -Object $parameters -Name "fetchOnlyWithAttachment"
    $state.trigger_fixed = $true
  }

  $expectedSplitOn = "@triggerOutputs()?['body/value']"
  if (-not $trigger.PSObject.Properties["splitOn"] -or [string]$trigger.splitOn -ne $expectedSplitOn) {
    Set-ObjectProperty -Object $trigger -Name "splitOn" -Value $expectedSplitOn
    $state.trigger_fixed = $true
  }

  $hasExpectedRecurrence = $false
  if ($trigger.PSObject.Properties["recurrence"]) {
    $hasExpectedRecurrence = (
      [int]$trigger.recurrence.interval -eq 1 -and
      [string]$trigger.recurrence.frequency -eq "Minute"
    )
  }
  if (-not $hasExpectedRecurrence) {
    Set-ObjectProperty -Object $trigger -Name "recurrence" -Value ([pscustomobject]@{
        interval = 1
        frequency = "Minute"
      })
    $state.trigger_fixed = $true
  }

  if ($definition.parameters.PSObject.Properties["qfu_QFU_SharedMailboxAddress"]) {
    if ([string]$definition.parameters.qfu_QFU_SharedMailboxAddress.defaultValue -ne $route.MailboxAddress) {
      $definition.parameters.qfu_QFU_SharedMailboxAddress.defaultValue = $route.MailboxAddress
      $state.mailbox_route_fixed = $true
    }
  }
  if ($definition.parameters.PSObject.Properties["qfu_QFU_SharedMailboxFolderId"]) {
    if ([string]$definition.parameters.qfu_QFU_SharedMailboxFolderId.defaultValue -ne $route.FolderId) {
      $definition.parameters.qfu_QFU_SharedMailboxFolderId.defaultValue = $route.FolderId
      $state.mailbox_route_fixed = $true
    }
  }

  $gl060Actions = $definition.actions.Apply_to_each_GL060_Attachment.actions
  if (-not $gl060Actions) {
    throw "GL060 attachment loop not found in $DisplayName"
  }

  $rawParameters = $gl060Actions.Create_Raw_Document.inputs.parameters
  $batchParameters = $gl060Actions.Create_Ingestion_Batch.inputs.parameters

  if ([string]$rawParameters."item/qfu_receivedon" -ne $expectedReceivedOn) {
    Set-ObjectProperty -Object $rawParameters -Name "item/qfu_receivedon" -Value $expectedReceivedOn
    $state.audit_fields_fixed = $true
  }
  if ([string]$rawParameters."item/qfu_rawcontentbase64" -ne $expectedRawContent) {
    Set-ObjectProperty -Object $rawParameters -Name "item/qfu_rawcontentbase64" -Value $expectedRawContent
    $state.audit_fields_fixed = $true
  }
  if ([string]$rawParameters."item/qfu_processingnotes" -ne $expectedProcessingNotes) {
    Set-ObjectProperty -Object $rawParameters -Name "item/qfu_processingnotes" -Value $expectedProcessingNotes
    $state.audit_fields_fixed = $true
  }
  if ([string]$batchParameters."item/qfu_startedon" -ne $expectedReceivedOn) {
    Set-ObjectProperty -Object $batchParameters -Name "item/qfu_startedon" -Value $expectedReceivedOn
    $state.audit_fields_fixed = $true
  }
  if ([string]$batchParameters."item/qfu_notes" -ne $expectedBatchNotes) {
    Set-ObjectProperty -Object $batchParameters -Name "item/qfu_notes" -Value $expectedBatchNotes
    $state.audit_fields_fixed = $true
  }

  Touch-WorkflowDefinition -WorkflowJson $WorkflowJson
  return [pscustomobject]$state
}

$selectedFlows = @($flowCatalog | Where-Object { $_.BranchCode -in $BranchCodes })
if (-not $selectedFlows) {
  throw "No GL060 flows matched the requested branch codes."
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $RepoRoot "results\gl060-live-mailbox-ingress-xrm-repair-$stamp.json"
}
if ([string]::IsNullOrWhiteSpace($ArtifactRoot)) {
  $ArtifactRoot = Join-Path $RepoRoot "results\gl060-live-mailbox-ingress-xrm-repair-$stamp"
}
Ensure-Directory -Path $ArtifactRoot

$connection = Connect-Org -Url $TargetEnvironmentUrl -User $Username
$rows = New-Object System.Collections.Generic.List[object]

foreach ($flow in $selectedFlows) {
  try {
    $workflowRecord = Resolve-WorkflowRecord -Connection $connection -Flow $flow
    if (-not $workflowRecord.clientdata) {
      throw "Workflow $($flow.DisplayName) does not have clientdata."
    }

    $beforeJson = $workflowRecord.clientdata | ConvertFrom-Json
    $beforeSummary = Get-FlowStateSummary -WorkflowRecord $workflowRecord -WorkflowJson $beforeJson
    Write-Utf8Json -Path (Join-Path $ArtifactRoot ("{0}-before.json" -f $flow.DisplayName)) -Object $beforeJson

    $repairState = Repair-Gl060WorkflowJson -WorkflowJson $beforeJson -BranchCode $flow.BranchCode -DisplayName $flow.DisplayName
    $clientData = ConvertTo-JsonCompact -Object $beforeJson
    Set-CrmRecord -conn $connection -EntityLogicalName workflow -Id $workflowRecord.workflowid -Fields @{ clientdata = $clientData } | Out-Null
    Set-CrmRecordState -conn $connection -EntityLogicalName workflow -Id $workflowRecord.workflowid -StateCode Activated -StatusCode Activated | Out-Null

    $afterRecord = Get-CrmRecord -conn $connection -EntityLogicalName workflow -Id $workflowRecord.workflowid -Fields name,workflowid,statecode,statuscode,modifiedon,clientdata
    $afterJson = $afterRecord.clientdata | ConvertFrom-Json
    $afterSummary = Get-FlowStateSummary -WorkflowRecord $afterRecord -WorkflowJson $afterJson
    Write-Utf8Json -Path (Join-Path $ArtifactRoot ("{0}-after.json" -f $flow.DisplayName)) -Object $afterJson

    $rows.Add([pscustomobject]@{
        branch_code = $flow.BranchCode
        display_name = $flow.DisplayName
        workflow_id = [string]$workflowRecord.workflowid
        patched = $true
        trigger_fixed = [bool]$repairState.trigger_fixed
        mailbox_route_fixed = [bool]$repairState.mailbox_route_fixed
        audit_fields_fixed = [bool]$repairState.audit_fields_fixed
        before = $beforeSummary
        after = $afterSummary
      }) | Out-Null
  } catch {
    $rows.Add([pscustomobject]@{
        branch_code = $flow.BranchCode
        display_name = $flow.DisplayName
        workflow_id = $flow.WorkflowId
        patched = $false
        error = $_.Exception.Message
      }) | Out-Null
  }
}

$report = [pscustomobject]@{
  captured_at = (Get-Date).ToUniversalTime().ToString("o")
  target_environment_url = $TargetEnvironmentUrl
  branch_codes = @($BranchCodes)
  artifact_root = $ArtifactRoot
  rows = @($rows.ToArray())
}

Write-Utf8Json -Path $OutputPath -Object $report

$report.rows |
  Select-Object display_name, patched, trigger_fixed, mailbox_route_fixed, audit_fields_fixed, @{n="subject_after";e={$_.after.subject_filter}}, @{n="has_attach_after";e={$_.after.has_attachments}}, @{n="include_attach_after";e={$_.after.include_attachments}}, @{n="receivedon_after";e={$_.after.raw_received_on}} |
  Format-Table -AutoSize

Write-Host "OUTPUT_PATH=$OutputPath"
Write-Host "ARTIFACT_ROOT=$ArtifactRoot"
