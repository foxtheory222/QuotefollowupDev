param(
  [string]$RepoRoot = "C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion",
  [string]$SourceSiteRoot = "",
  [string]$TargetEnvironmentUrl = "https://orgad610d2c.crm3.dynamics.com",
  [string]$TargetHostname = "quoteoperations.powerappsportals.com",
  [string]$TargetWebsiteId = "",
  [string]$TargetWebRoleRoot = "",
  [string]$Username = "smcfarlane@applied.com",
  [string]$PortalContactEmail = "",
  [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($SourceSiteRoot)) {
  $SourceSiteRoot = Join-Path $RepoRoot "powerpages-live\operations-hub---operationhub"
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $RepoRoot "results\quoteoperations-dev-powerpages-security-repair-20260413.json"
}

$siteSettingPath = Join-Path $SourceSiteRoot "sitesetting.yml"
$tablePermissionsRoot = Join-Path $SourceSiteRoot "table-permissions"
$webRolePath = Join-Path $SourceSiteRoot "webrole.yml"

foreach ($requiredPath in @($siteSettingPath, $tablePermissionsRoot, $webRolePath)) {
  if (-not (Test-Path -LiteralPath $requiredPath)) {
    throw "Required source path not found: $requiredPath"
  }
}

Import-Module Microsoft.Xrm.Data.Powershell
Add-Type -AssemblyName "Microsoft.Xrm.Sdk"

$connection = Connect-CrmOnline -ServerUrl $TargetEnvironmentUrl -ForceOAuth -Username $Username
if (-not $connection -or -not $connection.IsReady) {
  throw "Dataverse connection failed for $TargetEnvironmentUrl : $($connection.LastCrmError)"
}

function Resolve-OptionalEntityLogicalName {
  param([string[]]$Candidates)

  try {
    return Resolve-EntityLogicalName -Candidates $Candidates
  } catch {
    return $null
  }
}

function Resolve-EntityLogicalName {
  param([string[]]$Candidates)

  foreach ($candidate in $Candidates) {
    try {
      $null = Get-CrmEntityMetadata -conn $connection -EntityLogicalName $candidate
      return $candidate
    } catch {
      continue
    }
  }

  throw "None of the candidate entities were found: $($Candidates -join ', ')"
}

function Get-FetchRows {
  param([string]$Fetch)
  return @((Get-CrmRecordsByFetch -conn $connection -Fetch $Fetch).CrmRecords)
}

function New-EntityReference {
  param(
    [string]$LogicalName,
    [Guid]$Id
  )

  return [Microsoft.Xrm.Sdk.EntityReference]::new($LogicalName, $Id)
}

function Convert-ToBoolean {
  param([string]$Value)
  return [string]::Equals([string]$Value, "true", [System.StringComparison]::OrdinalIgnoreCase)
}

function Normalize-Host {
  param([string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return ""
  }

  $candidate = [string]$Value
  $candidate = $candidate.Trim()
  if ($candidate -match '^[A-Za-z][A-Za-z0-9+\-.]*://') {
    try {
      return ([Uri]$candidate).Host.ToLowerInvariant()
    } catch {
      $candidate = $candidate -replace '^[A-Za-z][A-Za-z0-9+\-.]*://', ''
    }
  }

  $candidate = $candidate.Trim('/').ToLowerInvariant()
  if ($candidate.Contains('/')) {
    $candidate = $candidate.Split('/')[0]
  }

  return $candidate
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

$siteSettingEntityName = Resolve-EntityLogicalName -Candidates @("mspp_sitesetting", "adx_sitesetting")
$entityPermissionEntityName = Resolve-EntityLogicalName -Candidates @("mspp_entitypermission", "adx_entitypermission")
$entityPermissionRoleIntersectName = Resolve-EntityLogicalName -Candidates @("mspp_entitypermission_webrole", "adx_entitypermission_webrole")
$websiteEntityName = Resolve-EntityLogicalName -Candidates @("mspp_website", "adx_website")
$websiteBindingEntityName = Resolve-OptionalEntityLogicalName -Candidates @("mspp_websitebinding", "adx_websitebinding")
$webRoleEntityName = "mspp_webrole"

$siteSettingIdAttribute = if ($siteSettingEntityName -eq "mspp_sitesetting") { "mspp_sitesettingid" } else { "adx_sitesettingid" }
$siteSettingNameAttribute = if ($siteSettingEntityName -eq "mspp_sitesetting") { "mspp_name" } else { "adx_name" }
$siteSettingValueAttribute = if ($siteSettingEntityName -eq "mspp_sitesetting") { "mspp_value" } else { "adx_value" }
$siteSettingWebsiteAttribute = if ($siteSettingEntityName -eq "mspp_sitesetting") { "mspp_websiteid" } else { "adx_websiteid" }

$entityPermissionIdAttribute = if ($entityPermissionEntityName -eq "mspp_entitypermission") { "mspp_entitypermissionid" } else { "adx_entitypermissionid" }
$entityPermissionNameAttribute = if ($entityPermissionEntityName -eq "mspp_entitypermission") { "mspp_entityname" } else { "adx_entityname" }
$entityPermissionLogicalNameAttribute = if ($entityPermissionEntityName -eq "mspp_entitypermission") { "mspp_entitylogicalname" } else { "adx_entitylogicalname" }
$entityPermissionScopeAttribute = if ($entityPermissionEntityName -eq "mspp_entitypermission") { "mspp_scope" } else { "adx_scope" }
$entityPermissionReadAttribute = if ($entityPermissionEntityName -eq "mspp_entitypermission") { "mspp_read" } else { "adx_read" }
$entityPermissionWriteAttribute = if ($entityPermissionEntityName -eq "mspp_entitypermission") { "mspp_write" } else { "adx_write" }
$entityPermissionCreateAttribute = if ($entityPermissionEntityName -eq "mspp_entitypermission") { "mspp_create" } else { "adx_create" }
$entityPermissionAppendAttribute = if ($entityPermissionEntityName -eq "mspp_entitypermission") { "mspp_append" } else { "adx_append" }
$entityPermissionAppendToAttribute = if ($entityPermissionEntityName -eq "mspp_entitypermission") { "mspp_appendto" } else { "adx_appendto" }
$entityPermissionDeleteAttribute = if ($entityPermissionEntityName -eq "mspp_entitypermission") { "mspp_delete" } else { "adx_delete" }
$entityPermissionWebsiteAttribute = if ($entityPermissionEntityName -eq "mspp_entitypermission") { "mspp_websiteid" } else { "adx_websiteid" }

$websiteIdAttribute = if ($websiteEntityName -eq "mspp_website") { "mspp_websiteid" } else { "adx_websiteid" }
$websiteNameAttribute = if ($websiteEntityName -eq "mspp_website") { "mspp_name" } else { "adx_name" }

$websiteBindingIdAttribute = $null
$websiteBindingDomainAttribute = $null
$websiteBindingSubdomainAttribute = $null
$websiteBindingWebsiteAttribute = $null
$websiteBindingNameAttribute = $null
if ($websiteBindingEntityName) {
  $websiteBindingIdAttribute = if ($websiteBindingEntityName -eq "mspp_websitebinding") { "mspp_websitebindingid" } else { "adx_websitebindingid" }
  $websiteBindingDomainAttribute = if ($websiteBindingEntityName -eq "mspp_websitebinding") { "mspp_domainname" } else { "adx_domainname" }
  $websiteBindingSubdomainAttribute = if ($websiteBindingEntityName -eq "mspp_websitebinding") { "mspp_subdomain" } else { "adx_subdomain" }
  $websiteBindingWebsiteAttribute = if ($websiteBindingEntityName -eq "mspp_websitebinding") { "mspp_websiteid" } else { "adx_websiteid" }
  $websiteBindingNameAttribute = if ($websiteBindingEntityName -eq "mspp_websitebinding") { "mspp_name" } else { "adx_name" }
}

$entityPermissionRoleAttribute = if ($entityPermissionRoleIntersectName -eq "mspp_entitypermission_webrole") { "mspp_webroleid" } else { "adx_webroleid" }

$normalizedTargetHost = Normalize-Host $TargetHostname

if ([string]::IsNullOrWhiteSpace($TargetWebsiteId)) {
  if (-not $websiteBindingEntityName) {
    throw "Website binding entity is unavailable in this environment. Re-run with -TargetWebsiteId for the hostname-backed website."
  }

  $bindings = Get-FetchRows @"
<fetch count='100'>
  <entity name='$websiteBindingEntityName'>
    <attribute name='$websiteBindingIdAttribute' />
    <attribute name='$websiteBindingDomainAttribute' />
    <attribute name='$websiteBindingSubdomainAttribute' />
    <attribute name='$websiteBindingNameAttribute' />
    <attribute name='$websiteBindingWebsiteAttribute' />
  </entity>
</fetch>
"@

  $resolvedBinding = $bindings | Where-Object {
    $domainHost = Normalize-Host ([string]$_.$websiteBindingDomainAttribute)
    $subdomainHost = if ([string]::IsNullOrWhiteSpace([string]$_.$websiteBindingSubdomainAttribute)) { "" } else { ("{0}.powerappsportals.com" -f ([string]$_.$websiteBindingSubdomainAttribute).ToLowerInvariant()) }
    $nameHost = Normalize-Host ([string]$_.$websiteBindingNameAttribute)
    $domainHost -eq $normalizedTargetHost -or $subdomainHost -eq $normalizedTargetHost -or $nameHost -eq $normalizedTargetHost
  } | Select-Object -First 1

  if (-not $resolvedBinding) {
    throw "Could not resolve a website binding for hostname $TargetHostname in $TargetEnvironmentUrl"
  }

  $TargetWebsiteId = if ($resolvedBinding.$websiteBindingWebsiteAttribute -and $resolvedBinding.$websiteBindingWebsiteAttribute.Id) {
    [string]$resolvedBinding.$websiteBindingWebsiteAttribute.Id
  } else {
    [string]$resolvedBinding.$websiteBindingWebsiteAttribute
  }
}

$targetWebsiteGuid = [Guid]$TargetWebsiteId

$targetWebsiteRow = Get-FetchRows @"
<fetch count='1'>
  <entity name='$websiteEntityName'>
    <attribute name='$websiteIdAttribute' />
    <attribute name='$websiteNameAttribute' />
    <filter>
      <condition attribute='$websiteIdAttribute' operator='eq' value='$targetWebsiteGuid' />
    </filter>
  </entity>
</fetch>
"@ | Select-Object -First 1

if (-not $targetWebsiteRow) {
  throw "Target website $targetWebsiteGuid was not found in $TargetEnvironmentUrl"
}

$sourceSiteSettings = Parse-YamlList -Path $siteSettingPath |
  Where-Object { $_.adx_name -like "Webapi/*" } |
  ForEach-Object {
    [pscustomobject]@{
      name = [string]$_.adx_name
      value = [string]$_.adx_value
    }
  }

$sourceWebRoles = Parse-YamlList -Path $webRolePath |
  ForEach-Object {
    [pscustomobject]@{
      id = [Guid]$_.adx_webroleid
      name = [string]$_.adx_name
      anonymous = Convert-ToBoolean $_.adx_anonymoususersrole
      authenticated = Convert-ToBoolean $_.adx_authenticatedusersrole
    }
  }

$sourcePermissions = Get-ChildItem -LiteralPath $tablePermissionsRoot -Filter "*.tablepermission.yml" |
  Sort-Object Name |
  ForEach-Object {
    $data = Parse-SimpleYamlMap -Path $_.FullName
    [pscustomobject]@{
      file_name = $_.Name
      entity_name = [string]$data.adx_entityname
      entity_logical_name = [string]$data.adx_entitylogicalname
      scope = [int]$data.adx_scope
      read = Convert-ToBoolean $data.adx_read
      write = Convert-ToBoolean $data.adx_write
      create = Convert-ToBoolean $data.adx_create
      append = Convert-ToBoolean $data.adx_append
      appendto = Convert-ToBoolean $data.adx_appendto
      delete = Convert-ToBoolean $data.adx_delete
      source_role_ids = @($data.adx_entitypermission_webrole |
        Where-Object { $_ -and [string]$_ -match '^[0-9A-Fa-f-]{36}$' } |
        ForEach-Object { [Guid]$_ })
    }
  }

$sourceRoleMapById = @{}
$sourceRoleIdsByName = @{}
foreach ($roleRow in Parse-YamlList -Path $webRolePath) {
  if ($roleRow.adx_webroleid) {
    $roleGuid = [Guid]$roleRow.adx_webroleid
    $roleName = [string]$roleRow.adx_name
    $sourceRoleMapById[[string]$roleGuid] = $roleName
    $sourceRoleIdsByName[$roleName] = $roleGuid
  }
}

$targetRoleIdsByName = @{}
$targetWebRoles = New-Object System.Collections.Generic.List[object]
if (-not [string]::IsNullOrWhiteSpace($TargetWebRoleRoot)) {
  $targetWebRolePath = Join-Path $TargetWebRoleRoot "webrole.yml"
  if (-not (Test-Path -LiteralPath $targetWebRolePath)) {
    throw "Target webrole source path not found: $targetWebRolePath"
  }

  foreach ($roleRow in Parse-YamlList -Path $targetWebRolePath) {
    if ($roleRow.adx_webroleid) {
      $roleGuid = [Guid]$roleRow.adx_webroleid
      $roleName = [string]$roleRow.adx_name
      if (-not [string]::IsNullOrWhiteSpace($roleName) -and -not $targetRoleIdsByName.ContainsKey($roleName)) {
        $targetRoleIdsByName[$roleName] = $roleGuid
        $targetWebRoles.Add([pscustomobject]@{
          name = $roleName
          id = $roleGuid
          source = $targetWebRolePath
        }) | Out-Null
      }
    }
  }
}

$existingTargetSiteSettings = Get-FetchRows @"
<fetch count='250'>
  <entity name='$siteSettingEntityName'>
    <attribute name='$siteSettingIdAttribute' />
    <attribute name='$siteSettingNameAttribute' />
    <attribute name='$siteSettingValueAttribute' />
    <attribute name='$siteSettingWebsiteAttribute' />
    <filter>
      <condition attribute='$siteSettingWebsiteAttribute' operator='eq' value='$targetWebsiteGuid' />
    </filter>
  </entity>
</fetch>
"@

$siteSettingsByName = @{}
foreach ($row in $existingTargetSiteSettings) {
  $name = [string]$row.$siteSettingNameAttribute
  if (-not $siteSettingsByName.ContainsKey($name)) {
    $siteSettingsByName[$name] = New-Object System.Collections.Generic.List[object]
  }
  $siteSettingsByName[$name].Add($row)
}

$existingTargetPermissions = Get-FetchRows @"
<fetch count='250'>
  <entity name='$entityPermissionEntityName'>
    <attribute name='$entityPermissionIdAttribute' />
    <attribute name='$entityPermissionNameAttribute' />
    <attribute name='$entityPermissionLogicalNameAttribute' />
    <attribute name='$entityPermissionWebsiteAttribute' />
    <attribute name='$entityPermissionScopeAttribute' />
    <attribute name='$entityPermissionReadAttribute' />
    <attribute name='$entityPermissionWriteAttribute' />
    <attribute name='$entityPermissionCreateAttribute' />
    <attribute name='$entityPermissionAppendAttribute' />
    <attribute name='$entityPermissionAppendToAttribute' />
    <attribute name='$entityPermissionDeleteAttribute' />
    <filter>
      <condition attribute='$entityPermissionWebsiteAttribute' operator='eq' value='$targetWebsiteGuid' />
    </filter>
  </entity>
</fetch>
"@

$permissionsByLogicalName = @{}
foreach ($row in $existingTargetPermissions) {
  $logicalName = [string]$row.$entityPermissionLogicalNameAttribute
  if (-not $permissionsByLogicalName.ContainsKey($logicalName)) {
    $permissionsByLogicalName[$logicalName] = New-Object System.Collections.Generic.List[object]
  }
  $permissionsByLogicalName[$logicalName].Add($row)
}

$webApiHeaders = @{
  Authorization      = "Bearer $($connection.CurrentAccessToken)"
  Accept             = "application/json"
  "OData-MaxVersion" = "4.0"
  "OData-Version"    = "4.0"
}
$entityPermissionEntitySetName = "mspp_entitypermissions"
$webRoleEntitySetName = "mspp_webroles"

$webRoleActions = New-Object System.Collections.Generic.List[object]
$siteSettingActions = New-Object System.Collections.Generic.List[object]
$permissionActions = New-Object System.Collections.Generic.List[object]
$roleLinkActions = New-Object System.Collections.Generic.List[object]
$contactRoleActions = New-Object System.Collections.Generic.List[object]

foreach ($sourceRole in $sourceWebRoles) {
  $webRoleActions.Add([pscustomobject]@{
    action = "source-role-loaded"
    role_name = $sourceRole.name
    role_id = $sourceRole.id
  })
}

foreach ($targetRole in $targetWebRoles) {
  $webRoleActions.Add([pscustomobject]@{
    action = "target-role-loaded"
    role_name = $targetRole.name
    role_id = $targetRole.id
    source = $targetRole.source
  })
}

foreach ($setting in $sourceSiteSettings) {
  $settingName = [string]$setting.name
  $matchingRows = if ($siteSettingsByName.ContainsKey($settingName)) { @($siteSettingsByName[$settingName].ToArray()) } else { @() }
  if ($matchingRows.Count -eq 0) {
    $entity = [Microsoft.Xrm.Sdk.Entity]::new($siteSettingEntityName)
    $siteSettingId = [Guid]::NewGuid()
    $entity.Id = $siteSettingId
    $entity[$siteSettingNameAttribute] = $settingName
    $entity[$siteSettingValueAttribute] = $setting.value
    $entity[$siteSettingWebsiteAttribute] = New-EntityReference -LogicalName $websiteEntityName -Id $targetWebsiteGuid
    $null = $connection.Create($entity)

    $siteSettingActions.Add([pscustomobject]@{
      action = "created"
      name = $settingName
      id = $siteSettingId
      value = $setting.value
    })
    continue
  }

  foreach ($row in $matchingRows) {
    $entity = [Microsoft.Xrm.Sdk.Entity]::new($siteSettingEntityName)
    $entity.Id = [Guid]$row.$siteSettingIdAttribute
    $entity[$siteSettingValueAttribute] = $setting.value
    $connection.Update($entity)

    $siteSettingActions.Add([pscustomobject]@{
      action = "updated"
      name = $settingName
      id = [Guid]$row.$siteSettingIdAttribute
      value = $setting.value
    })
  }
}

foreach ($permission in $sourcePermissions) {
  $permissionLogicalName = [string]$permission.entity_logical_name
  $matchingRows = if ($permissionsByLogicalName.ContainsKey($permissionLogicalName)) { @($permissionsByLogicalName[$permissionLogicalName].ToArray()) } else { @() }
  if ($matchingRows.Count -eq 0) {
    $entity = [Microsoft.Xrm.Sdk.Entity]::new($entityPermissionEntityName)
    $permissionId = [Guid]::NewGuid()
    $entity.Id = $permissionId
    $entity[$entityPermissionNameAttribute] = $permission.entity_name
    $entity[$entityPermissionLogicalNameAttribute] = $permissionLogicalName
    $entity[$entityPermissionScopeAttribute] = [Microsoft.Xrm.Sdk.OptionSetValue]::new($permission.scope)
    $entity[$entityPermissionReadAttribute] = $permission.read
    $entity[$entityPermissionWriteAttribute] = $permission.write
    $entity[$entityPermissionCreateAttribute] = $permission.create
    $entity[$entityPermissionAppendAttribute] = $permission.append
    $entity[$entityPermissionAppendToAttribute] = $permission.appendto
    $entity[$entityPermissionDeleteAttribute] = $permission.delete
    $entity[$entityPermissionWebsiteAttribute] = New-EntityReference -LogicalName $websiteEntityName -Id $targetWebsiteGuid
    $null = $connection.Create($entity)

    $matchingRows = @([pscustomobject]@{
      $entityPermissionIdAttribute = $permissionId
      $entityPermissionLogicalNameAttribute = $permissionLogicalName
      $entityPermissionNameAttribute = $permission.entity_name
    })

    $permissionActions.Add([pscustomobject]@{
      action = "created"
      entity_logical_name = $permissionLogicalName
      id = $permissionId
      file_name = $permission.file_name
    })
  } else {
    foreach ($row in $matchingRows) {
      $entity = [Microsoft.Xrm.Sdk.Entity]::new($entityPermissionEntityName)
      $entity.Id = [Guid]$row.$entityPermissionIdAttribute
      $entity[$entityPermissionNameAttribute] = $permission.entity_name
      $entity[$entityPermissionLogicalNameAttribute] = $permissionLogicalName
      $entity[$entityPermissionScopeAttribute] = [Microsoft.Xrm.Sdk.OptionSetValue]::new($permission.scope)
      $entity[$entityPermissionReadAttribute] = $permission.read
      $entity[$entityPermissionWriteAttribute] = $permission.write
      $entity[$entityPermissionCreateAttribute] = $permission.create
      $entity[$entityPermissionAppendAttribute] = $permission.append
      $entity[$entityPermissionAppendToAttribute] = $permission.appendto
      $entity[$entityPermissionDeleteAttribute] = $permission.delete
      $connection.Update($entity)

      $permissionActions.Add([pscustomobject]@{
        action = "updated"
        entity_logical_name = $permissionLogicalName
        id = [Guid]$row.$entityPermissionIdAttribute
        file_name = $permission.file_name
      })
    }
  }

  $targetRoleIds = @(
    $permission.source_role_ids |
      Select-Object -Unique |
      ForEach-Object {
        $sourceRoleId = [Guid]$_
        $sourceRoleName = $sourceRoleMapById[[string]$sourceRoleId]
        if ($sourceRoleName -and $targetRoleIdsByName.ContainsKey($sourceRoleName)) {
          $targetRoleIdsByName[$sourceRoleName]
        } else {
          $sourceRoleId
        }
      }
  )
  if ($targetRoleIds.Count -eq 0 -and $permissionLogicalName -eq "qfu_branchopsdaily") {
    $targetRoleIds = @(
      $(if ($targetRoleIdsByName.ContainsKey("Authenticated Users")) { $targetRoleIdsByName["Authenticated Users"] } else { $sourceRoleIdsByName["Authenticated Users"] }),
      $(if ($targetRoleIdsByName.ContainsKey("Anonymous Users")) { $targetRoleIdsByName["Anonymous Users"] } else { $sourceRoleIdsByName["Anonymous Users"] }),
      $(if ($targetRoleIdsByName.ContainsKey("Administrators")) { $targetRoleIdsByName["Administrators"] } else { $sourceRoleIdsByName["Administrators"] })
    ) | Where-Object { $_ } | Select-Object -Unique
  }

  foreach ($row in $matchingRows) {
    $permissionId = [Guid]$row.$entityPermissionIdAttribute
    $existingRoleIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($entityPermissionEntityName -eq "mspp_entitypermission" -and $webRoleEntityName -eq "mspp_webrole") {
      $roleUri = "$TargetEnvironmentUrl/api/data/v9.2/$entityPermissionEntitySetName($permissionId)/mspp_entitypermission_webrole?`$select=mspp_webroleid,mspp_name"
      $existingRoleRows = @((Invoke-RestMethod -Method Get -Uri $roleUri -Headers $webApiHeaders).value)
      foreach ($existingRoleRow in $existingRoleRows) {
        if ($existingRoleRow.mspp_webroleid) {
          $null = $existingRoleIds.Add([string]$existingRoleRow.mspp_webroleid)
        }
      }
    }

    foreach ($roleId in $targetRoleIds) {
      try {
        if ($existingRoleIds.Contains([string]$roleId)) {
          $roleLinkActions.Add([pscustomobject]@{
            action = "already-associated"
            entity_logical_name = $permissionLogicalName
            permission_id = $permissionId
            role_id = $roleId
          })
          continue
        }

        if ($entityPermissionEntityName -eq "mspp_entitypermission" -and $webRoleEntityName -eq "mspp_webrole") {
          $body = @{
            "@odata.id" = "$TargetEnvironmentUrl/api/data/v9.2/$webRoleEntitySetName($roleId)"
          }
          Invoke-RestMethod -Method Post -Uri "$TargetEnvironmentUrl/api/data/v9.2/$entityPermissionEntitySetName($permissionId)/mspp_entitypermission_webrole/`$ref" -Headers $webApiHeaders -ContentType "application/json" -Body ($body | ConvertTo-Json -Compress) | Out-Null
          $null = $existingRoleIds.Add([string]$roleId)
        } else {
          $request = [Microsoft.Xrm.Sdk.Messages.AssociateRequest]::new()
          $request.Target = New-EntityReference -LogicalName $entityPermissionEntityName -Id $permissionId
          $request.Relationship = [Microsoft.Xrm.Sdk.Relationship]::new($entityPermissionRoleIntersectName)
          $request.RelatedEntities = [Microsoft.Xrm.Sdk.EntityReferenceCollection]::new()
          $request.RelatedEntities.Add((New-EntityReference -LogicalName $webRoleEntityName -Id $roleId))
          $null = $connection.Execute($request)
        }

        $roleLinkActions.Add([pscustomobject]@{
          action = "associated"
          entity_logical_name = $permissionLogicalName
          permission_id = $permissionId
          role_id = $roleId
        })
      } catch {
        $message = $_.Exception.Message
        if ($message -like "*already exists*" -or $message -like "*matching key values already exists*" -or $message -like "*Cannot insert duplicate key*") {
          $roleLinkActions.Add([pscustomobject]@{
            action = "already-associated"
            entity_logical_name = $permissionLogicalName
            permission_id = $permissionId
            role_id = $roleId
          })
        } else {
          throw
        }
      }
    }
  }
}

if (-not [string]::IsNullOrWhiteSpace($PortalContactEmail)) {
  $escapedEmail = [System.Security.SecurityElement]::Escape($PortalContactEmail)
  $contactRows = Get-FetchRows @"
<fetch count='5'>
  <entity name='contact'>
    <attribute name='contactid' />
    <attribute name='fullname' />
    <attribute name='emailaddress1' />
    <filter>
      <condition attribute='emailaddress1' operator='eq' value='$escapedEmail' />
    </filter>
  </entity>
</fetch>
"@

  $targetContact = $contactRows | Select-Object -First 1
  if ($targetContact) {
    $token = $connection.CurrentAccessToken
    $headers = @{
      Authorization      = "Bearer $token"
      Accept             = "application/json"
      "OData-MaxVersion" = "4.0"
      "OData-Version"    = "4.0"
    }

    $desiredContactRoles = @("Authenticated Users", "Administrators") |
      Where-Object { $sourceRoleIdsByName.ContainsKey($_) } |
      ForEach-Object { [Guid]$sourceRoleIdsByName[$_] }

    $contactId = [Guid]$targetContact.contactid
    $existingUri = "$TargetEnvironmentUrl/api/data/v9.2/powerpagecomponent_mspp_webrole_contactset?`$select=powerpagecomponent_mspp_webrole_contactid,contactid,powerpagecomponentid&`$filter=contactid eq $contactId"
    $existingRows = @((Invoke-RestMethod -Method Get -Uri $existingUri -Headers $headers).value)
    $existingRoleIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $existingRows) {
      [void]$existingRoleIds.Add([string]$row.powerpagecomponentid)
    }

    foreach ($roleId in $desiredContactRoles) {
      if ($existingRoleIds.Contains([string]$roleId)) {
        $contactRoleActions.Add([pscustomobject]@{
          action = "already-associated"
          contact_id = $contactId
          role_id = $roleId
          email = $PortalContactEmail
        })
        continue
      }

      $body = @{
        "@odata.id" = "$TargetEnvironmentUrl/api/data/v9.2/powerpagecomponents($roleId)"
      }

      Invoke-RestMethod -Method Post -Uri "$TargetEnvironmentUrl/api/data/v9.2/contacts($contactId)/powerpagecomponent_mspp_webrole_contact/`$ref" -Headers $headers -ContentType "application/json" -Body ($body | ConvertTo-Json -Compress) | Out-Null

      $contactRoleActions.Add([pscustomobject]@{
        action = "associated"
        contact_id = $contactId
        role_id = $roleId
        email = $PortalContactEmail
      })
    }
  } else {
    $contactRoleActions.Add([pscustomobject]@{
      action = "contact-not-found"
      email = $PortalContactEmail
    })
  }
}

$postRepairPermissions = foreach ($logicalName in ($sourcePermissions.entity_logical_name | Select-Object -Unique)) {
  $escapedLogicalName = [System.Security.SecurityElement]::Escape($logicalName)
  $rows = Get-FetchRows @"
<fetch count='50'>
  <entity name='$entityPermissionEntityName'>
    <attribute name='$entityPermissionIdAttribute' />
    <attribute name='$entityPermissionLogicalNameAttribute' />
    <attribute name='$entityPermissionNameAttribute' />
    <attribute name='$entityPermissionWebsiteAttribute' />
    <filter type='and'>
      <condition attribute='$entityPermissionWebsiteAttribute' operator='eq' value='$targetWebsiteGuid' />
      <condition attribute='$entityPermissionLogicalNameAttribute' operator='eq' value='$escapedLogicalName' />
    </filter>
    <link-entity name='$entityPermissionRoleIntersectName' from='mspp_entitypermissionid' to='mspp_entitypermissionid' alias='link' intersect='true' link-type='outer'>
      <attribute name='$entityPermissionRoleAttribute' />
    </link-entity>
  </entity>
</fetch>
"@

  [pscustomobject]@{
    entity_logical_name = $logicalName
    permission_count = @($rows | Select-Object -ExpandProperty $entityPermissionIdAttribute -Unique).Count
    role_link_count = @($rows | Where-Object { $_."link.$entityPermissionRoleAttribute" } | Select-Object -ExpandProperty "link.$entityPermissionRoleAttribute").Count
    permission_ids = @($rows | Select-Object -ExpandProperty $entityPermissionIdAttribute -Unique)
    linked_role_ids = @($rows | Where-Object { $_."link.$entityPermissionRoleAttribute" } | Select-Object -ExpandProperty "link.$entityPermissionRoleAttribute" -Unique)
  }
}

$payload = [ordered]@{
  captured_at = (Get-Date).ToUniversalTime().ToString("o")
  source_site_root = $SourceSiteRoot
  target_environment_url = $TargetEnvironmentUrl
  target_hostname = $TargetHostname
  target_website = [ordered]@{
    id = $targetWebsiteGuid
    name = [string]$targetWebsiteRow.$websiteNameAttribute
  }
  web_role_actions = $webRoleActions
  site_setting_actions = $siteSettingActions
  permission_actions = $permissionActions
  role_link_actions = $roleLinkActions
  contact_role_actions = $contactRoleActions
  post_repair_permissions = $postRepairPermissions
}

[System.IO.File]::WriteAllText($OutputPath, ($payload | ConvertTo-Json -Depth 10), [System.Text.UTF8Encoding]::new($false))
Write-Host "OUTPUT_PATH=$OutputPath"
