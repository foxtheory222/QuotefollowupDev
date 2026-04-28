param(
  [string]$EnvironmentUrl = "https://orga632edd5.crm3.dynamics.com",
  [string]$Username = "smcfarlane@applied.com",
  [string]$WebsiteId = "80909c52-339a-4765-b797-ed913fe73123",
  [string]$SourceSiteRoot = "C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\powerpages-copy-20260427-074044\source-operationhub\operations-hub---operationhub",
  [string]$OutputPath = "results\powerpages-enhanced-tablepermission-webrole-repair.json"
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

function Parse-YamlList {
  param([string]$Path)

  $items = New-Object System.Collections.Generic.List[object]
  $current = $null
  $currentListKey = $null

  foreach ($line in Get-Content -LiteralPath $Path) {
    if ($line -match '^- ([A-Za-z0-9_]+):\s*(.*)$') {
      if ($current) {
        $items.Add([pscustomobject]$current)
      }

      $current = [ordered]@{}
      $key = $matches[1]
      $value = $matches[2]
      if ($value -eq "") {
        $current[$key] = @()
        $currentListKey = $key
      } else {
        $current[$key] = $value
        $currentListKey = $null
      }
      continue
    }

    if (-not $current) {
      continue
    }

    if ($line -match '^  ([A-Za-z0-9_]+):\s*(.*)$') {
      $key = $matches[1]
      $value = $matches[2]
      if ($value -eq "") {
        $current[$key] = @()
        $currentListKey = $key
      } else {
        $current[$key] = $value
        $currentListKey = $null
      }
      continue
    }

    if ($line -match '^  - (.+)$' -and $currentListKey) {
      $current[$currentListKey] += $matches[1]
    }
  }

  if ($current) {
    $items.Add([pscustomobject]$current)
  }

  return $items
}

function Parse-SimpleYamlMap {
  param([string]$Path)

  $result = [ordered]@{}
  $currentListKey = $null

  foreach ($line in Get-Content -LiteralPath $Path) {
    if ($line -match '^([A-Za-z0-9_]+):\s*(.*)$') {
      $key = $matches[1]
      $value = $matches[2]
      if ($value -eq "") {
        $result[$key] = @()
        $currentListKey = $key
      } else {
        $result[$key] = $value
        $currentListKey = $null
      }
      continue
    }

    if ($line -match '^-\s*(.+)$' -and $currentListKey) {
      $result[$currentListKey] += $matches[1]
    }
  }

  return $result
}

function New-EntityReference {
  param(
    [string]$LogicalName,
    [Guid]$Id
  )

  return [Microsoft.Xrm.Sdk.EntityReference]::new($LogicalName, $Id)
}

function Get-LinkedRoleIds {
  param([Guid]$PermissionId)

  $headers = @{
    Authorization      = "Bearer $($connection.CurrentAccessToken)"
    Accept             = "application/json"
    "OData-MaxVersion" = "4.0"
    "OData-Version"    = "4.0"
  }
  $uri = "$EnvironmentUrl/api/data/v9.2/mspp_entitypermissions($PermissionId)/mspp_entitypermission_webrole?`$select=mspp_webroleid,mspp_name"
  return @((Invoke-RestMethod -Method Get -Uri $uri -Headers $headers).value | ForEach-Object { [Guid]$_.mspp_webroleid })
}

$webRolePath = Join-Path $SourceSiteRoot "webrole.yml"
$tablePermissionsRoot = Join-Path $SourceSiteRoot "table-permissions"
foreach ($requiredPath in @($webRolePath, $tablePermissionsRoot)) {
  if (-not (Test-Path -LiteralPath $requiredPath)) {
    throw "Required source path not found: $requiredPath"
  }
}

$sourceRoleNameById = @{}
foreach ($role in Parse-YamlList -Path $webRolePath) {
  if ($role.adx_webroleid -and $role.adx_name) {
    $sourceRoleNameById[[string]([Guid]$role.adx_webroleid)] = [string]$role.adx_name
  }
}

$sourcePermissions = Get-ChildItem -LiteralPath $tablePermissionsRoot -Filter "*.tablepermission.yml" |
  Sort-Object Name |
  ForEach-Object {
    $data = Parse-SimpleYamlMap -Path $_.FullName
    [pscustomobject]@{
      file_name = $_.Name
      entity_logical_name = [string]$data.adx_entitylogicalname
      source_role_names = @($data.adx_entitypermission_webrole |
        Where-Object { $_ -and [string]$_ -match '^[0-9A-Fa-f-]{36}$' } |
        ForEach-Object { $sourceRoleNameById[[string]([Guid]$_)] } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique)
    }
  }

$targetWebsiteGuid = [Guid]$WebsiteId
$targetRoles = Get-FetchRows @"
<fetch count='100'>
  <entity name='mspp_webrole'>
    <attribute name='mspp_webroleid' />
    <attribute name='mspp_name' />
    <filter>
      <condition attribute='mspp_websiteid' operator='eq' value='$targetWebsiteGuid' />
    </filter>
  </entity>
</fetch>
"@

$targetRoleIdsByName = @{}
foreach ($role in $targetRoles) {
  $roleName = [string]$role.mspp_name
  if (-not $targetRoleIdsByName.ContainsKey($roleName)) {
    $targetRoleIdsByName[$roleName] = New-Object System.Collections.Generic.List[Guid]
  }
  $targetRoleIdsByName[$roleName].Add([Guid]$role.mspp_webroleid)
}

$targetPermissions = Get-FetchRows @"
<fetch count='250'>
  <entity name='mspp_entitypermission'>
    <attribute name='mspp_entitypermissionid' />
    <attribute name='mspp_entitylogicalname' />
    <attribute name='mspp_entityname' />
    <filter>
      <condition attribute='mspp_websiteid' operator='eq' value='$targetWebsiteGuid' />
    </filter>
  </entity>
</fetch>
"@

$permissionRowsByLogicalName = @{}
foreach ($permission in $targetPermissions) {
  $logicalName = [string]$permission.mspp_entitylogicalname
  if (-not $permissionRowsByLogicalName.ContainsKey($logicalName)) {
    $permissionRowsByLogicalName[$logicalName] = New-Object System.Collections.Generic.List[object]
  }
  $permissionRowsByLogicalName[$logicalName].Add($permission)
}

$actions = New-Object System.Collections.Generic.List[object]

foreach ($sourcePermission in $sourcePermissions) {
  $logicalName = [string]$sourcePermission.entity_logical_name
  if ([string]::IsNullOrWhiteSpace($logicalName) -or -not $permissionRowsByLogicalName.ContainsKey($logicalName)) {
    $actions.Add([pscustomobject]@{
      action = "missing-target-permission"
      entity_logical_name = $logicalName
      file_name = $sourcePermission.file_name
    }) | Out-Null
    continue
  }

  $targetRoleIds = @()
  foreach ($roleName in @($sourcePermission.source_role_names)) {
    if ($targetRoleIdsByName.ContainsKey($roleName)) {
      $targetRoleIds += @($targetRoleIdsByName[$roleName].ToArray())
    }
  }
  $targetRoleIds = @($targetRoleIds | Select-Object -Unique)

  if ($targetRoleIds.Count -eq 0) {
    $actions.Add([pscustomobject]@{
      action = "no-target-roles-resolved"
      entity_logical_name = $logicalName
      source_role_names = @($sourcePermission.source_role_names)
      file_name = $sourcePermission.file_name
    }) | Out-Null
    continue
  }

  foreach ($permissionRow in @($permissionRowsByLogicalName[$logicalName].ToArray())) {
    $permissionId = [Guid]$permissionRow.mspp_entitypermissionid
    $existingRoleIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($existingRoleId in Get-LinkedRoleIds -PermissionId $permissionId) {
      [void]$existingRoleIds.Add([string]$existingRoleId)
    }

    foreach ($roleId in $targetRoleIds) {
      if ($existingRoleIds.Contains([string]$roleId)) {
        $actions.Add([pscustomobject]@{
          action = "already-associated"
          entity_logical_name = $logicalName
          permission_id = $permissionId
          role_id = $roleId
        }) | Out-Null
        continue
      }

      try {
        $request = [Microsoft.Xrm.Sdk.Messages.AssociateRequest]::new()
        $request.Target = New-EntityReference -LogicalName "mspp_entitypermission" -Id $permissionId
        $request.Relationship = [Microsoft.Xrm.Sdk.Relationship]::new("mspp_entitypermission_webrole")
        $request.RelatedEntities = [Microsoft.Xrm.Sdk.EntityReferenceCollection]::new()
        $request.RelatedEntities.Add((New-EntityReference -LogicalName "mspp_webrole" -Id $roleId))
        $null = $connection.Execute($request)
        [void]$existingRoleIds.Add([string]$roleId)

        $actions.Add([pscustomobject]@{
          action = "associated"
          entity_logical_name = $logicalName
          permission_id = $permissionId
          role_id = $roleId
        }) | Out-Null
      } catch {
        $message = $_.Exception.Message
        if ($message -like "*already exists*" -or $message -like "*matching key values already exists*" -or $message -like "*Cannot insert duplicate key*") {
          $actions.Add([pscustomobject]@{
            action = "already-associated"
            entity_logical_name = $logicalName
            permission_id = $permissionId
            role_id = $roleId
            message = $message
          }) | Out-Null
        } else {
          throw
        }
      }
    }
  }
}

$postRepair = foreach ($permissionRow in $targetPermissions) {
  $permissionId = [Guid]$permissionRow.mspp_entitypermissionid
  $linkedRoleIds = @(Get-LinkedRoleIds -PermissionId $permissionId)
  [pscustomobject]@{
    entity_logical_name = [string]$permissionRow.mspp_entitylogicalname
    permission_id = $permissionId
    linked_role_count = $linkedRoleIds.Count
    linked_role_ids = @($linkedRoleIds)
  }
}

$result = [ordered]@{
  captured_at = (Get-Date).ToUniversalTime().ToString("o")
  environment_url = $EnvironmentUrl
  website_id = $targetWebsiteGuid
  source_site_root = $SourceSiteRoot
  target_webroles = @($targetRoles | ForEach-Object {
    [ordered]@{
      id = [Guid]$_.mspp_webroleid
      name = [string]$_.mspp_name
    }
  })
  actions = $actions
  post_repair_permissions = $postRepair
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

[System.IO.File]::WriteAllText($fullOutputPath, ($result | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
Write-Output "OUTPUT_PATH=$fullOutputPath"
