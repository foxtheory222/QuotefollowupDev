param(
  [string]$RepoRoot = "C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion",
  [string]$TargetEnvironmentUrl = "https://regionaloperationshub.crm.dynamics.com",
  [string]$Username = "smcfarlane@applied.com",
  [string[]]$BranchCodes = @("4171", "4172", "4173"),
  [switch]$Apply,
  [string]$OutputPath = "results\live-freight-invoice-survivor-restore.json"
)

$ErrorActionPreference = "Stop"

Import-Module Microsoft.Xrm.Data.Powershell

function Resolve-RepoPath {
  param([string]$Path)

  if ([System.IO.Path]::IsPathRooted($Path)) {
    return $Path
  }

  return Join-Path $RepoRoot $Path
}

function Ensure-Directory {
  param([string]$Path)

  if (-not [string]::IsNullOrWhiteSpace($Path) -and -not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Write-Utf8Json {
  param(
    [string]$Path,
    [object]$Object
  )

  $resolvedPath = Resolve-RepoPath $Path
  $directory = Split-Path -Parent $resolvedPath
  if ($directory) {
    Ensure-Directory -Path $directory
  }

  [System.IO.File]::WriteAllText($resolvedPath, ($Object | ConvertTo-Json -Depth 40), [System.Text.UTF8Encoding]::new($false))
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

function Get-TextValue {
  param([AllowNull()][object]$Value)

  if ($null -eq $Value) {
    return ""
  }

  return ([string]$Value).Trim()
}

function Get-DateValue {
  param([AllowNull()][object]$Value)

  if ($null -eq $Value) {
    return $null
  }

  try {
    return [datetime]$Value
  } catch {
    return $null
  }
}

function Get-DecimalValue {
  param([AllowNull()][object]$Value)

  if ($null -eq $Value) {
    return $null
  }

  try {
    return [decimal]$Value
  } catch {
    $text = (Get-TextValue $Value) -replace ",", ""
    if ([string]::IsNullOrWhiteSpace($text)) {
      return $null
    }
    try {
      return [decimal]$text
    } catch {
      return $null
    }
  }
}

function Get-BoolValue {
  param([AllowNull()][object]$Value)

  if ($null -eq $Value) {
    return $false
  }
  if ($Value -is [bool]) {
    return [bool]$Value
  }

  $text = (Get-TextValue $Value).ToLowerInvariant()
  return $text -in @("true", "1", "yes")
}

function Convert-OptionalText {
  param([AllowNull()][object]$Value)

  $text = Get-TextValue $Value
  if ([string]::IsNullOrWhiteSpace($text)) {
    return $null
  }
  return $text
}

function Convert-OptionalDecimal {
  param([AllowNull()][object]$Value)
  return Get-DecimalValue $Value
}

function Convert-OptionalDate {
  param([AllowNull()][object]$Value)
  return Get-DateValue $Value
}

function Convert-OptionalBoolean {
  param([AllowNull()][object]$Value)

  if ($null -eq $Value) {
    return $null
  }
  return Get-BoolValue $Value
}

function Get-FreightFieldNames {
  return @(
    "qfu_freightworkitemid",
    "qfu_name",
    "qfu_sourceid",
    "qfu_branchcode",
    "qfu_branchslug",
    "qfu_regionslug",
    "qfu_sourcefamily",
    "qfu_sourcefilename",
    "qfu_sourcecarrier",
    "qfu_importbatchid",
    "qfu_rawrowjson",
    "qfu_trackingnumber",
    "qfu_pronumber",
    "qfu_invoicenumber",
    "qfu_controlnumber",
    "qfu_reference",
    "qfu_shipdate",
    "qfu_invoicedate",
    "qfu_closedate",
    "qfu_billtype",
    "qfu_service",
    "qfu_servicecode",
    "qfu_sender",
    "qfu_destination",
    "qfu_zone",
    "qfu_actualweight",
    "qfu_billedweight",
    "qfu_quantity",
    "qfu_totalamount",
    "qfu_freightamount",
    "qfu_fuelamount",
    "qfu_taxamount",
    "qfu_gstamount",
    "qfu_hstamount",
    "qfu_qstamount",
    "qfu_accessorialamount",
    "qfu_accessorialpresent",
    "qfu_unrealizedsavings",
    "qfu_chargebreakdowntext",
    "qfu_direction",
    "qfu_status",
    "qfu_priorityband",
    "qfu_ownername",
    "qfu_owneridentifier",
    "qfu_claimedon",
    "qfu_comment",
    "qfu_commentupdatedon",
    "qfu_commentupdatedbyname",
    "qfu_lastactivityon",
    "qfu_isarchived",
    "qfu_archivedon",
    "qfu_lastseenon",
    "createdon",
    "modifiedon"
  )
}

function Convert-FreightRecordToFields {
  param([object]$Record)

  $stringFields = @(
    "qfu_name",
    "qfu_sourceid",
    "qfu_branchcode",
    "qfu_branchslug",
    "qfu_regionslug",
    "qfu_sourcefamily",
    "qfu_sourcefilename",
    "qfu_sourcecarrier",
    "qfu_importbatchid",
    "qfu_trackingnumber",
    "qfu_pronumber",
    "qfu_invoicenumber",
    "qfu_controlnumber",
    "qfu_reference",
    "qfu_billtype",
    "qfu_service",
    "qfu_servicecode",
    "qfu_sender",
    "qfu_destination",
    "qfu_zone",
    "qfu_direction",
    "qfu_status",
    "qfu_priorityband",
    "qfu_ownername",
    "qfu_owneridentifier",
    "qfu_commentupdatedbyname",
    "qfu_chargebreakdowntext",
    "qfu_rawrowjson"
  )
  $memoFields = @("qfu_comment")
  $decimalFields = @(
    "qfu_actualweight",
    "qfu_billedweight",
    "qfu_quantity",
    "qfu_totalamount",
    "qfu_freightamount",
    "qfu_fuelamount",
    "qfu_taxamount",
    "qfu_gstamount",
    "qfu_hstamount",
    "qfu_qstamount",
    "qfu_accessorialamount",
    "qfu_unrealizedsavings"
  )
  $dateFields = @(
    "qfu_shipdate",
    "qfu_invoicedate",
    "qfu_closedate",
    "qfu_claimedon",
    "qfu_commentupdatedon",
    "qfu_lastactivityon",
    "qfu_archivedon",
    "qfu_lastseenon"
  )
  $booleanFields = @("qfu_accessorialpresent", "qfu_isarchived")

  $fields = @{}
  foreach ($fieldName in $stringFields) {
    $value = Convert-OptionalText $Record.$fieldName
    if ($null -ne $value) {
      $fields[$fieldName] = $value
    }
  }
  foreach ($fieldName in $memoFields) {
    if ($null -ne $Record.$fieldName) {
      $fields[$fieldName] = [string]$Record.$fieldName
    }
  }
  foreach ($fieldName in $decimalFields) {
    $value = Convert-OptionalDecimal $Record.$fieldName
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

  return $fields
}

function Get-LatestActivityValue {
  param(
    [object[]]$Rows,
    [datetime]$ObservedOn
  )

  $dates = @()
  foreach ($row in @($Rows)) {
    foreach ($candidate in @($row.qfu_lastactivityon, $row.qfu_commentupdatedon, $row.qfu_claimedon, $row.modifiedon, $ObservedOn)) {
      $dateValue = Get-DateValue $candidate
      if ($dateValue) {
        $dates += $dateValue
      }
    }
  }

  if (-not $dates.Count) {
    return $ObservedOn
  }
  return ($dates | Sort-Object | Select-Object -Last 1)
}

function Merge-PreservedWorkState {
  param(
    [hashtable]$Fields,
    [AllowNull()][object]$Existing,
    [AllowNull()][object]$Fallback,
    [datetime]$ObservedOn
  )

  foreach ($fieldName in @("qfu_status", "qfu_ownername", "qfu_owneridentifier", "qfu_commentupdatedbyname")) {
    $existingValue = if ($Existing) { Convert-OptionalText $Existing.$fieldName } else { $null }
    $fallbackValue = if ($Fallback) { Convert-OptionalText $Fallback.$fieldName } else { $null }
    if ($existingValue) {
      $Fields[$fieldName] = $existingValue
    } elseif ($fallbackValue) {
      $Fields[$fieldName] = $fallbackValue
    }
  }

  $existingComment = if ($Existing) { $Existing.qfu_comment } else { $null }
  $fallbackComment = if ($Fallback) { $Fallback.qfu_comment } else { $null }
  if ($null -ne $existingComment -and -not [string]::IsNullOrWhiteSpace([string]$existingComment)) {
    $Fields.qfu_comment = [string]$existingComment
  } elseif ($null -ne $fallbackComment -and -not [string]::IsNullOrWhiteSpace([string]$fallbackComment)) {
    $Fields.qfu_comment = [string]$fallbackComment
  }

  foreach ($fieldName in @("qfu_claimedon", "qfu_commentupdatedon")) {
    $existingValue = if ($Existing) { Get-DateValue $Existing.$fieldName } else { $null }
    $fallbackValue = if ($Fallback) { Get-DateValue $Fallback.$fieldName } else { $null }
    if ($existingValue) {
      $Fields[$fieldName] = $existingValue
    } elseif ($fallbackValue) {
      $Fields[$fieldName] = $fallbackValue
    }
  }

  $activityRows = @()
  if ($Existing) { $activityRows += $Existing }
  if ($Fallback) { $activityRows += $Fallback }
  $Fields.qfu_lastactivityon = Get-LatestActivityValue -Rows $activityRows -ObservedOn $ObservedOn
  $Fields.qfu_lastseenon = $ObservedOn
  $Fields.qfu_isarchived = $false
}

function Get-ActiveInvoiceSurvivors {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string[]]$Branches
  )

  $rows = New-Object System.Collections.Generic.List[object]
  foreach ($branchCode in $Branches) {
    $branchRows = @((Get-CrmRecords -conn $Connection -EntityLogicalName "qfu_freightworkitem" -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $branchCode -Fields (Get-FreightFieldNames) -TopCount 5000).CrmRecords)
    foreach ($row in $branchRows) {
      $sourceId = Get-TextValue $row.qfu_sourceid
      $sourceFamily = (Get-TextValue $row.qfu_sourcefamily).ToUpperInvariant()
      if ($sourceId -notmatch "\|invoice\|") {
        continue
      }
      if ($sourceFamily -eq "FREIGHT_REDWOOD") {
        continue
      }
      if (Get-BoolValue $row.qfu_isarchived) {
        continue
      }
      $rows.Add($row) | Out-Null
    }
  }

  return @($rows.ToArray())
}

function Get-AffectedKey {
  param([object]$Row)

  $branch = (Get-TextValue $Row.qfu_branchcode).ToUpperInvariant()
  $family = (Get-TextValue $Row.qfu_sourcefamily).ToUpperInvariant()
  $invoice = (Get-TextValue $Row.qfu_invoicenumber).ToUpperInvariant()
  if ([string]::IsNullOrWhiteSpace($branch) -or [string]::IsNullOrWhiteSpace($family) -or [string]::IsNullOrWhiteSpace($invoice)) {
    return ""
  }
  return "$branch|$family|$invoice"
}

function Get-RawFreightDocuments {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string[]]$Branches,
    [string[]]$SourceFamilies
  )

  $rows = New-Object System.Collections.Generic.List[object]
  foreach ($branchCode in $Branches) {
    $branchRows = @((Get-CrmRecords -conn $Connection -EntityLogicalName "qfu_rawdocument" -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $branchCode -Fields @(
          "qfu_rawdocumentid",
          "qfu_name",
          "qfu_sourceid",
          "qfu_branchcode",
          "qfu_branchslug",
          "qfu_regionslug",
          "qfu_sourcefamily",
          "qfu_sourcefile",
          "qfu_status",
          "qfu_receivedon",
          "qfu_processedon",
          "qfu_contenthash",
          "qfu_rawcontentbase64"
        ) -TopCount 5000).CrmRecords)
    foreach ($row in $branchRows) {
      if ([string]::IsNullOrWhiteSpace([string]$row.qfu_rawcontentbase64)) {
        continue
      }
      if (@($SourceFamilies) -notcontains (Get-TextValue $row.qfu_sourcefamily).ToUpperInvariant()) {
        continue
      }
      if ((Get-TextValue $row.qfu_status).ToLowerInvariant() -notin @("processed", "duplicate")) {
        continue
      }
      $rows.Add($row) | Out-Null
    }
  }

  return @($rows.ToArray())
}

function Invoke-FreightParserForDocument {
  param(
    [object]$Document,
    [string]$StagingRoot
  )

  $python = Get-Command python -ErrorAction SilentlyContinue
  if (-not $python) {
    throw "python is required to parse freight raw documents."
  }

  Ensure-Directory $StagingRoot
  $safeName = [IO.Path]::GetFileName((Get-TextValue $Document.qfu_sourcefile))
  if ([string]::IsNullOrWhiteSpace($safeName)) {
    $safeName = "freight-input.bin"
  }
  $inputPath = Join-Path $StagingRoot ("{0}-{1}-{2}" -f $Document.qfu_branchcode, ([guid]::NewGuid().Guid), $safeName)
  $outputPath = Join-Path $StagingRoot ("parsed-{0}.json" -f ([guid]::NewGuid().Guid))

  [IO.File]::WriteAllBytes($inputPath, [Convert]::FromBase64String([string]$Document.qfu_rawcontentbase64))
  try {
    & $python.Source (Join-Path $RepoRoot "scripts\parse-freight-report.py") `
      --input $inputPath `
      --branch-code ([string]$Document.qfu_branchcode) `
      --branch-slug ([string]$Document.qfu_branchslug) `
      --region-slug ([string]$Document.qfu_regionslug) `
      --source-family ([string]$Document.qfu_sourcefamily) `
      --source-filename ([string]$Document.qfu_sourcefile) `
      --import-batch-id ([string]$Document.qfu_sourceid) `
      --output $outputPath
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $outputPath)) {
      throw "Freight parser failed for raw document $($Document.qfu_rawdocumentid)"
    }

    return (Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json)
  } finally {
    if (Test-Path -LiteralPath $inputPath) {
      Remove-Item -LiteralPath $inputPath -Force
    }
    if (Test-Path -LiteralPath $outputPath) {
      Remove-Item -LiteralPath $outputPath -Force
    }
  }
}

function Get-ExistingFreightRowsBySourceId {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$SourceId
  )

  return @((Get-CrmRecords -conn $Connection -EntityLogicalName "qfu_freightworkitem" -FilterAttribute "qfu_sourceid" -FilterOperator eq -FilterValue $SourceId -Fields (Get-FreightFieldNames) -TopCount 10).CrmRecords)
}

function Upsert-RestoredFreightRecord {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [object]$Record,
    [object]$FallbackState,
    [datetime]$ObservedOn
  )

  $sourceId = Get-TextValue $Record.qfu_sourceid
  if ([string]::IsNullOrWhiteSpace($sourceId)) {
    throw "Parsed freight record is missing qfu_sourceid."
  }

  $existingRows = @(Get-ExistingFreightRowsBySourceId -Connection $Connection -SourceId $sourceId)
  $existing = $existingRows | Sort-Object { Get-DateValue $_.modifiedon } -Descending | Select-Object -First 1
  $fields = Convert-FreightRecordToFields -Record $Record
  Merge-PreservedWorkState -Fields $fields -Existing $existing -Fallback $FallbackState -ObservedOn $ObservedOn

  if ($existing) {
    Set-CrmRecord -conn $Connection -EntityLogicalName "qfu_freightworkitem" -Id $existing.qfu_freightworkitemid -Fields $fields | Out-Null
    return [pscustomobject]@{
      action = "updated"
      id = [string]$existing.qfu_freightworkitemid
      source_id = $sourceId
      duplicate_exact_rows = [Math]::Max(0, @($existingRows).Count - 1)
      carried_state_from_invoice = [bool]((Convert-OptionalText $FallbackState.qfu_ownername) -or (Convert-OptionalText $FallbackState.qfu_comment) -or (Get-DateValue $FallbackState.qfu_claimedon))
    }
  }

  $newId = New-CrmRecord -conn $Connection -EntityLogicalName "qfu_freightworkitem" -Fields $fields
  return [pscustomobject]@{
    action = "created"
    id = [string]$newId
    source_id = $sourceId
    duplicate_exact_rows = 0
    carried_state_from_invoice = [bool]((Convert-OptionalText $FallbackState.qfu_ownername) -or (Convert-OptionalText $FallbackState.qfu_comment) -or (Get-DateValue $FallbackState.qfu_claimedon))
  }
}

$target = Connect-Target -Url $TargetEnvironmentUrl -User $Username
Write-Host "Connected target: $($target.ConnectedOrgFriendlyName)"

$survivors = @(Get-ActiveInvoiceSurvivors -Connection $target -Branches $BranchCodes)
$affected = @{}
foreach ($survivor in $survivors) {
  $key = Get-AffectedKey $survivor
  if ([string]::IsNullOrWhiteSpace($key)) {
    continue
  }
  if (-not $affected.ContainsKey($key)) {
    $affected[$key] = New-Object System.Collections.Generic.List[object]
  }
  $affected[$key].Add($survivor) | Out-Null
}

$sourceFamilies = @($survivors | ForEach-Object { (Get-TextValue $_.qfu_sourcefamily).ToUpperInvariant() } | Sort-Object -Unique)
$rawDocuments = if ($sourceFamilies.Count) { @(Get-RawFreightDocuments -Connection $target -Branches $BranchCodes -SourceFamilies $sourceFamilies) } else { @() }
$stagingRoot = Resolve-RepoPath "results\freight-invoice-survivor-restore-staging"
$matchedRecordsByKey = @{}
$parsedDocuments = New-Object System.Collections.Generic.List[object]
$parseErrors = New-Object System.Collections.Generic.List[object]

foreach ($document in @($rawDocuments | Sort-Object { Get-DateValue $_.qfu_receivedon })) {
  try {
    $parsed = Invoke-FreightParserForDocument -Document $document -StagingRoot $stagingRoot
    $matchedCount = 0
    foreach ($record in @($parsed.records)) {
      $key = Get-AffectedKey $record
      if (-not $affected.ContainsKey($key)) {
        continue
      }
      $sourceId = Get-TextValue $record.qfu_sourceid
      if ([string]::IsNullOrWhiteSpace($sourceId) -or $sourceId -match "\|invoice\|") {
        continue
      }
      if (-not $matchedRecordsByKey.ContainsKey($key)) {
        $matchedRecordsByKey[$key] = @{}
      }
      $matchedRecordsByKey[$key][$sourceId] = [pscustomobject]@{
        record = $record
        raw_document_id = [string]$document.qfu_rawdocumentid
        raw_source_id = [string]$document.qfu_sourceid
        source_file = [string]$document.qfu_sourcefile
        received_on = $document.qfu_receivedon
      }
      $matchedCount += 1
    }
    $parsedDocuments.Add([pscustomobject]@{
        raw_document_id = [string]$document.qfu_rawdocumentid
        raw_source_id = [string]$document.qfu_sourceid
        branch_code = [string]$document.qfu_branchcode
        source_family = [string]$document.qfu_sourcefamily
        source_file = [string]$document.qfu_sourcefile
        status = [string]$document.qfu_status
        received_on = $document.qfu_receivedon
        parsed_records = [int]$parsed.normalized_record_count
        matched_records = [int]$matchedCount
      }) | Out-Null
  } catch {
    $parseErrors.Add([pscustomobject]@{
        raw_document_id = [string]$document.qfu_rawdocumentid
        raw_source_id = [string]$document.qfu_sourceid
        source_file = [string]$document.qfu_sourcefile
        error = $_.Exception.Message
      }) | Out-Null
  }
}

$plans = New-Object System.Collections.Generic.List[object]
foreach ($key in @($affected.Keys | Sort-Object)) {
  $keySurvivors = @($affected[$key].ToArray())
  $primarySurvivor = $keySurvivors | Sort-Object { Get-DateValue $_.modifiedon } -Descending | Select-Object -First 1
  $recordItems = @()
  if ($matchedRecordsByKey.ContainsKey($key)) {
    $recordItems = @($matchedRecordsByKey[$key].Values | Sort-Object { Get-TextValue $_.record.qfu_sourceid })
  }

  $totalAmount = [decimal]0
  foreach ($item in $recordItems) {
    $amount = Get-DecimalValue $item.record.qfu_totalamount
    if ($null -ne $amount) {
      $totalAmount += $amount
    }
  }

  $plans.Add([pscustomobject]@{
      key = $key
      invoice_survivor_ids = @($keySurvivors | ForEach-Object { [string]$_.qfu_freightworkitemid })
      invoice_survivor_sourceids = @($keySurvivors | ForEach-Object { Get-TextValue $_.qfu_sourceid })
      branch_code = Get-TextValue $primarySurvivor.qfu_branchcode
      source_family = Get-TextValue $primarySurvivor.qfu_sourcefamily
      invoice_number = Get-TextValue $primarySurvivor.qfu_invoicenumber
      invoice_survivor_total = Get-DecimalValue $primarySurvivor.qfu_totalamount
      restored_record_count = @($recordItems).Count
      restored_total_amount = [decimal]::Round($totalAmount, 2)
      restored_sourceids = @($recordItems | ForEach-Object { Get-TextValue $_.record.qfu_sourceid })
      raw_document_ids = @($recordItems | ForEach-Object { $_.raw_document_id } | Sort-Object -Unique)
      source_files = @($recordItems | ForEach-Object { $_.source_file } | Sort-Object -Unique)
      state_source_id = [string]$primarySurvivor.qfu_freightworkitemid
      state_ownername = Get-TextValue $primarySurvivor.qfu_ownername
      state_comment_present = -not [string]::IsNullOrWhiteSpace((Get-TextValue $primarySurvivor.qfu_comment))
      can_apply = (@($recordItems).Count -gt 0)
    }) | Out-Null
}

$applyResults = New-Object System.Collections.Generic.List[object]
if ($Apply) {
  $observedOn = [datetime]::UtcNow
  foreach ($plan in @($plans.ToArray())) {
    if (-not $plan.can_apply) {
      $applyResults.Add([pscustomobject]@{
          key = $plan.key
          skipped = $true
          reason = "No matching parsed shipment-level records found; invoice survivor left active."
        }) | Out-Null
      continue
    }

    $fallbackState = @($survivors | Where-Object { [string]$_.qfu_freightworkitemid -eq [string]$plan.state_source_id }) | Select-Object -First 1
    $upserts = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($matchedRecordsByKey[$plan.key].Values)) {
      $upserts.Add((Upsert-RestoredFreightRecord -Connection $target -Record $item.record -FallbackState $fallbackState -ObservedOn $observedOn)) | Out-Null
    }

    foreach ($survivorId in @($plan.invoice_survivor_ids)) {
      Set-CrmRecord -conn $target -EntityLogicalName "qfu_freightworkitem" -Id $survivorId -Fields @{
        qfu_isarchived = $true
        qfu_archivedon = $observedOn
        qfu_lastactivityon = $observedOn
      } | Out-Null
    }

    $applyResults.Add([pscustomobject]@{
        key = $plan.key
        skipped = $false
        invoice_survivor_ids_archived = @($plan.invoice_survivor_ids)
        upserted_records = @($upserts.ToArray())
      }) | Out-Null
  }
}

$warnings = New-Object System.Collections.Generic.List[string]
foreach ($plan in @($plans.ToArray())) {
  if (-not $plan.can_apply) {
    $warnings.Add("No matching shipment-level parsed rows found for $($plan.key); left invoice survivor active.") | Out-Null
  }
}
if ($parseErrors.Count -gt 0) {
  $warnings.Add("One or more raw freight documents failed to parse; see parse_errors.") | Out-Null
}

$result = [ordered]@{
  target_environment = $TargetEnvironmentUrl
  captured_at = ([datetime]::UtcNow.ToString("o"))
  applied = [bool]$Apply
  branch_codes = @($BranchCodes)
  active_invoice_survivors_scanned = @($survivors).Count
  affected_keys = @($affected.Keys).Count
  raw_documents_scanned = @($rawDocuments).Count
  parsed_documents = @($parsedDocuments.ToArray())
  parse_errors = @($parseErrors.ToArray())
  plan_count = $plans.Count
  plans = @($plans.ToArray())
  apply_results = @($applyResults.ToArray())
  warnings = @($warnings.ToArray())
  assumption = "For non-Redwood carrier rows, invoice number is metadata. This repair restores shipment-level source IDs from raw Dataverse attachments and carries invoice-survivor owner/comment state onto restored detail rows only when the detail row lacks its own preserved work state."
}

Write-Utf8Json -Path $OutputPath -Object $result
Write-Output ($result | ConvertTo-Json -Depth 40)
