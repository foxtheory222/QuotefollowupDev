param(
  [string]$TargetEnvironmentName = "9f2e54c6-c349-e7e1-ac7c-010d3adf3c03",
  [string[]]$BranchCodes = @("4171", "4172", "4173"),
  [switch]$DisableLegacyLiveWhenR2Started,
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

  $json = $Object | ConvertTo-Json -Depth 50
  [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Get-FlowBearerToken {
  $token = Get-AzAccessToken -ResourceUrl "https://service.flow.microsoft.com/"
  return [System.Net.NetworkCredential]::new("", $token.Token).Password
}

function Get-FlowHeaders {
  param([string]$BearerToken)

  return @{
    Authorization = "Bearer $BearerToken"
    Accept = "application/json"
    "Content-Type" = "application/json"
  }
}

function Invoke-FlowGet {
  param(
    [string]$BearerToken,
    [string]$Uri
  )

  return Invoke-RestMethod -Uri $Uri -Headers (Get-FlowHeaders -BearerToken $BearerToken) -Method Get
}

function Invoke-FlowPatch {
  param(
    [string]$BearerToken,
    [string]$Uri,
    [object]$Body
  )

  $payload = $Body | ConvertTo-Json -Depth 200
  return Invoke-RestMethod -Uri $Uri -Headers (Get-FlowHeaders -BearerToken $BearerToken) -Method Patch -Body $payload
}

function Get-FlowCollection {
  param(
    [string]$BearerToken,
    [string]$EnvironmentName
  )

  $uri = "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$EnvironmentName/flows?api-version=2016-11-01"
  $flows = New-Object System.Collections.Generic.List[object]

  do {
    $response = Invoke-FlowGet -BearerToken $BearerToken -Uri $uri
    foreach ($item in @($response.value)) {
      $flows.Add($item) | Out-Null
    }

    $uri = $response.nextLink
  } while ($uri)

  return $flows.ToArray()
}

function Get-FlowDefinition {
  param(
    [string]$BearerToken,
    [string]$EnvironmentName,
    [string]$FlowName
  )

  $uri = "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$EnvironmentName/flows/$FlowName?api-version=2016-11-01"
  return Invoke-FlowGet -BearerToken $BearerToken -Uri $uri
}

function Set-FlowDefinition {
  param(
    [string]$BearerToken,
    [string]$EnvironmentName,
    [string]$FlowName,
    [object]$Flow
  )

  $uri = "https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple/environments/$EnvironmentName/flows/$FlowName?api-version=2016-11-01"
  return Invoke-FlowPatch -BearerToken $BearerToken -Uri $uri -Body $Flow
}

function Get-ZboSelectNode {
  param([object]$Definition)

  return $Definition.actions.Apply_to_each_Attachment.actions.Condition_Is_CA_ZBO_File.actions.Guard_BackOrder_Row_Limit.actions.Select_BackOrder_Rows.inputs.select
}

function Get-ZboNormalizedQtyOnDelExpression {
  return "@if(or(empty(coalesce(item()?['Qty on Del Not PGI_x0027_d'], item()?['Qty on Del Not PGI''d'])), startsWith(string(coalesce(item()?['Qty on Del Not PGI_x0027_d'], item()?['Qty on Del Not PGI''d'])), '#')), float(0), if(greater(float(coalesce(coalesce(item()?['Qty on Del Not PGI_x0027_d'], item()?['Qty on Del Not PGI''d']), 0)), 0), float(coalesce(coalesce(item()?['Qty on Del Not PGI_x0027_d'], item()?['Qty on Del Not PGI''d']), 0)), float(0)))"
}

function Get-ZboNormalizedQtyNotOnDelExpression {
  return "@if(or(empty(item()?['Qty Not On Del']), startsWith(string(item()?['Qty Not On Del']), '#')), float(0), if(greater(float(coalesce(item()?['Qty Not On Del'], 0)), 0), float(coalesce(item()?['Qty Not On Del'], 0)), float(0)))"
}

function Update-ZboDefinition {
  param([object]$Flow)

  $selectNode = Get-ZboSelectNode -Definition $Flow.properties.definition
  $expectedQtyOnDel = Get-ZboNormalizedQtyOnDelExpression
  $expectedQtyNotOnDel = Get-ZboNormalizedQtyNotOnDelExpression
  $updated = $false

  if ([string]$selectNode.qtyOnDelNotPgid -ne $expectedQtyOnDel) {
    $selectNode.qtyOnDelNotPgid = $expectedQtyOnDel
    $updated = $true
  }

  if ([string]$selectNode.qtyNotOnDel -ne $expectedQtyNotOnDel) {
    $selectNode.qtyNotOnDel = $expectedQtyNotOnDel
    $updated = $true
  }

  return $updated
}

function Disable-LegacyLiveIfSafe {
  param(
    [string]$BearerToken,
    [string]$EnvironmentName,
    [object]$FlowIndex,
    [string]$BranchCode
  )

  $legacyName = "$BranchCode-BackOrder-Update-ZBO-Live"
  $replacementName = "$BranchCode-BackOrder-Update-ZBO-Live-R2"
  $legacy = $FlowIndex[$legacyName]
  $replacement = $FlowIndex[$replacementName]
  if (-not $legacy -or -not $replacement) {
    return $null
  }

  $replacementFresh = Get-FlowDefinition -BearerToken $BearerToken -EnvironmentName $EnvironmentName -FlowName $replacement.name
  if ([string]$replacementFresh.properties.state -ne "Started") {
    return [pscustomobject]@{
      branch_code = $BranchCode
      display_name = $legacyName
      disabled = $false
      reason = "replacement_not_started"
    }
  }

  $legacyFresh = Get-FlowDefinition -BearerToken $BearerToken -EnvironmentName $EnvironmentName -FlowName $legacy.name
  if ([string]$legacyFresh.properties.state -eq "Stopped") {
    return [pscustomobject]@{
      branch_code = $BranchCode
      display_name = $legacyName
      disabled = $false
      reason = "already_stopped"
    }
  }

  $legacyFresh.properties.state = "Stopped"
  $stamp = Get-Date -Format "yyyyMMdd.HHmmss"
  $legacyFresh.properties.definition.contentVersion = "1.0.$stamp"
  $after = Set-FlowDefinition -BearerToken $BearerToken -EnvironmentName $EnvironmentName -FlowName $legacy.name -Flow $legacyFresh

  return [pscustomobject]@{
    branch_code = $BranchCode
    display_name = $legacyName
    disabled = $true
    state_after = [string]$after.properties.state
  }
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $OutputPath = Join-Path (Join-Path $PSScriptRoot "..\\results") "live-zbo-quantity-normalization-$stamp.json"
}

$bearerToken = Get-FlowBearerToken
$flowCollection = @(Get-FlowCollection -BearerToken $bearerToken -EnvironmentName $TargetEnvironmentName)
$targetDisplayNames = @(
  foreach ($branchCode in $BranchCodes) {
    "$branchCode-BackOrder-Update-ZBO-Live"
    "$branchCode-BackOrder-Update-ZBO-Live-R2"
  }
)

$flowIndex = @{}
foreach ($flow in $flowCollection) {
  $flowIndex[[string]$flow.properties.displayName] = $flow
}

$flowReports = New-Object System.Collections.Generic.List[object]
foreach ($displayName in $targetDisplayNames) {
  $flowSummary = $flowIndex[$displayName]
  if (-not $flowSummary) {
    $flowReports.Add([pscustomobject]@{
      display_name = $displayName
      found = $false
    }) | Out-Null
    continue
  }

  $flow = Get-FlowDefinition -BearerToken $bearerToken -EnvironmentName $TargetEnvironmentName -FlowName $flowSummary.name
  $updated = Update-ZboDefinition -Flow $flow
  $stateBefore = [string]$flow.properties.state
  $contentVersionBefore = [string]$flow.properties.definition.contentVersion

  if ($updated) {
    $stamp = Get-Date -Format "yyyyMMdd.HHmmss"
    $flow.properties.definition.contentVersion = "1.0.$stamp"
    $flow = Set-FlowDefinition -BearerToken $bearerToken -EnvironmentName $TargetEnvironmentName -FlowName $flowSummary.name -Flow $flow
  }

  $flowReports.Add([pscustomobject]@{
    display_name = $displayName
    found = $true
    flow_name = [string]$flowSummary.name
    updated = $updated
    state_before = $stateBefore
    state_after = [string]$flow.properties.state
    content_version_before = $contentVersionBefore
    content_version_after = [string]$flow.properties.definition.contentVersion
  }) | Out-Null
}

$legacyDisableReports = @()
if ($DisableLegacyLiveWhenR2Started) {
  $legacyDisableReports = foreach ($branchCode in $BranchCodes) {
    Disable-LegacyLiveIfSafe -BearerToken $bearerToken -EnvironmentName $TargetEnvironmentName -FlowIndex $flowIndex -BranchCode $branchCode
  }
}

$result = [pscustomobject]@{
  generated_on = (Get-Date).ToString("o")
  environment_name = $TargetEnvironmentName
  branch_codes = @($BranchCodes)
  flows = @($flowReports.ToArray())
  legacy_disable = @($legacyDisableReports | Where-Object { $null -ne $_ })
}

Write-Utf8Json -Path $OutputPath -Object $result
$result
