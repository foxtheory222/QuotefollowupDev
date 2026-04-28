param(
  [string]$EnvironmentUrl = "https://orga632edd5.crm3.dynamics.com",
  [string]$Username = "smcfarlane@applied.com",
  [string]$WebsiteId = "80909c52-339a-4765-b797-ed913fe73123",
  [string]$OutputPath = "results\powerpages-enhanced-security-inspection.json"
)

$ErrorActionPreference = "Stop"

Import-Module Microsoft.Xrm.Data.Powershell

$connection = Connect-CrmOnline -ServerUrl $EnvironmentUrl -ForceOAuth -Username $Username
if (-not $connection -or -not $connection.IsReady) {
  throw "Dataverse connection failed for $EnvironmentUrl : $($connection.LastCrmError)"
}

$headers = @{
  Authorization      = "Bearer $($connection.CurrentAccessToken)"
  Accept             = "application/json"
  "OData-MaxVersion" = "4.0"
  "OData-Version"    = "4.0"
}

function Invoke-DvGet {
  param([string]$Uri)
  return Invoke-RestMethod -Method Get -Uri $Uri -Headers $headers
}

function Get-EntityMetadataSummary {
  param([string]$LogicalName)

  $encodedExpand = "`$expand=ManyToManyRelationships(`$select=SchemaName,IntersectEntityName,Entity1LogicalName,Entity1IntersectAttribute,Entity2LogicalName,Entity2IntersectAttribute)"
  $uri = "$EnvironmentUrl/api/data/v9.2/EntityDefinitions(LogicalName='$LogicalName')?`$select=LogicalName,EntitySetName,PrimaryIdAttribute&$encodedExpand"
  $metadata = Invoke-DvGet -Uri $uri
  $relationships = @($metadata.ManyToManyRelationships | Where-Object {
      $_.SchemaName -like "*entitypermission*" -or
      $_.SchemaName -like "*webrole*" -or
      $_.IntersectEntityName -like "*entitypermission*" -or
      $_.IntersectEntityName -like "*webrole*" -or
      $_.IntersectEntityName -like "*powerpagecomponent*"
    } | ForEach-Object {
      [ordered]@{
        schema_name = $_.SchemaName
        intersect_entity_name = $_.IntersectEntityName
        entity1 = $_.Entity1LogicalName
        entity1_intersect_attribute = $_.Entity1IntersectAttribute
        entity2 = $_.Entity2LogicalName
        entity2_intersect_attribute = $_.Entity2IntersectAttribute
      }
    })

  return [ordered]@{
    logical_name = $metadata.LogicalName
    entity_set_name = $metadata.EntitySetName
    primary_id_attribute = $metadata.PrimaryIdAttribute
    matching_many_to_many_relationships = $relationships
  }
}

function Get-Rows {
  param(
    [string]$EntitySetName,
    [string]$Query
  )

  return @((Invoke-DvGet -Uri "$EnvironmentUrl/api/data/v9.2/$EntitySetName$Query").value)
}

$permissionRows = Get-Rows -EntitySetName "mspp_entitypermissions" -Query "?`$select=mspp_entitypermissionid,mspp_entitylogicalname,mspp_entityname,_mspp_websiteid_value&`$filter=_mspp_websiteid_value eq $WebsiteId"
$webRoleRows = Get-Rows -EntitySetName "mspp_webroles" -Query "?`$select=mspp_webroleid,mspp_name,_mspp_websiteid_value&`$filter=_mspp_websiteid_value eq $WebsiteId"

$navSamples = @()
foreach ($permission in @($permissionRows | Select-Object -First 5)) {
  $permissionId = $permission.mspp_entitypermissionid
  $roles = Get-Rows -EntitySetName "mspp_entitypermissions($permissionId)/mspp_entitypermission_webrole" -Query "?`$select=mspp_webroleid,mspp_name"
  $navSamples += [ordered]@{
    permission_id = $permissionId
    entity_logical_name = $permission.mspp_entitylogicalname
    role_count = @($roles).Count
    roles = @($roles | ForEach-Object { [ordered]@{ id = $_.mspp_webroleid; name = $_.mspp_name } })
  }
}

$intersectEntitySets = @(
  "mspp_entitypermission_webroles",
  "adx_entitypermission_webroles",
  "powerpagecomponent_mspp_entitypermission_mspp_webroles",
  "powerpagecomponent_mspp_webrole_mspp_entitypermissions"
)

$intersectProbe = @()
foreach ($setName in $intersectEntitySets) {
  try {
    $rows = Get-Rows -EntitySetName $setName -Query "?`$top=5"
    $intersectProbe += [ordered]@{
      entity_set_name = $setName
      available = $true
      row_count_sample = @($rows).Count
      sample_property_names = if (@($rows).Count -gt 0) { @($rows[0].PSObject.Properties.Name) } else { @() }
    }
  } catch {
    $intersectProbe += [ordered]@{
      entity_set_name = $setName
      available = $false
      error = $_.Exception.Message
    }
  }
}

$result = [ordered]@{
  captured_at = (Get-Date).ToString("o")
  environment_url = $EnvironmentUrl
  website_id = $WebsiteId
  metadata = @(
    Get-EntityMetadataSummary -LogicalName "mspp_entitypermission"
    Get-EntityMetadataSummary -LogicalName "mspp_webrole"
    Get-EntityMetadataSummary -LogicalName "powerpagecomponent"
  )
  permission_count = @($permissionRows).Count
  webrole_count = @($webRoleRows).Count
  webroles = @($webRoleRows | ForEach-Object { [ordered]@{ id = $_.mspp_webroleid; name = $_.mspp_name } })
  navigation_samples = $navSamples
  intersect_probe = $intersectProbe
}

$fullOutputPath = Join-Path (Split-Path -Parent $PSScriptRoot) $OutputPath
$parent = Split-Path -Parent $fullOutputPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) {
  New-Item -ItemType Directory -Path $parent -Force | Out-Null
}

[System.IO.File]::WriteAllText($fullOutputPath, ($result | ConvertTo-Json -Depth 20), (New-Object System.Text.UTF8Encoding($false)))
Write-Output "OUTPUT_PATH=$fullOutputPath"
