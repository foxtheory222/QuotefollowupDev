param(
  [string]$RepoRoot = "C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion",
  [string]$TargetEnvironmentUrl = "https://regionaloperationshub.crm.dynamics.com",
  [string]$Username = "smcfarlane@applied.com",
  [string]$OutputJson = "results\freight-worklist-schema-summary.json"
)

$ErrorActionPreference = "Stop"

. (Join-Path $RepoRoot "scripts\deploy-southern-alberta-pilot.ps1")

$branchSpecs = @(
  [pscustomobject]@{ BranchCode = "4171"; BranchSlug = "4171-calgary"; RegionSlug = "southern-alberta"; MailboxAddress = "4171@applied.com"; EnableFeeds = $true },
  [pscustomobject]@{ BranchCode = "4172"; BranchSlug = "4172-lethbridge"; RegionSlug = "southern-alberta"; MailboxAddress = "4172@applied.com"; EnableFeeds = $true },
  [pscustomobject]@{ BranchCode = "4173"; BranchSlug = "4173-medicine-hat"; RegionSlug = "southern-alberta"; MailboxAddress = "4173@applied.com"; EnableFeeds = $true }
)

$freightFeedSpecs = @(
  [pscustomobject]@{ SourceFamily = "FREIGHT_REDWOOD"; SubjectFilter = "Invoice Report"; FilePattern = "Applied Canada * Invoice Report.xlsx" },
  [pscustomobject]@{ SourceFamily = "FREIGHT_LOOMIS_F15"; SubjectFilter = "Loomis Invoices Report [F15]"; FilePattern = "Loomis Invoices Report [F15]*.xls" },
  [pscustomobject]@{ SourceFamily = "FREIGHT_PUROLATOR_F07"; SubjectFilter = "Purolator Invoices Report [F07]"; FilePattern = "Purolator Invoices Report [F07]*.xls" },
  [pscustomobject]@{ SourceFamily = "FREIGHT_UPS_F06"; SubjectFilter = "UPS Canada Invoices previous week Report [F06]"; FilePattern = "UPS Canada Invoices previous week Report [F06]*.xls" }
)

function Ensure-EntityKey {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$EntityLogicalName,
    [string]$SchemaName,
    [string]$DisplayName,
    [string[]]$AttributeLogicalNames
  )

  try {
    $retrieve = [Microsoft.Xrm.Sdk.Messages.RetrieveEntityRequest]::new()
    $retrieve.LogicalName = $EntityLogicalName
    $retrieve.EntityFilters = [Microsoft.Xrm.Sdk.Metadata.EntityFilters]::Entity
    $retrieve.RetrieveAsIfPublished = $true
    $response = $Connection.Execute($retrieve)

    $targetAttributes = @($AttributeLogicalNames | Sort-Object)
    foreach ($existingKey in @($response.EntityMetadata.Keys)) {
      if ($existingKey.SchemaName -eq $SchemaName) {
        Write-Host "Entity key exists: $EntityLogicalName.$SchemaName"
        return
      }

      $existingAttributes = @($existingKey.KeyAttributes | Sort-Object)
      if (($existingAttributes -join "|") -eq ($targetAttributes -join "|")) {
        Write-Host "Entity key exists by attribute set: $EntityLogicalName.$SchemaName"
        return
      }
    }
  } catch {
    Write-Host "Unable to pre-read entity keys for $EntityLogicalName; falling back to create-with-already-exists handling."
  }

  $key = [Microsoft.Xrm.Sdk.Metadata.EntityKeyMetadata]::new()
  $key.SchemaName = $SchemaName
  $key.DisplayName = New-Label $DisplayName
  $key.KeyAttributes = [string[]]@($AttributeLogicalNames)

  $create = [Microsoft.Xrm.Sdk.Messages.CreateEntityKeyRequest]::new()
  $create.EntityName = $EntityLogicalName
  $create.EntityKey = $key
  try {
    $Connection.Execute($create) | Out-Null
    Write-Host "Created entity key: $EntityLogicalName.$SchemaName"
  } catch {
    $message = $_.Exception.Message
    if ($message -like "*already exists*") {
      Write-Host "Entity key exists after retry: $EntityLogicalName.$SchemaName"
      return
    }
    throw
  }
}

function Ensure-FreightSchema {
  param([Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection)

  Ensure-MinimalSchema -Connection $Connection

  Ensure-Entity -Connection $Connection -SchemaName "qfu_freightworkitem" -DisplayName "QFU Freight Work Item" -DisplayCollectionName "QFU Freight Work Items" -Description "Weekly freight worklist rows imported from carrier reports." -PrimaryNameSchema "qfu_name" -PrimaryNameDisplay "Name"

  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_sourceid" -DisplayName "Source Id" -MaxLength 400
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_branchcode" -DisplayName "Branch Code" -MaxLength 10
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_branchslug" -DisplayName "Branch Slug" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_regionslug" -DisplayName "Region Slug" -MaxLength 100
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_sourcefamily" -DisplayName "Source Family" -MaxLength 60
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_sourcefilename" -DisplayName "Source File Name" -MaxLength 260
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_sourcecarrier" -DisplayName "Source Carrier" -MaxLength 160
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_importbatchid" -DisplayName "Import Batch Id" -MaxLength 200
  Ensure-MemoAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_rawrowjson" -DisplayName "Raw Row JSON" -MaxLength 1048576

  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_trackingnumber" -DisplayName "Tracking Number" -MaxLength 120
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_pronumber" -DisplayName "PRO Number" -MaxLength 120
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_invoicenumber" -DisplayName "Invoice Number" -MaxLength 120
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_controlnumber" -DisplayName "Control Number" -MaxLength 120
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_reference" -DisplayName "Reference" -MaxLength 500
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_shipdate" -DisplayName "Ship Date" -Format ([Microsoft.Xrm.Sdk.Metadata.DateTimeFormat]::DateOnly)
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_invoicedate" -DisplayName "Invoice Date" -Format ([Microsoft.Xrm.Sdk.Metadata.DateTimeFormat]::DateOnly)
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_closedate" -DisplayName "Close Date" -Format ([Microsoft.Xrm.Sdk.Metadata.DateTimeFormat]::DateOnly)
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_billtype" -DisplayName "Bill Type" -MaxLength 80
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_service" -DisplayName "Service" -MaxLength 200
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_servicecode" -DisplayName "Service Code" -MaxLength 80
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_sender" -DisplayName "Sender" -MaxLength 800
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_destination" -DisplayName "Destination" -MaxLength 800
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_zone" -DisplayName "Zone" -MaxLength 40
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_actualweight" -DisplayName "Actual Weight" -Precision 2 -MinValue 0 -MaxValue 1000000
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_billedweight" -DisplayName "Billed Weight" -Precision 2 -MinValue 0 -MaxValue 1000000
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_quantity" -DisplayName "Quantity" -Precision 2 -MinValue 0 -MaxValue 1000000

  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_totalamount" -DisplayName "Total Amount" -Precision 2 -MinValue -1000000 -MaxValue 1000000000
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_freightamount" -DisplayName "Freight Amount" -Precision 2 -MinValue -1000000 -MaxValue 1000000000
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_fuelamount" -DisplayName "Fuel Amount" -Precision 2 -MinValue -1000000 -MaxValue 1000000000
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_taxamount" -DisplayName "Tax Amount" -Precision 2 -MinValue -1000000 -MaxValue 1000000000
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_gstamount" -DisplayName "GST Amount" -Precision 2 -MinValue -1000000 -MaxValue 1000000000
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_hstamount" -DisplayName "HST Amount" -Precision 2 -MinValue -1000000 -MaxValue 1000000000
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_qstamount" -DisplayName "QST Amount" -Precision 2 -MinValue -1000000 -MaxValue 1000000000
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_accessorialamount" -DisplayName "Accessorial Amount" -Precision 2 -MinValue -1000000 -MaxValue 1000000000
  Ensure-BooleanAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_accessorialpresent" -DisplayName "Accessorial Present"
  Ensure-DecimalAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_unrealizedsavings" -DisplayName "Unrealized Savings" -Precision 2 -MinValue -1000000 -MaxValue 1000000000
  Ensure-MemoAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_chargebreakdowntext" -DisplayName "Charge Breakdown Text" -MaxLength 8000

  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_direction" -DisplayName "Direction" -MaxLength 40
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_status" -DisplayName "Status" -MaxLength 80
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_priorityband" -DisplayName "Priority Band" -MaxLength 80
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_ownername" -DisplayName "Owner Name" -MaxLength 200
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_owneridentifier" -DisplayName "Owner Identifier" -MaxLength 250
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_claimedon" -DisplayName "Claimed On"
  Ensure-MemoAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_comment" -DisplayName "Comment" -MaxLength 4000
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_commentupdatedon" -DisplayName "Comment Updated On"
  Ensure-StringAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_commentupdatedbyname" -DisplayName "Comment Updated By Name" -MaxLength 200
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_lastactivityon" -DisplayName "Last Activity On"
  Ensure-BooleanAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_isarchived" -DisplayName "Is Archived"
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_archivedon" -DisplayName "Archived On"
  Ensure-DateTimeAttribute -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_lastseenon" -DisplayName "Last Seen On"

  Ensure-EntityKey -Connection $Connection -EntityLogicalName "qfu_freightworkitem" -SchemaName "qfu_freightworkitem_sourceid_key" -DisplayName "Source Id Key" -AttributeLogicalNames @("qfu_sourceid")
}

function Upsert-SourceFeedRow {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [object]$Record
  )

  $existing = @(Get-CrmRecords -conn $Connection -EntityLogicalName "qfu_sourcefeed" -FilterAttribute "qfu_sourceid" -FilterOperator eq -FilterValue $Record.qfu_sourceid -Fields @("qfu_sourcefeedid") -TopCount 1).CrmRecords | Select-Object -First 1
  $fields = @{
    qfu_name = [string]$Record.qfu_name
    qfu_sourceid = [string]$Record.qfu_sourceid
    qfu_branchcode = [string]$Record.qfu_branchcode
    qfu_branchslug = [string]$Record.qfu_branchslug
    qfu_regionslug = [string]$Record.qfu_regionslug
    qfu_sourcefamily = [string]$Record.qfu_sourcefamily
    qfu_mailboxaddress = [string]$Record.qfu_mailboxaddress
    qfu_folderid = [string]$Record.qfu_folderid
    qfu_subjectfilter = [string]$Record.qfu_subjectfilter
    qfu_filenamepattern = [string]$Record.qfu_filenamepattern
    qfu_enabled = [bool]$Record.qfu_enabled
  }

  if ($existing) {
    Set-CrmRecord -conn $Connection -EntityLogicalName "qfu_sourcefeed" -Id $existing.qfu_sourcefeedid -Fields $fields | Out-Null
    return "updated"
  }

  New-CrmRecord -conn $Connection -EntityLogicalName "qfu_sourcefeed" -Fields $fields | Out-Null
  return "created"
}

function Get-FreightSourceFeedSeedRecords {
  $records = New-Object System.Collections.Generic.List[object]
  foreach ($branch in $branchSpecs) {
    foreach ($feed in $freightFeedSpecs) {
      $records.Add([pscustomobject]@{
          qfu_name = "$($branch.BranchCode) $($feed.SourceFamily) Feed"
          qfu_sourceid = "$($branch.BranchCode)|feed|$($feed.SourceFamily)"
          qfu_branchcode = $branch.BranchCode
          qfu_branchslug = $branch.BranchSlug
          qfu_regionslug = $branch.RegionSlug
          qfu_sourcefamily = $feed.SourceFamily
          qfu_mailboxaddress = $branch.MailboxAddress
          qfu_folderid = "Inbox"
          qfu_subjectfilter = $feed.SubjectFilter
          qfu_filenamepattern = $feed.FilePattern
          qfu_enabled = $branch.EnableFeeds
        }) | Out-Null
    }
  }

  return @($records.ToArray())
}

if ($MyInvocation.InvocationName -ne ".") {
  $target = Connect-Org -Url $TargetEnvironmentUrl
  Write-Host "Connected target: $($target.ConnectedOrgFriendlyName)"

  Ensure-FreightSchema -Connection $target

  $feedRows = Get-FreightSourceFeedSeedRecords
  $feedResults = @()
  foreach ($feedRow in $feedRows) {
    $feedResults += [pscustomobject]@{
      source_id = $feedRow.qfu_sourceid
      result = Upsert-SourceFeedRow -Connection $target -Record $feedRow
      enabled = [bool]$feedRow.qfu_enabled
    }
  }

  $result = [ordered]@{
    target_environment = $TargetEnvironmentUrl
    entity = "qfu_freightworkitem"
    source_feed_results = $feedResults
  }

  Write-Utf8Json -Path (Join-Path $RepoRoot $OutputJson) -Object $result
  Write-Output ($result | ConvertTo-Json -Depth 8)
}
