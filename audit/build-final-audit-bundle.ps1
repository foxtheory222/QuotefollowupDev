param(
  [string]$RepoRoot = "C:\Dev\QuoteFollowUpComplete",
  [string]$LegacyEvidenceRoot = "C:\Dev\QuoteFollowUpComplete-replacement-20260401",
  [string]$StagingRoot = "C:\Dev\QuoteFollowUpComplete\QFU_FINAL_AUDIT_STAGING",
  [string]$ZipPath = "C:\Dev\QuoteFollowUpComplete\QFU_CHATGPT_FINAL_AUDIT_EVIDENCE_BUNDLE_2026-04-07.zip",
  [string]$TargetEnvironmentUrl = "https://regionaloperationshub.crm.dynamics.com",
  [string]$WebsiteId = "2b4aca76-9dc1-4628-af07-20f7617d4115",
  [string]$Username = "smcfarlane@applied.com",
  [int]$OperationalHistoryDays = 180
)

$ErrorActionPreference = "Stop"

Import-Module Microsoft.Xrm.Data.Powershell

$liveRefreshFolderName = "live-refresh-20260407-074015"
$branchCodes = @("4171", "4172", "4173")
$regionSlug = "southern-alberta"
$requiredTables = @(
  "qfu_budget",
  "qfu_budgetarchive",
  "qfu_quote",
  "qfu_financesnapshot",
  "qfu_financevariance",
  "qfu_branchdailysummary",
  "qfu_ingestionbatch",
  "qfu_backorder",
  "qfu_marginexception",
  "qfu_deliverynotpgi",
  "qfu_sourcefeed",
  "qfu_branch",
  "qfu_region"
)
$tableDateFieldOverrides = @{
  "qfu_marginexception" = "qfu_billingdate"
}
$configTables = @("qfu_branch", "qfu_region", "qfu_sourcefeed")
$foundItems = New-Object System.Collections.Generic.List[object]
$missingItems = New-Object System.Collections.Generic.List[object]
$dataverseExportNotes = New-Object System.Collections.Generic.List[object]

function Ensure-Directory {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Invoke-RobocopyMirror {
  param(
    [string]$Source,
    [string]$Destination
  )

  if (-not (Test-Path -LiteralPath $Source)) {
    return $false
  }

  Ensure-Directory -Path $Destination
  & robocopy $Source $Destination /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
  $code = $LASTEXITCODE
  if ($code -gt 7) {
    throw "Robocopy failed for $Source -> $Destination with exit code $code"
  }

  return $true
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

function Get-DateFieldForEntity {
  param(
    [string]$EntityLogicalName,
    [string[]]$AttributeNames
  )

  if ($tableDateFieldOverrides.ContainsKey($EntityLogicalName) -and $AttributeNames -contains $tableDateFieldOverrides[$EntityLogicalName]) {
    return $tableDateFieldOverrides[$EntityLogicalName]
  }
  if ($AttributeNames -contains "createdon") { return "createdon" }
  if ($AttributeNames -contains "qfu_lastupdated") { return "qfu_lastupdated" }
  if ($AttributeNames -contains "modifiedon") { return "modifiedon" }
  return $null
}

function New-OrFilterXml {
  param(
    [string]$AttributeName,
    [string[]]$Values
  )

  if ($null -eq $Values -or $Values.Count -eq 0) { return "" }

  $conditions = foreach ($value in $Values) {
    "<condition attribute='{0}' operator='eq' value='{1}' />" -f $AttributeName, [System.Security.SecurityElement]::Escape($value)
  }

  return "<filter type='or'>{0}</filter>" -f ($conditions -join "")
}

function New-EntityFetchXml {
  param(
    [string]$EntityLogicalName,
    [string[]]$AttributeNames,
    [datetime]$CutoffDate
  )

  $filters = New-Object System.Collections.Generic.List[string]
  if ($AttributeNames -contains "qfu_branchcode") {
    $filters.Add((New-OrFilterXml -AttributeName "qfu_branchcode" -Values $branchCodes))
  }
  elseif ($AttributeNames -contains "qfu_regionslug") {
    $filters.Add("<condition attribute='qfu_regionslug' operator='eq' value='$regionSlug' />")
  }

  if ($configTables -notcontains $EntityLogicalName) {
    $dateField = Get-DateFieldForEntity -EntityLogicalName $EntityLogicalName -AttributeNames $AttributeNames
    if ($dateField) {
      $filters.Add(("<condition attribute='{0}' operator='on-or-after' value='{1}' />" -f $dateField, $CutoffDate.ToString("yyyy-MM-dd")))
    }
  }

  $filterXml = ""
  if ($filters.Count -gt 0) {
    $filterXml = "<filter type='and'>{0}</filter>" -f ($filters -join "")
  }

  return @"
<fetch version='1.0' mapping='logical' no-lock='true'>
  <entity name='$EntityLogicalName'>
    <all-attributes />
    $filterXml
  </entity>
</fetch>
"@
}

function Export-Metadata {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$OutputRoot,
    [System.Collections.Generic.List[object]]$SummaryRows
  )

  foreach ($table in $requiredTables) {
    $meta = Get-CrmEntityMetadata -conn $Connection -EntityLogicalName $table -EntityFilters All
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

      $summaryRow = [pscustomobject]@{
        entity_logical_name = $table
        entity_display_name = Get-DisplayLabel -Label $meta.DisplayName
        primary_id = $meta.PrimaryIdAttribute
        primary_name = $meta.PrimaryNameAttribute
        alternate_keys = (($alternateKeys | ForEach-Object { "{0}:{1}" -f $_.logical_name, ($_.key_attributes -join "|") }) -join "; ")
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
        option_set = ($optionSet | ConvertTo-Json -Depth 6 -Compress)
      }

      $SummaryRows.Add($summaryRow)
      $summaryRow
    }

    $tablePayload = [ordered]@{
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

    $jsonPath = Join-Path $OutputRoot ("{0}.metadata.json" -f $table)
    $tablePayload | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    $dataverseExportNotes.Add([pscustomobject]@{
      entity = $table
      export_type = "metadata"
      filter = "none"
      date_window = "none"
      format = "JSON"
      notes = "Read-only metadata export via Microsoft.Xrm.Data.Powershell Get-CrmEntityMetadata"
    })
  }
}

function Export-EntityRows {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$EntityLogicalName,
    [datetime]$CutoffDate,
    [string]$OutputRoot
  )

  $meta = Get-CrmEntityMetadata -conn $Connection -EntityLogicalName $EntityLogicalName -EntityFilters Attributes
  $readableAttributes = Get-ReadableAttributes -EntityMetadata $meta
  $attributeNames = @($readableAttributes | Select-Object -ExpandProperty LogicalName)
  $fetch = New-EntityFetchXml -EntityLogicalName $EntityLogicalName -AttributeNames $attributeNames -CutoffDate $CutoffDate
  $results = Get-CrmRecordsByFetch -conn $Connection -Fetch $fetch -AllRows
  $records = @($results.CrmRecords)

  $flatRows = @()
  foreach ($record in $records) {
    $flatRows += Flatten-CrmRecord -Record $record -EntityLogicalName $EntityLogicalName -Attributes $attributeNames
  }

  $jsonPath = Join-Path $OutputRoot ("{0}.rows.json" -f $EntityLogicalName)
  $csvPath = Join-Path $OutputRoot ("{0}.rows.csv" -f $EntityLogicalName)

  $flatRows | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
  $flatRows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

  $branchFilterMode = if ($attributeNames -contains "qfu_branchcode") {
    "qfu_branchcode in (4171,4172,4173)"
  }
  elseif ($attributeNames -contains "qfu_regionslug") {
    "qfu_regionslug = southern-alberta"
  }
  else {
    "no branch/region filter"
  }

  $dateField = Get-DateFieldForEntity -EntityLogicalName $EntityLogicalName -AttributeNames $attributeNames
  $dateRule = if ($configTables -contains $EntityLogicalName -or -not $dateField) {
    "no date filter"
  }
  else {
    "{0} on-or-after {1}" -f $dateField, $CutoffDate.ToString("yyyy-MM-dd")
  }

  $dataverseExportNotes.Add([pscustomobject]@{
    entity = $EntityLogicalName
    export_type = "rows"
    filter = $branchFilterMode
    date_window = $dateRule
    format = "JSON + CSV"
    notes = "Read-only row snapshot via Microsoft.Xrm.Data.Powershell Get-CrmRecordsByFetch with all attributes"
  })

  return @{
    metadata = $meta
    attributes = $attributeNames
    rows = $flatRows
  }
}

function Get-GroupKey {
  param(
    [psobject]$Row,
    [string[]]$Fields
  )

  $parts = foreach ($field in $Fields) {
    $rawName = "{0}__raw" -f $field
    if ($Row.PSObject.Properties[$rawName] -and $null -ne $Row.$rawName -and $Row.$rawName -ne "") {
      [string]$Row.$rawName
    }
    elseif ($Row.PSObject.Properties[$field] -and $null -ne $Row.$field -and $Row.$field -ne "") {
      [string]$Row.$field
    }
    else {
      ""
    }
  }

  return ($parts -join "||")
}

function Parse-CrmDateValue {
  param($Value)

  if ($null -eq $Value -or $Value -eq "") { return $null }
  if ($Value -is [datetime]) { return $Value }

  $parsed = [datetime]::MinValue
  if ([datetime]::TryParse([string]$Value, [ref]$parsed)) {
    return $parsed
  }

  return $null
}

function Write-FocusedExtract {
  param(
    [string]$Name,
    [object[]]$Rows,
    [object]$Summary,
    [string]$Note,
    [string]$OutputRoot
  )

  $targetDir = Join-Path $OutputRoot $Name
  Ensure-Directory -Path $targetDir

  $rowsJsonPath = Join-Path $targetDir "rows.json"
  $rowsCsvPath = Join-Path $targetDir "rows.csv"
  $summaryPath = Join-Path $targetDir "summary.json"
  $notePath = Join-Path $targetDir "note.md"

  @($Rows) | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $rowsJsonPath -Encoding UTF8
  @($Rows) | Export-Csv -LiteralPath $rowsCsvPath -NoTypeInformation -Encoding UTF8
  $Summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
  Set-Content -LiteralPath $notePath -Value $Note -Encoding UTF8
}

function Export-DuplicateCases {
  param(
    [hashtable]$EntityExports,
    [string]$OutputRoot
  )

  Ensure-Directory -Path $OutputRoot

  $budgetRows = @($EntityExports["qfu_budget"].rows)
  $budgetDuplicateGroups = @(
    $budgetRows |
      Group-Object { Get-GroupKey -Row $_ -Fields @("qfu_branchcode", "qfu_year", "qfu_month", "qfu_fiscalyear") } |
      Where-Object { $_.Count -gt 1 }
  )
  $budgetDuplicateRows = @($budgetDuplicateGroups | ForEach-Object { $_.Group })
  $budgetSummary = [ordered]@{
    entity = "qfu_budget"
    grouping_fields = @("qfu_branchcode", "qfu_year", "qfu_month", "qfu_fiscalyear")
    duplicate_group_count = $budgetDuplicateGroups.Count
    duplicate_row_count = $budgetDuplicateRows.Count
    groups = @(
      $budgetDuplicateGroups | ForEach-Object {
        [ordered]@{
          key = $_.Name
          count = $_.Count
        }
      }
    )
  }
  Write-FocusedExtract -Name "qfu_budget-duplicates" -Rows $budgetDuplicateRows -Summary $budgetSummary -Note @"
Grouping logic:
- Group qfu_budget rows by qfu_branchcode + qfu_year + qfu_month + qfu_fiscalyear.
- Export all rows from groups where the logical month identity appears more than once.
"@ -OutputRoot $OutputRoot

  $budgetArchiveRows = @($EntityExports["qfu_budgetarchive"].rows)
  $budgetArchiveDuplicateGroups = @(
    $budgetArchiveRows |
      Group-Object { Get-GroupKey -Row $_ -Fields @("qfu_branchcode", "qfu_year", "qfu_month", "qfu_fiscalyear") } |
      Where-Object { $_.Count -gt 1 }
  )
  $budgetArchiveLogicalMonthRows = @($budgetArchiveDuplicateGroups | ForEach-Object { $_.Group })
  $budgetArchiveSourceIdRows = @(
    $budgetArchiveRows | Where-Object {
      $sourceId = [string]$_.qfu_sourceid__raw
      ($sourceId -match "budgetarchive") -or ($sourceId -match "budgettarget")
    }
  )
  $budgetArchiveSchemeRows = @(
    $budgetArchiveRows |
      Group-Object { Get-GroupKey -Row $_ -Fields @("qfu_branchcode", "qfu_year", "qfu_month", "qfu_fiscalyear") } |
      Where-Object {
        $schemes = @(
          $_.Group |
            ForEach-Object {
              $sourceId = [string]$_.qfu_sourceid__raw
              if ($sourceId -match "budgetarchive") { "budgetarchive" }
              elseif ($sourceId -match "budgettarget") { "budgettarget" }
              else { "other" }
            } |
            Select-Object -Unique
        )
        $schemes.Count -gt 1
      } |
      ForEach-Object { $_.Group }
  )
  $budgetArchiveCollisionRows = @(
    ($budgetArchiveLogicalMonthRows + $budgetArchiveSourceIdRows + $budgetArchiveSchemeRows) |
      Sort-Object _primaryid -Unique
  )
  $budgetArchiveSummary = [ordered]@{
    entity = "qfu_budgetarchive"
    duplicate_logical_month_group_count = $budgetArchiveDuplicateGroups.Count
    duplicate_logical_month_row_count = $budgetArchiveLogicalMonthRows.Count
    mixed_source_scheme_row_count = $budgetArchiveSchemeRows.Count
    sourceid_keyword_row_count = $budgetArchiveSourceIdRows.Count
  }
  Write-FocusedExtract -Name "qfu_budgetarchive-collisions" -Rows $budgetArchiveCollisionRows -Summary $budgetArchiveSummary -Note @"
Grouping logic:
- Include all qfu_budgetarchive rows that collide on qfu_branchcode + qfu_year + qfu_month + qfu_fiscalyear.
- Include all rows whose qfu_sourceid contains budgetarchive or budgettarget.
- Include logical month groups where multiple sourceid schemes coexist.
"@ -OutputRoot $OutputRoot

  $quoteRows = @($EntityExports["qfu_quote"].rows)
  $quoteDuplicateGroups = @(
    $quoteRows |
      Group-Object { [string]$_.qfu_sourceid__raw } |
      Where-Object { $_.Name -and $_.Count -gt 1 }
  )
  $quoteDuplicateRows = @($quoteDuplicateGroups | ForEach-Object { $_.Group })
  $quoteSummary = [ordered]@{
    entity = "qfu_quote"
    grouping_field = "qfu_sourceid"
    duplicate_group_count = $quoteDuplicateGroups.Count
    duplicate_row_count = $quoteDuplicateRows.Count
    groups = @(
      $quoteDuplicateGroups | ForEach-Object {
        [ordered]@{
          qfu_sourceid = $_.Name
          count = $_.Count
          quotenumbers = @($_.Group | ForEach-Object { $_.qfu_quotenumber__raw } | Select-Object -Unique)
        }
      }
    )
  }
  Write-FocusedExtract -Name "qfu_quote-duplicates" -Rows $quoteDuplicateRows -Summary $quoteSummary -Note @"
Grouping logic:
- Group qfu_quote rows by qfu_sourceid.
- Export all rows from duplicate sourceid groups and include quotenumber context when present.
"@ -OutputRoot $OutputRoot

  $financeRows = @($EntityExports["qfu_financesnapshot"].rows)
  $financeWithDates = foreach ($row in $financeRows) {
    $effectiveTimestamp = Parse-CrmDateValue -Value $row.qfu_lastupdated__raw
    if (-not $effectiveTimestamp) { $effectiveTimestamp = Parse-CrmDateValue -Value $row.modifiedon__raw }
    if (-not $effectiveTimestamp) { $effectiveTimestamp = Parse-CrmDateValue -Value $row.createdon__raw }

    $logicalMonthSort = 0
    if ($row.qfu_year__raw -and $row.qfu_month__raw) {
      $logicalMonthSort = ([int]$row.qfu_year__raw * 100) + [int]$row.qfu_month__raw
    }

    [pscustomobject]@{
      row = $row
      timestamp = $effectiveTimestamp
      logicalMonthSort = $logicalMonthSort
      branch = [string]$row.qfu_branchcode__raw
    }
  }
  $financeTrapRows = New-Object System.Collections.Generic.List[object]
  $financeTrapPairs = New-Object System.Collections.Generic.List[object]
  foreach ($branchGroup in ($financeWithDates | Group-Object branch)) {
    $items = @($branchGroup.Group | Where-Object { $_.logicalMonthSort -gt 0 -and $_.timestamp } | Sort-Object logicalMonthSort)
    for ($i = 0; $i -lt $items.Count; $i++) {
      for ($j = $i + 1; $j -lt $items.Count; $j++) {
        $older = $items[$i]
        $newer = $items[$j]
        if ($older.timestamp -gt $newer.timestamp) {
          $financeTrapRows.Add($older.row)
          $financeTrapRows.Add($newer.row)
          $financeTrapPairs.Add([pscustomobject]@{
            branch = $branchGroup.Name
            older_month = $older.logicalMonthSort
            older_timestamp = $older.timestamp.ToString("o")
            newer_month = $newer.logicalMonthSort
            newer_timestamp = $newer.timestamp.ToString("o")
          })
        }
      }
    }
  }
  $financeTrapRowSet = @($financeTrapRows | Sort-Object _primaryid -Unique)
  $financeSummary = [ordered]@{
    entity = "qfu_financesnapshot"
    trap_pair_count = $financeTrapPairs.Count
    trap_row_count = $financeTrapRowSet.Count
    pairs = @($financeTrapPairs | ForEach-Object { $_ })
  }
  Write-FocusedExtract -Name "qfu_financesnapshot-latest-month-traps" -Rows $financeTrapRowSet -Summary $financeSummary -Note @"
Grouping logic:
- Within each branch, compute logical month from qfu_year + qfu_month.
- Compare logical month ordering to effective timestamp order using qfu_lastupdated, falling back to modifiedon and createdon.
- Export rows where an older month has a newer timestamp than a newer month.
"@ -OutputRoot $OutputRoot

  $ingestionRows = @($EntityExports["qfu_ingestionbatch"].rows)
  $recentIngestionRows = @(
    $ingestionRows | Where-Object {
      $dt = Parse-CrmDateValue -Value $_.createdon__raw
      $dt -and $dt -ge (Get-Date).ToUniversalTime().AddDays(-30)
    }
  )
  $ingestionGroups = @(
    $recentIngestionRows |
      Group-Object {
        $branch = if ($_.qfu_branchcode__raw) { [string]$_.qfu_branchcode__raw } else { [string]$_.qfu_branchslug__raw }
        $family = if ($_.qfu_sourcefamily__raw) { [string]$_.qfu_sourcefamily__raw } else { [string]$_.qfu_sourcefeed__raw }
        "{0}||{1}" -f $branch, $family
      }
  )
  $ingestionSummary = [ordered]@{
    entity = "qfu_ingestionbatch"
    window_days = 30
    row_count = $recentIngestionRows.Count
    groups = @(
      $ingestionGroups | ForEach-Object {
        $parts = $_.Name -split "\|\|", 2
        [ordered]@{
          branch = $parts[0]
          source_family = if ($parts.Count -gt 1) { $parts[1] } else { "" }
          count = $_.Count
        }
      }
    )
  }
  Write-FocusedExtract -Name "qfu_ingestionbatch-freshness-evidence" -Rows $recentIngestionRows -Summary $ingestionSummary -Note @"
Grouping logic:
- Export qfu_ingestionbatch rows from the most recent 30 days for the live branches.
- Summarize by branch and source family/feed so freshness logic can be audited.
"@ -OutputRoot $OutputRoot
}

function Copy-SourceInputSamples {
  param(
    [string]$LegacyRoot,
    [string]$OutputRoot
  )

  Ensure-Directory -Path $OutputRoot

  $sampleMappings = @(
    @{
      label = "SA1300 budget source files"
      source = Join-Path $LegacyRoot "Latest"
      target = Join-Path $OutputRoot "sa1300"
      filter = "SA1300.xlsx"
    },
    @{
      label = "SP830CA quote follow-up source files"
      source = Join-Path $LegacyRoot "Latest"
      target = Join-Path $OutputRoot "sp830ca"
      filter = "SP830CA - Quote Follow Up Report.xlsx"
    },
    @{
      label = "ZBO backorder source files"
      source = Join-Path $LegacyRoot "Latest"
      target = Join-Path $OutputRoot "zbo"
      filter = "CA ZBO *.xlsx"
    },
    @{
      label = "GL060 source PDFs from DATA"
      source = Join-Path $LegacyRoot "DATA\\GL060"
      target = Join-Path $OutputRoot "gl060-data"
      filter = "*.pdf"
    },
    @{
      label = "GL060 representative source PDFs from example"
      source = Join-Path $LegacyRoot "example"
      target = Join-Path $OutputRoot "gl060-example"
      filter = "*.pdf"
    }
  )

  foreach ($mapping in $sampleMappings) {
    if (-not (Test-Path -LiteralPath $mapping.source)) {
      $missingItems.Add([pscustomobject]@{
        category = "source-input"
        item = $mapping.label
        status = "NOT FOUND"
        detail = $mapping.source
      })
      continue
    }

    Ensure-Directory -Path $mapping.target
    $files = Get-ChildItem -Path $mapping.source -Recurse -File -Filter $mapping.filter
    if ($files.Count -eq 0) {
      $missingItems.Add([pscustomobject]@{
        category = "source-input"
        item = $mapping.label
        status = "NOT FOUND"
        detail = "No files matched filter $($mapping.filter) under $($mapping.source)"
      })
      continue
    }

    foreach ($file in $files) {
      $relative = $file.FullName.Substring($mapping.source.Length).TrimStart("\")
      $destination = Join-Path $mapping.target $relative
      Ensure-Directory -Path (Split-Path -Parent $destination)
      Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
    }

    $foundItems.Add([pscustomobject]@{
      category = "source-input"
      item = $mapping.label
      status = "FOUND"
      detail = $mapping.target
    })
  }

  $sourcefeedFiles = Get-ChildItem -Path $LegacyRoot -Recurse -File | Where-Object { $_.Name -match "sourcefeed" }
  if ($sourcefeedFiles.Count -gt 0) {
    $target = Join-Path $OutputRoot "sourcefeed-related"
    Ensure-Directory -Path $target
    foreach ($file in $sourcefeedFiles) {
      $destination = Join-Path $target $file.Name
      Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
    }
    $foundItems.Add([pscustomobject]@{
      category = "source-input"
      item = "sourcefeed-related mapping/config files"
      status = "FOUND BUT PATH DIFFERENT"
      detail = $target
    })
  }
  else {
    $missingItems.Add([pscustomobject]@{
      category = "source-input"
      item = "delivery-not-PGI or sourcefeed mapping/config exports outside Dataverse"
      status = "NOT FOUND"
      detail = "No filesystem samples matching delivery/sourcefeed mappings were found under the legacy evidence root."
    })
  }
}

function Get-RelativePathSafe {
  param(
    [string]$BasePath,
    [string]$FullPath
  )

  $base = [System.IO.Path]::GetFullPath($BasePath)
  $full = [System.IO.Path]::GetFullPath($FullPath)
  $baseUri = New-Object System.Uri(($base.TrimEnd("\") + "\"))
  $fullUri = New-Object System.Uri($full)
  $relativeUri = $baseUri.MakeRelativeUri($fullUri)
  return [System.Uri]::UnescapeDataString($relativeUri.ToString()).Replace("/", "\")
}

function Write-RouteRuntimeTraceability {
  param(
    [string]$SiteRoot,
    [string]$OutputPath
  )

  $routeSpecs = @(
    @{ route = "/"; pageDir = "hub"; pageMode = "hub" },
    @{ route = "/southern-alberta"; pageDir = "southern-alberta"; pageMode = "region" },
    @{ route = "/southern-alberta/4171"; pageDir = "4171-calgary"; pageMode = "branch" },
    @{ route = "/southern-alberta/4172"; pageDir = "4172-lethbridge"; pageMode = "branch" },
    @{ route = "/southern-alberta/4173"; pageDir = "4173-medicine-hat"; pageMode = "branch" },
    @{ route = "/southern-alberta/{branch}/detail"; pageDir = "detail-shell_4aa958d9"; pageMode = "detail" },
    @{ route = "/ops--admin"; pageDir = "ops---admin"; pageMode = "ops-admin" }
  )

  $runtimePath = Join-Path $SiteRoot "web-templates\qfu-regional-runtime\QFU-Regional-Runtime.webtemplate.source.html"
  $phase0CssPath = Join-Path $SiteRoot "web-files\qfu-phase0.css"
  $pageTemplatePath = Join-Path $SiteRoot "page-templates\Default-studio-template.pagetemplate.yml"

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("# Route / Page / Runtime Traceability")
  $lines.Add("")
  $lines.Add('The mappings below were derived from the current live Power Pages source under `RAW/powerpages-current`.')
  $lines.Add("")

  foreach ($spec in $routeSpecs) {
    $pageDir = Join-Path $SiteRoot ("web-pages\{0}" -f $spec.pageDir)
    $ymlPath = Get-ChildItem -Path $pageDir -Filter "*.webpage.yml" -File | Where-Object { $_.FullName -notmatch "\\content-pages\\" } | Select-Object -First 1
    $copyPath = Get-ChildItem -Path $pageDir -Filter "*.webpage.copy.html" -File | Where-Object { $_.FullName -notmatch "\\content-pages\\" } | Select-Object -First 1
    $customCssPath = Get-ChildItem -Path $pageDir -Filter "*.webpage.custom_css.css" -File | Where-Object { $_.FullName -notmatch "\\content-pages\\" } | Select-Object -First 1
    $customJsPath = Get-ChildItem -Path $pageDir -Filter "*.webpage.custom_javascript.js" -File | Where-Object { $_.FullName -notmatch "\\content-pages\\" } | Select-Object -First 1

    $usesSharedRuntime = $false
    if ($copyPath) {
      $copyContent = Get-Content -LiteralPath $copyPath.FullName -Raw
      $usesSharedRuntime = $copyContent -match "QFU Regional Runtime"
    }

    $pageSourceText = if ($ymlPath) { Get-RelativePathSafe -BasePath $SiteRoot -FullPath $ymlPath.FullName } else { "NOT FOUND" }
    $pageCopyText = if ($copyPath) { Get-RelativePathSafe -BasePath $SiteRoot -FullPath $copyPath.FullName } else { "NOT FOUND" }
    $runtimeUsageText = if ($usesSharedRuntime) { "yes" } else { "no / not detectable" }
    $runtimeFileText = Get-RelativePathSafe -BasePath $SiteRoot -FullPath $runtimePath
    $pageTemplateText = Get-RelativePathSafe -BasePath $SiteRoot -FullPath $pageTemplatePath
    $phase0CssText = Get-RelativePathSafe -BasePath $SiteRoot -FullPath $phase0CssPath

    $routeHeading = '## `{0}`' -f $spec.route
    $pageSourceLine = '- page source file: `{0}`' -f $pageSourceText
    $pageCopyLine = '- page copy file: `{0}`' -f $pageCopyText
    $sharedRuntimeLine = '- shared runtime: `{0}`' -f $runtimeUsageText
    $runtimeFileLine = '- runtime file: `{0}`' -f $runtimeFileText
    $pageTemplateLine = '- page template: `{0}`' -f $pageTemplateText
    $phase0CssLine = '  - `{0}`' -f $phase0CssText

    $lines.Add($routeHeading)
    $lines.Add("")
    $lines.Add($pageSourceLine)
    $lines.Add($pageCopyLine)
    $lines.Add($sharedRuntimeLine)
    $lines.Add($runtimeFileLine)
    $lines.Add($pageTemplateLine)
    $lines.Add("- dependent web files:")
    $lines.Add($phase0CssLine)
    if ($customCssPath) {
      $customCssLine = '  - `{0}`' -f (Get-RelativePathSafe -BasePath $SiteRoot -FullPath $customCssPath.FullName)
      $lines.Add($customCssLine)
    }
    if ($customJsPath) {
      $customJsLine = '  - `{0}`' -f (Get-RelativePathSafe -BasePath $SiteRoot -FullPath $customJsPath.FullName)
      $lines.Add($customJsLine)
    }
    $lines.Add("")
  }

  Set-Content -LiteralPath $OutputPath -Value $lines -Encoding UTF8
}

function Write-AuthoritativeVsArchivalDiff {
  param(
    [string]$StagingRoot,
    [string]$OutputPath
  )

  $rawRoot = Join-Path $StagingRoot "RAW"
  $currentRoot = Join-Path $rawRoot "powerpages-current"
  $archivalRoot = Join-Path $rawRoot $liveRefreshFolderName
  $runtimeCandidates = @(
    Get-ChildItem -Path $rawRoot -Recurse -File -Filter "QFU-Regional-Runtime.webtemplate.source.html"
  )

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("# Authoritative vs Archival Source Check")
  $lines.Add("")
  $lines.Add('- current source root: `RAW/powerpages-current`')
  $lines.Add(('- archival/live-refresh root: `RAW/{0}`' -f $liveRefreshFolderName))
  $lines.Add("")
  $lines.Add("## Runtime file hashes")
  $lines.Add("")

  foreach ($file in $runtimeCandidates) {
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash
    $relative = Get-RelativePathSafe -BasePath $StagingRoot -FullPath $file.FullName
    $lines.Add(('- `{0}`  `{1}`' -f $relative, $hash))
  }

  $currentRuntime = Join-Path $currentRoot "web-templates\qfu-regional-runtime\QFU-Regional-Runtime.webtemplate.source.html"
  $refreshRuntime = Join-Path $archivalRoot "web-templates\qfu-regional-runtime\QFU-Regional-Runtime.webtemplate.source.html"
  $lines.Add("")
  $lines.Add("## Current vs live-refresh comparison")
  $lines.Add("")
  if ((Test-Path -LiteralPath $currentRuntime) -and (Test-Path -LiteralPath $refreshRuntime)) {
    $currentHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $currentRuntime).Hash
    $refreshHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $refreshRuntime).Hash
    if ($currentHash -eq $refreshHash) {
      $lines.Add('- `QFU-Regional-Runtime.webtemplate.source.html` hashes match between current and live-refresh.')
    }
    else {
      $lines.Add('- `QFU-Regional-Runtime.webtemplate.source.html` hashes differ between current and live-refresh.')
      $diff = Compare-Object -ReferenceObject (Get-Content -LiteralPath $currentRuntime) -DifferenceObject (Get-Content -LiteralPath $refreshRuntime) -IncludeEqual:$false
      $lines.Add("- first differing lines (up to 20):")
      foreach ($entry in ($diff | Select-Object -First 20)) {
        $lines.Add(("  - {0} {1}" -f $entry.SideIndicator, $entry.InputObject))
      }
    }
  }
  else {
    $lines.Add("- Could not compare authoritative and live-refresh runtime copies because one or both files were missing.")
  }

  Set-Content -LiteralPath $OutputPath -Value $lines -Encoding UTF8
}

function Write-FoundVsMissing {
  param([string]$OutputPath)

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("# Found vs Missing")
  $lines.Add("")

  foreach ($status in @("FOUND", "FOUND BUT PATH DIFFERENT", "NOT FOUND", "COULD NOT EXPORT")) {
    $lines.Add("## $status")
    $lines.Add("")
    $allItems = @($foundItems.ToArray()) + @($missingItems.ToArray())
    $items = @($allItems | Where-Object { $_.status -eq $status })
    if ($items.Count -eq 0) {
      $lines.Add("- none")
    }
    else {
      foreach ($item in $items) {
        $lines.Add(("- **{0}** [{1}] - {2}" -f $item.item, $item.category, $item.detail))
      }
    }
    $lines.Add("")
  }

  Set-Content -LiteralPath $OutputPath -Value $lines -Encoding UTF8
}

function Write-SearchIndex {
  param(
    [string]$StagingRoot,
    [string]$OutputPath
  )

  $patterns = @(
    "qfu_isactive",
    "qfu_sourceid",
    "budgetarchive",
    "budgettarget",
    "createdon",
    "qfu_sourcedate",
    "qfu_billingdate",
    "qfu_snapshotdate",
    "qfu_budget",
    "qfu_budgetarchive",
    "qfu_quote",
    "qfu_financesnapshot",
    "qfu_financevariance",
    "qfu_branchdailysummary",
    "qfu_ingestionbatch",
    "4171",
    "4172",
    "4173"
  )

  $searchRoots = @(
    (Join-Path $StagingRoot "RAW"),
    (Join-Path $StagingRoot "DATA")
  )

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("# Search Index")
  $lines.Add("")
  foreach ($pattern in $patterns) {
    $lines.Add("## $pattern")
    $lines.Add("")
    $matches = @(
      Get-ChildItem -Path $searchRoots -Recurse -File -ErrorAction SilentlyContinue |
        Select-String -Pattern $pattern -SimpleMatch -ErrorAction SilentlyContinue
    )
    if ($matches.Count -eq 0) {
      $lines.Add("- no matches")
    }
    else {
      foreach ($match in $matches) {
        $relative = Get-RelativePathSafe -BasePath $StagingRoot -FullPath $match.Path
        $context = $match.Line.Trim()
        $lines.Add(('- `{0}:{1}` `{2}`' -f $relative, $match.LineNumber, $context))
      }
    }
    $lines.Add("")
  }

  Set-Content -LiteralPath $OutputPath -Value $lines -Encoding UTF8
}

function Write-FileCounts {
  param(
    [string]$StagingRoot,
    [string]$OutputPath
  )

  $targets = @(
    "RAW",
    "RAW\powerpages-current",
    "RAW\scripts",
    ("RAW\{0}" -f $liveRefreshFolderName),
    "RAW\solution-current",
    "RAW\results-current",
    "DATA",
    "DATA\dataverse-metadata",
    "DATA\dataverse-rows",
    "DATA\duplicate-and-collision-cases",
    "DATA\source-input-samples",
    "INVENTORY"
  )

  $lines = foreach ($target in $targets) {
    $path = Join-Path $StagingRoot $target
    if (Test-Path -LiteralPath $path) {
      $count = @(Get-ChildItem -Path $path -Recurse -File).Count
      "{0}`t{1}" -f $target, $count
    }
    else {
      "{0}`tMISSING" -f $target
    }
  }

  Set-Content -LiteralPath $OutputPath -Value $lines -Encoding UTF8
}

function Write-DataverseMethodReport {
  param(
    [datetime]$CutoffDate,
    [string]$OutputPath
  )

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("# Dataverse Export Method")
  $lines.Add("")
  $lines.Add('- tool used: `Microsoft.Xrm.Data.Powershell` via `Connect-CrmOnline`, `Get-CrmEntityMetadata`, and `Get-CrmRecordsByFetch`')
  $lines.Add('- environment: `https://regionaloperationshub.crm.dynamics.com`')
  $lines.Add('- website read-only refresh tool: `pac pages download`')
  $lines.Add(('- date range target: last {0} days (cutoff `{1}`) for operational tables when a usable date field exists' -f $OperationalHistoryDays, $CutoffDate.ToString("yyyy-MM-dd")))
  $lines.Add('- branch scope: `4171`, `4172`, `4173` when `qfu_branchcode` exists')
  $lines.Add('- region scope fallback: `southern-alberta` when `qfu_regionslug` exists and branch code does not')
  $lines.Add('- config tables exported without date trimming: `qfu_branch`, `qfu_region`, `qfu_sourcefeed`')
  $lines.Add("- row exports keep original values, nulls, booleans, and system fields where returned")
  $lines.Add("- no POST, PATCH, DELETE, activation, deployment, or repair actions were performed by this bundle build")
  $lines.Add("")
  $lines.Add("## Per-entity export notes")
  $lines.Add("")
  foreach ($note in $dataverseExportNotes) {
    $lines.Add(('- `{0}` [{1}] filter=`{2}` date_window=`{3}` format=`{4}` note=`{5}`' -f $note.entity, $note.export_type, $note.filter, $note.date_window, $note.format, $note.notes))
  }

  Set-Content -LiteralPath $OutputPath -Value $lines -Encoding UTF8
}

function Write-DuplicateSummary {
  param(
    [string]$FocusedRoot,
    [string]$OutputPath
  )

  $budgetSummary = Get-Content -LiteralPath (Join-Path $FocusedRoot "qfu_budget-duplicates\summary.json") -Raw | ConvertFrom-Json
  $budgetArchiveSummary = Get-Content -LiteralPath (Join-Path $FocusedRoot "qfu_budgetarchive-collisions\summary.json") -Raw | ConvertFrom-Json
  $quoteSummary = Get-Content -LiteralPath (Join-Path $FocusedRoot "qfu_quote-duplicates\summary.json") -Raw | ConvertFrom-Json
  $financeSummary = Get-Content -LiteralPath (Join-Path $FocusedRoot "qfu_financesnapshot-latest-month-traps\summary.json") -Raw | ConvertFrom-Json
  $ingestionSummary = Get-Content -LiteralPath (Join-Path $FocusedRoot "qfu_ingestionbatch-freshness-evidence\summary.json") -Raw | ConvertFrom-Json

  $lines = @(
    "# Duplicate Summary",
    "",
    "- duplicate qfu_budget groups found: $($budgetSummary.duplicate_group_count)",
    "- duplicate qfu_budgetarchive logical months found: $($budgetArchiveSummary.duplicate_logical_month_group_count)",
    "- duplicate qfu_quote qfu_sourceids found: $($quoteSummary.duplicate_group_count)",
    "- finance month/timestamp inversions found: $($financeSummary.trap_pair_count)",
    "",
    "## Recent qfu_ingestionbatch counts by branch/source family",
    ""
  )
  foreach ($group in @($ingestionSummary.groups)) {
    $lines += ('- branch=`{0}` source_family=`{1}` count=`{2}`' -f $group.branch, $group.source_family, $group.count)
  }

  Set-Content -LiteralPath $OutputPath -Value $lines -Encoding UTF8
}

function Write-Readme {
  param([string]$OutputPath)

  $content = @"
# QFU Final Audit Evidence Bundle

This bundle is a final, self-contained audit evidence package for the Quote Follow Up regional rollout as of 2026-04-07.

- Purpose: regression and hardening audit only
- Behavior changes: none
- Dataverse mutations: none
- Deployment actions: none
- Exports: read-only snapshots from the current live environment and local authoritative source trees

The bundle includes:
- current and archival Power Pages source trees
- scripts, flow exports, and evidence folders
- Dataverse table metadata
- Dataverse raw row snapshots for the Southern Alberta live branches
- focused duplicate and collision extracts
- representative source input files
- inventory and traceability reports
"@

  Set-Content -LiteralPath $OutputPath -Value $content -Encoding UTF8
}

function Write-TreeFile {
  param(
    [string]$StagingRoot,
    [string]$OutputPath
  )

  tree $StagingRoot /F | Set-Content -LiteralPath $OutputPath -Encoding UTF8
}

function Write-Sha256File {
  param(
    [string]$StagingRoot,
    [string]$OutputPath
  )

  $hashLines = Get-ChildItem -Path $StagingRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash
    "{0}  {1}" -f $hash, (Get-RelativePathSafe -BasePath $StagingRoot -FullPath $_.FullName)
  }

  Set-Content -LiteralPath $OutputPath -Value $hashLines -Encoding UTF8
}

$cutoffDate = (Get-Date).ToUniversalTime().AddDays(-1 * $OperationalHistoryDays)

if (Test-Path -LiteralPath $StagingRoot) {
  Remove-Item -LiteralPath $StagingRoot -Recurse -Force
}
Ensure-Directory -Path $StagingRoot

if (Test-Path -LiteralPath $ZipPath) {
  Remove-Item -LiteralPath $ZipPath -Force
}

$inventoryRoot = Join-Path $StagingRoot "INVENTORY"
$rawRoot = Join-Path $StagingRoot "RAW"
$dataRoot = Join-Path $StagingRoot "DATA"
$metadataRoot = Join-Path $dataRoot "dataverse-metadata"
$rowsRoot = Join-Path $dataRoot "dataverse-rows"
$duplicateRoot = Join-Path $dataRoot "duplicate-and-collision-cases"
$sourceInputRoot = Join-Path $dataRoot "source-input-samples"

Ensure-Directory -Path $inventoryRoot
Ensure-Directory -Path $rawRoot
Ensure-Directory -Path $metadataRoot
Ensure-Directory -Path $rowsRoot
Ensure-Directory -Path $duplicateRoot
Ensure-Directory -Path $sourceInputRoot

$rawMappings = @(
  @{
    label = "current Power Pages source tree"
    source = Join-Path $RepoRoot "site"
    target = Join-Path $rawRoot "powerpages-current"
  },
  @{
    label = "legacy scripts tree"
    source = Join-Path $LegacyEvidenceRoot "scripts"
    target = Join-Path $rawRoot "scripts"
  },
  @{
    label = "legacy solution tree"
    source = Join-Path $LegacyEvidenceRoot "solution"
    target = Join-Path $rawRoot "solution-current"
  },
  @{
    label = "legacy results tree"
    source = Join-Path $LegacyEvidenceRoot "results"
    target = Join-Path $rawRoot "results-current"
  },
  @{
    label = "legacy powerpages-live tree"
    source = Join-Path $LegacyEvidenceRoot "powerpages-live"
    target = Join-Path $rawRoot "powerpages-live-archival"
  },
  @{
    label = "legacy powerpages source tree"
    source = Join-Path $LegacyEvidenceRoot "powerpages"
    target = Join-Path $rawRoot "powerpages-archival"
  }
)

foreach ($mapping in $rawMappings) {
  if (Invoke-RobocopyMirror -Source $mapping.source -Destination $mapping.target) {
    $foundItems.Add([pscustomobject]@{
      category = "raw-tree"
      item = $mapping.label
      status = "FOUND"
      detail = $mapping.target
    })
  }
  else {
    $missingItems.Add([pscustomobject]@{
      category = "raw-tree"
      item = $mapping.label
      status = "NOT FOUND"
      detail = $mapping.source
    })
  }
}

$liveRefreshPath = Join-Path $rawRoot $liveRefreshFolderName
Ensure-Directory -Path $liveRefreshPath
& pac pages download --path $liveRefreshPath --webSiteId $WebsiteId --environment $TargetEnvironmentUrl -mv Enhanced
if ($LASTEXITCODE -ne 0) {
  $missingItems.Add([pscustomobject]@{
    category = "raw-tree"
    item = "fresh live Power Pages export"
    status = "COULD NOT EXPORT"
    detail = "pac pages download failed for $liveRefreshPath"
  })
}
else {
  $foundItems.Add([pscustomobject]@{
    category = "raw-tree"
    item = "fresh live Power Pages export"
    status = "FOUND"
    detail = $liveRefreshPath
  })
}

Copy-SourceInputSamples -LegacyRoot $LegacyEvidenceRoot -OutputRoot $sourceInputRoot

$flowEvidenceChecks = @(
  @{
    item = "QFU-Regional-Runtime.webtemplate.source.html"
    path = Join-Path $rawRoot "powerpages-current\web-templates\qfu-regional-runtime\QFU-Regional-Runtime.webtemplate.source.html"
  },
  @{
    item = "Hub / Southern Alberta / 4171 / 4172 / 4173 / Detail Shell / Ops-Admin page source"
    path = Join-Path $rawRoot "powerpages-current\web-pages"
  },
  @{
    item = "SA1300 budget flow export"
    path = Join-Path $rawRoot "solution-current\src\Workflows\Budget_Update_From_SA1300_Unmanaged-F4FDE436-F3BB-F011-BBD3-6045BD0A8FB0.json"
  },
  @{
    item = "GL060 flow export"
    path = Join-Path $rawRoot "solution-current\src\Workflows\GL060*.json"
  },
  @{
    item = "temp mailbox capture flow export"
    path = Join-Path $rawRoot "solution-current\src\Workflows\*Temp*Mailbox*Capture*.json"
  },
  @{
    item = "repair / normalize / deploy scripts"
    path = Join-Path $rawRoot "scripts"
  }
)

foreach ($check in $flowEvidenceChecks) {
  $matches = Get-ChildItem -Path $check.path -ErrorAction SilentlyContinue
  if ($matches) {
    $foundItems.Add([pscustomobject]@{
      category = "required-evidence"
      item = $check.item
      status = "FOUND"
      detail = ($matches | Select-Object -ExpandProperty FullName -First 3) -join "; "
    })
  }
  else {
    $missingItems.Add([pscustomobject]@{
      category = "required-evidence"
      item = $check.item
      status = "NOT FOUND"
      detail = $check.path
    })
  }
}

$connection = Connect-Org -Url $TargetEnvironmentUrl -User $Username
$metadataSummaryRows = New-Object System.Collections.Generic.List[object]
Export-Metadata -Connection $connection -OutputRoot $metadataRoot -SummaryRows $metadataSummaryRows
$metadataSummaryRows | Export-Csv -LiteralPath (Join-Path $metadataRoot "dataverse-metadata-summary.csv") -NoTypeInformation -Encoding UTF8

$entityExports = @{}
foreach ($table in $requiredTables) {
  $entityExports[$table] = Export-EntityRows -Connection $connection -EntityLogicalName $table -CutoffDate $cutoffDate -OutputRoot $rowsRoot
}

Export-DuplicateCases -EntityExports $entityExports -OutputRoot $duplicateRoot

Write-Readme -OutputPath (Join-Path $StagingRoot "README_FINAL_AUDIT_BUNDLE.md")
Write-RouteRuntimeTraceability -SiteRoot (Join-Path $rawRoot "powerpages-current") -OutputPath (Join-Path $inventoryRoot "route-runtime-traceability.md")
Write-AuthoritativeVsArchivalDiff -StagingRoot $StagingRoot -OutputPath (Join-Path $inventoryRoot "authoritative-vs-archival-diff.md")
Write-DataverseMethodReport -CutoffDate $cutoffDate -OutputPath (Join-Path $inventoryRoot "dataverse-export-method.md")
Write-DuplicateSummary -FocusedRoot $duplicateRoot -OutputPath (Join-Path $inventoryRoot "duplicate-summary.md")
Write-FoundVsMissing -OutputPath (Join-Path $inventoryRoot "found-vs-missing.md")
Write-SearchIndex -StagingRoot $StagingRoot -OutputPath (Join-Path $inventoryRoot "search-index.txt")
Write-FileCounts -StagingRoot $StagingRoot -OutputPath (Join-Path $inventoryRoot "file-counts.txt")
Write-TreeFile -StagingRoot $StagingRoot -OutputPath (Join-Path $inventoryRoot "tree.txt")
Write-Sha256File -StagingRoot $StagingRoot -OutputPath (Join-Path $inventoryRoot "sha256.txt")

$allFiles = @(Get-ChildItem -Path $StagingRoot -Recurse -File)
$topLevelCounts = [ordered]@{}
foreach ($folder in @("RAW", "DATA", "INVENTORY")) {
  $path = Join-Path $StagingRoot $folder
  $topLevelCounts[$folder] = if (Test-Path -LiteralPath $path) { @(Get-ChildItem -Path $path -Recurse -File).Count } else { 0 }
}

$foundCount = (@($foundItems.ToArray() | Where-Object { $_.status -like "FOUND*" })).Count
$missingCount = $missingItems.Count
$summaryLines = @(
  "",
  "Summary",
  "RAW`t$($topLevelCounts['RAW'])",
  "DATA`t$($topLevelCounts['DATA'])",
  "INVENTORY`t$($topLevelCounts['INVENTORY'])",
  "",
  "Found items`t$foundCount",
  "Missing or could-not-export items`t$missingCount"
)
Add-Content -LiteralPath (Join-Path $inventoryRoot "file-counts.txt") -Value $summaryLines -Encoding UTF8

try {
  Compress-Archive -Path (Join-Path $StagingRoot "*") -DestinationPath $ZipPath -CompressionLevel Optimal
}
catch {
  if (Test-Path -LiteralPath $ZipPath) {
    Remove-Item -LiteralPath $ZipPath -Force
  }
  & tar.exe -a -cf $ZipPath -C $StagingRoot .
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $ZipPath)) {
    throw
  }
}

$zipInfo = Get-Item -LiteralPath $ZipPath
$result = [ordered]@{
  staging_root = $StagingRoot
  zip_path = $ZipPath
  file_count = $allFiles.Count
  zip_size_bytes = $zipInfo.Length
  found_count = $foundCount
  missing_count = $missingCount
}
$result | ConvertTo-Json -Depth 6
