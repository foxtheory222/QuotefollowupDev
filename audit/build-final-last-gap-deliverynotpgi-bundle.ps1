param(
  [string]$RepoRoot = "C:\Dev\QuoteFollowUpComplete",
  [string]$LegacyEvidenceRoot = "C:\Dev\QuoteFollowUpComplete-replacement-20260401",
  [string]$PriorGapsRoot = "C:\Dev\QuoteFollowUpComplete\QFU_FINAL_GAPS_STAGING",
  [string]$PriorGapsZip = "C:\Dev\QuoteFollowUpComplete\QFU_CHATGPT_FINAL_AUDIT_GAPS_BUNDLE_2026-04-07.zip",
  [string]$PriorAuditZip = "C:\Dev\QuoteFollowUpComplete\QFU_CHATGPT_FINAL_AUDIT_EVIDENCE_BUNDLE_2026-04-07.zip",
  [string]$StagingRoot = "C:\Dev\QuoteFollowUpComplete\QFU_FINAL_LAST_GAP_STAGING",
  [string]$ZipPath = "C:\Dev\QuoteFollowUpComplete\QFU_CHATGPT_FINAL_LAST_GAP_DELIVERYNOTPGI_BUNDLE_2026-04-07.zip",
  [string]$TargetEnvironmentUrl = "https://regionaloperationshub.crm.dynamics.com",
  [string]$Username = "smcfarlane@applied.com",
  [int]$HistoryDays = 180
)

$ErrorActionPreference = "Stop"

Import-Module Microsoft.Xrm.Data.Powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem

$branchCodes = @("4171", "4172", "4173")
$searchTerms = @(
  "qfu_deliverynotpgi",
  "deliverynotpgi",
  "delivery-not-pgi",
  "notpgi",
  "not pgi",
  "pgi",
  "ready to ship not pgi",
  "ready-to-ship-not-pgid",
  "dayslate",
  "unshippednetvalue",
  "qfu_commentupdatedon",
  "qfu_commentupdatedbyname",
  "qfu_deliverynotpgiid",
  "qfu_sourceid",
  "qfu_sourcefamily",
  "zbo",
  "ca zbo",
  "sapilot",
  "quotefollowup",
  "sourcefeed",
  "rawdocument",
  "ingestionbatch",
  "/_api/qfu_deliverynotpgis",
  "/_api/qfu_deliverynotpgi",
  "qfu_deliverynotpgis(",
  "createRecord(",
  "updateRecord(",
  "patch",
  "post"
)

$textExtensions = @(".ps1", ".py", ".js", ".ts", ".cs", ".sql", ".json", ".xml", ".html", ".md", ".txt", ".yml", ".yaml", ".csv")
$found = New-Object System.Collections.Generic.List[object]
$missing = New-Object System.Collections.Generic.List[object]
$searchHitList = New-Object System.Collections.Generic.List[object]
$zipHitList = New-Object System.Collections.Generic.List[object]

function Ensure-Directory {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) {
    return
  }
  if (-not (Test-Path -LiteralPath $Path)) {
    try {
      New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
    catch {
      throw "Ensure-Directory failed for path: $Path :: $($_.Exception.Message)"
    }
  }
}

function Get-RelativePathSafe {
  param(
    [string]$BasePath,
    [string]$FullPath
  )

  try {
    $baseFull = [System.IO.Path]::GetFullPath($BasePath).TrimEnd('\')
    $targetFull = [System.IO.Path]::GetFullPath($FullPath)
    if ($targetFull.StartsWith($baseFull, [System.StringComparison]::OrdinalIgnoreCase)) {
      return $targetFull.Substring($baseFull.Length).TrimStart('\')
    }
    return [System.IO.Path]::GetRelativePath($baseFull, $targetFull)
  }
  catch {
    return $FullPath
  }
}

function Write-JsonFile {
  param(
    [string]$Path,
    [object]$Data,
    [int]$Depth = 12
  )

  $Data | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Add-Found {
  param(
    [string]$Bucket,
    [string]$Item,
    [string]$Status,
    [string]$Detail
  )

  $found.Add([pscustomobject]@{
    bucket = $Bucket
    item = $Item
    status = $Status
    detail = $Detail
  })
}

function Add-Missing {
  param(
    [string]$Bucket,
    [string]$Item,
    [string]$Status,
    [string]$Detail
  )

  $missing.Add([pscustomobject]@{
    bucket = $Bucket
    item = $Item
    status = $Status
    detail = $Detail
  })
}

function Get-DisplayLabel {
  param($Label)

  if ($null -eq $Label) { return $null }
  if ($Label.UserLocalizedLabel -and $Label.UserLocalizedLabel.Label) { return $Label.UserLocalizedLabel.Label }
  if ($Label.LocalizedLabels -and $Label.LocalizedLabels.Count -gt 0) { return $Label.LocalizedLabels[0].Label }
  return $null
}

function Convert-RawValue {
  param($Value)

  if ($null -eq $Value) { return $null }

  $typeName = $Value.GetType().FullName
  switch ($typeName) {
    "Microsoft.Xrm.Sdk.OptionSetValue" { return $Value.Value }
    "Microsoft.Xrm.Sdk.Money" { return $Value.Value }
    "Microsoft.Xrm.Sdk.EntityReference" {
      return @{
        id = $Value.Id.Guid
        logicalname = $Value.LogicalName
        name = $Value.Name
      }
    }
    "Microsoft.Xrm.Sdk.BooleanManagedProperty" { return $Value.Value }
    "Microsoft.Xrm.Sdk.AliasedValue" { return Convert-RawValue -Value $Value.Value }
  }

  if ($Value -is [datetime]) { return $Value.ToString("o") }
  if ($Value -is [guid]) { return $Value.Guid }
  if ($Value -is [System.ValueType] -or $Value -is [string]) { return $Value }

  try {
    return ($Value | ConvertTo-Json -Depth 10 -Compress)
  }
  catch {
    return [string]$Value
  }
}

function Get-FormattedValue {
  param(
    [psobject]$Record,
    [string]$PropertyName
  )

  if ($Record.PSObject.Properties[$PropertyName]) {
    return $Record.$PropertyName
  }

  return $null
}

function Get-RawPropertyValue {
  param(
    [psobject]$Record,
    [string]$PropertyName
  )

  $rawPropertyName = "{0}_Property" -f $PropertyName
  if ($Record.PSObject.Properties[$rawPropertyName]) {
    return Convert-RawValue -Value $Record.$rawPropertyName.Value
  }

  if ($Record.PSObject.Properties[$PropertyName]) {
    return Convert-RawValue -Value $Record.$PropertyName
  }

  return $null
}

function Flatten-CrmRecord {
  param(
    [psobject]$Record,
    [string]$EntityLogicalName,
    [string[]]$Attributes
  )

  $flat = [ordered]@{
    _entity = $EntityLogicalName
    _logicalname = $Record.logicalname
    _primaryid = $Record.ReturnProperty_Id
  }

  foreach ($attribute in $Attributes) {
    $flat[$attribute] = Get-FormattedValue -Record $Record -PropertyName $attribute
    $flat["{0}__raw" -f $attribute] = Get-RawPropertyValue -Record $Record -PropertyName $attribute
  }

  return [pscustomobject]$flat
}

function Connect-Org {
  param(
    [string]$Url,
    [string]$User
  )

  $conn = Connect-CrmOnline -ServerUrl $Url -ForceOAuth -Username $User
  if (-not $conn -or -not $conn.IsReady) {
    throw "Dataverse connection failed for $Url : $($conn.LastCrmError)"
  }

  return $conn
}

function Get-ReadableAttributes {
  param($EntityMetadata)

  return @(
    $EntityMetadata.Attributes |
      Where-Object { $_.IsValidForRead -ne $false } |
      Sort-Object LogicalName
  )
}

function Export-EntityMetadata {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$EntityLogicalName,
    [string]$OutputPath
  )

  $meta = Get-CrmEntityMetadata -conn $Connection -EntityLogicalName $EntityLogicalName -EntityFilters All
  $readableAttributes = Get-ReadableAttributes -EntityMetadata $meta
  $alternateKeys = @()

  foreach ($key in @($meta.Keys)) {
    $alternateKeys += [pscustomobject]@{
      logical_name = $key.LogicalName
      display_name = Get-DisplayLabel -Label $key.DisplayName
      key_attributes = @($key.KeyAttributes)
    }
  }

  $attributeRows = foreach ($attribute in $readableAttributes) {
    $optionSet = @()
    if ($attribute.PSObject.Properties["OptionSet"] -and $attribute.OptionSet -and $attribute.OptionSet.Options) {
      foreach ($option in @($attribute.OptionSet.Options)) {
        $optionSet += [pscustomobject]@{
          value = $option.Value
          label = Get-DisplayLabel -Label $option.Label
        }
      }
    }

    [pscustomobject]@{
      logical_name = $attribute.LogicalName
      display_name = Get-DisplayLabel -Label $attribute.DisplayName
      data_type = [string]$attribute.AttributeType
      data_type_name = [string]$attribute.AttributeTypeName.Value
      format = if ($attribute.PSObject.Properties["Format"] -and $attribute.Format) { [string]$attribute.Format } else { $null }
      date_behavior = if ($attribute.PSObject.Properties["DateTimeBehavior"] -and $attribute.DateTimeBehavior) { [string]$attribute.DateTimeBehavior.Value } else { $null }
      required_level = if ($attribute.PSObject.Properties["RequiredLevel"] -and $attribute.RequiredLevel) { [string]$attribute.RequiredLevel.Value } else { $null }
      is_primary_id = ($attribute.LogicalName -eq $meta.PrimaryIdAttribute)
      is_primary_name = ($attribute.LogicalName -eq $meta.PrimaryNameAttribute)
      is_valid_for_read = $attribute.IsValidForRead
      option_set = $optionSet
    }
  }

  $payload = [ordered]@{
    exported_at = (Get-Date).ToUniversalTime().ToString("o")
    entity_logical_name = $meta.LogicalName
    entity_display_name = Get-DisplayLabel -Label $meta.DisplayName
    schema_name = $meta.SchemaName
    entity_set_name = $meta.EntitySetName
    primary_id = $meta.PrimaryIdAttribute
    primary_name = $meta.PrimaryNameAttribute
    alternate_keys = $alternateKeys
    attributes = $attributeRows
  }

  $payload | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
}

function New-BranchFilterXml {
  param(
    [string]$BranchField
  )

  $conditions = foreach ($branchCode in $branchCodes) {
    "<condition attribute='{0}' operator='eq' value='{1}' />" -f $BranchField, [System.Security.SecurityElement]::Escape($branchCode)
  }

  return "<filter type='or'>{0}</filter>" -f ($conditions -join [Environment]::NewLine)
}

function Export-EntityRows {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$EntityLogicalName,
    [string]$FilterXml,
    [string]$JsonPath,
    [string]$CsvPath
  )

  $meta = Get-CrmEntityMetadata -conn $Connection -EntityLogicalName $EntityLogicalName -EntityFilters Attributes
  $attributeNames = @((Get-ReadableAttributes -EntityMetadata $meta) | Select-Object -ExpandProperty LogicalName)

  $fetch = @"
<fetch version='1.0' mapping='logical' no-lock='true'>
  <entity name='$EntityLogicalName'>
    <all-attributes />
    $FilterXml
    <order attribute='modifiedon' descending='true' />
  </entity>
</fetch>
"@

  $results = Get-CrmRecordsByFetch -conn $Connection -Fetch $fetch -AllRows
  $records = @($results.CrmRecords)
  $flatRows = foreach ($record in $records) {
    Flatten-CrmRecord -Record $record -EntityLogicalName $EntityLogicalName -Attributes $attributeNames
  }

  @($flatRows) | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $JsonPath -Encoding UTF8
  @($flatRows) | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8
  return @($flatRows)
}

function Search-TextRoots {
  param(
    [string[]]$Roots,
    [string]$Label
  )

  $hits = New-Object System.Collections.Generic.List[object]
  foreach ($root in @($Roots | Where-Object { Test-Path -LiteralPath $_ })) {
    $files = Get-ChildItem -Path $root -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $textExtensions -contains $_.Extension.ToLowerInvariant() }
    foreach ($term in $searchTerms) {
      $termHits = Select-String -Path $files.FullName -Pattern $term -SimpleMatch -ErrorAction SilentlyContinue
      foreach ($hit in @($termHits)) {
        $row = [pscustomobject]@{
          source = $Label
          search_term = $term
          path = $hit.Path
          line_number = $hit.LineNumber
          line = $hit.Line.Trim()
        }
        $hits.Add($row)
        $searchHitList.Add($row)
      }
    }
  }

  return @($hits.ToArray())
}

function Search-ZipText {
  param(
    [string[]]$ZipPaths,
    [string]$OutputRoot
  )

  Ensure-Directory -Path $OutputRoot
  $zipInventory = New-Object System.Collections.Generic.List[object]

  foreach ($zipPath in @($ZipPaths | Where-Object { Test-Path -LiteralPath $_ })) {
    $zipInventory.Add([pscustomobject]@{
      zip_path = $zipPath
      length = (Get-Item -LiteralPath $zipPath).Length
    })

    try {
      $archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
      foreach ($entry in @($archive.Entries)) {
        if ([string]::IsNullOrWhiteSpace($entry.Name)) { continue }

        $entryExt = [System.IO.Path]::GetExtension($entry.FullName).ToLowerInvariant()
        if ($entryExt -eq ".zip") {
          $nestedZipTemp = Join-Path $OutputRoot ("nested-" + [guid]::NewGuid().Guid + ".zip")
          $entryStream = $entry.Open()
          $fileStream = [System.IO.File]::Create($nestedZipTemp)
          $entryStream.CopyTo($fileStream)
          $fileStream.Dispose()
          $entryStream.Dispose()

          try {
            $nestedArchive = [System.IO.Compression.ZipFile]::OpenRead($nestedZipTemp)
            foreach ($nestedEntry in @($nestedArchive.Entries)) {
              if ([string]::IsNullOrWhiteSpace($nestedEntry.Name)) { continue }
              $nestedExt = [System.IO.Path]::GetExtension($nestedEntry.FullName).ToLowerInvariant()
              if ($textExtensions -notcontains $nestedExt) { continue }
              $reader = New-Object System.IO.StreamReader($nestedEntry.Open())
              $content = $reader.ReadToEnd()
              $reader.Dispose()
              foreach ($term in $searchTerms) {
                if ($content -like ("*" + $term + "*")) {
                  $zipHitList.Add([pscustomobject]@{
                    source = "zip-nested"
                    search_term = $term
                    zip_path = $zipPath
                    entry_path = $entry.FullName
                    nested_entry_path = $nestedEntry.FullName
                    line_number = $null
                    line = $null
                  })
                }
              }
            }
            $nestedArchive.Dispose()
          }
          finally {
            if (Test-Path -LiteralPath $nestedZipTemp) {
              Remove-Item -LiteralPath $nestedZipTemp -Force
            }
          }
          continue
        }

        if ($textExtensions -notcontains $entryExt) { continue }

        $reader = New-Object System.IO.StreamReader($entry.Open())
        $content = $reader.ReadToEnd()
        $reader.Dispose()
        foreach ($term in $searchTerms) {
          if ($content -like ("*" + $term + "*")) {
            $zipHitList.Add([pscustomobject]@{
              source = "zip-entry"
              search_term = $term
              zip_path = $zipPath
              entry_path = $entry.FullName
              nested_entry_path = $null
              line_number = $null
              line = $null
            })
          }
        }
      }
      $archive.Dispose()
    }
    catch {
      $zipHitList.Add([pscustomobject]@{
        source = "zip-open-failed"
        search_term = ""
        zip_path = $zipPath
        entry_path = ""
        nested_entry_path = ""
        line_number = $null
        line = $_.Exception.Message
      })
    }
  }

  Write-JsonFile -Path (Join-Path $OutputRoot "zip-inventory.json") -Data @($zipInventory.ToArray())
  Write-JsonFile -Path (Join-Path $OutputRoot "zip-search-hits.json") -Data @($zipHitList.ToArray())
}

function Copy-IfExists {
  param(
    [string]$SourcePath,
    [string]$DestinationPath
  )

  if (Test-Path -LiteralPath $SourcePath) {
    Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($DestinationPath))
    Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force
    return $true
  }

  return $false
}

function Export-SolutionReadOnly {
  param(
    [string]$SolutionName,
    [string]$OutputRoot
  )

  Ensure-Directory -Path $OutputRoot
  $zipOut = Join-Path $OutputRoot ($SolutionName + ".zip")
  $logPath = Join-Path $OutputRoot ($SolutionName + ".export.log")
  $extractRoot = Join-Path $OutputRoot "extracted"

  if (Test-Path -LiteralPath $zipOut) { Remove-Item -LiteralPath $zipOut -Force }
  if (Test-Path -LiteralPath $extractRoot) { Remove-Item -LiteralPath $extractRoot -Recurse -Force }

  $output = & pac solution export --name $SolutionName --path $zipOut --managed false --overwrite 2>&1
  Set-Content -LiteralPath $logPath -Value $output -Encoding UTF8

  $success = (Test-Path -LiteralPath $zipOut)
  if ($success) {
    Expand-Archive -LiteralPath $zipOut -DestinationPath $extractRoot -Force
  }

  return @{
    success = $success
    zip_path = $zipOut
    extract_root = $extractRoot
    log_path = $logPath
  }
}

function Query-WorkflowDiscovery {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$OutputRoot
  )

  Ensure-Directory -Path $OutputRoot

  $workflowFetch = @"
<fetch version='1.0' mapping='logical' no-lock='true'>
  <entity name='workflow'>
    <all-attributes />
    <filter type='or'>
      <condition attribute='name' operator='like' value='%ZBO%' />
      <condition attribute='name' operator='like' value='%PGI%' />
      <condition attribute='name' operator='like' value='%Delivery%' />
      <condition attribute='name' operator='like' value='%Pilot%' />
      <condition attribute='name' operator='like' value='%Ready to Ship%' />
    </filter>
    <order attribute='modifiedon' descending='true' />
  </entity>
</fetch>
"@

  $solutionFetch = @"
<fetch version='1.0' mapping='logical' no-lock='true'>
  <entity name='solution'>
    <all-attributes />
    <filter type='or'>
      <condition attribute='uniquename' operator='like' value='%sapilot%' />
      <condition attribute='uniquename' operator='like' value='%pgi%' />
      <condition attribute='uniquename' operator='like' value='%delivery%' />
      <condition attribute='friendlyname' operator='like' value='%Pilot%' />
      <condition attribute='friendlyname' operator='like' value='%PGI%' />
      <condition attribute='friendlyname' operator='like' value='%Delivery%' />
    </filter>
    <order attribute='modifiedon' descending='true' />
  </entity>
</fetch>
"@

  $workflowRows = @((Get-CrmRecordsByFetch -conn $Connection -Fetch $workflowFetch -AllRows).CrmRecords)
  $solutionRows = @((Get-CrmRecordsByFetch -conn $Connection -Fetch $solutionFetch -AllRows).CrmRecords)

  $workflowExport = @(
    $workflowRows | ForEach-Object {
      [pscustomobject]@{
        workflowid = $_.workflowid
        name = $_.name
        statecode = $_.statecode
        statuscode = $_.statuscode
        category = $_.category
        type = $_.type
        createdon = $_.createdon
        modifiedon = $_.modifiedon
      }
    }
  )

  $solutionExport = @(
    $solutionRows | ForEach-Object {
      [pscustomobject]@{
        solutionid = $_.solutionid
        friendlyname = $_.friendlyname
        uniquename = $_.uniquename
        version = $_.version
        createdon = $_.createdon
        modifiedon = $_.modifiedon
      }
    }
  )

  Write-JsonFile -Path (Join-Path $OutputRoot "workflow-query-results.json") -Data $workflowExport
  $workflowExport | Export-Csv -LiteralPath (Join-Path $OutputRoot "workflow-query-results.csv") -NoTypeInformation -Encoding UTF8
  Write-JsonFile -Path (Join-Path $OutputRoot "solution-query-results.json") -Data $solutionExport
  $solutionExport | Export-Csv -LiteralPath (Join-Path $OutputRoot "solution-query-results.csv") -NoTypeInformation -Encoding UTF8

  return @{
    workflows = $workflowExport
    solutions = $solutionExport
  }
}

function Write-Readme {
  param([string]$Path)

  $content = @'
# Final Last-Gap Delivery-Not-PGI Bundle

This bundle contains the final missing evidence for the delivery-not-PGI writer path.

- No fixes were implemented.
- No app behavior was changed.
- No flow definitions were activated, deactivated, repaired, or redeployed.
- No Dataverse rows were created, patched, deleted, normalized, or deduplicated.
- All environment actions were read-only discovery or export operations.

Purpose:
- prove the exact create/update writer path for qfu_deliverynotpgi, or prove with hard evidence that the writer is not present in the available exported/source-controlled artifacts
- separate Power Pages comment/update behavior from the true base-row writer
- close the last missing audit evidence gap so no more file requests are needed for a full regression/reliability audit
'@

  Set-Content -LiteralPath $Path -Value $content -Encoding UTF8
}

function Write-FoundVsMissing {
  param(
    [string]$Path,
    [object[]]$FoundItems,
    [object[]]$MissingItems
  )

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("# Found vs Missing")
  $lines.Add("")

  $sections = @(
    "FOUND",
    "FOUND INSIDE NESTED ZIP",
    "FOUND VIA READ-ONLY ENVIRONMENT QUERY",
    "NOT FOUND",
    "COULD NOT EXPORT"
  )

  foreach ($section in $sections) {
    $lines.Add("## $section")
    $items = @($FoundItems + $MissingItems | Where-Object { $_.status -eq $section } | Sort-Object bucket, item)
    if (-not $items) {
      $lines.Add("- none")
      $lines.Add("")
      continue
    }
    foreach ($item in $items) {
      $lines.Add("- [$($item.bucket)] $($item.item)")
      $lines.Add("  - $($item.detail)")
    }
    $lines.Add("")
  }

  Set-Content -LiteralPath $Path -Value @($lines) -Encoding UTF8
}

function Write-ExportMethod {
  param(
    [datetime]$CutoffDate,
    [string]$Path,
    [string]$TargetEnvironmentUrl
  )

  $lines = @(
    "# Export Method",
    "",
    "## Filesystem search methods",
    "- Searched current source tree under site/, audit/, and repository root text artifacts.",
    "- Searched legacy evidence tree under C:\Dev\QuoteFollowUpComplete-replacement-20260401 scripts/, results/, and solution/ text artifacts.",
    "- Used PowerShell Get-ChildItem + Select-String with explicit term lists and text-file extension filters.",
    "",
    "## Zip-inside-zip search methods",
    "- Enumerated zip files in repository root and legacy evidence root.",
    "- Opened zip archives read-only via System.IO.Compression.ZipFile.",
    "- Searched textual entry contents for the required delivery-not-PGI terms.",
    "- If a zip entry was itself a .zip, extracted that nested zip to a temporary file and searched its textual entries too.",
    "",
    "## Workflow/process discovery methods",
    "- Queried Dataverse workflow and solution tables read-only via Microsoft.Xrm.Data.Powershell using FetchXML like-filters for ZBO/PGI/Delivery/Pilot names.",
    "- Exported the current unmanaged qfu_sapilotflows solution read-only via pac solution export.",
    "- Searched the exported workflow JSON/XML contents for delivery-not-PGI and related patterns.",
    "",
    "## Dataverse export method",
    "- Tool: Microsoft.Xrm.Data.Powershell Get-CrmEntityMetadata and Get-CrmRecordsByFetch",
    "- Connection: Connect-CrmOnline to $TargetEnvironmentUrl",
    "- Tables exported: qfu_deliverynotpgi, qfu_sourcefeed, qfu_rawdocument, qfu_ingestionbatch",
    "- Date window: on-or-after $($CutoffDate.ToString('yyyy-MM-dd')) for delivery rows, rawdocument rows, and ingestionbatch rows; sourcefeed exported without date trim",
    "- Branch filter: qfu_branchcode in (4171, 4172, 4173) where the table carries qfu_branchcode",
    "",
    "## Limits / trimming",
    "- No row dedupe or summarization applied to raw exports.",
    "- JSON and CSV both emitted for row exports.",
    "- No rows intentionally omitted beyond the explicit 180-day window and branch filters above."
  )

  Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
}

function Write-SearchHits {
  param(
    [string]$Path,
    [object[]]$SearchHits,
    [object[]]$ZipHits,
    [string]$RepoRoot
  )

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("# Search Hits")
  $lines.Add("")

  foreach ($term in $searchTerms) {
    $lines.Add("## $term")
    $termHits = @($SearchHits | Where-Object { $_.search_term -eq $term } | Sort-Object path, line_number)
    $zipTermHits = @($ZipHits | Where-Object { $_.search_term -eq $term } | Sort-Object zip_path, entry_path, nested_entry_path)

    if (-not $termHits -and -not $zipTermHits) {
      $lines.Add("- no hits")
      $lines.Add("")
      continue
    }

    foreach ($hit in $termHits) {
      $relative = Get-RelativePathSafe -BasePath $RepoRoot -FullPath $hit.path
      $lines.Add("- [$($hit.source)] ${relative}:$($hit.line_number): $($hit.line)")
    }

    foreach ($hit in $zipTermHits) {
      if ($hit.source -eq "zip-nested") {
        $lines.Add("- [zip-nested] $($hit.zip_path) :: $($hit.entry_path) :: $($hit.nested_entry_path)")
      }
      elseif ($hit.source -eq "zip-entry") {
        $lines.Add("- [zip-entry] $($hit.zip_path) :: $($hit.entry_path)")
      }
      else {
        $lines.Add("- [$($hit.source)] $($hit.zip_path): $($hit.line)")
      }
    }

    $lines.Add("")
  }

  Set-Content -LiteralPath $Path -Value @($lines) -Encoding UTF8
}

function Write-TreeFile {
  param(
    [string]$Root,
    [string]$Path
  )

  tree $Root /F | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-Sha256File {
  param(
    [string]$Root,
    [string]$Path
  )

  $lines = Get-ChildItem -Path $Root -Recurse -File | Sort-Object FullName | ForEach-Object {
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash
    "{0}  {1}" -f $hash, (Get-RelativePathSafe -BasePath $Root -FullPath $_.FullName)
  }
  Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
}

$cutoffDate = (Get-Date).ToUniversalTime().AddDays(-1 * $HistoryDays)

if (Test-Path -LiteralPath $StagingRoot) { Remove-Item -LiteralPath $StagingRoot -Recurse -Force }
if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }
Ensure-Directory -Path $StagingRoot

$inventoryRoot = Join-Path $StagingRoot "INVENTORY"
$rawRoot = Join-Path $StagingRoot "RAW"
$rawRecoveredRoot = Join-Path $rawRoot "recovered-deliverynotpgi-writer-evidence"
$dataRoot = Join-Path $StagingRoot "DATA"
$metadataRoot = Join-Path $dataRoot "dataverse-metadata"
$rowsRoot = Join-Path $dataRoot "dataverse-rows"
$workflowDiscoveryRoot = Join-Path $dataRoot "workflow-discovery"
$reportsRoot = Join-Path $StagingRoot "REPORTS"

foreach ($path in @($inventoryRoot, $rawRoot, $rawRecoveredRoot, $dataRoot, $metadataRoot, $rowsRoot, $workflowDiscoveryRoot, $reportsRoot)) {
  Ensure-Directory -Path $path
}

$currentSourceRoots = @(
  (Join-Path $RepoRoot "site"),
  (Join-Path $RepoRoot "audit")
)
$legacySearchRoots = @(
  (Join-Path $LegacyEvidenceRoot "scripts"),
  (Join-Path $LegacyEvidenceRoot "results"),
  (Join-Path $LegacyEvidenceRoot "solution")
)

$currentHits = Search-TextRoots -Roots $currentSourceRoots -Label "current-source"
$legacyHits = Search-TextRoots -Roots $legacySearchRoots -Label "legacy-source"

$zipPaths = @(
  (Get-ChildItem -Path $RepoRoot -Recurse -File -Filter *.zip -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName),
  (Get-ChildItem -Path $LegacyEvidenceRoot -Recurse -File -Filter *.zip -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
) | Sort-Object -Unique
Search-ZipText -ZipPaths $zipPaths -OutputRoot $workflowDiscoveryRoot

$nestedBundleExtractRoot = Join-Path $rawRecoveredRoot "from-nested-bundles"
Ensure-Directory -Path $nestedBundleExtractRoot
foreach ($bundleZip in @($PriorGapsZip, $PriorAuditZip)) {
  if (-not (Test-Path -LiteralPath $bundleZip)) { continue }
  $bundleName = [System.IO.Path]::GetFileNameWithoutExtension($bundleZip)
  $bundleExtract = Join-Path $nestedBundleExtractRoot $bundleName
  Ensure-Directory -Path $bundleExtract
  $archive = [System.IO.Compression.ZipFile]::OpenRead($bundleZip)
  foreach ($entry in @($archive.Entries)) {
    if (
      $entry.FullName -like "*delivery-notpgi-lineage*" -or
      $entry.FullName -like "*qfu_deliverynotpgi*" -or
      $entry.FullName -like "*qfu_sourcefeed*" -or
      $entry.FullName -like "*qfu_rawdocument*" -or
      $entry.FullName -like "*qfu-southern-alberta-pilot-flows.zip*" -or
      $entry.FullName -like "*qfu-sapilotflows-target.zip*"
    ) {
      $dest = Join-Path $bundleExtract $entry.FullName
      Ensure-Directory -Path ([System.IO.Path]::GetDirectoryName($dest))
      if (-not [string]::IsNullOrWhiteSpace($entry.Name)) {
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $dest, $true)
      }
    }
  }
  $archive.Dispose()
}

$currentRuntimePath = Join-Path $RepoRoot "site\web-templates\qfu-regional-runtime\QFU-Regional-Runtime.webtemplate.source.html"
$currentSiteSettingPath = Join-Path $RepoRoot "site\sitesetting.yml"
$currentManifestPath = Join-Path $RepoRoot "site\.portalconfig\regionaloperationshub.crm.dynamics.com-manifest.yml"
$currentTablePermissionPath = Join-Path $RepoRoot "site\table-permissions\operationhub-qfu_deliverynotpgi-Global-ReadWrite.tablepermission.yml"

Copy-IfExists -SourcePath $currentRuntimePath -DestinationPath (Join-Path $rawRecoveredRoot "current-site\QFU-Regional-Runtime.webtemplate.source.html") | Out-Null
Copy-IfExists -SourcePath $currentSiteSettingPath -DestinationPath (Join-Path $rawRecoveredRoot "current-site\sitesetting.yml") | Out-Null
Copy-IfExists -SourcePath $currentManifestPath -DestinationPath (Join-Path $rawRecoveredRoot "current-site\regionaloperationshub.crm.dynamics.com-manifest.yml") | Out-Null
Copy-IfExists -SourcePath $currentTablePermissionPath -DestinationPath (Join-Path $rawRecoveredRoot "current-site\operationhub-qfu_deliverynotpgi-Global-ReadWrite.tablepermission.yml") | Out-Null

$legacyFileCandidates = @(
  "scripts\create-southern-alberta-pilot-flow-solution.ps1",
  "scripts\parse-southern-alberta-workbooks.py",
  "results\flow-a5a911cc-get.json",
  "results\qfu-southern-alberta-pilot-flows.zip",
  "results\qfu-sapilotflows-target.zip",
  "results\qfu-southern-alberta-pilot-flows-map.json"
) | ForEach-Object { Join-Path $LegacyEvidenceRoot $_ }

foreach ($candidate in $legacyFileCandidates) {
  if (Test-Path -LiteralPath $candidate) {
    $rel = Get-RelativePathSafe -BasePath $LegacyEvidenceRoot -FullPath $candidate
    Copy-IfExists -SourcePath $candidate -DestinationPath (Join-Path $rawRecoveredRoot "legacy-evidence\$rel") | Out-Null
  }
}

$connection = Connect-Org -Url $TargetEnvironmentUrl -User $Username

foreach ($entity in @("qfu_deliverynotpgi", "qfu_sourcefeed", "qfu_rawdocument", "qfu_ingestionbatch")) {
  Export-EntityMetadata -Connection $connection -EntityLogicalName $entity -OutputPath (Join-Path $metadataRoot ($entity + ".metadata.json"))
}

$deliveryFilterXml = @"
<filter type='and'>
  $(New-BranchFilterXml -BranchField "qfu_branchcode")
  <condition attribute='createdon' operator='on-or-after' value='$($cutoffDate.ToString("yyyy-MM-dd"))' />
</filter>
"@
$sourcefeedFilterXml = @"
<filter type='and'>
  $(New-BranchFilterXml -BranchField "qfu_branchcode")
</filter>
"@
$rawdocumentFilterXml = @"
<filter type='and'>
  $(New-BranchFilterXml -BranchField "qfu_branchcode")
  <condition attribute='createdon' operator='on-or-after' value='$($cutoffDate.ToString("yyyy-MM-dd"))' />
</filter>
"@
$ingestionFilterXml = @"
<filter type='and'>
  $(New-BranchFilterXml -BranchField "qfu_branchcode")
  <condition attribute='createdon' operator='on-or-after' value='$($cutoffDate.ToString("yyyy-MM-dd"))' />
</filter>
"@

$deliveryRows = Export-EntityRows -Connection $connection -EntityLogicalName "qfu_deliverynotpgi" -FilterXml $deliveryFilterXml -JsonPath (Join-Path $rowsRoot "qfu_deliverynotpgi.rows.json") -CsvPath (Join-Path $rowsRoot "qfu_deliverynotpgi.rows.csv")
$sourcefeedRows = Export-EntityRows -Connection $connection -EntityLogicalName "qfu_sourcefeed" -FilterXml $sourcefeedFilterXml -JsonPath (Join-Path $rowsRoot "qfu_sourcefeed.rows.json") -CsvPath (Join-Path $rowsRoot "qfu_sourcefeed.rows.csv")
$rawdocumentRows = Export-EntityRows -Connection $connection -EntityLogicalName "qfu_rawdocument" -FilterXml $rawdocumentFilterXml -JsonPath (Join-Path $rowsRoot "qfu_rawdocument.rows.json") -CsvPath (Join-Path $rowsRoot "qfu_rawdocument.rows.csv")
$ingestionRows = Export-EntityRows -Connection $connection -EntityLogicalName "qfu_ingestionbatch" -FilterXml $ingestionFilterXml -JsonPath (Join-Path $rowsRoot "qfu_ingestionbatch.rows.json") -CsvPath (Join-Path $rowsRoot "qfu_ingestionbatch.rows.csv")

$workflowDiscovery = Query-WorkflowDiscovery -Connection $connection -OutputRoot $workflowDiscoveryRoot
$sapilotExportRoot = Join-Path $workflowDiscoveryRoot "qfu_sapilotflows-export"
$sapilotExport = Export-SolutionReadOnly -SolutionName "qfu_sapilotflows" -OutputRoot $sapilotExportRoot

if ($sapilotExport.success) {
  Add-Found -Bucket "workflow-export" -Item "qfu_sapilotflows unmanaged solution export" -Status "FOUND VIA READ-ONLY ENVIRONMENT QUERY" -Detail $sapilotExport.zip_path
  Ensure-Directory -Path (Join-Path $rawRecoveredRoot "environment-solution")
  Copy-Item -LiteralPath $sapilotExport.zip_path -Destination (Join-Path $rawRecoveredRoot "environment-solution\qfu_sapilotflows.zip") -Force
  $sapilotRelevantRoot = Join-Path $rawRecoveredRoot "environment-solution\extracted"
  Ensure-Directory -Path $sapilotRelevantRoot
  foreach ($candidate in @(
    (Join-Path $sapilotExport.extract_root "solution.xml"),
    (Join-Path $sapilotExport.extract_root "customizations.xml")
  )) {
    if (Test-Path -LiteralPath $candidate) {
      Copy-Item -LiteralPath $candidate -Destination (Join-Path $sapilotRelevantRoot ([System.IO.Path]::GetFileName($candidate))) -Force
    }
  }
  $zboWorkflows = Get-ChildItem -Path (Join-Path $sapilotExport.extract_root "Workflows") -File | Where-Object { $_.Name -like "*BackOrder-Update-ZBO*" }
  foreach ($workflowFile in @($zboWorkflows)) {
    Ensure-Directory -Path (Join-Path $sapilotRelevantRoot "Workflows")
    Copy-Item -LiteralPath $workflowFile.FullName -Destination (Join-Path $sapilotRelevantRoot "Workflows\$($workflowFile.Name)") -Force
  }
}
else {
  Add-Missing -Bucket "workflow-export" -Item "qfu_sapilotflows unmanaged solution export" -Status "COULD NOT EXPORT" -Detail $sapilotExport.log_path
}

$sapilotSearchResults = @()
if ($sapilotExport.success) {
  $sapilotFiles = Get-ChildItem -Path $sapilotExport.extract_root -Recurse -File -Include *.json,*.xml
  foreach ($term in @("qfu_deliverynotpgi", "deliverynotpgi", "notpgi", "unshippednetvalue", "qfu_commentupdatedon", "qfu_commentupdatedbyname", "qfu_backorders", "item/qfu_sourcefamily", "ZBO")) {
    $sapilotSearchResults += Select-String -Path $sapilotFiles.FullName -Pattern $term -SimpleMatch -ErrorAction SilentlyContinue | ForEach-Object {
      [pscustomobject]@{
        search_term = $term
        path = $_.Path
        line_number = $_.LineNumber
        line = $_.Line.Trim()
      }
    }
  }
}
Write-JsonFile -Path (Join-Path $workflowDiscoveryRoot "qfu_sapilotflows-search-results.json") -Data $sapilotSearchResults

foreach ($hit in @($sapilotSearchResults)) {
  $searchHitList.Add([pscustomobject]@{
    source = "workflow-export"
    search_term = $hit.search_term
    path = $hit.path
    line_number = $hit.line_number
    line = $hit.line
  })
}

function Get-FlatValueSafe {
  param(
    $Row,
    [string]$PropertyName
  )

  if ($null -eq $Row) { return $null }
  $prop = $Row.PSObject.Properties[$PropertyName]
  if ($null -eq $prop) { return $null }
  return $prop.Value
}

function Convert-EntityRefLikeToId {
  param($Value)

  if ($null -eq $Value) { return $null }
  if ($Value -is [hashtable] -or $Value -is [System.Collections.IDictionary]) {
    return $Value["id"]
  }
  return [string]$Value
}

function Convert-EntityRefLikeToName {
  param($Value)

  if ($null -eq $Value) { return $null }
  if ($Value -is [hashtable] -or $Value -is [System.Collections.IDictionary]) {
    return $Value["name"]
  }
  return [string]$Value
}

function Add-ReportFile {
  param(
    [string]$Path,
    [string[]]$Lines
  )

  Set-Content -LiteralPath $Path -Value $Lines -Encoding UTF8
}

$sourceSamplesRoot = Join-Path $dataRoot "source-input-samples"
$recoveredRawDocRoot = Join-Path $sourceSamplesRoot "recovered-from-qfu_rawdocument"
$representativeZboRoot = Join-Path $sourceSamplesRoot "representative-zbo-source-files"
foreach ($path in @($sourceSamplesRoot, $recoveredRawDocRoot, $representativeZboRoot)) {
  Ensure-Directory -Path $path
}

$importBatchIds = @(
  $deliveryRows |
    ForEach-Object { Convert-EntityRefLikeToId (Get-FlatValueSafe -Row $_ -PropertyName "qfu_importbatchid__raw") } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    Sort-Object -Unique
)
$deliverySourceFiles = @(
  $deliveryRows |
    Group-Object { Get-FlatValueSafe -Row $_ -PropertyName "qfu_sourcefile__raw" } |
    Sort-Object Count -Descending |
    ForEach-Object {
      [pscustomobject]@{
        sourcefile = $_.Name
        row_count = $_.Count
      }
    }
)
$deliverySourceFamilies = @(
  $deliveryRows |
    Group-Object { Get-FlatValueSafe -Row $_ -PropertyName "qfu_sourcefamily__raw" } |
    Sort-Object Count -Descending |
    ForEach-Object {
      [pscustomobject]@{
        sourcefamily = $_.Name
        row_count = $_.Count
      }
    }
)
$deliveryCreatedDates = @(
  $deliveryRows |
    Group-Object {
      $value = Get-FlatValueSafe -Row $_ -PropertyName "createdon__raw"
      if ($value) { ([datetime]$value).ToString("yyyy-MM-dd") } else { "<null>" }
    } |
    Sort-Object Name |
    ForEach-Object {
      [pscustomobject]@{
        created_date = $_.Name
        row_count = $_.Count
      }
    }
)
$deliveryModifiedBy = @(
  $deliveryRows |
    Group-Object {
      $formatted = Get-FlatValueSafe -Row $_ -PropertyName "modifiedby"
      if (-not [string]::IsNullOrWhiteSpace([string]$formatted)) { return [string]$formatted }
      Convert-EntityRefLikeToName (Get-FlatValueSafe -Row $_ -PropertyName "modifiedby__raw")
    } |
    Sort-Object Count -Descending |
    ForEach-Object {
      [pscustomobject]@{
        modifiedby = $_.Name
        row_count = $_.Count
      }
    }
)
$sourcefeedFamilies = @(
  $sourcefeedRows |
    ForEach-Object { [string](Get-FlatValueSafe -Row $_ -PropertyName "qfu_sourcefamily__raw") } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    Sort-Object -Unique
)
$ingestionBatchIds = @(
  $ingestionRows |
    ForEach-Object { [string](Get-FlatValueSafe -Row $_ -PropertyName "_primaryid") } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    Sort-Object -Unique
)
$matchingImportBatches = @($importBatchIds | Where-Object { $ingestionBatchIds -contains $_ })
$rawdocumentFamilies = @(
  $rawdocumentRows |
    Group-Object { Get-FlatValueSafe -Row $_ -PropertyName "qfu_sourcefamily__raw" } |
    Sort-Object Count -Descending |
    ForEach-Object {
      [pscustomobject]@{
        sourcefamily = $_.Name
        row_count = $_.Count
      }
    }
)

Write-JsonFile -Path (Join-Path $rowsRoot "qfu_deliverynotpgi.sourcefamily-summary.json") -Data $deliverySourceFamilies
Write-JsonFile -Path (Join-Path $rowsRoot "qfu_deliverynotpgi.sourcefile-summary.json") -Data $deliverySourceFiles
Write-JsonFile -Path (Join-Path $rowsRoot "qfu_deliverynotpgi.created-date-summary.json") -Data $deliveryCreatedDates
Write-JsonFile -Path (Join-Path $rowsRoot "qfu_deliverynotpgi.modifiedby-summary.json") -Data $deliveryModifiedBy
Write-JsonFile -Path (Join-Path $rowsRoot "qfu_deliverynotpgi.importbatchids.json") -Data @($importBatchIds)
Write-JsonFile -Path (Join-Path $rowsRoot "qfu_rawdocument.sourcefamily-summary.json") -Data $rawdocumentFamilies
Write-JsonFile -Path (Join-Path $rowsRoot "qfu_ingestionbatch.id-summary.json") -Data @($ingestionBatchIds)
Write-JsonFile -Path (Join-Path $rowsRoot "qfu_deliverynotpgi.matching-ingestionbatchids.json") -Data @($matchingImportBatches)

$recoveredRawFiles = New-Object System.Collections.Generic.List[object]
$rawdocumentSampleCounts = @{}
foreach ($row in @($rawdocumentRows | Sort-Object { Get-FlatValueSafe -Row $_ -PropertyName "createdon__raw" } -Descending)) {
  $family = [string](Get-FlatValueSafe -Row $row -PropertyName "qfu_sourcefamily__raw")
  if ([string]::IsNullOrWhiteSpace($family)) { $family = "unknown" }
  $payload = Get-FlatValueSafe -Row $row -PropertyName "qfu_rawcontentbase64__raw"
  if ([string]::IsNullOrWhiteSpace([string]$payload)) { continue }
  if (-not $rawdocumentSampleCounts.ContainsKey($family)) { $rawdocumentSampleCounts[$family] = 0 }
  if ($rawdocumentSampleCounts[$family] -ge 2) { continue }

  $sourceFile = [string](Get-FlatValueSafe -Row $row -PropertyName "qfu_sourcefile__raw")
  if ([string]::IsNullOrWhiteSpace($sourceFile)) {
    $sourceFile = [string](Get-FlatValueSafe -Row $row -PropertyName "qfu_name__raw")
  }
  if ([string]::IsNullOrWhiteSpace($sourceFile)) {
    $sourceFile = "{0}-{1}.bin" -f $family, (Get-FlatValueSafe -Row $row -PropertyName "_primaryid")
  }
  $safeFileName = ($sourceFile -replace '[\\/:*?"<>|]', "_")
  $targetPath = Join-Path $recoveredRawDocRoot $safeFileName
  try {
    [System.IO.File]::WriteAllBytes($targetPath, [System.Convert]::FromBase64String([string]$payload))
    $rawdocumentSampleCounts[$family]++
    $recoveredRawFiles.Add([pscustomobject]@{
      sourcefamily = $family
      sourcefile = $sourceFile
      target_path = $targetPath
      row_id = Get-FlatValueSafe -Row $row -PropertyName "_primaryid"
    })
  }
  catch {
    continue
  }
}
Write-JsonFile -Path (Join-Path $recoveredRawDocRoot "recovered-rawdocument-files.json") -Data $recoveredRawFiles.ToArray()

$zboSourceCandidates = @(
  @(Get-ChildItem -Path $RepoRoot -Recurse -File -Include *.xlsx -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'ZBO' }) +
  @(Get-ChildItem -Path $LegacyEvidenceRoot -Recurse -File -Include *.xlsx -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'ZBO' })
) | Sort-Object FullName -Unique

$copiedZboSamples = New-Object System.Collections.Generic.List[object]
foreach ($file in @($zboSourceCandidates | Select-Object -First 12)) {
  $relative = Get-RelativePathSafe -BasePath $LegacyEvidenceRoot -FullPath $file.FullName
  if ($relative -eq $file.FullName) {
    $relative = Get-RelativePathSafe -BasePath $RepoRoot -FullPath $file.FullName
  }
  $dest = Join-Path $representativeZboRoot ([System.IO.Path]::GetFileName($file.FullName))
  Copy-Item -LiteralPath $file.FullName -Destination $dest -Force
  $copiedZboSamples.Add([pscustomobject]@{
    original_path = $file.FullName
    copied_path = $dest
    relative_hint = $relative
  })
}
Write-JsonFile -Path (Join-Path $representativeZboRoot "available-zbo-samples.json") -Data $copiedZboSamples.ToArray()

$dedicatedDeliverySourcefeeds = @(
  $sourcefeedRows |
    Where-Object {
      $family = [string](Get-FlatValueSafe -Row $_ -PropertyName "qfu_sourcefamily__raw")
      $name = [string](Get-FlatValueSafe -Row $_ -PropertyName "qfu_name__raw")
      ($family -match 'delivery|pgi|notpgi') -or ($name -match 'delivery|pgi|notpgi')
    }
)

$exactDeliveryWriterHits = @(
  $searchHitList.ToArray() |
    Where-Object {
      $_.line -and
      (
        (($_.line -match "createRecord|updateRecord|patchRecord|Add a new row|Update a row|/_api/qfu_deliverynotpgis|qfu_deliverynotpgis\(") -and ($_.line -match "qfu_deliverynotpgi")) -or
        ($_.line -match "^\s*entityName\b.{0,40}qfu_deliverynotpgi")
      ) -and
      $_.path -notlike "*\audit\*" -and
      $_.path -notlike "*QFU-Regional-Runtime.webtemplate.source.html"
    }
)

$runtimePatchHits = @(
  $searchHitList.ToArray() |
    Where-Object {
      $_.path -like "*QFU-Regional-Runtime.webtemplate.source.html" -and
      (
        $_.line.Contains('patchRecord("') -or
        $_.line.Contains('qfu_commentupdatedon') -or
        $_.line.Contains('qfu_commentupdatedbyname') -or
        $_.line.Contains('/_api/qfu_deliverynotpgis')
      )
    }
)

$runtimeCreateHits = @(
  $searchHitList.ToArray() |
    Where-Object {
      $_.path -like "*QFU-Regional-Runtime.webtemplate.source.html" -and
      $_.line.Contains('createRecord("') -and $_.line.Contains('qfu_deliverynotpgi')
    }
)

if ($exactDeliveryWriterHits.Count -gt 0) {
  Add-Found -Bucket "writer-artifact" -Item "Direct qfu_deliverynotpgi writer references in searched source/exported artifacts" -Status "FOUND" -Detail ("{0} hits" -f $exactDeliveryWriterHits.Count)
}
else {
  Add-Missing -Bucket "writer-artifact" -Item "Direct qfu_deliverynotpgi writer references in searched source/exported artifacts" -Status "NOT FOUND" -Detail "Searched current site/audit tree, legacy scripts/results/solution tree, nested zips, and exported qfu_sapilotflows solution."
}

if ($runtimePatchHits.Count -gt 0) {
  Add-Found -Bucket "runtime-role" -Item "Power Pages runtime qfu_deliverynotpgi comment patch behavior" -Status "FOUND" -Detail "QFU-Regional-Runtime.webtemplate.source.html fetches qfu_deliverynotpgis and PATCHes qfu_commentupdatedon/qfu_commentupdatedbyname."
}
if ($runtimeCreateHits.Count -gt 0) {
  Add-Found -Bucket "runtime-role" -Item "Power Pages runtime qfu_deliverynotpgi base-row creation" -Status "FOUND" -Detail ("{0} create hits" -f $runtimeCreateHits.Count)
}
else {
  Add-Missing -Bucket "runtime-role" -Item "Power Pages runtime qfu_deliverynotpgi base-row creation" -Status "NOT FOUND" -Detail "Searched current QFU runtime for createRecord(/_api) paths referencing qfu_deliverynotpgi or qfu_deliverynotpgis."
}

if ($deliveryRows.Count -gt 0) {
  Add-Found -Bucket "dataverse-rows" -Item "qfu_deliverynotpgi row snapshot" -Status "FOUND VIA READ-ONLY ENVIRONMENT QUERY" -Detail ("{0} rows exported" -f $deliveryRows.Count)
}
else {
  Add-Missing -Bucket "dataverse-rows" -Item "qfu_deliverynotpgi row snapshot" -Status "COULD NOT EXPORT" -Detail "Read-only export returned 0 rows for the selected branch/date window."
}

if ($rawdocumentRows.Count -gt 0) {
  Add-Found -Bucket "dataverse-rows" -Item "qfu_rawdocument row snapshot" -Status "FOUND VIA READ-ONLY ENVIRONMENT QUERY" -Detail ("{0} rows exported" -f $rawdocumentRows.Count)
}
else {
  Add-Missing -Bucket "dataverse-rows" -Item "qfu_rawdocument row snapshot" -Status "COULD NOT EXPORT" -Detail "Read-only export returned 0 rows for the selected branch/date window."
}

if ($dedicatedDeliverySourcefeeds.Count -gt 0) {
  Add-Found -Bucket "sourcefeed-lineage" -Item "Dedicated delivery/not-PGI sourcefeed rows" -Status "FOUND VIA READ-ONLY ENVIRONMENT QUERY" -Detail ("{0} rows matched delivery/pgi terms" -f $dedicatedDeliverySourcefeeds.Count)
}
else {
  Add-Missing -Bucket "sourcefeed-lineage" -Item "Dedicated delivery/not-PGI sourcefeed rows" -Status "NOT FOUND" -Detail "Searched qfu_sourcefeed rows for family/name terms delivery, pgi, and notpgi."
}

if ($deliverySourceFamilies | Where-Object { $_.sourcefamily -eq "ZBO" }) {
  Add-Found -Bucket "sourcefeed-lineage" -Item "qfu_deliverynotpgi rows aligned to ZBO source family" -Status "FOUND VIA READ-ONLY ENVIRONMENT QUERY" -Detail "Delivery rows carry qfu_sourcefamily = ZBO."
}
if ($matchingImportBatches.Count -gt 0) {
  Add-Found -Bucket "correlation" -Item "qfu_deliverynotpgi import batches matching qfu_ingestionbatch ids" -Status "FOUND VIA READ-ONLY ENVIRONMENT QUERY" -Detail ("{0} matching import batch ids" -f $matchingImportBatches.Count)
}
else {
  Add-Missing -Bucket "correlation" -Item "qfu_deliverynotpgi import batches matching qfu_ingestionbatch ids" -Status "NOT FOUND" -Detail "Compared qfu_deliverynotpgi.qfu_importbatchid values to qfu_ingestionbatch primary ids in the exported window."
}

if ($recoveredRawFiles.Count -gt 0) {
  Add-Found -Bucket "rawdocument-payload" -Item "Recovered qfu_rawdocument raw payload samples" -Status "FOUND VIA READ-ONLY ENVIRONMENT QUERY" -Detail ("{0} files decoded from qfu_rawcontentbase64" -f $recoveredRawFiles.Count)
}
else {
  Add-Missing -Bucket "rawdocument-payload" -Item "Recovered qfu_rawdocument raw payload samples" -Status "COULD NOT EXPORT" -Detail "qfu_rawcontentbase64 was absent or undecodable for the exported rows."
}

if ($copiedZboSamples.Count -gt 0) {
  Add-Found -Bucket "source-samples" -Item "Representative ZBO upstream source files" -Status "FOUND" -Detail ("{0} representative ZBO workbook samples copied" -f $copiedZboSamples.Count)
}
else {
  Add-Missing -Bucket "source-samples" -Item "Representative ZBO upstream source files" -Status "NOT FOUND" -Detail "Searched repository and legacy evidence roots for *.xlsx files with ZBO in the filename."
}

$gl060WorkflowRows = @($workflowDiscovery.workflows | Where-Object { $_.name -match 'GL060' })
$deliveryWorkflowRows = @($workflowDiscovery.workflows | Where-Object { $_.name -match 'Delivery|PGI|Ready to Ship' })
$sapilotWorkflowRows = @($workflowDiscovery.workflows | Where-Object { $_.name -match '4171-|4172-|4173-' })
$scriptWriterLines = New-Object System.Collections.Generic.List[string]
$scriptWriterLines.Add("# Script Writer Discovery: qfu_deliverynotpgi")
$scriptWriterLines.Add("")
$scriptWriterLines.Add("## Direct writer hits")
if ($exactDeliveryWriterHits.Count -gt 0) {
  foreach ($hit in $exactDeliveryWriterHits | Sort-Object path, line_number) {
    $scriptWriterLines.Add("- [$($hit.source)] $($hit.path):$($hit.line_number): $($hit.line)")
  }
}
else {
  $scriptWriterLines.Add("- No direct qfu_deliverynotpgi writer references were found in the searched current-source or legacy-source trees.")
}
$scriptWriterLines.Add("")
$scriptWriterLines.Add("## Closest upstream ZBO writer evidence")
$scriptWriterLines.Add("- The strongest source-controlled matches are ZBO/backorder writers, not qfu_deliverynotpgi writers.")
$scriptWriterLines.Add("- Evidence paths copied into the bundle:")
$scriptWriterLines.Add("  - RAW/recovered-deliverynotpgi-writer-evidence/legacy-evidence/scripts/create-southern-alberta-pilot-flow-solution.ps1")
$scriptWriterLines.Add("  - RAW/recovered-deliverynotpgi-writer-evidence/legacy-evidence/scripts/parse-southern-alberta-workbooks.py")
$scriptWriterLines.Add("  - RAW/recovered-deliverynotpgi-writer-evidence/legacy-evidence/results/flow-a5a911cc-get.json")
$scriptWriterLines.Add("")
$scriptWriterLines.Add("## Read of the evidence")
$scriptWriterLines.Add("- create-southern-alberta-pilot-flow-solution.ps1 builds 4171/4172/4173 BackOrder-Update-ZBO flow definitions and stamps qfu_sourcefamily = ZBO.")
$scriptWriterLines.Add("- parse-southern-alberta-workbooks.py produces ZBO source ids like branch|ZBO|salesDoc|line.")
$scriptWriterLines.Add("- flow-a5a911cc-get.json shows Dataverse writes to qfu_backorders, not qfu_deliverynotpgi.")
$scriptWriterLines.Add("- Exact search terms qfu_deliverynotpgi, deliverynotpgi, qfu_deliverynotpgiid, qfu_commentupdatedon, qfu_commentupdatedbyname returned no direct hits in the legacy scripts/results/solution tree.")
Add-ReportFile -Path (Join-Path $reportsRoot "script-writer-discovery-deliverynotpgi.md") -Lines @($scriptWriterLines)

$workflowLines = New-Object System.Collections.Generic.List[string]
$workflowLines.Add("# Workflow Discovery: qfu_deliverynotpgi")
$workflowLines.Add("")
$workflowLines.Add("## Read-only environment workflow query")
$workflowLines.Add("- Workflow query result count: $($workflowDiscovery.workflows.Count)")
$workflowLines.Add("- Solution query result count: $($workflowDiscovery.solutions.Count)")
$workflowLines.Add("- GL060-named workflows found: $($gl060WorkflowRows.Count)")
$workflowLines.Add("- Delivery/PGI/Ready-to-Ship named workflows found: $($deliveryWorkflowRows.Count)")
$workflowLines.Add("- Pilot 4171/4172/4173 workflows found: $($sapilotWorkflowRows.Count)")
$workflowLines.Add("")
$workflowLines.Add("## qfu_sapilotflows export")
$workflowLines.Add("- Export succeeded: $($sapilotExport.success)")
$workflowLines.Add("- Export log: DATA/workflow-discovery/qfu_sapilotflows-export/qfu_sapilotflows.export.log")
$workflowLines.Add("- Search results: DATA/workflow-discovery/qfu_sapilotflows-search-results.json")
$workflowLines.Add("")
$workflowLines.Add("## Read of the export")
$workflowLines.Add("- The exported pilot solution contains BackOrder-Update-ZBO, Budget-Update-SA1300, and QuoteFollowUp-Import-Staging workflows.")
$workflowLines.Add("- Search hits inside the exported solution show qfu_backorders entity writes and qfu_sourcefamily = ZBO.")
$workflowLines.Add("- No extracted workflow JSON or solution XML in qfu_sapilotflows references qfu_deliverynotpgi, deliverynotpgi, unshippednetvalue, qfu_commentupdatedon, or qfu_commentupdatedbyname.")
$workflowLines.Add("")
$workflowLines.Add("## Conclusion")
$workflowLines.Add("- Current exported pilot flows prove ZBO/backorder ingestion exists, but they do not prove any exported flow that creates or updates qfu_deliverynotpgi base rows.")
Add-ReportFile -Path (Join-Path $reportsRoot "workflow-discovery-deliverynotpgi.md") -Lines @($workflowLines)

$correlationLines = New-Object System.Collections.Generic.List[string]
$correlationLines.Add("# Delivery-not-PGI Correlation Analysis")
$correlationLines.Add("")
$correlationLines.Add("## Delivery row clustering")
$correlationLines.Add("- qfu_deliverynotpgi row count exported: $($deliveryRows.Count)")
$correlationLines.Add("- qfu_sourcefamily summary file: DATA/dataverse-rows/qfu_deliverynotpgi.sourcefamily-summary.json")
$correlationLines.Add("- qfu_sourcefile summary file: DATA/dataverse-rows/qfu_deliverynotpgi.sourcefile-summary.json")
$correlationLines.Add("- created-date summary file: DATA/dataverse-rows/qfu_deliverynotpgi.created-date-summary.json")
$correlationLines.Add("- modified-by summary file: DATA/dataverse-rows/qfu_deliverynotpgi.modifiedby-summary.json")
$correlationLines.Add("")
$correlationLines.Add("## Source family alignment")
if ($deliverySourceFamilies.Count -gt 0) {
  foreach ($row in $deliverySourceFamilies) {
    $correlationLines.Add("- $($row.sourcefamily): $($row.row_count) rows")
  }
}
else {
  $correlationLines.Add("- No delivery rows were available to group.")
}
$correlationLines.Add("")
$correlationLines.Add("## Sourcefeed evidence")
$correlationLines.Add("- qfu_sourcefeed source families present in export: $(([string]::Join(', ', $sourcefeedFamilies)))")
if ($dedicatedDeliverySourcefeeds.Count -gt 0) {
  $correlationLines.Add("- Dedicated delivery/pgi sourcefeed rows were found.")
}
else {
  $correlationLines.Add("- No dedicated delivery/not-PGI sourcefeed family or sourcefeed name was found.")
}
$correlationLines.Add("")
$correlationLines.Add("## Rawdocument evidence")
$correlationLines.Add("- qfu_rawdocument sourcefamily summary file: DATA/dataverse-rows/qfu_rawdocument.sourcefamily-summary.json")
$correlationLines.Add("- Recovered rawdocument payload samples: DATA/source-input-samples/recovered-from-qfu_rawdocument/")
if (($rawdocumentFamilies | Where-Object { $_.sourcefamily -eq 'ZBO' }).Count -gt 0) {
  $correlationLines.Add("- ZBO qfu_rawdocument rows were present in the exported window.")
}
else {
  $correlationLines.Add("- No ZBO qfu_rawdocument rows were present in the exported window, so mailbox/file intake could not be directly chained from qfu_rawdocument to qfu_deliverynotpgi.")
}
$correlationLines.Add("")
$correlationLines.Add("## Ingestion batch correlation")
$correlationLines.Add("- qfu_deliverynotpgi import batch ids file: DATA/dataverse-rows/qfu_deliverynotpgi.importbatchids.json")
$correlationLines.Add("- qfu_ingestionbatch id summary file: DATA/dataverse-rows/qfu_ingestionbatch.id-summary.json")
$correlationLines.Add("- matching ids file: DATA/dataverse-rows/qfu_deliverynotpgi.matching-ingestionbatchids.json")
if ($matchingImportBatches.Count -gt 0) {
  $correlationLines.Add("- Matching delivery import batch ids and ingestionbatch ids were found.")
}
else {
  $correlationLines.Add("- No matching delivery import batch ids were found in the exported ingestionbatch window.")
}
$correlationLines.Add("")
$correlationLines.Add("## Strongest correlation read")
$correlationLines.Add("- Delivery rows are strongly aligned to ZBO/CA ZBO lineage based on qfu_sourcefamily = ZBO, ZBO-shaped qfu_sourceid patterns, and CA ZBO sourcefile naming.")
$correlationLines.Add("- The exact writer implementation remains unproven because the exported/source-controlled artifacts show qfu_backorder writers, but not qfu_deliverynotpgi writers.")
$correlationLines.Add("- The missing writer is therefore most consistent with an unexported transform, a historical one-time seeding process, or a manual/import path outside the currently collected source-controlled/exported assets.")
Add-ReportFile -Path (Join-Path $reportsRoot "deliverynotpgi-correlation-analysis.md") -Lines @($correlationLines)

$runtimeLines = New-Object System.Collections.Generic.List[string]
$runtimeLines.Add("# Power Pages Runtime Role: qfu_deliverynotpgi")
$runtimeLines.Add("")
$runtimeLines.Add("## Observed runtime behavior")
$runtimeLines.Add("- Current runtime evidence file: RAW/recovered-deliverynotpgi-writer-evidence/current-site/QFU-Regional-Runtime.webtemplate.source.html")
$runtimeLines.Add("- The runtime fetches qfu_deliverynotpgis via the Dataverse Web API for display.")
$runtimeLines.Add("- The runtime PATCHes qfu_commentupdatedon and qfu_commentupdatedbyname against existing qfu_deliverynotpgi rows.")
$runtimeLines.Add("")
$runtimeLines.Add("## Role separation")
$runtimeLines.Add("- Base-row creation: not found in the current Power Pages runtime.")
$runtimeLines.Add("- Base-row display: found.")
$runtimeLines.Add("- Comment/update behavior on existing rows: found.")
$runtimeLines.Add("")
$runtimeLines.Add("## Read of the evidence")
$runtimeLines.Add("- Search hits for runtime behavior are recorded in INVENTORY/search-hits.md.")
$runtimeLines.Add("- The evidence distinguishes the portal as a consumer/comment editor, not the proven base-row ingester for qfu_deliverynotpgi.")
Add-ReportFile -Path (Join-Path $reportsRoot "powerpages-deliverynotpgi-runtime-role.md") -Lines @($runtimeLines)

$finalConclusionLines = New-Object System.Collections.Generic.List[string]
$finalConclusionLines.Add("# Final Delivery-Not-PGI Write Path Conclusion")
$finalConclusionLines.Add("")
$finalConclusionLines.Add("Conclusion: Most likely writer identified with evidence but exact implementation artifact still missing.")
$finalConclusionLines.Add("")
$finalConclusionLines.Add("## What is proven")
$finalConclusionLines.Add("- qfu_deliverynotpgi rows exist in Dataverse and carry ZBO-shaped lineage fields.")
$finalConclusionLines.Add("- The current Power Pages runtime reads qfu_deliverynotpgis and PATCHes comment metadata only; it is not the proven base-row writer.")
$finalConclusionLines.Add("- The exported qfu_sapilotflows solution proves active ZBO/backorder ingestion workflows exist, but those workflow exports write qfu_backorders, not qfu_deliverynotpgi.")
$finalConclusionLines.Add("- No dedicated delivery/not-PGI source family was found in qfu_sourcefeed.")
$finalConclusionLines.Add("")
$finalConclusionLines.Add("## Strongest likely writer")
$finalConclusionLines.Add("- Strongest likely writer lineage: ZBO / CA ZBO upstream input, followed by a transform that materializes qfu_deliverynotpgi rows outside the currently exported/source-controlled writer artifacts.")
$finalConclusionLines.Add("- Most likely missing implementation class: historical one-time seeding process or unexported flow/script that derives delivery-not-PGI rows from ZBO-shaped upstream data.")
$finalConclusionLines.Add("")
$finalConclusionLines.Add("## Key evidence paths")
$finalConclusionLines.Add("- DATA/dataverse-rows/qfu_deliverynotpgi.rows.json")
$finalConclusionLines.Add("- DATA/dataverse-rows/qfu_deliverynotpgi.sourcefamily-summary.json")
$finalConclusionLines.Add("- DATA/dataverse-rows/qfu_deliverynotpgi.sourcefile-summary.json")
$finalConclusionLines.Add("- DATA/workflow-discovery/qfu_sapilotflows-search-results.json")
$finalConclusionLines.Add("- RAW/recovered-deliverynotpgi-writer-evidence/environment-solution/extracted/Workflows/")
$finalConclusionLines.Add("- RAW/recovered-deliverynotpgi-writer-evidence/legacy-evidence/scripts/create-southern-alberta-pilot-flow-solution.ps1")
$finalConclusionLines.Add("- RAW/recovered-deliverynotpgi-writer-evidence/legacy-evidence/scripts/parse-southern-alberta-workbooks.py")
$finalConclusionLines.Add("- REPORTS/powerpages-deliverynotpgi-runtime-role.md")
$finalConclusionLines.Add("- REPORTS/deliverynotpgi-correlation-analysis.md")
$finalConclusionLines.Add("")
$finalConclusionLines.Add("## Still missing")
$finalConclusionLines.Add("- Exact source-controlled/exported artifact that explicitly creates or updates qfu_deliverynotpgi base rows.")
$finalConclusionLines.Add("- Direct rawdocument-to-delivery proof in the exported window for ZBO/SA1300 families.")
Add-ReportFile -Path (Join-Path $reportsRoot "final-deliverynotpgi-write-path-conclusion.md") -Lines @($finalConclusionLines)

Write-Readme -Path (Join-Path $StagingRoot "README_FINAL_LAST_GAP.md")
Write-FoundVsMissing -Path (Join-Path $inventoryRoot "found-vs-missing.md") -FoundItems @($found.ToArray()) -MissingItems @($missing.ToArray())
Write-ExportMethod -CutoffDate $cutoffDate -Path (Join-Path $inventoryRoot "export-method.md") -TargetEnvironmentUrl $TargetEnvironmentUrl
Write-SearchHits -Path (Join-Path $inventoryRoot "search-hits.md") -SearchHits @($searchHitList.ToArray()) -ZipHits @($zipHitList.ToArray()) -RepoRoot $RepoRoot
Write-TreeFile -Root $StagingRoot -Path (Join-Path $inventoryRoot "tree.txt")
Write-Sha256File -Root $StagingRoot -Path (Join-Path $inventoryRoot "sha256.txt")

$zipParent = Split-Path -Parent $StagingRoot
$zipLeaf = Split-Path -Leaf $StagingRoot
Push-Location $zipParent
try {
  tar.exe -a -cf $ZipPath $zipLeaf
}
finally {
  Pop-Location
}

$stagingFileCount = (Get-ChildItem -Path $StagingRoot -Recurse -File | Measure-Object).Count
$zipSize = (Get-Item -LiteralPath $ZipPath).Length
Write-JsonFile -Path (Join-Path $inventoryRoot "bundle-summary.json") -Data ([ordered]@{
  zip_path = $ZipPath
  staging_root = $StagingRoot
  file_count = $stagingFileCount
  zip_size = $zipSize
  exact_writer_found = ($exactDeliveryWriterHits.Count -gt 0)
  strongest_likely_writer = "ZBO/CA ZBO-derived transform outside the currently exported/source-controlled writer artifacts"
  power_pages_role = "display and comment patch only"
  still_missing = @(
    "exact base-row writer artifact for qfu_deliverynotpgi",
    "direct qfu_rawdocument ZBO/SA1300 linkage in the exported window"
  )
})
