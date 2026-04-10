param(
  [string]$RepoRoot = "C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion",
  [string]$TargetEnvironmentUrl = "https://regionaloperationshub.crm.dynamics.com",
  [string]$SolutionUniqueName = "qfu_sapilotflows",
  [string]$SolutionDisplayName = "QFU Southern Alberta Pilot Flows",
  [string]$SolutionVersion = "1.0.0.1",
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
  [pscustomobject]@{ BranchCode = "4171"; BranchSlug = "4171-calgary"; BranchName = "Calgary"; MailboxAddress = "4171@applied.com"; SortOrder = 1 },
  [pscustomobject]@{ BranchCode = "4172"; BranchSlug = "4172-lethbridge"; BranchName = "Lethbridge"; MailboxAddress = "4172@applied.com"; SortOrder = 2 },
  [pscustomobject]@{ BranchCode = "4173"; BranchSlug = "4173-medicine-hat"; BranchName = "Medicine Hat"; MailboxAddress = "4173@applied.com"; SortOrder = 3 }
)

$templateSpecs = @(
  [pscustomobject]@{
    Family = "Quote"
    SourceFlowName = "QuoteFollow-UpImport-Staging_DEV"
    SourceFile = "QuoteFollow-UpImport-Staging_DEV-7742C979-E2EB-F011-8406-000D3AF4C93E.json"
    TargetSuffix = "QuoteFollowUp-Import-Staging"
    SourceFamily = "SP830CA"
    SubjectFilter = $null
  },
  [pscustomobject]@{
    Family = "Backorder"
    SourceFlowName = "BackOrder_Update_From_CA_ZBO_DEV"
    SourceFile = "BackOrder_Update_From_CA_ZBO_DEV-5C42C979-E2EB-F011-8406-000D3AF4C93E.json"
    TargetSuffix = "BackOrder-Update-ZBO"
    SourceFamily = "ZBO"
    SubjectFilter = $null
  },
  [pscustomobject]@{
    Family = "Budget"
    SourceFlowName = "Budget_Update_From_SA1300_Unmanaged_DEV"
    SourceFile = "Budget_Update_From_SA1300_Unmanaged_DEV-6942C979-E2EB-F011-8406-000D3AF4C93E.json"
    TargetSuffix = "Budget-Update-SA1300"
    SourceFamily = "SA1300"
    SubjectFilter = $null
  }
)

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
  return $Definition.triggers.PSObject.Properties[0].Name
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
      type = "OpenApiConnectionNotification"
      description = $Description
      inputs = [ordered]@{
        parameters = $parameters
        host = [ordered]@{
          apiId = "/providers/Microsoft.PowerApps/apis/shared_office365"
          operationId = "SharedMailboxOnNewEmailV2"
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

function Update-QuoteFlow {
  param(
    [object]$Json,
    [object]$Branch,
    [object]$Template,
    [System.Collections.Generic.List[string]]$Notes
  )

  $definition = $Json.properties.definition
  Add-BranchParameters -Definition $definition -Branch $Branch -Template $Template
  Set-SharedMailboxTrigger -Definition $definition -Description "Triggers when a new SP830CA workbook lands in the $($Branch.BranchCode) $($Branch.BranchName) shared mailbox." -SubjectFilter $Template.SubjectFilter

  $quoteActions = $definition.actions.Check_if_weekday.actions.Apply_to_each_attachment.actions.Condition_Is_SP830CA_File.actions
  $lineActions = $quoteActions.Guard_Quote_Rows.actions.Apply_to_each_quote_line.actions
  $quoteActions.Create_attachment_file.inputs.parameters.name = "@concat(parameters('qfu_QFU_BranchCode'), '_QuoteFollowUp_', formatDateTime(utcNow(), 'yyyyMMdd_HHmmss'), '_', items('Apply_to_each_attachment')?['name'])"
  $lineActions.Compose_UniqueKey.inputs = "@concat(parameters('qfu_QFU_BranchCode'), '_', items('Apply_to_each_quote_line')?['quotenumber'], '_', items('Apply_to_each_quote_line')?['linenumber'])"
  $lineActions.Check_Quote_Exists.inputs.parameters.'$filter' = "qfu_sourceid eq '@{concat(parameters('qfu_QFU_BranchCode'), '|SP830CA|', items('Apply_to_each_quote_line')?['quotenumber'])}'"
  $lineActions.Resolve_Quote_For_Line.inputs.parameters.'$filter' = "qfu_sourceid eq '@{concat(parameters('qfu_QFU_BranchCode'), '|SP830CA|', items('Apply_to_each_quote_line')?['quotenumber'])}'"

  $updateHeader = Copy-OrderedMap $lineActions.Condition_Quote_Exists.actions.Update_Quote_Header.inputs.parameters
  Set-FieldValue -Map $updateHeader -Name "item/qfu_name" -Value "@concat(parameters('qfu_QFU_BranchCode'), ' ', items('Apply_to_each_quote_line')?['quotenumber'])"
  Set-FieldValue -Map $updateHeader -Name "item/qfu_sourceid" -Value "@concat(parameters('qfu_QFU_BranchCode'), '|SP830CA|', items('Apply_to_each_quote_line')?['quotenumber'])"
  Set-FieldValue -Map $updateHeader -Name "item/qfu_branchcode" -Value "@parameters('qfu_QFU_BranchCode')"
  Set-FieldValue -Map $updateHeader -Name "item/qfu_branchslug" -Value "@parameters('qfu_QFU_BranchSlug')"
  Set-FieldValue -Map $updateHeader -Name "item/qfu_regionslug" -Value "@parameters('qfu_QFU_RegionSlug')"
  Set-FieldValue -Map $updateHeader -Name "item/qfu_sourcefamily" -Value "SP830CA"
  Set-FieldValue -Map $updateHeader -Name "item/qfu_sourcefile" -Value "@items('Apply_to_each_attachment')?['name']"
  Set-FieldValue -Map $updateHeader -Name "item/qfu_sourceworksheet" -Value "Daily"
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
  Set-FieldValue -Map $createHeader -Name "item/qfu_cssr" -Value "@if(equals(items('Apply_to_each_quote_line')?['cssr'], null), null, string(items('Apply_to_each_quote_line')?['cssr']))"
  Set-FieldValue -Map $createHeader -Name "item/qfu_tsr" -Value "@if(equals(items('Apply_to_each_quote_line')?['tsr'], null), null, string(items('Apply_to_each_quote_line')?['tsr']))"
  $lineActions.Condition_Quote_Exists.else.actions.Create_Quote_Header.inputs.parameters = [pscustomobject]$createHeader

  foreach ($actionName in @("Update_Quote_Line", "Create_Quote_Line")) {
    $action = if ($actionName -eq "Update_Quote_Line") { $lineActions.Condition_Line_Exists.actions.Update_Quote_Line } else { $lineActions.Condition_Line_Exists.else.actions.Create_Quote_Line }
    $itemMap = Copy-OrderedMap $action.inputs.parameters
    Remove-PropertyIfPresent -Object $itemMap -Name "item/qfu_quoteid@odata.bind"
    Set-FieldValue -Map $itemMap -Name "item/qfu_name" -Value "@concat(parameters('qfu_QFU_BranchCode'), ' ', items('Apply_to_each_quote_line')?['quotenumber'], ' / ', items('Apply_to_each_quote_line')?['linenumber'])"
    Set-FieldValue -Map $itemMap -Name "item/qfu_sourceid" -Value "@outputs('Compose_UniqueKey')"
    Set-FieldValue -Map $itemMap -Name "item/qfu_branchcode" -Value "@parameters('qfu_QFU_BranchCode')"
    Set-FieldValue -Map $itemMap -Name "item/qfu_branchslug" -Value "@parameters('qfu_QFU_BranchSlug')"
    Set-FieldValue -Map $itemMap -Name "item/qfu_regionslug" -Value "@parameters('qfu_QFU_RegionSlug')"
    Set-FieldValue -Map $itemMap -Name "item/qfu_sourcefamily" -Value "SP830CA"
    Set-FieldValue -Map $itemMap -Name "item/qfu_sourcefile" -Value "@items('Apply_to_each_attachment')?['name']"
    Set-FieldValue -Map $itemMap -Name "item/qfu_sourceworksheet" -Value "Daily"
    Set-FieldValue -Map $itemMap -Name "item/qfu_sourcedate" -Value "@if(empty(items('Apply_to_each_quote_line')?['sapcreatedon']), null, formatDateTime(items('Apply_to_each_quote_line')?['sapcreatedon'], 'yyyy-MM-dd'))"
    Set-FieldValue -Map $itemMap -Name "item/qfu_cssr" -Value "@if(equals(items('Apply_to_each_quote_line')?['cssr'], null), null, string(items('Apply_to_each_quote_line')?['cssr']))"
    Set-FieldValue -Map $itemMap -Name "item/qfu_tsr" -Value "@if(equals(items('Apply_to_each_quote_line')?['tsr'], null), null, string(items('Apply_to_each_quote_line')?['tsr']))"
    $action.inputs.parameters = [pscustomobject]$itemMap
  }

  Add-Note -Notes $Notes -Text "Quote flow keeps source-style header and line upserts, but header amount is still line-driven; the pilot page should prefer line aggregation once qfu_quoteline is exposed."
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
  Set-SharedMailboxTrigger -Definition $definition -Description "Triggers when a new ZBO workbook lands in the $($Branch.BranchCode) $($Branch.BranchName) shared mailbox." -SubjectFilter $Template.SubjectFilter

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
  $backorderActions = $conditionActions.Guard_BackOrder_Row_Limit.actions.Condition_Has_New_Rows.actions
  $listOldParameters = Copy-OrderedMap $backorderActions.List_Old_BackOrders.inputs.parameters
  Set-FieldValue -Map $listOldParameters -Name '$filter' -Value "qfu_branchcode eq '@{parameters('qfu_QFU_BranchCode')}'"
  $backorderActions.List_Old_BackOrders.inputs.parameters = [pscustomobject]$listOldParameters

  $createRecord = Copy-OrderedMap $backorderActions.Insert_New_BackOrders.actions.Create_BackOrder_Record.inputs.parameters
  Set-FieldValue -Map $createRecord -Name "item/qfu_name" -Value "@concat(parameters('qfu_QFU_BranchCode'), '-BO-', items('Insert_New_BackOrders')?['salesDocNumber'], '-', items('Insert_New_BackOrders')?['lineNumber'])"
  Set-FieldValue -Map $createRecord -Name "item/qfu_sourceid" -Value "@concat(parameters('qfu_QFU_BranchCode'), '|ZBO|', items('Insert_New_BackOrders')?['salesDocNumber'], '|', items('Insert_New_BackOrders')?['lineNumber'])"
  Set-FieldValue -Map $createRecord -Name "item/qfu_branchcode" -Value "@parameters('qfu_QFU_BranchCode')"
  Set-FieldValue -Map $createRecord -Name "item/qfu_branchslug" -Value "@parameters('qfu_QFU_BranchSlug')"
  Set-FieldValue -Map $createRecord -Name "item/qfu_regionslug" -Value "@parameters('qfu_QFU_RegionSlug')"
  Set-FieldValue -Map $createRecord -Name "item/qfu_sourcefamily" -Value "ZBO"
  Set-FieldValue -Map $createRecord -Name "item/qfu_sourcefile" -Value "@items('Apply_to_each_Attachment')?['name']"
  Set-FieldValue -Map $createRecord -Name "item/qfu_sourceline" -Value "@string(items('Insert_New_BackOrders')?['lineNumber'])"
  $backorderActions.Insert_New_BackOrders.actions.Create_BackOrder_Record.inputs.parameters = [pscustomobject]$createRecord
}

function Update-BudgetFlow {
  param(
    [object]$Json,
    [object]$Branch,
    [object]$Template,
    [System.Collections.Generic.List[string]]$Notes
  )

  $definition = $Json.properties.definition
  Add-BranchParameters -Definition $definition -Branch $Branch -Template $Template
  Set-SharedMailboxTrigger -Definition $definition -Description "Triggers when a new SA1300 workbook lands in the $($Branch.BranchCode) $($Branch.BranchName) shared mailbox." -SubjectFilter $Template.SubjectFilter
  $definition.triggers.Shared_Mailbox_New_Email.runtimeConfiguration = [ordered]@{
    concurrency = [ordered]@{
      runs = 1
    }
  }

  $budgetRootActions = $definition.actions.Apply_to_each_Attachment.actions.Condition_Is_SA1300_File.actions
  $budgetRootActions.Create_File_in_OneDrive.inputs.parameters.name = "@concat(parameters('qfu_QFU_BranchCode'), '_SA1300_', formatDateTime(utcNow(), 'yyyyMMdd_HHmmss'), '.xlsx')"
  $budgetActions = $budgetRootActions.Guard_Budget_Row_Limit.actions
  $budgetActions.Get_Budget_Goal_From_Archives.inputs.parameters.'$filter' = "qfu_branchcode eq '@{parameters('qfu_QFU_BranchCode')}' and qfu_month eq @{int(formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'MM'))} and qfu_fiscalyear eq '@{parameters('qfu_QFU_ActiveFiscalYear')}'"
  $budgetActions.Get_Budget_Goal_From_Archives.inputs.parameters.'$orderby' = "modifiedon desc, createdon desc"
  $budgetActions.Get_Active_Budget.inputs.parameters.'$filter' = "qfu_isactive eq false and qfu_branchcode eq '@{parameters('qfu_QFU_BranchCode')}' and qfu_sourcefamily eq 'SA1300'"
  $budgetActions.Get_Active_Budget.inputs.parameters.'$orderby' = "qfu_lastupdated desc, createdon desc"
  if ($budgetActions.PSObject.Properties['Get_Current_Month_Budget_Record']) {
    $budgetActions.Get_Current_Month_Budget_Record.inputs.parameters.'$filter' = "qfu_branchcode eq '@{parameters('qfu_QFU_BranchCode')}' and qfu_sourcefamily eq 'SA1300' and qfu_sourceid eq '@{concat(parameters('qfu_QFU_BranchCode'), '|SA1300|', formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'yyyy-MM'))}'"
    $budgetActions.Get_Current_Month_Budget_Record.inputs.parameters.'$top' = 1
    $budgetActions.Get_Current_Month_Budget_Record.inputs.parameters.'$orderby' = "createdon desc"
  }

  foreach ($action in @(
      $budgetActions.Condition_Check_Month_Changed.actions.Create_New_Month_Budget_Record,
      $budgetActions.Condition_Check_Month_Changed.else.actions.Condition_Budget_Exists_Same_Month.else.actions.Create_First_Budget_Record
    )) {
    $parameters = Copy-OrderedMap $action.inputs.parameters
    Set-FieldValue -Map $parameters -Name "item/qfu_name" -Value "@concat(parameters('qfu_QFU_BranchCode'), ' ', formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'MMMM yyyy'), ' Budget')"
    Set-FieldValue -Map $parameters -Name "item/qfu_sourceid" -Value "@concat(parameters('qfu_QFU_BranchCode'), '|SA1300|', formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'yyyy-MM'))"
    Set-FieldValue -Map $parameters -Name "item/qfu_budgetname" -Value "@concat(parameters('qfu_QFU_BranchCode'), ' ', formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'MMMM yyyy'), ' Budget')"
    Set-FieldValue -Map $parameters -Name "item/qfu_budgetamount" -Value "@first(outputs('Get_Budget_Goal_From_Archives')?['body/value'])?['qfu_budgetgoal']"
    Set-FieldValue -Map $parameters -Name "item/qfu_branchcode" -Value "@parameters('qfu_QFU_BranchCode')"
    Set-FieldValue -Map $parameters -Name "item/qfu_branchslug" -Value "@parameters('qfu_QFU_BranchSlug')"
    Set-FieldValue -Map $parameters -Name "item/qfu_regionslug" -Value "@parameters('qfu_QFU_RegionSlug')"
    Set-FieldValue -Map $parameters -Name "item/qfu_sourcefamily" -Value "SA1300"
    Set-FieldValue -Map $parameters -Name "item/qfu_customername" -Value "@parameters('qfu_QFU_BranchName')"
    $action.inputs.parameters = [pscustomobject]$parameters
    $itemMap = Copy-OrderedMap $action.inputs.parameters.item
    Set-FieldValue -Map $itemMap -Name "qfu_isactive" -Value $false
    Set-FieldValue -Map $itemMap -Name "qfu_fiscalyear" -Value "@parameters('qfu_QFU_ActiveFiscalYear')"
    Set-FieldValue -Map $itemMap -Name "qfu_budgetamount" -Value "@first(outputs('Get_Budget_Goal_From_Archives')?['body/value'])?['qfu_budgetgoal']"
    Set-FieldValue -Map $itemMap -Name "qfu_customername" -Value "@parameters('qfu_QFU_BranchName')"
    Set-FieldValue -Map $itemMap -Name "qfu_sourcefile" -Value "@items('Apply_to_each_Attachment')?['name']"
    Set-FieldValue -Map $itemMap -Name "qfu_branchcode" -Value "@parameters('qfu_QFU_BranchCode')"
    Set-FieldValue -Map $itemMap -Name "qfu_branchslug" -Value "@parameters('qfu_QFU_BranchSlug')"
    Set-FieldValue -Map $itemMap -Name "qfu_regionslug" -Value "@parameters('qfu_QFU_RegionSlug')"
    Set-FieldValue -Map $itemMap -Name "qfu_sourcefamily" -Value "SA1300"
    $action.inputs.parameters.item = [pscustomobject]$itemMap
  }

  $updateCurrent = Copy-OrderedMap $budgetActions.Condition_Check_Month_Changed.else.actions.Condition_Budget_Exists_Same_Month.actions.Update_Current_Month_Budget.inputs.parameters.item
  Set-FieldValue -Map $updateCurrent -Name "qfu_sourcefile" -Value "@items('Apply_to_each_Attachment')?['name']"
  Set-FieldValue -Map $updateCurrent -Name "qfu_branchcode" -Value "@parameters('qfu_QFU_BranchCode')"
  Set-FieldValue -Map $updateCurrent -Name "qfu_branchslug" -Value "@parameters('qfu_QFU_BranchSlug')"
  Set-FieldValue -Map $updateCurrent -Name "qfu_regionslug" -Value "@parameters('qfu_QFU_RegionSlug')"
  Set-FieldValue -Map $updateCurrent -Name "qfu_sourcefamily" -Value "SA1300"
  Set-FieldValue -Map $updateCurrent -Name "qfu_sourceid" -Value "@concat(parameters('qfu_QFU_BranchCode'), '|SA1300|', formatDateTime(convertTimeZone(utcNow(), 'UTC', 'Mountain Standard Time'), 'yyyy-MM'))"
  Set-FieldValue -Map $updateCurrent -Name "qfu_isactive" -Value $false
  Set-FieldValue -Map $updateCurrent -Name "qfu_fiscalyear" -Value "@parameters('qfu_QFU_ActiveFiscalYear')"
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
  $getExistingArchive.inputs.parameters.entityName = "qfu_budgetarchives"
  $getExistingArchive.inputs.parameters.'$select' = "qfu_budgetarchiveid,qfu_sourceid,qfu_branchcode,qfu_month,qfu_year,qfu_fiscalyear"
  $getExistingArchive.inputs.parameters.'$filter' = "qfu_branchcode eq '@{parameters('qfu_QFU_BranchCode')}' and qfu_month eq @{outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_month']} and qfu_fiscalyear eq '@{outputs('Get_Active_Budget')?['body/value']?[0]?['qfu_fiscalyear']}'"
  $getExistingArchive.inputs.parameters.'$top' = 1
  $getExistingArchive.inputs.parameters.'$orderby' = "modifiedon desc, createdon desc"
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

  Add-Note -Notes $Notes -Text "Budget flow now enforces trigger concurrency = 1, treats qfu_isactive false as active, resolves current-month rows by qfu_sourceid, and checks branch+month+fiscal year before creating qfu_budgetarchive."
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
}

Write-Host "SOLUTION_ROOT=$solutionRoot"
Write-Host "ZIP_PATH=$zipPath"
Write-Host "FLOW_COUNT=$($flowManifest.Count)"
