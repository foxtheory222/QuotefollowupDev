param(
  [string]$RepoRoot = "C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion",
  [string]$TargetEnvironmentUrl = "<URL>
  [string]$TargetEnvironmentName = "<GUID>",
  [string]$Username = "<EMAIL>",
  [string]$TemplateWorkflowId = "<GUID>",
  [string[]]$BranchCodes = @("4171", "4172", "4173"),
  [string]$FlowNameSuffixTag = "R2",
  [string]$SolutionUniqueName = "",
  [string]$SolutionDisplayName = "",
  [string]$SolutionVersion = "1.0.0.1",
  [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

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

function Normalize-StringArray {
  param([string[]]$Values)

  $set = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($value in @($Values)) {
    foreach ($candidate in @(([string]$value) -split ",")) {
      $trimmed = [string]$candidate
      if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
        [void]$set.Add($trimmed.Trim())
      }
    }
  }

  return @($set)
}

function Get-DateOrMinValue {
  param([object]$Value)

  if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
    return [datetime]::MinValue
  }

  try {
    return [datetime]$Value
  } catch {
    return [datetime]::MinValue
  }
}

function Get-AdminFlows {
  param([string]$EnvironmentName)

  return @(Get-AdminFlow -EnvironmentName $EnvironmentName)
}

function Resolve-ExactAdminFlow {
  param(
    [object[]]$AdminFlows,
    [string]$DisplayName
  )

  return @(
    $AdminFlows |
      Where-Object { $_.DisplayName -eq $DisplayName } |
      Sort-Object @{ Expression = { [bool]$_.Enabled }; Descending = $true }, @{ Expression = { Get-DateOrMinValue $_.LastModifiedTime }; Descending = $true }
  ) | Select-Object -First 1
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

function Get-TemplateConnectionBindings {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$WorkflowId
  )

  $workflow = Get-CrmRecord -conn $Connection -EntityLogicalName workflow -Id $WorkflowId -Fields clientdata, name
  if (-not $workflow.clientdata) {
    throw "Workflow $WorkflowId does not have clientdata."
  }

  $clientData = $workflow.clientdata | ConvertFrom-Json
  $hostConnectionMap = @{}

  function Walk-Hosts {
    param([object]$Node)

    if ($null -eq $Node) {
      return
    }

    if ($Node -is [System.Collections.IEnumerable] -and -not ($Node -is [string])) {
      foreach ($item in $Node) {
        Walk-Hosts -Node $item
      }
      return
    }

    if ($Node -is [System.Management.Automation.PSCustomObject]) {
      if ($Node.PSObject.Properties["inputs"] -and $Node.inputs -and $Node.inputs.PSObject.Properties["host"]) {
        $hostInfo = $Node.inputs.host
        if ($hostInfo.apiId -and $hostInfo.connectionName) {
          $hostConnectionMap[[string]$hostInfo.apiId] = [string]$hostInfo.connectionName
        }
      }

      foreach ($property in $Node.PSObject.Properties) {
        Walk-Hosts -Node $property.Value
      }
    }
  }

  Walk-Hosts -Node $clientData.properties.definition

  return [pscustomobject]@{
    connectionReferences = $clientData.properties.connectionReferences
    hostConnectionMap = $hostConnectionMap
    sourceWorkflowName = $workflow.name
  }
}

function Sync-QfuSharedConnectionReferences {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [object]$TemplateBindings
  )

  $records = @((Get-CrmRecords -conn $Connection -EntityLogicalName connectionreference -Fields connectionreferenceid, connectionreferencelogicalname, connectionid, connectorid -TopCount 200).CrmRecords)
  $recordMap = @{}
  foreach ($record in $records) {
    $recordMap[[string]$record.connectionreferencelogicalname] = $record
  }

  foreach ($reference in $TemplateBindings.connectionReferences.PSObject.Properties) {
    $templateLogicalName = [string]$reference.Value.connection.connectionReferenceLogicalName
    $templateRecord = $recordMap[$templateLogicalName]
    if (-not $templateRecord -or [string]::IsNullOrWhiteSpace([string]$templateRecord.connectionid)) {
      throw "Template connection reference is not bound: $templateLogicalName"
    }

    $targetLogicalName = "qfu_" + [string]$reference.Value.api.name
    $targetRecord = $recordMap[$targetLogicalName]
    if (-not $targetRecord) {
      throw "Target qfu connection reference not found: $targetLogicalName"
    }

    if ([string]$targetRecord.connectionid -ne [string]$templateRecord.connectionid) {
      Set-CrmRecord -conn $Connection -EntityLogicalName connectionreference -Id $targetRecord.connectionreferenceid -Fields @{ connectionid = [string]$templateRecord.connectionid } | Out-Null
    }
  }
}

function Normalize-Connections {
  param(
    [object]$WorkflowJson,
    [object]$TemplateBindings
  )

  $WorkflowJson.properties.connectionReferences = $TemplateBindings.connectionReferences

  function Walk-Nodes {
    param([object]$Node)

    if ($null -eq $Node) {
      return
    }

    if ($Node -is [System.Collections.IEnumerable] -and -not ($Node -is [string])) {
      foreach ($item in $Node) {
        Walk-Nodes -Node $item
      }
      return
    }

    if ($Node -is [System.Management.Automation.PSCustomObject]) {
      if ($Node.PSObject.Properties["inputs"] -and $Node.inputs -and $Node.inputs.PSObject.Properties["host"]) {
        $hostInfo = $Node.inputs.host
        $apiId = [string]$hostInfo.apiId
        if ($apiId -and $TemplateBindings.hostConnectionMap.ContainsKey($apiId)) {
          $hostInfo.connectionName = $TemplateBindings.hostConnectionMap[$apiId]
        }
      }

      foreach ($property in $Node.PSObject.Properties) {
        Walk-Nodes -Node $property.Value
      }
    }
  }

  Walk-Nodes -Node $WorkflowJson.properties.definition
}

function Get-GeneratedWorkflowJsonPath {
  param(
    [string]$Root,
    [object]$ManifestEntry
  )

  $fileName = "{0}-{1}.json" -f $ManifestEntry.target_flow, ([string]$ManifestEntry.workflow_id).ToUpperInvariant()
  return Join-Path $Root ("results\sapilotflows\src\Workflows\{0}" -f $fileName)
}

function Resave-ReplacementWorkflow {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [object]$TemplateBindings,
    [string]$Root,
    [object]$ManifestEntry
  )

  $workflowPath = Get-GeneratedWorkflowJsonPath -Root $Root -ManifestEntry $ManifestEntry
  if (-not (Test-Path -LiteralPath $workflowPath)) {
    throw "Generated workflow source not found: $workflowPath"
  }

  $workflowJson = Get-Content -LiteralPath $workflowPath -Raw | ConvertFrom-Json
  Normalize-Connections -WorkflowJson $workflowJson -TemplateBindings $TemplateBindings
  $clientData = ConvertTo-JsonCompact -Object $workflowJson
  Set-CrmRecord -conn $Connection -EntityLogicalName workflow -Id $ManifestEntry.workflow_id -Fields @{ clientdata = $clientData } | Out-Null
}

function Wait-ForAdminFlowEnabledState {
  param(
    [string]$EnvironmentName,
    [string]$DisplayName,
    [bool]$ExpectedEnabled,
    [int]$TimeoutSeconds = 180,
    [int]$PollSeconds = 5
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    $candidate = Resolve-ExactAdminFlow -AdminFlows (Get-AdminFlows -EnvironmentName $EnvironmentName) -DisplayName $DisplayName
    if ($candidate -and ([bool]$candidate.Enabled -eq $ExpectedEnabled)) {
      return $candidate
    }

    Start-Sleep -Seconds $PollSeconds
  } while ((Get-Date) -lt $deadline)

  return (Resolve-ExactAdminFlow -AdminFlows (Get-AdminFlows -EnvironmentName $EnvironmentName) -DisplayName $DisplayName)
}

if ([string]::IsNullOrWhiteSpace($SolutionUniqueName)) {
  $normalizedTag = ($FlowNameSuffixTag.ToLowerInvariant() -replace "[^a-z0-9]", "")
  $SolutionUniqueName = "qfu_sabackorder{0}" -f $normalizedTag
}

if ([string]::IsNullOrWhiteSpace($SolutionDisplayName)) {
  $SolutionDisplayName = "QFU Southern Alberta Backorder Replacement Flows {0}" -f $FlowNameSuffixTag
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $OutputPath = Join-Path (Join-Path $RepoRoot "results") "zbo-replacement-cutover-$stamp.json"
}

$normalizedBranchCodes = Normalize-StringArray -Values $BranchCodes

$generatorScript = Join-Path $RepoRoot "scripts\create-southern-alberta-pilot-flow-solution.ps1"
if (-not (Test-Path -LiteralPath $generatorScript)) {
  throw "Generator script not found: $generatorScript"
}

try {
  & $generatorScript `
    -RepoRoot $RepoRoot `
    -TargetEnvironmentUrl $TargetEnvironmentUrl `
    -TargetEnvironmentName $TargetEnvironmentName `
    -Username $Username `
    -Families Backorder `
    -FlowNameSuffixTag $FlowNameSuffixTag `
    -UseGeneratedWorkflowIds `
    -SolutionUniqueName $SolutionUniqueName `
    -SolutionDisplayName $SolutionDisplayName `
    -SolutionVersion $SolutionVersion `
    -ImportToTarget
} catch {
  throw "Replacement flow generation/import failed: $($_.Exception.Message)"
}

if ($LASTEXITCODE -ne 0) {
  throw "Replacement flow import failed."
}

$mapPath = Join-Path $RepoRoot "results\qfu-southern-alberta-pilot-flows-map.json"
if (-not (Test-Path -LiteralPath $mapPath)) {
  throw "Flow manifest not found: $mapPath"
}

$manifest = @(
  (Get-Content -LiteralPath $mapPath -Raw | ConvertFrom-Json) |
    Where-Object { $_.family -eq "Backorder" -and $_.branch_code -in $normalizedBranchCodes }
)

if ($manifest.Count -eq 0) {
  throw "No imported backorder replacement flows were found in $mapPath"
}

$connection = Connect-Org -Url $TargetEnvironmentUrl
$templateBindings = Get-TemplateConnectionBindings -Connection $connection -WorkflowId $TemplateWorkflowId
Sync-QfuSharedConnectionReferences -Connection $connection -TemplateBindings $templateBindings

foreach ($entry in $manifest) {
  $workflow = Get-CrmRecord -conn $connection -EntityLogicalName workflow -Id $entry.workflow_id -Fields workflowid, name, statecode, statuscode
  if (-not $workflow -or -not $workflow.workflowid) {
    throw "Imported replacement workflow $($entry.workflow_id) for branch $($entry.branch_code) was not found in $TargetEnvironmentUrl."
  }

  Resave-ReplacementWorkflow -Connection $connection -TemplateBindings $templateBindings -Root $RepoRoot -ManifestEntry $entry
}

Import-Module Microsoft.PowerApps.Administration.PowerShell
Add-PowerAppsAccount -Endpoint prod -Username $Username | Out-Null

$rows = New-Object System.Collections.Generic.List[object]

foreach ($entry in $manifest) {
  $legacyDisplayName = "{0}-BackOrder-Update-ZBO-Live" -f $entry.branch_code
  $replacementDisplayName = [string]$entry.target_flow
  $adminFlows = Get-AdminFlows -EnvironmentName $TargetEnvironmentName
  $replacementBefore = Resolve-ExactAdminFlow -AdminFlows $adminFlows -DisplayName $replacementDisplayName
  $legacyBefore = Resolve-ExactAdminFlow -AdminFlows $adminFlows -DisplayName $legacyDisplayName

  if (-not $replacementBefore) {
    $rows.Add([pscustomobject]@{
        branch_code = $entry.branch_code
        replacement_display_name = $replacementDisplayName
        replacement_flow_name = $null
        replacement_enabled_after = $false
        legacy_display_name = $legacyDisplayName
        legacy_flow_name = if ($legacyBefore) { [string]$legacyBefore.FlowName } else { $null }
        legacy_enabled_after = if ($legacyBefore) { [bool]$legacyBefore.Enabled } else { $null }
        cutover_completed = $false
        error = "Replacement flow was not present after import."
      }) | Out-Null
    continue
  }

  try {
    Enable-AdminFlow -EnvironmentName $TargetEnvironmentName -FlowName $replacementBefore.FlowName | Out-Null
    $replacementAfterEnable = Wait-ForAdminFlowEnabledState -EnvironmentName $TargetEnvironmentName -DisplayName $replacementDisplayName -ExpectedEnabled $true
    if (-not $replacementAfterEnable -or -not [bool]$replacementAfterEnable.Enabled) {
      throw "Replacement flow did not enable successfully."
    }

    if ($legacyBefore -and [string]$legacyBefore.FlowName -ne [string]$replacementBefore.FlowName -and [bool]$legacyBefore.Enabled) {
      Disable-AdminFlow -EnvironmentName $TargetEnvironmentName -FlowName $legacyBefore.FlowName | Out-Null
      $legacyAfterDisable = Wait-ForAdminFlowEnabledState -EnvironmentName $TargetEnvironmentName -DisplayName $legacyDisplayName -ExpectedEnabled $false
      if ($legacyAfterDisable -and [bool]$legacyAfterDisable.Enabled) {
        throw "Legacy flow did not disable successfully."
      }
    }

    $adminFlows = Get-AdminFlows -EnvironmentName $TargetEnvironmentName
    $replacementAfter = Resolve-ExactAdminFlow -AdminFlows $adminFlows -DisplayName $replacementDisplayName
    $legacyAfter = Resolve-ExactAdminFlow -AdminFlows $adminFlows -DisplayName $legacyDisplayName

    $rows.Add([pscustomobject]@{
        branch_code = $entry.branch_code
        replacement_display_name = $replacementDisplayName
        replacement_flow_name = [string]$replacementAfter.FlowName
        replacement_workflow_entity_id = [string]$replacementAfter.WorkflowEntityId
        replacement_enabled_after = [bool]$replacementAfter.Enabled
        replacement_state_after = [string]$replacementAfter.State
        legacy_display_name = $legacyDisplayName
        legacy_flow_name = if ($legacyAfter) { [string]$legacyAfter.FlowName } else { $null }
        legacy_workflow_entity_id = if ($legacyAfter) { [string]$legacyAfter.WorkflowEntityId } else { $null }
        legacy_enabled_after = if ($legacyAfter) { [bool]$legacyAfter.Enabled } else { $null }
        legacy_state_after = if ($legacyAfter) { [string]$legacyAfter.State } else { $null }
        cutover_completed = [bool]($replacementAfter -and $replacementAfter.Enabled -and ($null -eq $legacyAfter -or -not [bool]$legacyAfter.Enabled))
        error = $null
      }) | Out-Null
  } catch {
    $rows.Add([pscustomobject]@{
        branch_code = $entry.branch_code
        replacement_display_name = $replacementDisplayName
        replacement_flow_name = [string]$replacementBefore.FlowName
        replacement_enabled_after = [bool]$replacementBefore.Enabled
        legacy_display_name = $legacyDisplayName
        legacy_flow_name = if ($legacyBefore) { [string]$legacyBefore.FlowName } else { $null }
        legacy_enabled_after = if ($legacyBefore) { [bool]$legacyBefore.Enabled } else { $null }
        cutover_completed = $false
        error = $_.Exception.Message
      }) | Out-Null
  }
}

$report = [pscustomobject]@{
  captured_at = (Get-Date).ToUniversalTime().ToString("o")
  target_environment_url = $TargetEnvironmentUrl
  target_environment_name = $TargetEnvironmentName
  template_workflow_id = $TemplateWorkflowId
  template_source_workflow = $templateBindings.sourceWorkflowName
  flow_name_suffix_tag = $FlowNameSuffixTag
  solution_unique_name = $SolutionUniqueName
  solution_display_name = $SolutionDisplayName
  solution_version = $SolutionVersion
  manifest_path = $mapPath
  rows = @($rows.ToArray())
}

Write-Utf8Json -Path $OutputPath -Object $report

$report.rows |
  Select-Object branch_code, replacement_display_name, replacement_enabled_after, legacy_display_name, legacy_enabled_after, cutover_completed, error |
  Format-Table -AutoSize

Write-Host "OUTPUT_PATH=$OutputPath"
