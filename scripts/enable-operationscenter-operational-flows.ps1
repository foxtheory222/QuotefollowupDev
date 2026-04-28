param(
  [string]$EnvironmentName = "1c97a8d0-fd57-e76e-b8ab-35d9229d88f6",
  [string]$Username = "smcfarlane@applied.com",
  [string[]]$FlowDisplayNames = @(
    "4171-QuoteFollowUp-Import-Staging",
    "4172-QuoteFollowUp-Import-Staging",
    "4173-QuoteFollowUp-Import-Staging",
    "4171-BackOrder-Update-ZBO-Live-R2",
    "4172-BackOrder-Update-ZBO-Live-R2",
    "4173-BackOrder-Update-ZBO-Live-R2",
    "4171-Budget-Update-SA1300",
    "4172-Budget-Update-SA1300",
    "4173-Budget-Update-SA1300",
    "4171-GL060-Inbox-Ingress",
    "4172-GL060-Inbox-Ingress",
    "4173-GL060-Inbox-Ingress",
    "4171-Freight-Inbox-Ingress",
    "4172-Freight-Inbox-Ingress",
    "4173-Freight-Inbox-Ingress",
    "QFU-Freight-Archive-Workitems"
  ),
  [string]$OutputPath = "results\operationscenter-flow-autonomy-20260428\enable-operational-flows-retry.json"
)

$ErrorActionPreference = "Stop"

Import-Module Microsoft.PowerApps.Administration.PowerShell
Add-PowerAppsAccount -Endpoint prod -Username $Username | Out-Null

function Ensure-Directory {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Get-FlowByDisplayName {
  param(
    [string]$TargetEnvironmentName,
    [string]$DisplayName
  )

  return @(
    Get-AdminFlow -EnvironmentName $TargetEnvironmentName |
      Where-Object { $_.DisplayName -eq $DisplayName } |
      Sort-Object LastModifiedTime -Descending
  ) | Select-Object -First 1
}

$results = New-Object System.Collections.Generic.List[object]

foreach ($displayName in $FlowDisplayNames) {
  $flow = Get-FlowByDisplayName -TargetEnvironmentName $EnvironmentName -DisplayName $displayName
  if (-not $flow) {
    $results.Add([pscustomobject]@{
      displayName = $displayName
      flowName = $null
      workflowEntityId = $null
      beforeEnabled = $false
      action = "missing"
      success = $false
      afterEnabled = $false
      error = "Flow not found in target environment."
    }) | Out-Null
    continue
  }

  $beforeEnabled = [bool]$flow.Enabled
  $action = "already_enabled"
  $errorMessage = $null

  if (-not $beforeEnabled) {
    $action = "enable_attempted"
    try {
      $response = Enable-AdminFlow -EnvironmentName $EnvironmentName -FlowName $flow.FlowName -ErrorAction Stop
      if ($response -and $response.PSObject.Properties["Code"] -and [int]$response.Code -ge 400) {
        $errorMessage = $response.Error.message
      }
    } catch {
      $errorMessage = $_.Exception.Message
    }
  }

  Start-Sleep -Seconds 2
  $after = Get-AdminFlow -EnvironmentName $EnvironmentName -FlowName $flow.FlowName
  $afterEnabled = [bool]$after.Enabled

  $results.Add([pscustomobject]@{
    displayName = $displayName
    flowName = $flow.FlowName
    workflowEntityId = $flow.WorkflowEntityId
    beforeEnabled = $beforeEnabled
    action = $action
    success = $afterEnabled
    afterEnabled = $afterEnabled
    error = $errorMessage
  }) | Out-Null
}

$fullOutputPath = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
  $OutputPath
} else {
  Join-Path (Split-Path -Parent $PSScriptRoot) $OutputPath
}

$parent = Split-Path -Parent $fullOutputPath
if ($parent) {
  Ensure-Directory -Path $parent
}

[System.IO.File]::WriteAllText($fullOutputPath, ($results | ConvertTo-Json -Depth 10), [System.Text.UTF8Encoding]::new($false))
Write-Output "OUTPUT_PATH=$fullOutputPath"
$results | Format-Table displayName, action, success, afterEnabled, error -AutoSize
