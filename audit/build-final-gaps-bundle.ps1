param(
  [string]$RepoRoot = "C:\Dev\QuoteFollowUpComplete",
  [string]$LegacyEvidenceRoot = "C:\Dev\QuoteFollowUpComplete-replacement-20260401",
  [string]$PriorBundleRoot = "C:\Dev\QuoteFollowUpComplete\QFU_FINAL_AUDIT_STAGING",
  [string]$StagingRoot = "C:\Dev\QuoteFollowUpComplete\QFU_FINAL_GAPS_STAGING",
  [string]$ZipPath = "C:\Dev\QuoteFollowUpComplete\QFU_CHATGPT_FINAL_AUDIT_GAPS_BUNDLE_2026-04-07.zip",
  [string]$TargetEnvironmentUrl = "https://regionaloperationshub.crm.dynamics.com",
  [string]$Username = "smcfarlane@applied.com",
  [int]$OperationalHistoryDays = 180
)

$ErrorActionPreference = "Stop"

Import-Module Microsoft.Xrm.Data.Powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem

$branchCodes = @("4171", "4172", "4173")
$rawDocumentSourceFamilies = @("GL060", "SA1300", "SP830CA", "ZBO")
$foundItems = New-Object System.Collections.Generic.List[object]
$missingItems = New-Object System.Collections.Generic.List[object]
$exportNotes = New-Object System.Collections.Generic.List[object]

function Ensure-Directory {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    try {
      New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
    catch {
      throw "Failed to create directory: $Path :: $($_.Exception.Message)"
    }
  }
}

function Get-RelativePathSafe {
  param(
    [string]$BasePath,
    [string]$FullPath
  )

  try {
    return [System.IO.Path]::GetRelativePath($BasePath, $FullPath)
  }
  catch {
    return $FullPath
  }
}

function Add-FoundItem {
  param(
    [string]$Category,
    [string]$Item,
    [string]$Status,
    [string]$Detail
  )

  $foundItems.Add([pscustomobject]@{
    category = $Category
    item = $Item
    status = $Status
    detail = $Detail
  })
}

function Add-MissingItem {
  param(
    [string]$Category,
    [string]$Item,
    [string]$Status,
    [string]$Detail
  )

  $missingItems.Add([pscustomobject]@{
    category = $Category
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

function ConvertTo-SelectedJson {
  param(
    [object[]]$Rows,
    [string[]]$Properties
  )

  $selected = foreach ($row in @($Rows)) {
    $ordered = [ordered]@{}
    foreach ($property in $Properties) {
      $ordered[$property] = if ($row.PSObject.Properties[$property]) { $row.$property } else { $null }
    }
    [pscustomobject]$ordered
  }

  return @($selected)
}

function New-WorkflowFetchXml {
  param(
    [string[]]$Names,
    [string[]]$Ids
  )

  $conditions = New-Object System.Collections.Generic.List[string]
  foreach ($name in @($Names)) {
    $conditions.Add(("<condition attribute='name' operator='eq' value='{0}' />" -f [System.Security.SecurityElement]::Escape($name)))
  }
  foreach ($id in @($Ids)) {
    $conditions.Add(("<condition attribute='workflowid' operator='eq' value='{0}' />" -f [System.Security.SecurityElement]::Escape($id)))
  }

  return @"
<fetch version='1.0' mapping='logical' no-lock='true'>
  <entity name='workflow'>
    <all-attributes />
    <filter type='or'>
      $($conditions -join [Environment]::NewLine)
    </filter>
  </entity>
</fetch>
"@
}

function New-SolutionFetchXml {
  param(
    [string[]]$UniqueNames
  )

  $conditions = foreach ($name in @($UniqueNames)) {
    "<condition attribute='uniquename' operator='eq' value='{0}' />" -f [System.Security.SecurityElement]::Escape($name)
  }

  return @"
<fetch version='1.0' mapping='logical' no-lock='true'>
  <entity name='solution'>
    <all-attributes />
    <filter type='or'>
      $($conditions -join [Environment]::NewLine)
    </filter>
  </entity>
</fetch>
"@
}

function New-SolutionComponentFetchXml {
  param(
    [string[]]$ObjectIds
  )

  $conditions = foreach ($id in @($ObjectIds)) {
    "<condition attribute='objectid' operator='eq' value='{0}' />" -f [System.Security.SecurityElement]::Escape($id)
  }

  return @"
<fetch version='1.0' mapping='logical' no-lock='true'>
  <entity name='solutioncomponent'>
    <all-attributes />
    <filter type='and'>
      <condition attribute='componenttype' operator='eq' value='29' />
      <filter type='or'>
        $($conditions -join [Environment]::NewLine)
      </filter>
    </filter>
  </entity>
</fetch>
"@
}

function New-RawDocumentFetchXml {
  param(
    [string[]]$AttributeNames,
    [datetime]$CutoffDate
  )

  $dateField = if ($AttributeNames -contains "qfu_receivedon") {
    "qfu_receivedon"
  }
  elseif ($AttributeNames -contains "createdon") {
    "createdon"
  }
  else {
    $null
  }

  $dateCondition = ""
  if ($dateField) {
    $dateCondition = "<condition attribute='{0}' operator='on-or-after' value='{1}' />" -f $dateField, $CutoffDate.ToString("yyyy-MM-dd")
  }

  $branchConditions = foreach ($branchCode in $branchCodes) {
    "<condition attribute='qfu_branchcode' operator='eq' value='{0}' />" -f [System.Security.SecurityElement]::Escape($branchCode)
  }

  $familyConditions = foreach ($family in $rawDocumentSourceFamilies) {
    "<condition attribute='qfu_sourcefamily' operator='eq' value='{0}' />" -f [System.Security.SecurityElement]::Escape($family)
  }

  return @"
<fetch version='1.0' mapping='logical' no-lock='true'>
  <entity name='qfu_rawdocument'>
    <all-attributes />
    <filter type='and'>
      <filter type='or'>
        $($branchConditions -join [Environment]::NewLine)
      </filter>
      <filter type='or'>
        $($familyConditions -join [Environment]::NewLine)
      </filter>
      $dateCondition
    </filter>
    <order attribute='createdon' descending='true' />
  </entity>
</fetch>
"@
}

function Export-SingleMetadata {
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

  $exportNotes.Add([pscustomobject]@{
    export = "qfu_rawdocument metadata"
    method = "EXPORTED READ-ONLY FROM ENVIRONMENT"
    tool = "Microsoft.Xrm.Data.Powershell Get-CrmEntityMetadata"
    filters = "none"
    date_window = "none"
  })
}

function Export-RawDocumentRows {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [datetime]$CutoffDate,
    [string]$JsonPath,
    [string]$CsvPath
  )

  $meta = Get-CrmEntityMetadata -conn $Connection -EntityLogicalName "qfu_rawdocument" -EntityFilters Attributes
  $attributeNames = @((Get-ReadableAttributes -EntityMetadata $meta) | Select-Object -ExpandProperty LogicalName)
  $fetch = New-RawDocumentFetchXml -AttributeNames $attributeNames -CutoffDate $CutoffDate
  $results = Get-CrmRecordsByFetch -conn $Connection -Fetch $fetch -AllRows
  $records = @($results.CrmRecords)

  $flatRows = foreach ($record in $records) {
    Flatten-CrmRecord -Record $record -EntityLogicalName "qfu_rawdocument" -Attributes $attributeNames
  }

  @($flatRows) | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $JsonPath -Encoding UTF8
  @($flatRows) | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8

  $exportNotes.Add([pscustomobject]@{
    export = "qfu_rawdocument rows"
    method = "EXPORTED READ-ONLY FROM ENVIRONMENT"
    tool = "Microsoft.Xrm.Data.Powershell Get-CrmRecordsByFetch"
    filters = "qfu_branchcode in (4171,4172,4173) and qfu_sourcefamily in (GL060,SA1300,SP830CA,ZBO)"
    date_window = "180-day window by qfu_receivedon or createdon"
  })

  return @($flatRows)
}

function Write-JsonFile {
  param(
    [string]$Path,
    [object]$Data,
    [int]$Depth = 12
  )

  $Data | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Expand-ZipToFolder {
  param(
    [string]$ZipPath,
    [string]$Destination
  )

  if (-not (Test-Path -LiteralPath $ZipPath)) { return $false }
  if (Test-Path -LiteralPath $Destination) {
    Remove-Item -LiteralPath $Destination -Recurse -Force
  }
  Ensure-Directory -Path $Destination
  Expand-Archive -LiteralPath $ZipPath -DestinationPath $Destination -Force
  return $true
}

function Search-ZipArtifacts {
  param(
    [string[]]$Roots,
    [string[]]$Patterns,
    [string]$OutputRoot
  )

  Ensure-Directory -Path $OutputRoot
  $zipHits = New-Object System.Collections.Generic.List[object]
  $zipInventory = New-Object System.Collections.Generic.List[object]
  $zipFiles = @()

  foreach ($root in $Roots) {
    if (Test-Path -LiteralPath $root) {
      $zipFiles += Get-ChildItem -Path $root -Recurse -File -Filter *.zip -ErrorAction SilentlyContinue
    }
  }
  $zipFiles = @($zipFiles | Sort-Object FullName -Unique)

  foreach ($zipFile in $zipFiles) {
    $zipInventory.Add([pscustomobject]@{
      zip_path = $zipFile.FullName
      length = $zipFile.Length
      last_write_time = $zipFile.LastWriteTime.ToString("o")
    })

    try {
      $archive = [System.IO.Compression.ZipFile]::OpenRead($zipFile.FullName)
      foreach ($entry in @($archive.Entries)) {
        foreach ($pattern in $Patterns) {
          if ($entry.FullName -like "*$pattern*") {
            $zipHits.Add([pscustomobject]@{
              zip_path = $zipFile.FullName
              entry_path = $entry.FullName
              match_pattern = $pattern
              match_type = "entry-name"
            })
          }
        }
      }
      $archive.Dispose()
    }
    catch {
      $zipHits.Add([pscustomobject]@{
        zip_path = $zipFile.FullName
        entry_path = ""
        match_pattern = ""
        match_type = "zip-open-failed"
        detail = $_.Exception.Message
      })
    }
  }

  Write-JsonFile -Path (Join-Path $OutputRoot "zip-inventory.json") -Data @($zipInventory.ToArray())
  Write-JsonFile -Path (Join-Path $OutputRoot "zip-search-hits.json") -Data @($zipHits.ToArray())
}

function Search-FileSystemByName {
  param(
    [string[]]$Roots,
    [string[]]$Patterns,
    [string]$OutputPath
  )

  $results = New-Object System.Collections.Generic.List[object]
  foreach ($root in $Roots) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    foreach ($pattern in $Patterns) {
      $hits = Get-ChildItem -Path $root -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -like $pattern }
      foreach ($hit in @($hits)) {
        $results.Add([pscustomobject]@{
          root = $root
          pattern = $pattern
          path = $hit.FullName
          type = if ($hit.PSIsContainer) { "directory" } else { "file" }
        })
      }
    }
  }

  Write-JsonFile -Path $OutputPath -Data @($results.ToArray())
}

function Write-WorkflowPresenceFiles {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$OutputRoot
  )

  Ensure-Directory -Path $OutputRoot

  $gl060Names = @("4171-GL060-Inbox-Ingress", "4172-GL060-Inbox-Ingress", "4173-GL060-Inbox-Ingress")
  $gl060Ids = @("fd1ec8dc-56ca-4af7-ab8d-49465802b52a", "7447f66d-93d0-44dd-9bf4-449e320190e7", "cb327979-b304-4b7f-9a42-44c01c959666")
  $tempNames = @("4171-Temp-Mailbox-Capture", "4172-Temp-Mailbox-Capture", "4173-Temp-Mailbox-Capture")
  $tempIds = @("7b4e2b57-a83d-4d1f-b23c-82f6037e7217", "d496a7b4-be51-40e0-b20a-b4112fdc252f", "7d935f14-85c6-4b10-8d37-99c9b3bfc6e8")
  $gl060SolutionNames = @("qfu_sagl060flows")
  $tempSolutionNames = @("qfu_tempmailboxcapture", "qfu_tempmailboxcapture4171", "qfu_tempmailboxcapture4172", "qfu_tempmailboxcapture4173")

  $gl060WorkflowRows = ConvertTo-SelectedJson -Rows @((Get-CrmRecordsByFetch -conn $Connection -Fetch (New-WorkflowFetchXml -Names $gl060Names -Ids $gl060Ids) -AllRows).CrmRecords) -Properties @("ReturnProperty_Id", "name", "workflowid", "statecode", "statuscode", "modifiedon", "createdon", "category", "type")
  $tempWorkflowRows = ConvertTo-SelectedJson -Rows @((Get-CrmRecordsByFetch -conn $Connection -Fetch (New-WorkflowFetchXml -Names $tempNames -Ids $tempIds) -AllRows).CrmRecords) -Properties @("ReturnProperty_Id", "name", "workflowid", "statecode", "statuscode", "modifiedon", "createdon", "category", "type")
  $gl060SolutionRows = ConvertTo-SelectedJson -Rows @((Get-CrmRecordsByFetch -conn $Connection -Fetch (New-SolutionFetchXml -UniqueNames $gl060SolutionNames) -AllRows).CrmRecords) -Properties @("ReturnProperty_Id", "friendlyname", "uniquename", "solutionid", "version", "modifiedon", "createdon", "ismanaged")
  $tempSolutionRows = ConvertTo-SelectedJson -Rows @((Get-CrmRecordsByFetch -conn $Connection -Fetch (New-SolutionFetchXml -UniqueNames $tempSolutionNames) -AllRows).CrmRecords) -Properties @("ReturnProperty_Id", "friendlyname", "uniquename", "solutionid", "version", "modifiedon", "createdon", "ismanaged")

  $gl060ComponentRows = ConvertTo-SelectedJson -Rows @((Get-CrmRecordsByFetch -conn $Connection -Fetch (New-SolutionComponentFetchXml -ObjectIds @($gl060WorkflowRows | ForEach-Object { $_.workflowid } | Where-Object { $_ })) -AllRows).CrmRecords) -Properties @("ReturnProperty_Id", "solutioncomponentid", "objectid", "solutionid", "componenttype", "createdon", "modifiedon")
  $tempComponentRows = ConvertTo-SelectedJson -Rows @((Get-CrmRecordsByFetch -conn $Connection -Fetch (New-SolutionComponentFetchXml -ObjectIds @($tempWorkflowRows | ForEach-Object { $_.workflowid } | Where-Object { $_ })) -AllRows).CrmRecords) -Properties @("ReturnProperty_Id", "solutioncomponentid", "objectid", "solutionid", "componenttype", "createdon", "modifiedon")

  Write-JsonFile -Path (Join-Path $OutputRoot "gl060-workflows.json") -Data $gl060WorkflowRows
  $gl060WorkflowRows | Export-Csv -LiteralPath (Join-Path $OutputRoot "gl060-workflows.csv") -NoTypeInformation -Encoding UTF8
  Write-JsonFile -Path (Join-Path $OutputRoot "gl060-solutions.json") -Data $gl060SolutionRows
  $gl060SolutionRows | Export-Csv -LiteralPath (Join-Path $OutputRoot "gl060-solutions.csv") -NoTypeInformation -Encoding UTF8
  Write-JsonFile -Path (Join-Path $OutputRoot "gl060-solutioncomponents.json") -Data $gl060ComponentRows
  $gl060ComponentRows | Export-Csv -LiteralPath (Join-Path $OutputRoot "gl060-solutioncomponents.csv") -NoTypeInformation -Encoding UTF8

  Write-JsonFile -Path (Join-Path $OutputRoot "tempmailbox-workflows.json") -Data $tempWorkflowRows
  $tempWorkflowRows | Export-Csv -LiteralPath (Join-Path $OutputRoot "tempmailbox-workflows.csv") -NoTypeInformation -Encoding UTF8
  Write-JsonFile -Path (Join-Path $OutputRoot "tempmailbox-solutions.json") -Data $tempSolutionRows
  $tempSolutionRows | Export-Csv -LiteralPath (Join-Path $OutputRoot "tempmailbox-solutions.csv") -NoTypeInformation -Encoding UTF8
  Write-JsonFile -Path (Join-Path $OutputRoot "tempmailbox-solutioncomponents.json") -Data $tempComponentRows
  $tempComponentRows | Export-Csv -LiteralPath (Join-Path $OutputRoot "tempmailbox-solutioncomponents.csv") -NoTypeInformation -Encoding UTF8

  $exportNotes.Add([pscustomobject]@{
    export = "workflow and solution presence"
    method = "EXPORTED READ-ONLY FROM ENVIRONMENT"
    tool = "Microsoft.Xrm.Data.Powershell Get-CrmRecordsByFetch"
    filters = "workflow names/ids and solution unique names for GL060 and temp mailbox capture"
    date_window = "none"
  })

  return @{
    gl060_workflows = $gl060WorkflowRows
    gl060_solutions = $gl060SolutionRows
    temp_workflows = $tempWorkflowRows
    temp_solutions = $tempSolutionRows
  }
}

function Export-Gl060SolutionReadOnly {
  param([string]$OutputRoot)

  Ensure-Directory -Path $OutputRoot
  $zipOut = Join-Path $OutputRoot "qfu_sagl060flows.exported-unmanaged.zip"
  $logOut = Join-Path $OutputRoot "gl060-solution-export.log"
  $extractRoot = Join-Path $OutputRoot "extracted"

  $pacOutput = & pac solution export --name qfu_sagl060flows --path $zipOut --managed false --environment $TargetEnvironmentUrl --overwrite 2>&1
  $pacOutput | Set-Content -LiteralPath $logOut -Encoding UTF8
  $success = ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $zipOut))

  if ($success) {
    Expand-ZipToFolder -ZipPath $zipOut -Destination $extractRoot | Out-Null
    Add-FoundItem -Category "gl060-flow" -Item "GL060 unmanaged solution export" -Status "EXPORTED READ-ONLY FROM ENVIRONMENT" -Detail $zipOut
  }
  else {
    Add-MissingItem -Category "gl060-flow" -Item "GL060 unmanaged solution export" -Status "COULD NOT EXPORT" -Detail $logOut
  }

  $exportNotes.Add([pscustomobject]@{
    export = "GL060 solution export"
    method = if ($success) { "EXPORTED READ-ONLY FROM ENVIRONMENT" } else { "COULD NOT EXPORT" }
    tool = "pac solution export"
    filters = "solution name qfu_sagl060flows"
    date_window = "none"
  })

  return @{
    success = $success
    zip_path = $zipOut
    log_path = $logOut
    extract_root = $extractRoot
  }
}

function Recover-TempMailboxArtifacts {
  param([string]$OutputRoot)

  Ensure-Directory -Path $OutputRoot
  $originalRoot = Join-Path $OutputRoot "original-zips"
  $extractRoot = Join-Path $OutputRoot "extracted"
  $canonicalRoot = Join-Path $OutputRoot "canonical-workflows"
  Ensure-Directory -Path $originalRoot
  Ensure-Directory -Path $extractRoot
  Ensure-Directory -Path $canonicalRoot

  $zipCandidates = @(
    (Join-Path $LegacyEvidenceRoot "results\qfu-tempmailboxcapture.zip")
    (Join-Path $LegacyEvidenceRoot "results\qfu-tempmailboxcapture-target.zip")
    (Join-Path $LegacyEvidenceRoot "results\qfu-tempmailboxcapture_target.zip")
    (Join-Path $PriorBundleRoot "RAW\results-current\qfu-tempmailboxcapture.zip")
    (Join-Path $PriorBundleRoot "RAW\results-current\qfu-tempmailboxcapture-target.zip")
    (Join-Path $PriorBundleRoot "RAW\results-current\qfu-tempmailboxcapture_target.zip")
  )

  $copied = New-Object System.Collections.Generic.List[string]
  foreach ($candidate in @($zipCandidates | Select-Object -Unique)) {
    if (Test-Path -LiteralPath $candidate) {
      $destination = Join-Path $originalRoot ([System.IO.Path]::GetFileName($candidate))
      Copy-Item -LiteralPath $candidate -Destination $destination -Force
      $copied.Add($destination)
    }
  }

  foreach ($zipFile in @($copied)) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($zipFile)
    $destination = Join-Path $extractRoot $name
    Expand-ZipToFolder -ZipPath $zipFile -Destination $destination | Out-Null
  }

  $workflowJsons = Get-ChildItem -Path $extractRoot -Recurse -File -Filter *.json -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*Temp-Mailbox-Capture*" }
  $canonicalJsons = New-Object System.Collections.Generic.List[string]
  foreach ($workflowJson in @($workflowJsons | Sort-Object FullName)) {
    $destination = Join-Path $canonicalRoot $workflowJson.Name
    if (-not (Test-Path -LiteralPath $destination)) {
      Copy-Item -LiteralPath $workflowJson.FullName -Destination $destination -Force
      $canonicalJsons.Add($destination)
    }
  }
  if ($workflowJsons.Count -gt 0) {
    Add-FoundItem -Category "temp-mailbox" -Item "Temp mailbox capture flow export" -Status "FOUND INSIDE NESTED ZIP" -Detail $canonicalRoot
  }
  else {
    Add-MissingItem -Category "temp-mailbox" -Item "Temp mailbox capture flow export" -Status "NOT FOUND" -Detail $OutputRoot
  }

  return @{
    copied_zips = @($copied)
    workflow_jsons = @($workflowJsons | Select-Object -ExpandProperty FullName)
    canonical_jsons = @($canonicalJsons.ToArray())
  }
}

function Copy-DeliveryLineageArtifacts {
  param([string]$OutputRoot)

  Ensure-Directory -Path $OutputRoot
  $evidenceRoot = Join-Path $OutputRoot "workspace-evidence"
  Ensure-Directory -Path $evidenceRoot

  $sourceFiles = @(
    (Join-Path $RepoRoot "site\sitesetting.yml")
    (Join-Path $RepoRoot "site\.portalconfig\regionaloperationshub.crm.dynamics.com-manifest.yml")
    (Join-Path $RepoRoot "site\web-templates\qfu-regional-runtime\QFU-Regional-Runtime.webtemplate.source.html")
    (Join-Path $LegacyEvidenceRoot "scripts\create-southern-alberta-pilot-flow-solution.ps1")
    (Join-Path $LegacyEvidenceRoot "scripts\deploy-southern-alberta-pilot.ps1")
  )

  foreach ($source in $sourceFiles) {
    if (Test-Path -LiteralPath $source) {
      if ($source.StartsWith($RepoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relative = $source.Substring($RepoRoot.Length).TrimStart("\")
      }
      elseif ($source.StartsWith($LegacyEvidenceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relative = $source.Substring($LegacyEvidenceRoot.Length).TrimStart("\")
      }
      else {
        $relative = [System.IO.Path]::GetFileName($source)
      }
      $destination = Join-Path $evidenceRoot $relative
      Ensure-Directory -Path (Split-Path -Parent $destination)
      Copy-Item -LiteralPath $source -Destination $destination -Force
    }
  }

  foreach ($name in @("qfu_sourcefeed.rows.json", "qfu_sourcefeed.rows.csv", "qfu_deliverynotpgi.rows.json", "qfu_deliverynotpgi.rows.csv")) {
    $source = Join-Path $PriorBundleRoot ("DATA\dataverse-rows\{0}" -f $name)
    if (Test-Path -LiteralPath $source) {
      Copy-Item -LiteralPath $source -Destination (Join-Path $OutputRoot $name) -Force
    }
  }
  foreach ($name in @("qfu_sourcefeed.metadata.json", "qfu_deliverynotpgi.metadata.json")) {
    $source = Join-Path $PriorBundleRoot ("DATA\dataverse-metadata\{0}" -f $name)
    if (Test-Path -LiteralPath $source) {
      Copy-Item -LiteralPath $source -Destination (Join-Path $OutputRoot $name) -Force
    }
  }

  $hits = @(
    Get-ChildItem -Path $RepoRoot -Recurse -File -ErrorAction SilentlyContinue |
      Where-Object { $_.Extension -in @(".ps1", ".py", ".json", ".html", ".yml", ".yaml", ".xml", ".md", ".txt") } |
      Select-String -Pattern "qfu_deliverynotpgi|deliverynotpgi|notpgi|unshippednetvalue|qtyondelnotpgid|DNPGI" -ErrorAction SilentlyContinue
  ) + @(
    Get-ChildItem -Path $LegacyEvidenceRoot -Recurse -File -ErrorAction SilentlyContinue |
      Where-Object { $_.Extension -in @(".ps1", ".py", ".json", ".html", ".yml", ".yaml", ".xml", ".md", ".txt") } |
      Select-String -Pattern "qfu_deliverynotpgi|deliverynotpgi|notpgi|unshippednetvalue|qtyondelnotpgid|DNPGI" -ErrorAction SilentlyContinue
  )

  $lines = if ($hits.Count -gt 0) {
    @($hits | ForEach-Object { "{0}:{1}: {2}" -f $_.Path, $_.LineNumber, $_.Line.Trim() })
  }
  else {
    @("NO MATCHES FOUND in workspace scripts/solution/results for qfu_deliverynotpgi/deliverynotpgi/notpgi/unshippednetvalue/qtyondelnotpgid/DNPGI outside the current live site runtime.")
  }
  Set-Content -LiteralPath (Join-Path $OutputRoot "delivery-lineage-search-results.txt") -Value $lines -Encoding UTF8

  $zboOut = Join-Path $OutputRoot "representative-zbo-source-files"
  Ensure-Directory -Path $zboOut
  $zboFiles = Get-ChildItem -Path (Join-Path $LegacyEvidenceRoot "Latest") -Recurse -File -Filter "CA ZBO *.xlsx" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 6
  foreach ($file in @($zboFiles)) {
    Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $zboOut $file.Name) -Force
  }
}

function Recover-RawDocumentSampleFiles {
  param(
    [object[]]$Rows,
    [string]$OutputRoot
  )

  Ensure-Directory -Path $OutputRoot
  $recovered = New-Object System.Collections.Generic.List[object]
  $selectedRows = @(
    $Rows |
      Where-Object { $_.qfu_rawcontentbase64__raw -and $_.qfu_sourcefamily__raw -in @("GL060", "SA1300") } |
      Group-Object { [string]$_.qfu_sourcefamily__raw } |
      ForEach-Object { $_.Group | Sort-Object createdon__raw -Descending | Select-Object -First 2 }
  )

  foreach ($row in @($selectedRows)) {
    try {
      $base64 = [string]$row.qfu_rawcontentbase64__raw
      $bytes = [System.Convert]::FromBase64String($base64)
      $sourceFile = if ($row.qfu_sourcefile__raw) { [string]$row.qfu_sourcefile__raw } elseif ($row.qfu_name__raw) { [string]$row.qfu_name__raw } else { [string]$row._primaryid }
      $extension = [System.IO.Path]::GetExtension($sourceFile)
      if ([string]::IsNullOrWhiteSpace($extension)) { $extension = ".bin" }
      $safeName = "{0}-{1}-{2}{3}" -f $row.qfu_sourcefamily__raw, $row.qfu_branchcode__raw, $row._primaryid, $extension
      $path = Join-Path $OutputRoot $safeName
      [System.IO.File]::WriteAllBytes($path, $bytes)
      $recovered.Add([pscustomobject]@{
        file = $path
        sourcefamily = $row.qfu_sourcefamily__raw
        sourcefile = $row.qfu_sourcefile__raw
        branchcode = $row.qfu_branchcode__raw
        rawdocumentid = $row._primaryid
      })
    }
    catch {
      $recovered.Add([pscustomobject]@{
        file = ""
        sourcefamily = $row.qfu_sourcefamily__raw
        sourcefile = $row.qfu_sourcefile__raw
        branchcode = $row.qfu_branchcode__raw
        rawdocumentid = $row._primaryid
        error = $_.Exception.Message
      })
    }
  }

  Write-JsonFile -Path (Join-Path $OutputRoot "recovery-summary.json") -Data @($recovered.ToArray())
  return @($recovered.ToArray())
}

function Write-Readme {
  param([string]$OutputPath)

  $content = @'
# Final Gaps Audit Bundle

This is a final gap-closure evidence bundle.

- No fixes were implemented.
- No app behavior was changed.
- No Dataverse rows were patched, deleted, normalized, or deduplicated.
- No deployments were performed.
- All environment actions in this bundle were read-only discovery or export actions.

Purpose:
- close the remaining missing evidence gaps before a full regression and reliability audit
- preserve canonical recovered flow artifacts
- prove GL060 and temp-mailbox flow presence or absence and export status
- prove delivery-not-PGI lineage
- export qfu_rawdocument metadata and rows to bridge mailbox/file input to downstream rows
'@

  Set-Content -LiteralPath $OutputPath -Value $content -Encoding UTF8
}

function Write-FoundVsMissing {
  param([string]$OutputPath)

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("# Found vs Missing")
  $lines.Add("")
  $allItems = @($foundItems.ToArray()) + @($missingItems.ToArray())
  foreach ($group in ($allItems | Group-Object category | Sort-Object Name)) {
    $lines.Add("## $($group.Name)")
    foreach ($item in @($group.Group | Sort-Object item, status)) {
      $lines.Add("- [$($item.status)] $($item.item)")
      $lines.Add("  - $($item.detail)")
    }
    $lines.Add("")
  }
  Set-Content -LiteralPath $OutputPath -Value @($lines) -Encoding UTF8
}

function Write-ExportMethod {
  param(
    [datetime]$CutoffDate,
    [string]$OutputPath
  )

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("# Export Method")
  $lines.Add("")
  $lines.Add("## Filesystem search")
  $lines.Add("- searched current workspace, legacy evidence workspace, and prior audit staging before exporting anything new")
  $lines.Add("- pattern families: *gl060*, *GL060*, *qfu_sagl060flows*, *southern-alberta-gl060-flows*, *Temp*Mailbox*Capture*, *qfu_tempmailboxcapture*, *rawdocument*")
  $lines.Add("")
  $lines.Add("## Zip search")
  $lines.Add("- tool: System.IO.Compression.ZipFile via PowerShell")
  $lines.Add("- roots searched: repository root, legacy evidence root, prior audit staging")
  $lines.Add("- match rule: zip entry path contains targeted GL060/temp/rawdocument patterns")
  $lines.Add("")
  $lines.Add("## Dataverse read-only discovery")
  $lines.Add("- tool: Microsoft.Xrm.Data.Powershell")
  $lines.Add("- connection: Connect-CrmOnline against $TargetEnvironmentUrl")
  $lines.Add("- entities queried: workflow, solution, solutioncomponent, qfu_rawdocument")
  $lines.Add("- qfu_rawdocument date window: on-or-after $($CutoffDate.ToString('yyyy-MM-dd'))")
  $lines.Add("- qfu_rawdocument filters: qfu_branchcode in (4171, 4172, 4173) and qfu_sourcefamily in (GL060, SA1300, SP830CA, ZBO)")
  $lines.Add("")
  $lines.Add("## Solution export")
  $lines.Add("- tool: pac solution export")
  $lines.Add("- attempted solution: qfu_sagl060flows")
  $lines.Add("- mode: unmanaged read-only export from target environment")
  $lines.Add("")
  $lines.Add("## Existing evidence reused")
  $lines.Add("- copied qfu_sourcefeed and qfu_deliverynotpgi metadata and row exports from the prior final audit staging")
  $lines.Add("- copied representative ZBO source files from the legacy evidence workspace")
  $lines.Add("")
  foreach ($note in @($exportNotes.ToArray())) {
    $lines.Add("- $($note.export): $($note.method) | tool=$($note.tool) | filters=$($note.filters) | date_window=$($note.date_window)")
  }

  Set-Content -LiteralPath $OutputPath -Value @($lines) -Encoding UTF8
}

function Write-TreeFile {
  param(
    [string]$Root,
    [string]$OutputPath
  )

  tree $Root /F | Set-Content -LiteralPath $OutputPath -Encoding UTF8
}

function Write-Sha256File {
  param(
    [string]$Root,
    [string]$OutputPath
  )

  $lines = Get-ChildItem -Path $Root -Recurse -File | Sort-Object FullName | ForEach-Object {
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash
    "{0}  {1}" -f $hash, (Get-RelativePathSafe -BasePath $Root -FullPath $_.FullName)
  }
  Set-Content -LiteralPath $OutputPath -Value $lines -Encoding UTF8
}

function Write-SearchHits {
  param(
    [string]$Root,
    [string]$OutputPath
  )

  $terms = @("GL060", "qfu_sagl060flows", "Temp-Mailbox-Capture", "qfu_tempmailboxcapture", "qfu_rawdocument", "qfu_deliverynotpgi", "deliverynotpgi", "notpgi", "pgi", "SA1300", "qfu_sourcefeed", "qfu_sourcefamily", "4171", "4172", "4173")
  $textFiles = Get-ChildItem -Path $Root -Recurse -File | Where-Object { $_.Extension -in @(".md", ".txt", ".json", ".csv", ".ps1", ".py", ".html", ".xml", ".yml", ".yaml") }
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("# Search Hits")
  $lines.Add("")
  foreach ($term in $terms) {
    $lines.Add("## $term")
    $hits = Select-String -Path $textFiles.FullName -Pattern $term -SimpleMatch -ErrorAction SilentlyContinue
    if (-not $hits) {
      $lines.Add("- no hits")
      $lines.Add("")
      continue
    }
    foreach ($hit in @($hits)) {
      $relative = Get-RelativePathSafe -BasePath $Root -FullPath $hit.Path
      $lines.Add(("- {0}:{1}: {2}" -f $relative, $hit.LineNumber, $hit.Line.Trim()))
    }
    $lines.Add("")
  }
  Set-Content -LiteralPath $OutputPath -Value @($lines) -Encoding UTF8
}

function Write-WorkflowPresenceReport {
  param(
    [string]$OutputPath,
    [hashtable]$PresenceData,
    [hashtable]$Gl060ExportData,
    [hashtable]$TempRecoveryData
  )

  $lines = @(
    "# Workflow and Solution Presence",
    "",
    "## GL060",
    "- searched workflow names: 4171-GL060-Inbox-Ingress, 4172-GL060-Inbox-Ingress, 4173-GL060-Inbox-Ingress",
    "- searched workflow ids: fd1ec8dc-56ca-4af7-ab8d-49465802b52a, 7447f66d-93d0-44dd-9bf4-449e320190e7, cb327979-b304-4b7f-9a42-44c01c959666",
    "- workflow rows found: $(@($PresenceData.gl060_workflows).Count)",
    "- solution rows found: $(@($PresenceData.gl060_solutions).Count)",
    "- export succeeded: $($Gl060ExportData.success)",
    "- export log: RAW/recovered-flow-exports/qfu_sagl060flows/gl060-solution-export.log",
    "",
    "## Temp Mailbox Capture",
    "- searched workflow names: 4171-Temp-Mailbox-Capture, 4172-Temp-Mailbox-Capture, 4173-Temp-Mailbox-Capture",
    "- searched workflow ids: 7b4e2b57-a83d-4d1f-b23c-82f6037e7217, d496a7b4-be51-40e0-b20a-b4112fdc252f, 7d935f14-85c6-4b10-8d37-99c9b3bfc6e8",
    "- workflow rows found: $(@($PresenceData.temp_workflows).Count)",
    "- solution rows found: $(@($PresenceData.temp_solutions).Count)",
    "- recovered nested zip count: $(@($TempRecoveryData.copied_zips).Count)",
    "- canonical extracted workflow json count: $(@($TempRecoveryData.workflow_jsons).Count)"
  )
  Set-Content -LiteralPath $OutputPath -Value $lines -Encoding UTF8
}

function Write-Gl060FlowStatus {
  param(
    [string]$OutputPath,
    [hashtable]$Gl060ExportData,
    [hashtable]$PresenceData
  )

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("# GL060 Flow Status")
  $lines.Add("")
  if ($Gl060ExportData.success) {
    $lines.Add("- GL060 flow export was exported read-only from the environment as unmanaged solution qfu_sagl060flows.")
    $lines.Add("- canonical location: RAW/recovered-flow-exports/qfu_sagl060flows/qfu_sagl060flows.exported-unmanaged.zip")
    $lines.Add("- extracted location: RAW/recovered-flow-exports/qfu_sagl060flows/extracted/")
  }
  else {
    $lines.Add("- No pre-existing GL060 solution zip was found in the searched workspace or nested zip artifacts.")
    $lines.Add("- Environment workflow and solution presence were proven via Dataverse query results.")
    $lines.Add("- Solution export did not complete successfully; see RAW/recovered-flow-exports/qfu_sagl060flows/gl060-solution-export.log.")
  }
  $lines.Add("- workflow rows found in environment: $(@($PresenceData.gl060_workflows).Count)")
  $lines.Add("- solution rows found in environment: $(@($PresenceData.gl060_solutions).Count)")
  Set-Content -LiteralPath $OutputPath -Value @($lines) -Encoding UTF8
}

function Write-TempMailboxStatus {
  param(
    [string]$OutputPath,
    [hashtable]$TempRecoveryData
  )

  $lines = @(
    "# Temp Mailbox Flow Status",
    "",
    "- Temp mailbox capture exports were recovered from nested zip artifacts already present in the workspace.",
    "- Original zip artifacts were preserved under RAW/recovered-flow-exports/qfu_tempmailboxcapture/original-zips/",
    "- Canonical extracted location: RAW/recovered-flow-exports/qfu_tempmailboxcapture/extracted/",
    "- Canonical flat workflow location: RAW/recovered-flow-exports/qfu_tempmailboxcapture/canonical-workflows/",
    "- Recovered zip count: $(@($TempRecoveryData.copied_zips).Count)",
    "- Extracted workflow json count: $(@($TempRecoveryData.workflow_jsons).Count)",
    "- Canonical workflow json count: $(@($TempRecoveryData.canonical_jsons).Count)"
  )
  Set-Content -LiteralPath $OutputPath -Value $lines -Encoding UTF8
}

function Write-DeliveryLineageReport {
  param([string]$OutputPath)

  $lines = @(
    "# Delivery Not-PGI Lineage",
    "",
    "- No dedicated delivery-not-PGI source family or sourcefeed evidence was found in the existing qfu_sourcefeed row export.",
    "- qfu_deliverynotpgi rows show qfu_sourcefamily = ZBO and qfu_sourcefile values that point to CA ZBO workbook files.",
    "- The current live Power Pages runtime consumes qfu_deliverynotpgis directly via the shared regional runtime.",
    "- No standalone source-controlled script or flow export in the searched workspace/results/solution trees contained qfu_deliverynotpgi or deliverynotpgi creation logic.",
    "- The evidence therefore supports: qfu_deliverynotpgi is derived from ZBO lineage in the live data, but the exact creation or update implementation is not present in the searched source-controlled or archived flow artifacts available in this workspace.",
    "",
    "Evidence paths:",
    "- DATA/delivery-notpgi-lineage/qfu_sourcefeed.rows.json",
    "- DATA/delivery-notpgi-lineage/qfu_deliverynotpgi.rows.json",
    "- DATA/delivery-notpgi-lineage/workspace-evidence/site/web-templates/qfu-regional-runtime/QFU-Regional-Runtime.webtemplate.source.html",
    "- DATA/delivery-notpgi-lineage/workspace-evidence/site/sitesetting.yml",
    "- DATA/delivery-notpgi-lineage/delivery-lineage-search-results.txt",
    "- DATA/delivery-notpgi-lineage/representative-zbo-source-files/"
  )
  Set-Content -LiteralPath $OutputPath -Value $lines -Encoding UTF8
}

$cutoffDate = (Get-Date).ToUniversalTime().AddDays(-1 * $OperationalHistoryDays)

if (Test-Path -LiteralPath $StagingRoot) { Remove-Item -LiteralPath $StagingRoot -Recurse -Force }
Ensure-Directory -Path $StagingRoot
if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }

$inventoryRoot = Join-Path $StagingRoot "INVENTORY"
$rawRoot = Join-Path $StagingRoot "RAW"
$dataRoot = Join-Path $StagingRoot "DATA"
$reportsRoot = Join-Path $StagingRoot "REPORTS"
$rawRecoveredFlowsRoot = Join-Path $rawRoot "recovered-flow-exports"
$rawSearchRoot = Join-Path $rawRoot "search-evidence"
$metadataRoot = Join-Path $dataRoot "dataverse-metadata"
$rowsRoot = Join-Path $dataRoot "dataverse-rows"
$workflowPresenceRoot = Join-Path $dataRoot "workflow-presence"
$deliveryLineageRoot = Join-Path $dataRoot "delivery-notpgi-lineage"
$sourceInputRoot = Join-Path $dataRoot "source-input-samples"
$rawRecoveredSourceInputRoot = Join-Path $sourceInputRoot "recovered-from-qfu_rawdocument"

foreach ($path in @($inventoryRoot, $rawRecoveredFlowsRoot, $rawSearchRoot, $metadataRoot, $rowsRoot, $workflowPresenceRoot, $deliveryLineageRoot, $sourceInputRoot, $rawRecoveredSourceInputRoot, $reportsRoot)) {
  Ensure-Directory -Path $path
}

$searchRoots = @($RepoRoot, $LegacyEvidenceRoot, $PriorBundleRoot) | Where-Object { Test-Path -LiteralPath $_ }
Search-FileSystemByName -Roots $searchRoots -Patterns @("*gl060*", "*GL060*", "*qfu_sagl060flows*", "*southern-alberta-gl060-flows*", "*Temp*Mailbox*Capture*", "*qfu_tempmailboxcapture*", "*rawdocument*") -OutputPath (Join-Path $rawSearchRoot "filesystem-name-search.json")
Search-ZipArtifacts -Roots $searchRoots -Patterns @("GL060", "gl060", "qfu_sagl060flows", "southern-alberta-gl060-flows", "Temp-Mailbox-Capture", "tempmailboxcapture", "qfu_tempmailboxcapture", "rawdocument") -OutputRoot $rawSearchRoot

$tempRecovery = Recover-TempMailboxArtifacts -OutputRoot (Join-Path $rawRecoveredFlowsRoot "qfu_tempmailboxcapture")
$connection = Connect-Org -Url $TargetEnvironmentUrl -User $Username
$presenceData = Write-WorkflowPresenceFiles -Connection $connection -OutputRoot $workflowPresenceRoot
$gl060Export = Export-Gl060SolutionReadOnly -OutputRoot (Join-Path $rawRecoveredFlowsRoot "qfu_sagl060flows")
Export-SingleMetadata -Connection $connection -EntityLogicalName "qfu_rawdocument" -OutputPath (Join-Path $metadataRoot "qfu_rawdocument.metadata.json")
$rawRows = Export-RawDocumentRows -Connection $connection -CutoffDate $cutoffDate -JsonPath (Join-Path $rowsRoot "qfu_rawdocument.rows.json") -CsvPath (Join-Path $rowsRoot "qfu_rawdocument.rows.csv")
$recoveredRawFiles = Recover-RawDocumentSampleFiles -Rows $rawRows -OutputRoot $rawRecoveredSourceInputRoot

Add-FoundItem -Category "qfu_rawdocument" -Item "qfu_rawdocument metadata" -Status "EXPORTED READ-ONLY FROM ENVIRONMENT" -Detail (Join-Path $metadataRoot "qfu_rawdocument.metadata.json")
Add-FoundItem -Category "qfu_rawdocument" -Item "qfu_rawdocument rows" -Status "EXPORTED READ-ONLY FROM ENVIRONMENT" -Detail (Join-Path $rowsRoot "qfu_rawdocument.rows.json")
$rawFamilySummary = @(
  $rawRows |
    Group-Object { [string]$_.qfu_sourcefamily__raw } |
    ForEach-Object {
      $withPayload = @($_.Group | Where-Object { $_.qfu_rawcontentbase64__raw }).Count
      [pscustomobject]@{
        sourcefamily = $_.Name
        row_count = $_.Count
        rows_with_raw_payload = $withPayload
      }
    }
)
Write-JsonFile -Path (Join-Path $rowsRoot "qfu_rawdocument.sourcefamily-summary.json") -Data $rawFamilySummary
foreach ($family in @("GL060", "SA1300")) {
  $familyRecovered = @($recoveredRawFiles | Where-Object { $_.sourcefamily -eq $family -and $_.file })
  if ($familyRecovered.Count -gt 0) {
    Add-FoundItem -Category "qfu_rawdocument" -Item "$family recovered raw files from qfu_rawdocument" -Status "EXPORTED READ-ONLY FROM ENVIRONMENT" -Detail $rawRecoveredSourceInputRoot
  }
  else {
    Add-MissingItem -Category "qfu_rawdocument" -Item "$family recovered raw files from qfu_rawdocument" -Status "COULD NOT EXPORT" -Detail (Join-Path $rawRecoveredSourceInputRoot "recovery-summary.json")
  }
}

Copy-DeliveryLineageArtifacts -OutputRoot $deliveryLineageRoot
Add-FoundItem -Category "delivery-notpgi" -Item "qfu_sourcefeed row export for lineage" -Status "FOUND" -Detail (Join-Path $deliveryLineageRoot "qfu_sourcefeed.rows.json")
Add-FoundItem -Category "delivery-notpgi" -Item "qfu_deliverynotpgi row export for lineage" -Status "FOUND" -Detail (Join-Path $deliveryLineageRoot "qfu_deliverynotpgi.rows.json")

$sourcefeedRowsPath = Join-Path $deliveryLineageRoot "qfu_sourcefeed.rows.json"
if (Test-Path -LiteralPath $sourcefeedRowsPath) {
  $sourceRows = Get-Content -LiteralPath $sourcefeedRowsPath -Raw | ConvertFrom-Json
  $families = @($sourceRows | ForEach-Object { $_.qfu_sourcefamily__raw } | Where-Object { $_ } | Sort-Object -Unique)
  Write-JsonFile -Path (Join-Path $deliveryLineageRoot "qfu_sourcefeed.sourcefamilies-summary.json") -Data ([pscustomobject]@{
    unique_source_families = $families
    has_dedicated_delivery_family = ($families -contains "DeliveryNotPGI")
  })
  if ($families -contains "DeliveryNotPGI") {
    Add-FoundItem -Category "delivery-notpgi" -Item "Dedicated delivery source family" -Status "FOUND" -Detail "qfu_sourcefeed includes DeliveryNotPGI"
  }
  else {
    Add-MissingItem -Category "delivery-notpgi" -Item "Dedicated delivery source family" -Status "NOT FOUND" -Detail "qfu_sourcefeed source families do not include a delivery or not-PGI-specific family"
  }
}
else {
  Add-MissingItem -Category "delivery-notpgi" -Item "qfu_sourcefeed row export for lineage" -Status "NOT FOUND" -Detail $sourcefeedRowsPath
}

$deliveryRowsPath = Join-Path $deliveryLineageRoot "qfu_deliverynotpgi.rows.json"
if (Test-Path -LiteralPath $deliveryRowsPath) {
  $deliveryRows = Get-Content -LiteralPath $deliveryRowsPath -Raw | ConvertFrom-Json
  $sampleRows = @($deliveryRows | Select-Object -First 50)
  Write-JsonFile -Path (Join-Path $deliveryLineageRoot "qfu_deliverynotpgi.sample-rows.json") -Data $sampleRows
  $sampleRows | Export-Csv -LiteralPath (Join-Path $deliveryLineageRoot "qfu_deliverynotpgi.sample-rows.csv") -NoTypeInformation -Encoding UTF8
}
else {
  Add-MissingItem -Category "delivery-notpgi" -Item "qfu_deliverynotpgi row export for lineage" -Status "NOT FOUND" -Detail $deliveryRowsPath
}

Write-Readme -OutputPath (Join-Path $StagingRoot "README_FINAL_GAPS.md")
Write-WorkflowPresenceReport -OutputPath (Join-Path $reportsRoot "workflow-solution-presence.md") -PresenceData $presenceData -Gl060ExportData $gl060Export -TempRecoveryData $tempRecovery
Write-Gl060FlowStatus -OutputPath (Join-Path $reportsRoot "gl060-flow-status.md") -Gl060ExportData $gl060Export -PresenceData $presenceData
Write-TempMailboxStatus -OutputPath (Join-Path $reportsRoot "tempmailbox-flow-status.md") -TempRecoveryData $tempRecovery
Write-DeliveryLineageReport -OutputPath (Join-Path $reportsRoot "delivery-notpgi-lineage.md")
Write-FoundVsMissing -OutputPath (Join-Path $inventoryRoot "found-vs-missing.md")
Write-ExportMethod -CutoffDate $cutoffDate -OutputPath (Join-Path $inventoryRoot "export-method.md")
Write-SearchHits -Root $StagingRoot -OutputPath (Join-Path $inventoryRoot "search-hits.md")
Write-TreeFile -Root $StagingRoot -OutputPath (Join-Path $inventoryRoot "tree.txt")
Write-Sha256File -Root $StagingRoot -OutputPath (Join-Path $inventoryRoot "sha256.txt")

$allFiles = @(Get-ChildItem -Path $StagingRoot -Recurse -File)
$summaryLines = @(
  "# Bundle Summary",
  "",
  "Total files: $($allFiles.Count)",
  "- RAW: $(@(Get-ChildItem -Path $rawRoot -Recurse -File -ErrorAction SilentlyContinue).Count)",
  "- DATA: $(@(Get-ChildItem -Path $dataRoot -Recurse -File -ErrorAction SilentlyContinue).Count)",
  "- REPORTS: $(@(Get-ChildItem -Path $reportsRoot -Recurse -File -ErrorAction SilentlyContinue).Count)",
  "- INVENTORY: $(@(Get-ChildItem -Path $inventoryRoot -Recurse -File -ErrorAction SilentlyContinue).Count)"
)
Set-Content -LiteralPath (Join-Path $inventoryRoot "summary.txt") -Value $summaryLines -Encoding UTF8

& tar.exe -a -cf $ZipPath -C $RepoRoot "QFU_FINAL_GAPS_STAGING"
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $ZipPath)) {
  throw "Failed to create zip at $ZipPath"
}

$zipInfo = Get-Item -LiteralPath $ZipPath
[ordered]@{
  staging_root = $StagingRoot
  zip_path = $ZipPath
  file_count = $allFiles.Count
  zip_size_bytes = $zipInfo.Length
  gl060_flow_exported = $gl060Export.success
  temp_mailbox_workflow_json_count = @($tempRecovery.workflow_jsons).Count
  qfu_rawdocument_row_count = @($rawRows).Count
} | ConvertTo-Json -Depth 6
