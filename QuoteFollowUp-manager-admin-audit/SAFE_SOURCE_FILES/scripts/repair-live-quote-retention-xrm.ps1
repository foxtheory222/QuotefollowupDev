param(
  [string]$RepoRoot = "C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion",
  [string]$TargetEnvironmentUrl = "<URL>
  [string]$Username = "<EMAIL>",
  [string[]]$BranchCodes = @("4171", "4172", "4173"),
  [string]$OutputPath = "",
  [string]$ArtifactRoot = ""
)

$ErrorActionPreference = "Stop"

$flowCatalog = @(
  [pscustomobject]@{
    BranchCode = "4171"
    DisplayName = "4171-QuoteFollowUp-Import-Staging"
  },
  [pscustomobject]@{
    BranchCode = "4172"
    DisplayName = "4172-QuoteFollowUp-Import-Staging"
  },
  [pscustomobject]@{
    BranchCode = "4173"
    DisplayName = "4173-QuoteFollowUp-Import-Staging"
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

  $byName = @(
    (Get-CrmRecords -conn $Connection -EntityLogicalName workflow -FilterAttribute "name" -FilterOperator eq -FilterValue $Flow.DisplayName -Fields $fields -TopCount 10).CrmRecords |
      Sort-Object { if ($_.modifiedon) { [datetime]$_.modifiedon } else { [datetime]::MinValue } } -Descending
  ) | Select-Object -First 1

  if ($byName) {
    return $byName
  }

  throw "Workflow not found for $($Flow.DisplayName)"
}

function Get-QuoteFlowStateSummary {
  param(
    [object]$WorkflowRecord,
    [object]$WorkflowJson
  )

  $definition = $WorkflowJson.properties.definition
  $attachmentCondition = $definition.actions.Check_if_weekday.actions.Apply_to_each_attachment.actions.Condition_Is_SP830CA_File
  $quoteActions = $attachmentCondition.actions
  $lineActions = $quoteActions.Guard_Quote_Rows.actions.Apply_to_each_quote_line.actions

  return [pscustomobject]@{
    workflow_name = [string]$WorkflowRecord.name
    workflow_id = [string]$WorkflowRecord.workflowid
    workflow_state = [string]$WorkflowRecord.statecode
    workflow_status = [string]$WorkflowRecord.statuscode
    workflow_modifiedon = [string]$WorkflowRecord.modifiedon
    attachment_gate = $attachmentCondition.expression
    quote_select = [string]$lineActions.Check_Quote_Exists.inputs.parameters.'$select'
    cleanup_foreach = [string]$quoteActions.Deactivate_Missing_Quotes.foreach
    cleanup_description = [string]$quoteActions.Deactivate_Missing_Quotes.description
    content_version = [string]$definition.contentVersion
  }
}

function Repair-QuoteWorkflowJson {
  param(
    [object]$WorkflowJson,
    [string]$DisplayName
  )

  $state = [ordered]@{
    attachment_gate_fixed = $false
    quote_select_fixed = $false
    cleanup_gate_fixed = $false
  }

  $definition = $WorkflowJson.properties.definition
  $attachmentCondition = $definition.actions.Check_if_weekday.actions.Apply_to_each_attachment.actions.Condition_Is_SP830CA_File
  $quoteActions = $attachmentCondition.actions
  $lineActions = $quoteActions.Guard_Quote_Rows.actions.Apply_to_each_quote_line.actions

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
    $state.attachment_gate_fixed = $true
  }

  $expectedSelect = "qfu_quoteid,statecode,statuscode"
  if ([string]$lineActions.Check_Quote_Exists.inputs.parameters.'$select' -ne $expectedSelect) {
    $lineActions.Check_Quote_Exists.inputs.parameters.'$select' = $expectedSelect
    $state.quote_select_fixed = $true
  }

  $expectedCleanupForeach = "@json('[]')"
  if ([string]$quoteActions.Deactivate_Missing_Quotes.foreach -ne $expectedCleanupForeach) {
    $quoteActions.Deactivate_Missing_Quotes.foreach = $expectedCleanupForeach
    $state.cleanup_gate_fixed = $true
  }

  $expectedCleanupDescription = "Quote cleanup is disabled on the live SP830 flow so previously-seen quotes stay visible until cleanup is intentionally re-enabled."
  if ([string]$quoteActions.Deactivate_Missing_Quotes.description -ne $expectedCleanupDescription) {
    $quoteActions.Deactivate_Missing_Quotes.description = $expectedCleanupDescription
    $state.cleanup_gate_fixed = $true
  }

  Touch-WorkflowDefinition -WorkflowJson $WorkflowJson
  return [pscustomobject]$state
}

$selectedFlows = @($flowCatalog | Where-Object { $_.BranchCode -in $BranchCodes })
if (-not $selectedFlows) {
  throw "No quote flows matched the requested branch codes."
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $RepoRoot "results\quote-live-retention-xrm-repair-$stamp.json"
}
if ([string]::IsNullOrWhiteSpace($ArtifactRoot)) {
  $ArtifactRoot = Join-Path $RepoRoot "results\quote-live-retention-xrm-repair-$stamp"
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
    $beforeSummary = Get-QuoteFlowStateSummary -WorkflowRecord $workflowRecord -WorkflowJson $beforeJson
    Write-Utf8Json -Path (Join-Path $ArtifactRoot ("{0}-before.json" -f $flow.DisplayName)) -Object $beforeJson

    $repairState = Repair-QuoteWorkflowJson -WorkflowJson $beforeJson -DisplayName $flow.DisplayName
    $clientData = ConvertTo-JsonCompact -Object $beforeJson
    Set-CrmRecord -conn $connection -EntityLogicalName workflow -Id $workflowRecord.workflowid -Fields @{ clientdata = $clientData } | Out-Null
    Set-CrmRecordState -conn $connection -EntityLogicalName workflow -Id $workflowRecord.workflowid -StateCode Activated -StatusCode Activated | Out-Null

    $afterRecord = Get-CrmRecord -conn $connection -EntityLogicalName workflow -Id $workflowRecord.workflowid -Fields name,workflowid,statecode,statuscode,modifiedon,clientdata
    $afterJson = $afterRecord.clientdata | ConvertFrom-Json
    $afterSummary = Get-QuoteFlowStateSummary -WorkflowRecord $afterRecord -WorkflowJson $afterJson
    Write-Utf8Json -Path (Join-Path $ArtifactRoot ("{0}-after.json" -f $flow.DisplayName)) -Object $afterJson

    $rows.Add([pscustomobject]@{
        branch_code = $flow.BranchCode
        display_name = $flow.DisplayName
        workflow_id = [string]$workflowRecord.workflowid
        patched = $true
        attachment_gate_fixed = [bool]$repairState.attachment_gate_fixed
        quote_select_fixed = [bool]$repairState.quote_select_fixed
        cleanup_gate_fixed = [bool]$repairState.cleanup_gate_fixed
        before = $beforeSummary
        after = $afterSummary
      }) | Out-Null
  } catch {
    $rows.Add([pscustomobject]@{
        branch_code = $flow.BranchCode
        display_name = $flow.DisplayName
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
  Select-Object branch_code, display_name, patched, attachment_gate_fixed, quote_select_fixed, cleanup_gate_fixed |
  Format-Table -AutoSize

Write-Host "OUTPUT_PATH=$OutputPath"
