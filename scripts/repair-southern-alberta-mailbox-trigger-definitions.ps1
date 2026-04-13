param(
  [string]$TargetEnvironmentName = "9f2e54c6-c349-e7e1-ac7c-010d3adf3c03",
  [string]$Username = "smcfarlane@applied.com",
  [string[]]$BranchCodes = @("4171", "4172", "4173"),
  [switch]$RestartAfterPatch = $true,
  [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

$flowCatalog = @(
  [pscustomobject]@{ BranchCode = "4171"; DisplayName = "4171-QuoteFollowUp-Import-Staging"; TriggerKind = "SharedMailbox" },
  [pscustomobject]@{ BranchCode = "4171"; DisplayName = "4171-BackOrder-Update-ZBO"; TriggerKind = "SharedMailbox" },
  [pscustomobject]@{ BranchCode = "4171"; DisplayName = "4171-Budget-Update-SA1300"; TriggerKind = "SharedMailbox" },
  [pscustomobject]@{ BranchCode = "4171"; DisplayName = "4171-GL060-Inbox-Ingress"; TriggerKind = "SharedMailbox" },
  [pscustomobject]@{ BranchCode = "4172"; DisplayName = "4172-QuoteFollowUp-Import-Staging"; TriggerKind = "SharedMailbox" },
  [pscustomobject]@{ BranchCode = "4172"; DisplayName = "4172-BackOrder-Update-ZBO"; TriggerKind = "SharedMailbox" },
  [pscustomobject]@{ BranchCode = "4172"; DisplayName = "4172-Budget-Update-SA1300"; TriggerKind = "SharedMailbox" },
  [pscustomobject]@{ BranchCode = "4172"; DisplayName = "4172-GL060-Inbox-Ingress"; TriggerKind = "SharedMailbox" },
  [pscustomobject]@{ BranchCode = "4173"; DisplayName = "4173-QuoteFollowUp-Import-Staging"; TriggerKind = "SharedMailbox" },
  [pscustomobject]@{ BranchCode = "4173"; DisplayName = "4173-BackOrder-Update-ZBO"; TriggerKind = "SharedMailbox" },
  [pscustomobject]@{ BranchCode = "4173"; DisplayName = "4173-Budget-Update-SA1300"; TriggerKind = "SharedMailbox" },
  [pscustomobject]@{ BranchCode = "4173"; DisplayName = "4173-GL060-Inbox-Ingress"; TriggerKind = "SharedMailbox" }
)

function Get-ExpectedSubjectFilter {
  param(
    [string]$DisplayName,
    [string]$BranchCode,
    [string]$TriggerKind
  )

  if ($DisplayName -like "*QuoteFollowUp-Import-Staging") {
    return "SP830CA - Quote Follow Up Report"
  }
  if ($DisplayName -like "*BackOrder-Update-ZBO") {
    return "Daily Backorder Report $BranchCode"
  }
  if ($DisplayName -like "*Budget-Update-SA1300") {
    return "SA1300-Excel Report"
  }

  return $null
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

$targetFlows = @($flowCatalog | Where-Object { $_.BranchCode -in $BranchCodes })
$adminFlows = @(Get-Flow -EnvironmentName $TargetEnvironmentName)
$reportRows = New-Object System.Collections.Generic.List[object]

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
    trigger_kind = $TriggerKind
    trigger_name_after = $null
    normalized_datetime_nulls = New-Object System.Collections.Generic.List[string]
  }

  $expectedSubjectFilter = Get-ExpectedSubjectFilter -DisplayName $DisplayName -BranchCode $BranchCode -TriggerKind $TriggerKind

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
        $currentSubjectFilter = if ($Node.inputs.parameters.PSObject.Properties["subjectFilter"]) { [string]$Node.inputs.parameters.subjectFilter } else { $null }

        if ([string]::IsNullOrWhiteSpace($expectedSubjectFilter)) {
          if ($Node.inputs.parameters.PSObject.Properties["subjectFilter"]) {
            $Node.inputs.parameters.PSObject.Properties.Remove("subjectFilter")
            $state.subject_filter_updated = $true
          }
        } elseif ($currentSubjectFilter -ne $expectedSubjectFilter) {
          $Node.inputs.parameters | Add-Member -NotePropertyName "subjectFilter" -NotePropertyValue $expectedSubjectFilter -Force
          $state.subject_filter_updated = $true
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
  $state.trigger_name_after = @($Definition.triggers.PSObject.Properties)[0].Name
  return $state
}

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
      trigger_kind = $targetFlow.TriggerKind
      flow_name = $adminFlow.FlowName
      trigger_name = $triggerProperty.Name
      patched = $true
      converted_trigger_type = [bool]$repairState.converted_trigger_type
      removed_recurrence = [bool]$repairState.removed_recurrence
      added_or_normalized_recurrence = [bool]$repairState.added_or_normalized_recurrence
      subject_filter_updated = [bool]$repairState.subject_filter_updated
      normalized_datetime_nulls = @($repairState.normalized_datetime_nulls.ToArray())
      trigger_name_after = [string]$repairState.trigger_name_after
      trigger_type_after = [string]$afterTrigger.type
      subject_filter_after = if ($afterTrigger.inputs.parameters.PSObject.Properties["subjectFilter"]) { [string]$afterTrigger.inputs.parameters.subjectFilter } else { $null }
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
  Select-Object display_name, converted_trigger_type, added_or_normalized_recurrence, subject_filter_updated, subject_filter_after, trigger_type_after, recurrence_present_after, state_after, last_modified_after |
  Format-Table -AutoSize

Write-Host "OUTPUT_PATH=$OutputPath"
