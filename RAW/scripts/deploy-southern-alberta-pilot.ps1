param(
  [string]$TargetEnvironmentUrl = "https://regionaloperationshub.crm.dynamics.com",
  [string]$Username = "smcfarlane@applied.com",
  [string]$SolutionUniqueName = "Default",
  [string]$ParsedWorkbookJson = "results\\southern-alberta-workbooks.json",
  [string]$ParsedWorkbookScript = "scripts\\parse-southern-alberta-workbooks.py",
  [string]$OutputJson = "results\\southern-alberta-deploy-summary.json",
  [int]$GraceDays = 3
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

function Ensure-Directory {
  param([string]$Path)
  if (-not (Test-Path $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Write-Utf8Json {
  param(
    [string]$Path,
    [object]$Object
  )

  $parent = Split-Path -Parent $Path
  if ($parent) {
    Ensure-Directory $parent
  }

  $json = $Object | ConvertTo-Json -Depth 10
  [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
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

function Ensure-IntegerAttribute {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$EntityLogicalName,
    [string]$SchemaName,
    [string]$DisplayName,
    [int]$MinValue = -2147483648,
    [int]$MaxValue = 2147483647,
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

function Ensure-DecimalAttribute {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$EntityLogicalName,
    [string]$SchemaName,
    [string]$DisplayName,
    [int]$Precision = 2,
    [decimal]$MinValue = 0,
    [decimal]$MaxValue = 1000000000,
    [string]$Description = ""
  )

  if (Test-AttributeExists -Connection $Connection -EntityLogicalName $EntityLogicalName -AttributeLogicalName $SchemaName) {
    Write-Host "Attribute exists: $EntityLogicalName.$SchemaName"
    return
  }

  $attribute = [Microsoft.Xrm.Sdk.Metadata.DecimalAttributeMetadata]::new()
  $attribute.SchemaName = $SchemaName
  $attribute.DisplayName = New-Label $DisplayName
  $attribute.Description = New-Label $Description
  $attribute.RequiredLevel = New-RequiredLevel ([Microsoft.Xrm.Sdk.Metadata.AttributeRequiredLevel]::None)
  $attribute.Precision = $Precision
  $attribute.MinValue = $MinValue
  $attribute.MaxValue = $MaxValue

  $request = [Microsoft.Xrm.Sdk.Messages.CreateAttributeRequest]::new()
  $request.EntityName = $EntityLogicalName
  $request.Attribute = $attribute
  if ($SolutionUniqueName) {
    $request.SolutionUniqueName = $SolutionUniqueName
  }
  Invoke-MetadataCreateRequest -Connection $Connection -Request $request -AlreadyExistsLabel "Attribute exists after retry: $EntityLogicalName.$SchemaName"

  Write-Host "Created decimal attribute: $EntityLogicalName.$SchemaName"
}

function Ensure-DecimalAttributeRange {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$EntityLogicalName,
    [string]$SchemaName,
    [int]$Precision = 2,
    [decimal]$MinValue = 0,
    [decimal]$MaxValue = 1000000000
  )

  if (-not (Test-AttributeExists -Connection $Connection -EntityLogicalName $EntityLogicalName -AttributeLogicalName $SchemaName)) {
    return
  }

  $request = [Microsoft.Xrm.Sdk.Messages.RetrieveAttributeRequest]::new()
  $request.EntityLogicalName = $EntityLogicalName
  $request.LogicalName = $SchemaName
  $request.RetrieveAsIfPublished = $true
  $response = $Connection.Execute($request)
  $attribute = [Microsoft.Xrm.Sdk.Metadata.DecimalAttributeMetadata]$response.AttributeMetadata
  if ($null -eq $attribute) {
    return
  }

  $needsUpdate = ($attribute.MinValue -ne $MinValue) -or ($attribute.MaxValue -ne $MaxValue) -or ($attribute.Precision -ne $Precision)
  if (-not $needsUpdate) {
    return
  }

  $attribute.MinValue = $MinValue
  $attribute.MaxValue = $MaxValue
  $attribute.Precision = $Precision

  $update = [Microsoft.Xrm.Sdk.Messages.UpdateAttributeRequest]::new()
  $update.EntityName = $EntityLogicalName
  $update.Attribute = $attribute
  if ($SolutionUniqueName) {
    $update.SolutionUniqueName = $SolutionUniqueName
  }

  $Connection.Execute($update) | Out-Null
  Write-Host "Updated decimal range: $EntityLogicalName.$SchemaName"
}

function Ensure-DateTimeAttribute {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$EntityLogicalName,
    [string]$SchemaName,
    [string]$DisplayName,
    [Microsoft.Xrm.Sdk.Metadata.DateTimeFormat]$Format = [Microsoft.Xrm.Sdk.Metadata.DateTimeFormat]::DateAndTime,
    [string]$Description = ""
  )

  if (Test-AttributeExists -Connection $Connection -EntityLogicalName $EntityLogicalName -AttributeLogicalName $SchemaName) {
    Write-Host "Attribute exists: $EntityLogicalName.$SchemaName"
    return
  }

  $attribute = [Microsoft.Xrm.Sdk.Metadata.DateTimeAttributeMetadata]::new()
  $attribute.SchemaName = $SchemaName
  $attribute.DisplayName = New-Label $DisplayName
  $attribute.Description = New-Label $Description
  $attribute.RequiredLevel = New-RequiredLevel ([Microsoft.Xrm.Sdk.Metadata.AttributeRequiredLevel]::None)
  $attribute.Format = $Format

  $request = [Microsoft.Xrm.Sdk.Messages.CreateAttributeRequest]::new()
  $request.EntityName = $EntityLogicalName
  $request.Attribute = $attribute
  if ($SolutionUniqueName) {
    $request.SolutionUniqueName = $SolutionUniqueName
  }
  Invoke-MetadataCreateRequest -Connection $Connection -Request $request -AlreadyExistsLabel "Attribute exists after retry: $EntityLogicalName.$SchemaName"

  Write-Host "Created datetime attribute: $EntityLogicalName.$SchemaName"
}

function Ensure-BooleanAttribute {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$EntityLogicalName,
    [string]$SchemaName,
    [string]$DisplayName,
    [string]$Description = ""
  )

  if (Test-AttributeExists -Connection $Connection -EntityLogicalName $EntityLogicalName -AttributeLogicalName $SchemaName) {
    Write-Host "Attribute exists: $EntityLogicalName.$SchemaName"
    return
  }

  $attribute = [Microsoft.Xrm.Sdk.Metadata.BooleanAttributeMetadata]::new()
  $attribute.SchemaName = $SchemaName
  $attribute.DisplayName = New-Label $DisplayName
  $attribute.Description = New-Label $Description
  $attribute.RequiredLevel = New-RequiredLevel ([Microsoft.Xrm.Sdk.Metadata.AttributeRequiredLevel]::None)
  $attribute.OptionSet = [Microsoft.Xrm.Sdk.Metadata.BooleanOptionSetMetadata]::new(
    [Microsoft.Xrm.Sdk.Metadata.OptionMetadata]::new((New-Label "Yes"), 1),
    [Microsoft.Xrm.Sdk.Metadata.OptionMetadata]::new((New-Label "No"), 0)
  )

  $request = [Microsoft.Xrm.Sdk.Messages.CreateAttributeRequest]::new()
  $request.EntityName = $EntityLogicalName
  $request.Attribute = $attribute
  if ($SolutionUniqueName) {
    $request.SolutionUniqueName = $SolutionUniqueName
  }
  Invoke-MetadataCreateRequest -Connection $Connection -Request $request -AlreadyExistsLabel "Attribute exists after retry: $EntityLogicalName.$SchemaName"

  Write-Host "Created boolean attribute: $EntityLogicalName.$SchemaName"
}

function Ensure-MinimalSchema {
  param([Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection)

  Ensure-Entity -Connection $Connection -SchemaName "qfu_quote" -DisplayName "QFU Quote" -DisplayCollectionName "QFU Quotes" -Description "Southern Alberta quote workbench records." -PrimaryNameSchema "qfu_name" -PrimaryNameDisplay "Name"
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quote" -SchemaName "qfu_sourceid" -DisplayName "Source Id" -MaxLength 200
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quote" -SchemaName "qfu_quotenumber" -DisplayName "Quote Number" -MaxLength 50
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quote" -SchemaName "qfu_customername" -DisplayName "Customer Name" -MaxLength 200
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_quote" -SchemaName "qfu_amount" -DisplayName "Amount" -Precision 2 -MinValue 0
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quote" -SchemaName "qfu_assignedto" -DisplayName "Assigned To" -MaxLength 150
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quote" -SchemaName "qfu_cssr" -DisplayName "CSSR" -MaxLength 50
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quote" -SchemaName "qfu_cssrname" -DisplayName "CSSR Name" -MaxLength 150
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quote" -SchemaName "qfu_tsr" -DisplayName "TSR" -MaxLength 50
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_quote" -SchemaName "qfu_nextfollowup" -DisplayName "Next Follow Up"
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_quote" -SchemaName "qfu_overduesince" -DisplayName "Overdue Since"
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_quote" -SchemaName "qfu_lasttouchedon" -DisplayName "Last Touched On"
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_quote" -SchemaName "qfu_lastfollowupupdatedon" -DisplayName "Last Follow Up Updated On"
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_quote" -SchemaName "qfu_closedon" -DisplayName "Closed On"
  Ensure-IntegerAttribute -Connection $Connection -EntityLogicalName "qfu_quote" -SchemaName "qfu_priorityscore" -DisplayName "Priority Score"
  Ensure-IntegerAttribute -Connection $Connection -EntityLogicalName "qfu_quote" -SchemaName "qfu_actionstate" -DisplayName "Action State"
  Ensure-IntegerAttribute -Connection $Connection -EntityLogicalName "qfu_quote" -SchemaName "qfu_status" -DisplayName "Status"
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_quote" -SchemaName "qfu_sourcedate" -DisplayName "Source Date" -Format ([Microsoft.Xrm.Sdk.Metadata.DateTimeFormat]::DateOnly)
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_quote" -SchemaName "qfu_sourceupdatedon" -DisplayName "Source Updated On"
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quote" -SchemaName "qfu_branchcode" -DisplayName "Branch Code" -MaxLength 10
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quote" -SchemaName "qfu_branchslug" -DisplayName "Branch Slug" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quote" -SchemaName "qfu_regionslug" -DisplayName "Region Slug" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quote" -SchemaName "qfu_sourcefamily" -DisplayName "Source Family" -MaxLength 50
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quote" -SchemaName "qfu_importbatchid" -DisplayName "Import Batch Id" -MaxLength 200
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quote" -SchemaName "qfu_sourcefile" -DisplayName "Source File" -MaxLength 250
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quote" -SchemaName "qfu_sourceworksheet" -DisplayName "Source Worksheet" -MaxLength 50
  Ensure-IntegerAttribute -Connection $Connection -EntityLogicalName "qfu_quote" -SchemaName "qfu_source_row_count" -DisplayName "Source Row Count" -MinValue 0
  Ensure-BooleanAttribute -Connection $Connection -EntityLogicalName "qfu_quote" -SchemaName "qfu_active" -DisplayName "Active"
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_quote" -SchemaName "qfu_inactiveon" -DisplayName "Inactive On"
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_quote" -SchemaName "qfu_lastseenon" -DisplayName "Last Seen On"

  Ensure-Entity -Connection $Connection -SchemaName "qfu_backorder" -DisplayName "QFU Backorder" -DisplayCollectionName "QFU Backorders" -Description "Southern Alberta overdue backorder rows." -PrimaryNameSchema "qfu_name" -PrimaryNameDisplay "Name"
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_sourceid" -DisplayName "Source Id" -MaxLength 200
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_customername" -DisplayName "Customer Name" -MaxLength 200
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_totalvalue" -DisplayName "Total Value" -Precision 2 -MinValue 0
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_ontimedate" -DisplayName "On Time Date" -Format ([Microsoft.Xrm.Sdk.Metadata.DateTimeFormat]::DateOnly)
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_cssrname" -DisplayName "CSSR Name" -MaxLength 150
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_customerpo" -DisplayName "Customer PO" -MaxLength 100
  Ensure-IntegerAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_daysoverdue" -DisplayName "Days Overdue"
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_salesdocnumber" -DisplayName "Sales Document Number" -MaxLength 50
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_salesdoctype" -DisplayName "Sales Document Type" -MaxLength 50
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_material" -DisplayName "Material" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_materialgroup" -DisplayName "Material Group" -MaxLength 100
  Ensure-MemoAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_description" -DisplayName "Description" -MaxLength 2000
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_quantity" -DisplayName "Quantity" -Precision 2 -MinValue 0
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_qtybilled" -DisplayName "Qty Billed" -Precision 2 -MinValue 0
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_qtyondelnotpgid" -DisplayName "Qty On Delivery Not PGI" -Precision 2 -MinValue 0
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_qtynotondel" -DisplayName "Qty Not On Delivery" -Precision 2 -MinValue 0
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_netprice" -DisplayName "Net Price" -Precision 2 -MinValue 0
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_uom" -DisplayName "UOM" -MaxLength 20
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_accountmanager" -DisplayName "Account Manager" -MaxLength 50
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_accountmanagername" -DisplayName "Account Manager Name" -MaxLength 150
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_soldto" -DisplayName "Sold To" -MaxLength 50
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_shipto" -DisplayName "Ship To" -MaxLength 50
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_shiptoname" -DisplayName "Ship To Name" -MaxLength 200
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_shipconddesc" -DisplayName "Ship Condition" -MaxLength 100
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_lineitemcreatedon" -DisplayName "Line Item Created On" -Format ([Microsoft.Xrm.Sdk.Metadata.DateTimeFormat]::DateOnly)
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_firstdate" -DisplayName "First Date" -Format ([Microsoft.Xrm.Sdk.Metadata.DateTimeFormat]::DateOnly)
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_delblockdesc" -DisplayName "Delivery Block" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_billblockdesc" -DisplayName "Billing Block" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_itemcategory" -DisplayName "Item Category" -MaxLength 50
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_vendorpo" -DisplayName "Vendor PO" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_createdby" -DisplayName "Created By" -MaxLength 150
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_plant" -DisplayName "Plant" -MaxLength 50
  Ensure-MemoAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_userstatusdescription" -DisplayName "User Status Description" -MaxLength 500
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_reasonforrejection" -DisplayName "Reason For Rejection" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_branchcode" -DisplayName "Branch Code" -MaxLength 10
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_branchslug" -DisplayName "Branch Slug" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_regionslug" -DisplayName "Region Slug" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_sourcefamily" -DisplayName "Source Family" -MaxLength 50
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_importbatchid" -DisplayName "Import Batch Id" -MaxLength 200
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_sourcefile" -DisplayName "Source File" -MaxLength 250
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_sourceline" -DisplayName "Source Line" -MaxLength 50
  Ensure-BooleanAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_active" -DisplayName "Active"
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_inactiveon" -DisplayName "Inactive On"
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_backorder" -SchemaName "qfu_lastseenon" -DisplayName "Last Seen On"

  Ensure-Entity -Connection $Connection -SchemaName "qfu_deliverynotpgi" -DisplayName "QFU Delivery Not PGI" -DisplayCollectionName "QFU Delivery Not PGIs" -Description "Branch-scoped ready to ship but not PGI'd delivery-line rows." -PrimaryNameSchema "qfu_name" -PrimaryNameDisplay "Name"
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_deliverynotpgi" -SchemaName "qfu_sourceid" -DisplayName "Source Id" -MaxLength 200
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_deliverynotpgi" -SchemaName "qfu_deliverynumber" -DisplayName "Delivery Number" -MaxLength 50
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_deliverynotpgi" -SchemaName "qfu_deliveryline" -DisplayName "Delivery Line" -MaxLength 50
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_deliverynotpgi" -SchemaName "qfu_ontimedate" -DisplayName "On Time Date" -Format ([Microsoft.Xrm.Sdk.Metadata.DateTimeFormat]::DateOnly)
  Ensure-IntegerAttribute -Connection $Connection -EntityLogicalName "qfu_deliverynotpgi" -SchemaName "qfu_dayslate" -DisplayName "Days Late" -MinValue 0
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_deliverynotpgi" -SchemaName "qfu_shiptocustomername" -DisplayName "Ship To Customer Name" -MaxLength 200
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_deliverynotpgi" -SchemaName "qfu_soldtocustomername" -DisplayName "Sold To Customer Name" -MaxLength 200
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_deliverynotpgi" -SchemaName "qfu_material" -DisplayName "Material" -MaxLength 100
  Ensure-MemoAttribute -Connection $Connection -EntityLogicalName "qfu_deliverynotpgi" -SchemaName "qfu_description" -DisplayName "Description" -MaxLength 2000
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_deliverynotpgi" -SchemaName "qfu_qtyondelnotpgid" -DisplayName "Qty On Delivery Not PGI'd" -Precision 2 -MinValue 0
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_deliverynotpgi" -SchemaName "qfu_unshippednetvalue" -DisplayName "Unshipped Net Value" -Precision 2 -MinValue 0
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_deliverynotpgi" -SchemaName "qfu_cssrname" -DisplayName "CSSR Name" -MaxLength 150
  Ensure-MemoAttribute -Connection $Connection -EntityLogicalName "qfu_deliverynotpgi" -SchemaName "qfu_comment" -DisplayName "Comment" -MaxLength 4000
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_deliverynotpgi" -SchemaName "qfu_commentupdatedon" -DisplayName "Comment Updated On"
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_deliverynotpgi" -SchemaName "qfu_commentupdatedbyname" -DisplayName "Comment Updated By Name" -MaxLength 150
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_deliverynotpgi" -SchemaName "qfu_snapshotcapturedon" -DisplayName "Snapshot Captured On"
  Ensure-BooleanAttribute -Connection $Connection -EntityLogicalName "qfu_deliverynotpgi" -SchemaName "qfu_active" -DisplayName "Active"
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_deliverynotpgi" -SchemaName "qfu_inactiveon" -DisplayName "Inactive On"
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_deliverynotpgi" -SchemaName "qfu_branchcode" -DisplayName "Branch Code" -MaxLength 10
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_deliverynotpgi" -SchemaName "qfu_branchslug" -DisplayName "Branch Slug" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_deliverynotpgi" -SchemaName "qfu_regionslug" -DisplayName "Region Slug" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_deliverynotpgi" -SchemaName "qfu_sourcefamily" -DisplayName "Source Family" -MaxLength 50
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_deliverynotpgi" -SchemaName "qfu_importbatchid" -DisplayName "Import Batch Id" -MaxLength 200
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_deliverynotpgi" -SchemaName "qfu_sourcefile" -DisplayName "Source File" -MaxLength 250

  Ensure-Entity -Connection $Connection -SchemaName "qfu_budget" -DisplayName "QFU Budget" -DisplayCollectionName "QFU Budgets" -Description "Southern Alberta budget pacing rows." -PrimaryNameSchema "qfu_name" -PrimaryNameDisplay "Name"
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_budget" -SchemaName "qfu_sourceid" -DisplayName "Source Id" -MaxLength 200
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_budget" -SchemaName "qfu_budgetname" -DisplayName "Budget Name" -MaxLength 200
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_budget" -SchemaName "qfu_actualsales" -DisplayName "Actual Sales" -Precision 2 -MinValue 0
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_budget" -SchemaName "qfu_budgetamount" -DisplayName "Budget Amount" -Precision 2 -MinValue 0
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_budget" -SchemaName "qfu_budgetgoal" -DisplayName "Budget Goal" -Precision 2 -MinValue 0
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_budget" -SchemaName "qfu_percentachieved" -DisplayName "Percent Achieved" -Precision 2 -MinValue 0 -MaxValue 1000
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_budget" -SchemaName "qfu_lastupdated" -DisplayName "Last Updated"
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_budget" -SchemaName "qfu_cadsales" -DisplayName "CAD Sales" -Precision 2 -MinValue 0
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_budget" -SchemaName "qfu_usdsales" -DisplayName "USD Sales" -Precision 2 -MinValue 0
  Ensure-BooleanAttribute -Connection $Connection -EntityLogicalName "qfu_budget" -SchemaName "qfu_isactive" -DisplayName "Is Active"
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_budget" -SchemaName "qfu_fiscalyear" -DisplayName "Fiscal Year" -MaxLength 20
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_budget" -SchemaName "qfu_customername" -DisplayName "Customer Name" -MaxLength 200
  Ensure-IntegerAttribute -Connection $Connection -EntityLogicalName "qfu_budget" -SchemaName "qfu_month" -DisplayName "Month" -MinValue 1 -MaxValue 12
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_budget" -SchemaName "qfu_monthname" -DisplayName "Month Name" -MaxLength 50
  Ensure-IntegerAttribute -Connection $Connection -EntityLogicalName "qfu_budget" -SchemaName "qfu_year" -DisplayName "Year" -MinValue 2000 -MaxValue 2100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_budget" -SchemaName "qfu_sourcefile" -DisplayName "Source File" -MaxLength 250
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_budget" -SchemaName "qfu_branchcode" -DisplayName "Branch Code" -MaxLength 10
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_budget" -SchemaName "qfu_branchslug" -DisplayName "Branch Slug" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_budget" -SchemaName "qfu_regionslug" -DisplayName "Region Slug" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_budget" -SchemaName "qfu_sourcefamily" -DisplayName "Source Family" -MaxLength 50
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_budget" -SchemaName "qfu_importbatchid" -DisplayName "Import Batch Id" -MaxLength 200
  Ensure-MemoAttribute -Connection $Connection -EntityLogicalName "qfu_budget" -SchemaName "qfu_opsdailycadjson" -DisplayName "Ops Daily CAD Json" -MaxLength 1048576 -Description "Latest SA1300 CAD Daily Sales- Location rows serialized for analytics."
  Ensure-MemoAttribute -Connection $Connection -EntityLogicalName "qfu_budget" -SchemaName "qfu_opsdailyusdjson" -DisplayName "Ops Daily USD Json" -MaxLength 1048576 -Description "Latest SA1300 USD Daily Sales- Location rows serialized for analytics."

  Ensure-Entity -Connection $Connection -SchemaName "qfu_budgetarchive" -DisplayName "QFU Budget Archive" -DisplayCollectionName "QFU Budget Archives" -Description "Branch-scoped monthly budget target rows used by Southern Alberta pilot flows." -PrimaryNameSchema "qfu_name" -PrimaryNameDisplay "Name"
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_budgetarchive" -SchemaName "qfu_sourceid" -DisplayName "Source Id" -MaxLength 200
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_budgetarchive" -SchemaName "qfu_budgetgoal" -DisplayName "Budget Goal" -Precision 2 -MinValue 0
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_budgetarchive" -SchemaName "qfu_actualsales" -DisplayName "Actual Sales" -Precision 2 -MinValue 0
  Ensure-IntegerAttribute -Connection $Connection -EntityLogicalName "qfu_budgetarchive" -SchemaName "qfu_month" -DisplayName "Month" -MinValue 1 -MaxValue 12
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_budgetarchive" -SchemaName "qfu_monthname" -DisplayName "Month Name" -MaxLength 50
  Ensure-IntegerAttribute -Connection $Connection -EntityLogicalName "qfu_budgetarchive" -SchemaName "qfu_year" -DisplayName "Year" -MinValue 2000 -MaxValue 2100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_budgetarchive" -SchemaName "qfu_fiscalyear" -DisplayName "Fiscal Year" -MaxLength 20
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_budgetarchive" -SchemaName "qfu_lastupdated" -DisplayName "Last Updated"
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_budgetarchive" -SchemaName "qfu_sourcefile" -DisplayName "Source File" -MaxLength 250
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_budgetarchive" -SchemaName "qfu_branchcode" -DisplayName "Branch Code" -MaxLength 10
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_budgetarchive" -SchemaName "qfu_branchslug" -DisplayName "Branch Slug" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_budgetarchive" -SchemaName "qfu_regionslug" -DisplayName "Region Slug" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_budgetarchive" -SchemaName "qfu_sourcefamily" -DisplayName "Source Family" -MaxLength 50

  Ensure-Entity -Connection $Connection -SchemaName "qfu_quoteline" -DisplayName "QFU Quote Line" -DisplayCollectionName "QFU Quote Lines" -Description "Minimal branch-scoped quote-line rows for pilot dedupe and aggregation." -PrimaryNameSchema "qfu_name" -PrimaryNameDisplay "Name"
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_sourceid" -DisplayName "Source Id" -MaxLength 200
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_uniquekey" -DisplayName "Unique Key" -MaxLength 200
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_quotenumber" -DisplayName "Quote Number" -MaxLength 50
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_linenumber" -DisplayName "Line Number" -MaxLength 50
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_soldtopartyname" -DisplayName "Sold To Party Name" -MaxLength 200
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_soldtopartycode" -DisplayName "Sold To Party Code" -MaxLength 50
  Ensure-MemoAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_additionalinfo" -DisplayName "Additional Info" -MaxLength 2000
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_amount" -DisplayName "Amount" -Precision 2 -MinValue 0
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_cssr" -DisplayName "CSSR" -MaxLength 50
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_cssrname" -DisplayName "CSSR Name" -MaxLength 150
  Ensure-MemoAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_description" -DisplayName "Description" -MaxLength 2000
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_dollarconnected" -DisplayName "Dollar Connected" -Precision 2 -MinValue 0
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_followupowner" -DisplayName "Follow Up Owner" -MaxLength 150
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_gppercent" -DisplayName "GP Percent" -Precision 4 -MinValue -1000 -MaxValue 1000
  Ensure-DecimalAttributeRange -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_gppercent" -Precision 4 -MinValue -1000 -MaxValue 1000
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_itemnumber" -DisplayName "Item Number" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_tsrname" -DisplayName "TSR Name" -MaxLength 150
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_tsr" -DisplayName "TSR" -MaxLength 50
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_linetotal" -DisplayName "Line Total" -Precision 2 -MinValue 0
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_location" -DisplayName "Location" -MaxLength 20
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_manufacturerpart" -DisplayName "Manufacturer Part" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_materialgroup" -DisplayName "Material Group" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_productcode" -DisplayName "Product Code" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_productname" -DisplayName "Product Name" -MaxLength 200
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_quantity" -DisplayName "Quantity" -Precision 2 -MinValue 0
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_rejectionreason" -DisplayName "Rejection Reason" -MaxLength 200
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_unitprice" -DisplayName "Unit Price" -Precision 2 -MinValue 0
  Ensure-IntegerAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_status" -DisplayName "Status"
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_lastimportdate" -DisplayName "Last Import Date"
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_sourcedate" -DisplayName "Source Date" -Format ([Microsoft.Xrm.Sdk.Metadata.DateTimeFormat]::DateOnly)
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_branchcode" -DisplayName "Branch Code" -MaxLength 10
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_branchslug" -DisplayName "Branch Slug" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_regionslug" -DisplayName "Region Slug" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_sourcefamily" -DisplayName "Source Family" -MaxLength 50
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_importbatchid" -DisplayName "Import Batch Id" -MaxLength 200
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_sourcefile" -DisplayName "Source File" -MaxLength 250
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_quoteline" -SchemaName "qfu_sourceworksheet" -DisplayName "Source Worksheet" -MaxLength 50

  Ensure-Entity -Connection $Connection -SchemaName "qfu_branch" -DisplayName "QFU Branch" -DisplayCollectionName "QFU Branches" -Description "Southern Alberta branch configuration." -PrimaryNameSchema "qfu_name" -PrimaryNameDisplay "Name"
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_branch" -SchemaName "qfu_sourceid" -DisplayName "Source Id" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_branch" -SchemaName "qfu_branchcode" -DisplayName "Branch Code" -MaxLength 10
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_branch" -SchemaName "qfu_branchname" -DisplayName "Branch Name" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_branch" -SchemaName "qfu_branchslug" -DisplayName "Branch Slug" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_branch" -SchemaName "qfu_regionslug" -DisplayName "Region Slug" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_branch" -SchemaName "qfu_regionname" -DisplayName "Region Name" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_branch" -SchemaName "qfu_mailboxaddress" -DisplayName "Mailbox Address" -MaxLength 200
  Ensure-IntegerAttribute -Connection $Connection -EntityLogicalName "qfu_branch" -SchemaName "qfu_sortorder" -DisplayName "Sort Order" -MinValue 0
  Ensure-BooleanAttribute -Connection $Connection -EntityLogicalName "qfu_branch" -SchemaName "qfu_active" -DisplayName "Active"

  Ensure-Entity -Connection $Connection -SchemaName "qfu_sourcefeed" -DisplayName "QFU Source Feed" -DisplayCollectionName "QFU Source Feeds" -Description "Mailbox to source-family registration." -PrimaryNameSchema "qfu_name" -PrimaryNameDisplay "Name"
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_sourcefeed" -SchemaName "qfu_sourceid" -DisplayName "Source Id" -MaxLength 150
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_sourcefeed" -SchemaName "qfu_branchcode" -DisplayName "Branch Code" -MaxLength 10
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_sourcefeed" -SchemaName "qfu_branchslug" -DisplayName "Branch Slug" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_sourcefeed" -SchemaName "qfu_regionslug" -DisplayName "Region Slug" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_sourcefeed" -SchemaName "qfu_sourcefamily" -DisplayName "Source Family" -MaxLength 50
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_sourcefeed" -SchemaName "qfu_mailboxaddress" -DisplayName "Mailbox Address" -MaxLength 200
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_sourcefeed" -SchemaName "qfu_folderid" -DisplayName "Folder Id" -MaxLength 250
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_sourcefeed" -SchemaName "qfu_subjectfilter" -DisplayName "Subject Filter" -MaxLength 200
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_sourcefeed" -SchemaName "qfu_filenamepattern" -DisplayName "Filename Pattern" -MaxLength 200
  Ensure-BooleanAttribute -Connection $Connection -EntityLogicalName "qfu_sourcefeed" -SchemaName "qfu_enabled" -DisplayName "Enabled"

  Ensure-Entity -Connection $Connection -SchemaName "qfu_ingestionbatch" -DisplayName "QFU Ingestion Batch" -DisplayCollectionName "QFU Ingestion Batches" -Description "Source ingestion audit rows." -PrimaryNameSchema "qfu_name" -PrimaryNameDisplay "Name"
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_ingestionbatch" -SchemaName "qfu_sourceid" -DisplayName "Source Id" -MaxLength 200
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_ingestionbatch" -SchemaName "qfu_branchcode" -DisplayName "Branch Code" -MaxLength 10
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_ingestionbatch" -SchemaName "qfu_branchslug" -DisplayName "Branch Slug" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_ingestionbatch" -SchemaName "qfu_regionslug" -DisplayName "Region Slug" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_ingestionbatch" -SchemaName "qfu_sourcefamily" -DisplayName "Source Family" -MaxLength 50
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_ingestionbatch" -SchemaName "qfu_sourcefilename" -DisplayName "Source File Name" -MaxLength 250
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_ingestionbatch" -SchemaName "qfu_status" -DisplayName "Status" -MaxLength 50
  Ensure-IntegerAttribute -Connection $Connection -EntityLogicalName "qfu_ingestionbatch" -SchemaName "qfu_insertedcount" -DisplayName "Inserted Count" -MinValue 0
  Ensure-IntegerAttribute -Connection $Connection -EntityLogicalName "qfu_ingestionbatch" -SchemaName "qfu_updatedcount" -DisplayName "Updated Count" -MinValue 0
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_ingestionbatch" -SchemaName "qfu_startedon" -DisplayName "Started On"
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_ingestionbatch" -SchemaName "qfu_completedon" -DisplayName "Completed On"
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_ingestionbatch" -SchemaName "qfu_triggerflow" -DisplayName "Trigger Flow" -MaxLength 200
  Ensure-MemoAttribute -Connection $Connection -EntityLogicalName "qfu_ingestionbatch" -SchemaName "qfu_notes" -DisplayName "Notes" -MaxLength 4000

  Ensure-Entity -Connection $Connection -SchemaName "qfu_rawdocument" -DisplayName "QFU Raw Document" -DisplayCollectionName "QFU Raw Documents" -Description "Queued raw source documents awaiting controlled processing." -PrimaryNameSchema "qfu_name" -PrimaryNameDisplay "Name"
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_rawdocument" -SchemaName "qfu_sourceid" -DisplayName "Source Id" -MaxLength 200
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_rawdocument" -SchemaName "qfu_branchcode" -DisplayName "Branch Code" -MaxLength 10
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_rawdocument" -SchemaName "qfu_branchslug" -DisplayName "Branch Slug" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_rawdocument" -SchemaName "qfu_regionslug" -DisplayName "Region Slug" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_rawdocument" -SchemaName "qfu_sourcefamily" -DisplayName "Source Family" -MaxLength 50
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_rawdocument" -SchemaName "qfu_sourcefile" -DisplayName "Source File" -MaxLength 250
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_rawdocument" -SchemaName "qfu_status" -DisplayName "Status" -MaxLength 50
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_rawdocument" -SchemaName "qfu_contenthash" -DisplayName "Content Hash" -MaxLength 128
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_rawdocument" -SchemaName "qfu_monthlabel" -DisplayName "Month Label" -MaxLength 50
  Ensure-IntegerAttribute -Connection $Connection -EntityLogicalName "qfu_rawdocument" -SchemaName "qfu_month" -DisplayName "Month" -MinValue 1 -MaxValue 12
  Ensure-IntegerAttribute -Connection $Connection -EntityLogicalName "qfu_rawdocument" -SchemaName "qfu_year" -DisplayName "Year" -MinValue 2000 -MaxValue 2100
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_rawdocument" -SchemaName "qfu_receivedon" -DisplayName "Received On"
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_rawdocument" -SchemaName "qfu_processedon" -DisplayName "Processed On"
  Ensure-MemoAttribute -Connection $Connection -EntityLogicalName "qfu_rawdocument" -SchemaName "qfu_rawcontentbase64" -DisplayName "Raw Content Base64" -MaxLength 1048576
  Ensure-MemoAttribute -Connection $Connection -EntityLogicalName "qfu_rawdocument" -SchemaName "qfu_processingnotes" -DisplayName "Processing Notes" -MaxLength 4000

  Ensure-Entity -Connection $Connection -SchemaName "qfu_branchdailysummary" -DisplayName "QFU Branch Daily Summary" -DisplayCollectionName "QFU Branch Daily Summaries" -Description "Branch summary metrics for the Southern Alberta shell." -PrimaryNameSchema "qfu_name" -PrimaryNameDisplay "Name"
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_branchdailysummary" -SchemaName "qfu_sourceid" -DisplayName "Source Id" -MaxLength 150
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_branchdailysummary" -SchemaName "qfu_branchcode" -DisplayName "Branch Code" -MaxLength 10
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_branchdailysummary" -SchemaName "qfu_branchslug" -DisplayName "Branch Slug" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_branchdailysummary" -SchemaName "qfu_regionslug" -DisplayName "Region Slug" -MaxLength 100
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_branchdailysummary" -SchemaName "qfu_summarydate" -DisplayName "Summary Date" -Format ([Microsoft.Xrm.Sdk.Metadata.DateTimeFormat]::DateOnly)
  Ensure-IntegerAttribute -Connection $Connection -EntityLogicalName "qfu_branchdailysummary" -SchemaName "qfu_openquotes" -DisplayName "Open Quotes" -MinValue 0
  Ensure-IntegerAttribute -Connection $Connection -EntityLogicalName "qfu_branchdailysummary" -SchemaName "qfu_overduequotes" -DisplayName "Overdue Quotes" -MinValue 0
  Ensure-IntegerAttribute -Connection $Connection -EntityLogicalName "qfu_branchdailysummary" -SchemaName "qfu_duetoday" -DisplayName "Due Today" -MinValue 0
  Ensure-IntegerAttribute -Connection $Connection -EntityLogicalName "qfu_branchdailysummary" -SchemaName "qfu_unscheduledold" -DisplayName "Unscheduled Old" -MinValue 0
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_branchdailysummary" -SchemaName "qfu_openquotevalue" -DisplayName "Open Quote Value"
  Ensure-IntegerAttribute -Connection $Connection -EntityLogicalName "qfu_branchdailysummary" -SchemaName "qfu_quoteslast30days" -DisplayName "Quotes Last 30 Days" -MinValue 0
  Ensure-IntegerAttribute -Connection $Connection -EntityLogicalName "qfu_branchdailysummary" -SchemaName "qfu_quoteswon30days" -DisplayName "Quotes Won 30 Days" -MinValue 0
  Ensure-IntegerAttribute -Connection $Connection -EntityLogicalName "qfu_branchdailysummary" -SchemaName "qfu_quoteslost30days" -DisplayName "Quotes Lost 30 Days" -MinValue 0
  Ensure-IntegerAttribute -Connection $Connection -EntityLogicalName "qfu_branchdailysummary" -SchemaName "qfu_quotesopen30days" -DisplayName "Quotes Open 30 Days" -MinValue 0
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_branchdailysummary" -SchemaName "qfu_avgquotevalue30days" -DisplayName "Average Quote Value 30 Days"
  Ensure-IntegerAttribute -Connection $Connection -EntityLogicalName "qfu_branchdailysummary" -SchemaName "qfu_backordercount" -DisplayName "Backorder Count" -MinValue 0
  Ensure-IntegerAttribute -Connection $Connection -EntityLogicalName "qfu_branchdailysummary" -SchemaName "qfu_overduebackordercount" -DisplayName "Overdue Backorder Count" -MinValue 0
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_branchdailysummary" -SchemaName "qfu_currentmonthforecastvalue" -DisplayName "Current Month Forecast Value"
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_branchdailysummary" -SchemaName "qfu_currentmonthlatevalue" -DisplayName "Current Month Late Value"
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_branchdailysummary" -SchemaName "qfu_allbackordersvalue" -DisplayName "All Backorders Value"
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_branchdailysummary" -SchemaName "qfu_overduebackordersvalue" -DisplayName "Overdue Backorders Value"
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_branchdailysummary" -SchemaName "qfu_budgetactual" -DisplayName "Budget Actual"
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_branchdailysummary" -SchemaName "qfu_budgettarget" -DisplayName "Budget Target"
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_branchdailysummary" -SchemaName "qfu_budgetpace" -DisplayName "Budget Pace" -Precision 2 -MinValue 0 -MaxValue 1000
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_branchdailysummary" -SchemaName "qfu_cadsales" -DisplayName "CAD Sales"
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_branchdailysummary" -SchemaName "qfu_usdsales" -DisplayName "USD Sales"
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_branchdailysummary" -SchemaName "qfu_lastcalculatedon" -DisplayName "Last Calculated On"

  Ensure-Entity -Connection $Connection -SchemaName "qfu_branchopsdaily" -DisplayName "QFU Branch Ops Daily" -DisplayCollectionName "QFU Branch Ops Dailies" -Description "SA1300 branch-level daily sales and on-time delivery rows for analytics." -PrimaryNameSchema "qfu_name" -PrimaryNameDisplay "Name"
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_branchopsdaily" -SchemaName "qfu_sourceid" -DisplayName "Source Id" -MaxLength 200
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_branchopsdaily" -SchemaName "qfu_branchcode" -DisplayName "Branch Code" -MaxLength 10
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_branchopsdaily" -SchemaName "qfu_branchslug" -DisplayName "Branch Slug" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_branchopsdaily" -SchemaName "qfu_regionslug" -DisplayName "Region Slug" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_branchopsdaily" -SchemaName "qfu_sourcefamily" -DisplayName "Source Family" -MaxLength 50
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_branchopsdaily" -SchemaName "qfu_sourcefile" -DisplayName "Source File" -MaxLength 250
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_branchopsdaily" -SchemaName "qfu_sourceworksheet" -DisplayName "Source Worksheet" -MaxLength 100
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_branchopsdaily" -SchemaName "qfu_snapshotdate" -DisplayName "Snapshot Date" -Format ([Microsoft.Xrm.Sdk.Metadata.DateTimeFormat]::DateOnly)
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_branchopsdaily" -SchemaName "qfu_billingday" -DisplayName "Billing Day" -Format ([Microsoft.Xrm.Sdk.Metadata.DateTimeFormat]::DateOnly)
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_branchopsdaily" -SchemaName "qfu_billinglabel" -DisplayName "Billing Label" -MaxLength 50
  Ensure-BooleanAttribute -Connection $Connection -EntityLogicalName "qfu_branchopsdaily" -SchemaName "qfu_istotalrow" -DisplayName "Is Total Row"
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_branchopsdaily" -SchemaName "qfu_currencytype" -DisplayName "Currency Type" -MaxLength 20
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_branchopsdaily" -SchemaName "qfu_sales" -DisplayName "Sales" -Precision 2
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_branchopsdaily" -SchemaName "qfu_gp" -DisplayName "GP" -Precision 2
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_branchopsdaily" -SchemaName "qfu_gppct" -DisplayName "GP Percent" -Precision 6 -MinValue -1000 -MaxValue 1000
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_branchopsdaily" -SchemaName "qfu_ontimedelivery" -DisplayName "On Time Delivery" -Precision 6 -MinValue -1000 -MaxValue 1000
  Ensure-IntegerAttribute -Connection $Connection -EntityLogicalName "qfu_branchopsdaily" -SchemaName "qfu_sortorder" -DisplayName "Sort Order" -MinValue 0
  foreach ($field in @("qfu_sales", "qfu_gp")) {
    Ensure-DecimalAttributeRange -Connection $Connection -EntityLogicalName "qfu_branchopsdaily" -SchemaName $field -Precision 2 -MinValue -1000000000 -MaxValue 1000000000
  }
  foreach ($field in @("qfu_gppct", "qfu_ontimedelivery")) {
    Ensure-DecimalAttributeRange -Connection $Connection -EntityLogicalName "qfu_branchopsdaily" -SchemaName $field -Precision 6 -MinValue -1000 -MaxValue 1000
  }

  Publish-Entities -Connection $Connection -LogicalNames @(
    "qfu_quote",
    "qfu_backorder",
    "qfu_budget",
    "qfu_budgetarchive",
    "qfu_quoteline",
    "qfu_branch",
    "qfu_sourcefeed",
    "qfu_ingestionbatch",
    "qfu_rawdocument",
    "qfu_branchdailysummary",
    "qfu_branchopsdaily"
  )
}

function Convert-OptionalDate {
  param($Value)
  if ($null -eq $Value -or [string]::IsNullOrWhiteSpace("$Value")) {
    return $null
  }
  return [datetime]$Value
}

function Convert-OptionalDecimal {
  param($Value)
  if ($null -eq $Value -or [string]::IsNullOrWhiteSpace("$Value")) {
    return $null
  }
  return [decimal]$Value
}

function Convert-OptionalInt {
  param($Value)
  if ($null -eq $Value -or [string]::IsNullOrWhiteSpace("$Value")) {
    return $null
  }
  try {
    return [int]$Value
  } catch {
    return $null
  }
}

function Convert-OptionalText {
  param($Value)
  if ($null -eq $Value) {
    return $null
  }
  $text = "$Value".Trim()
  if ($text -eq "") {
    return $null
  }
  return $text
}

function Get-SingleRecord {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$EntityLogicalName,
    [string]$FilterAttribute,
    [string]$FilterValue,
    [string[]]$Fields
  )

  return (Get-CrmRecords -conn $Connection -EntityLogicalName $EntityLogicalName -FilterAttribute $FilterAttribute -FilterOperator eq -FilterValue $FilterValue -Fields $Fields -TopCount 1).CrmRecords | Select-Object -First 1
}

function Upsert-RecordBySourceId {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$EntityLogicalName,
    [string]$SourceId,
    [hashtable]$Fields
  )

  $matches = @(
    (Get-CrmRecords -conn $Connection -EntityLogicalName $EntityLogicalName -FilterAttribute "qfu_sourceid" -FilterOperator eq -FilterValue $SourceId -Fields @("${EntityLogicalName}id", "qfu_sourceid") -TopCount 2).CrmRecords
  )
  if ($matches.Count -gt 1) {
    throw "Duplicate $EntityLogicalName rows already exist for qfu_sourceid '$SourceId'. Repair the duplicate group before running the seed sync again."
  }

  $existing = $matches | Select-Object -First 1
  if ($existing) {
    Update-CrmRecord -conn $Connection -EntityLogicalName $EntityLogicalName -Id $existing."${EntityLogicalName}id" -Fields $Fields | Out-Null
    return "updated"
  }

  $null = New-CrmRecord -conn $Connection -EntityLogicalName $EntityLogicalName -Fields $Fields
  return "created"
}

function Get-QuoteSourceRows {
  param([Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection)

  $fetch = @"
<fetch version='1.0' mapping='logical' count='5000'>
  <entity name='qfu_quote'>
    <attribute name='qfu_quoteid' />
    <attribute name='qfu_quotenumber' />
    <attribute name='qfu_customername' />
    <attribute name='qfu_amount' />
    <attribute name='qfu_assignedto' />
    <attribute name='qfu_cssrname' />
    <attribute name='qfu_nextfollowup' />
    <attribute name='qfu_overduesince' />
    <attribute name='qfu_lasttouchedon' />
    <attribute name='qfu_lastfollowupupdatedon' />
    <attribute name='qfu_priorityscore' />
    <attribute name='qfu_actionstate' />
    <attribute name='qfu_status' />
    <attribute name='createdon' />
    <attribute name='modifiedon' />
    <order attribute='qfu_priorityscore' descending='true' />
    <order attribute='qfu_quotenumber' descending='false' />
  </entity>
</fetch>
"@

  return @((Get-CrmRecordsByFetch -conn $Connection -Fetch $fetch).CrmRecords)
}

function Get-BackorderSourceRows {
  param([Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection)

  $fetch = @"
<fetch version='1.0' mapping='logical' count='5000'>
  <entity name='qfu_backorder'>
    <attribute name='qfu_backorderid' />
    <attribute name='qfu_name' />
    <attribute name='qfu_customername' />
    <attribute name='qfu_totalvalue' />
    <attribute name='qfu_ontimedate' />
    <attribute name='qfu_cssrname' />
    <attribute name='qfu_daysoverdue' />
    <attribute name='qfu_salesdocnumber' />
    <attribute name='qfu_material' />
    <attribute name='qfu_description' />
    <attribute name='qfu_quantity' />
    <order attribute='qfu_daysoverdue' descending='true' />
    <order attribute='qfu_ontimedate' descending='false' />
  </entity>
</fetch>
"@

  return @((Get-CrmRecordsByFetch -conn $Connection -Fetch $fetch).CrmRecords)
}

function Get-BudgetSourceRows {
  param([Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection)

  $fetch = @"
<fetch version='1.0' mapping='logical' count='500'>
  <entity name='qfu_budget'>
    <attribute name='qfu_budgetid' />
    <attribute name='qfu_budgetname' />
    <attribute name='qfu_actualsales' />
    <attribute name='qfu_budgetgoal' />
    <attribute name='qfu_percentachieved' />
    <attribute name='qfu_lastupdated' />
    <attribute name='qfu_cadsales' />
    <attribute name='qfu_usdsales' />
    <attribute name='qfu_month' />
    <attribute name='qfu_monthname' />
    <attribute name='qfu_year' />
    <attribute name='qfu_sourcefile' />
    <order attribute='qfu_year' descending='true' />
    <order attribute='qfu_month' descending='true' />
  </entity>
</fetch>
"@

  return @((Get-CrmRecordsByFetch -conn $Connection -Fetch $fetch).CrmRecords)
}

function Sync-Quotes {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$SourceConnection,
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$TargetConnection
  )

  $created = 0
  $updated = 0
  $rows = Get-QuoteSourceRows -Connection $SourceConnection

  foreach ($row in $rows) {
    $sourceId = "$($row.qfu_quoteid)"
    $quoteNumber = Convert-OptionalText $row.qfu_quotenumber
    $customer = Convert-OptionalText $row.qfu_customername
    $name = @($quoteNumber, $customer) -join " - "
    if ([string]::IsNullOrWhiteSpace($name.Trim('- '))) {
      $name = $sourceId
    }

    $result = Upsert-RecordBySourceId -Connection $TargetConnection -EntityLogicalName "qfu_quote" -SourceId $sourceId -Fields @{
      qfu_name = $name
      qfu_sourceid = $sourceId
      qfu_quotenumber = $quoteNumber
      qfu_customername = $customer
      qfu_amount = Convert-OptionalDecimal $row.qfu_amount
      qfu_assignedto = (Convert-OptionalText $row.qfu_assignedto)
      qfu_cssrname = (Convert-OptionalText $row.qfu_cssrname)
      qfu_nextfollowup = Convert-OptionalDate $row.qfu_nextfollowup
      qfu_overduesince = Convert-OptionalDate $row.qfu_overduesince
      qfu_lasttouchedon = Convert-OptionalDate $row.qfu_lasttouchedon
      qfu_lastfollowupupdatedon = Convert-OptionalDate $row.qfu_lastfollowupupdatedon
      qfu_priorityscore = Convert-OptionalInt $row.qfu_priorityscore
      qfu_actionstate = Convert-OptionalInt $row.qfu_actionstate
      qfu_status = Convert-OptionalInt $row.qfu_status
      qfu_sourcedate = Convert-OptionalDate $row.createdon
      qfu_sourceupdatedon = Convert-OptionalDate $row.modifiedon
    }

    if ($result -eq "created") {
      $created += 1
    } else {
      $updated += 1
    }
  }

  return [pscustomobject]@{
    count = $rows.Count
    created = $created
    updated = $updated
  }
}

function Sync-Backorders {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$SourceConnection,
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$TargetConnection
  )

  $created = 0
  $updated = 0
  $rows = Get-BackorderSourceRows -Connection $SourceConnection

  foreach ($row in $rows) {
    $sourceId = "$($row.qfu_backorderid)"
    $name = Convert-OptionalText $row.qfu_name
    if (-not $name) {
      $name = @((Convert-OptionalText $row.qfu_salesdocnumber), (Convert-OptionalText $row.qfu_material)) -join " - "
    }

    $result = Upsert-RecordBySourceId -Connection $TargetConnection -EntityLogicalName "qfu_backorder" -SourceId $sourceId -Fields @{
      qfu_name = $name
      qfu_sourceid = $sourceId
      qfu_customername = (Convert-OptionalText $row.qfu_customername)
      qfu_totalvalue = Convert-OptionalDecimal $row.qfu_totalvalue
      qfu_ontimedate = Convert-OptionalDate $row.qfu_ontimedate
      qfu_cssrname = (Convert-OptionalText $row.qfu_cssrname)
      qfu_daysoverdue = Convert-OptionalInt $row.qfu_daysoverdue
      qfu_salesdocnumber = (Convert-OptionalText $row.qfu_salesdocnumber)
      qfu_material = (Convert-OptionalText $row.qfu_material)
      qfu_description = (Convert-OptionalText $row.qfu_description)
      qfu_quantity = Convert-OptionalDecimal $row.qfu_quantity
    }

    if ($result -eq "created") {
      $created += 1
    } else {
      $updated += 1
    }
  }

  return [pscustomobject]@{
    count = $rows.Count
    created = $created
    updated = $updated
  }
}

function Sync-Budgets {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$SourceConnection,
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$TargetConnection
  )

  $created = 0
  $updated = 0
  $rows = Get-BudgetSourceRows -Connection $SourceConnection

  foreach ($row in $rows) {
    $sourceId = "$($row.qfu_budgetid)"
    $name = Convert-OptionalText $row.qfu_budgetname
    if (-not $name) {
      $name = @((Convert-OptionalText $row.qfu_monthname), (Convert-OptionalInt $row.qfu_year)) -join " "
    }

    $result = Upsert-RecordBySourceId -Connection $TargetConnection -EntityLogicalName "qfu_budget" -SourceId $sourceId -Fields @{
      qfu_name = $name
      qfu_sourceid = $sourceId
      qfu_budgetname = $name
      qfu_actualsales = Convert-OptionalDecimal $row.qfu_actualsales
      qfu_budgetgoal = Convert-OptionalDecimal $row.qfu_budgetgoal
      qfu_percentachieved = Convert-OptionalDecimal $row.qfu_percentachieved
      qfu_lastupdated = Convert-OptionalDate $row.qfu_lastupdated
      qfu_cadsales = Convert-OptionalDecimal $row.qfu_cadsales
      qfu_usdsales = Convert-OptionalDecimal $row.qfu_usdsales
      qfu_month = Convert-OptionalInt $row.qfu_month
      qfu_monthname = (Convert-OptionalText $row.qfu_monthname)
      qfu_year = Convert-OptionalInt $row.qfu_year
      qfu_sourcefile = (Convert-OptionalText $row.qfu_sourcefile)
    }

    if ($result -eq "created") {
      $created += 1
    } else {
      $updated += 1
    }
  }

  return [pscustomobject]@{
    count = $rows.Count
    created = $created
    updated = $updated
  }
}

function Get-TargetRows {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$Fetch
  )

  return @((Get-CrmRecordsByFetch -conn $Connection -Fetch $Fetch).CrmRecords)
}

function Get-VerificationSummary {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [int]$GraceDaysValue
  )

  $quotesFetch = @"
<fetch version='1.0' mapping='logical' count='5000'>
  <entity name='qfu_quote'>
    <attribute name='qfu_quoteid' />
    <attribute name='qfu_quotenumber' />
    <attribute name='qfu_customername' />
    <attribute name='qfu_amount' />
    <attribute name='qfu_assignedto' />
    <attribute name='qfu_cssrname' />
    <attribute name='qfu_nextfollowup' />
    <attribute name='qfu_overduesince' />
    <attribute name='qfu_lasttouchedon' />
    <attribute name='qfu_priorityscore' />
    <attribute name='qfu_status' />
    <attribute name='qfu_sourcedate' />
    <order attribute='qfu_priorityscore' descending='true' />
    <order attribute='qfu_quotenumber' descending='false' />
  </entity>
</fetch>
"@
  $backordersFetch = @"
<fetch version='1.0' mapping='logical' count='5000'>
  <entity name='qfu_backorder'>
    <attribute name='qfu_backorderid' />
    <attribute name='qfu_customername' />
    <attribute name='qfu_totalvalue' />
    <attribute name='qfu_ontimedate' />
    <attribute name='qfu_cssrname' />
    <attribute name='qfu_daysoverdue' />
    <attribute name='qfu_salesdocnumber' />
    <attribute name='qfu_material' />
    <attribute name='qfu_description' />
    <attribute name='qfu_quantity' />
  </entity>
</fetch>
"@
  $budgetsFetch = @"
<fetch version='1.0' mapping='logical' count='500'>
  <entity name='qfu_budget'>
    <attribute name='qfu_budgetid' />
    <attribute name='qfu_budgetname' />
    <attribute name='qfu_actualsales' />
    <attribute name='qfu_budgetgoal' />
    <attribute name='qfu_percentachieved' />
    <attribute name='qfu_lastupdated' />
    <attribute name='qfu_cadsales' />
    <attribute name='qfu_usdsales' />
    <attribute name='qfu_month' />
    <attribute name='qfu_monthname' />
    <attribute name='qfu_year' />
    <order attribute='qfu_year' descending='true' />
    <order attribute='qfu_month' descending='true' />
  </entity>
</fetch>
"@

  $quotes = Get-TargetRows -Connection $Connection -Fetch $quotesFetch
  $backorders = Get-TargetRows -Connection $Connection -Fetch $backordersFetch
  $budgets = Get-TargetRows -Connection $Connection -Fetch $budgetsFetch

  $today = (Get-Date).Date
  $tomorrow = $today.AddDays(1)
  $graceCutoff = $today.AddDays(-1 * [Math]::Max(0, $GraceDaysValue - 1))
  $monthStart = Get-Date -Year $today.Year -Month $today.Month -Day 1
  $nextMonthStart = $monthStart.AddMonths(1)
  $last30Cutoff = $today.AddDays(-30)

  $openQuotes = @($quotes | Where-Object {
      $status = Convert-OptionalInt $_.qfu_status
      $status -notin @(2, 3, 4)
    })

  $dueToday = @($openQuotes | Where-Object {
      $next = Convert-OptionalDate $_.qfu_nextfollowup
      $next -and $next.Date -ge $today -and $next.Date -lt $tomorrow
    })
  $overdueQuotes = @($openQuotes | Where-Object {
      $next = Convert-OptionalDate $_.qfu_nextfollowup
      $next -and $next.Date -lt $today
    })
  $unscheduledOld = @($openQuotes | Where-Object {
      $next = Convert-OptionalDate $_.qfu_nextfollowup
      $sourceDate = Convert-OptionalDate $_.qfu_sourcedate
      (-not $next) -and $sourceDate -and $sourceDate.Date -lt $graceCutoff
    })
  $quotes30 = @($quotes | Where-Object {
      $sourceDate = Convert-OptionalDate $_.qfu_sourcedate
      $sourceDate -and $sourceDate -ge $last30Cutoff
    })

  $quotesWon = @($quotes30 | Where-Object { (Convert-OptionalInt $_.qfu_status) -eq 2 }).Count
  $quotesLost = @($quotes30 | Where-Object { (Convert-OptionalInt $_.qfu_status) -in @(3, 4) }).Count
  $quotesOpen30 = [Math]::Max(0, $quotes30.Count - $quotesWon - $quotesLost)
  $avgQuoteValue = if ($quotes30.Count -gt 0) {
    (($quotes30 | Measure-Object -Property qfu_amount -Sum).Sum / $quotes30.Count)
  } else {
    0
  }

  $currentMonthBackorders = @($backorders | Where-Object {
      $onTime = Convert-OptionalDate $_.qfu_ontimedate
      $onTime -and $onTime.Date -ge $monthStart -and $onTime.Date -lt $nextMonthStart
    })
  $currentMonthLate = @($currentMonthBackorders | Where-Object {
      $onTime = Convert-OptionalDate $_.qfu_ontimedate
      $days = Convert-OptionalInt $_.qfu_daysoverdue
      ($days -gt 0) -or ($onTime -and $onTime.Date -lt $today)
    })
  $allLateBackorders = @($backorders | Where-Object {
      $onTime = Convert-OptionalDate $_.qfu_ontimedate
      $days = Convert-OptionalInt $_.qfu_daysoverdue
      ($days -gt 0) -or ($onTime -and $onTime.Date -lt $today)
    })

  $latestBudget = $budgets | Sort-Object @{Expression = { Convert-OptionalInt $_.qfu_year }; Descending = $true }, @{Expression = { Convert-OptionalInt $_.qfu_month }; Descending = $true }, @{Expression = { Convert-OptionalDate $_.qfu_lastupdated }; Descending = $true } | Select-Object -First 1
  $openQuoteValue = (($openQuotes | Measure-Object -Property qfu_amount -Sum).Sum)

  return [ordered]@{
    synced_on = (Get-Date).ToString("o")
    quote_metrics = [ordered]@{
      total = $quotes.Count
      open = $openQuotes.Count
      due_today = $dueToday.Count
      overdue = $overdueQuotes.Count
      unscheduled_old = $unscheduledOld.Count
      open_value = if ($null -ne $openQuoteValue) { [decimal]$openQuoteValue } else { [decimal]0 }
      last_30_days_total = $quotes30.Count
      last_30_days_won = $quotesWon
      last_30_days_lost = $quotesLost
      last_30_days_open = $quotesOpen30
      last_30_days_avg_value = [decimal]$avgQuoteValue
    }
    backorder_metrics = [ordered]@{
      total = $backorders.Count
      current_month = $currentMonthBackorders.Count
      overdue_total = $allLateBackorders.Count
      current_month_forecast_value = [decimal](($currentMonthBackorders | Measure-Object -Property qfu_totalvalue -Sum).Sum)
      current_month_late_value = [decimal](($currentMonthLate | Measure-Object -Property qfu_totalvalue -Sum).Sum)
      all_backorders_value = [decimal](($backorders | Measure-Object -Property qfu_totalvalue -Sum).Sum)
      all_late_backorders_value = [decimal](($allLateBackorders | Measure-Object -Property qfu_totalvalue -Sum).Sum)
    }
    budget_latest = if ($latestBudget) {
      [ordered]@{
        name = $latestBudget.qfu_budgetname
        month = $latestBudget.qfu_month
        month_name = $latestBudget.qfu_monthname
        year = $latestBudget.qfu_year
        actual_sales = $latestBudget.qfu_actualsales
        budget_goal = $latestBudget.qfu_budgetgoal
        percent_achieved = $latestBudget.qfu_percentachieved
        last_updated = if ($latestBudget.qfu_lastupdated) { ([datetime]$latestBudget.qfu_lastupdated).ToString("o") } else { $null }
        cad_sales = $latestBudget.qfu_cadsales
        usd_sales = $latestBudget.qfu_usdsales
      }
    } else {
      $null
    }
    samples = [ordered]@{
      quotes = @($openQuotes | Select-Object -First 10 | ForEach-Object {
          [ordered]@{
            qfu_quotenumber = $_.qfu_quotenumber
            qfu_customername = $_.qfu_customername
            qfu_amount = $_.qfu_amount
            qfu_assignedto = $_.qfu_assignedto
            qfu_cssrname = $_.qfu_cssrname
            qfu_nextfollowup = if ($_.qfu_nextfollowup) { ([datetime]$_.qfu_nextfollowup).ToString("o") } else { $null }
            qfu_overduesince = if ($_.qfu_overduesince) { ([datetime]$_.qfu_overduesince).ToString("o") } else { $null }
            qfu_lasttouchedon = if ($_.qfu_lasttouchedon) { ([datetime]$_.qfu_lasttouchedon).ToString("o") } else { $null }
            qfu_priorityscore = $_.qfu_priorityscore
            qfu_status = $_.qfu_status
            qfu_sourcedate = if ($_.qfu_sourcedate) { ([datetime]$_.qfu_sourcedate).ToString("o") } else { $null }
          }
        })
      backorders = @($allLateBackorders | Sort-Object @{Expression = { Convert-OptionalInt $_.qfu_daysoverdue }; Descending = $true } | Select-Object -First 10 | ForEach-Object {
          [ordered]@{
            qfu_customername = $_.qfu_customername
            qfu_salesdocnumber = $_.qfu_salesdocnumber
            qfu_material = $_.qfu_material
            qfu_description = $_.qfu_description
            qfu_totalvalue = $_.qfu_totalvalue
            qfu_cssrname = $_.qfu_cssrname
            qfu_daysoverdue = $_.qfu_daysoverdue
            qfu_ontimedate = if ($_.qfu_ontimedate) { ([datetime]$_.qfu_ontimedate).ToString("o") } else { $null }
          }
        })
    }
  }
}

function Convert-OptionalBoolean {
  param($Value)

  if ($null -eq $Value -or [string]::IsNullOrWhiteSpace("$Value")) {
    return $null
  }

  return [System.Convert]::ToBoolean($Value)
}

function Ensure-ParsedWorkbookData {
  param(
    [string]$JsonPath,
    [string]$ParserScriptPath,
    [int]$GraceDaysValue
  )

  if (Test-Path -LiteralPath $JsonPath) {
    return
  }

  if (-not (Test-Path -LiteralPath $ParserScriptPath)) {
    throw "Parsed workbook JSON missing and parser script not found: $ParserScriptPath"
  }

  $python = Get-Command python -ErrorAction SilentlyContinue
  if (-not $python) {
    throw "python is required to generate $JsonPath"
  }

  Ensure-Directory (Split-Path -Parent $JsonPath)
  & $python.Source $ParserScriptPath --example-root "example" --output $JsonPath --grace-days $GraceDaysValue
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $JsonPath)) {
    throw "Failed to generate parsed workbook JSON: $JsonPath"
  }
}

function Get-ParsedWorkbookData {
  param([string]$JsonPath)

  return (Get-Content -LiteralPath $JsonPath -Raw | ConvertFrom-Json)
}

function Get-BranchSeedRecords {
  param([object]$ParsedData)

  return @($ParsedData.branches | ForEach-Object {
      [pscustomobject]@{
        qfu_name = "$($_.branch.branch_code) $($_.branch.branch_name)"
        qfu_sourceid = "$($_.branch.branch_code)|branch"
        qfu_branchcode = $_.branch.branch_code
        qfu_branchname = $_.branch.branch_name
        qfu_branchslug = $_.branch.branch_slug
        qfu_regionslug = $_.branch.region_slug
        qfu_regionname = $_.branch.region_name
        qfu_mailboxaddress = $_.branch.mailbox_address
        qfu_sortorder = $_.branch.sort_order
        qfu_active = $true
      }
    })
}

function Get-SourceFeedSeedRecords {
  param([object]$ParsedData)

  $feedSpecs = @(
    @{ SourceFamily = "SP830CA"; SubjectFilter = "SP830CA"; FilePattern = "*Quote Follow Up Report*.xlsx"; Enabled = $false },
    @{ SourceFamily = "ZBO"; SubjectFilter = "Daily Backorder Report"; FilePattern = "*ZBO*.xlsx"; Enabled = $false },
    @{ SourceFamily = "SA1300"; SubjectFilter = "SA1300"; FilePattern = "SA1300*.xlsx"; Enabled = $false },
    @{ SourceFamily = "GL060"; SubjectFilter = $null; FilePattern = "GL060 Report - Profit Center*.pdf"; Enabled = $true }
  )

  $records = @()
  foreach ($branchData in @($ParsedData.branches)) {
    foreach ($feed in $feedSpecs) {
      $records += [pscustomobject]@{
        qfu_name = "$($branchData.branch.branch_code) $($feed.SourceFamily) Feed"
        qfu_sourceid = "$($branchData.branch.branch_code)|feed|$($feed.SourceFamily)"
        qfu_branchcode = $branchData.branch.branch_code
        qfu_branchslug = $branchData.branch.branch_slug
        qfu_regionslug = $branchData.branch.region_slug
        qfu_sourcefamily = $feed.SourceFamily
        qfu_mailboxaddress = $branchData.branch.mailbox_address
        qfu_folderid = "Inbox"
        qfu_subjectfilter = $feed.SubjectFilter
        qfu_filenamepattern = $feed.FilePattern
        qfu_enabled = $feed.Enabled
      }
    }
  }

  return $records
}

function Get-OperationalSeedPayload {
  param([object]$ParsedData)

  $quotes = @()
  $quoteLines = @()
  $backorders = @()
  $budgets = @()
  $budgetArchives = @()
  $summaries = @()
  $batches = @()

  foreach ($branchData in @($ParsedData.branches)) {
    $quotes += @($branchData.quotes.records)
    $quoteLines += @($branchData.quote_lines.records)
    $backorders += @($branchData.backorders.records)
    $budgets += @($branchData.budgets.records)
    $budgetArchives += @($branchData.budgets.records | ForEach-Object {
        [pscustomobject]@{
          qfu_name = "$($branchData.branch.branch_code) $($_.qfu_monthname) $($_.qfu_year) Budget Target"
          qfu_sourceid = "$($branchData.branch.branch_code)|budgettarget|$($_.qfu_year)-$('{0:d2}' -f $_.qfu_month)"
          qfu_budgetgoal = $_.qfu_budgetgoal
          qfu_month = $_.qfu_month
          qfu_monthname = $_.qfu_monthname
          qfu_year = $_.qfu_year
          qfu_fiscalyear = "FY$([int]$_.qfu_year - 2000)"
          qfu_lastupdated = $_.qfu_lastupdated
          qfu_sourcefile = $_.qfu_sourcefile
          qfu_branchcode = $_.qfu_branchcode
          qfu_branchslug = $_.qfu_branchslug
          qfu_regionslug = $_.qfu_regionslug
          qfu_sourcefamily = $_.qfu_sourcefamily
        }
      })
    $summaries += @($branchData.summary)
    $batches += @($branchData.batches)
  }

  return [ordered]@{
    qfu_branch = Get-BranchSeedRecords -ParsedData $ParsedData
    qfu_sourcefeed = Get-SourceFeedSeedRecords -ParsedData $ParsedData
    qfu_quote = $quotes
    qfu_quoteline = $quoteLines
    qfu_backorder = $backorders
    qfu_budget = $budgets
    qfu_budgetarchive = $budgetArchives
    qfu_branchdailysummary = $summaries
    qfu_ingestionbatch = $batches
  }
}

function Convert-RecordToFields {
  param(
    [string]$EntityLogicalName,
    [object]$Record
  )

  $stringFields = @()
  $decimalFields = @()
  $integerFields = @()
  $dateFields = @()
  $booleanFields = @()

  switch ($EntityLogicalName) {
    "qfu_branch" {
      $stringFields = @("qfu_name", "qfu_sourceid", "qfu_branchcode", "qfu_branchname", "qfu_branchslug", "qfu_regionslug", "qfu_regionname", "qfu_mailboxaddress")
      $integerFields = @("qfu_sortorder")
      $booleanFields = @("qfu_active")
    }
    "qfu_sourcefeed" {
      $stringFields = @("qfu_name", "qfu_sourceid", "qfu_branchcode", "qfu_branchslug", "qfu_regionslug", "qfu_sourcefamily", "qfu_mailboxaddress", "qfu_folderid", "qfu_subjectfilter", "qfu_filenamepattern")
      $booleanFields = @("qfu_enabled")
    }
    "qfu_quote" {
      $stringFields = @("qfu_name", "qfu_sourceid", "qfu_quotenumber", "qfu_customername", "qfu_assignedto", "qfu_cssrname", "qfu_branchcode", "qfu_branchslug", "qfu_regionslug", "qfu_sourcefamily", "qfu_importbatchid", "qfu_sourcefile", "qfu_sourceworksheet")
      $decimalFields = @("qfu_amount")
      $integerFields = @("qfu_priorityscore", "qfu_actionstate", "qfu_status", "qfu_source_row_count")
      $dateFields = @("qfu_nextfollowup", "qfu_overduesince", "qfu_lasttouchedon", "qfu_lastfollowupupdatedon", "qfu_sourcedate", "qfu_sourceupdatedon", "qfu_inactiveon", "qfu_lastseenon")
      $booleanFields = @("qfu_active")
    }
    "qfu_backorder" {
      $stringFields = @("qfu_name", "qfu_sourceid", "qfu_customername", "qfu_cssrname", "qfu_salesdocnumber", "qfu_salesdoctype", "qfu_material", "qfu_materialgroup", "qfu_description", "qfu_uom", "qfu_accountmanager", "qfu_accountmanagername", "qfu_soldto", "qfu_shipto", "qfu_shiptoname", "qfu_shipconddesc", "qfu_delblockdesc", "qfu_billblockdesc", "qfu_itemcategory", "qfu_vendorpo", "qfu_createdby", "qfu_plant", "qfu_userstatusdescription", "qfu_reasonforrejection", "qfu_branchcode", "qfu_branchslug", "qfu_regionslug", "qfu_sourcefamily", "qfu_importbatchid", "qfu_sourcefile", "qfu_sourceline")
      $decimalFields = @("qfu_totalvalue", "qfu_quantity", "qfu_qtybilled", "qfu_qtyondelnotpgid", "qfu_qtynotondel", "qfu_netprice")
      $integerFields = @("qfu_daysoverdue")
      $dateFields = @("qfu_ontimedate", "qfu_lineitemcreatedon", "qfu_firstdate", "qfu_inactiveon", "qfu_lastseenon")
      $booleanFields = @("qfu_active")
    }
    "qfu_budget" {
      $stringFields = @("qfu_name", "qfu_sourceid", "qfu_budgetname", "qfu_monthname", "qfu_sourcefile", "qfu_branchcode", "qfu_branchslug", "qfu_regionslug", "qfu_sourcefamily", "qfu_importbatchid")
      $decimalFields = @("qfu_actualsales", "qfu_budgetgoal", "qfu_percentachieved", "qfu_cadsales", "qfu_usdsales")
      $integerFields = @("qfu_month", "qfu_year")
      $dateFields = @("qfu_lastupdated")
    }
    "qfu_budgetarchive" {
      $stringFields = @("qfu_name", "qfu_sourceid", "qfu_monthname", "qfu_fiscalyear", "qfu_sourcefile", "qfu_branchcode", "qfu_branchslug", "qfu_regionslug", "qfu_sourcefamily")
      $decimalFields = @("qfu_budgetgoal", "qfu_actualsales")
      $integerFields = @("qfu_month", "qfu_year")
      $dateFields = @("qfu_lastupdated")
    }
    "qfu_quoteline" {
      $stringFields = @("qfu_name", "qfu_sourceid", "qfu_uniquekey", "qfu_quotenumber", "qfu_linenumber", "qfu_soldtopartyname", "qfu_cssrname", "qfu_tsrname", "qfu_branchcode", "qfu_branchslug", "qfu_regionslug", "qfu_sourcefamily", "qfu_importbatchid", "qfu_sourcefile", "qfu_sourceworksheet")
      $decimalFields = @("qfu_amount")
      $integerFields = @("qfu_status")
      $dateFields = @("qfu_lastimportdate", "qfu_sourcedate")
    }
    "qfu_branchdailysummary" {
      $stringFields = @("qfu_name", "qfu_sourceid", "qfu_branchcode", "qfu_branchslug", "qfu_regionslug")
      $decimalFields = @("qfu_openquotevalue", "qfu_avgquotevalue30days", "qfu_currentmonthforecastvalue", "qfu_currentmonthlatevalue", "qfu_allbackordersvalue", "qfu_overduebackordersvalue", "qfu_budgetactual", "qfu_budgettarget", "qfu_budgetpace", "qfu_cadsales", "qfu_usdsales")
      $integerFields = @("qfu_openquotes", "qfu_overduequotes", "qfu_duetoday", "qfu_unscheduledold", "qfu_quoteslast30days", "qfu_quoteswon30days", "qfu_quoteslost30days", "qfu_quotesopen30days", "qfu_backordercount", "qfu_overduebackordercount")
      $dateFields = @("qfu_summarydate", "qfu_lastcalculatedon")
    }
    "qfu_branchopsdaily" {
      $stringFields = @("qfu_name", "qfu_sourceid", "qfu_branchcode", "qfu_branchslug", "qfu_regionslug", "qfu_sourcefamily", "qfu_sourcefile", "qfu_sourceworksheet", "qfu_billinglabel", "qfu_currencytype")
      $decimalFields = @("qfu_sales", "qfu_gp", "qfu_gppct", "qfu_ontimedelivery")
      $integerFields = @("qfu_sortorder")
      $dateFields = @("qfu_snapshotdate", "qfu_billingday")
      $booleanFields = @("qfu_istotalrow")
    }
    "qfu_financesnapshot" {
      $stringFields = @("qfu_name", "qfu_sourceid", "qfu_branchcode", "qfu_branchslug", "qfu_regionslug", "qfu_sourcefamily", "qfu_sourcefile", "qfu_monthlabel")
      $decimalFields = @("qfu_currentmonthsalesactual", "qfu_currentmonthsalesplan", "qfu_currentmonthgrossprofitactual", "qfu_currentmonthgrossprofitplan", "qfu_currentmonthgrossprofitpctactual", "qfu_currentmonthgrossprofitpctplan", "qfu_currentmonthopexpctactual", "qfu_currentmonthopexpctplan", "qfu_currentmonthgapactual", "qfu_currentmonthgapplan", "qfu_currentmonthoperatingprofitactual", "qfu_currentmonthoperatingprofitplan", "qfu_ytdsalesactual", "qfu_ytdsalesplan", "qfu_ytdgrossprofitactual", "qfu_ytdgrossprofitplan", "qfu_ytdoperatingprofitactual", "qfu_ytdoperatingprofitplan")
      $integerFields = @("qfu_month", "qfu_year")
      $dateFields = @("qfu_lastupdated")
    }
    "qfu_financevariance" {
      $stringFields = @("qfu_name", "qfu_sourceid", "qfu_branchcode", "qfu_branchslug", "qfu_regionslug", "qfu_sourcefamily", "qfu_sourcefile", "qfu_monthlabel", "qfu_variancelabel", "qfu_varianceslug")
      $decimalFields = @("qfu_currentmonthactual", "qfu_currentmonthplan", "qfu_currentmonthvariance", "qfu_ytdactual", "qfu_ytdplan", "qfu_ytdvariance")
      $integerFields = @("qfu_month", "qfu_year", "qfu_sortorder")
      $dateFields = @("qfu_lastupdated")
    }
    "qfu_marginexception" {
      $stringFields = @("qfu_name", "qfu_sourceid", "qfu_branchcode", "qfu_branchslug", "qfu_regionslug", "qfu_sourcefamily", "qfu_sourcefile", "qfu_reviewtype", "qfu_currencytype", "qfu_cssr", "qfu_cssrname", "qfu_customername", "qfu_billingdocumentnumber", "qfu_billingdocumenttype")
      $decimalFields = @("qfu_sales", "qfu_cogs", "qfu_gp")
      $dateFields = @("qfu_snapshotdate", "qfu_billingdate")
    }
    "qfu_lateorderexception" {
      $stringFields = @("qfu_name", "qfu_sourceid", "qfu_branchcode", "qfu_branchslug", "qfu_regionslug", "qfu_sourcefamily", "qfu_sourcefile", "qfu_cssr", "qfu_cssrname", "qfu_soldtocustomername", "qfu_shiptocustomername", "qfu_billingdocumentnumber", "qfu_materialgroup", "qfu_itemcategory", "qfu_itemcategorydescription")
      $decimalFields = @("qfu_sales")
      $dateFields = @("qfu_snapshotdate", "qfu_billingdate")
    }
    "qfu_ingestionbatch" {
      $stringFields = @("qfu_name", "qfu_sourceid", "qfu_branchcode", "qfu_branchslug", "qfu_regionslug", "qfu_sourcefamily", "qfu_sourcefilename", "qfu_status", "qfu_triggerflow", "qfu_notes")
      $integerFields = @("qfu_insertedcount", "qfu_updatedcount")
      $dateFields = @("qfu_startedon", "qfu_completedon")
    }
    "qfu_rawdocument" {
      $stringFields = @("qfu_name", "qfu_sourceid", "qfu_branchcode", "qfu_branchslug", "qfu_regionslug", "qfu_sourcefamily", "qfu_sourcefile", "qfu_status", "qfu_monthlabel", "qfu_rawcontentbase64", "qfu_processingnotes")
      $integerFields = @("qfu_month", "qfu_year")
      $dateFields = @("qfu_receivedon", "qfu_processedon")
    }
    default {
      throw "Unsupported entity for seed conversion: $EntityLogicalName"
    }
  }

  $fields = @{}

  foreach ($fieldName in $stringFields) {
    $value = Convert-OptionalText $Record.$fieldName
    if ($null -ne $value) {
      $fields[$fieldName] = $value
    }
  }
  foreach ($fieldName in $decimalFields) {
    $value = Convert-OptionalDecimal $Record.$fieldName
    if ($null -ne $value) {
      $fields[$fieldName] = $value
    }
  }
  foreach ($fieldName in $integerFields) {
    $value = Convert-OptionalInt $Record.$fieldName
    if ($null -ne $value) {
      $fields[$fieldName] = $value
    }
  }
  foreach ($fieldName in $dateFields) {
    $value = Convert-OptionalDate $Record.$fieldName
    if ($null -ne $value) {
      $fields[$fieldName] = $value
    }
  }
  foreach ($fieldName in $booleanFields) {
    $value = Convert-OptionalBoolean $Record.$fieldName
    if ($null -ne $value) {
      $fields[$fieldName] = $value
    }
  }

  if ($EntityLogicalName -eq "qfu_quote") {
    if (-not $fields.ContainsKey("qfu_active")) {
      $fields["qfu_active"] = $true
    }
    if (-not $fields.ContainsKey("qfu_lastseenon")) {
      $lastSeen = Convert-OptionalDate $Record.qfu_sourceupdatedon
      if ($null -eq $lastSeen) {
        $lastSeen = Convert-OptionalDate $Record.qfu_sourcedate
      }
      if ($null -eq $lastSeen) {
        $lastSeen = Convert-OptionalDate $Record.createdon
      }
      if ($null -ne $lastSeen) {
        $fields["qfu_lastseenon"] = $lastSeen
      }
    }
  }

  if ($EntityLogicalName -eq "qfu_backorder") {
    if (-not $fields.ContainsKey("qfu_active")) {
      $fields["qfu_active"] = $true
    }
    if (-not $fields.ContainsKey("qfu_lastseenon")) {
      $lastSeen = Convert-OptionalDate $Record.qfu_lastseenon
      if ($null -eq $lastSeen) {
        $lastSeen = Convert-OptionalDate $Record.modifiedon
      }
      if ($null -eq $lastSeen) {
        $lastSeen = Convert-OptionalDate $Record.createdon
      }
      if ($null -eq $lastSeen) {
        $lastSeen = Convert-OptionalDate $Record.qfu_ontimedate
      }
      if ($null -ne $lastSeen) {
        $fields["qfu_lastseenon"] = $lastSeen
      }
    }
  }

  return $fields
}

function Remove-SeedRowsForBranches {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$EntityLogicalName,
    [string[]]$BranchCodes
  )

  $idFieldName = "${EntityLogicalName}id"
  $deleted = 0

  foreach ($branchCode in $BranchCodes) {
    do {
      $rows = @(Get-CrmRecords -conn $Connection -EntityLogicalName $EntityLogicalName -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $branchCode -Fields @($idFieldName) -TopCount 5000).CrmRecords
      foreach ($row in $rows) {
        $recordId = $row.$idFieldName
        if ($recordId) {
          $attempt = 0
          while ($true) {
            try {
              $Connection.Delete($EntityLogicalName, [guid]$recordId)
              $deleted += 1
              break
            } catch {
              if ($_.Exception.Message -like "*Does Not Exist*" -or $_.Exception.Message -like "*No object matched the query*") {
                break
              }
              if (($_.Exception.Message -like "*concurrent Delete requests detected*" -or $_.Exception.Message -like "*try again later*") -and $attempt -lt 5) {
                Start-Sleep -Seconds (2 * ($attempt + 1))
                $attempt += 1
                continue
              }
              throw
            }
          }
        }
      }
    } while ($rows.Count -gt 0)
  }

  return $deleted
}

function Import-SeedRecords {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$EntityLogicalName,
    [object[]]$Records
  )

  $inserted = 0
  foreach ($record in @($Records)) {
    $fields = Convert-RecordToFields -EntityLogicalName $EntityLogicalName -Record $record
    $null = New-CrmRecord -conn $Connection -EntityLogicalName $EntityLogicalName -Fields $fields
    $inserted += 1
  }

  return $inserted
}

function Collapse-DuplicateRowsBySourceId {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$EntityLogicalName,
    [string[]]$BranchCodes
  )

  $idFieldName = "${EntityLogicalName}id"
  $collapsed = 0
  $groups = @()

  foreach ($branchCode in $BranchCodes) {
    $rows = @(
      (Get-CrmRecords -conn $Connection -EntityLogicalName $EntityLogicalName -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $branchCode -Fields @($idFieldName, "qfu_branchcode", "qfu_sourceid", "createdon", "modifiedon") -TopCount 5000).CrmRecords |
        Where-Object { $_.qfu_sourceid }
    )
    $duplicateGroups = @(
      $rows |
        Group-Object -Property qfu_sourceid |
        Where-Object { $_.Count -gt 1 }
    )

    foreach ($group in $duplicateGroups) {
      $ordered = @(
        $group.Group |
          Sort-Object `
            @{ Expression = { if ($_.modifiedon) { [datetime]$_.modifiedon } else { [datetime]::MinValue } }; Descending = $true }, `
            @{ Expression = { if ($_.createdon) { [datetime]$_.createdon } else { [datetime]::MinValue } }; Descending = $true }, `
            @{ Expression = { [string]$($_.$idFieldName) } }
      )
      $winner = $ordered | Select-Object -First 1
      $duplicates = @($ordered | Select-Object -Skip 1)
      foreach ($duplicate in $duplicates) {
        $recordId = $duplicate.$idFieldName
        if (-not $recordId) {
          continue
        }
        try {
          $Connection.Delete($EntityLogicalName, [guid]$recordId)
          $collapsed += 1
        } catch {
          if ($_.Exception.Message -notlike "*Does Not Exist*" -and $_.Exception.Message -notlike "*No object matched the query*") {
            throw
          }
        }
      }
      $groups += [pscustomobject]@{
        branch_code = $branchCode
        source_id = [string]$group.Name
        winner_id = [string]$winner.$idFieldName
        removed_ids = @($duplicates | ForEach-Object { [string]$_.$idFieldName })
      }
    }
  }

  return [ordered]@{
    collapsed = $collapsed
    groups = $groups
  }
}

function Get-EntityCountsByBranch {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$EntityLogicalName,
    [string[]]$BranchCodes
  )

  $result = [ordered]@{}
  foreach ($branchCode in $BranchCodes) {
    $rows = @(Get-CrmRecords -conn $Connection -EntityLogicalName $EntityLogicalName -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $branchCode -Fields @("qfu_branchcode") -TopCount 5000).CrmRecords
    $result[$branchCode] = @($rows).Count
  }

  return $result
}

function Get-SeedVerificationSummary {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [object]$ParsedData
  )

  $branchCodes = @($ParsedData.branches | ForEach-Object { $_.branch.branch_code })
  $summaryByBranch = [ordered]@{}

  foreach ($branchData in @($ParsedData.branches)) {
    $summaryByBranch[$branchData.branch.branch_code] = [ordered]@{
      branch_name = $branchData.branch.branch_name
      branch_slug = $branchData.branch.branch_slug
      expected = [ordered]@{
        qfu_quote = @($branchData.quotes.records).Count
        qfu_quoteline = @($branchData.quote_lines.records).Count
        qfu_backorder = @($branchData.backorders.records).Count
        qfu_budget = @($branchData.budgets.records).Count
        qfu_budgetarchive = @($branchData.budgets.records).Count
        qfu_branchdailysummary = 1
        qfu_ingestionbatch = @($branchData.batches).Count
      }
      summary_snapshot = $branchData.summary
    }
  }

  return [ordered]@{
    verified_on = (Get-Date).ToString("o")
    branches = $summaryByBranch
    target_counts = [ordered]@{
      qfu_branch = Get-EntityCountsByBranch -Connection $Connection -EntityLogicalName "qfu_branch" -BranchCodes $branchCodes
      qfu_sourcefeed = Get-EntityCountsByBranch -Connection $Connection -EntityLogicalName "qfu_sourcefeed" -BranchCodes $branchCodes
      qfu_quote = Get-EntityCountsByBranch -Connection $Connection -EntityLogicalName "qfu_quote" -BranchCodes $branchCodes
      qfu_quoteline = Get-EntityCountsByBranch -Connection $Connection -EntityLogicalName "qfu_quoteline" -BranchCodes $branchCodes
      qfu_backorder = Get-EntityCountsByBranch -Connection $Connection -EntityLogicalName "qfu_backorder" -BranchCodes $branchCodes
      qfu_budget = Get-EntityCountsByBranch -Connection $Connection -EntityLogicalName "qfu_budget" -BranchCodes $branchCodes
      qfu_budgetarchive = Get-EntityCountsByBranch -Connection $Connection -EntityLogicalName "qfu_budgetarchive" -BranchCodes $branchCodes
      qfu_branchdailysummary = Get-EntityCountsByBranch -Connection $Connection -EntityLogicalName "qfu_branchdailysummary" -BranchCodes $branchCodes
      qfu_ingestionbatch = Get-EntityCountsByBranch -Connection $Connection -EntityLogicalName "qfu_ingestionbatch" -BranchCodes $branchCodes
    }
  }
}

if (-not $QfuLoadAsLibrary -and $MyInvocation.InvocationName -ne ".") {
  $target = Connect-Org -Url $TargetEnvironmentUrl

  Write-Host "Connected target: $($target.ConnectedOrgFriendlyName)"

  Ensure-ParsedWorkbookData -JsonPath $ParsedWorkbookJson -ParserScriptPath $ParsedWorkbookScript -GraceDaysValue $GraceDays
  Ensure-MinimalSchema -Connection $target

  $parsedData = Get-ParsedWorkbookData -JsonPath $ParsedWorkbookJson
  $branchCodes = @($parsedData.branches | ForEach-Object { $_.branch.branch_code })
  $seedPayload = Get-OperationalSeedPayload -ParsedData $parsedData

  if (@($seedPayload.qfu_quote).Count -gt 0 -and @($seedPayload.qfu_quoteline).Count -eq 0) {
    throw "Seed payload contains qfu_quote rows but no qfu_quoteline rows. Refusing to create header-only quote data."
  }

  $deleteOrder = @(
    "qfu_ingestionbatch",
    "qfu_branchdailysummary",
    "qfu_quoteline",
    "qfu_quote",
    "qfu_backorder",
    "qfu_budget",
    "qfu_budgetarchive",
    "qfu_sourcefeed",
    "qfu_branch"
  )

  $deletedCounts = [ordered]@{}
  foreach ($entityLogicalName in $deleteOrder) {
    $deletedCounts[$entityLogicalName] = Remove-SeedRowsForBranches -Connection $target -EntityLogicalName $entityLogicalName -BranchCodes $branchCodes
  }

  $insertedCounts = [ordered]@{}
  foreach ($entityLogicalName in @("qfu_branch", "qfu_sourcefeed", "qfu_quote", "qfu_quoteline", "qfu_backorder", "qfu_budget", "qfu_budgetarchive", "qfu_branchdailysummary", "qfu_ingestionbatch")) {
    $insertedCounts[$entityLogicalName] = Import-SeedRecords -Connection $target -EntityLogicalName $entityLogicalName -Records @($seedPayload[$entityLogicalName])
  }

  $collapsedDuplicates = [ordered]@{
    qfu_branch = Collapse-DuplicateRowsBySourceId -Connection $target -EntityLogicalName "qfu_branch" -BranchCodes $branchCodes
    qfu_sourcefeed = Collapse-DuplicateRowsBySourceId -Connection $target -EntityLogicalName "qfu_sourcefeed" -BranchCodes $branchCodes
    qfu_quote = Collapse-DuplicateRowsBySourceId -Connection $target -EntityLogicalName "qfu_quote" -BranchCodes $branchCodes
    qfu_quoteline = Collapse-DuplicateRowsBySourceId -Connection $target -EntityLogicalName "qfu_quoteline" -BranchCodes $branchCodes
    qfu_backorder = Collapse-DuplicateRowsBySourceId -Connection $target -EntityLogicalName "qfu_backorder" -BranchCodes $branchCodes
    qfu_budgetarchive = Collapse-DuplicateRowsBySourceId -Connection $target -EntityLogicalName "qfu_budgetarchive" -BranchCodes $branchCodes
    qfu_branchdailysummary = Collapse-DuplicateRowsBySourceId -Connection $target -EntityLogicalName "qfu_branchdailysummary" -BranchCodes $branchCodes
    qfu_ingestionbatch = Collapse-DuplicateRowsBySourceId -Connection $target -EntityLogicalName "qfu_ingestionbatch" -BranchCodes $branchCodes
  }

  $verification = Get-SeedVerificationSummary -Connection $target -ParsedData $parsedData

  $result = [ordered]@{
    target_environment = $TargetEnvironmentUrl
    parsed_workbook_json = (Resolve-Path -LiteralPath $ParsedWorkbookJson).Path
    grace_days = $GraceDays
    deleted = $deletedCounts
    inserted = $insertedCounts
    collapsed_duplicates = $collapsedDuplicates
    verification = $verification
  }

  Write-Utf8Json -Path $OutputJson -Object $result
  Write-Output ($result | ConvertTo-Json -Depth 10)
}
