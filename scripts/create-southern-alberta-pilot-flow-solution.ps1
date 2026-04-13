param(
  [string]$RepoRoot = "C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion",
  [string]$TargetEnvironmentUrl = "https://regionaloperationshub.crm.dynamics.com",
  [string]$TargetEnvironmentName = "9f2e54c6-c349-e7e1-ac7c-010d3adf3c03",
  [string]$Username = "smcfarlane@applied.com",
  [string]$SolutionUniqueName = "qfu_sapilotflows",
  [string]$SolutionDisplayName = "QFU Southern Alberta Pilot Flows",
  [string]$SolutionVersion = "1.0.0.1",
  [string[]]$Families = @(),
  [switch]$ImportToTarget = $false
)

$ErrorActionPreference = "Stop"

$sourceWorkflowRoot = Join-Path $RepoRoot "results\source4171-solution-unpacked\Workflows"
$solutionRoot = Join-Path $RepoRoot "results\sapilotflows"
$sourceRoot = Join-Path $solutionRoot "src"
$otherRoot = Join-Path $sourceRoot "Other"
$workflowRoot = Join-Path $sourceRoot "Workflows"
$zipPath = Join-Path $RepoRoot "results\qfu-southern-alberta-pilot-flows.zip"
$mapPath = Join-Path $RepoRoot "results\qfu-southern-alberta-pilot-flows-map.json"

$branchSpecs = @(
  [pscustomobject]@{ BranchCode = "4171"; BranchSlug = "4171-calgary"; BranchName = "Calgary"; MailboxAddress = "4171@applied.com"; SortOrder = 1; UsdOpsDailyRange = "'Daily Sales- Location'!A2:F500"; CadOpsDailyRange = "'Daily Sales- Location'!H2:M500" },
  [pscustomobject]@{ BranchCode = "4172"; BranchSlug = "4172-lethbridge"; BranchName = "Lethbridge"; MailboxAddress = "4172@applied.com"; SortOrder = 2; UsdOpsDailyRange = $null; CadOpsDailyRange = "'Daily Sales- Location'!B2:G500" },
  [pscustomobject]@{ BranchCode = "4173"; BranchSlug = "4173-medicine-hat"; BranchName = "Medicine Hat"; MailboxAddress = "4173@applied.com"; SortOrder = 3; UsdOpsDailyRange = $null; CadOpsDailyRange = "'Daily Sales- Location'!B2:G500" }
)

$templateSpecs = @(
  [pscustomobject]@{
    Family = "Quote"
    SourceFlowName = "QuoteFollow-UpImport-Staging_DEV"
    SourceFile = "QuoteFollow-UpImport-Staging_DEV-7742C979-E2EB-F011-8406-000D3AF4C93E.json"
    TargetSuffix = "QuoteFollowUp-Import-Staging"
    SourceFamily = "SP830CA"
    TriggerKind = "SharedMailbox"
    SubjectFilter = "SP830CA - Quote Follow Up Report"
  },
  [pscustomobject]@{
    Family = "Backorder"
    SourceFlowName = "BackOrder_Update_From_CA_ZBO_DEV"
    SourceFile = "BackOrder_Update_From_CA_ZBO_DEV-5C42C979-E2EB-F011-8406-000D3AF4C93E.json"
    TargetSuffix = "BackOrder-Update-ZBO"
    SourceFamily = "ZBO"
    TriggerKind = "SharedMailbox"
    SubjectFilter = "Daily Backorder Report"
  },
  [pscustomobject]@{
    Family = "Budget"
    SourceFlowName = "Budget_Update_From_SA1300_Unmanaged_DEV"
    SourceFile = "Budget_Update_From_SA1300_Unmanaged_DEV-6942C979-E2EB-F011-8406-000D3AF4C93E.json"
    TargetSuffix = "Budget-Update-SA1300"
    SourceFamily = "SA1300"
    TriggerKind = "SharedMailbox"
    SubjectFilter = "SA1300-Excel Report"
  }
)

if (@($Families | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
  $selectedFamilies = @($Families | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
  $templateSpecs = @($templateSpecs | Where-Object { $_.Family -in $selectedFamilies })
  if ($templateSpecs.Count -eq 0) {
    throw "No template specs matched Families: $($selectedFamilies -join ', ')"
  }
}

$workflowIdMap = @{
  "4171|Quote" = "0aff92f1-a8f0-45d7-b05c-3afe5ade9ed1"
  "4171|Backorder" = "94ae1bae-fe22-455e-bf63-24ba92644dc0"
  "4171|Budget" = "6db19ff3-c313-4db6-9a57-f3335fe55558"
  "4172|Quote" = "3520a9d9-f40d-430b-aec8-56b9f4c5d96c"
  "4172|Backorder" = "a5a911cc-1d2d-4e5a-b0ab-da6f52def8b0"
  "4172|Budget" = "078cea4c-84f6-4c4f-b73b-62ad838f7cae"
  "4173|Quote" = "490e1685-4623-461e-ba1c-6c0907a60e33"
  "4173|Backorder" = "3277dd8e-14f6-4e7b-b627-ebc923ba86ef"
  "4173|Budget" = "3c2ebd80-35d9-4e3c-bdbe-70be98a82ae6"
}

function Ensure-Directory {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Connect-Org {
  param([string]$Url)

  Import-Module Microsoft.Xrm.Data.Powershell

  $conn = Connect-CrmOnline -ServerUrl $Url -ForceOAuth -Username $Username
  if (-not $conn -or -not $conn.IsReady) {
    throw "Dataverse connection failed for $Url : $($conn.LastCrmError)"
  }

  return $conn
}

function Activate-ImportedWorkflows {
  param(
    [string]$Url,
    [string[]]$WorkflowIds
  )

  $conn = Connect-Org -Url $Url
  foreach ($workflowId in @($WorkflowIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
    Set-CrmRecordState -conn $conn -EntityLogicalName workflow -Id $workflowId -StateCode Activated -StatusCode Activated | Out-Null
  }
}

function Enable-ImportedAdminFlows {
  param(
    [string]$EnvironmentName,
    [string[]]$WorkflowIds
  )

  Import-Module Microsoft.PowerApps.Administration.PowerShell
  Add-PowerAppsAccount -Endpoint prod -Username $Username | Out-Null

  $ids = @($WorkflowIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  $adminFlows = @(Get-AdminFlow -EnvironmentName $EnvironmentName | Where-Object { $_.WorkflowEntityId -in $ids })
  foreach ($flow in $adminFlows) {
    if (-not $flow.Enabled) {
      Enable-AdminFlow -EnvironmentName $EnvironmentName -FlowName $flow.FlowName | Out-Null
    }
  }
}

function Remove-IfExists {
  param([string]$Path)
  if (Test-Path -LiteralPath $Path) {
    Remove-Item -LiteralPath $Path -Recurse -Force
  }
}

function Write-Utf8File {
  param(
    [string]$Path,
    [string]$Content
  )

  $parent = Split-Path -Parent $Path
  if ($parent) {
    Ensure-Directory $parent
  }

  [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function Convert-ToJsonCompact {
  param([object]$Object)
  return ($Object | ConvertTo-Json -Depth 100)
}

function Add-Note {
  param(
    [System.Collections.Generic.List[string]]$Notes,
    [string]$Text
  )
  if ($Text) {
    $Notes.Add($Text) | Out-Null
  }
}

function Get-WorkflowTemplate {
  param([string]$Path)
  return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

function Get-FirstTriggerName {
  param([object]$Definition)
  $triggerProperty = @($Definition.triggers.PSObject.Properties | Select-Object -First 1)
  if ($triggerProperty.Count -eq 0) {
    return $null
  }
  return $triggerProperty[0].Name
}

function Set-ParameterDefault {
  param(
    [object]$ParametersObject,
    [string]$Name,
    [object]$DefaultValue,
    [string]$Type = "String"
  )

  if (-not $ParametersObject.PSObject.Properties[$Name]) {
    $ParametersObject | Add-Member -NotePropertyName $Name -NotePropertyValue ([ordered]@{
      defaultValue = $DefaultValue
      type = $Type
    })
  } else {
    $ParametersObject.$Name.defaultValue = $DefaultValue
    $ParametersObject.$Name.type = $Type
  }
}

function Remove-PropertyIfPresent {
  param(
    [object]$Object,
    [string]$Name
  )

  if ($Object -is [System.Collections.IDictionary]) {
    if ($Object.Contains($Name)) {
      $Object.Remove($Name)
    }
    return
  }

  if ($Object -and $Object.PSObject.Properties[$Name]) {
    $Object.PSObject.Properties.Remove($Name)
  }
}

function Set-SharedMailboxTrigger {
  param(
    [object]$Definition,
    [string]$Description,
    [string]$SubjectFilter
  )

  $triggerName = Get-FirstTriggerName -Definition $Definition
  $existing = $Definition.triggers.$triggerName
  $opId = if ($existing.metadata.operationMetadataId) { $existing.metadata.operationMetadataId } else { [guid]::NewGuid().Guid }

  $parameters = [ordered]@{
    mailboxAddress = "@parameters('qfu_QFU_SharedMailboxAddress')"
    folderId = "@parameters('qfu_QFU_SharedMailboxFolderId')"
    includeAttachments = $true
    importance = "Any"
  }
  if ($SubjectFilter) {
    $parameters.subjectFilter = $SubjectFilter
  }

  $Definition.triggers = [pscustomobject]([ordered]@{
    Shared_Mailbox_New_Email = [ordered]@{
      type = "OpenApiConnection"
      description = $Description
      inputs = [ordered]@{
        parameters = $parameters
        host = [ordered]@{
          apiId = "/providers/Microsoft.PowerApps/apis/shared_office365"
          operationId = "SharedMailboxOnNewEmailV2"
          connectionName = "shared_office365"
        }
      }
      recurrence = [ordered]@{
        interval = 1
        frequency = "Minute"
      }
      splitOn = "@triggerOutputs()?['body/value']"
      metadata = [ordered]@{
        operationMetadataId = $opId
      }
    }
  })
}

function Set-PrimaryInboxTrigger {
  param(
    [object]$Definition,
    [string]$Description,
    [string]$SubjectFilter
  )

  $triggerName = Get-FirstTriggerName -Definition $Definition
  $existing = $Definition.triggers.$triggerName
  $opId = if ($existing.metadata.operationMetadataId) { $existing.metadata.operationMetadataId } else { [guid]::NewGuid().Guid }

  $parameters = [ordered]@{
    includeAttachments = $true
    importance = "Any"
    fetchOnlyWithAttachment = $true
    folderPath = "@parameters('qfu_QFU_OutlookFolderId')"
  }
  if ($SubjectFilter) {
    $parameters.subjectFilter = $SubjectFilter
  }

  $Definition.triggers = [pscustomobject]([ordered]@{
    "When_email_arrives_(V3)" = [ordered]@{
      type = "OpenApiConnectionNotification"
      description = $Description
      inputs = [ordered]@{
        parameters = $parameters
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
}

function Get-TriggerSubjectFilter {
  param(
    [object]$Template,
    [object]$Branch
  )

  if ($Template.Family -eq "Backorder") {
    return "{0} {1}" -f $Template.SubjectFilter, $Branch.BranchCode
  }

  return $Template.SubjectFilter
}

function Add-BranchParameters {
  param(
    [object]$Definition,
    [object]$Branch,
    [object]$Template
  )

  $params = $Definition.parameters
  Set-ParameterDefault -ParametersObject $params -Name "qfu_QFU_BranchCode" -DefaultValue $Branch.BranchCode
  Set-ParameterDefault -ParametersObject $params -Name "qfu_QFU_BranchSlug" -DefaultValue $Branch.BranchSlug
  Set-ParameterDefault -ParametersObject $params -Name "qfu_QFU_BranchName" -DefaultValue $Branch.BranchName
  Set-ParameterDefault -ParametersObject $params -Name "qfu_QFU_RegionSlug" -DefaultValue "southern-alberta"
  Set-ParameterDefault -ParametersObject $params -Name "qfu_QFU_SharedMailboxAddress" -DefaultValue $Branch.MailboxAddress
  Set-ParameterDefault -ParametersObject $params -Name "qfu_QFU_SharedMailboxFolderId" -DefaultValue "Inbox"

  if ($Template.Family -eq "Budget") {
    Set-ParameterDefault -ParametersObject $params -Name "qfu_QFU_ActiveFiscalYear" -DefaultValue "FY26"
  }
}

function Set-TemplateTrigger {
  param(
    [object]$Definition,
    [object]$Branch,
    [object]$Template,
    [string]$SharedMailboxDescription,
    [string]$PrimaryInboxDescription
  )

  $subjectFilter = Get-TriggerSubjectFilter -Template $Template -Branch $Branch
  if ($Template.TriggerKind -eq "PrimaryInbox") {
    Set-PrimaryInboxTrigger -Definition $Definition -Description $PrimaryInboxDescription -SubjectFilter $subjectFilter
  } else {
    Set-SharedMailboxTrigger -Definition $Definition -Description $SharedMailboxDescription -SubjectFilter $subjectFilter
  }

  $triggerName = Get-FirstTriggerName -Definition $Definition
  $triggerProperty = @($Definition.triggers.PSObject.Properties | Where-Object { $_.Name -eq $triggerName }) | Select-Object -First 1
  if (-not $triggerProperty) {
    throw "Unable to resolve trigger property '$triggerName' after trigger rewrite."
  }
  $trigger = $triggerProperty.Value
  $trigger | Add-Member -NotePropertyName "runtimeConfiguration" -NotePropertyValue ([ordered]@{
    concurrency = [ordered]@{
      runs = 1
    }
  }) -Force
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

function Copy-OrderedMap {
  param([object]$Source)
  $map = [ordered]@{}
  if ($null -eq $Source) {
    return $map
  }
  if ($Source -is [System.Collections.IDictionary]) {
    foreach ($key in $Source.Keys) {
      $map[[string]$key] = $Source[$key]
    }
    return $map
  }
  foreach ($property in $Source.PSObject.Properties) {
    $map[$property.Name] = $property.Value
  }
  return $map
}

function Copy-DeepObject {
  param([object]$Source)
  if ($null -eq $Source) {
    return $null
  }
  return ($Source | ConvertTo-Json -Depth 100 | ConvertFrom-Json)
}

function New-IngestionBatchSyncActionSet {
  param(
    [string]$ActionPrefix,
    [string]$ImportNameSuffix,
    [string]$SourceFamily,
    [string]$FlowNameExpression,
    [string]$FileNameExpression,
    [string]$StartedOnExpression,
    [object]$RunAfter,
    [string]$ConnectionName = "shared_commondataserviceforapps"
  )

  $listActionName = "List_Existing_{0}_Import_Batch" -f $ActionPrefix
  $conditionActionName = "Condition_{0}_Import_Batch_Exists" -f $ActionPrefix
  $updateActionName = "Update_{0}_Import_Batch" -f $ActionPrefix
  $createActionName = "Create_{0}_Import_Batch" -f $ActionPrefix
  $sourceIdExpression = "@concat(parameters('qfu_QFU_BranchCode'), '|batch|$SourceFamily')"

  $listAction = [ordered]@{
    type = "OpenApiConnection"
    description = "Load the stable qfu_ingestionbatch row for the $SourceFamily workbook feed."
    inputs = [ordered]@{
      parameters = [ordered]@{
        entityName = "qfu_ingestionbatchs"
        '$select' = "qfu_ingestionbatchid,qfu_sourceid,qfu_completedon"
        '$filter' = "qfu_branchcode eq '@{parameters('qfu_QFU_BranchCode')}' and qfu_sourcefamily eq '$SourceFamily' and qfu_sourceid eq '@{concat(parameters('qfu_QFU_BranchCode'), '|batch|$SourceFamily')}'"
        '$top' = 1
        '$orderby' = "modifiedon desc, createdon desc"
      }
      host = [ordered]@{
        apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
        operationId = "ListRecords"
        connectionName = $ConnectionName
      }
    }
    runAfter = (Copy-OrderedMap -Source $RunAfter)
    metadata = [ordered]@{
      operationMetadataId = [guid]::NewGuid().Guid
    }
  }

  $commonParameters = [ordered]@{
    "item/qfu_name" = "@concat(parameters('qfu_QFU_BranchCode'), ' $ImportNameSuffix')"
    "item/qfu_sourceid" = $sourceIdExpression
    "item/qfu_branchcode" = "@parameters('qfu_QFU_BranchCode')"
    "item/qfu_branchslug" = "@parameters('qfu_QFU_BranchSlug')"
    "item/qfu_regionslug" = "@parameters('qfu_QFU_RegionSlug')"
    "item/qfu_sourcefamily" = $SourceFamily
    "item/qfu_sourcefilename" = $FileNameExpression
    "item/qfu_status" = "ready"
    "item/qfu_startedon" = $StartedOnExpression
    "item/qfu_completedon" = "@utcNow()"
    "item/qfu_triggerflow" = $FlowNameExpression
  }

  $updateParameters = [ordered]@{
    entityName = "qfu_ingestionbatchs"
    recordId = "@first(outputs('$listActionName')?['body/value'])?['qfu_ingestionbatchid']"
  }
  foreach ($pair in $commonParameters.GetEnumerator()) {
    $updateParameters[$pair.Key] = $pair.Value
  }

  $createParameters = [ordered]@{
    entityName = "qfu_ingestionbatchs"
  }
  foreach ($pair in $commonParameters.GetEnumerator()) {
    $createParameters[$pair.Key] = $pair.Value
  }

  $conditionAction = [ordered]@{
    type = "If"
    expression = [ordered]@{
      greater = @(
        "@length(outputs('$listActionName')?['body/value'])",
        0
      )
    }
    actions = [ordered]@{
      $updateActionName = [ordered]@{
        type = "OpenApiConnection"
        description = "Refresh the existing qfu_ingestionbatch audit row for the $SourceFamily workbook feed."
        inputs = [ordered]@{
          parameters = $updateParameters
          host = [ordered]@{
            apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
            operationId = "UpdateRecord"
            connectionName = $ConnectionName
          }
        }
        metadata = [ordered]@{
          operationMetadataId = [guid]::NewGuid().Guid
        }
      }
    }
    else = [ordered]@{
      actions = [ordered]@{
        $createActionName = [ordered]@{
          type = "OpenApiConnection"
          description = "Create the stable qfu_ingestionbatch audit row for the $SourceFamily workbook feed."
          inputs = [ordered]@{
            parameters = $createParameters
            host = [ordered]@{
              apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
              operationId = "CreateRecord"
              connectionName = $ConnectionName
            }
          }
          metadata = [ordered]@{
            operationMetadataId = [guid]::NewGuid().Guid
          }
        }
      }
    }
    runAfter = [ordered]@{
      $listActionName = @("Succeeded")
    }
    metadata = [ordered]@{
      operationMetadataId = [guid]::NewGuid().Guid
    }
  }

  return [pscustomobject]@{
    ListActionName = $listActionName
    ListAction = [pscustomobject]$listAction
    ConditionActionName = $conditionActionName
    ConditionAction = [pscustomobject]$conditionAction
  }
}

function Add-Sa1300AbnormalMarginActions {
  param(
    [object]$Definition,
    [object]$BudgetRootActions,
    [string]$FlowName
  )

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
    "Create_Abnormal_Margin_Batch"
  )
  $snapshotActionSet = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($name in $snapshotActionNames) {
    [void]$snapshotActionSet.Add($name)
  }

  $topLevelActions = [ordered]@{}
  foreach ($property in $Definition.actions.PSObject.Properties) {
    if ($property.Name -eq "Initialize_Variable_SA1300_Snapshot_Date") {
      continue
    }

    $topLevelActions[$property.Name] = $property.Value
    if ($property.Name -eq "Initialize_Variable_BudgetGoalError") {
      $topLevelActions.Initialize_Variable_SA1300_Snapshot_Date = [ordered]@{
        type = "InitializeVariable"
        inputs = [ordered]@{
          variables = @(
            [ordered]@{
              name = "SA1300SnapshotDate"
              type = "string"
              value = "@formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'yyyy-MM-dd')"
            }
          )
        }
        runAfter = [ordered]@{
          Initialize_Variable_BudgetGoalError = @("Succeeded")
        }
        metadata = [ordered]@{
          operationMetadataId = [guid]::NewGuid().Guid
        }
      }
    }
  }
  $Definition.actions = [pscustomobject]$topLevelActions
  $Definition.actions.Filter_SA1300_Attachments.runAfter = [ordered]@{
    Initialize_Variable_SA1300_Snapshot_Date = @("Succeeded")
  }

  $excelConnectionName = [string]$BudgetRootActions.Create_Budget_Table.inputs.host.connectionName
  $dataverseConnectionName = [string]$BudgetRootActions.Guard_Budget_Row_Limit.actions.Get_Budget_Goal_From_Archives.inputs.host.connectionName
  $resumeStatuses = @("Succeeded", "Failed", "Skipped", "TimedOut")
  $marginSnapshotPrefixInner = "concat(parameters('qfu_QFU_BranchCode'), '|SA1300-MARGIN|', variables('SA1300SnapshotDate'), '|')"
  $marginBatchSourceIdInner = "concat(parameters('qfu_QFU_BranchCode'), '|batch|SA1300-ABNORMALMARGIN|', variables('SA1300SnapshotDate'))"
  $marginBatchSourceIdExpr = "@concat(parameters('qfu_QFU_BranchCode'), '|batch|SA1300-ABNORMALMARGIN|', variables('SA1300SnapshotDate'))"
  $marginSourceIdExpr = "@concat(parameters('qfu_QFU_BranchCode'), '|SA1300-MARGIN|', variables('SA1300SnapshotDate'), '|', string(items('Apply_to_each_Abnormal_Margin_Row')?['Billing Document Number']), '|', replace(replace(replace(replace(replace(toLower(coalesce(items('Apply_to_each_Abnormal_Margin_Row')?['Reveiw Type'], 'line')), ' ', '-'), '$', 'dollars'), '(', ''), ')', ''), '/', '-'))"

  $createAbnormalMarginTable = [ordered]@{
    type = "OpenApiConnection"
    description = "Create a temporary Excel table over the Abnormal Margin Review sheet."
    inputs = [ordered]@{
      parameters = [ordered]@{
        source = "me"
        drive = "@parameters('qfu_QFU_OneDriveDriveId')"
        file = "@variables('FileID')"
        "table/Range" = "'Abnormal Margin Review'!D2:P5000"
      }
      host = [ordered]@{
        apiId = "/providers/Microsoft.PowerApps/apis/shared_excelonlinebusiness"
        operationId = "CreateTable"
        connectionName = $excelConnectionName
      }
    }
    runAfter = [ordered]@{
      Guard_Budget_Row_Limit = $resumeStatuses
    }
    metadata = [ordered]@{
      operationMetadataId = [guid]::NewGuid().Guid
    }
  }

  $listAbnormalMarginRows = [ordered]@{
    type = "OpenApiConnection"
    description = "Read abnormal margin rows from the temporary Excel table."
    inputs = [ordered]@{
      parameters = [ordered]@{
        source = "me"
        drive = "@parameters('qfu_QFU_OneDriveDriveId')"
        file = "@variables('FileID')"
        table = "@coalesce(body('Create_Abnormal_Margin_Table')?['name'], body('Create_Abnormal_Margin_Table')?['id'], body('Create_Abnormal_Margin_Table')?['Id'])"
      }
      host = [ordered]@{
        apiId = "/providers/Microsoft.PowerApps/apis/shared_excelonlinebusiness"
        operationId = "GetItems"
        connectionName = $excelConnectionName
      }
    }
    runAfter = [ordered]@{
      Create_Abnormal_Margin_Table = @("Succeeded")
    }
    metadata = [ordered]@{
      operationMetadataId = [guid]::NewGuid().Guid
    }
  }

  $filterAbnormalMarginRows = [ordered]@{
    type = "Query"
    description = "Keep only abnormal margin rows for the current branch with a billing document and review type."
    inputs = [ordered]@{
      from = "@coalesce(outputs('List_Abnormal_Margin_Rows')?['body/value'], json('[]'))"
      where = "@and(not(empty(item()?['Billing Document Number'])), equals(string(item()?['Location']), parameters('qfu_QFU_BranchCode')), not(empty(item()?['Reveiw Type'])))"
    }
    runAfter = [ordered]@{
      List_Abnormal_Margin_Rows = @("Succeeded")
    }
  }

  $listExistingAbnormalMarginSnapshot = [ordered]@{
    type = "OpenApiConnection"
    description = "Load existing same-branch abnormal margin rows so today's snapshot can be replaced deterministically."
    inputs = [ordered]@{
      parameters = [ordered]@{
        entityName = "qfu_marginexceptions"
        '$select' = "qfu_marginexceptionid,qfu_sourceid"
        '$filter' = "qfu_branchcode eq '@{parameters('qfu_QFU_BranchCode')}' and qfu_sourcefamily eq 'SA1300-ABNORMALMARGIN'"
        '$top' = 5000
        '$orderby' = "createdon desc"
      }
      host = [ordered]@{
        apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
        operationId = "ListRecords"
        connectionName = $dataverseConnectionName
      }
    }
    runAfter = [ordered]@{
      Filter_Abnormal_Margin_Rows = @("Succeeded")
    }
    metadata = [ordered]@{
      operationMetadataId = [guid]::NewGuid().Guid
    }
  }

  $filterExistingAbnormalMarginSnapshot = [ordered]@{
    type = "Query"
    description = "Keep only abnormal margin rows for this branch and today's snapshot date."
    inputs = [ordered]@{
      from = "@coalesce(outputs('List_Existing_Abnormal_Margin_Snapshot')?['body/value'], json('[]'))"
      where = "@startsWith(item()?['qfu_sourceid'], $marginSnapshotPrefixInner)"
    }
    runAfter = [ordered]@{
      List_Existing_Abnormal_Margin_Snapshot = @("Succeeded")
    }
  }

  $deleteExistingAbnormalMarginSnapshot = [ordered]@{
    type = "Foreach"
    description = "Delete today's abnormal margin rows before reloading the latest workbook snapshot."
    foreach = "@coalesce(body('Filter_Existing_Abnormal_Margin_Snapshot'), json('[]'))"
    actions = [ordered]@{
      Delete_Abnormal_Margin_Record = [ordered]@{
        type = "OpenApiConnection"
        inputs = [ordered]@{
          parameters = [ordered]@{
            entityName = "qfu_marginexceptions"
            recordId = "@items('Delete_Existing_Abnormal_Margin_Snapshot')?['qfu_marginexceptionid']"
          }
          host = [ordered]@{
            apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
            operationId = "DeleteRecord"
            connectionName = $dataverseConnectionName
          }
        }
        metadata = [ordered]@{
          operationMetadataId = [guid]::NewGuid().Guid
        }
      }
    }
    runAfter = [ordered]@{
      Filter_Existing_Abnormal_Margin_Snapshot = @("Succeeded")
    }
    metadata = [ordered]@{
      operationMetadataId = [guid]::NewGuid().Guid
    }
  }

  $applyToEachAbnormalMarginRow = [ordered]@{
    type = "Foreach"
    description = "Create abnormal margin snapshot rows for the current branch from the SA1300 workbook."
    foreach = "@coalesce(body('Filter_Abnormal_Margin_Rows'), json('[]'))"
    actions = [ordered]@{
      Create_Abnormal_Margin_Record = [ordered]@{
        type = "OpenApiConnection"
        inputs = [ordered]@{
          parameters = [ordered]@{
            entityName = "qfu_marginexceptions"
            "item/qfu_name" = "@concat(parameters('qfu_QFU_BranchCode'), ' Margin ', string(items('Apply_to_each_Abnormal_Margin_Row')?['Billing Document Number']))"
            "item/qfu_sourceid" = $marginSourceIdExpr
            "item/qfu_branchcode" = "@parameters('qfu_QFU_BranchCode')"
            "item/qfu_branchslug" = "@parameters('qfu_QFU_BranchSlug')"
            "item/qfu_regionslug" = "@parameters('qfu_QFU_RegionSlug')"
            "item/qfu_sourcefamily" = "SA1300-ABNORMALMARGIN"
            "item/qfu_sourcefile" = "@items('Apply_to_each_Attachment')?['name']"
            "item/qfu_snapshotdate" = "@variables('SA1300SnapshotDate')"
            "item/qfu_billingdate" = "@if(empty(items('Apply_to_each_Abnormal_Margin_Row')?['Billing Date']), null, if(or(contains(string(items('Apply_to_each_Abnormal_Margin_Row')?['Billing Date']), '-'), contains(string(items('Apply_to_each_Abnormal_Margin_Row')?['Billing Date']), '/')), formatDateTime(items('Apply_to_each_Abnormal_Margin_Row')?['Billing Date'], 'yyyy-MM-dd'), formatDateTime(addDays('1899-12-30', int(float(items('Apply_to_each_Abnormal_Margin_Row')?['Billing Date']))), 'yyyy-MM-dd')))"
            "item/qfu_reviewtype" = "@string(items('Apply_to_each_Abnormal_Margin_Row')?['Reveiw Type'])"
            "item/qfu_currencytype" = "@string(items('Apply_to_each_Abnormal_Margin_Row')?['Currency Type'])"
            "item/qfu_cssr" = "@string(items('Apply_to_each_Abnormal_Margin_Row')?['CSSR'])"
            "item/qfu_cssrname" = "@string(items('Apply_to_each_Abnormal_Margin_Row')?['CSSR (Heading)'])"
            "item/qfu_customername" = "@string(items('Apply_to_each_Abnormal_Margin_Row')?['Sold-To Customer Name'])"
            "item/qfu_billingdocumentnumber" = "@string(items('Apply_to_each_Abnormal_Margin_Row')?['Billing Document Number'])"
            "item/qfu_billingdocumenttype" = "@string(items('Apply_to_each_Abnormal_Margin_Row')?['Billing Document Type'])"
            "item/qfu_sales" = "@float(replace(replace(string(coalesce(items('Apply_to_each_Abnormal_Margin_Row')?['Sales'], 0)), '$', ''), ',', ''))"
            "item/qfu_cogs" = "@float(replace(replace(string(coalesce(items('Apply_to_each_Abnormal_Margin_Row')?['COGS$ (LRMAC)'], 0)), '$', ''), ',', ''))"
            "item/qfu_gp" = "@float(replace(replace(string(coalesce(items('Apply_to_each_Abnormal_Margin_Row')?['GP$ (LRMAC)'], 0)), '$', ''), ',', ''))"
          }
          host = [ordered]@{
            apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
            operationId = "CreateRecord"
            connectionName = $dataverseConnectionName
          }
        }
        metadata = [ordered]@{
          operationMetadataId = [guid]::NewGuid().Guid
        }
      }
    }
    runAfter = [ordered]@{
      Delete_Existing_Abnormal_Margin_Snapshot = @("Succeeded")
    }
    metadata = [ordered]@{
      operationMetadataId = [guid]::NewGuid().Guid
    }
  }

  $listExistingAbnormalMarginBatches = [ordered]@{
    type = "OpenApiConnection"
    description = "Load existing abnormal margin batch audit rows for today's snapshot."
    inputs = [ordered]@{
      parameters = [ordered]@{
        entityName = "qfu_ingestionbatchs"
        '$select' = "qfu_ingestionbatchid,qfu_sourceid"
        '$filter' = "qfu_branchcode eq '@{parameters('qfu_QFU_BranchCode')}' and qfu_sourcefamily eq 'SA1300-ABNORMALMARGIN'"
        '$top' = 25
        '$orderby' = "createdon desc"
      }
      host = [ordered]@{
        apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
        operationId = "ListRecords"
        connectionName = $dataverseConnectionName
      }
    }
    runAfter = [ordered]@{
      Apply_to_each_Abnormal_Margin_Row = @("Succeeded")
    }
    metadata = [ordered]@{
      operationMetadataId = [guid]::NewGuid().Guid
    }
  }

  $filterExistingAbnormalMarginBatches = [ordered]@{
    type = "Query"
    description = "Keep only today's abnormal margin snapshot batch rows."
    inputs = [ordered]@{
      from = "@coalesce(outputs('List_Existing_Abnormal_Margin_Batches')?['body/value'], json('[]'))"
      where = "@equals(item()?['qfu_sourceid'], $marginBatchSourceIdInner)"
    }
    runAfter = [ordered]@{
      List_Existing_Abnormal_Margin_Batches = @("Succeeded")
    }
  }

  $deleteExistingAbnormalMarginBatches = [ordered]@{
    type = "Foreach"
    description = "Delete today's abnormal margin batch audit rows before creating the replacement audit row."
    foreach = "@coalesce(body('Filter_Existing_Abnormal_Margin_Batches'), json('[]'))"
    actions = [ordered]@{
      Delete_Abnormal_Margin_Batch = [ordered]@{
        type = "OpenApiConnection"
        inputs = [ordered]@{
          parameters = [ordered]@{
            entityName = "qfu_ingestionbatchs"
            recordId = "@items('Delete_Existing_Abnormal_Margin_Batches')?['qfu_ingestionbatchid']"
          }
          host = [ordered]@{
            apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
            operationId = "DeleteRecord"
            connectionName = $dataverseConnectionName
          }
        }
        metadata = [ordered]@{
          operationMetadataId = [guid]::NewGuid().Guid
        }
      }
    }
    runAfter = [ordered]@{
      Filter_Existing_Abnormal_Margin_Batches = @("Succeeded")
    }
    metadata = [ordered]@{
      operationMetadataId = [guid]::NewGuid().Guid
    }
  }

  $createAbnormalMarginBatch = [ordered]@{
    type = "OpenApiConnection"
    description = "Create the abnormal margin ingestion audit row for today's SA1300 snapshot."
    inputs = [ordered]@{
      parameters = [ordered]@{
        entityName = "qfu_ingestionbatchs"
        "item/qfu_name" = "@concat(parameters('qfu_QFU_BranchCode'), ' SA1300 Abnormal Margin Snapshot')"
        "item/qfu_sourceid" = $marginBatchSourceIdExpr
        "item/qfu_branchcode" = "@parameters('qfu_QFU_BranchCode')"
        "item/qfu_branchslug" = "@parameters('qfu_QFU_BranchSlug')"
        "item/qfu_regionslug" = "@parameters('qfu_QFU_RegionSlug')"
        "item/qfu_sourcefamily" = "SA1300-ABNORMALMARGIN"
        "item/qfu_sourcefilename" = "@items('Apply_to_each_Attachment')?['name']"
        "item/qfu_status" = "ready"
        "item/qfu_insertedcount" = "@length(body('Filter_Abnormal_Margin_Rows'))"
        "item/qfu_updatedcount" = 0
        "item/qfu_startedon" = "@utcNow()"
        "item/qfu_completedon" = "@utcNow()"
        "item/qfu_triggerflow" = $FlowName
        "item/qfu_notes" = "Parsed from the SA1300 abnormal margin review sheet."
      }
      host = [ordered]@{
        apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
        operationId = "CreateRecord"
        connectionName = $dataverseConnectionName
      }
    }
    runAfter = [ordered]@{
      Delete_Existing_Abnormal_Margin_Batches = @("Succeeded")
    }
    metadata = [ordered]@{
      operationMetadataId = [guid]::NewGuid().Guid
    }
  }

  $orderedBudgetRootActions = [ordered]@{}
  foreach ($property in $BudgetRootActions.PSObject.Properties) {
    if ($snapshotActionSet.Contains($property.Name)) {
      continue
    }

    $orderedBudgetRootActions[$property.Name] = $property.Value
    if ($property.Name -eq "Guard_Budget_Row_Limit") {
      $orderedBudgetRootActions.Create_Abnormal_Margin_Table = $createAbnormalMarginTable
      $orderedBudgetRootActions.List_Abnormal_Margin_Rows = $listAbnormalMarginRows
      $orderedBudgetRootActions.Filter_Abnormal_Margin_Rows = $filterAbnormalMarginRows
      $orderedBudgetRootActions.List_Existing_Abnormal_Margin_Snapshot = $listExistingAbnormalMarginSnapshot
      $orderedBudgetRootActions.Filter_Existing_Abnormal_Margin_Snapshot = $filterExistingAbnormalMarginSnapshot
      $orderedBudgetRootActions.Delete_Existing_Abnormal_Margin_Snapshot = $deleteExistingAbnormalMarginSnapshot
      $orderedBudgetRootActions.Apply_to_each_Abnormal_Margin_Row = $applyToEachAbnormalMarginRow
      $orderedBudgetRootActions.List_Existing_Abnormal_Margin_Batches = $listExistingAbnormalMarginBatches
      $orderedBudgetRootActions.Filter_Existing_Abnormal_Margin_Batches = $filterExistingAbnormalMarginBatches
      $orderedBudgetRootActions.Delete_Existing_Abnormal_Margin_Batches = $deleteExistingAbnormalMarginBatches
      $orderedBudgetRootActions.Create_Abnormal_Margin_Batch = $createAbnormalMarginBatch
    }
  }

  $Definition.actions.Apply_to_each_Attachment.actions.Condition_Is_SA1300_File.actions = [pscustomobject]$orderedBudgetRootActions
}

function Add-Sa1300OpsDailyActions {
  param(
    [object]$Definition,
    [object]$BudgetRootActions,
    [object]$Branch
  )

  $excelConnectionName = [string]$BudgetRootActions.Create_Budget_Table.inputs.host.connectionName
  $dataverseConnectionName = [string]$BudgetRootActions.Guard_Budget_Row_Limit.actions.Get_Budget_Goal_From_Archives.inputs.host.connectionName
  $currentBudgetSourceIdExpr = "concat(parameters('qfu_QFU_BranchCode'), '|SA1300|', formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'yyyy-MM'))"
  $sameMonthActualRollbackBody = "and(equals(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_sourceid'], $currentBudgetSourceIdExpr), greater(float(coalesce(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_actualsales'], 0)), float(coalesce(variables('TotalSales'), 0))))"
  $incomingCadOpsDailyBody = "string(coalesce(body('Filter_CAD_Ops_Daily_Rows'), json('[]')))"
  $incomingUsdOpsDailyBody = "string(coalesce(outputs('Filter_USD_Ops_Daily_Rows')?['body'], json('[]')))"
  $preservedCadOpsDailyExpr = "@if($sameMonthActualRollbackBody, coalesce(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_opsdailycadjson'], string(json('[]'))), $incomingCadOpsDailyBody)"
  $preservedUsdOpsDailyExpr = "@if($sameMonthActualRollbackBody, coalesce(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_opsdailyusdjson'], string(json('[]'))), $incomingUsdOpsDailyBody)"
  $usdDateIsoExpr = "if(or(contains(string(items('Apply_to_each_USD_Ops_Daily_Row')?['Billing Day']), '-'), contains(string(items('Apply_to_each_USD_Ops_Daily_Row')?['Billing Day']), '/')), formatDateTime(items('Apply_to_each_USD_Ops_Daily_Row')?['Billing Day'], 'yyyy-MM-dd'), formatDateTime(addDays('1899-12-30', int(float(items('Apply_to_each_USD_Ops_Daily_Row')?['Billing Day']))), 'yyyy-MM-dd'))"
  $usdDateKeyExpr = "if(or(contains(string(items('Apply_to_each_USD_Ops_Daily_Row')?['Billing Day']), '-'), contains(string(items('Apply_to_each_USD_Ops_Daily_Row')?['Billing Day']), '/')), formatDateTime(items('Apply_to_each_USD_Ops_Daily_Row')?['Billing Day'], 'yyyyMMdd'), formatDateTime(addDays('1899-12-30', int(float(items('Apply_to_each_USD_Ops_Daily_Row')?['Billing Day']))), 'yyyyMMdd'))"
  $usdDateDayExpr = "if(or(contains(string(items('Apply_to_each_USD_Ops_Daily_Row')?['Billing Day']), '-'), contains(string(items('Apply_to_each_USD_Ops_Daily_Row')?['Billing Day']), '/')), int(formatDateTime(items('Apply_to_each_USD_Ops_Daily_Row')?['Billing Day'], 'dd')), int(formatDateTime(addDays('1899-12-30', int(float(items('Apply_to_each_USD_Ops_Daily_Row')?['Billing Day']))), 'dd')))"
  $cadDateIsoExpr = "if(or(contains(string(items('Apply_to_each_CAD_Ops_Daily_Row')?['Billing Day']), '-'), contains(string(items('Apply_to_each_CAD_Ops_Daily_Row')?['Billing Day']), '/')), formatDateTime(items('Apply_to_each_CAD_Ops_Daily_Row')?['Billing Day'], 'yyyy-MM-dd'), formatDateTime(addDays('1899-12-30', int(float(items('Apply_to_each_CAD_Ops_Daily_Row')?['Billing Day']))), 'yyyy-MM-dd'))"
  $cadDateKeyExpr = "if(or(contains(string(items('Apply_to_each_CAD_Ops_Daily_Row')?['Billing Day']), '-'), contains(string(items('Apply_to_each_CAD_Ops_Daily_Row')?['Billing Day']), '/')), formatDateTime(items('Apply_to_each_CAD_Ops_Daily_Row')?['Billing Day'], 'yyyyMMdd'), formatDateTime(addDays('1899-12-30', int(float(items('Apply_to_each_CAD_Ops_Daily_Row')?['Billing Day']))), 'yyyyMMdd'))"
  $cadDateDayExpr = "if(or(contains(string(items('Apply_to_each_CAD_Ops_Daily_Row')?['Billing Day']), '-'), contains(string(items('Apply_to_each_CAD_Ops_Daily_Row')?['Billing Day']), '/')), int(formatDateTime(items('Apply_to_each_CAD_Ops_Daily_Row')?['Billing Day'], 'dd')), int(formatDateTime(addDays('1899-12-30', int(float(items('Apply_to_each_CAD_Ops_Daily_Row')?['Billing Day']))), 'dd')))"
  $usdOpsDailyRange = if ($Branch -and $Branch.PSObject.Properties["UsdOpsDailyRange"] -and -not [string]::IsNullOrWhiteSpace([string]$Branch.UsdOpsDailyRange)) {
    [string]$Branch.UsdOpsDailyRange
  } else {
    $null
  }
  $hasUsdOpsDailyRange = -not [string]::IsNullOrWhiteSpace($usdOpsDailyRange)
  $cadOpsDailyRange = if ($Branch -and $Branch.PSObject.Properties["CadOpsDailyRange"] -and -not [string]::IsNullOrWhiteSpace([string]$Branch.CadOpsDailyRange)) {
    [string]$Branch.CadOpsDailyRange
  } else {
    "'Daily Sales- Location'!H2:M500"
  }

  $createUsdOpsTable = [ordered]@{
    type = "OpenApiConnection"
    description = "Create a temporary Excel table over the USD Daily Sales- Location block."
    inputs = [ordered]@{
      parameters = [ordered]@{
        source = "me"
        drive = "@parameters('qfu_QFU_OneDriveDriveId')"
        file = "@variables('FileID')"
        "table/Range" = $usdOpsDailyRange
      }
      host = [ordered]@{
        apiId = "/providers/Microsoft.PowerApps/apis/shared_excelonlinebusiness"
        operationId = "CreateTable"
        connectionName = $excelConnectionName
      }
    }
    runAfter = [ordered]@{
      Create_Abnormal_Margin_Batch = @("Succeeded")
    }
    metadata = [ordered]@{
      operationMetadataId = [guid]::NewGuid().Guid
    }
  }

  $listUsdOpsRows = [ordered]@{
    type = "OpenApiConnection"
    description = "Read USD Daily Sales- Location rows from the temporary Excel table."
    inputs = [ordered]@{
      parameters = [ordered]@{
        source = "me"
        drive = "@parameters('qfu_QFU_OneDriveDriveId')"
        file = "@variables('FileID')"
        table = "@coalesce(body('Create_USD_Ops_Daily_Table')?['name'], body('Create_USD_Ops_Daily_Table')?['id'], body('Create_USD_Ops_Daily_Table')?['Id'])"
      }
      host = [ordered]@{
        apiId = "/providers/Microsoft.PowerApps/apis/shared_excelonlinebusiness"
        operationId = "GetItems"
        connectionName = $excelConnectionName
      }
    }
    runAfter = [ordered]@{
      Create_USD_Ops_Daily_Table = @("Succeeded")
    }
    metadata = [ordered]@{
      operationMetadataId = [guid]::NewGuid().Guid
    }
  }

  $filterUsdOpsRows = if ($hasUsdOpsDailyRange) {
    [ordered]@{
      type = "Query"
      description = "Keep only USD Daily Sales- Location rows for the current branch or total row."
      inputs = [ordered]@{
        from = "@coalesce(outputs('List_USD_Ops_Daily_Rows')?['body/value'], json('[]'))"
        where = "@and(not(empty(item()?['Billing Day'])), not(empty(item()?['On-Time Delivery'])), or(equals(string(item()?['Location']), parameters('qfu_QFU_BranchCode')), equals(string(item()?['Billing Day']), 'Total')))"
      }
      runAfter = [ordered]@{
        List_USD_Ops_Daily_Rows = @("Succeeded")
      }
    }
  } else {
    [ordered]@{
      type = "Query"
      description = "Emit an explicit empty USD Daily Sales- Location payload when this branch workbook is CAD-only."
      inputs = [ordered]@{
        from = "@json('[]')"
        where = "@equals(1, 2)"
      }
      runAfter = [ordered]@{
        Create_Abnormal_Margin_Batch = @("Succeeded")
      }
    }
  }

  $createCadOpsTable = [ordered]@{
    type = "OpenApiConnection"
    description = "Create a temporary Excel table over the configured CAD Daily Sales- Location block."
    inputs = [ordered]@{
      parameters = [ordered]@{
        source = "me"
        drive = "@parameters('qfu_QFU_OneDriveDriveId')"
        file = "@variables('FileID')"
        "table/Range" = $cadOpsDailyRange
      }
      host = [ordered]@{
        apiId = "/providers/Microsoft.PowerApps/apis/shared_excelonlinebusiness"
        operationId = "CreateTable"
        connectionName = $excelConnectionName
      }
    }
    runAfter = [ordered]@{
      Filter_USD_Ops_Daily_Rows = @("Succeeded")
    }
    metadata = [ordered]@{
      operationMetadataId = [guid]::NewGuid().Guid
    }
  }

  $listCadOpsRows = [ordered]@{
    type = "OpenApiConnection"
    description = "Read CAD Daily Sales- Location rows from the temporary Excel table."
    inputs = [ordered]@{
      parameters = [ordered]@{
        source = "me"
        drive = "@parameters('qfu_QFU_OneDriveDriveId')"
        file = "@variables('FileID')"
        table = "@coalesce(body('Create_CAD_Ops_Daily_Table')?['name'], body('Create_CAD_Ops_Daily_Table')?['id'], body('Create_CAD_Ops_Daily_Table')?['Id'])"
      }
      host = [ordered]@{
        apiId = "/providers/Microsoft.PowerApps/apis/shared_excelonlinebusiness"
        operationId = "GetItems"
        connectionName = $excelConnectionName
      }
    }
    runAfter = [ordered]@{
      Create_CAD_Ops_Daily_Table = @("Succeeded")
    }
    metadata = [ordered]@{
      operationMetadataId = [guid]::NewGuid().Guid
    }
  }

  $filterCadOpsRows = [ordered]@{
    type = "Query"
    description = "Keep only CAD Daily Sales- Location rows for the current branch or total row."
    inputs = [ordered]@{
      from = "@coalesce(outputs('List_CAD_Ops_Daily_Rows')?['body/value'], json('[]'))"
      where = "@and(not(empty(item()?['Billing Day'])), not(empty(item()?['On-Time Delivery'])), or(equals(string(item()?['Location']), parameters('qfu_QFU_BranchCode')), equals(string(item()?['Billing Day']), 'Total')))"
    }
    runAfter = [ordered]@{
      List_CAD_Ops_Daily_Rows = @("Succeeded")
    }
  }

  $listExistingOpsDaily = [ordered]@{
    type = "OpenApiConnection"
    description = "Get existing branch ops daily rows so the latest SA1300 snapshot replaces them."
    inputs = [ordered]@{
      parameters = [ordered]@{
        entityName = "qfu_branchopsdailies"
        '$select' = "qfu_branchopsdailyid"
        '$filter' = "qfu_branchcode eq '@{parameters('qfu_QFU_BranchCode')}' and qfu_sourcefamily eq 'SA1300-OPSDAILY'"
      }
      host = [ordered]@{
        apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
        operationId = "ListRecords"
        connectionName = $dataverseConnectionName
      }
    }
    runAfter = [ordered]@{
      Filter_CAD_Ops_Daily_Rows = @("Succeeded")
    }
    metadata = [ordered]@{
      operationMetadataId = [guid]::NewGuid().Guid
    }
  }

  $deleteExistingOpsDaily = [ordered]@{
    type = "Foreach"
    description = "Delete prior branch ops daily rows before loading the latest SA1300 snapshot."
    foreach = "@if($sameMonthActualRollbackBody, json('[]'), coalesce(outputs('List_Existing_Branch_Ops_Daily')?['body/value'], json('[]')))"
    actions = [ordered]@{
      Delete_Branch_Ops_Daily_Record = [ordered]@{
        type = "OpenApiConnection"
        inputs = [ordered]@{
          parameters = [ordered]@{
            entityName = "qfu_branchopsdailies"
            recordId = "@items('Delete_Existing_Branch_Ops_Daily')?['qfu_branchopsdailyid']"
          }
          host = [ordered]@{
            apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
            operationId = "DeleteRecord"
            connectionName = $dataverseConnectionName
          }
        }
        runAfter = [ordered]@{}
        metadata = [ordered]@{
          operationMetadataId = [guid]::NewGuid().Guid
        }
      }
    }
    runAfter = [ordered]@{
      List_Existing_Branch_Ops_Daily = @("Succeeded")
    }
    metadata = [ordered]@{
      operationMetadataId = [guid]::NewGuid().Guid
    }
  }

  $applyUsdOpsRows = [ordered]@{
    type = "Foreach"
    description = "Create USD branch ops daily rows from the SA1300 workbook."
    foreach = "@if($sameMonthActualRollbackBody, json('[]'), coalesce(body('Filter_USD_Ops_Daily_Rows'), json('[]')))"
    actions = [ordered]@{
      Create_USD_Branch_Ops_Daily_Record = [ordered]@{
        type = "OpenApiConnection"
        inputs = [ordered]@{
          parameters = [ordered]@{
            entityName = "qfu_branchopsdailies"
            "item/qfu_name" = "@concat(parameters('qfu_QFU_BranchCode'), ' Ops Daily USD ', if(equals(string(items('Apply_to_each_USD_Ops_Daily_Row')?['Billing Day']), 'Total'), 'Total', $usdDateIsoExpr))"
            "item/qfu_sourceid" = "@concat(parameters('qfu_QFU_BranchCode'), '|SA1300-OPSDAILY|', variables('SA1300SnapshotDate'), '|USD|', if(equals(string(items('Apply_to_each_USD_Ops_Daily_Row')?['Billing Day']), 'Total'), 'total', $usdDateKeyExpr))"
            "item/qfu_branchcode" = "@parameters('qfu_QFU_BranchCode')"
            "item/qfu_branchslug" = "@parameters('qfu_QFU_BranchSlug')"
            "item/qfu_regionslug" = "@parameters('qfu_QFU_RegionSlug')"
            "item/qfu_sourcefamily" = "SA1300-OPSDAILY"
            "item/qfu_sourcefile" = "@items('Apply_to_each_Attachment')?['name']"
            "item/qfu_sourceworksheet" = "Daily Sales- Location"
            "item/qfu_snapshotdate" = "@variables('SA1300SnapshotDate')"
            "item/qfu_billingday" = "@if(equals(string(items('Apply_to_each_USD_Ops_Daily_Row')?['Billing Day']), 'Total'), null, $usdDateIsoExpr)"
            "item/qfu_billinglabel" = "@if(equals(string(items('Apply_to_each_USD_Ops_Daily_Row')?['Billing Day']), 'Total'), 'Total', $usdDateIsoExpr)"
            "item/qfu_istotalrow" = "@equals(string(items('Apply_to_each_USD_Ops_Daily_Row')?['Billing Day']), 'Total')"
            "item/qfu_currencytype" = "USD"
            "item/qfu_sales" = "@float(replace(replace(string(coalesce(items('Apply_to_each_USD_Ops_Daily_Row')?['Sales'], 0)), '$', ''), ',', ''))"
            "item/qfu_gp" = "@float(replace(replace(string(coalesce(items('Apply_to_each_USD_Ops_Daily_Row')?['GP$ (LRMAC)'], 0)), '$', ''), ',', ''))"
            "item/qfu_gppct" = "@mul(float(replace(replace(string(coalesce(items('Apply_to_each_USD_Ops_Daily_Row')?['GP% (LRMAC)'], 0)), '%', ''), ',', '')), 100)"
            "item/qfu_ontimedelivery" = "@mul(float(replace(replace(string(coalesce(items('Apply_to_each_USD_Ops_Daily_Row')?['On-Time Delivery'], 0)), '%', ''), ',', '')), 100)"
            "item/qfu_sortorder" = "@if(equals(string(items('Apply_to_each_USD_Ops_Daily_Row')?['Billing Day']), 'Total'), 999, $usdDateDayExpr)"
          }
          host = [ordered]@{
            apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
            operationId = "CreateRecord"
            connectionName = $dataverseConnectionName
          }
        }
        runAfter = [ordered]@{}
        metadata = [ordered]@{
          operationMetadataId = [guid]::NewGuid().Guid
        }
      }
    }
    runAfter = [ordered]@{
      Delete_Existing_Branch_Ops_Daily = @("Succeeded")
    }
    metadata = [ordered]@{
      operationMetadataId = [guid]::NewGuid().Guid
    }
  }

  $applyCadOpsRows = [ordered]@{
    type = "Foreach"
    description = "Create CAD branch ops daily rows from the SA1300 workbook."
    foreach = "@if($sameMonthActualRollbackBody, json('[]'), coalesce(body('Filter_CAD_Ops_Daily_Rows'), json('[]')))"
    actions = [ordered]@{
      Create_CAD_Branch_Ops_Daily_Record = [ordered]@{
        type = "OpenApiConnection"
        inputs = [ordered]@{
          parameters = [ordered]@{
            entityName = "qfu_branchopsdailies"
            "item/qfu_name" = "@concat(parameters('qfu_QFU_BranchCode'), ' Ops Daily CAD ', if(equals(string(items('Apply_to_each_CAD_Ops_Daily_Row')?['Billing Day']), 'Total'), 'Total', $cadDateIsoExpr))"
            "item/qfu_sourceid" = "@concat(parameters('qfu_QFU_BranchCode'), '|SA1300-OPSDAILY|', variables('SA1300SnapshotDate'), '|CAD|', if(equals(string(items('Apply_to_each_CAD_Ops_Daily_Row')?['Billing Day']), 'Total'), 'total', $cadDateKeyExpr))"
            "item/qfu_branchcode" = "@parameters('qfu_QFU_BranchCode')"
            "item/qfu_branchslug" = "@parameters('qfu_QFU_BranchSlug')"
            "item/qfu_regionslug" = "@parameters('qfu_QFU_RegionSlug')"
            "item/qfu_sourcefamily" = "SA1300-OPSDAILY"
            "item/qfu_sourcefile" = "@items('Apply_to_each_Attachment')?['name']"
            "item/qfu_sourceworksheet" = "Daily Sales- Location"
            "item/qfu_snapshotdate" = "@variables('SA1300SnapshotDate')"
            "item/qfu_billingday" = "@if(equals(string(items('Apply_to_each_CAD_Ops_Daily_Row')?['Billing Day']), 'Total'), null, $cadDateIsoExpr)"
            "item/qfu_billinglabel" = "@if(equals(string(items('Apply_to_each_CAD_Ops_Daily_Row')?['Billing Day']), 'Total'), 'Total', $cadDateIsoExpr)"
            "item/qfu_istotalrow" = "@equals(string(items('Apply_to_each_CAD_Ops_Daily_Row')?['Billing Day']), 'Total')"
            "item/qfu_currencytype" = "CAD"
            "item/qfu_sales" = "@float(replace(replace(string(coalesce(items('Apply_to_each_CAD_Ops_Daily_Row')?['Sales'], 0)), '$', ''), ',', ''))"
            "item/qfu_gp" = "@float(replace(replace(string(coalesce(items('Apply_to_each_CAD_Ops_Daily_Row')?['GP$ (LRMAC)'], 0)), '$', ''), ',', ''))"
            "item/qfu_gppct" = "@mul(float(replace(replace(string(coalesce(items('Apply_to_each_CAD_Ops_Daily_Row')?['GP% (LRMAC)'], 0)), '%', ''), ',', '')), 100)"
            "item/qfu_ontimedelivery" = "@mul(float(replace(replace(string(coalesce(items('Apply_to_each_CAD_Ops_Daily_Row')?['On-Time Delivery'], 0)), '%', ''), ',', '')), 100)"
            "item/qfu_sortorder" = "@if(equals(string(items('Apply_to_each_CAD_Ops_Daily_Row')?['Billing Day']), 'Total'), 999, $cadDateDayExpr)"
          }
          host = [ordered]@{
            apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
            operationId = "CreateRecord"
            connectionName = $dataverseConnectionName
          }
        }
        runAfter = [ordered]@{}
        metadata = [ordered]@{
          operationMetadataId = [guid]::NewGuid().Guid
        }
      }
    }
    runAfter = [ordered]@{
      Apply_to_each_USD_Ops_Daily_Row = @("Succeeded", "Skipped")
    }
    metadata = [ordered]@{
      operationMetadataId = [guid]::NewGuid().Guid
    }
  }

  $getCurrentMonthBudgetForAnalytics = [ordered]@{
    type = "OpenApiConnection"
    description = "Get the current month qfu_budget row so analytics can store the latest SA1300 daily payload."
    inputs = [ordered]@{
      parameters = [ordered]@{
        entityName = "qfu_budgets"
        '$select' = "qfu_budgetid"
        '$filter' = "qfu_branchcode eq '@{parameters('qfu_QFU_BranchCode')}' and qfu_sourcefamily eq 'SA1300' and qfu_sourceid eq '@{concat(parameters('qfu_QFU_BranchCode'), '|SA1300|', formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'yyyy-MM'))}' and qfu_fiscalyear eq '@{parameters('qfu_QFU_ActiveFiscalYear')}'"
        '$top' = 1
        '$orderby' = "modifiedon desc, createdon desc"
      }
      host = [ordered]@{
        apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
        operationId = "ListRecords"
        connectionName = $dataverseConnectionName
      }
    }
    runAfter = [ordered]@{
      Filter_CAD_Ops_Daily_Rows = @("Succeeded")
    }
    metadata = [ordered]@{
      operationMetadataId = [guid]::NewGuid().Guid
    }
  }

  $updateCurrentMonthBudgetAnalyticsPayload = [ordered]@{
    type = "OpenApiConnection"
    description = "Store the latest SA1300 daily ops payload on the current qfu_budget row for analytics."
    inputs = [ordered]@{
      parameters = [ordered]@{
        entityName = "qfu_budgets"
        recordId = "@first(outputs('Get_Current_Month_Budget_Record_For_Analytics')?['body/value'])?['qfu_budgetid']"
        item = [ordered]@{
          qfu_opsdailycadjson = $preservedCadOpsDailyExpr
          qfu_opsdailyusdjson = $preservedUsdOpsDailyExpr
        }
      }
      host = [ordered]@{
        apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
        operationId = "UpdateRecord"
        connectionName = $dataverseConnectionName
      }
    }
    runAfter = [ordered]@{}
    metadata = [ordered]@{
      operationMetadataId = [guid]::NewGuid().Guid
    }
  }

  $conditionCurrentMonthBudgetForAnalyticsExists = [ordered]@{
    type = "If"
    expression = [ordered]@{
      greater = @(
        "@length(outputs('Get_Current_Month_Budget_Record_For_Analytics')?['body/value'])",
        0
      )
    }
    actions = [ordered]@{
      Update_Current_Month_Budget_Analytics_Payload = $updateCurrentMonthBudgetAnalyticsPayload
    }
    else = [ordered]@{
      actions = [ordered]@{}
    }
    runAfter = [ordered]@{
      Get_Current_Month_Budget_Record_For_Analytics = @("Succeeded")
    }
    metadata = [ordered]@{
      operationMetadataId = [guid]::NewGuid().Guid
    }
  }

  $orderedBudgetRootActions = [ordered]@{}
  foreach ($property in $BudgetRootActions.PSObject.Properties) {
    $orderedBudgetRootActions[$property.Name] = $property.Value
    if ($property.Name -eq "Create_Abnormal_Margin_Batch") {
      if ($hasUsdOpsDailyRange) {
        $orderedBudgetRootActions.Create_USD_Ops_Daily_Table = $createUsdOpsTable
        $orderedBudgetRootActions.List_USD_Ops_Daily_Rows = $listUsdOpsRows
      }
      $orderedBudgetRootActions.Filter_USD_Ops_Daily_Rows = $filterUsdOpsRows
      $orderedBudgetRootActions.Create_CAD_Ops_Daily_Table = $createCadOpsTable
      $orderedBudgetRootActions.List_CAD_Ops_Daily_Rows = $listCadOpsRows
      $orderedBudgetRootActions.Filter_CAD_Ops_Daily_Rows = $filterCadOpsRows
      $orderedBudgetRootActions.List_Existing_Branch_Ops_Daily = $listExistingOpsDaily
      $orderedBudgetRootActions.Delete_Existing_Branch_Ops_Daily = $deleteExistingOpsDaily
      $orderedBudgetRootActions.Apply_to_each_USD_Ops_Daily_Row = $applyUsdOpsRows
      $orderedBudgetRootActions.Apply_to_each_CAD_Ops_Daily_Row = $applyCadOpsRows
      $orderedBudgetRootActions.Get_Current_Month_Budget_Record_For_Analytics = $getCurrentMonthBudgetForAnalytics
      $orderedBudgetRootActions.Condition_Current_Month_Budget_Record_For_Analytics_Exists = $conditionCurrentMonthBudgetForAnalyticsExists
    }
  }

  $Definition.actions.Apply_to_each_Attachment.actions.Condition_Is_SA1300_File.actions = [pscustomobject]$orderedBudgetRootActions
}

function Update-QuoteFlow {
  param(
    [object]$Json,
    [object]$Branch,
    [object]$Template,
    [System.Collections.Generic.List[string]]$Notes
  )

  $definition = $Json.properties.definition
  Add-BranchParameters -Definition $definition -Branch $Branch -Template $Template
  Set-TemplateTrigger `
    -Definition $definition `
    -Branch $Branch `
    -Template $Template `
    -SharedMailboxDescription "Triggers when a new SP830CA workbook lands in the $($Branch.BranchCode) $($Branch.BranchName) shared mailbox." `
    -PrimaryInboxDescription "Triggers when a new SP830CA workbook lands in the primary inbox for $($Branch.BranchCode) $($Branch.BranchName)."

  $existingTopLevelActions = $definition.actions
  $definition.actions = [pscustomobject]([ordered]@{
      Initialize_CurrentQuoteGUID = $existingTopLevelActions.Initialize_CurrentQuoteGUID
      Initialize_QuoteSnapshotProcessedOn = [ordered]@{
        type = "InitializeVariable"
        inputs = [ordered]@{
          variables = @(
            [ordered]@{
              name = "QuoteSnapshotProcessedOn"
              type = "string"
              value = ""
            }
          )
        }
        runAfter = [ordered]@{
          Initialize_CurrentQuoteGUID = @("Succeeded")
        }
        metadata = [ordered]@{
          operationMetadataId = [guid]::NewGuid().Guid
        }
      }
      Initialize_QuoteImportBatchId = [ordered]@{
        type = "InitializeVariable"
        inputs = [ordered]@{
          variables = @(
            [ordered]@{
              name = "QuoteImportBatchId"
              type = "string"
              value = ""
            }
          )
        }
        runAfter = [ordered]@{
          Initialize_QuoteSnapshotProcessedOn = @("Succeeded")
        }
        metadata = [ordered]@{
          operationMetadataId = [guid]::NewGuid().Guid
        }
      }
      Initialize_CurrentQuoteSnapshotKeys = [ordered]@{
        type = "InitializeVariable"
        inputs = [ordered]@{
          variables = @(
            [ordered]@{
              name = "CurrentQuoteSnapshotKeys"
              type = "array"
              value = "@json('[]')"
            }
          )
        }
        runAfter = [ordered]@{
          Initialize_QuoteImportBatchId = @("Succeeded")
        }
        metadata = [ordered]@{
          operationMetadataId = [guid]::NewGuid().Guid
        }
      }
      Check_if_weekday = $existingTopLevelActions.Check_if_weekday
    })
  $definition.actions.Check_if_weekday.runAfter = [ordered]@{
    Initialize_CurrentQuoteSnapshotKeys = @("Succeeded")
  }

  $attachmentActions = $definition.actions.Check_if_weekday.actions.Apply_to_each_attachment.actions
  $quoteActions = $attachmentActions.Condition_Is_SP830CA_File.actions
  $lineActions = $quoteActions.Guard_Quote_Rows.actions.Apply_to_each_quote_line.actions
  $quoteActions.Create_attachment_file.inputs.parameters.name = "@concat(parameters('qfu_QFU_BranchCode'), '_QuoteFollowUp_', formatDateTime(utcNow(), 'yyyyMMdd_HHmmss'), '_', items('Apply_to_each_attachment')?['name'])"
  Set-FieldValue -Map $quoteActions -Name "Set_QuoteSnapshotProcessedOn" -Value ([pscustomobject]([ordered]@{
        type = "SetVariable"
        description = "Capture one snapshot timestamp for the current SP830CA attachment."
        inputs = [ordered]@{
          name = "QuoteSnapshotProcessedOn"
          value = "@utcNow()"
        }
        runAfter = [ordered]@{
          Create_attachment_file = @("Succeeded")
        }
        metadata = [ordered]@{
          operationMetadataId = [guid]::NewGuid().Guid
        }
      }))
  Set-FieldValue -Map $quoteActions -Name "Set_QuoteImportBatchId" -Value ([pscustomobject]([ordered]@{
        type = "SetVariable"
        description = "Capture one import batch id for the current SP830CA attachment."
        inputs = [ordered]@{
          name = "QuoteImportBatchId"
          value = "@guid()"
        }
        runAfter = [ordered]@{
          Set_QuoteSnapshotProcessedOn = @("Succeeded")
        }
        metadata = [ordered]@{
          operationMetadataId = [guid]::NewGuid().Guid
        }
      }))
  Set-FieldValue -Map $quoteActions -Name "Reset_CurrentQuoteSnapshotKeys" -Value ([pscustomobject]([ordered]@{
        type = "SetVariable"
        description = "Reset the quote snapshot key bag for the current attachment."
        inputs = [ordered]@{
          name = "CurrentQuoteSnapshotKeys"
          value = "@json('[]')"
        }
        runAfter = [ordered]@{
          Set_QuoteImportBatchId = @("Succeeded")
        }
        metadata = [ordered]@{
          operationMetadataId = [guid]::NewGuid().Guid
        }
      }))
  $quoteActions.Delay_For_File_Sync.runAfter = [ordered]@{
    Reset_CurrentQuoteSnapshotKeys = @("Succeeded")
  }

  $quoteActions.Guard_Quote_Rows.expression = "@greaterOrEquals(length(coalesce(body('Filter_Quote_Rows'), createArray())), 0)"
  $quoteLineSourceIdExpression = "@concat(parameters('qfu_QFU_BranchCode'), '|SP830CA|', items('Apply_to_each_quote_line')?['quotenumber'], '|', items('Apply_to_each_quote_line')?['linenumber'])"
  $lineActions.Compose_UniqueKey.inputs = "@concat(items('Apply_to_each_quote_line')?['quotenumber'], '_', items('Apply_to_each_quote_line')?['linenumber'])"
  Set-FieldValue -Map $lineActions -Name "Append_Quote_SourceId" -Value ([pscustomobject]([ordered]@{
        type = "AppendToArrayVariable"
        inputs = [ordered]@{
          name = "CurrentQuoteSnapshotKeys"
          value = "@concat(parameters('qfu_QFU_BranchCode'), '|SP830CA|', items('Apply_to_each_quote_line')?['quotenumber'])"
        }
        runAfter = [ordered]@{
          Compose_UniqueKey = @("Succeeded")
        }
      }))
  $lineActions.Determine_Status_Code.inputs = "@if(greater(coalesce(items('Apply_to_each_quote_line')?['convertedquote'], 0), 0), 2, if(or(contains(toLower(string(coalesce(items('Apply_to_each_quote_line')?['status'], ''))), 'loss'), contains(toLower(string(coalesce(items('Apply_to_each_quote_line')?['status'], ''))), 'lost'), not(empty(items('Apply_to_each_quote_line')?['rejectionreason']))), 3, 1))"
  $lineActions.Determine_Status_Code.description = "If converted quote dollars are present the quote is won; if the workbook says lost or rejected the quote is closed-lost; otherwise it stays open."
  $lineActions.Determine_Status_Code.runAfter = [ordered]@{
    Append_Quote_SourceId = @("Succeeded")
  }
  $checkQuoteParameters = Copy-OrderedMap $lineActions.Check_Quote_Exists.inputs.parameters
  Set-FieldValue -Map $checkQuoteParameters -Name '$select' -Value "qfu_quoteid,statecode,statuscode"
  Set-FieldValue -Map $checkQuoteParameters -Name '$top' -Value 1
  Set-FieldValue -Map $checkQuoteParameters -Name '$orderby' -Value "modifiedon desc, createdon desc"
  Set-FieldValue -Map $checkQuoteParameters -Name '$filter' -Value "qfu_sourceid eq '@{concat(parameters('qfu_QFU_BranchCode'), '|SP830CA|', items('Apply_to_each_quote_line')?['quotenumber'])}' and (qfu_active eq true or qfu_active eq null)"
  $lineActions.Check_Quote_Exists.inputs.parameters = [pscustomobject]$checkQuoteParameters
  $resolveQuoteParameters = Copy-OrderedMap $lineActions.Resolve_Quote_For_Line.inputs.parameters
  Set-FieldValue -Map $resolveQuoteParameters -Name '$top' -Value 1
  Set-FieldValue -Map $resolveQuoteParameters -Name '$orderby' -Value "modifiedon desc, createdon desc"
  Set-FieldValue -Map $resolveQuoteParameters -Name '$filter' -Value "qfu_sourceid eq '@{concat(parameters('qfu_QFU_BranchCode'), '|SP830CA|', items('Apply_to_each_quote_line')?['quotenumber'])}' and (qfu_active eq true or qfu_active eq null)"
  $lineActions.Resolve_Quote_For_Line.inputs.parameters = [pscustomobject]$resolveQuoteParameters
  $checkLineParameters = Copy-OrderedMap $lineActions.Check_Line_Exists.inputs.parameters
  Set-FieldValue -Map $checkLineParameters -Name '$select' -Value "qfu_quotelineid,qfu_sourceid,qfu_uniquekey"
  Set-FieldValue -Map $checkLineParameters -Name '$top' -Value 1
  Set-FieldValue -Map $checkLineParameters -Name '$orderby' -Value "modifiedon desc, createdon desc"
  Set-FieldValue -Map $checkLineParameters -Name '$filter' -Value "qfu_sourceid eq '@{concat(parameters('qfu_QFU_BranchCode'), '|SP830CA|', items('Apply_to_each_quote_line')?['quotenumber'], '|', items('Apply_to_each_quote_line')?['linenumber'])}'"
  $lineActions.Check_Line_Exists.inputs.parameters = [pscustomobject]$checkLineParameters

  $updateHeader = Copy-OrderedMap $lineActions.Condition_Quote_Exists.actions.Update_Quote_Header.inputs.parameters
  Set-FieldValue -Map $updateHeader -Name "item/qfu_name" -Value "@concat(parameters('qfu_QFU_BranchCode'), ' ', items('Apply_to_each_quote_line')?['quotenumber'])"
  Set-FieldValue -Map $updateHeader -Name "item/qfu_sourceid" -Value "@concat(parameters('qfu_QFU_BranchCode'), '|SP830CA|', items('Apply_to_each_quote_line')?['quotenumber'])"
  Set-FieldValue -Map $updateHeader -Name "item/qfu_branchcode" -Value "@parameters('qfu_QFU_BranchCode')"
  Set-FieldValue -Map $updateHeader -Name "item/qfu_branchslug" -Value "@parameters('qfu_QFU_BranchSlug')"
  Set-FieldValue -Map $updateHeader -Name "item/qfu_regionslug" -Value "@parameters('qfu_QFU_RegionSlug')"
  Set-FieldValue -Map $updateHeader -Name "item/qfu_sourcefamily" -Value "SP830CA"
  Set-FieldValue -Map $updateHeader -Name "item/qfu_sourcefile" -Value "@items('Apply_to_each_attachment')?['name']"
  Set-FieldValue -Map $updateHeader -Name "item/qfu_sourceworksheet" -Value "Daily"
  Set-FieldValue -Map $updateHeader -Name "item/qfu_importbatchid" -Value "@variables('QuoteImportBatchId')"
  Set-FieldValue -Map $updateHeader -Name "item/qfu_active" -Value $true
  Set-FieldValue -Map $updateHeader -Name "item/qfu_inactiveon" -Value $null
  Set-FieldValue -Map $updateHeader -Name "item/qfu_lastseenon" -Value "@variables('QuoteSnapshotProcessedOn')"
  Set-FieldValue -Map $updateHeader -Name "item/qfu_closedon" -Value "@if(greaterOrEquals(int(outputs('Determine_Status_Code')), 2), variables('QuoteSnapshotProcessedOn'), null)"
  Set-FieldValue -Map $updateHeader -Name "item/qfu_cssr" -Value "@if(equals(items('Apply_to_each_quote_line')?['cssr'], null), null, string(items('Apply_to_each_quote_line')?['cssr']))"
  Set-FieldValue -Map $updateHeader -Name "item/qfu_tsr" -Value "@if(equals(items('Apply_to_each_quote_line')?['tsr'], null), null, string(items('Apply_to_each_quote_line')?['tsr']))"
  $lineActions.Condition_Quote_Exists.actions.Update_Quote_Header.inputs.parameters = [pscustomobject]$updateHeader

  $createHeader = Copy-OrderedMap $lineActions.Condition_Quote_Exists.else.actions.Create_Quote_Header.inputs.parameters
  Set-FieldValue -Map $createHeader -Name "item/qfu_name" -Value "@concat(parameters('qfu_QFU_BranchCode'), ' ', items('Apply_to_each_quote_line')?['quotenumber'])"
  Set-FieldValue -Map $createHeader -Name "item/qfu_sourceid" -Value "@concat(parameters('qfu_QFU_BranchCode'), '|SP830CA|', items('Apply_to_each_quote_line')?['quotenumber'])"
  Set-FieldValue -Map $createHeader -Name "item/qfu_branchcode" -Value "@parameters('qfu_QFU_BranchCode')"
  Set-FieldValue -Map $createHeader -Name "item/qfu_branchslug" -Value "@parameters('qfu_QFU_BranchSlug')"
  Set-FieldValue -Map $createHeader -Name "item/qfu_regionslug" -Value "@parameters('qfu_QFU_RegionSlug')"
  Set-FieldValue -Map $createHeader -Name "item/qfu_sourcefamily" -Value "SP830CA"
  Set-FieldValue -Map $createHeader -Name "item/qfu_sourcefile" -Value "@items('Apply_to_each_attachment')?['name']"
  Set-FieldValue -Map $createHeader -Name "item/qfu_sourceworksheet" -Value "Daily"
  Set-FieldValue -Map $createHeader -Name "item/qfu_importbatchid" -Value "@variables('QuoteImportBatchId')"
  Set-FieldValue -Map $createHeader -Name "item/qfu_active" -Value $true
  Set-FieldValue -Map $createHeader -Name "item/qfu_inactiveon" -Value $null
  Set-FieldValue -Map $createHeader -Name "item/qfu_lastseenon" -Value "@variables('QuoteSnapshotProcessedOn')"
  Set-FieldValue -Map $createHeader -Name "item/qfu_closedon" -Value "@if(greaterOrEquals(int(outputs('Determine_Status_Code')), 2), variables('QuoteSnapshotProcessedOn'), null)"
  Set-FieldValue -Map $createHeader -Name "item/qfu_cssr" -Value "@if(equals(items('Apply_to_each_quote_line')?['cssr'], null), null, string(items('Apply_to_each_quote_line')?['cssr']))"
  Set-FieldValue -Map $createHeader -Name "item/qfu_tsr" -Value "@if(equals(items('Apply_to_each_quote_line')?['tsr'], null), null, string(items('Apply_to_each_quote_line')?['tsr']))"
  $lineActions.Condition_Quote_Exists.else.actions.Create_Quote_Header.inputs.parameters = [pscustomobject]$createHeader

  foreach ($actionName in @("Update_Quote_Line", "Create_Quote_Line")) {
    $action = if ($actionName -eq "Update_Quote_Line") { $lineActions.Condition_Line_Exists.actions.Update_Quote_Line } else { $lineActions.Condition_Line_Exists.else.actions.Create_Quote_Line }
    $itemMap = Copy-OrderedMap $action.inputs.parameters
    Remove-PropertyIfPresent -Object $itemMap -Name "item/qfu_quoteid@odata.bind"
    Set-FieldValue -Map $itemMap -Name "item/qfu_name" -Value "@concat(parameters('qfu_QFU_BranchCode'), ' ', items('Apply_to_each_quote_line')?['quotenumber'], ' / ', items('Apply_to_each_quote_line')?['linenumber'])"
    Set-FieldValue -Map $itemMap -Name "item/qfu_sourceid" -Value $quoteLineSourceIdExpression
    Set-FieldValue -Map $itemMap -Name "item/qfu_uniquekey" -Value "@outputs('Compose_UniqueKey')"
    Set-FieldValue -Map $itemMap -Name "item/qfu_quotenumber" -Value "@items('Apply_to_each_quote_line')?['quotenumber']"
    Set-FieldValue -Map $itemMap -Name "item/qfu_linenumber" -Value "@string(items('Apply_to_each_quote_line')?['linenumber'])"
    Set-FieldValue -Map $itemMap -Name "item/qfu_branchcode" -Value "@parameters('qfu_QFU_BranchCode')"
    Set-FieldValue -Map $itemMap -Name "item/qfu_branchslug" -Value "@parameters('qfu_QFU_BranchSlug')"
    Set-FieldValue -Map $itemMap -Name "item/qfu_regionslug" -Value "@parameters('qfu_QFU_RegionSlug')"
    Set-FieldValue -Map $itemMap -Name "item/qfu_sourcefamily" -Value "SP830CA"
    Set-FieldValue -Map $itemMap -Name "item/qfu_sourcefile" -Value "@items('Apply_to_each_attachment')?['name']"
    Set-FieldValue -Map $itemMap -Name "item/qfu_sourceworksheet" -Value "Daily"
    Set-FieldValue -Map $itemMap -Name "item/qfu_importbatchid" -Value "@variables('QuoteImportBatchId')"
    Set-FieldValue -Map $itemMap -Name "item/qfu_lastimportdate" -Value "@variables('QuoteSnapshotProcessedOn')"
    Set-FieldValue -Map $itemMap -Name "item/qfu_sourcedate" -Value "@if(empty(items('Apply_to_each_quote_line')?['sapcreatedon']), null, formatDateTime(items('Apply_to_each_quote_line')?['sapcreatedon'], 'yyyy-MM-dd'))"
    Set-FieldValue -Map $itemMap -Name "item/qfu_cssr" -Value "@if(equals(items('Apply_to_each_quote_line')?['cssr'], null), null, string(items('Apply_to_each_quote_line')?['cssr']))"
    Set-FieldValue -Map $itemMap -Name "item/qfu_tsr" -Value "@if(equals(items('Apply_to_each_quote_line')?['tsr'], null), null, string(items('Apply_to_each_quote_line')?['tsr']))"
    $action.inputs.parameters = [pscustomobject]$itemMap
  }

  Set-FieldValue -Map $quoteActions -Name "List_Existing_Active_Quotes" -Value ([pscustomobject]([ordered]@{
        type = "OpenApiConnection"
        description = "Get active quote headers for this branch so rows absent from the latest workbook can be marked inactive."
        inputs = [ordered]@{
          parameters = [ordered]@{
            entityName = "qfu_quotes"
            '$select' = "qfu_quoteid,qfu_sourceid"
            '$top' = 5000
            '$orderby' = "modifiedon desc, createdon desc"
            '$filter' = "qfu_branchcode eq '@{parameters('qfu_QFU_BranchCode')}' and (qfu_active eq true or qfu_active eq null)"
          }
          host = [ordered]@{
            apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
            operationId = "ListRecords"
            connectionName = "shared_commondataserviceforapps"
          }
        }
        runAfter = [ordered]@{
          Guard_Quote_Rows = @("Succeeded")
        }
        metadata = [ordered]@{
          operationMetadataId = [guid]::NewGuid().Guid
        }
      }))
  Set-FieldValue -Map $quoteActions -Name "Filter_Missing_Active_Quotes" -Value ([pscustomobject]([ordered]@{
        type = "Query"
        description = "Identify quote headers that were active before this workbook but were not seen in the current snapshot."
        inputs = [ordered]@{
          from = "@coalesce(outputs('List_Existing_Active_Quotes')?['body/value'], json('[]'))"
          where = "@not(contains(variables('CurrentQuoteSnapshotKeys'), item()?['qfu_sourceid']))"
        }
        runAfter = [ordered]@{
          List_Existing_Active_Quotes = @("Succeeded")
        }
      }))
  Set-FieldValue -Map $quoteActions -Name "Deactivate_Missing_Quotes" -Value ([pscustomobject]([ordered]@{
        type = "Foreach"
        description = "Mark previously-active quote headers inactive when they are absent from the latest workbook."
        foreach = "@coalesce(body('Filter_Missing_Active_Quotes'), json('[]'))"
        actions = [ordered]@{
          Update_Quote_Inactive = [ordered]@{
            type = "OpenApiConnection"
            inputs = [ordered]@{
              parameters = [ordered]@{
                entityName = "qfu_quotes"
                recordId = "@items('Deactivate_Missing_Quotes')?['qfu_quoteid']"
                "item/qfu_active" = $false
                "item/qfu_inactiveon" = "@variables('QuoteSnapshotProcessedOn')"
              }
              host = [ordered]@{
                apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
                operationId = "UpdateRecord"
                connectionName = "shared_commondataserviceforapps"
              }
            }
            metadata = [ordered]@{
              operationMetadataId = [guid]::NewGuid().Guid
            }
          }
        }
        runAfter = [ordered]@{
          Filter_Missing_Active_Quotes = @("Succeeded")
        }
        metadata = [ordered]@{
          operationMetadataId = [guid]::NewGuid().Guid
        }
      }))

  $quoteBatchActions = New-IngestionBatchSyncActionSet `
    -ActionPrefix "Quote" `
    -ImportNameSuffix "Quote Workbook Import" `
    -SourceFamily "SP830CA" `
    -FlowNameExpression "@concat(parameters('qfu_QFU_BranchCode'), '-QuoteFollowUp-Import-Staging')" `
    -FileNameExpression "@items('Apply_to_each_attachment')?['name']" `
    -StartedOnExpression "@variables('QuoteSnapshotProcessedOn')" `
    -RunAfter ([ordered]@{
        Deactivate_Missing_Quotes = @("Succeeded", "Skipped")
        Set_QuoteImportBatchId = @("Succeeded")
      })
  Set-FieldValue -Map $quoteActions -Name $quoteBatchActions.ListActionName -Value $quoteBatchActions.ListAction
  Set-FieldValue -Map $quoteActions -Name $quoteBatchActions.ConditionActionName -Value $quoteBatchActions.ConditionAction

  Add-Note -Notes $Notes -Text "Quote flow now enforces trigger concurrency = 1, stamps a branch-scoped import batch id on headers and lines, treats qfu_quote as current-state with qfu_active/qfu_inactiveon/qfu_lastseenon, uses qfu_quote line source ids in the canonical branch|SP830CA|quote|line format, closes lost/rejected rows explicitly, marks previously-active headers inactive when they disappear from the latest SP830CA workbook, and refreshes the stable qfu_ingestionbatch freshness row that analytics reads."
}

function Update-BackorderFlow {
  param(
    [object]$Json,
    [object]$Branch,
    [object]$Template,
    [System.Collections.Generic.List[string]]$Notes
  )

  $definition = $Json.properties.definition
  Add-BranchParameters -Definition $definition -Branch $Branch -Template $Template
  Set-TemplateTrigger `
    -Definition $definition `
    -Branch $Branch `
    -Template $Template `
    -SharedMailboxDescription "Triggers when a new ZBO workbook lands in the $($Branch.BranchCode) $($Branch.BranchName) shared mailbox." `
    -PrimaryInboxDescription "Triggers when a new ZBO workbook lands in the primary inbox for $($Branch.BranchCode) $($Branch.BranchName)."

  $topLevelActions = $definition.actions
  Set-FieldValue -Map $topLevelActions -Name "Initialize_DeliverySnapshotProcessedOn" -Value ([pscustomobject]([ordered]@{
        type = "InitializeVariable"
        inputs = [ordered]@{
          variables = @(
            [ordered]@{
              name = "DeliverySnapshotProcessedOn"
              type = "string"
              value = ""
            }
          )
        }
        runAfter = [ordered]@{
          Initialize_FilePath = @("Succeeded")
        }
        metadata = [ordered]@{
          operationMetadataId = [guid]::NewGuid().Guid
        }
      }))
  Set-FieldValue -Map $topLevelActions -Name "Initialize_DeliveryImportBatchId" -Value ([pscustomobject]([ordered]@{
        type = "InitializeVariable"
        inputs = [ordered]@{
          variables = @(
            [ordered]@{
              name = "DeliveryImportBatchId"
              type = "string"
              value = ""
            }
          )
        }
        runAfter = [ordered]@{
          Initialize_DeliverySnapshotProcessedOn = @("Succeeded")
        }
        metadata = [ordered]@{
          operationMetadataId = [guid]::NewGuid().Guid
        }
      }))
  Set-FieldValue -Map $topLevelActions -Name "Initialize_CurrentDeliverySnapshotKeys" -Value ([pscustomobject]([ordered]@{
        type = "InitializeVariable"
        inputs = [ordered]@{
          variables = @(
            [ordered]@{
              name = "CurrentDeliverySnapshotKeys"
              type = "array"
              value = "@json('[]')"
            }
          )
        }
        runAfter = [ordered]@{
          Initialize_DeliveryImportBatchId = @("Succeeded")
        }
        metadata = [ordered]@{
          operationMetadataId = [guid]::NewGuid().Guid
        }
      }))
  Set-FieldValue -Map $topLevelActions -Name "Initialize_CurrentBackorderSnapshotKeys" -Value ([pscustomobject]([ordered]@{
        type = "InitializeVariable"
        inputs = [ordered]@{
          variables = @(
            [ordered]@{
              name = "CurrentBackorderSnapshotKeys"
              type = "array"
              value = "@json('[]')"
            }
          )
        }
        runAfter = [ordered]@{
          Initialize_CurrentDeliverySnapshotKeys = @("Succeeded")
        }
        metadata = [ordered]@{
          operationMetadataId = [guid]::NewGuid().Guid
        }
      }))
  $definition.actions.Apply_to_each_Attachment.runAfter = [ordered]@{
    Initialize_CurrentBackorderSnapshotKeys = @("Succeeded")
  }

  $conditionActions = $definition.actions.Apply_to_each_Attachment.actions.Condition_Is_CA_ZBO_File.actions
  $definition.actions.Apply_to_each_Attachment.actions.Condition_Is_CA_ZBO_File.expression = [ordered]@{
    or = @(
      [ordered]@{
        contains = @(
          "@toLower(coalesce(items('Apply_to_each_Attachment')?['name'], ''))",
          "zbo"
        )
      },
      [ordered]@{
        contains = @(
          "@toLower(coalesce(items('Apply_to_each_Attachment')?['name'], ''))",
          "backorder"
        )
      }
    )
  }
  $conditionActions.Create_File_in_OneDrive.inputs.parameters.name = "@concat(parameters('qfu_QFU_BranchCode'), '_ZBO_', formatDateTime(utcNow(), 'yyyyMMdd_HHmmss'), '_', items('Apply_to_each_Attachment')?['name'])"

  Set-FieldValue -Map $conditionActions -Name "Set_DeliverySnapshotProcessedOn" -Value ([pscustomobject]([ordered]@{
        type = "SetVariable"
        description = "Capture one snapshot timestamp for delivery not PGI sync."
        inputs = [ordered]@{
          name = "DeliverySnapshotProcessedOn"
          value = "@utcNow()"
        }
        runAfter = [ordered]@{
          Set_FilePath = @("Succeeded")
        }
        metadata = [ordered]@{
          operationMetadataId = [guid]::NewGuid().Guid
        }
      }))
  Set-FieldValue -Map $conditionActions -Name "Set_DeliveryImportBatchId" -Value ([pscustomobject]([ordered]@{
        type = "SetVariable"
        description = "Capture one import batch id for delivery not PGI sync."
        inputs = [ordered]@{
          name = "DeliveryImportBatchId"
          value = "@guid()"
        }
        runAfter = [ordered]@{
          Set_DeliverySnapshotProcessedOn = @("Succeeded")
        }
        metadata = [ordered]@{
          operationMetadataId = [guid]::NewGuid().Guid
        }
      }))
  Set-FieldValue -Map $conditionActions -Name "Reset_CurrentDeliverySnapshotKeys" -Value ([pscustomobject]([ordered]@{
        type = "SetVariable"
        description = "Reset the delivery snapshot key bag for the current attachment."
        inputs = [ordered]@{
          name = "CurrentDeliverySnapshotKeys"
          value = "@json('[]')"
        }
        runAfter = [ordered]@{
          Set_DeliveryImportBatchId = @("Succeeded")
        }
        metadata = [ordered]@{
          operationMetadataId = [guid]::NewGuid().Guid
        }
      }))
  Set-FieldValue -Map $conditionActions -Name "Reset_CurrentBackorderSnapshotKeys" -Value ([pscustomobject]([ordered]@{
        type = "SetVariable"
        description = "Reset the backorder snapshot key bag for the current attachment."
        inputs = [ordered]@{
          name = "CurrentBackorderSnapshotKeys"
          value = "@json('[]')"
        }
        runAfter = [ordered]@{
          Reset_CurrentDeliverySnapshotKeys = @("Succeeded")
        }
        metadata = [ordered]@{
          operationMetadataId = [guid]::NewGuid().Guid
        }
      }))
  $conditionActions.Delay_for_File_Availability.runAfter = [ordered]@{
    Reset_CurrentBackorderSnapshotKeys = @("Succeeded")
  }

  $guardActions = $conditionActions.Guard_BackOrder_Row_Limit.actions
  $selectBackorderParameters = Copy-OrderedMap $guardActions.Select_BackOrder_Rows.inputs.select
  Set-FieldValue -Map $selectBackorderParameters -Name "branchCode" -Value "@if(or(empty(coalesce(item()?['Soff_x002e_'], item()?['Soff.'])), startsWith(string(coalesce(item()?['Soff_x002e_'], item()?['Soff.'])), '#')), '', string(coalesce(item()?['Soff_x002e_'], item()?['Soff.'])))"
  Set-FieldValue -Map $selectBackorderParameters -Name "accountManagerName" -Value "@item()?['Acct Mgr Name']"
  Set-FieldValue -Map $selectBackorderParameters -Name "soldTo" -Value "@if(or(empty(coalesce(item()?['Sold-To'], item()?['Sold To'])), startsWith(string(coalesce(item()?['Sold-To'], item()?['Sold To'])), '#')), '', string(coalesce(item()?['Sold-To'], item()?['Sold To'])))"
  Set-FieldValue -Map $selectBackorderParameters -Name "shipTo" -Value "@if(or(empty(coalesce(item()?['Ship To'], item()?['ShipTo'])), startsWith(string(coalesce(item()?['Ship To'], item()?['ShipTo'])), '#')), '', string(coalesce(item()?['Ship To'], item()?['ShipTo'])))"
  Set-FieldValue -Map $selectBackorderParameters -Name "shipCondDesc" -Value "@item()?['Ship Cond Desc']"
  Set-FieldValue -Map $selectBackorderParameters -Name "billBlockDesc" -Value "@item()?['Bill Block Desc']"
  Set-FieldValue -Map $selectBackorderParameters -Name "delBlockDesc" -Value "@item()?['Del Block Desc']"
  Set-FieldValue -Map $selectBackorderParameters -Name "itemCategory" -Value "@item()?['Item Category']"
  Set-FieldValue -Map $selectBackorderParameters -Name "vendorPO" -Value "@item()?['Vendor PO']"
  Set-FieldValue -Map $selectBackorderParameters -Name "createdBy" -Value "@item()?['Created By']"
  Set-FieldValue -Map $selectBackorderParameters -Name "plant" -Value "@item()?['Plant']"
  Set-FieldValue -Map $selectBackorderParameters -Name "reasonForRejection" -Value "@item()?['Reason for Rejection']"
  Set-FieldValue -Map $selectBackorderParameters -Name "firstDate" -Value "@item()?['First date']"
  Set-FieldValue -Map $selectBackorderParameters -Name "qtyBilled" -Value "@if(or(empty(item()?['Qty Billed']), startsWith(string(item()?['Qty Billed']), '#')), float(0), float(coalesce(item()?['Qty Billed'], 0)))"
  Set-FieldValue -Map $selectBackorderParameters -Name "qtyOnDelNotPgid" -Value "@if(or(empty(coalesce(item()?['Qty on Del Not PGI_x0027_d'], item()?['Qty on Del Not PGI''d'])), startsWith(string(coalesce(item()?['Qty on Del Not PGI_x0027_d'], item()?['Qty on Del Not PGI''d'])), '#')), float(0), float(coalesce(coalesce(item()?['Qty on Del Not PGI_x0027_d'], item()?['Qty on Del Not PGI''d']), 0)))"
  Set-FieldValue -Map $selectBackorderParameters -Name "qtyNotOnDel" -Value "@if(or(empty(item()?['Qty Not On Del']), startsWith(string(item()?['Qty Not On Del']), '#')), float(0), float(coalesce(item()?['Qty Not On Del'], 0)))"
  $guardActions.Select_BackOrder_Rows.inputs.select = [pscustomobject]$selectBackorderParameters
  $guardActions.Filter_BackOrder_Rows.description = "Keep only actionable current-state backorder rows for the configured branch."
  $guardActions.Filter_BackOrder_Rows.inputs.where = "@and(equals(item()?['branchCode'], parameters('qfu_QFU_BranchCode')), not(empty(item()?['salesDocNumber'])), not(empty(item()?['lineNumber'])), or(greater(item()?['qtyNotOnDel'], 0), greater(item()?['qtyOnDelNotPgid'], 0)))"
  $guardActions.Condition_Has_New_Rows.expression = "@greaterOrEquals(length(coalesce(body('Filter_BackOrder_Rows'), createArray())), 0)"

  $backorderActions = $guardActions.Condition_Has_New_Rows.actions
  $backorderRecordParameters = Copy-OrderedMap $backorderActions.Insert_New_BackOrders.actions.Create_BackOrder_Record.inputs.parameters
  Set-FieldValue -Map $backorderRecordParameters -Name "item/qfu_name" -Value "@concat(parameters('qfu_QFU_BranchCode'), '-BO-', items('Insert_New_BackOrders')?['salesDocNumber'], '-', items('Insert_New_BackOrders')?['lineNumber'])"
  Set-FieldValue -Map $backorderRecordParameters -Name "item/qfu_sourceid" -Value "@outputs('Compose_BackOrder_SourceId')"
  Set-FieldValue -Map $backorderRecordParameters -Name "item/qfu_branchcode" -Value "@parameters('qfu_QFU_BranchCode')"
  Set-FieldValue -Map $backorderRecordParameters -Name "item/qfu_branchslug" -Value "@parameters('qfu_QFU_BranchSlug')"
  Set-FieldValue -Map $backorderRecordParameters -Name "item/qfu_regionslug" -Value "@parameters('qfu_QFU_RegionSlug')"
  Set-FieldValue -Map $backorderRecordParameters -Name "item/qfu_sourcefamily" -Value "ZBO"
  Set-FieldValue -Map $backorderRecordParameters -Name "item/qfu_sourcefile" -Value "@items('Apply_to_each_Attachment')?['name']"
  Set-FieldValue -Map $backorderRecordParameters -Name "item/qfu_sourceline" -Value "@string(items('Insert_New_BackOrders')?['lineNumber'])"
  Set-FieldValue -Map $backorderRecordParameters -Name "item/qfu_salesdoctype" -Value "@items('Insert_New_BackOrders')?['salesDocType']"
  Set-FieldValue -Map $backorderRecordParameters -Name "item/qfu_materialgroup" -Value "@items('Insert_New_BackOrders')?['materialGroup']"
  Set-FieldValue -Map $backorderRecordParameters -Name "item/qfu_uom" -Value "@items('Insert_New_BackOrders')?['uom']"
  Set-FieldValue -Map $backorderRecordParameters -Name "item/qfu_qtybilled" -Value "@items('Insert_New_BackOrders')?['qtyBilled']"
  Set-FieldValue -Map $backorderRecordParameters -Name "item/qfu_qtyondelnotpgid" -Value "@items('Insert_New_BackOrders')?['qtyOnDelNotPgid']"
  Set-FieldValue -Map $backorderRecordParameters -Name "item/qfu_qtynotondel" -Value "@items('Insert_New_BackOrders')?['qtyNotOnDel']"
  Set-FieldValue -Map $backorderRecordParameters -Name "item/qfu_netprice" -Value "@items('Insert_New_BackOrders')?['unitPrice']"
  Set-FieldValue -Map $backorderRecordParameters -Name "item/qfu_accountmanager" -Value "@items('Insert_New_BackOrders')?['accountManager']"
  Set-FieldValue -Map $backorderRecordParameters -Name "item/qfu_accountmanagername" -Value "@items('Insert_New_BackOrders')?['accountManagerName']"
  Set-FieldValue -Map $backorderRecordParameters -Name "item/qfu_soldto" -Value "@items('Insert_New_BackOrders')?['soldTo']"
  Set-FieldValue -Map $backorderRecordParameters -Name "item/qfu_shipto" -Value "@items('Insert_New_BackOrders')?['shipTo']"
  Set-FieldValue -Map $backorderRecordParameters -Name "item/qfu_shiptoname" -Value "@items('Insert_New_BackOrders')?['shipToName']"
  Set-FieldValue -Map $backorderRecordParameters -Name "item/qfu_shipconddesc" -Value "@items('Insert_New_BackOrders')?['shipCondDesc']"
  Set-FieldValue -Map $backorderRecordParameters -Name "item/qfu_lineitemcreatedon" -Value "@if(equals(items('Insert_New_BackOrders')?['createdDate'], null), null, formatDateTime(items('Insert_New_BackOrders')?['createdDate'], 'yyyy-MM-dd'))"
  Set-FieldValue -Map $backorderRecordParameters -Name "item/qfu_firstdate" -Value "@if(equals(items('Insert_New_BackOrders')?['firstDate'], null), null, formatDateTime(items('Insert_New_BackOrders')?['firstDate'], 'yyyy-MM-dd'))"
  Set-FieldValue -Map $backorderRecordParameters -Name "item/qfu_delblockdesc" -Value "@items('Insert_New_BackOrders')?['delBlockDesc']"
  Set-FieldValue -Map $backorderRecordParameters -Name "item/qfu_billblockdesc" -Value "@items('Insert_New_BackOrders')?['billBlockDesc']"
  Set-FieldValue -Map $backorderRecordParameters -Name "item/qfu_itemcategory" -Value "@items('Insert_New_BackOrders')?['itemCategory']"
  Set-FieldValue -Map $backorderRecordParameters -Name "item/qfu_vendorpo" -Value "@items('Insert_New_BackOrders')?['vendorPO']"
  Set-FieldValue -Map $backorderRecordParameters -Name "item/qfu_createdby" -Value "@items('Insert_New_BackOrders')?['createdBy']"
  Set-FieldValue -Map $backorderRecordParameters -Name "item/qfu_plant" -Value "@items('Insert_New_BackOrders')?['plant']"
  Set-FieldValue -Map $backorderRecordParameters -Name "item/qfu_userstatusdescription" -Value "@items('Insert_New_BackOrders')?['status']"
  Set-FieldValue -Map $backorderRecordParameters -Name "item/qfu_reasonforrejection" -Value "@items('Insert_New_BackOrders')?['reasonForRejection']"
  Set-FieldValue -Map $backorderRecordParameters -Name "item/qfu_importbatchid" -Value "@variables('DeliveryImportBatchId')"
  Set-FieldValue -Map $backorderRecordParameters -Name "item/qfu_active" -Value $true
  Set-FieldValue -Map $backorderRecordParameters -Name "item/qfu_inactiveon" -Value $null
  Set-FieldValue -Map $backorderRecordParameters -Name "item/qfu_lastseenon" -Value "@variables('DeliverySnapshotProcessedOn')"
  $backorderUpdateParameters = Copy-OrderedMap $backorderRecordParameters
  Set-FieldValue -Map $backorderUpdateParameters -Name "recordId" -Value "@outputs('Check_Existing_Active_BackOrder')?['body/value'][0]['qfu_backorderid']"
  $guardActions.Condition_Has_New_Rows.actions = [pscustomobject]([ordered]@{
      List_Existing_Active_BackOrders = [ordered]@{
        type = "OpenApiConnection"
        description = "Get active backorder rows for this branch so absent rows can be marked inactive."
        inputs = [ordered]@{
          parameters = [ordered]@{
            entityName = "qfu_backorders"
            '$select' = "qfu_backorderid,qfu_sourceid"
            '$filter' = "qfu_branchcode eq '@{parameters('qfu_QFU_BranchCode')}' and (qfu_active eq true or qfu_active eq null)"
          }
          host = [ordered]@{
            apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
            operationId = "ListRecords"
            connectionName = "shared_commondataserviceforapps"
          }
        }
        metadata = [ordered]@{
          operationMetadataId = [guid]::NewGuid().Guid
        }
      }
      Insert_New_BackOrders = [ordered]@{
        type = "Foreach"
        description = "Upsert actionable backorder rows for the current branch snapshot."
        foreach = "@coalesce(body('Filter_BackOrder_Rows'), json('[]'))"
        actions = [ordered]@{
          Compose_BackOrder_SourceId = [ordered]@{
            type = "Compose"
            inputs = "@concat(parameters('qfu_QFU_BranchCode'), '|ZBO|', items('Insert_New_BackOrders')?['salesDocNumber'], '|', items('Insert_New_BackOrders')?['lineNumber'])"
            metadata = [ordered]@{
              operationMetadataId = [guid]::NewGuid().Guid
            }
          }
          Append_BackOrder_SourceId = [ordered]@{
            type = "AppendToArrayVariable"
            inputs = [ordered]@{
              name = "CurrentBackorderSnapshotKeys"
              value = "@outputs('Compose_BackOrder_SourceId')"
            }
            runAfter = [ordered]@{
              Compose_BackOrder_SourceId = @("Succeeded")
            }
          }
          Check_Existing_Active_BackOrder = [ordered]@{
            type = "OpenApiConnection"
            description = "Find an existing active backorder row by stable source id."
            inputs = [ordered]@{
              parameters = [ordered]@{
                entityName = "qfu_backorders"
                '$select' = "qfu_backorderid"
                '$top' = 1
                '$orderby' = "modifiedon desc, createdon desc"
                '$filter' = "qfu_sourceid eq '@{outputs('Compose_BackOrder_SourceId')}' and (qfu_active eq true or qfu_active eq null)"
              }
              host = [ordered]@{
                apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
                operationId = "ListRecords"
                connectionName = "shared_commondataserviceforapps"
              }
            }
            runAfter = [ordered]@{
              Append_BackOrder_SourceId = @("Succeeded")
            }
            metadata = [ordered]@{
              operationMetadataId = [guid]::NewGuid().Guid
            }
          }
          Condition_BackOrder_Exists = [ordered]@{
            type = "If"
            expression = "@greater(length(outputs('Check_Existing_Active_BackOrder')?['body/value']), 0)"
            actions = [ordered]@{
              Update_BackOrder_Record = [ordered]@{
                type = "OpenApiConnection"
                inputs = [ordered]@{
                  parameters = [pscustomobject]$backorderUpdateParameters
                  host = [ordered]@{
                    apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
                    operationId = "UpdateRecord"
                    connectionName = "shared_commondataserviceforapps"
                  }
                }
                metadata = [ordered]@{
                  operationMetadataId = [guid]::NewGuid().Guid
                }
              }
            }
            else = [ordered]@{
              actions = [ordered]@{
                Create_BackOrder_Record = [ordered]@{
                  type = "OpenApiConnection"
                  inputs = [ordered]@{
                    parameters = [pscustomobject]$backorderRecordParameters
                    host = [ordered]@{
                      apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
                      operationId = "CreateRecord"
                      connectionName = "shared_commondataserviceforapps"
                    }
                  }
                  metadata = [ordered]@{
                    operationMetadataId = [guid]::NewGuid().Guid
                  }
                }
              }
            }
            runAfter = [ordered]@{
              Check_Existing_Active_BackOrder = @("Succeeded")
            }
            metadata = [ordered]@{
              operationMetadataId = [guid]::NewGuid().Guid
            }
          }
        }
        runAfter = [ordered]@{
          List_Existing_Active_BackOrders = @("Succeeded")
        }
        metadata = [ordered]@{
          operationMetadataId = [guid]::NewGuid().Guid
        }
      }
      Filter_Missing_Active_BackOrders = [ordered]@{
        type = "Query"
        description = "Identify active backorder rows that are absent from the current snapshot and must be inactivated."
        inputs = [ordered]@{
          from = "@coalesce(outputs('List_Existing_Active_BackOrders')?['body/value'], json('[]'))"
          where = "@not(contains(variables('CurrentBackorderSnapshotKeys'), item()?['qfu_sourceid']))"
        }
        runAfter = [ordered]@{
          Insert_New_BackOrders = @("Succeeded")
        }
      }
      Deactivate_Missing_BackOrders = [ordered]@{
        type = "Foreach"
        description = "Mark previously-active backorder rows inactive when they are absent from the latest branch snapshot."
        foreach = "@coalesce(body('Filter_Missing_Active_BackOrders'), json('[]'))"
        actions = [ordered]@{
          Update_BackOrder_Inactive = [ordered]@{
            type = "OpenApiConnection"
            inputs = [ordered]@{
              parameters = [ordered]@{
                entityName = "qfu_backorders"
                recordId = "@items('Deactivate_Missing_BackOrders')?['qfu_backorderid']"
                "item/qfu_active" = $false
                "item/qfu_inactiveon" = "@variables('DeliverySnapshotProcessedOn')"
              }
              host = [ordered]@{
                apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
                operationId = "UpdateRecord"
                connectionName = "shared_commondataserviceforapps"
              }
            }
            metadata = [ordered]@{
              operationMetadataId = [guid]::NewGuid().Guid
            }
          }
        }
        runAfter = [ordered]@{
          Filter_Missing_Active_BackOrders = @("Succeeded")
        }
        metadata = [ordered]@{
          operationMetadataId = [guid]::NewGuid().Guid
        }
      }
    })

  Set-FieldValue -Map $guardActions -Name "Filter_DeliveryNotPgi_Rows" -Value ([pscustomobject]([ordered]@{
        type = "Query"
        description = "Keep only delivery-line rows that are ready to ship and not PGI'd for the configured branch."
        inputs = [ordered]@{
          from = "@coalesce(body('Select_BackOrder_Rows'), json('[]'))"
          where = "@and(equals(item()?['branchCode'], parameters('qfu_QFU_BranchCode')), not(empty(item()?['salesDocNumber'])), not(empty(item()?['lineNumber'])), greater(item()?['qtyOnDelNotPgid'], 0))"
        }
        runAfter = [ordered]@{
          Select_BackOrder_Rows = @("Succeeded")
        }
      }))
  Set-FieldValue -Map $guardActions -Name "List_Existing_Active_DeliveryNotPgi" -Value ([pscustomobject]([ordered]@{
        type = "OpenApiConnection"
        description = "Get active delivery not PGI rows for this branch so absent rows can be marked inactive."
        inputs = [ordered]@{
          parameters = [ordered]@{
            entityName = "qfu_deliverynotpgis"
            '$select' = "qfu_deliverynotpgiid,qfu_sourceid"
            '$filter' = "qfu_branchcode eq '@{parameters('qfu_QFU_BranchCode')}' and qfu_active eq true"
          }
          host = [ordered]@{
            apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
            operationId = "ListRecords"
            connectionName = "shared_commondataserviceforapps"
          }
        }
        runAfter = [ordered]@{
          Filter_DeliveryNotPgi_Rows = @("Succeeded")
        }
        metadata = [ordered]@{
          operationMetadataId = [guid]::NewGuid().Guid
        }
      }))
  Set-FieldValue -Map $guardActions -Name "Apply_to_each_DeliveryNotPgi_Row" -Value ([pscustomobject]([ordered]@{
        type = "Foreach"
        description = "Upsert active delivery not PGI rows for the current branch snapshot."
        foreach = "@coalesce(body('Filter_DeliveryNotPgi_Rows'), json('[]'))"
        actions = [ordered]@{
          Compose_Delivery_SourceId = [ordered]@{
            type = "Compose"
            inputs = "@concat(parameters('qfu_QFU_BranchCode'), '|ZBO|', items('Apply_to_each_DeliveryNotPgi_Row')?['salesDocNumber'], '|', items('Apply_to_each_DeliveryNotPgi_Row')?['lineNumber'])"
            metadata = [ordered]@{
              operationMetadataId = [guid]::NewGuid().Guid
            }
          }
          Append_Delivery_SourceId = [ordered]@{
            type = "AppendToArrayVariable"
            inputs = [ordered]@{
              name = "CurrentDeliverySnapshotKeys"
              value = "@outputs('Compose_Delivery_SourceId')"
            }
            runAfter = [ordered]@{
              Compose_Delivery_SourceId = @("Succeeded")
            }
          }
          Check_Existing_Active_DeliveryNotPgi = [ordered]@{
            type = "OpenApiConnection"
            description = "Find an existing active delivery-line row by stable source id."
            inputs = [ordered]@{
              parameters = [ordered]@{
                entityName = "qfu_deliverynotpgis"
                '$select' = "qfu_deliverynotpgiid"
                '$top' = 1
                '$filter' = "qfu_sourceid eq '@{outputs('Compose_Delivery_SourceId')}' and qfu_active eq true"
              }
              host = [ordered]@{
                apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
                operationId = "ListRecords"
                connectionName = "shared_commondataserviceforapps"
              }
            }
            runAfter = [ordered]@{
              Append_Delivery_SourceId = @("Succeeded")
            }
            metadata = [ordered]@{
              operationMetadataId = [guid]::NewGuid().Guid
            }
          }
          Condition_DeliveryNotPgi_Exists = [ordered]@{
            type = "If"
            expression = "@greater(length(outputs('Check_Existing_Active_DeliveryNotPgi')?['body/value']), 0)"
            actions = [ordered]@{
              Update_DeliveryNotPgi_Record = [ordered]@{
                type = "OpenApiConnection"
                description = "Update source-owned fields only; portal comments stay untouched."
                inputs = [ordered]@{
                  parameters = [ordered]@{
                    entityName = "qfu_deliverynotpgis"
                    recordId = "@outputs('Check_Existing_Active_DeliveryNotPgi')?['body/value'][0]['qfu_deliverynotpgiid']"
                    "item/qfu_name" = "@concat('DNPGI-', parameters('qfu_QFU_BranchCode'), '-', items('Apply_to_each_DeliveryNotPgi_Row')?['salesDocNumber'], '-', items('Apply_to_each_DeliveryNotPgi_Row')?['lineNumber'])"
                    "item/qfu_sourceid" = "@outputs('Compose_Delivery_SourceId')"
                    "item/qfu_deliverynumber" = "@items('Apply_to_each_DeliveryNotPgi_Row')?['salesDocNumber']"
                    "item/qfu_deliveryline" = "@items('Apply_to_each_DeliveryNotPgi_Row')?['lineNumber']"
                    "item/qfu_ontimedate" = "@if(equals(items('Apply_to_each_DeliveryNotPgi_Row')?['onTimeDate'], null), null, formatDateTime(items('Apply_to_each_DeliveryNotPgi_Row')?['onTimeDate'], 'yyyy-MM-dd'))"
                    "item/qfu_dayslate" = "@int(coalesce(items('Apply_to_each_DeliveryNotPgi_Row')?['daysOverdue'], 0))"
                    "item/qfu_shiptocustomername" = "@items('Apply_to_each_DeliveryNotPgi_Row')?['shipToName']"
                    "item/qfu_soldtocustomername" = "@items('Apply_to_each_DeliveryNotPgi_Row')?['customerName']"
                    "item/qfu_material" = "@items('Apply_to_each_DeliveryNotPgi_Row')?['material']"
                    "item/qfu_description" = "@items('Apply_to_each_DeliveryNotPgi_Row')?['description']"
                    "item/qfu_qtyondelnotpgid" = "@items('Apply_to_each_DeliveryNotPgi_Row')?['qtyOnDelNotPgid']"
                    "item/qfu_unshippednetvalue" = "@items('Apply_to_each_DeliveryNotPgi_Row')?['totalValue']"
                    "item/qfu_cssrname" = "@items('Apply_to_each_DeliveryNotPgi_Row')?['cssrName']"
                    "item/qfu_snapshotcapturedon" = "@variables('DeliverySnapshotProcessedOn')"
                    "item/qfu_active" = $true
                    "item/qfu_inactiveon" = $null
                    "item/qfu_branchcode" = "@parameters('qfu_QFU_BranchCode')"
                    "item/qfu_branchslug" = "@parameters('qfu_QFU_BranchSlug')"
                    "item/qfu_regionslug" = "@parameters('qfu_QFU_RegionSlug')"
                    "item/qfu_sourcefamily" = "ZBO"
                    "item/qfu_sourcefile" = "@items('Apply_to_each_Attachment')?['name']"
                    "item/qfu_importbatchid" = "@variables('DeliveryImportBatchId')"
                  }
                  host = [ordered]@{
                    apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
                    operationId = "UpdateRecord"
                    connectionName = "shared_commondataserviceforapps"
                  }
                }
                metadata = [ordered]@{
                  operationMetadataId = [guid]::NewGuid().Guid
                }
              }
            }
            else = [ordered]@{
              actions = [ordered]@{
                Create_DeliveryNotPgi_Record = [ordered]@{
                  type = "OpenApiConnection"
                  description = "Create a new active delivery-line record for the current snapshot."
                  inputs = [ordered]@{
                    parameters = [ordered]@{
                      entityName = "qfu_deliverynotpgis"
                      "item/qfu_name" = "@concat('DNPGI-', parameters('qfu_QFU_BranchCode'), '-', items('Apply_to_each_DeliveryNotPgi_Row')?['salesDocNumber'], '-', items('Apply_to_each_DeliveryNotPgi_Row')?['lineNumber'])"
                      "item/qfu_sourceid" = "@outputs('Compose_Delivery_SourceId')"
                      "item/qfu_deliverynumber" = "@items('Apply_to_each_DeliveryNotPgi_Row')?['salesDocNumber']"
                      "item/qfu_deliveryline" = "@items('Apply_to_each_DeliveryNotPgi_Row')?['lineNumber']"
                      "item/qfu_ontimedate" = "@if(equals(items('Apply_to_each_DeliveryNotPgi_Row')?['onTimeDate'], null), null, formatDateTime(items('Apply_to_each_DeliveryNotPgi_Row')?['onTimeDate'], 'yyyy-MM-dd'))"
                      "item/qfu_dayslate" = "@int(coalesce(items('Apply_to_each_DeliveryNotPgi_Row')?['daysOverdue'], 0))"
                      "item/qfu_shiptocustomername" = "@items('Apply_to_each_DeliveryNotPgi_Row')?['shipToName']"
                      "item/qfu_soldtocustomername" = "@items('Apply_to_each_DeliveryNotPgi_Row')?['customerName']"
                      "item/qfu_material" = "@items('Apply_to_each_DeliveryNotPgi_Row')?['material']"
                      "item/qfu_description" = "@items('Apply_to_each_DeliveryNotPgi_Row')?['description']"
                      "item/qfu_qtyondelnotpgid" = "@items('Apply_to_each_DeliveryNotPgi_Row')?['qtyOnDelNotPgid']"
                      "item/qfu_unshippednetvalue" = "@items('Apply_to_each_DeliveryNotPgi_Row')?['totalValue']"
                      "item/qfu_cssrname" = "@items('Apply_to_each_DeliveryNotPgi_Row')?['cssrName']"
                      "item/qfu_snapshotcapturedon" = "@variables('DeliverySnapshotProcessedOn')"
                      "item/qfu_active" = $true
                      "item/qfu_inactiveon" = $null
                      "item/qfu_branchcode" = "@parameters('qfu_QFU_BranchCode')"
                      "item/qfu_branchslug" = "@parameters('qfu_QFU_BranchSlug')"
                      "item/qfu_regionslug" = "@parameters('qfu_QFU_RegionSlug')"
                      "item/qfu_sourcefamily" = "ZBO"
                      "item/qfu_sourcefile" = "@items('Apply_to_each_Attachment')?['name']"
                      "item/qfu_importbatchid" = "@variables('DeliveryImportBatchId')"
                    }
                    host = [ordered]@{
                      apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
                      operationId = "CreateRecord"
                      connectionName = "shared_commondataserviceforapps"
                    }
                  }
                  metadata = [ordered]@{
                    operationMetadataId = [guid]::NewGuid().Guid
                  }
                }
              }
            }
            runAfter = [ordered]@{
              Check_Existing_Active_DeliveryNotPgi = @("Succeeded")
            }
            metadata = [ordered]@{
              operationMetadataId = [guid]::NewGuid().Guid
            }
          }
        }
        runAfter = [ordered]@{
          List_Existing_Active_DeliveryNotPgi = @("Succeeded")
        }
        metadata = [ordered]@{
          operationMetadataId = [guid]::NewGuid().Guid
        }
      }))
  Set-FieldValue -Map $guardActions -Name "Filter_Missing_Active_DeliveryNotPgi" -Value ([pscustomobject]([ordered]@{
        type = "Query"
        description = "Identify active delivery rows that are absent from the current snapshot and must be inactivated."
        inputs = [ordered]@{
          from = "@coalesce(outputs('List_Existing_Active_DeliveryNotPgi')?['body/value'], json('[]'))"
          where = "@not(contains(variables('CurrentDeliverySnapshotKeys'), item()?['qfu_sourceid']))"
        }
        runAfter = [ordered]@{
          Apply_to_each_DeliveryNotPgi_Row = @("Succeeded")
        }
      }))
  Set-FieldValue -Map $guardActions -Name "Deactivate_Missing_DeliveryNotPgi" -Value ([pscustomobject]([ordered]@{
        type = "Foreach"
        description = "Mark previously-active delivery rows inactive when they are absent from the latest branch snapshot."
        foreach = "@coalesce(body('Filter_Missing_Active_DeliveryNotPgi'), json('[]'))"
        actions = [ordered]@{
          Update_DeliveryNotPgi_Inactive = [ordered]@{
            type = "OpenApiConnection"
            inputs = [ordered]@{
              parameters = [ordered]@{
                entityName = "qfu_deliverynotpgis"
                recordId = "@items('Deactivate_Missing_DeliveryNotPgi')?['qfu_deliverynotpgiid']"
                "item/qfu_active" = $false
                "item/qfu_inactiveon" = "@variables('DeliverySnapshotProcessedOn')"
              }
              host = [ordered]@{
                apiId = "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps"
                operationId = "UpdateRecord"
                connectionName = "shared_commondataserviceforapps"
              }
            }
            metadata = [ordered]@{
              operationMetadataId = [guid]::NewGuid().Guid
            }
          }
        }
        runAfter = [ordered]@{
          Filter_Missing_Active_DeliveryNotPgi = @("Succeeded")
        }
        metadata = [ordered]@{
          operationMetadataId = [guid]::NewGuid().Guid
        }
      }))

  $backorderBatchActions = New-IngestionBatchSyncActionSet `
    -ActionPrefix "Backorder" `
    -ImportNameSuffix "Backorder Workbook Import" `
    -SourceFamily "ZBO" `
    -FlowNameExpression "@concat(parameters('qfu_QFU_BranchCode'), '-BackOrder-Update-ZBO')" `
    -FileNameExpression "@items('Apply_to_each_Attachment')?['name']" `
    -StartedOnExpression "@variables('DeliverySnapshotProcessedOn')" `
    -RunAfter ([ordered]@{
        Guard_BackOrder_Row_Limit = @("Succeeded")
        Reset_CurrentBackorderSnapshotKeys = @("Succeeded")
      })
  Set-FieldValue -Map $conditionActions -Name $backorderBatchActions.ListActionName -Value $backorderBatchActions.ListAction
  Set-FieldValue -Map $conditionActions -Name $backorderBatchActions.ConditionActionName -Value $backorderBatchActions.ConditionAction

  Add-Note -Notes $Notes -Text "Backorder flow now enforces trigger concurrency = 1, treats qfu_backorder as current-state with qfu_active/qfu_inactiveon/qfu_lastseenon, upserts actionable ZBO rows by canonical source id, marks missing rows inactive on rerun, syncs qfu_deliverynotpgi from the same workbook using branch-scoped upsert plus inactive marking, and refreshes the stable qfu_ingestionbatch freshness row that analytics reads."
}

function Update-BudgetFlow {
  param(
    [object]$Json,
    [object]$Branch,
    [object]$Template,
    [System.Collections.Generic.List[string]]$Notes
  )

  $definition = $Json.properties.definition
  $flowName = "{0}-{1}" -f $Branch.BranchCode, $Template.TargetSuffix
  $budgetGoalFromPlanExpr = "@if(or(empty(body('Filter_Budget_Target_Rows')), empty(body('Filter_Budget_Target_Rows')?[0]?['Sales'])), null, float(replace(replace(coalesce(body('Filter_Budget_Target_Rows')?[0]?['Sales'], '0'), '$', ''), ',', '')))"
  $resolvedBudgetGoalExpr = "@coalesce(first(outputs('Get_Budget_Goal_From_Archives')?['body/value'])?['qfu_budgetgoal'], outputs('Resolve_Budget_Goal_From_SA1300_Plan'), outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_budgetgoal'])"
  $currentBudgetSourceIdExpr = "concat(parameters('qfu_QFU_BranchCode'), '|SA1300|', formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'yyyy-MM'))"
  $sameMonthActualRollbackBody = "and(equals(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_sourceid'], $currentBudgetSourceIdExpr), greater(float(coalesce(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_actualsales'], 0)), float(coalesce(variables('TotalSales'), 0))))"
  $preservedActualSalesExpr = "@if($sameMonthActualRollbackBody, outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_actualsales'], variables('TotalSales'))"
  $preservedCadSalesExpr = "@if($sameMonthActualRollbackBody, outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_cadsales'], variables('CADSales'))"
  $preservedUsdSalesExpr = "@if($sameMonthActualRollbackBody, outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_usdsales'], variables('USDSales'))"
  $preservedLastUpdatedExpr = "@if($sameMonthActualRollbackBody, outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_lastupdated'], utcNow())"
  $preservedSourceFileExpr = "@if($sameMonthActualRollbackBody, outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_sourcefile'], items('Apply_to_each_Attachment')?['name'])"
  $incomingCadOpsDailyExpr = "@string(coalesce(body('Filter_CAD_Ops_Daily_Rows'), json('[]')))"
  $incomingUsdOpsDailyExpr = "@string(coalesce(outputs('Filter_USD_Ops_Daily_Rows')?['body'], json('[]')))"
  $preservedCadOpsDailyExpr = "@if($sameMonthActualRollbackBody, coalesce(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_opsdailycadjson'], string(json('[]'))), string(coalesce(body('Filter_CAD_Ops_Daily_Rows'), json('[]'))))"
  $preservedUsdOpsDailyExpr = "@if($sameMonthActualRollbackBody, coalesce(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_opsdailyusdjson'], string(json('[]'))), string(coalesce(outputs('Filter_USD_Ops_Daily_Rows')?['body'], json('[]'))))"
  Add-BranchParameters -Definition $definition -Branch $Branch -Template $Template
  Set-TemplateTrigger `
    -Definition $definition `
    -Branch $Branch `
    -Template $Template `
    -SharedMailboxDescription "Triggers when a new SA1300 workbook lands in the $($Branch.BranchCode) $($Branch.BranchName) shared mailbox." `
    -PrimaryInboxDescription "Triggers when a new SA1300 workbook lands in the primary inbox for $($Branch.BranchCode) $($Branch.BranchName)."

  $budgetRootActions = $definition.actions.Apply_to_each_Attachment.actions.Condition_Is_SA1300_File.actions
  $budgetRootActions.Create_File_in_OneDrive.inputs.parameters.name = "@concat(parameters('qfu_QFU_BranchCode'), '_SA1300_', formatDateTime(utcNow(), 'yyyyMMdd_HHmmss'), '.xlsx')"
  $budgetRootActions.Create_Budget_Table.description = "Create a dedicated Current Month-To-Date Sales table for the SA1300 attachment."
  $budgetRootActions.Get_Budget_Tables.runAfter = [ordered]@{
    Create_Budget_Table = @("Succeeded")
  }
  $budgetRootActions.List_Budget_Rows.description = "List budget rows from the table created for Current Month-To-Date Sales."
  $budgetRootActions.List_Budget_Rows.inputs.parameters.table = "@coalesce(body('Create_Budget_Table')?['name'], body('Create_Budget_Table')?['id'], body('Create_Budget_Table')?['Id'])"
  $budgetRootActions.List_Budget_Rows.runAfter = [ordered]@{
    Create_Budget_Table = @("Succeeded")
  }
  $budgetRootActions.Filter_Budget_Rows.description = "Keep only populated Current Month-To-Date Sales rows."
  $definition.triggers.Shared_Mailbox_New_Email.runtimeConfiguration = [ordered]@{
    concurrency = [ordered]@{
      runs = 1
    }
  }
  $budgetActions = $budgetRootActions.Guard_Budget_Row_Limit.actions
  $budgetArchiveParameters = Copy-OrderedMap $budgetActions.Get_Budget_Goal_From_Archives.inputs.parameters
  Set-FieldValue -Map $budgetArchiveParameters -Name '$filter' -Value "qfu_branchcode eq '@{parameters('qfu_QFU_BranchCode')}' and qfu_month eq @{int(formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'MM'))} and qfu_fiscalyear eq '@{parameters('qfu_QFU_ActiveFiscalYear')}'"
  Set-FieldValue -Map $budgetArchiveParameters -Name '$orderby' -Value "modifiedon desc, createdon desc"
  $budgetActions.Get_Budget_Goal_From_Archives.inputs.parameters = [pscustomobject]$budgetArchiveParameters
  $getActiveBudgetParameters = Copy-OrderedMap $budgetActions.Get_Active_Budget.inputs.parameters
  Set-FieldValue -Map $getActiveBudgetParameters -Name '$select' -Value "qfu_budgetid,qfu_sourceid,qfu_budgetgoal,qfu_actualsales,qfu_cadsales,qfu_usdsales,qfu_opsdailycadjson,qfu_opsdailyusdjson,qfu_sourcefile,qfu_lastupdated,qfu_month,qfu_monthname,qfu_year,qfu_fiscalyear"
  Set-FieldValue -Map $getActiveBudgetParameters -Name '$filter' -Value "qfu_isactive eq false and qfu_branchcode eq '@{parameters('qfu_QFU_BranchCode')}' and qfu_sourcefamily eq 'SA1300'"
  Set-FieldValue -Map $getActiveBudgetParameters -Name '$orderby' -Value "qfu_lastupdated desc, createdon desc"
  $budgetActions.Get_Active_Budget.inputs.parameters = [pscustomobject]$getActiveBudgetParameters
  if ($budgetActions.PSObject.Properties['Get_Current_Month_Budget_Record']) {
    $currentMonthBudgetParameters = Copy-OrderedMap $budgetActions.Get_Current_Month_Budget_Record.inputs.parameters
    Set-FieldValue -Map $currentMonthBudgetParameters -Name '$filter' -Value "qfu_branchcode eq '@{parameters('qfu_QFU_BranchCode')}' and qfu_sourcefamily eq 'SA1300' and qfu_sourceid eq '@{concat(parameters('qfu_QFU_BranchCode'), '|SA1300|', formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'yyyy-MM'))}' and qfu_fiscalyear eq '@{parameters('qfu_QFU_ActiveFiscalYear')}'"
    Set-FieldValue -Map $currentMonthBudgetParameters -Name '$top' -Value 1
    Set-FieldValue -Map $currentMonthBudgetParameters -Name '$orderby' -Value "createdon desc"
    $budgetActions.Get_Current_Month_Budget_Record.inputs.parameters = [pscustomobject]$currentMonthBudgetParameters
  }

  $createBudgetTargetTable = Copy-DeepObject $budgetRootActions.Create_Budget_Table
  $createBudgetTargetTable.description = "Create a dedicated Month-End Plan table for the SA1300 attachment."
  $createBudgetTargetTable.inputs.parameters."table/Range" = "'Location Summary'!H2:H500"
  $createBudgetTargetTable.runAfter = [ordered]@{
    Filter_Budget_Rows = @("Succeeded")
  }
  Set-FieldValue -Map $createBudgetTargetTable -Name "metadata" -Value ([pscustomobject]([ordered]@{
    operationMetadataId = [guid]::NewGuid().Guid
  }))

  $listBudgetTargetRows = Copy-DeepObject $budgetRootActions.List_Budget_Rows
  $listBudgetTargetRows.description = "List Month-End Plan rows from the table created for the SA1300 attachment."
  $listBudgetTargetRows.inputs.parameters.table = "@coalesce(body('Create_Budget_Target_Table')?['name'], body('Create_Budget_Target_Table')?['id'], body('Create_Budget_Target_Table')?['Id'])"
  $listBudgetTargetRows.runAfter = [ordered]@{
    Create_Budget_Target_Table = @("Succeeded")
  }
  Set-FieldValue -Map $listBudgetTargetRows -Name "metadata" -Value ([pscustomobject]([ordered]@{
    operationMetadataId = [guid]::NewGuid().Guid
  }))

  $filterBudgetTargetRows = Copy-DeepObject $budgetRootActions.Filter_Budget_Rows
  $filterBudgetTargetRows.description = "Keep only populated Month-End Plan rows."
  $filterBudgetTargetRows.inputs.from = "@body('List_Budget_Target_Rows')?['value']"
  $filterBudgetTargetRows.inputs.where = "@not(empty(item()?['Sales']))"
  $filterBudgetTargetRows.runAfter = [ordered]@{
    List_Budget_Target_Rows = @("Succeeded")
  }
  Set-FieldValue -Map $filterBudgetTargetRows -Name "metadata" -Value ([pscustomobject]([ordered]@{
    operationMetadataId = [guid]::NewGuid().Guid
  }))

  $resolveBudgetGoalFromPlan = [pscustomobject]([ordered]@{
      type = "Compose"
      description = "Resolve the SA1300 Month-End Plan target from the Location Summary sheet."
      inputs = $budgetGoalFromPlanExpr
      runAfter = [ordered]@{
        Filter_Budget_Target_Rows = @("Succeeded")
      }
      metadata = [ordered]@{
        operationMetadataId = [guid]::NewGuid().Guid
      }
    })

  $budgetRootActions.Guard_Budget_Row_Limit.runAfter = [ordered]@{
    Resolve_Budget_Goal_From_SA1300_Plan = @("Succeeded")
  }
  $budgetActions.Get_Active_Budget.runAfter = [ordered]@{
    Get_Budget_Goal_From_Archives = @("Succeeded")
  }
  foreach ($action in @(
      $budgetActions.Condition_Check_Month_Changed.actions.Create_New_Month_Budget_Record,
      $budgetActions.Condition_Check_Month_Changed.else.actions.Condition_Budget_Exists_Same_Month.else.actions.Create_First_Budget_Record
    )) {
    $parameters = Copy-OrderedMap $action.inputs.parameters
    Set-FieldValue -Map $parameters -Name "item/qfu_name" -Value "@concat(parameters('qfu_QFU_BranchCode'), ' ', formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'MMMM yyyy'), ' Budget')"
    Set-FieldValue -Map $parameters -Name "item/qfu_sourceid" -Value "@concat(parameters('qfu_QFU_BranchCode'), '|SA1300|', formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'yyyy-MM'))"
    Set-FieldValue -Map $parameters -Name "item/qfu_budgetname" -Value "@concat(parameters('qfu_QFU_BranchCode'), ' ', formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'MMMM yyyy'), ' Budget')"
    Set-FieldValue -Map $parameters -Name "item/qfu_budgetamount" -Value $resolvedBudgetGoalExpr
    Set-FieldValue -Map $parameters -Name "item/qfu_branchcode" -Value "@parameters('qfu_QFU_BranchCode')"
    Set-FieldValue -Map $parameters -Name "item/qfu_branchslug" -Value "@parameters('qfu_QFU_BranchSlug')"
    Set-FieldValue -Map $parameters -Name "item/qfu_regionslug" -Value "@parameters('qfu_QFU_RegionSlug')"
    Set-FieldValue -Map $parameters -Name "item/qfu_sourcefamily" -Value "SA1300"
    Set-FieldValue -Map $parameters -Name "item/qfu_customername" -Value "@parameters('qfu_QFU_BranchName')"
    Set-FieldValue -Map $parameters -Name "item/qfu_opsdailycadjson" -Value $incomingCadOpsDailyExpr
    Set-FieldValue -Map $parameters -Name "item/qfu_opsdailyusdjson" -Value $incomingUsdOpsDailyExpr
    $action.inputs.parameters = [pscustomobject]$parameters
    $itemMap = Copy-OrderedMap $action.inputs.parameters.item
    Set-FieldValue -Map $itemMap -Name "qfu_isactive" -Value $false
    Set-FieldValue -Map $itemMap -Name "qfu_fiscalyear" -Value "@parameters('qfu_QFU_ActiveFiscalYear')"
    Set-FieldValue -Map $itemMap -Name "qfu_budgetamount" -Value $resolvedBudgetGoalExpr
    Set-FieldValue -Map $itemMap -Name "qfu_customername" -Value "@parameters('qfu_QFU_BranchName')"
    Set-FieldValue -Map $itemMap -Name "qfu_sourcefile" -Value "@items('Apply_to_each_Attachment')?['name']"
    Set-FieldValue -Map $itemMap -Name "qfu_branchcode" -Value "@parameters('qfu_QFU_BranchCode')"
    Set-FieldValue -Map $itemMap -Name "qfu_branchslug" -Value "@parameters('qfu_QFU_BranchSlug')"
    Set-FieldValue -Map $itemMap -Name "qfu_regionslug" -Value "@parameters('qfu_QFU_RegionSlug')"
    Set-FieldValue -Map $itemMap -Name "qfu_sourcefamily" -Value "SA1300"
    Set-FieldValue -Map $itemMap -Name "qfu_opsdailycadjson" -Value $incomingCadOpsDailyExpr
    Set-FieldValue -Map $itemMap -Name "qfu_opsdailyusdjson" -Value $incomingUsdOpsDailyExpr
    $action.inputs.parameters.item = [pscustomobject]$itemMap
  }

  $updateCurrent = Copy-OrderedMap $budgetActions.Condition_Check_Month_Changed.else.actions.Condition_Budget_Exists_Same_Month.actions.Update_Current_Month_Budget.inputs.parameters.item
  Set-FieldValue -Map $updateCurrent -Name "qfu_sourcefile" -Value $preservedSourceFileExpr
  Set-FieldValue -Map $updateCurrent -Name "qfu_branchcode" -Value "@parameters('qfu_QFU_BranchCode')"
  Set-FieldValue -Map $updateCurrent -Name "qfu_branchslug" -Value "@parameters('qfu_QFU_BranchSlug')"
  Set-FieldValue -Map $updateCurrent -Name "qfu_regionslug" -Value "@parameters('qfu_QFU_RegionSlug')"
  Set-FieldValue -Map $updateCurrent -Name "qfu_sourcefamily" -Value "SA1300"
  Set-FieldValue -Map $updateCurrent -Name "qfu_year" -Value "@int(formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'yyyy'))"
  Set-FieldValue -Map $updateCurrent -Name "qfu_monthname" -Value "@formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'MMMM')"
  Set-FieldValue -Map $updateCurrent -Name "qfu_month" -Value "@int(formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'MM'))"
  Set-FieldValue -Map $updateCurrent -Name "qfu_isactive" -Value $false
  Set-FieldValue -Map $updateCurrent -Name "qfu_fiscalyear" -Value "@parameters('qfu_QFU_ActiveFiscalYear')"
  Set-FieldValue -Map $updateCurrent -Name "qfu_budgetamount" -Value $resolvedBudgetGoalExpr
  Set-FieldValue -Map $updateCurrent -Name "qfu_customername" -Value "@parameters('qfu_QFU_BranchName')"
  Set-FieldValue -Map $updateCurrent -Name "qfu_budgetgoal" -Value $resolvedBudgetGoalExpr
  Set-FieldValue -Map $updateCurrent -Name "qfu_budgetname" -Value "@concat(formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'MMMM'), ' ', formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'yyyy'), ' Budget')"
  Set-FieldValue -Map $updateCurrent -Name "qfu_name" -Value "@concat(parameters('qfu_QFU_BranchCode'), ' ', formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'MMMM yyyy'), ' Budget')"
  Set-FieldValue -Map $updateCurrent -Name "qfu_sourceid" -Value "@concat(parameters('qfu_QFU_BranchCode'), '|SA1300|', formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'yyyy-MM'))"
  Set-FieldValue -Map $updateCurrent -Name "qfu_actualsales" -Value $preservedActualSalesExpr
  Set-FieldValue -Map $updateCurrent -Name "qfu_cadsales" -Value $preservedCadSalesExpr
  Set-FieldValue -Map $updateCurrent -Name "qfu_usdsales" -Value $preservedUsdSalesExpr
  Set-FieldValue -Map $updateCurrent -Name "qfu_lastupdated" -Value $preservedLastUpdatedExpr
  Set-FieldValue -Map $updateCurrent -Name "qfu_opsdailycadjson" -Value $preservedCadOpsDailyExpr
  Set-FieldValue -Map $updateCurrent -Name "qfu_opsdailyusdjson" -Value $preservedUsdOpsDailyExpr
  $budgetActions.Condition_Check_Month_Changed.else.actions.Condition_Budget_Exists_Same_Month.actions.Update_Current_Month_Budget.inputs.parameters.item = [pscustomobject]$updateCurrent

  $archiveCreateAction = Copy-DeepObject $budgetActions.Condition_Check_Month_Changed.actions.Archive_Previous_Month_Budget
  $archiveRecord = Copy-OrderedMap $archiveCreateAction.inputs.parameters
  Set-FieldValue -Map $archiveRecord -Name "item/qfu_name" -Value "@concat(parameters('qfu_QFU_BranchCode'), ' ', outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_monthname'], ' ', outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_year'], ' Budget Target')"
  Set-FieldValue -Map $archiveRecord -Name "item/qfu_sourceid" -Value "@concat(parameters('qfu_QFU_BranchCode'), '|budgetarchive|', outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_fiscalyear'], '|', formatNumber(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_month'], '00'))"
  Set-FieldValue -Map $archiveRecord -Name "item/qfu_budgetgoal" -Value "@outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_budgetgoal']"
  Set-FieldValue -Map $archiveRecord -Name "item/qfu_month" -Value "@outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_month']"
  Set-FieldValue -Map $archiveRecord -Name "item/qfu_monthname" -Value "@outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_monthname']"
  Set-FieldValue -Map $archiveRecord -Name "item/qfu_year" -Value "@outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_year']"
  Set-FieldValue -Map $archiveRecord -Name "item/qfu_fiscalyear" -Value "@outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_fiscalyear']"
  Set-FieldValue -Map $archiveRecord -Name "item/qfu_lastupdated" -Value "@utcNow()"
  Set-FieldValue -Map $archiveRecord -Name "item/qfu_sourcefile" -Value "@items('Apply_to_each_Attachment')?['name']"
  Set-FieldValue -Map $archiveRecord -Name "item/qfu_branchcode" -Value "@parameters('qfu_QFU_BranchCode')"
  Set-FieldValue -Map $archiveRecord -Name "item/qfu_branchslug" -Value "@parameters('qfu_QFU_BranchSlug')"
  Set-FieldValue -Map $archiveRecord -Name "item/qfu_regionslug" -Value "@parameters('qfu_QFU_RegionSlug')"
  Set-FieldValue -Map $archiveRecord -Name "item/qfu_sourcefamily" -Value "SA1300"
  $archiveCreateAction.inputs.parameters = [pscustomobject]$archiveRecord

  $getExistingArchive = Copy-DeepObject $budgetActions.Get_Budget_Goal_From_Archives
  $getExistingArchiveParameters = Copy-OrderedMap $getExistingArchive.inputs.parameters
  Set-FieldValue -Map $getExistingArchiveParameters -Name 'entityName' -Value "qfu_budgetarchives"
  Set-FieldValue -Map $getExistingArchiveParameters -Name '$select' -Value "qfu_budgetarchiveid,qfu_sourceid,qfu_branchcode,qfu_month,qfu_year,qfu_fiscalyear"
  Set-FieldValue -Map $getExistingArchiveParameters -Name '$filter' -Value "qfu_branchcode eq '@{parameters('qfu_QFU_BranchCode')}' and qfu_month eq @{outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_month']} and qfu_fiscalyear eq '@{outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_fiscalyear']}'"
  Set-FieldValue -Map $getExistingArchiveParameters -Name '$top' -Value 1
  Set-FieldValue -Map $getExistingArchiveParameters -Name '$orderby' -Value "modifiedon desc, createdon desc"
  $getExistingArchive.inputs.parameters = [pscustomobject]$getExistingArchiveParameters
  $getExistingArchive.runAfter = [ordered]@{}
  $getExistingArchive.metadata.operationMetadataId = [guid]::NewGuid().Guid

  $archiveUpdateAction = Copy-DeepObject $budgetActions.Condition_Check_Month_Changed.actions.Deactivate_Old_Budget_Record
  $archiveUpdateAction.inputs.parameters.entityName = "qfu_budgetarchives"
  $archiveUpdateAction.inputs.parameters.recordId = "@outputs('Get_Existing_Archive_Budget')?['body/value']?[0]?['qfu_budgetarchiveid']"
  $archiveUpdateItem = [ordered]@{
    qfu_name = "@concat(parameters('qfu_QFU_BranchCode'), ' ', outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_monthname'], ' ', outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_year'], ' Budget Target')"
    qfu_sourceid = "@concat(parameters('qfu_QFU_BranchCode'), '|budgetarchive|', outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_fiscalyear'], '|', formatNumber(outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_month'], '00'))"
    qfu_budgetgoal = "@outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_budgetgoal']"
    qfu_month = "@outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_month']"
    qfu_monthname = "@outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_monthname']"
    qfu_year = "@outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_year']"
    qfu_fiscalyear = "@outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_fiscalyear']"
    qfu_lastupdated = "@utcNow()"
    qfu_sourcefile = "@items('Apply_to_each_Attachment')?['name']"
    qfu_branchcode = "@parameters('qfu_QFU_BranchCode')"
    qfu_branchslug = "@parameters('qfu_QFU_BranchSlug')"
    qfu_regionslug = "@parameters('qfu_QFU_RegionSlug')"
    qfu_sourcefamily = "SA1300"
  }
  $archiveUpdateAction.inputs.parameters.item = [pscustomobject]$archiveUpdateItem
  $archiveUpdateAction.runAfter = [ordered]@{}
  $archiveUpdateAction.metadata.operationMetadataId = [guid]::NewGuid().Guid

  $archiveExistsCondition = [ordered]@{
    type = "If"
    expression = [ordered]@{
      and = @(
        [ordered]@{
          greater = @(
            "@length(outputs('Get_Existing_Archive_Budget')?['body/value'])",
            0
          )
        }
      )
    }
    actions = [ordered]@{
      Update_Existing_Archive_Budget = $archiveUpdateAction
    }
    else = [ordered]@{
      actions = [ordered]@{
        Archive_Previous_Month_Budget = $archiveCreateAction
      }
    }
    runAfter = [ordered]@{
      Get_Existing_Archive_Budget = @("Succeeded")
    }
    metadata = [ordered]@{
      operationMetadataId = [guid]::NewGuid().Guid
    }
  }

  $budgetActions.Condition_Check_Month_Changed.actions.Deactivate_Old_Budget_Record.runAfter = [ordered]@{
    Condition_Archive_Budget_Exists = @("Succeeded")
  }
  $budgetActions.Condition_Check_Month_Changed.actions = [pscustomobject]([ordered]@{
    Get_Existing_Archive_Budget = $getExistingArchive
    Condition_Archive_Budget_Exists = $archiveExistsCondition
    Deactivate_Old_Budget_Record = $budgetActions.Condition_Check_Month_Changed.actions.Deactivate_Old_Budget_Record
    Condition_Current_Month_Budget_Record_Exists = $budgetActions.Condition_Check_Month_Changed.actions.Condition_Current_Month_Budget_Record_Exists
  })
  $budgetActions.Ensure_Budget_Goal_Found.expression = [pscustomobject]([ordered]@{
      and = @(
        [ordered]@{
          not = [ordered]@{
            equals = @(
              $resolvedBudgetGoalExpr,
              $null
            )
          }
        }
      )
    })
  $budgetActions.Ensure_Budget_Goal_Found.runAfter = [ordered]@{
    Get_Active_Budget = @("Succeeded")
  }
  $budgetActions.Condition_Check_Month_Changed.runAfter = [ordered]@{
    Ensure_Budget_Goal_Found = @("Succeeded")
  }
  $updatedBudgetRootActions = [ordered]@{}
  foreach ($property in @($budgetRootActions.PSObject.Properties)) {
    if ($property.Name -in @("Create_Budget_Target_Table", "List_Budget_Target_Rows", "Filter_Budget_Target_Rows", "Resolve_Budget_Goal_From_SA1300_Plan")) {
      continue
    }

    if ($property.Name -eq "Guard_Budget_Row_Limit") {
      $updatedBudgetRootActions.Create_Budget_Target_Table = $createBudgetTargetTable
      $updatedBudgetRootActions.List_Budget_Target_Rows = $listBudgetTargetRows
      $updatedBudgetRootActions.Filter_Budget_Target_Rows = $filterBudgetTargetRows
      $updatedBudgetRootActions.Resolve_Budget_Goal_From_SA1300_Plan = $resolveBudgetGoalFromPlan
    }

    $updatedBudgetRootActions[$property.Name] = $property.Value
  }
  $definition.actions.Apply_to_each_Attachment.actions.Condition_Is_SA1300_File.actions = [pscustomobject]$updatedBudgetRootActions
  if ($definition.actions.PSObject.Properties['Terminate_If_No_Budget_Goal']) {
    $terminateAction = $definition.actions.Terminate_If_No_Budget_Goal.actions.Terminate_No_Budget_Goal_Found
    if ($terminateAction -and $terminateAction.inputs -and $terminateAction.inputs.runError) {
      $terminateAction.inputs.runError.message = "No budget target was found from qfu_budgetarchive or the SA1300 Month-End Plan."
    }
  }

  Add-Sa1300AbnormalMarginActions -Definition $definition -BudgetRootActions $definition.actions.Apply_to_each_Attachment.actions.Condition_Is_SA1300_File.actions -FlowName $flowName
  Add-Sa1300OpsDailyActions -Definition $definition -BudgetRootActions $definition.actions.Apply_to_each_Attachment.actions.Condition_Is_SA1300_File.actions -Branch $Branch
  $budgetBatchActions = New-IngestionBatchSyncActionSet `
    -ActionPrefix "Budget" `
    -ImportNameSuffix "Budget Workbook Import" `
    -SourceFamily "SA1300" `
    -FlowNameExpression "@concat(parameters('qfu_QFU_BranchCode'), '-Budget-Update-SA1300')" `
    -FileNameExpression "@items('Apply_to_each_Attachment')?['name']" `
    -StartedOnExpression "@utcNow()" `
    -RunAfter ([ordered]@{
        Create_Abnormal_Margin_Batch = @("Succeeded")
        Apply_to_each_CAD_Ops_Daily_Row = @("Succeeded", "Skipped")
        Condition_Current_Month_Budget_Record_For_Analytics_Exists = @("Succeeded")
      })
  $budgetRootActions = $definition.actions.Apply_to_each_Attachment.actions.Condition_Is_SA1300_File.actions
  Set-FieldValue -Map $budgetRootActions -Name $budgetBatchActions.ListActionName -Value $budgetBatchActions.ListAction
  Set-FieldValue -Map $budgetRootActions -Name $budgetBatchActions.ConditionActionName -Value $budgetBatchActions.ConditionAction

  Add-Note -Notes $Notes -Text "Budget flow now enforces trigger concurrency = 1, treats qfu_isactive false as active, resolves current-month rows by qfu_sourceid plus active fiscal year, falls back from qfu_budgetarchive to the SA1300 Month-End Plan before flagging a missing target, checks branch+month+fiscal year before creating qfu_budgetarchive, blocks stale same-month SA1300 actuals from rolling back the live qfu_budget/qfu_branchopsdaily state, replaces the current branch's same-day qfu_marginexception snapshot directly from the SA1300 abnormal margin sheet, refreshes qfu_branchopsdaily rows from branch-configured SA1300 Daily Sales- Location ranges without overlapping USD/CAD temporary tables, stores the latest CAD/USD Daily Sales- Location payload on the current qfu_budget row for analytics, and refreshes the stable qfu_ingestionbatch freshness row that analytics reads."
}

function New-WorkflowDataXml {
  param(
    [string]$WorkflowId,
    [string]$FlowName
  )

  $workflowIdUpper = $WorkflowId.ToUpperInvariant()
  return @"
<?xml version="1.0" encoding="utf-8"?>
<Workflow WorkflowId="{$workflowIdUpper}" Name="$FlowName" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <JsonFileName>/Workflows/$FlowName-$workflowIdUpper.json</JsonFileName>
  <Type>1</Type>
  <Subprocess>0</Subprocess>
  <Category>5</Category>
  <Mode>0</Mode>
  <Scope>4</Scope>
  <OnDemand>0</OnDemand>
  <TriggerOnCreate>0</TriggerOnCreate>
  <TriggerOnDelete>0</TriggerOnDelete>
  <AsyncAutodelete>0</AsyncAutodelete>
  <SyncWorkflowLogOnFailure>0</SyncWorkflowLogOnFailure>
  <StateCode>0</StateCode>
  <StatusCode>1</StatusCode>
  <RunAs>1</RunAs>
  <IsTransacted>1</IsTransacted>
  <IntroducedVersion>1.0</IntroducedVersion>
  <IsCustomizable>1</IsCustomizable>
  <RendererObjectTypeCode>0</RendererObjectTypeCode>
  <IsCustomProcessingStepAllowedForOtherPublishers>1</IsCustomProcessingStepAllowedForOtherPublishers>
  <ModernFlowType>0</ModernFlowType>
  <PrimaryEntity>none</PrimaryEntity>
  <LocalizedNames>
    <LocalizedName languagecode="1033" description="$FlowName" />
  </LocalizedNames>
</Workflow>
"@
}

Remove-IfExists $solutionRoot
Remove-IfExists $zipPath
Remove-IfExists $mapPath

Ensure-Directory $otherRoot
Ensure-Directory $workflowRoot

$flowManifest = New-Object System.Collections.Generic.List[object]
$rootComponents = New-Object System.Collections.Generic.List[string]

foreach ($branch in $branchSpecs) {
  foreach ($template in $templateSpecs) {
    $sourcePath = Join-Path $sourceWorkflowRoot $template.SourceFile
    if (-not (Test-Path -LiteralPath $sourcePath)) {
      throw "Source flow template not found: $sourcePath"
    }

    $json = Get-WorkflowTemplate -Path $sourcePath
    $flowName = "$($branch.BranchCode)-$($template.TargetSuffix)"
    $workflowKey = "$($branch.BranchCode)|$($template.Family)"
    if (-not $workflowIdMap.ContainsKey($workflowKey)) {
      throw "No canonical workflow ID configured for $workflowKey"
    }
    $workflowId = $workflowIdMap[$workflowKey]
    $notes = New-Object System.Collections.Generic.List[string]

    switch ($template.Family) {
      "Quote" { Update-QuoteFlow -Json $json -Branch $branch -Template $template -Notes $notes }
      "Backorder" { Update-BackorderFlow -Json $json -Branch $branch -Template $template -Notes $notes }
      "Budget" { Update-BudgetFlow -Json $json -Branch $branch -Template $template -Notes $notes }
      default { throw "Unsupported template family: $($template.Family)" }
    }

    $jsonName = "$flowName-$($workflowId.ToUpperInvariant()).json"
    $dataXmlName = "$jsonName.data.xml"

    Write-Utf8File -Path (Join-Path $workflowRoot $jsonName) -Content (Convert-ToJsonCompact -Object $json)
    Write-Utf8File -Path (Join-Path $workflowRoot $dataXmlName) -Content (New-WorkflowDataXml -WorkflowId $workflowId -FlowName $flowName)

    $rootComponents.Add('      <RootComponent type="29" id="{' + $workflowId + '}" behavior="0" />') | Out-Null
    $flowManifest.Add([pscustomobject]@{
        branch_code = $branch.BranchCode
        branch_slug = $branch.BranchSlug
        branch_name = $branch.BranchName
        family = $template.Family
        source_flow = $template.SourceFlowName
        target_flow = $flowName
        workflow_id = $workflowId
        source_template = $sourcePath
        notes = @($notes)
      }) | Out-Null
  }
}

foreach ($branch in $branchSpecs) {
  $flowManifest.Add([pscustomobject]@{
      branch_code = $branch.BranchCode
      branch_slug = $branch.BranchSlug
      branch_name = $branch.BranchName
      family = "Finance"
      source_flow = $null
      target_flow = $null
      workflow_id = $null
      source_template = $null
      notes = @(
        "Future GL060 ingestion must trigger when the email first lands in Inbox.",
        "Do not rely on later folder moves inside the shared mailbox.",
        "Subject filter: GL060 P&L report - Last month",
        "Attachment pattern: GL060 Report - Profit Center*.pdf"
      )
    }) | Out-Null
}

$solutionXml = @"
<?xml version="1.0" encoding="utf-8"?>
<ImportExportXml version="9.2.26033.148" SolutionPackageVersion="9.2" languagecode="1033" generatedBy="CrmLive" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" OrganizationVersion="9.2.26033.148" OrganizationSchemaType="Standard" CRMServerServiceabilityVersion="9.2.26033.00148">
  <SolutionManifest>
    <UniqueName>$SolutionUniqueName</UniqueName>
    <LocalizedNames>
      <LocalizedName description="$SolutionDisplayName" languagecode="1033" />
    </LocalizedNames>
    <Descriptions />
    <Version>$SolutionVersion</Version>
    <Managed>0</Managed>
    <Publisher>
      <UniqueName>qfu</UniqueName>
      <LocalizedNames>
        <LocalizedName description="qfu" languagecode="1033" />
      </LocalizedNames>
      <Descriptions />
      <EMailAddress xsi:nil="true"></EMailAddress>
      <SupportingWebsiteUrl xsi:nil="true"></SupportingWebsiteUrl>
      <CustomizationPrefix>qfu</CustomizationPrefix>
      <CustomizationOptionValuePrefix>98501</CustomizationOptionValuePrefix>
      <Addresses>
        <Address><AddressNumber>1</AddressNumber></Address>
        <Address><AddressNumber>2</AddressNumber></Address>
      </Addresses>
    </Publisher>
    <RootComponents>
$($rootComponents -join "`r`n")
    </RootComponents>
    <MissingDependencies />
  </SolutionManifest>
</ImportExportXml>
"@

$customizationsXml = @"
<?xml version="1.0" encoding="utf-8"?>
<ImportExportXml xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" OrganizationVersion="9.2.26033.148" OrganizationSchemaType="Standard" CRMServerServiceabilityVersion="9.2.26033.00148">
  <Entities />
  <Roles />
  <Workflows />
  <FieldSecurityProfiles />
  <Templates />
  <EntityMaps />
  <EntityRelationships />
  <OrganizationSettings />
  <optionsets />
  <CustomControls />
  <EntityDataProviders />
  <connectionreferences>
    <connectionreference connectionreferencelogicalname="qfu_shared_commondataserviceforapps">
      <connectionreferencedisplayname>qfu_shared_commondataserviceforapps</connectionreferencedisplayname>
      <connectorid>/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps</connectorid>
      <iscustomizable>1</iscustomizable>
      <promptingbehavior>0</promptingbehavior>
      <statecode>0</statecode>
      <statuscode>1</statuscode>
    </connectionreference>
    <connectionreference connectionreferencelogicalname="qfu_shared_excelonlinebusiness">
      <connectionreferencedisplayname>qfu_shared_excelonlinebusiness</connectionreferencedisplayname>
      <connectorid>/providers/Microsoft.PowerApps/apis/shared_excelonlinebusiness</connectorid>
      <iscustomizable>1</iscustomizable>
      <promptingbehavior>0</promptingbehavior>
      <statecode>0</statecode>
      <statuscode>1</statuscode>
    </connectionreference>
    <connectionreference connectionreferencelogicalname="qfu_shared_office365">
      <connectionreferencedisplayname>qfu_shared_office365</connectionreferencedisplayname>
      <connectorid>/providers/Microsoft.PowerApps/apis/shared_office365</connectorid>
      <iscustomizable>1</iscustomizable>
      <promptingbehavior>0</promptingbehavior>
      <statecode>0</statecode>
      <statuscode>1</statuscode>
    </connectionreference>
    <connectionreference connectionreferencelogicalname="qfu_shared_onedriveforbusiness">
      <connectionreferencedisplayname>qfu_shared_onedriveforbusiness</connectionreferencedisplayname>
      <connectorid>/providers/Microsoft.PowerApps/apis/shared_onedriveforbusiness</connectorid>
      <iscustomizable>1</iscustomizable>
      <promptingbehavior>0</promptingbehavior>
      <statecode>0</statecode>
      <statuscode>1</statuscode>
    </connectionreference>
  </connectionreferences>
  <Languages>
    <Language>1033</Language>
  </Languages>
</ImportExportXml>
"@

$relationshipsXml = @"
<?xml version="1.0" encoding="utf-8"?>
<EntityRelationships xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" />
"@

Write-Utf8File -Path (Join-Path $otherRoot "Solution.xml") -Content $solutionXml
Write-Utf8File -Path (Join-Path $otherRoot "Customizations.xml") -Content $customizationsXml
Write-Utf8File -Path (Join-Path $otherRoot "Relationships.xml") -Content $relationshipsXml
Write-Utf8File -Path $mapPath -Content (Convert-ToJsonCompact -Object $flowManifest)

& pac solution pack --folder $sourceRoot --zipfile $zipPath --packagetype Unmanaged
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $zipPath)) {
  throw "pac solution pack failed for $zipPath"
}

if ($ImportToTarget) {
  & pac solution import --environment $TargetEnvironmentUrl --path $zipPath --force-overwrite --publish-changes
  if ($LASTEXITCODE -ne 0) {
    throw "pac solution import failed for $zipPath"
  }

  $workflowIds = @($flowManifest | ForEach-Object { [string]$_.workflow_id })
  Activate-ImportedWorkflows -Url $TargetEnvironmentUrl -WorkflowIds $workflowIds
  Enable-ImportedAdminFlows -EnvironmentName $TargetEnvironmentName -WorkflowIds $workflowIds
}

Write-Host "SOLUTION_ROOT=$solutionRoot"
Write-Host "ZIP_PATH=$zipPath"
Write-Host "FLOW_COUNT=$($flowManifest.Count)"
