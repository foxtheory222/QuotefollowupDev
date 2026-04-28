param(
  [string]$TargetEnvironmentName = "<GUID>",
  [string]$Username = "<EMAIL>",
  [string[]]$BranchCodes = @("4171"),
  [string[]]$SourceFamilies = @("SP830CA", "GL060"),
  [switch]$RestartAfterPatch = $true,
  [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

$flowCatalog = @(
  [pscustomobject]@{ BranchCode = "4171"; SourceFamily = "SP830CA"; DisplayName = "4171-QuoteFollowUp-Import-Staging" },
  [pscustomobject]@{ BranchCode = "4171"; SourceFamily = "ZBO"; DisplayName = "4171-BackOrder-Update-ZBO-Live" },
  [pscustomobject]@{ BranchCode = "4171"; SourceFamily = "GL060"; DisplayName = "4171-GL060-Inbox-Ingress" },
  [pscustomobject]@{ BranchCode = "4172"; SourceFamily = "SP830CA"; DisplayName = "4172-QuoteFollowUp-Import-Staging" },
  [pscustomobject]@{ BranchCode = "4172"; SourceFamily = "ZBO"; DisplayName = "4172-BackOrder-Update-ZBO-Live" },
  [pscustomobject]@{ BranchCode = "4172"; SourceFamily = "GL060"; DisplayName = "4172-GL060-Inbox-Ingress" },
  [pscustomobject]@{ BranchCode = "4173"; SourceFamily = "SP830CA"; DisplayName = "4173-QuoteFollowUp-Import-Staging" },
  [pscustomobject]@{ BranchCode = "4173"; SourceFamily = "ZBO"; DisplayName = "4173-BackOrder-Update-ZBO-Live" },
  [pscustomobject]@{ BranchCode = "4173"; SourceFamily = "GL060"; DisplayName = "4173-GL060-Inbox-Ingress" }
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

function Normalize-MailboxTrigger {
  param([object]$Definition)

  $state = [ordered]@{
    normalized_trigger_type = $false
    normalized_recurrence = $false
  }

  foreach ($triggerProperty in @($Definition.triggers.PSObject.Properties)) {
    $trigger = $triggerProperty.Value
    if (
      $null -ne $trigger -and
      $trigger.PSObject.Properties["inputs"] -and
      $trigger.inputs.PSObject.Properties["host"] -and
      $trigger.inputs.host.PSObject.Properties["operationId"] -and
      [string]$trigger.inputs.host.operationId -eq "SharedMailboxOnNewEmailV2"
    ) {
      if ([string]$trigger.type -ne "OpenApiConnection") {
        $trigger.type = "OpenApiConnection"
        $state.normalized_trigger_type = $true
      }

      $expectedRecurrence = [pscustomobject]@{
        interval = 1
        frequency = "Minute"
      }

      $needsRecurrence = $true
      if ($trigger.PSObject.Properties["recurrence"]) {
        $recurrence = $trigger.recurrence
        $needsRecurrence = -not (
          $recurrence -is [System.Management.Automation.PSCustomObject] -and
          [int]$recurrence.interval -eq 1 -and
          [string]$recurrence.frequency -eq "Minute"
        )
      }

      if ($needsRecurrence) {
        $trigger | Add-Member -NotePropertyName recurrence -NotePropertyValue $expectedRecurrence -Force
        $state.normalized_recurrence = $true
      }
    }
  }

  return $state
}

function Repair-QfuDefinition {
  param([object]$Definition)

  $attachmentCondition = $Definition.actions.Check_if_weekday.actions.Apply_to_each_attachment.actions.Condition_Is_SP830CA_File
  $quoteActions = $attachmentCondition.actions
  $lineActions = $Definition.actions.Check_if_weekday.actions.Apply_to_each_attachment.actions.Condition_Is_SP830CA_File.actions.Guard_Quote_Rows.actions.Apply_to_each_quote_line.actions
  $updates = [ordered]@{
    updated_quote_select = $false
    updated_attachment_gate = $false
    updated_cleanup_gate = $false
  }

  $expectedAttachmentExpression = [ordered]@{
    and = @(
      [ordered]@{
        contains = @(
          "@toLower(coalesce(items('Apply_to_each_attachment')?['name'], ''))",
          ".xlsx"
        )
      },
      [ordered]@{
        contains = @(
          "@toLower(coalesce(items('Apply_to_each_attachment')?['name'], ''))",
          "sp830"
        )
      }
    )
  }
  if ((ConvertTo-Json $attachmentCondition.expression -Depth 10 -Compress) -ne (ConvertTo-Json $expectedAttachmentExpression -Depth 10 -Compress)) {
    $attachmentCondition.expression = $expectedAttachmentExpression
    $updates.updated_attachment_gate = $true
  }

  $expectedSelect = "qfu_quoteid,statecode,statuscode"
  if ([string]$lineActions.Check_Quote_Exists.inputs.parameters.'$select' -ne $expectedSelect) {
    $lineActions.Check_Quote_Exists.inputs.parameters.'$select' = $expectedSelect
    $updates.updated_quote_select = $true
  }

  $expectedCleanupForeach = "@json('[]')"
  if ([string]$quoteActions.Deactivate_Missing_Quotes.foreach -ne $expectedCleanupForeach) {
    $quoteActions.Deactivate_Missing_Quotes.foreach = $expectedCleanupForeach
    $updates.updated_cleanup_gate = $true
  }

  $expectedCleanupDescription = "Quote cleanup is disabled on the live SP830 flow so previously-seen quotes stay visible until cleanup is intentionally re-enabled."
  if ([string]$quoteActions.Deactivate_Missing_Quotes.description -ne $expectedCleanupDescription) {
    $quoteActions.Deactivate_Missing_Quotes.description = $expectedCleanupDescription
    $updates.updated_cleanup_gate = $true
  }

  return $updates
}

function Repair-ZboDefinition {
  param([object]$Definition)

  $attachmentCondition = $Definition.actions.Apply_to_each_Attachment.actions.Condition_Is_CA_ZBO_File
  $updates = [ordered]@{
    updated_attachment_gate = $false
  }

  $expectedAttachmentExpression = [ordered]@{
    or = @(
      [ordered]@{
        endsWith = @(
          "@toLower(coalesce(items('Apply_to_each_Attachment')?['name'], ''))",
          ".xlsx"
        )
      },
      [ordered]@{
        endsWith = @(
          "@toLower(coalesce(items('Apply_to_each_Attachment')?['name'], ''))",
          ".xlsm"
        )
      },
      [ordered]@{
        endsWith = @(
          "@toLower(coalesce(items('Apply_to_each_Attachment')?['name'], ''))",
          ".xls"
        )
      }
    )
  }

  if ((ConvertTo-Json $attachmentCondition.expression -Depth 10 -Compress) -ne (ConvertTo-Json $expectedAttachmentExpression -Depth 10 -Compress)) {
    $attachmentCondition.expression = $expectedAttachmentExpression
    $updates.updated_attachment_gate = $true
  }

  return $updates
}

function Repair-Gl060Definition {
  param([object]$Definition)

  $createRawDocument = $Definition.actions.Apply_to_each_GL060_Attachment.actions.Create_Raw_Document
  $updates = [ordered]@{
    updated_rawcontent_expression = $false
  }

  $expectedExpression = "@base64(base64ToBinary(items('Apply_to_each_GL060_Attachment')?['contentBytes']))"
  if ([string]$createRawDocument.inputs.parameters.'item/qfu_rawcontentbase64' -ne $expectedExpression) {
    $createRawDocument.inputs.parameters.'item/qfu_rawcontentbase64' = $expectedExpression
    $updates.updated_rawcontent_expression = $true
  }

  return $updates
}

Import-Module Microsoft.PowerApps.PowerShell

Add-PowerAppsAccount -Endpoint prod -Username $Username | Out-Null

$targetFlows = @(
  $flowCatalog |
    Where-Object { $_.BranchCode -in $BranchCodes -and $_.SourceFamily -in $SourceFamilies }
)
$adminFlows = @(Get-Flow -EnvironmentName $TargetEnvironmentName)
$reportRows = New-Object System.Collections.Generic.List[object]

foreach ($targetFlow in $targetFlows) {
  try {
    $adminFlow = $adminFlows | Where-Object { $_.DisplayName -eq $targetFlow.DisplayName } | Select-Object -First 1
    if (-not $adminFlow) {
      throw "Flow not found."
    }

    $route = "<URL> `
      | ReplaceMacro -Macro "{environment}" -Value $TargetEnvironmentName `
      | ReplaceMacro -Macro "{flowName}" -Value $adminFlow.FlowName

    $flow = InvokeApi -Method GET -Route $route -ApiVersion "2016-11-01" -Verbose:$false
    $triggerState = Normalize-MailboxTrigger -Definition $flow.properties.definition
    $repairState = switch ($targetFlow.SourceFamily) {
      "SP830CA" { Repair-QfuDefinition -Definition $flow.properties.definition }
      "ZBO" { Repair-ZboDefinition -Definition $flow.properties.definition }
      "GL060" { Repair-Gl060Definition -Definition $flow.properties.definition }
      default { [ordered]@{} }
    }

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
    $reportRows.Add([pscustomobject]@{
      display_name = $targetFlow.DisplayName
      branch_code = $targetFlow.BranchCode
      source_family = $targetFlow.SourceFamily
      flow_name = $adminFlow.FlowName
      normalized_trigger_type = [bool]$triggerState.normalized_trigger_type
      normalized_recurrence = [bool]$triggerState.normalized_recurrence
      repair_state = [pscustomobject]$repairState
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
      error = $_.Exception.Message
    }) | Out-Null
  }
}

$report = [pscustomobject]@{
  captured_at = (Get-Date).ToUniversalTime().ToString("o")
  environment_name = $TargetEnvironmentName
  branch_codes = @($BranchCodes)
  source_families = @($SourceFamilies)
  restart_after_patch = [bool]$RestartAfterPatch
  rows = @($reportRows.ToArray())
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $OutputPath = Join-Path (Join-Path (Get-Location) "results") "southern-alberta-live-flow-defect-repair-$stamp.json"
}

Write-Utf8Json -Path $OutputPath -Object $report

$report.rows |
  Select-Object display_name, source_family, normalized_trigger_type, normalized_recurrence, state_after, last_modified_after |
  Format-Table -AutoSize

Write-Host "OUTPUT_PATH=$OutputPath"
