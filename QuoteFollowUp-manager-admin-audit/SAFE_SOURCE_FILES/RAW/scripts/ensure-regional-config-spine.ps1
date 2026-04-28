param(
  [string]$TargetEnvironmentUrl = "<URL>
  [string]$Username = "<EMAIL>",
  [string]$SolutionUniqueName = "Default"
)

$ErrorActionPreference = "Stop"

Import-Module Microsoft.Xrm.Data.Powershell
Add-Type -AssemblyName "Microsoft.Xrm.Sdk"
Add-Type -AssemblyName "Microsoft.Crm.Sdk.Proxy"

function New-Label {
  param([string]$Text)
  return [Microsoft.Xrm.Sdk.Label]::new($Text, 1033)
}

function New-RequiredLevel {
  param([Microsoft.Xrm.Sdk.Metadata.AttributeRequiredLevel]$Level)
  return [Microsoft.Xrm.Sdk.Metadata.AttributeRequiredLevelManagedProperty]::new($Level)
}

function Connect-Org {
  param([string]$Url)

  $conn = Connect-CrmOnline -ServerUrl $Url -ForceOAuth -Username $Username
  if (-not $conn -or -not $conn.IsReady) {
    throw "Dataverse connection failed for $Url : $($conn.LastCrmError)"
  }

  return $conn
}

function Test-EntityExists {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$LogicalName
  )

  try {
    $request = [Microsoft.Xrm.Sdk.Messages.RetrieveEntityRequest]::new()
    $request.LogicalName = $LogicalName
    $request.EntityFilters = [Microsoft.Xrm.Sdk.Metadata.EntityFilters]::Entity
    $request.RetrieveAsIfPublished = $true
    $null = $Connection.Execute($request)
    return $true
  } catch {
    return $false
  }
}

function Test-AttributeExists {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$EntityLogicalName,
    [string]$AttributeLogicalName
  )

  try {
    $request = [Microsoft.Xrm.Sdk.Messages.RetrieveAttributeRequest]::new()
    $request.EntityLogicalName = $EntityLogicalName
    $request.LogicalName = $AttributeLogicalName
    $request.RetrieveAsIfPublished = $true
    $null = $Connection.Execute($request)
    return $true
  } catch {
    return $false
  }
}

function Publish-Entities {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string[]]$LogicalNames
  )

  $xml = "<importexportxml><entities>" + (($LogicalNames | ForEach-Object { "<entity>$_</entity>" }) -join "") + "</entities><nodes/><securityroles/><settings/><workflows/></importexportxml>"
  $request = [Microsoft.Crm.Sdk.Messages.PublishXmlRequest]::new()
  $request.ParameterXml = $xml
  $attempt = 0

  while ($true) {
    try {
      $null = $Connection.Execute($request)
      return
    } catch {
      $message = $_.Exception.Message
      if (($message -like "*another [Import] running*" -or $message -like "*CustomizationLockException*" -or $message -like "*try again later*") -and $attempt -lt 5) {
        Start-Sleep -Seconds (10 * ($attempt + 1))
        $attempt += 1
        continue
      }
      throw
    }
  }
}

function Invoke-MetadataCreateRequest {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [object]$Request,
    [string]$AlreadyExistsLabel
  )

  $attempt = 0
  while ($true) {
    try {
      $null = $Connection.Execute($Request)
      return
    } catch {
      $message = $_.Exception.Message
      if ($message -like "*already exists*") {
        Write-Host $AlreadyExistsLabel
        return
      }
      if (($message -like "*CustomizationLockException*" -or $message -like "*try again later*") -and $attempt -lt 5) {
        Start-Sleep -Seconds (5 * ($attempt + 1))
        $attempt += 1
        continue
      }
      throw
    }
  }
}

function Ensure-Entity {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$SchemaName,
    [string]$DisplayName,
    [string]$DisplayCollectionName,
    [string]$Description,
    [string]$PrimaryNameSchema,
    [string]$PrimaryNameDisplay,
    [int]$PrimaryNameLength = 200
  )

  if (Test-EntityExists -Connection $Connection -LogicalName $SchemaName) {
    Write-Host "Entity exists: $SchemaName"
    return
  }

  $entity = [Microsoft.Xrm.Sdk.Metadata.EntityMetadata]::new()
  $entity.SchemaName = $SchemaName
  $entity.DisplayName = New-Label $DisplayName
  $entity.DisplayCollectionName = New-Label $DisplayCollectionName
  $entity.Description = New-Label $Description
  $entity.OwnershipType = [Microsoft.Xrm.Sdk.Metadata.OwnershipTypes]::OrganizationOwned
  $entity.IsActivity = $false

  $primary = [Microsoft.Xrm.Sdk.Metadata.StringAttributeMetadata]::new()
  $primary.SchemaName = $PrimaryNameSchema
  $primary.DisplayName = New-Label $PrimaryNameDisplay
  $primary.RequiredLevel = New-RequiredLevel ([Microsoft.Xrm.Sdk.Metadata.AttributeRequiredLevel]::ApplicationRequired)
  $primary.MaxLength = $PrimaryNameLength

  $request = [Microsoft.Xrm.Sdk.Messages.CreateEntityRequest]::new()
  $request.Entity = $entity
  $request.PrimaryAttribute = $primary
  $request.HasActivities = $false
  $request.HasFeedback = $false
  $request.HasNotes = $false
  if ($SolutionUniqueName) {
    $request.SolutionUniqueName = $SolutionUniqueName
  }

  Invoke-MetadataCreateRequest -Connection $Connection -Request $request -AlreadyExistsLabel "Entity exists after retry: $SchemaName"
  Write-Host "Created entity: $SchemaName"
}

function Ensure-StringAttribute {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$EntityLogicalName,
    [string]$SchemaName,
    [string]$DisplayName,
    [int]$MaxLength = 200,
    [string]$Description = ""
  )

  if (Test-AttributeExists -Connection $Connection -EntityLogicalName $EntityLogicalName -AttributeLogicalName $SchemaName) {
    Write-Host "Attribute exists: $EntityLogicalName.$SchemaName"
    return
  }

  $attribute = [Microsoft.Xrm.Sdk.Metadata.StringAttributeMetadata]::new()
  $attribute.SchemaName = $SchemaName
  $attribute.DisplayName = New-Label $DisplayName
  $attribute.Description = New-Label $Description
  $attribute.RequiredLevel = New-RequiredLevel ([Microsoft.Xrm.Sdk.Metadata.AttributeRequiredLevel]::None)
  $attribute.MaxLength = $MaxLength

  $request = [Microsoft.Xrm.Sdk.Messages.CreateAttributeRequest]::new()
  $request.EntityName = $EntityLogicalName
  $request.Attribute = $attribute
  if ($SolutionUniqueName) {
    $request.SolutionUniqueName = $SolutionUniqueName
  }

  Invoke-MetadataCreateRequest -Connection $Connection -Request $request -AlreadyExistsLabel "Attribute exists after retry: $EntityLogicalName.$SchemaName"
  Write-Host "Created string attribute: $EntityLogicalName.$SchemaName"
}

function Ensure-MemoAttribute {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$EntityLogicalName,
    [string]$SchemaName,
    [string]$DisplayName,
    [int]$MaxLength = 2000,
    [string]$Description = ""
  )

  if (Test-AttributeExists -Connection $Connection -EntityLogicalName $EntityLogicalName -AttributeLogicalName $SchemaName) {
    Write-Host "Attribute exists: $EntityLogicalName.$SchemaName"
    return
  }

  $attribute = [Microsoft.Xrm.Sdk.Metadata.MemoAttributeMetadata]::new()
  $attribute.SchemaName = $SchemaName
  $attribute.DisplayName = New-Label $DisplayName
  $attribute.Description = New-Label $Description
  $attribute.RequiredLevel = New-RequiredLevel ([Microsoft.Xrm.Sdk.Metadata.AttributeRequiredLevel]::None)
  $attribute.MaxLength = $MaxLength

  $request = [Microsoft.Xrm.Sdk.Messages.CreateAttributeRequest]::new()
  $request.EntityName = $EntityLogicalName
  $request.Attribute = $attribute
  if ($SolutionUniqueName) {
    $request.SolutionUniqueName = $SolutionUniqueName
  }

  Invoke-MetadataCreateRequest -Connection $Connection -Request $request -AlreadyExistsLabel "Attribute exists after retry: $EntityLogicalName.$SchemaName"
  Write-Host "Created memo attribute: $EntityLogicalName.$SchemaName"
}

function Ensure-WholeNumberAttribute {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$EntityLogicalName,
    [string]$SchemaName,
    [string]$DisplayName,
    [int]$MinValue = 0,
    [int]$MaxValue = 100000,
    [string]$Description = ""
  )

  if (Test-AttributeExists -Connection $Connection -EntityLogicalName $EntityLogicalName -AttributeLogicalName $SchemaName) {
    Write-Host "Attribute exists: $EntityLogicalName.$SchemaName"
    return
  }

  $attribute = [Microsoft.Xrm.Sdk.Metadata.IntegerAttributeMetadata]::new()
  $attribute.SchemaName = $SchemaName
  $attribute.DisplayName = New-Label $DisplayName
  $attribute.Description = New-Label $Description
  $attribute.RequiredLevel = New-RequiredLevel ([Microsoft.Xrm.Sdk.Metadata.AttributeRequiredLevel]::None)
  $attribute.MinValue = $MinValue
  $attribute.MaxValue = $MaxValue

  $request = [Microsoft.Xrm.Sdk.Messages.CreateAttributeRequest]::new()
  $request.EntityName = $EntityLogicalName
  $request.Attribute = $attribute
  if ($SolutionUniqueName) {
    $request.SolutionUniqueName = $SolutionUniqueName
  }

  Invoke-MetadataCreateRequest -Connection $Connection -Request $request -AlreadyExistsLabel "Attribute exists after retry: $EntityLogicalName.$SchemaName"
  Write-Host "Created integer attribute: $EntityLogicalName.$SchemaName"
}

function Get-RecordId {
  param(
    [object]$Record,
    [string]$PrimaryIdAttribute
  )

  $value = $Record.$PrimaryIdAttribute
  if (-not $value) {
    throw "Primary id field $PrimaryIdAttribute was not present on record."
  }

  return [guid]([string]$value)
}

function Set-RecordFields {
  param(
    [Microsoft.Xrm.Sdk.Entity]$Entity,
    [hashtable]$Fields
  )

  foreach ($key in $Fields.Keys) {
    $Entity[$key] = $Fields[$key]
  }
}

function Get-OptionalRecordValue {
  param(
    [object]$Record,
    [string]$FieldName
  )

  if ($null -eq $Record -or -not $Record.PSObject.Properties[$FieldName]) {
    return $null
  }

  return $Record.$FieldName
}

function Get-RecordTimestamp {
  param([object]$Record)

  $modified = Get-OptionalRecordValue -Record $Record -FieldName "modifiedon"
  if ($modified) {
    return [datetime]$modified
  }

  $created = Get-OptionalRecordValue -Record $Record -FieldName "createdon"
  if ($created) {
    return [datetime]$created
  }

  return [datetime]::MinValue
}

function Get-RecordCompletenessScore {
  param(
    [object]$Record,
    [string[]]$FieldNames
  )

  $score = 0
  foreach ($fieldName in @($FieldNames)) {
    $value = Get-OptionalRecordValue -Record $Record -FieldName $fieldName
    if ($null -eq $value) {
      continue
    }

    $text = [string]$value
    if (-not [string]::IsNullOrWhiteSpace($text)) {
      $score += 1
    }
  }

  return $score
}

function Remove-RecordSafe {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$EntityLogicalName,
    [Guid]$RecordId
  )

  try {
    $Connection.Delete($EntityLogicalName, $RecordId)
  } catch {
    if ($_.Exception.Message -like "*Does Not Exist*" -or $_.Exception.Message -like "*No object matched the query*") {
      return
    }
    throw
  }
}

function Upsert-ConfigRecord {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$EntityLogicalName,
    [string]$PrimaryIdAttribute,
    [string]$FilterAttribute,
    [string]$FilterValue,
    [hashtable]$Fields
  )

  $lookupFields = @($PrimaryIdAttribute, $FilterAttribute, "createdon", "modifiedon") + @($Fields.Keys)
  $existing = @((Get-CrmRecords -conn $Connection -EntityLogicalName $EntityLogicalName -FilterAttribute $FilterAttribute -FilterOperator eq -FilterValue $FilterValue -Fields $lookupFields -TopCount 25).CrmRecords)

  if ($existing.Count -gt 0) {
    $ordered = @(
      $existing |
        Sort-Object `
          @{ Expression = { Get-RecordCompletenessScore -Record $_ -FieldNames @($Fields.Keys) }; Descending = $true }, `
          @{ Expression = { Get-RecordTimestamp -Record $_ }; Descending = $true }, `
          @{ Expression = { [string](Get-OptionalRecordValue -Record $_ -FieldName $PrimaryIdAttribute) } }
    )
    $winner = $ordered | Select-Object -First 1
    $duplicates = @($ordered | Select-Object -Skip 1)

    $entity = [Microsoft.Xrm.Sdk.Entity]::new($EntityLogicalName, (Get-RecordId -Record $winner -PrimaryIdAttribute $PrimaryIdAttribute))
    Set-RecordFields -Entity $entity -Fields $Fields
    $Connection.Update($entity)
    Write-Host "Updated $EntityLogicalName where $FilterAttribute=$FilterValue"

    foreach ($duplicate in $duplicates) {
      $duplicateId = Get-RecordId -Record $duplicate -PrimaryIdAttribute $PrimaryIdAttribute
      Remove-RecordSafe -Connection $Connection -EntityLogicalName $EntityLogicalName -RecordId $duplicateId
      Write-Host "Removed duplicate $EntityLogicalName row $duplicateId where $FilterAttribute=$FilterValue"
    }
    return
  }

  $entity = [Microsoft.Xrm.Sdk.Entity]::new($EntityLogicalName)
  Set-RecordFields -Entity $entity -Fields $Fields
  $null = $Connection.Create($entity)
  Write-Host "Created $EntityLogicalName where $FilterAttribute=$FilterValue"
}

$connection = Connect-Org -Url $TargetEnvironmentUrl

Ensure-Entity `
  -Connection $connection `
  -SchemaName "qfu_region" `
  -DisplayName "QFU Region" `
  -DisplayCollectionName "QFU Regions" `
  -Description "Manager-editable region configuration for the Quote Follow Up regional rollout." `
  -PrimaryNameSchema "qfu_name" `
  -PrimaryNameDisplay "Region Name"

Ensure-StringAttribute -Connection $connection -EntityLogicalName "qfu_region" -SchemaName "qfu_regionslug" -DisplayName "Region Slug" -MaxLength 100 -Description "Stable route/config slug for the region."
Ensure-StringAttribute -Connection $connection -EntityLogicalName "qfu_region" -SchemaName "qfu_regionname" -DisplayName "Region Display Name" -MaxLength 200 -Description "Manager-facing region label."
Ensure-StringAttribute -Connection $connection -EntityLogicalName "qfu_region" -SchemaName "qfu_status" -DisplayName "Region Status" -MaxLength 50 -Description "Requested region state such as live, locked, awaiting, or stale."
Ensure-WholeNumberAttribute -Connection $connection -EntityLogicalName "qfu_region" -SchemaName "qfu_sortorder" -DisplayName "Sort Order" -Description "Display order for region cards."
Ensure-WholeNumberAttribute -Connection $connection -EntityLogicalName "qfu_region" -SchemaName "qfu_stalethresholdhours" -DisplayName "Stale Threshold Hours" -Description "Hours before the region is treated as stale when no fresh summary exists."
Ensure-WholeNumberAttribute -Connection $connection -EntityLogicalName "qfu_region" -SchemaName "qfu_budgetpacewarningpct" -DisplayName "Budget Pace Warning %" -Description "Warning threshold for budget pace."
Ensure-WholeNumberAttribute -Connection $connection -EntityLogicalName "qfu_region" -SchemaName "qfu_overduequotewarningcount" -DisplayName "Overdue Quote Warning Count" -Description "Warning threshold for overdue quotes."
Ensure-WholeNumberAttribute -Connection $connection -EntityLogicalName "qfu_region" -SchemaName "qfu_overduebackorderwarningcount" -DisplayName "Overdue Backorder Warning Count" -Description "Warning threshold for overdue backorders."
Ensure-MemoAttribute -Connection $connection -EntityLogicalName "qfu_region" -SchemaName "qfu_managernote" -DisplayName "Manager Note" -Description "Internal notes for rollout and status management."

Ensure-StringAttribute -Connection $connection -EntityLogicalName "qfu_branch" -SchemaName "qfu_branchstate" -DisplayName "Branch State" -MaxLength 50 -Description "Requested branch state such as live, locked, awaiting, or stale."
Ensure-WholeNumberAttribute -Connection $connection -EntityLogicalName "qfu_branch" -SchemaName "qfu_stalethresholdhours" -DisplayName "Stale Threshold Hours" -Description "Hours before the branch is treated as stale when no fresh summary exists."
Ensure-WholeNumberAttribute -Connection $connection -EntityLogicalName "qfu_branch" -SchemaName "qfu_budgetpacewarningpct" -DisplayName "Budget Pace Warning %" -Description "Warning threshold for budget pace."
Ensure-WholeNumberAttribute -Connection $connection -EntityLogicalName "qfu_branch" -SchemaName "qfu_overduequotewarningcount" -DisplayName "Overdue Quote Warning Count" -Description "Warning threshold for overdue quotes."
Ensure-WholeNumberAttribute -Connection $connection -EntityLogicalName "qfu_branch" -SchemaName "qfu_overduebackorderwarningcount" -DisplayName "Overdue Backorder Warning Count" -Description "Warning threshold for overdue backorders."
Ensure-MemoAttribute -Connection $connection -EntityLogicalName "qfu_branch" -SchemaName "qfu_managernote" -DisplayName "Manager Note" -Description "Internal notes for branch rollout and support."

Publish-Entities -Connection $connection -LogicalNames @("qfu_region", "qfu_branch")

$regionSeed = @(
  @{
    qfu_name = "Southern Alberta"
    qfu_regionslug = "southern-alberta"
    qfu_regionname = "Southern Alberta"
    qfu_status = "live"
    qfu_sortorder = 10
    qfu_stalethresholdhours = 36
    qfu_budgetpacewarningpct = 85
    qfu_overduequotewarningcount = 12
    qfu_overduebackorderwarningcount = 150
    qfu_managernote = "Pilot region live in DEV. 4171, 4172, and 4173 are the only active rollout branches in scope right now."
  },
  @{
    qfu_name = "Northern Alberta"
    qfu_regionslug = "northern-alberta"
    qfu_regionname = "Northern Alberta"
    qfu_status = "locked"
    qfu_sortorder = 20
    qfu_stalethresholdhours = 36
    qfu_budgetpacewarningpct = 85
    qfu_overduequotewarningcount = 12
    qfu_overduebackorderwarningcount = 150
    qfu_managernote = "Visible in the hub and nav structure, but intentionally locked until real integration begins."
  },
  @{
    qfu_name = "Saskatchewan"
    qfu_regionslug = "saskatchewan"
    qfu_regionname = "Saskatchewan"
    qfu_status = "locked"
    qfu_sortorder = 30
    qfu_stalethresholdhours = 36
    qfu_budgetpacewarningpct = 85
    qfu_overduequotewarningcount = 12
    qfu_overduebackorderwarningcount = 150
    qfu_managernote = "Visible in the hub and nav structure, but intentionally locked until real integration begins."
  }
)

foreach ($region in $regionSeed) {
  Upsert-ConfigRecord `
    -Connection $connection `
    -EntityLogicalName "qfu_region" `
    -PrimaryIdAttribute "qfu_regionid" `
    -FilterAttribute "qfu_regionslug" `
    -FilterValue $region.qfu_regionslug `
    -Fields $region
}

$branchSeed = @(
  @{
    code = "4171"
    fields = @{
      qfu_branchstate = "live"
      qfu_stalethresholdhours = 36
      qfu_budgetpacewarningpct = 85
      qfu_overduequotewarningcount = 10
      qfu_overduebackorderwarningcount = 120
      qfu_sortorder = 10
      qfu_managernote = "Southern Alberta pilot branch."
    }
  },
  @{
    code = "4172"
    fields = @{
      qfu_branchstate = "live"
      qfu_stalethresholdhours = 36
      qfu_budgetpacewarningpct = 85
      qfu_overduequotewarningcount = 10
      qfu_overduebackorderwarningcount = 120
      qfu_sortorder = 20
      qfu_managernote = "Southern Alberta pilot branch."
    }
  },
  @{
    code = "4173"
    fields = @{
      qfu_branchstate = "live"
      qfu_stalethresholdhours = 36
      qfu_budgetpacewarningpct = 85
      qfu_overduequotewarningcount = 10
      qfu_overduebackorderwarningcount = 120
      qfu_sortorder = 30
      qfu_managernote = "Southern Alberta pilot branch."
    }
  }
)

foreach ($branch in $branchSeed) {
  Upsert-ConfigRecord `
    -Connection $connection `
    -EntityLogicalName "qfu_branch" `
    -PrimaryIdAttribute "qfu_branchid" `
    -FilterAttribute "qfu_branchcode" `
    -FilterValue $branch.code `
    -Fields $branch.fields
}

Write-Host "Regional config spine ensured."
