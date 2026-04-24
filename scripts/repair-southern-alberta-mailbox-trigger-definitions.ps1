param(
  [string]$TargetEnvironmentName = "9f2e54c6-c349-e7e1-ac7c-010d3adf3c03",
  [string]$Username = "smcfarlane@applied.com",
  [string[]]$BranchCodes = @("4171", "4172", "4173"),
  [string[]]$SourceFamilies = @("SP830CA", "ZBO", "SA1300", "GL060", "FREIGHT"),
  [switch]$RestartAfterPatch = $true,
  [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "shared-mailbox-routing.ps1")

$flowCatalog = @(
  [pscustomobject]@{ BranchCode = "4171"; SourceFamily = "SP830CA"; DisplayName = "4171-QuoteFollowUp-Import-Staging"; DisplayNamePattern = "4171-QuoteFollowUp-Import-Staging"; TriggerKind = "SharedMailbox" },
  [pscustomobject]@{ BranchCode = "4171"; SourceFamily = "ZBO"; DisplayName = "4171-BackOrder-Update-ZBO-Live"; DisplayNamePattern = "4171-BackOrder-Update-ZBO-Live"; TriggerKind = "SharedMailbox" },
  [pscustomobject]@{ BranchCode = "4171"; SourceFamily = "SA1300"; DisplayName = "4171-Budget-Update-SA1300"; DisplayNamePattern = "4171-Budget-Update-SA1300*"; TriggerKind = "SharedMailbox" },
  [pscustomobject]@{ BranchCode = "4171"; SourceFamily = "GL060"; DisplayName = "4171-GL060-Inbox-Ingress"; DisplayNamePattern = "4171-GL060-Inbox-Ingress"; TriggerKind = "SharedMailbox" },
  [pscustomobject]@{ BranchCode = "4171"; SourceFamily = "FREIGHT"; DisplayName = "4171-Freight-Inbox-Ingress"; DisplayNamePattern = "4171-Freight-Inbox-Ingress"; TriggerKind = "SharedMailbox" },
  [pscustomobject]@{ BranchCode = "4172"; SourceFamily = "SP830CA"; DisplayName = "4172-QuoteFollowUp-Import-Staging"; DisplayNamePattern = "4172-QuoteFollowUp-Import-Staging"; TriggerKind = "SharedMailbox" },
  [pscustomobject]@{ BranchCode = "4172"; SourceFamily = "ZBO"; DisplayName = "4172-BackOrder-Update-ZBO-Live"; DisplayNamePattern = "4172-BackOrder-Update-ZBO-Live"; TriggerKind = "SharedMailbox" },
  [pscustomobject]@{ BranchCode = "4172"; SourceFamily = "SA1300"; DisplayName = "4172-Budget-Update-SA1300"; DisplayNamePattern = "4172-Budget-Update-SA1300*"; TriggerKind = "SharedMailbox" },
  [pscustomobject]@{ BranchCode = "4172"; SourceFamily = "GL060"; DisplayName = "4172-GL060-Inbox-Ingress"; DisplayNamePattern = "4172-GL060-Inbox-Ingress"; TriggerKind = "SharedMailbox" },
  [pscustomobject]@{ BranchCode = "4172"; SourceFamily = "FREIGHT"; DisplayName = "4172-Freight-Inbox-Ingress"; DisplayNamePattern = "4172-Freight-Inbox-Ingress"; TriggerKind = "SharedMailbox" },
  [pscustomobject]@{ BranchCode = "4173"; SourceFamily = "SP830CA"; DisplayName = "4173-QuoteFollowUp-Import-Staging"; DisplayNamePattern = "4173-QuoteFollowUp-Import-Staging"; TriggerKind = "SharedMailbox" },
  [pscustomobject]@{ BranchCode = "4173"; SourceFamily = "ZBO"; DisplayName = "4173-BackOrder-Update-ZBO-Live"; DisplayNamePattern = "4173-BackOrder-Update-ZBO-Live"; TriggerKind = "SharedMailbox" },
  [pscustomobject]@{ BranchCode = "4173"; SourceFamily = "SA1300"; DisplayName = "4173-Budget-Update-SA1300"; DisplayNamePattern = "4173-Budget-Update-SA1300*"; TriggerKind = "SharedMailbox" },
  [pscustomobject]@{ BranchCode = "4173"; SourceFamily = "GL060"; DisplayName = "4173-GL060-Inbox-Ingress"; DisplayNamePattern = "4173-GL060-Inbox-Ingress"; TriggerKind = "SharedMailbox" },
  [pscustomobject]@{ BranchCode = "4173"; SourceFamily = "FREIGHT"; DisplayName = "4173-Freight-Inbox-Ingress"; DisplayNamePattern = "4173-Freight-Inbox-Ingress"; TriggerKind = "SharedMailbox" }
)

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

function Get-ExpectedSubjectFilter {
  param(
    [string]$DisplayName,
    [string]$BranchCode,
    [string]$TriggerKind
  )

  if ($DisplayName -like "*QuoteFollowUp-Import-Staging*") {
    return "SP830"
  }
  if ($DisplayName -like "*BackOrder-Update-ZBO*") {
    return "Daily Backorder Report $BranchCode"
  }
  if ($DisplayName -like "*Budget-Update-SA1300*") {
    return "SA1300-Excel Report"
  }
  if ($DisplayName -like "*GL060-Inbox-Ingress*") {
    return "GL060 P&L report"
  }

  return $null
}

function Get-ExpectedHasAttachments {
  param(
    [string]$DisplayName,
    [string]$BranchCode,
    [string]$TriggerKind
  )

  if ($DisplayName -like "*GL060-Inbox-Ingress*") {
    return $true
  }

  return $null
}

function Get-ExpectedIncludeAttachments {
  param(
    [string]$DisplayName,
    [string]$BranchCode,
    [string]$TriggerKind
  )

  if ($DisplayName -like "*GL060-Inbox-Ingress*") {
    return $true
  }

  return $null
}

function Get-ExpectedSharedMailboxRoute {
  param(
    [string]$DisplayName,
    [string]$BranchCode
  )

  if ($DisplayName -like "*Freight-Inbox-Ingress") {
    return Get-SouthernAlbertaSharedMailboxRoute -BranchCode $BranchCode -MailboxAddress ("{0}@applied.com" -f $BranchCode)
  }

  return Get-SouthernAlbertaSharedMailboxRoute -BranchCode $BranchCode -MailboxAddress ("{0}@applied.com" -f $BranchCode)
}

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

Import-Module Microsoft.PowerApps.PowerShell

Add-PowerAppsAccount -Endpoint prod -Username $Username | Out-Null

$targetFlows = @($flowCatalog | Where-Object { $_.BranchCode -in $BranchCodes -and $_.SourceFamily -in $SourceFamilies })
$adminFlows = @(Get-Flow -EnvironmentName $TargetEnvironmentName)
$reportRows = New-Object System.Collections.Generic.List[object]

function Resolve-AdminFlow {
  param(
    [object[]]$AdminFlows,
    [object]$TargetFlow
  )

  return @(
    $AdminFlows |
      Where-Object { $_.DisplayName -like $TargetFlow.DisplayNamePattern } |
      Sort-Object `
        @{ Expression = { [string]$_.DisplayName -eq $TargetFlow.DisplayName }; Descending = $true }, `
        @{ Expression = { [bool]$_.Enabled }; Descending = $true }, `
        @{ Expression = { if ($_.LastModifiedTime) { [datetime]$_.LastModifiedTime } else { [datetime]::MinValue } }; Descending = $true }
  ) | Select-Object -First 1
}

function Repair-Definition {
  param(
    [object]$Definition,
    [string]$DisplayName,
    [string]$BranchCode,
    [string]$TriggerKind
  )

  $state = [ordered]@{
    removed_recurrence = $false
    added_or_normalized_recurrence = $false
    converted_trigger_type = $false
    subject_filter_updated = $false
    has_attachments_updated = $false
    include_attachments_updated = $false
    gl060_audit_updated = $false
    trigger_kind = $TriggerKind
    trigger_name_after = $null
    normalized_datetime_nulls = New-Object System.Collections.Generic.List[string]
  }

  $expectedSubjectFilter = Get-ExpectedSubjectFilter -DisplayName $DisplayName -BranchCode $BranchCode -TriggerKind $TriggerKind
  $expectedHasAttachments = Get-ExpectedHasAttachments -DisplayName $DisplayName -BranchCode $BranchCode -TriggerKind $TriggerKind
  $expectedIncludeAttachments = Get-ExpectedIncludeAttachments -DisplayName $DisplayName -BranchCode $BranchCode -TriggerKind $TriggerKind
  $expectedSharedMailboxRoute = Get-ExpectedSharedMailboxRoute -DisplayName $DisplayName -BranchCode $BranchCode
  $addressParameterName = if ($DisplayName -like "*Freight-Inbox-Ingress") { "qfu_Freight_SharedMailboxAddress" } else { "qfu_QFU_SharedMailboxAddress" }
  $folderParameterName = if ($DisplayName -like "*Freight-Inbox-Ingress") { "qfu_Freight_SharedMailboxFolderId" } else { "qfu_QFU_SharedMailboxFolderId" }

  if ($TriggerKind -eq "PrimaryInbox") {
    $triggerName = @($Definition.triggers.PSObject.Properties)[0].Name
    $existing = $Definition.triggers.$triggerName
    $opId = if ($existing.metadata.operationMetadataId) { $existing.metadata.operationMetadataId } else { [guid]::NewGuid().Guid }

    $Definition.triggers = [pscustomobject]([ordered]@{
      "When_email_arrives_(V3)" = [ordered]@{
        type = "OpenApiConnectionNotification"
        description = "Triggers when a new ZBO workbook lands in the primary inbox for $BranchCode."
        inputs = [ordered]@{
          parameters = [ordered]@{
            includeAttachments = $true
            subjectFilter = $expectedSubjectFilter
            importance = "Any"
            fetchOnlyWithAttachment = $true
            folderPath = "@parameters('qfu_QFU_OutlookFolderId')"
          }
          host = [ordered]@{
            apiId = "/providers/Microsoft.PowerApps/apis/shared_office365"
            operationId = "OnNewEmailV3"
            connectionName = "shared_office365"
          }
        }
        splitOn = "@triggerOutputs()?['body/value']"
        metadata = [ordered]@{
          operationMetadataId = $opId
        }
      }
    })

    $Definition.triggers."When_email_arrives_(V3)".runtimeConfiguration = [ordered]@{
      concurrency = [ordered]@{
        runs = 1
      }
    }
    $state.converted_trigger_type = $true
    $state.subject_filter_updated = $true
    $state.trigger_name_after = "When_email_arrives_(V3)"
    return $state
  }

  if ($Definition.PSObject.Properties["parameters"]) {
    $parameterDefaults = $Definition.parameters

    if ($parameterDefaults.PSObject.Properties[$addressParameterName]) {
      $parameterDefaults.$addressParameterName.defaultValue = $expectedSharedMailboxRoute.MailboxAddress
    }

    if ($parameterDefaults.PSObject.Properties[$folderParameterName]) {
      $parameterDefaults.$folderParameterName.defaultValue = $expectedSharedMailboxRoute.FolderId
    }
  }

  function Walk-Node {
    param([object]$Node)

    if ($null -eq $Node) {
      return
    }

    if ($Node -is [System.Collections.IEnumerable] -and -not ($Node -is [string])) {
      foreach ($item in $Node) {
        Walk-Node -Node $item
      }
      return
    }

    if ($Node -isnot [System.Management.Automation.PSCustomObject]) {
      return
    }

    if (
      $Node.PSObject.Properties["type"] -and
      $Node.PSObject.Properties["inputs"] -and
      $Node.inputs.PSObject.Properties["host"] -and
      $Node.inputs.host.PSObject.Properties["operationId"] -and
      [string]$Node.inputs.host.operationId -eq "SharedMailboxOnNewEmailV2"
    ) {
      if ([string]$Node.type -eq "OpenApiConnectionNotification") {
        $Node.type = "OpenApiConnection"
        $state.converted_trigger_type = $true
      }

      $expectedRecurrence = [ordered]@{
        interval = 1
        frequency = "Minute"
      }

      $hasExpectedRecurrence = $false
      if ($Node.PSObject.Properties["recurrence"]) {
        $recurrence = $Node.recurrence
        $hasExpectedRecurrence = (
          $recurrence -is [System.Management.Automation.PSCustomObject] -and
          [int]$recurrence.interval -eq 1 -and
          [string]$recurrence.frequency -eq "Minute"
        )
      }

      if (-not $hasExpectedRecurrence) {
        if ($Node.PSObject.Properties["recurrence"]) {
          $Node.PSObject.Properties.Remove("recurrence")
          $state.removed_recurrence = $true
        }

        $Node | Add-Member -NotePropertyName "recurrence" -NotePropertyValue ([pscustomobject]$expectedRecurrence) -Force
        $state.added_or_normalized_recurrence = $true
      }

      if ($Node.inputs.PSObject.Properties["parameters"] -and $Node.inputs.parameters) {
        $Node.inputs.parameters | Add-Member -NotePropertyName "mailboxAddress" -NotePropertyValue ("@parameters('{0}')" -f $addressParameterName) -Force
        $Node.inputs.parameters | Add-Member -NotePropertyName "folderId" -NotePropertyValue ("@parameters('{0}')" -f $folderParameterName) -Force
        $currentSubjectFilter = if ($Node.inputs.parameters.PSObject.Properties["subjectFilter"]) { [string]$Node.inputs.parameters.subjectFilter } else { $null }
        $currentHasAttachments = if ($Node.inputs.parameters.PSObject.Properties["hasAttachments"]) { [bool]$Node.inputs.parameters.hasAttachments } else { $null }
        $currentIncludeAttachments = if ($Node.inputs.parameters.PSObject.Properties["includeAttachments"]) { [bool]$Node.inputs.parameters.includeAttachments } else { $null }

        if ([string]::IsNullOrWhiteSpace($expectedSubjectFilter)) {
          if ($Node.inputs.parameters.PSObject.Properties["subjectFilter"]) {
            $Node.inputs.parameters.PSObject.Properties.Remove("subjectFilter")
            $state.subject_filter_updated = $true
          }
        } elseif ($currentSubjectFilter -ne $expectedSubjectFilter) {
          $Node.inputs.parameters | Add-Member -NotePropertyName "subjectFilter" -NotePropertyValue $expectedSubjectFilter -Force
          $state.subject_filter_updated = $true
        }

        if ($null -ne $expectedHasAttachments -and $currentHasAttachments -ne [bool]$expectedHasAttachments) {
          $Node.inputs.parameters | Add-Member -NotePropertyName "hasAttachments" -NotePropertyValue ([bool]$expectedHasAttachments) -Force
          $state.has_attachments_updated = $true
        }

        if ($null -ne $expectedIncludeAttachments -and $currentIncludeAttachments -ne [bool]$expectedIncludeAttachments) {
          $Node.inputs.parameters | Add-Member -NotePropertyName "includeAttachments" -NotePropertyValue ([bool]$expectedIncludeAttachments) -Force
          $state.include_attachments_updated = $true
        }
      }
    }

    foreach ($property in @($Node.PSObject.Properties)) {
      if ($property.Name -eq "item/qfu_nextfollowup" -and [string]$property.Value -eq "null") {
        $Node.PSObject.Properties.Remove($property.Name)
        $Node | Add-Member -NotePropertyName $property.Name -NotePropertyValue $null -Force
        $state.normalized_datetime_nulls.Add($property.Name) | Out-Null
        continue
      }

      Walk-Node -Node $property.Value
    }
  }

  Walk-Node -Node $Definition

  if ($DisplayName -like "*GL060-Inbox-Ingress*") {
    $gl060Actions = if ($Definition.PSObject.Properties["actions"] -and $Definition.actions.PSObject.Properties["Apply_to_each_GL060_Attachment"]) {
      $Definition.actions.Apply_to_each_GL060_Attachment.actions
    } else {
      $null
    }

    if ($gl060Actions) {
      $rawParameters = $gl060Actions.Create_Raw_Document.inputs.parameters
      $batchParameters = $gl060Actions.Create_Ingestion_Batch.inputs.parameters

      $expectedReceivedOn = "@coalesce(triggerOutputs()?['body/receivedDateTime'], utcNow())"
      $expectedRawContent = "@base64(base64ToBinary(items('Apply_to_each_GL060_Attachment')?['contentBytes']))"
      $expectedProcessingNotes = "@concat('Queued from the configured shared mailbox folder by GL060 ingress flow. Subject=', coalesce(triggerOutputs()?['body/subject'], ''), '; InternetMessageId=', coalesce(triggerOutputs()?['body/internetMessageId'], ''), '; ReceivedDateTime=', string(coalesce(triggerOutputs()?['body/receivedDateTime'], utcNow())))"
      $expectedBatchNotes = "@concat('Queued from the configured shared mailbox folder. Subject=', coalesce(triggerOutputs()?['body/subject'], ''), '; InternetMessageId=', coalesce(triggerOutputs()?['body/internetMessageId'], ''), '; ReceivedDateTime=', string(coalesce(triggerOutputs()?['body/receivedDateTime'], utcNow())), '. Awaiting downstream GL060 processing.')"

      if ([string]$rawParameters.'item/qfu_receivedon' -ne $expectedReceivedOn) {
        Set-ObjectProperty -Object $rawParameters -Name "item/qfu_receivedon" -Value $expectedReceivedOn
        $state.gl060_audit_updated = $true
      }

      if ([string]$rawParameters.'item/qfu_rawcontentbase64' -ne $expectedRawContent) {
        Set-ObjectProperty -Object $rawParameters -Name "item/qfu_rawcontentbase64" -Value $expectedRawContent
        $state.gl060_audit_updated = $true
      }

      if ([string]$rawParameters.'item/qfu_processingnotes' -ne $expectedProcessingNotes) {
        Set-ObjectProperty -Object $rawParameters -Name "item/qfu_processingnotes" -Value $expectedProcessingNotes
        $state.gl060_audit_updated = $true
      }

      if ([string]$batchParameters.'item/qfu_startedon' -ne $expectedReceivedOn) {
        Set-ObjectProperty -Object $batchParameters -Name "item/qfu_startedon" -Value $expectedReceivedOn
        $state.gl060_audit_updated = $true
      }

      if ([string]$batchParameters.'item/qfu_notes' -ne $expectedBatchNotes) {
        Set-ObjectProperty -Object $batchParameters -Name "item/qfu_notes" -Value $expectedBatchNotes
        $state.gl060_audit_updated = $true
      }
    }
  }

  $state.trigger_name_after = @($Definition.triggers.PSObject.Properties)[0].Name
  return $state
}

foreach ($targetFlow in $targetFlows) {
  try {
    $adminFlow = Resolve-AdminFlow -AdminFlows $adminFlows -TargetFlow $targetFlow
    if (-not $adminFlow) {
      throw "Flow not found."
    }

    $route = "https://{flowEndpoint}/providers/Microsoft.ProcessSimple/environments/{environment}/flows/{flowName}?api-version={apiVersion}" `
      | ReplaceMacro -Macro "{environment}" -Value $TargetEnvironmentName `
      | ReplaceMacro -Macro "{flowName}" -Value $adminFlow.FlowName

    $flow = InvokeApi -Method GET -Route $route -ApiVersion "2016-11-01" -Verbose:$false
    $triggerProperty = @($flow.properties.definition.triggers.PSObject.Properties)[0]
    if (-not $triggerProperty) {
      throw "No trigger found in flow definition."
    }

    $trigger = $triggerProperty.Value
    $repairState = Repair-Definition -Definition $flow.properties.definition -DisplayName $targetFlow.DisplayName -BranchCode $targetFlow.BranchCode -TriggerKind $targetFlow.TriggerKind
    $flow.properties.state = "Started"
    $stamp = Get-Date -Format "yyyyMMdd.HHmmss"
    $flow.properties.definition.contentVersion = "1.0.$stamp"

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

    $after = InvokeApi -Method GET -Route $route -ApiVersion "2016-11-01" -Verbose:$false
    $afterTrigger = @($after.properties.definition.triggers.PSObject.Properties)[0].Value

    $reportRows.Add([pscustomobject]@{
      display_name = $targetFlow.DisplayName
      branch_code = $targetFlow.BranchCode
      source_family = $targetFlow.SourceFamily
      trigger_kind = $targetFlow.TriggerKind
      flow_name = $adminFlow.FlowName
      trigger_name = $triggerProperty.Name
      patched = $true
      converted_trigger_type = [bool]$repairState.converted_trigger_type
      removed_recurrence = [bool]$repairState.removed_recurrence
      added_or_normalized_recurrence = [bool]$repairState.added_or_normalized_recurrence
      subject_filter_updated = [bool]$repairState.subject_filter_updated
      has_attachments_updated = [bool]$repairState.has_attachments_updated
      include_attachments_updated = [bool]$repairState.include_attachments_updated
      gl060_audit_updated = [bool]$repairState.gl060_audit_updated
      normalized_datetime_nulls = @($repairState.normalized_datetime_nulls.ToArray())
      trigger_name_after = [string]$repairState.trigger_name_after
      trigger_type_after = [string]$afterTrigger.type
      subject_filter_after = if ($afterTrigger.inputs.parameters.PSObject.Properties["subjectFilter"]) { [string]$afterTrigger.inputs.parameters.subjectFilter } else { $null }
      has_attachments_after = if ($afterTrigger.inputs.parameters.PSObject.Properties["hasAttachments"]) { [bool]$afterTrigger.inputs.parameters.hasAttachments } else { $null }
      include_attachments_after = if ($afterTrigger.inputs.parameters.PSObject.Properties["includeAttachments"]) { [bool]$afterTrigger.inputs.parameters.includeAttachments } else { $null }
      mailbox_address_after = if ($after.properties.definition.parameters.PSObject.Properties["qfu_Freight_SharedMailboxAddress"]) { [string]$after.properties.definition.parameters.qfu_Freight_SharedMailboxAddress.defaultValue } elseif ($after.properties.definition.parameters.PSObject.Properties["qfu_QFU_SharedMailboxAddress"]) { [string]$after.properties.definition.parameters.qfu_QFU_SharedMailboxAddress.defaultValue } else { $null }
      folder_id_after = if ($after.properties.definition.parameters.PSObject.Properties["qfu_Freight_SharedMailboxFolderId"]) { [string]$after.properties.definition.parameters.qfu_Freight_SharedMailboxFolderId.defaultValue } elseif ($after.properties.definition.parameters.PSObject.Properties["qfu_QFU_SharedMailboxFolderId"]) { [string]$after.properties.definition.parameters.qfu_QFU_SharedMailboxFolderId.defaultValue } else { $null }
      recurrence_present_after = [bool]($afterTrigger.PSObject.Properties["recurrence"])
      recurrence_after = if ($afterTrigger.PSObject.Properties["recurrence"]) { $afterTrigger.recurrence } else { $null }
      state_after = [string]$after.properties.state
      content_version_after = $after.properties.definition.contentVersion
      last_modified_after = $after.properties.lastModifiedTime
    }) | Out-Null
  } catch {
    $reportRows.Add([pscustomobject]@{
      display_name = $targetFlow.DisplayName
      branch_code = $targetFlow.BranchCode
      source_family = $targetFlow.SourceFamily
      flow_name = if ($adminFlow) { $adminFlow.FlowName } else { $null }
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
  rows = @($reportRows.ToArray())
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $OutputPath = Join-Path (Join-Path (Get-Location) "results") "southern-alberta-mailbox-trigger-definition-repair-$stamp.json"
}

Write-Utf8Json -Path $OutputPath -Object $report

$report.rows |
  Select-Object display_name, source_family, converted_trigger_type, added_or_normalized_recurrence, subject_filter_updated, has_attachments_updated, include_attachments_updated, gl060_audit_updated, subject_filter_after, has_attachments_after, include_attachments_after, trigger_type_after, recurrence_present_after, state_after, last_modified_after |
  Format-Table -AutoSize

Write-Host "OUTPUT_PATH=$OutputPath"
