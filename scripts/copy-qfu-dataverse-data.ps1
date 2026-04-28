param(
  [string]$SourceEnvironmentUrl = "https://regionaloperationshub.crm.dynamics.com",
  [string]$TargetEnvironmentUrl = "https://orga632edd5.crm3.dynamics.com",
  [string]$Username = "smcfarlane@applied.com",
  [string]$OutputPath = "results\qfu-dataverse-data-copy.json",
  [switch]$Execute,
  [switch]$ResumeMissingOnly,
  [int]$BatchSize = 250
)

$ErrorActionPreference = "Stop"

Import-Module Microsoft.Xrm.Data.Powershell
Add-Type -AssemblyName "Microsoft.Xrm.Sdk"
Add-Type -AssemblyName "Microsoft.Crm.Sdk.Proxy"

$sourceConnection = Connect-CrmOnline -ServerUrl $SourceEnvironmentUrl -ForceOAuth -Username $Username
if (-not $sourceConnection -or -not $sourceConnection.IsReady) {
  throw "Source Dataverse connection failed for $SourceEnvironmentUrl : $($sourceConnection.LastCrmError)"
}

$targetConnection = Connect-CrmOnline -ServerUrl $TargetEnvironmentUrl -ForceOAuth -Username $Username
if (-not $targetConnection -or -not $targetConnection.IsReady) {
  throw "Target Dataverse connection failed for $TargetEnvironmentUrl : $($targetConnection.LastCrmError)"
}

$copyOrder = @(
  "qfu_region",
  "qfu_branch",
  "qfu_sourcefeed",
  "qfu_ingestionbatch",
  "qfu_budgetarchive",
  "qfu_budget",
  "qfu_financesnapshot",
  "qfu_financevariance",
  "qfu_branchdailysummary",
  "qfu_branchopsdaily",
  "qfu_quote",
  "qfu_quoteline",
  "qfu_backorder",
  "qfu_deliverynotpgi",
  "qfu_marginexception",
  "qfu_lateorderexception",
  "qfu_freightworkitem"
)

$deleteOrder = @(
  "qfu_freightworkitem",
  "qfu_lateorderexception",
  "qfu_marginexception",
  "qfu_deliverynotpgi",
  "qfu_backorder",
  "qfu_quoteline",
  "qfu_quote",
  "qfu_branchopsdaily",
  "qfu_branchdailysummary",
  "qfu_financevariance",
  "qfu_financesnapshot",
  "qfu_budget",
  "qfu_budgetarchive",
  "qfu_ingestionbatch",
  "qfu_sourcefeed",
  "qfu_branch",
  "qfu_region"
)

function Get-EntityMetadataMap {
  param(
    [object]$Connection,
    [string]$LogicalName
  )

  $request = [Microsoft.Xrm.Sdk.Messages.RetrieveEntityRequest]::new()
  $request.LogicalName = $LogicalName
  $request.EntityFilters = [Microsoft.Xrm.Sdk.Metadata.EntityFilters]::Entity -bor [Microsoft.Xrm.Sdk.Metadata.EntityFilters]::Attributes
  $request.RetrieveAsIfPublished = $true
  $response = $Connection.Execute($request)
  $metadata = $response.EntityMetadata
  $attributes = @{}
  foreach ($attribute in $metadata.Attributes) {
    $attributes[$attribute.LogicalName] = $attribute
  }

  return [pscustomobject]@{
    logical_name = $metadata.LogicalName
    primary_id_attribute = $metadata.PrimaryIdAttribute
    primary_name_attribute = $metadata.PrimaryNameAttribute
    attributes = $attributes
  }
}

function Get-AllRows {
  param(
    [object]$Connection,
    [string]$LogicalName,
    [string[]]$Columns
  )

  $query = [Microsoft.Xrm.Sdk.Query.QueryExpression]::new($LogicalName)
  $query.ColumnSet = [Microsoft.Xrm.Sdk.Query.ColumnSet]::new($Columns)
  $query.NoLock = $true
  $query.PageInfo = [Microsoft.Xrm.Sdk.Query.PagingInfo]::new()
  $query.PageInfo.Count = 5000
  $query.PageInfo.PageNumber = 1

  $rows = New-Object System.Collections.Generic.List[Microsoft.Xrm.Sdk.Entity]
  do {
    $response = $Connection.RetrieveMultiple($query)
    foreach ($entity in $response.Entities) {
      $rows.Add($entity) | Out-Null
    }
    $query.PageInfo.PageNumber += 1
    $query.PageInfo.PagingCookie = $response.PagingCookie
  } while ($response.MoreRecords)

  return $rows
}

function Get-TargetIds {
  param(
    [object]$Connection,
    [string]$LogicalName,
    [string]$PrimaryIdAttribute
  )

  $rows = Get-AllRows -Connection $Connection -LogicalName $LogicalName -Columns @($PrimaryIdAttribute)
  return @($rows | ForEach-Object { $_.Id })
}

function New-CopiedEntity {
  param(
    [Microsoft.Xrm.Sdk.Entity]$SourceEntity,
    [object]$Metadata
  )

  $copy = [Microsoft.Xrm.Sdk.Entity]::new($SourceEntity.LogicalName)
  $copy.Id = $SourceEntity.Id
  if ($SourceEntity.Attributes.ContainsKey("createdon") -and $SourceEntity["createdon"]) {
    $copy["overriddencreatedon"] = $SourceEntity["createdon"]
  }

  foreach ($key in $SourceEntity.Attributes.Keys) {
    if ($key -eq $Metadata.primary_id_attribute) {
      continue
    }

    $attributeMetadata = $Metadata.attributes[$key]
    if (-not $attributeMetadata) {
      continue
    }

    if (-not ([string]$key).StartsWith("qfu_", [System.StringComparison]::OrdinalIgnoreCase)) {
      continue
    }

    if ($attributeMetadata.IsValidForCreate -ne $true) {
      continue
    }

    $copy[$key] = $SourceEntity[$key]
  }

  return ,$copy
}

function Remove-ExistingRows {
  param(
    [object]$Connection,
    [string]$LogicalName,
    [Guid[]]$Ids
  )

  $requests = New-Object System.Collections.Generic.List[object]
  foreach ($id in $Ids) {
    $request = [Microsoft.Xrm.Sdk.Messages.DeleteRequest]::new()
    $request.Target = [Microsoft.Xrm.Sdk.EntityReference]::new($LogicalName, $id)
    $requests.Add([pscustomobject]@{
      id = $id
      request = $request
    }) | Out-Null
  }

  return Invoke-RequestBatches -Connection $Connection -Requests $requests -BatchSize $BatchSize
}

function Create-CopiedRows {
  param(
    [object]$Connection,
    [string]$LogicalName,
    [Microsoft.Xrm.Sdk.Entity[]]$Rows,
    [object]$Metadata,
    [System.Collections.Generic.HashSet[string]]$ExistingIds
  )

  $created = 0
  $skipped = 0
  $requests = New-Object System.Collections.Generic.List[object]
  foreach ($row in $Rows) {
    if ($ExistingIds -and $ExistingIds.Contains([string]$row.Id)) {
      $skipped += 1
      continue
    }

    $entity = New-CopiedEntity -SourceEntity $row -Metadata $Metadata
    $request = [Microsoft.Xrm.Sdk.Messages.CreateRequest]::new()
    $request.Target = $entity
    $requests.Add([pscustomobject]@{
      id = $row.Id
      request = $request
    }) | Out-Null
  }

  $batchResult = Invoke-RequestBatches -Connection $Connection -Requests $requests -BatchSize $BatchSize
  $created = $batchResult.succeeded
  return ,([pscustomobject]@{
    created = $created
    skipped = $skipped
    failures = @($batchResult.failures)
  })
}

function Invoke-RequestBatches {
  param(
    [object]$Connection,
    [object[]]$Requests,
    [int]$BatchSize = 250
  )

  $succeeded = 0
  $failures = New-Object System.Collections.Generic.List[object]
  $requestArray = @($Requests)
  for ($offset = 0; $offset -lt $requestArray.Count; $offset += $BatchSize) {
    $batchItems = @($requestArray | Select-Object -Skip $offset -First $BatchSize)
    if ($batchItems.Count -eq 0) {
      continue
    }

    $batch = [Microsoft.Xrm.Sdk.Messages.ExecuteMultipleRequest]::new()
    $batch.Settings = [Microsoft.Xrm.Sdk.ExecuteMultipleSettings]::new()
    $batch.Settings.ContinueOnError = $true
    $batch.Settings.ReturnResponses = $true
    $batch.Requests = [Microsoft.Xrm.Sdk.OrganizationRequestCollection]::new()

    foreach ($item in $batchItems) {
      $batch.Requests.Add($item.request)
    }

    $response = $Connection.Execute($batch)
    $failedIndexes = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($responseItem in $response.Responses) {
      if ($responseItem.Fault) {
        [void]$failedIndexes.Add([int]$responseItem.RequestIndex)
        $failedItem = $batchItems[[int]$responseItem.RequestIndex]
        $failures.Add([pscustomobject]@{
          id = $failedItem.id
          message = $responseItem.Fault.Message
        }) | Out-Null
      }
    }

    $succeeded += ($batchItems.Count - $failedIndexes.Count)
  }

  return ,([pscustomobject]@{
    succeeded = $succeeded
    failures = @($failures.ToArray())
  })
}

$metadataByTable = @{}
$sourceRowsByTable = @{}
$preflight = New-Object System.Collections.Generic.List[object]

foreach ($table in $copyOrder) {
  try {
    $metadata = Get-EntityMetadataMap -Connection $sourceConnection -LogicalName $table
    $null = Get-EntityMetadataMap -Connection $targetConnection -LogicalName $table
  } catch {
    $preflight.Add([pscustomobject]@{
      table = $table
      available = $false
      error = $_.Exception.Message
    }) | Out-Null
    continue
  }

  $columns = @($metadata.attributes.Keys | Where-Object {
    if ($_ -eq $metadata.primary_id_attribute) {
      return $true
    }

    if ($_ -eq "createdon") {
      return $true
    }

    $attribute = $metadata.attributes[$_]
    ([string]$_).StartsWith("qfu_", [System.StringComparison]::OrdinalIgnoreCase) -and
      $attribute.IsValidForRead -eq $true -and
      $attribute.IsValidForCreate -eq $true -and
      [string]::IsNullOrWhiteSpace([string]$attribute.AttributeOf)
  } | Sort-Object)
  if ($columns -notcontains $metadata.primary_id_attribute) {
    $columns += $metadata.primary_id_attribute
  }

  $sourceRows = Get-AllRows -Connection $sourceConnection -LogicalName $table -Columns $columns
  $targetIds = Get-TargetIds -Connection $targetConnection -LogicalName $table -PrimaryIdAttribute $metadata.primary_id_attribute

  $metadataByTable[$table] = $metadata
  $sourceRowsByTable[$table] = $sourceRows
  $preflight.Add([pscustomobject]@{
    table = $table
    available = $true
    source_count = $sourceRows.Count
    target_count_before = @($targetIds).Count
    copied_column_count = $columns.Count
  }) | Out-Null
}

$deleteResults = @()
$copyResults = @()

if ($Execute) {
  if (-not $ResumeMissingOnly) {
    foreach ($table in $deleteOrder) {
      if (-not $metadataByTable.ContainsKey($table)) {
        continue
      }

      $metadata = $metadataByTable[$table]
      $targetIds = Get-TargetIds -Connection $targetConnection -LogicalName $table -PrimaryIdAttribute $metadata.primary_id_attribute
      $deleted = Remove-ExistingRows -Connection $targetConnection -LogicalName $table -Ids @($targetIds)
      $deleteResults += [pscustomobject]@{
        table = $table
        deleted = $deleted
      }
    }
  }

  foreach ($table in $copyOrder) {
    if (-not $metadataByTable.ContainsKey($table)) {
      continue
    }

    $metadata = $metadataByTable[$table]
    $rows = @($sourceRowsByTable[$table])
    $existingIds = $null
    if ($ResumeMissingOnly) {
      $existingIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
      foreach ($targetId in Get-TargetIds -Connection $targetConnection -LogicalName $table -PrimaryIdAttribute $metadata.primary_id_attribute) {
        [void]$existingIds.Add([string]$targetId)
      }
    }

    $result = Create-CopiedRows -Connection $targetConnection -LogicalName $table -Rows $rows -Metadata $metadata -ExistingIds $existingIds
    $copyResults += [pscustomobject]@{
      table = $table
      source_count = $rows.Count
      created = [int]$result.created
      skipped = [int]$result.skipped
      failure_count = @($result.failures).Count
      failures = @($result.failures)
    }
  }
}

$postCounts = New-Object System.Collections.Generic.List[object]
foreach ($table in $copyOrder) {
  if (-not $metadataByTable.ContainsKey($table)) {
    continue
  }

  $metadata = $metadataByTable[$table]
  $targetIds = Get-TargetIds -Connection $targetConnection -LogicalName $table -PrimaryIdAttribute $metadata.primary_id_attribute
  $postCounts.Add([pscustomobject]@{
    table = $table
    target_count_after = @($targetIds).Count
  }) | Out-Null
}

$resultPayload = [ordered]@{
  captured_at = (Get-Date).ToUniversalTime().ToString("o")
  mode = if ($Execute) { "execute" } else { "dry-run" }
  resume_missing_only = [bool]$ResumeMissingOnly
  source_environment_url = $SourceEnvironmentUrl
  target_environment_url = $TargetEnvironmentUrl
  tables = $copyOrder
  preflight = $preflight
  delete_results = $deleteResults
  copy_results = $copyResults
  post_counts = $postCounts
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

[System.IO.File]::WriteAllText($fullOutputPath, ($resultPayload | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
Write-Output "OUTPUT_PATH=$fullOutputPath"
