param(
  [string]$RepoRoot = "C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion",
  [string]$TargetEnvironmentUrl = "https://regionaloperationshub.crm.dynamics.com",
  [string]$Username = "smcfarlane@applied.com",
  [string]$OutputJson = "results\freight-inbox-queue-summary.json",
  [int]$TopCount = 50
)

$ErrorActionPreference = "Stop"

. (Join-Path $RepoRoot "scripts\deploy-southern-alberta-pilot.ps1")
. (Join-Path $RepoRoot "scripts\deploy-freight-worklist.ps1")

function Ensure-FreightProcessorSchema {
  param([Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection)
  Ensure-FreightSchema -Connection $Connection
}

function Get-QueuedFreightDocuments {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [int]$MaxRows
  )

  $scanCount = [Math]::Max(($MaxRows * 10), 500)
  $rows = @((Get-CrmRecords -conn $Connection -EntityLogicalName "qfu_rawdocument" -FilterAttribute "qfu_status" -FilterOperator eq -FilterValue "queued" -Fields @(
        "qfu_rawdocumentid",
        "qfu_name",
        "qfu_sourceid",
        "qfu_branchcode",
        "qfu_branchslug",
        "qfu_regionslug",
        "qfu_sourcefamily",
        "qfu_sourcefile",
        "qfu_contenthash",
        "qfu_receivedon",
        "qfu_rawcontentbase64",
        "qfu_status"
      ) -TopCount $scanCount).CrmRecords)

  return @($rows |
      Where-Object { [string]$_.qfu_sourcefamily -like "FREIGHT_*" } |
      Sort-Object { [datetime]($_.qfu_receivedon | ForEach-Object { if ($_){ $_ } else { [datetime]::MinValue } }) } -Descending |
      Select-Object -First $MaxRows)
}

function Set-RawDocumentState {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [object]$Document,
    [string]$Status,
    [string]$Notes = $null,
    [string]$ContentHash = $null,
    [Nullable[datetime]]$ProcessedOn = $null
  )

  $fields = @{
    qfu_status = $Status
    qfu_processingnotes = $Notes
  }
  if ($ContentHash) { $fields.qfu_contenthash = $ContentHash }
  if ($ProcessedOn) { $fields.qfu_processedon = $ProcessedOn }

  Set-CrmRecord -conn $Connection -EntityLogicalName "qfu_rawdocument" -Id $Document.qfu_rawdocumentid -Fields $fields | Out-Null
}

function Get-ContentHash {
  param([object]$Document)

  if ($Document.qfu_contenthash) {
    return [string]$Document.qfu_contenthash
  }

  $bytes = [Convert]::FromBase64String([string]$Document.qfu_rawcontentbase64)
  $hashBytes = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
  return ([System.BitConverter]::ToString($hashBytes) -replace "-", "").ToLowerInvariant()
}

function Get-ExistingDuplicateDocument {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [object]$Document,
    [string]$ContentHash
  )

  $existingRows = @((Get-CrmRecords -conn $Connection -EntityLogicalName "qfu_rawdocument" -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $Document.qfu_branchcode -Fields @(
        "qfu_rawdocumentid",
        "qfu_sourceid",
        "qfu_sourcefamily",
        "qfu_status",
        "qfu_sourcefile",
        "qfu_contenthash",
        "qfu_processedon",
        "qfu_rawcontentbase64"
      ) -TopCount 500).CrmRecords)

  foreach ($row in $existingRows) {
    if ([string]$row.qfu_rawdocumentid -eq [string]$Document.qfu_rawdocumentid) {
      continue
    }
    if ([string]$row.qfu_sourcefamily -ne [string]$Document.qfu_sourcefamily) {
      continue
    }
    if (@("processed", "duplicate") -notcontains [string]$row.qfu_status) {
      continue
    }

    $rowHash = [string]$row.qfu_contenthash
    if (-not $rowHash -and $row.qfu_rawcontentbase64) {
      $rowHash = Get-ContentHash -Document $row
      Set-CrmRecord -conn $Connection -EntityLogicalName "qfu_rawdocument" -Id $row.qfu_rawdocumentid -Fields @{ qfu_contenthash = $rowHash } | Out-Null
    }

    if ($rowHash -and $rowHash -eq $ContentHash) {
      return $row
    }
  }

  return $null
}

function Upsert-IngestionBatch {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [object]$Document,
    [string]$Status,
    [int]$InsertedCount = 0,
    [int]$UpdatedCount = 0,
    [string]$Notes = $null,
    [Nullable[datetime]]$CompletedOn = $null
  )

  $existing = @(Get-CrmRecords -conn $Connection -EntityLogicalName "qfu_ingestionbatch" -FilterAttribute "qfu_sourceid" -FilterOperator eq -FilterValue $Document.qfu_sourceid -Fields @("qfu_ingestionbatchid") -TopCount 1).CrmRecords | Select-Object -First 1
  $fields = @{
    qfu_name = "$($Document.qfu_branchcode) Freight Import"
    qfu_sourceid = [string]$Document.qfu_sourceid
    qfu_branchcode = [string]$Document.qfu_branchcode
    qfu_branchslug = [string]$Document.qfu_branchslug
    qfu_regionslug = [string]$Document.qfu_regionslug
    qfu_sourcefamily = [string]$Document.qfu_sourcefamily
    qfu_sourcefilename = [string]$Document.qfu_sourcefile
    qfu_status = $Status
    qfu_insertedcount = $InsertedCount
    qfu_updatedcount = $UpdatedCount
    qfu_triggerflow = "Freight Inbox Import"
    qfu_notes = $Notes
  }
  if (-not $existing) {
    $fields.qfu_startedon = [datetime]::UtcNow
  }
  if ($CompletedOn) {
    $fields.qfu_completedon = $CompletedOn
  }

  if ($existing) {
    Set-CrmRecord -conn $Connection -EntityLogicalName "qfu_ingestionbatch" -Id $existing.qfu_ingestionbatchid -Fields $fields | Out-Null
    return "updated"
  }

  New-CrmRecord -conn $Connection -EntityLogicalName "qfu_ingestionbatch" -Fields $fields | Out-Null
  return "created"
}

function New-TempFreightFileFromRawDocument {
  param(
    [object]$Document,
    [string]$RepoRootPath
  )

  $stagingRoot = Join-Path $RepoRootPath "results\freight-queue-staging"
  Ensure-Directory $stagingRoot
  $safeName = [IO.Path]::GetFileName(($Document.qfu_sourcefile | ForEach-Object { if ($_){$_} else {"freight-input.bin"} }))
  $fileName = "{0}-{1}-{2}" -f $Document.qfu_branchcode, ([guid]::NewGuid().Guid), $safeName
  $path = Join-Path $stagingRoot $fileName
  [IO.File]::WriteAllBytes($path, [Convert]::FromBase64String([string]$Document.qfu_rawcontentbase64))
  return $path
}

function Invoke-FreightParser {
  param(
    [string]$RepoRootPath,
    [object]$Document,
    [string]$InputFilePath
  )

  $python = Get-Command python -ErrorAction SilentlyContinue
  if (-not $python) {
    throw "python is required to process queued freight reports."
  }

  $outputPath = Join-Path $RepoRootPath ("results\freight-queue-staging\parsed-{0}.json" -f ([guid]::NewGuid().Guid))
  $scriptPath = Join-Path $RepoRootPath "scripts\parse-freight-report.py"
  & $python.Source $scriptPath `
    --input $InputFilePath `
    --branch-code ([string]$Document.qfu_branchcode) `
    --branch-slug ([string]$Document.qfu_branchslug) `
    --region-slug ([string]$Document.qfu_regionslug) `
    --source-family ([string]$Document.qfu_sourcefamily) `
    --source-filename ([string]$Document.qfu_sourcefile) `
    --import-batch-id ([string]$Document.qfu_sourceid) `
    --output $outputPath
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $outputPath)) {
    throw "Freight parser failed for $InputFilePath"
  }

  return (Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json)
}

function Get-LatestActivityValue {
  param(
    [object]$Existing,
    [datetime]$ObservedOn
  )

  $dates = @()
  foreach ($candidate in @($Existing.qfu_lastactivityon, $Existing.qfu_commentupdatedon, $Existing.qfu_claimedon, $ObservedOn)) {
    if ($candidate) {
      try {
        $dates += [datetime]$candidate
      } catch {
      }
    }
  }
  if (-not $dates.Count) {
    return $ObservedOn
  }
  return ($dates | Sort-Object | Select-Object -Last 1)
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

function Upsert-FreightWorkItems {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [object[]]$Records
  )

  $inserted = 0
  $updated = 0
  $warnings = New-Object System.Collections.Generic.List[string]
  $observedOn = [datetime]::UtcNow

  foreach ($record in @($Records)) {
    $existingRows = @((Get-CrmRecords -conn $Connection -EntityLogicalName "qfu_freightworkitem" -FilterAttribute "qfu_sourceid" -FilterOperator eq -FilterValue $record.qfu_sourceid -Fields @(
          "qfu_freightworkitemid",
          "qfu_sourceid",
          "qfu_status",
          "qfu_ownername",
          "qfu_owneridentifier",
          "qfu_claimedon",
          "qfu_comment",
          "qfu_commentupdatedon",
          "qfu_commentupdatedbyname",
          "qfu_lastactivityon",
          "qfu_isarchived",
          "qfu_archivedon",
          "modifiedon"
        ) -TopCount 5).CrmRecords)
    $existing = $existingRows | Sort-Object modifiedon -Descending | Select-Object -First 1
    if ($existingRows.Count -gt 1) {
      $warnings.Add("Duplicate freight rows already existed for source id $($record.qfu_sourceid); updated latest row only.") | Out-Null
    }

    $fields = Convert-FreightRecordToFields -Record $record
    $fields.qfu_lastseenon = $observedOn
    $fields.qfu_lastactivityon = $observedOn
    $fields.qfu_isarchived = $false

    if ($existing) {
      if ([string]$existing.qfu_status) { $fields.qfu_status = [string]$existing.qfu_status }
      if ([string]$existing.qfu_ownername) { $fields.qfu_ownername = [string]$existing.qfu_ownername }
      if ([string]$existing.qfu_owneridentifier) { $fields.qfu_owneridentifier = [string]$existing.qfu_owneridentifier }
      if ($existing.qfu_claimedon) { $fields.qfu_claimedon = [datetime]$existing.qfu_claimedon }
      if ($null -ne $existing.qfu_comment) { $fields.qfu_comment = [string]$existing.qfu_comment }
      if ($existing.qfu_commentupdatedon) { $fields.qfu_commentupdatedon = [datetime]$existing.qfu_commentupdatedon }
      if ([string]$existing.qfu_commentupdatedbyname) { $fields.qfu_commentupdatedbyname = [string]$existing.qfu_commentupdatedbyname }
      if ($existing.qfu_archivedon) { $fields.qfu_archivedon = [datetime]$existing.qfu_archivedon }
      $fields.qfu_lastactivityon = Get-LatestActivityValue -Existing $existing -ObservedOn $observedOn

      Set-CrmRecord -conn $Connection -EntityLogicalName "qfu_freightworkitem" -Id $existing.qfu_freightworkitemid -Fields $fields | Out-Null
      $updated += 1
      continue
    }

    New-CrmRecord -conn $Connection -EntityLogicalName "qfu_freightworkitem" -Fields $fields | Out-Null
    $inserted += 1
  }

  return [pscustomobject]@{
    inserted = $inserted
    updated = $updated
    warnings = @($warnings.ToArray())
  }
}

$target = Connect-Org -Url $TargetEnvironmentUrl
Write-Host "Connected target: $($target.ConnectedOrgFriendlyName)"

Ensure-FreightProcessorSchema -Connection $target

$documents = Get-QueuedFreightDocuments -Connection $target -MaxRows $TopCount
$results = New-Object System.Collections.Generic.List[object]

foreach ($document in $documents) {
  $contentHash = $null
  $stagedPath = $null
  try {
    $contentHash = Get-ContentHash -Document $document
    $duplicate = Get-ExistingDuplicateDocument -Connection $target -Document $document -ContentHash $contentHash
    if ($duplicate) {
      $duplicateNote = "Duplicate freight attachment matched existing source $($duplicate.qfu_sourceid). No reprocess required."
      Set-RawDocumentState -Connection $target -Document $document -Status "duplicate" -Notes $duplicateNote -ContentHash $contentHash -ProcessedOn ([datetime]::UtcNow)
      Upsert-IngestionBatch -Connection $target -Document $document -Status "duplicate" -InsertedCount 0 -UpdatedCount 0 -Notes $duplicateNote -CompletedOn ([datetime]::UtcNow) | Out-Null
      $results.Add([pscustomobject]@{
          source_id = [string]$document.qfu_sourceid
          branch_code = [string]$document.qfu_branchcode
          source_family = [string]$document.qfu_sourcefamily
          file_name = [string]$document.qfu_sourcefile
          status = "duplicate"
          duplicate_of = [string]$duplicate.qfu_sourceid
        }) | Out-Null
      continue
    }

    $stagedPath = New-TempFreightFileFromRawDocument -Document $document -RepoRootPath $RepoRoot
    $parsed = Invoke-FreightParser -RepoRootPath $RepoRoot -Document $document -InputFilePath $stagedPath
    $upsertResult = Upsert-FreightWorkItems -Connection $target -Records @($parsed.records)
    $completedOn = [datetime]::UtcNow
    $warningSummary = if (@($upsertResult.warnings).Count) { " Warnings: " + (@($upsertResult.warnings) -join " | ") } else { "" }
    $batchNote = "Normalized $($parsed.input_row_count) source row(s) into $($parsed.normalized_record_count) freight work item(s)." + $warningSummary
    Set-RawDocumentState -Connection $target -Document $document -Status "processed" -Notes $batchNote -ContentHash $contentHash -ProcessedOn $completedOn
    Upsert-IngestionBatch -Connection $target -Document $document -Status "processed" -InsertedCount $upsertResult.inserted -UpdatedCount $upsertResult.updated -Notes $batchNote -CompletedOn $completedOn | Out-Null
    $results.Add([pscustomobject]@{
        source_id = [string]$document.qfu_sourceid
        branch_code = [string]$document.qfu_branchcode
        source_family = [string]$document.qfu_sourcefamily
        file_name = [string]$document.qfu_sourcefile
        status = "processed"
        input_rows = [int]$parsed.input_row_count
        normalized_records = [int]$parsed.normalized_record_count
        collapsed_group_rows = [int]$parsed.collapsed_group_rows
        inserted = [int]$upsertResult.inserted
        updated = [int]$upsertResult.updated
        warnings = @($upsertResult.warnings)
      }) | Out-Null
  } catch {
    $message = $_.Exception.Message
    try {
      Set-RawDocumentState -Connection $target -Document $document -Status "error" -Notes $message -ContentHash $contentHash -ProcessedOn ([datetime]::UtcNow)
      Upsert-IngestionBatch -Connection $target -Document $document -Status "error" -InsertedCount 0 -UpdatedCount 0 -Notes $message -CompletedOn ([datetime]::UtcNow) | Out-Null
    } catch {
    }
    $results.Add([pscustomobject]@{
        source_id = [string]$document.qfu_sourceid
        branch_code = [string]$document.qfu_branchcode
        source_family = [string]$document.qfu_sourcefamily
        file_name = [string]$document.qfu_sourcefile
        status = "error"
        error = $message
      }) | Out-Null
  } finally {
    if ($stagedPath -and (Test-Path -LiteralPath $stagedPath)) {
      Remove-Item -LiteralPath $stagedPath -Force
    }
  }
}

$result = [ordered]@{
  target_environment = $TargetEnvironmentUrl
  processed = @($results.ToArray())
}

Write-Utf8Json -Path (Join-Path $RepoRoot $OutputJson) -Object $result
Write-Output ($result | ConvertTo-Json -Depth 8)
