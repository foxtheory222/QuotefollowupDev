param(
  [string]$TargetEnvironmentUrl = "https://regionaloperationshub.crm.dynamics.com",
  [string]$Username = "smcfarlane@applied.com",
  [string[]]$BranchCodes = @("4171", "4172", "4173"),
  [string]$OutputJson = "VERIFICATION\\operational-current-state-audit.json",
  [string]$OutputMarkdown = "VERIFICATION\\operational-current-state-audit.md"
)

$ErrorActionPreference = "Stop"

Import-Module Microsoft.Xrm.Data.Powershell

function Resolve-RepoPath {
  param([string]$Path)

  if ([System.IO.Path]::IsPathRooted($Path)) {
    return $Path
  }

  return Join-Path (Get-Location) $Path
}

function Ensure-Directory {
  param([string]$Path)

  if (-not [string]::IsNullOrWhiteSpace($Path) -and -not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Write-Utf8File {
  param(
    [string]$Path,
    [string]$Content
  )

  $directory = Split-Path -Parent $Path
  if ($directory) {
    Ensure-Directory -Path $directory
  }

  [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Write-Utf8Json {
  param(
    [string]$Path,
    [object]$Object
  )

  Write-Utf8File -Path $Path -Content ($Object | ConvertTo-Json -Depth 20)
}

function Connect-Target {
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

function Get-DateValue {
  param([object]$Value)

  if ($null -eq $Value) {
    return $null
  }

  try {
    return [datetime]$Value
  } catch {
    return $null
  }
}

function Format-DateValue {
  param([object]$Value)

  $parsed = Get-DateValue -Value $Value
  if ($parsed) {
    return $parsed.ToString("yyyy-MM-dd HH:mm:ss")
  }

  return $null
}

function Get-StringValue {
  param([object]$Value)

  if ($null -eq $Value) {
    return ""
  }

  return [string]$Value
}

function Get-BoolValue {
  param([object]$Value)

  if ($null -eq $Value) {
    return $null
  }

  if ($Value -is [bool]) {
    return [bool]$Value
  }

  $text = ([string]$Value).Trim().ToLowerInvariant()
  if ($text -in @("true", "1", "yes")) {
    return $true
  }
  if ($text -in @("false", "0", "no")) {
    return $false
  }

  return $null
}

function Get-EntityBoolValue {
  param(
    [string]$EntityLogicalName,
    [object]$Value
  )

  if ($Value -is [bool]) {
    return [bool]$Value
  }

  $text = if ($null -eq $Value) { "" } else { ([string]$Value).Trim().ToLowerInvariant() }
  if ($EntityLogicalName -eq "qfu_deliverynotpgi") {
    switch ($text) {
      "yes" { return $false }
      "no" { return $true }
    }
  }

  return Get-BoolValue $Value
}

function Test-RowHasLifecycleValue {
  param(
    [object]$Row,
    [string[]]$FieldNames
  )

  foreach ($fieldName in @($FieldNames)) {
    $property = $Row.PSObject.Properties[$fieldName]
    if (-not $property) {
      continue
    }
    if ($null -eq $property.Value) {
      continue
    }
    if ($property.Value -is [string] -and [string]::IsNullOrWhiteSpace([string]$property.Value)) {
      continue
    }
    return $true
  }

  return $false
}

function Compare-RepairCandidate {
  param(
    [object]$Left,
    [object]$Right,
    [string]$IdField,
    [string]$ActiveField,
    [string]$SnapshotField
  )

  if (-not [string]::IsNullOrWhiteSpace($ActiveField)) {
    $leftEntity = if ($Left.PSObject.Properties["LogicalName"]) { [string]$Left.LogicalName } else { "" }
    $rightEntity = if ($Right.PSObject.Properties["LogicalName"]) { [string]$Right.LogicalName } else { "" }
    $leftActive = if ((Get-EntityBoolValue -EntityLogicalName $leftEntity -Value $Left.$ActiveField) -eq $true) { 1 } else { 0 }
    $rightActive = if ((Get-EntityBoolValue -EntityLogicalName $rightEntity -Value $Right.$ActiveField) -eq $true) { 1 } else { 0 }
    if ($leftActive -ne $rightActive) {
      return $rightActive - $leftActive
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($SnapshotField)) {
    $leftSnapshot = Get-DateValue $Left.$SnapshotField
    $rightSnapshot = Get-DateValue $Right.$SnapshotField
    $leftTicks = if ($leftSnapshot) { $leftSnapshot.Ticks } else { 0 }
    $rightTicks = if ($rightSnapshot) { $rightSnapshot.Ticks } else { 0 }
    if ($leftTicks -ne $rightTicks) {
      return $rightTicks - $leftTicks
    }
  }

  $leftModified = Get-DateValue $Left.modifiedon
  $rightModified = Get-DateValue $Right.modifiedon
  $leftModifiedTicks = if ($leftModified) { $leftModified.Ticks } else { 0 }
  $rightModifiedTicks = if ($rightModified) { $rightModified.Ticks } else { 0 }
  if ($leftModifiedTicks -ne $rightModifiedTicks) {
    return $rightModifiedTicks - $leftModifiedTicks
  }

  $leftCreated = Get-DateValue $Left.createdon
  $rightCreated = Get-DateValue $Right.createdon
  $leftCreatedTicks = if ($leftCreated) { $leftCreated.Ticks } else { 0 }
  $rightCreatedTicks = if ($rightCreated) { $rightCreated.Ticks } else { 0 }
  if ($leftCreatedTicks -ne $rightCreatedTicks) {
    return $rightCreatedTicks - $leftCreatedTicks
  }

  return ([string]$Left.$IdField).CompareTo([string]$Right.$IdField)
}

function Get-EntityAudit {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [hashtable]$Definition,
    [string[]]$BranchCodes
  )

  $rows = @()
  foreach ($branchCode in $BranchCodes) {
    $rows += @(
      (Get-CrmRecords -conn $Connection -EntityLogicalName $Definition.EntityLogicalName -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $branchCode -Fields $Definition.Fields -TopCount 5000).CrmRecords
    )
  }

  $rows = @($rows | Where-Object { $_.qfu_sourceid })
  $duplicateGroups = @(
    $rows |
      Group-Object -Property qfu_branchcode, qfu_sourceid |
      Where-Object { $_.Count -gt 1 }
  )

  $samples = foreach ($group in ($duplicateGroups | Select-Object -First 10)) {
    $ordered = @(
      $group.Group |
        Sort-Object -Property @{
          Expression = {
            if ($Definition.ActiveField) {
              if ((Get-EntityBoolValue -EntityLogicalName $Definition.EntityLogicalName -Value $_.$($Definition.ActiveField)) -eq $true) { 1 } else { 0 }
            } else {
              0
            }
          }
          Descending = $true
        }, @{
          Expression = {
            if ($Definition.SnapshotField) {
              $snapshot = Get-DateValue $_.$($Definition.SnapshotField)
              if ($snapshot) { $snapshot } else { [datetime]::MinValue }
            } else {
              [datetime]::MinValue
            }
          }
          Descending = $true
        }, @{
          Expression = {
            $modified = Get-DateValue $_.modifiedon
            if ($modified) { $modified } else { [datetime]::MinValue }
          }
          Descending = $true
        }, @{
          Expression = {
            $created = Get-DateValue $_.createdon
            if ($created) { $created } else { [datetime]::MinValue }
          }
          Descending = $true
        }, @{
          Expression = { [string]$_.$($Definition.IdField) }
        }
    )

    $winner = $ordered | Select-Object -First 1
    [pscustomobject]@{
      key = [string]$group.Name
      count = $group.Count
      winner_id = [string]$winner.$($Definition.IdField)
      rows = @(
        $ordered | ForEach-Object {
          [pscustomobject]@{
            record_id = [string]$_.$($Definition.IdField)
            branch_code = [string]$_.qfu_branchcode
            source_id = [string]$_.qfu_sourceid
            createdon = Format-DateValue $_.createdon
            modifiedon = Format-DateValue $_.modifiedon
            snapshot_on = if ($Definition.SnapshotField) { Format-DateValue $_.$($Definition.SnapshotField) } else { $null }
            active = if ($Definition.ActiveField) { Get-EntityBoolValue -EntityLogicalName $Definition.EntityLogicalName -Value $_.$($Definition.ActiveField) } else { $null }
            detail_1 = if ($Definition.DetailFields.Count -gt 0) { Get-StringValue $_.$($Definition.DetailFields[0]) } else { $null }
            detail_2 = if ($Definition.DetailFields.Count -gt 1) { Get-StringValue $_.$($Definition.DetailFields[1]) } else { $null }
          }
        }
      )
    }
  }

  $activeDuplicateGroups = if ($Definition.ActiveField) {
    @(
      $duplicateGroups | Where-Object {
        @($_.Group | Where-Object { (Get-EntityBoolValue -EntityLogicalName $Definition.EntityLogicalName -Value $_.$($Definition.ActiveField)) -eq $true }).Count -gt 1
      }
    )
  } else {
    @()
  }

  $activeRowCount = if ($Definition.ActiveField) {
    @(
      $rows | Where-Object {
        (Get-EntityBoolValue -EntityLogicalName $Definition.EntityLogicalName -Value $_.$($Definition.ActiveField)) -eq $true -and -not (Get-DateValue $_.qfu_inactiveon)
      }
    ).Count
  } else {
    $null
  }

  $inactiveRowCount = if ($Definition.ActiveField) {
    @(
      $rows | Where-Object {
        (Get-EntityBoolValue -EntityLogicalName $Definition.EntityLogicalName -Value $_.$($Definition.ActiveField)) -eq $false -or (Get-DateValue $_.qfu_inactiveon)
      }
    ).Count
  } else {
    $null
  }

  $lifecycleMissingCount = if ($Definition.LifecycleFields) {
    @(
      $rows | Where-Object {
        -not (Test-RowHasLifecycleValue -Row $_ -FieldNames $Definition.LifecycleFields)
      }
    ).Count
  } else {
    $null
  }

  return [pscustomobject]@{
    entity = $Definition.EntityLogicalName
    canonical_key = $Definition.CanonicalKey
    table_role = $Definition.TableRole
    total_rows = $rows.Count
    unique_source_ids = @($rows | Select-Object -ExpandProperty qfu_sourceid -Unique).Count
    duplicate_group_count = $duplicateGroups.Count
    duplicate_row_count = @($duplicateGroups | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
    active_duplicate_group_count = $activeDuplicateGroups.Count
    active_row_count = $activeRowCount
    inactive_row_count = $inactiveRowCount
    lifecycle_missing_count = $lifecycleMissingCount
    sample_groups = @($samples)
  }
}

function Get-LatestImportSummary {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string[]]$BranchCodes
  )

  $families = @("SP830CA", "ZBO", "SA1300", "SA1300-ABNORMALMARGIN")
  $rows = @(
    (Get-CrmRecords -conn $Connection -EntityLogicalName "qfu_ingestionbatch" -Fields @(
      "qfu_ingestionbatchid",
      "qfu_branchcode",
      "qfu_sourcefamily",
      "qfu_sourcefilename",
      "qfu_status",
      "qfu_startedon",
      "qfu_completedon",
      "qfu_triggerflow",
      "qfu_notes",
      "createdon",
      "modifiedon"
    ) -TopCount 5000).CrmRecords |
      Where-Object { $_.qfu_branchcode -in $BranchCodes -and $_.qfu_sourcefamily -in $families }
  )

  $summary = foreach ($branchCode in $BranchCodes) {
    foreach ($family in $families) {
      $latest = @(
        $rows |
          Where-Object { [string]$_.qfu_branchcode -eq $branchCode -and [string]$_.qfu_sourcefamily -eq $family } |
          Sort-Object -Property @{
            Expression = {
              $completed = Get-DateValue $_.qfu_completedon
              if ($completed) { $completed } else { [datetime]::MinValue }
            }
            Descending = $true
          }, @{
            Expression = {
              $started = Get-DateValue $_.qfu_startedon
              if ($started) { $started } else { [datetime]::MinValue }
            }
            Descending = $true
          }, @{
            Expression = {
              $created = Get-DateValue $_.createdon
              if ($created) { $created } else { [datetime]::MinValue }
            }
            Descending = $true
          }
      ) | Select-Object -First 1

      [pscustomobject]@{
        branch_code = $branchCode
        source_family = $family
        latest_status = if ($latest) { [string]$latest.qfu_status } else { $null }
        source_filename = if ($latest) { [string]$latest.qfu_sourcefilename } else { $null }
        source_startedon = if ($latest) { Format-DateValue $latest.qfu_startedon } else { $null }
        source_completedon = if ($latest) { Format-DateValue $latest.qfu_completedon } else { $null }
        row_createdon = if ($latest) { Format-DateValue $latest.createdon } else { $null }
        trigger_flow = if ($latest) { [string]$latest.qfu_triggerflow } else { $null }
        seeded = if ($latest) {
          $text = ([string]$latest.qfu_triggerflow + " " + [string]$latest.qfu_notes + " " + [string]$latest.qfu_sourcefilename).ToLowerInvariant()
          $text.Contains("controlled workbook seed") -or $text.Contains("seeded from ")
        } else {
          $false
        }
      }
    }
  }

  return @($summary)
}

$outputJsonPath = Resolve-RepoPath -Path $OutputJson
$outputMarkdownPath = Resolve-RepoPath -Path $OutputMarkdown

$definitions = @(
  @{
    EntityLogicalName = "qfu_quote"
    IdField = "qfu_quoteid"
    CanonicalKey = "qfu_sourceid (branch|SP830CA|quotenumber)"
    TableRole = "current-state"
    Fields = @("qfu_quoteid", "qfu_branchcode", "qfu_sourceid", "qfu_quotenumber", "qfu_customername", "qfu_sourcedate", "qfu_sourceupdatedon", "qfu_active", "qfu_inactiveon", "qfu_lastseenon", "createdon", "modifiedon")
    DetailFields = @("qfu_quotenumber", "qfu_customername")
    ActiveField = "qfu_active"
    SnapshotField = "qfu_lastseenon"
    LifecycleFields = @("qfu_active", "qfu_inactiveon", "qfu_lastseenon")
  },
  @{
    EntityLogicalName = "qfu_backorder"
    IdField = "qfu_backorderid"
    CanonicalKey = "qfu_sourceid (branch|ZBO|salesdoc|line)"
    TableRole = "current-state"
    Fields = @("qfu_backorderid", "qfu_branchcode", "qfu_sourceid", "qfu_salesdocnumber", "qfu_customername", "qfu_daysoverdue", "qfu_active", "qfu_inactiveon", "qfu_lastseenon", "createdon", "modifiedon")
    DetailFields = @("qfu_salesdocnumber", "qfu_customername")
    ActiveField = "qfu_active"
    SnapshotField = "qfu_lastseenon"
    LifecycleFields = @("qfu_active", "qfu_inactiveon", "qfu_lastseenon")
  },
  @{
    EntityLogicalName = "qfu_marginexception"
    IdField = "qfu_marginexceptionid"
    CanonicalKey = "qfu_sourceid (branch|SA1300-MARGIN|snapshotdate|billingdoc|reviewtype)"
    TableRole = "snapshot"
    Fields = @("qfu_marginexceptionid", "qfu_branchcode", "qfu_sourceid", "qfu_billingdocumentnumber", "qfu_reviewtype", "qfu_snapshotdate", "createdon", "modifiedon")
    DetailFields = @("qfu_billingdocumentnumber", "qfu_reviewtype")
    ActiveField = $null
    SnapshotField = "qfu_snapshotdate"
  },
  @{
    EntityLogicalName = "qfu_deliverynotpgi"
    IdField = "qfu_deliverynotpgiid"
    CanonicalKey = "branch + delivery number + delivery line"
    TableRole = "snapshot with active/inactive lifecycle"
    Fields = @("qfu_deliverynotpgiid", "qfu_branchcode", "qfu_sourceid", "qfu_deliverynumber", "qfu_deliveryline", "qfu_active", "qfu_inactiveon", "qfu_snapshotcapturedon", "createdon", "modifiedon")
    DetailFields = @("qfu_deliverynumber", "qfu_deliveryline")
    ActiveField = "qfu_active"
    SnapshotField = "qfu_snapshotcapturedon"
    LifecycleFields = @("qfu_active", "qfu_inactiveon", "qfu_snapshotcapturedon")
  }
)

$connection = Connect-Target -Url $TargetEnvironmentUrl -User $Username

$entityAudits = foreach ($definition in $definitions) {
  Get-EntityAudit -Connection $connection -Definition $definition -BranchCodes $BranchCodes
}

$importSummary = Get-LatestImportSummary -Connection $connection -BranchCodes $BranchCodes

$report = [pscustomobject]@{
  generated_on = (Get-Date).ToUniversalTime().ToString("o")
  target_environment_url = $TargetEnvironmentUrl
  branch_codes = @($BranchCodes)
  operational_tables = @($entityAudits)
  latest_imports = @($importSummary)
}

Write-Utf8Json -Path $outputJsonPath -Object $report

$markdown = New-Object System.Collections.Generic.List[string]
$markdown.Add("# Operational Current-State Audit") | Out-Null
$markdown.Add("") | Out-Null
$markdown.Add("- Generated: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))") | Out-Null
$markdown.Add("- Environment: $TargetEnvironmentUrl") | Out-Null
$markdown.Add("- Branches: $([string]::Join(', ', $BranchCodes))") | Out-Null
$markdown.Add("") | Out-Null

foreach ($entity in $entityAudits) {
  $markdown.Add("## $($entity.entity)") | Out-Null
  $markdown.Add("") | Out-Null
  $markdown.Add("- Table role: $($entity.table_role)") | Out-Null
  $markdown.Add("- Canonical key: $($entity.canonical_key)") | Out-Null
  $markdown.Add("- Total rows: $($entity.total_rows)") | Out-Null
  $markdown.Add("- Unique source ids: $($entity.unique_source_ids)") | Out-Null
  $markdown.Add("- Duplicate groups: $($entity.duplicate_group_count)") | Out-Null
  $markdown.Add("- Duplicate rows: $($entity.duplicate_row_count)") | Out-Null
  if ($null -ne $entity.active_row_count) {
    $markdown.Add("- Active rows: $($entity.active_row_count)") | Out-Null
  }
  if ($null -ne $entity.inactive_row_count) {
    $markdown.Add("- Inactive rows: $($entity.inactive_row_count)") | Out-Null
  }
  if ($null -ne $entity.lifecycle_missing_count) {
    $markdown.Add("- Rows missing lifecycle fields: $($entity.lifecycle_missing_count)") | Out-Null
  }
  if ($entity.active_duplicate_group_count -gt 0) {
    $markdown.Add("- Groups with more than one active row: $($entity.active_duplicate_group_count)") | Out-Null
  }
  $markdown.Add("") | Out-Null

  if (@($entity.sample_groups).Count -gt 0) {
    $markdown.Add("| Duplicate key | Count | Winner | Sample rows |") | Out-Null
    $markdown.Add("| --- | ---: | --- | --- |") | Out-Null
    foreach ($group in @($entity.sample_groups)) {
      $sampleText = @($group.rows | Select-Object -First 3 | ForEach-Object {
        $parts = @(
          $_.record_id,
          $_.createdon,
          $_.modifiedon,
          $_.snapshot_on,
          $_.detail_1,
          $_.detail_2
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
        [string]::Join(" / ", $parts)
      }) -join " ; "
      $markdown.Add("| $($group.key.Replace('|', '\\|')) | $($group.count) | $($group.winner_id) | $($sampleText.Replace('|', '\\|')) |") | Out-Null
    }
    $markdown.Add("") | Out-Null
  }
}

$markdown.Add("## Latest Imports") | Out-Null
$markdown.Add("") | Out-Null
$markdown.Add("| Branch | Family | Status | Source started | Row created | Seeded | Trigger | File |") | Out-Null
$markdown.Add("| --- | --- | --- | --- | --- | --- | --- | --- |") | Out-Null
foreach ($row in $importSummary) {
  $markdown.Add("| $($row.branch_code) | $($row.source_family) | $($row.latest_status) | $($row.source_startedon) | $($row.row_createdon) | $($row.seeded) | $(([string]$row.trigger_flow).Replace('|', '\\|')) | $(([string]$row.source_filename).Replace('|', '\\|')) |") | Out-Null
}
$markdown.Add("") | Out-Null

Write-Utf8File -Path $outputMarkdownPath -Content ($markdown -join [Environment]::NewLine)

Write-Host "OUTPUT_JSON=$outputJsonPath"
Write-Host "OUTPUT_MARKDOWN=$outputMarkdownPath"
