param(
  [string]$EnvironmentUrl = "https://orga632edd5.crm3.dynamics.com",
  [string]$Username = "smcfarlane@applied.com",
  [string]$LogicalName = "new_sharedoffice365_bbb5d",
  [string]$DisplayName = "Office 365 Outlook",
  [string]$ConnectorId = "/providers/Microsoft.PowerApps/apis/shared_office365",
  [string]$OutputPath = "results\ensure-dev-office365-connectionreference.json"
)

$ErrorActionPreference = "Stop"

Import-Module Microsoft.Xrm.Data.Powershell
Add-Type -AssemblyName "Microsoft.Xrm.Sdk"

$connection = Connect-CrmOnline -ServerUrl $EnvironmentUrl -ForceOAuth -Username $Username
if (-not $connection -or -not $connection.IsReady) {
  throw "Dataverse connection failed for $EnvironmentUrl : $($connection.LastCrmError)"
}

function Get-FetchRows {
  param([string]$Fetch)
  return @((Get-CrmRecordsByFetch -conn $connection -Fetch $Fetch).CrmRecords)
}

$escapedLogicalName = [System.Security.SecurityElement]::Escape($LogicalName)
$existing = Get-FetchRows @"
<fetch count='1'>
  <entity name='connectionreference'>
    <attribute name='connectionreferenceid' />
    <attribute name='connectionreferencelogicalname' />
    <attribute name='connectionreferencedisplayname' />
    <attribute name='connectorid' />
    <filter>
      <condition attribute='connectionreferencelogicalname' operator='eq' value='$escapedLogicalName' />
    </filter>
  </entity>
</fetch>
"@

if ($existing.Count -eq 0) {
  $entity = [Microsoft.Xrm.Sdk.Entity]::new("connectionreference")
  $entity["connectionreferencelogicalname"] = $LogicalName
  $entity["connectionreferencedisplayname"] = $DisplayName
  $entity["connectorid"] = $ConnectorId
  $createdId = $connection.Create($entity)
  $action = "created"
  $connectionReferenceId = $createdId
} else {
  $row = $existing | Select-Object -First 1
  $entity = [Microsoft.Xrm.Sdk.Entity]::new("connectionreference")
  $entity.Id = [Guid]$row.connectionreferenceid
  $entity["connectionreferencedisplayname"] = $DisplayName
  $entity["connectorid"] = $ConnectorId
  $connection.Update($entity)
  $action = "updated"
  $connectionReferenceId = [Guid]$row.connectionreferenceid
}

$payload = [ordered]@{
  captured_at = (Get-Date).ToUniversalTime().ToString("o")
  environment_url = $EnvironmentUrl
  action = $action
  connectionreferenceid = $connectionReferenceId
  connectionreferencelogicalname = $LogicalName
  connectionreferencedisplayname = $DisplayName
  connectorid = $ConnectorId
}

$fullOutputPath = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
  $OutputPath
} else {
  Join-Path (Split-Path -Parent $PSScriptRoot) $OutputPath
}
$parent = Split-Path -Parent $fullOutputPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) {
  New-Item -ItemType Directory -Path $parent -Force | Out-Null
}

[System.IO.File]::WriteAllText($fullOutputPath, ($payload | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
Write-Output "OUTPUT_PATH=$fullOutputPath"
