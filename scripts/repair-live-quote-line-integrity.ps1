param(
  [string]$TargetEnvironmentUrl = "https://regionaloperationshub.crm.dynamics.com",
  [string]$Username = "smcfarlane@applied.com",
  [string]$ExampleRoot = "example",
  [string]$ParserScript = "scripts\parse-southern-alberta-workbooks.py",
  [string]$ParsedWorkbookJson = "results\live-quote-line-integrity\parsed-workbooks.json",
  [string]$OutputJson = "results\live-quote-line-integrity\repair-summary.json",
  [switch]$Apply,
  [bool]$ReactivateQuotesWithRecoveredLines = $true,
  [switch]$AllowQuoteCleanup
)

$ErrorActionPreference = "Stop"

Import-Module Microsoft.Xrm.Data.Powershell

function Ensure-Directory {
  param([string]$Path)

  if ($Path -and -not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Write-Utf8Json {
  param(
    [string]$Path,
    [object]$Object
  )

  $directory = Split-Path -Parent $Path
  if ($directory) {
    Ensure-Directory -Path $directory
  }

  $json = $Object | ConvertTo-Json -Depth 20
  [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Resolve-LocalPath {
  param([string]$Path)

  if ([System.IO.Path]::IsPathRooted($Path)) {
    return $Path
  }

  return Join-Path (Get-Location).Path $Path
}

function ConvertTo-PlainHashtable {
  param([object]$Value)

  if ($null -eq $Value) {
    return $null
  }

  if ($Value -is [System.Collections.IDictionary]) {
    $result = @{}
    foreach ($key in $Value.Keys) {
      $result[[string]$key] = ConvertTo-PlainHashtable -Value $Value[$key]
    }
    return $result
  }

  if ($Value -is [System.Management.Automation.PSCustomObject]) {
    $result = @{}
    foreach ($property in $Value.PSObject.Properties) {
      $result[$property.Name] = ConvertTo-PlainHashtable -Value $property.Value
    }
    return $result
  }

  if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($item in $Value) {
      $items.Add((ConvertTo-PlainHashtable -Value $item)) | Out-Null
    }
    return @($items)
  }

  return $Value
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

function Ensure-ParsedWorkbookData {
  param(
    [string]$ParserPath,
    [string]$ExampleRootPath,
    [string]$OutputPath
  )

  $python = Get-Command python -ErrorAction SilentlyContinue
  if (-not $python) {
    throw "python is required to generate parsed workbook data."
  }

  Ensure-Directory -Path (Split-Path -Parent $OutputPath)
  & $python.Source $ParserPath --example-root $ExampleRootPath --output $OutputPath
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $OutputPath)) {
    throw "Failed to generate parsed workbook JSON: $OutputPath"
  }
}

function Parse-DateValue {
  param($Value)

  if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
    return $null
  }

  return [datetime]$Value
}

function Normalize-QuoteLineCreateFields {
  param([hashtable]$Fields)

  if ($Fields.ContainsKey("qfu_sourcedate") -and -not [string]::IsNullOrWhiteSpace([string]$Fields["qfu_sourcedate"])) {
    $Fields["qfu_sourcedate"] = [datetime]$Fields["qfu_sourcedate"]
  }

  if ($Fields.ContainsKey("qfu_lastimportdate") -and -not [string]::IsNullOrWhiteSpace([string]$Fields["qfu_lastimportdate"])) {
    $Fields["qfu_lastimportdate"] = [datetime]$Fields["qfu_lastimportdate"]
  }

  if ($Fields.ContainsKey("qfu_status") -and -not [string]::IsNullOrWhiteSpace([string]$Fields["qfu_status"])) {
    $Fields["qfu_status"] = [int]$Fields["qfu_status"]
  }

  return $Fields
}

function Test-QuoteActive {
  param([object]$Record)

  $inactiveOn = Parse-DateValue $Record.qfu_inactiveon
  if ($inactiveOn) {
    return $false
  }

  if ($null -eq $Record.qfu_active -or [string]::IsNullOrWhiteSpace([string]$Record.qfu_active)) {
    return $true
  }

  if ($Record.qfu_active -is [bool]) {
    return [bool]$Record.qfu_active
  }

  $label = ([string]$Record.qfu_active).Trim().ToLowerInvariant()
  switch ($label) {
    "true" { return $true }
    "false" { return $false }
    "yes" { return $true }
    "no" { return $false }
    "1" { return $true }
    "0" { return $false }
    default { return $true }
  }
}

function Get-CanonicalQuoteLineSourceId {
  param(
    [string]$BranchCode,
    [string]$QuoteNumber,
    [string]$LineNumber
  )

  if ([string]::IsNullOrWhiteSpace($BranchCode) -or [string]::IsNullOrWhiteSpace($QuoteNumber) -or [string]::IsNullOrWhiteSpace($LineNumber)) {
    return $null
  }

  return "{0}|SP830CA|{1}|{2}" -f $BranchCode.Trim(), $QuoteNumber.Trim(), $LineNumber.Trim()
}

function Get-CanonicalQuoteLineUniqueKey {
  param(
    [string]$QuoteNumber,
    [string]$LineNumber
  )

  if ([string]::IsNullOrWhiteSpace($QuoteNumber) -or [string]::IsNullOrWhiteSpace($LineNumber)) {
    return $null
  }

  return "{0}_{1}" -f $QuoteNumber.Trim(), $LineNumber.Trim()
}

function Get-LatestRecord {
  param([object[]]$Records)

  return @(
    $Records |
      Sort-Object `
        @{ Expression = { if ($_.modifiedon) { [datetime]$_.modifiedon } else { [datetime]::MinValue } }; Descending = $true }, `
        @{ Expression = { if ($_.createdon) { [datetime]$_.createdon } else { [datetime]::MinValue } }; Descending = $true }, `
        @{ Expression = { [string]$_.qfu_quotelineid } }
  ) | Select-Object -First 1
}

function Get-QuoteWorkingSet {
  param([object[]]$LiveQuotes)

  $groups = @{}
  $workingSet = New-Object System.Collections.Generic.List[object]
  $deletedDuplicateIds = New-Object System.Collections.Generic.List[string]
  $normalizedGroups = New-Object System.Collections.Generic.List[object]

  foreach ($quote in @($LiveQuotes)) {
    $sourceId = [string]$quote.qfu_sourceid
    if ([string]::IsNullOrWhiteSpace($sourceId)) {
      $workingSet.Add($quote) | Out-Null
      continue
    }

    if (-not $groups.ContainsKey($sourceId)) {
      $groups[$sourceId] = New-Object System.Collections.Generic.List[object]
    }

    $groups[$sourceId].Add($quote) | Out-Null
  }

  foreach ($canonicalSourceId in ($groups.Keys | Sort-Object)) {
    $winner = Get-LatestRecord -Records @($groups[$canonicalSourceId].ToArray())
    $duplicates = @($groups[$canonicalSourceId].ToArray() | Where-Object { [string]$_.qfu_quoteid -ne [string]$winner.qfu_quoteid })

    foreach ($duplicate in $duplicates) {
      $duplicateId = [string]$duplicate.qfu_quoteid
      if ([string]::IsNullOrWhiteSpace($duplicateId)) {
        continue
      }

      $deletedDuplicateIds.Add($duplicateId) | Out-Null
    }

    $workingSet.Add($winner) | Out-Null
    $normalizedGroups.Add([pscustomobject]@{
      canonical_source_id = $canonicalSourceId
      winner_id = [string]$winner.qfu_quoteid
      removed_duplicate_ids = @($duplicates | ForEach-Object { [string]$_.qfu_quoteid })
    }) | Out-Null
  }

  $workingSetValues = foreach ($item in $workingSet) { $item }
  $removedDuplicateIds = foreach ($item in $deletedDuplicateIds) { [string]$item }
  $normalizedGroupValues = foreach ($item in $normalizedGroups) { $item }

  return [pscustomobject]@{
    working_set = @($workingSetValues)
    removed_duplicate_ids = @($removedDuplicateIds)
    normalized_groups = @($normalizedGroupValues)
  }
}

$parserPath = Resolve-LocalPath -Path $ParserScript
$exampleRootPath = Resolve-LocalPath -Path $ExampleRoot
$parsedWorkbookJsonPath = Resolve-LocalPath -Path $ParsedWorkbookJson
$outputJsonPath = Resolve-LocalPath -Path $OutputJson

Ensure-ParsedWorkbookData -ParserPath $parserPath -ExampleRootPath $exampleRootPath -OutputPath $parsedWorkbookJsonPath
$parsedPayload = Get-Content -LiteralPath $parsedWorkbookJsonPath -Raw | ConvertFrom-Json
$connection = Connect-Org -Url $TargetEnvironmentUrl -User $Username
$repairTimestamp = Get-Date

$branchResults = @{}

foreach ($branchPayload in @($parsedPayload.branches)) {
  $branchCode = [string]$branchPayload.branch.branch_code
  $branchSlug = [string]$branchPayload.branch.branch_slug
  $quoteFileName = [string]$branchPayload.quotes.file_name
  $currentQuoteNumbers = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)
  $parsedLineMap = @{}

  foreach ($quote in @($branchPayload.quotes.records)) {
    if ($quote.qfu_quotenumber) {
      [void]$currentQuoteNumbers.Add([string]$quote.qfu_quotenumber)
    }
  }

  foreach ($line in @($branchPayload.quote_lines.records)) {
    $canonicalSourceId = [string]$line.qfu_sourceid
    if ([string]::IsNullOrWhiteSpace($canonicalSourceId)) {
      continue
    }
    $parsedLineMap[$canonicalSourceId] = $line
  }

  $liveLines = @(
    (Get-CrmRecords -conn $connection -EntityLogicalName "qfu_quoteline" -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $branchCode -Fields @(
        "qfu_quotelineid",
        "qfu_branchcode",
        "qfu_quotenumber",
        "qfu_linenumber",
        "qfu_sourceid",
        "qfu_uniquekey",
        "qfu_sourcefile",
        "createdon",
        "modifiedon"
      ) -TopCount 5000).CrmRecords
  )

  $groups = @{}
  foreach ($line in $liveLines) {
    $canonicalSourceId = Get-CanonicalQuoteLineSourceId -BranchCode ([string]$line.qfu_branchcode) -QuoteNumber ([string]$line.qfu_quotenumber) -LineNumber ([string]$line.qfu_linenumber)
    if ([string]::IsNullOrWhiteSpace($canonicalSourceId)) {
      continue
    }
    if (-not $groups.ContainsKey($canonicalSourceId)) {
      $groups[$canonicalSourceId] = New-Object System.Collections.Generic.List[object]
    }
    $groups[$canonicalSourceId].Add($line) | Out-Null
  }

  $normalized = New-Object System.Collections.Generic.List[object]
  $deletedDuplicateIds = New-Object System.Collections.Generic.List[string]
  $canonicalLiveIds = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)

  foreach ($canonicalSourceId in ($groups.Keys | Sort-Object)) {
    $winner = Get-LatestRecord -Records @($groups[$canonicalSourceId].ToArray())
    $canonicalUniqueKey = Get-CanonicalQuoteLineUniqueKey -QuoteNumber ([string]$winner.qfu_quotenumber) -LineNumber ([string]$winner.qfu_linenumber)
    $updatedFields = @{}
    if ([string]$winner.qfu_sourceid -ne $canonicalSourceId) {
      $updatedFields.qfu_sourceid = $canonicalSourceId
    }
    if ($canonicalUniqueKey -and [string]$winner.qfu_uniquekey -ne $canonicalUniqueKey) {
      $updatedFields.qfu_uniquekey = $canonicalUniqueKey
    }
    if ($updatedFields.Count -gt 0 -and $Apply) {
      Set-CrmRecord -conn $connection -EntityLogicalName "qfu_quoteline" -Id $winner.qfu_quotelineid -Fields $updatedFields | Out-Null
    }

    $duplicates = @($groups[$canonicalSourceId].ToArray() | Where-Object { [string]$_.qfu_quotelineid -ne [string]$winner.qfu_quotelineid })
    foreach ($duplicate in $duplicates) {
      if ($Apply) {
        $connection.Delete("qfu_quoteline", [guid]$duplicate.qfu_quotelineid)
      }
      $deletedDuplicateIds.Add([string]$duplicate.qfu_quotelineid) | Out-Null
    }

    $canonicalLiveIds.Add($canonicalSourceId) | Out-Null
    $normalized.Add([pscustomobject]@{
      canonical_source_id = $canonicalSourceId
      winner_id = [string]$winner.qfu_quotelineid
      updated = ($updatedFields.Count -gt 0)
      removed_duplicate_ids = @($duplicates | ForEach-Object { [string]$_.qfu_quotelineid })
    }) | Out-Null
  }

  $insertedLineSourceIds = New-Object System.Collections.Generic.List[string]
  foreach ($canonicalSourceId in ($parsedLineMap.Keys | Sort-Object)) {
    if ($canonicalLiveIds.Contains($canonicalSourceId)) {
      continue
    }
    if ($Apply) {
      $insertFields = ConvertTo-PlainHashtable -Value $parsedLineMap[$canonicalSourceId]
      $insertFields = Normalize-QuoteLineCreateFields -Fields $insertFields
      New-CrmRecord -conn $connection -EntityLogicalName "qfu_quoteline" -Fields $insertFields | Out-Null
    }
    $canonicalLiveIds.Add($canonicalSourceId) | Out-Null
    $insertedLineSourceIds.Add($canonicalSourceId) | Out-Null
  }

  $lineQuoteNumbers = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($canonicalSourceId in $canonicalLiveIds) {
    $parts = [string]$canonicalSourceId -split '\|'
    if ($parts.Length -ge 4) {
      [void]$lineQuoteNumbers.Add($parts[2])
    }
  }

  $liveQuotes = @(
    (Get-CrmRecords -conn $connection -EntityLogicalName "qfu_quote" -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $branchCode -Fields @(
        "qfu_quoteid",
        "qfu_branchcode",
        "qfu_branchslug",
        "qfu_quotenumber",
        "qfu_sourceid",
        "qfu_sourcefile",
        "qfu_active",
        "qfu_inactiveon",
        "qfu_lastseenon",
        "qfu_sourcedate",
        "qfu_sourceupdatedon",
        "createdon",
        "modifiedon"
      ) -TopCount 5000).CrmRecords
  )

  $quoteWorkingSet = Get-QuoteWorkingSet -LiveQuotes $liveQuotes
  $deactivatedQuotes = New-Object System.Collections.Generic.List[object]
  $reactivatedQuotes = New-Object System.Collections.Generic.List[object]
  $preservedQuotes = New-Object System.Collections.Generic.List[object]
  $remainingMissingQuotes = New-Object System.Collections.Generic.List[object]

  if ($Apply) {
    foreach ($removedQuoteId in @($quoteWorkingSet.removed_duplicate_ids)) {
      if ([string]::IsNullOrWhiteSpace([string]$removedQuoteId)) {
        continue
      }
      $connection.Delete("qfu_quote", [guid]$removedQuoteId)
    }
  }

  foreach ($quote in @($quoteWorkingSet.working_set)) {
    $quoteIsActive = Test-QuoteActive -Record $quote
    $quoteNumber = [string]$quote.qfu_quotenumber
    if ([string]::IsNullOrWhiteSpace($quoteNumber)) {
      continue
    }
    if ($lineQuoteNumbers.Contains($quoteNumber)) {
      if ($ReactivateQuotesWithRecoveredLines -and -not $quoteIsActive) {
        if ($Apply) {
          Set-CrmRecord -conn $connection -EntityLogicalName "qfu_quote" -Id $quote.qfu_quoteid -Fields @{
            qfu_active = $true
            qfu_inactiveon = $null
          } | Out-Null
        }
        $reactivatedQuotes.Add([pscustomobject]@{
          qfu_quoteid = [string]$quote.qfu_quoteid
          qfu_quotenumber = $quoteNumber
          qfu_sourceid = [string]$quote.qfu_sourceid
          qfu_sourcefile = [string]$quote.qfu_sourcefile
          reason = "quote header was reactivated because line history was recovered from the parsed workbook seed"
        }) | Out-Null
      }
      continue
    }

    if (-not $quoteIsActive) {
      continue
    }

    $seedStyleSourceId = [string]$quote.qfu_sourceid -like "$branchCode|SP830CA|*"
    $matchesCurrentSeed = $currentQuoteNumbers.Contains($quoteNumber)

    if ($seedStyleSourceId -and -not $matchesCurrentSeed) {
      if ($AllowQuoteCleanup) {
        if ($Apply) {
          Set-CrmRecord -conn $connection -EntityLogicalName "qfu_quote" -Id $quote.qfu_quoteid -Fields @{
            qfu_active = $false
            qfu_inactiveon = $repairTimestamp
          } | Out-Null
        }
        $deactivatedQuotes.Add([pscustomobject]@{
          qfu_quoteid = [string]$quote.qfu_quoteid
          qfu_quotenumber = $quoteNumber
          qfu_sourceid = [string]$quote.qfu_sourceid
          qfu_sourcefile = [string]$quote.qfu_sourcefile
          reason = "active quote header had no line rows and is absent from the current parsed SP830 workbook"
        }) | Out-Null
      } else {
        $preservedQuotes.Add([pscustomobject]@{
          qfu_quoteid = [string]$quote.qfu_quoteid
          qfu_quotenumber = $quoteNumber
          qfu_sourceid = [string]$quote.qfu_sourceid
          qfu_sourcefile = [string]$quote.qfu_sourcefile
          reason = "quote cleanup is disabled, so the header stayed visible even though no parsed line rows were found"
        }) | Out-Null
      }
      continue
    }

    $remainingMissingQuotes.Add([pscustomobject]@{
      qfu_quoteid = [string]$quote.qfu_quoteid
      qfu_quotenumber = $quoteNumber
      qfu_sourceid = [string]$quote.qfu_sourceid
      qfu_sourcefile = [string]$quote.qfu_sourcefile
      in_current_seed = $matchesCurrentSeed
    }) | Out-Null
  }

  $removedDuplicateLineIds = foreach ($item in $deletedDuplicateIds) { [string]$item }
  $insertedLineSourceIdValues = foreach ($item in $insertedLineSourceIds) { [string]$item }
  $deactivatedOrphanQuotes = foreach ($item in $deactivatedQuotes) { $item }
  $reactivatedQuoteHeaders = foreach ($item in $reactivatedQuotes) { $item }
  $preservedOrphanQuotes = foreach ($item in $preservedQuotes) { $item }
  $remainingMissingQuoteHeaders = foreach ($item in $remainingMissingQuotes) { $item }

  $branchResult = @{}
  $branchResult["branch_code"] = $branchCode
  $branchResult["branch_slug"] = $branchSlug
  $branchResult["parsed_quote_count"] = $branchPayload.quotes.records.Count
  $branchResult["parsed_quote_line_count"] = $branchPayload.quote_lines.records.Count
  $branchResult["live_quote_count"] = $liveQuotes.Count
  $branchResult["normalized_quote_count"] = $quoteWorkingSet.working_set.Count
  $branchResult["removed_duplicate_quote_ids"] = @($quoteWorkingSet.removed_duplicate_ids)
  $branchResult["normalized_quote_groups"] = @($quoteWorkingSet.normalized_groups)
  $branchResult["live_quote_line_count"] = $liveLines.Count
  $branchResult["normalized_line_groups"] = $normalized.Count
  $branchResult["removed_duplicate_line_ids"] = $removedDuplicateLineIds
  $branchResult["inserted_line_source_ids"] = $insertedLineSourceIdValues
  $branchResult["deactivated_orphan_quotes"] = $deactivatedOrphanQuotes
  $branchResult["reactivated_quotes"] = $reactivatedQuoteHeaders
  $branchResult["preserved_orphan_quotes"] = $preservedOrphanQuotes
  $branchResult["remaining_missing_quote_headers"] = $remainingMissingQuoteHeaders
  $branchResult["parsed_quote_source_file"] = $quoteFileName
  $branchResults[$branchCode] = $branchResult
}

$result = [pscustomobject]@{
  captured_at = (Get-Date).ToUniversalTime().ToString("o")
  target_environment = $TargetEnvironmentUrl
  apply = [bool]$Apply
  reactivate_quotes_with_recovered_lines = [bool]$ReactivateQuotesWithRecoveredLines
  allow_quote_cleanup = [bool]$AllowQuoteCleanup
  parsed_workbook_json = $parsedWorkbookJsonPath
  branches = @($branchResults.Values)
}

Write-Utf8Json -Path $outputJsonPath -Object $result

$result.branches |
  Select-Object branch_code,
    parsed_quote_count,
    parsed_quote_line_count,
    live_quote_count,
    normalized_quote_count,
    @{ Name = "removed_quote_duplicates"; Expression = { @($_.removed_duplicate_quote_ids).Count } },
    live_quote_line_count,
    @{ Name = "inserted_lines"; Expression = { @($_.inserted_line_source_ids).Count } },
    @{ Name = "reactivated_quotes"; Expression = { @($_.reactivated_quotes).Count } },
    @{ Name = "preserved_quotes"; Expression = { @($_.preserved_orphan_quotes).Count } },
    @{ Name = "deactivated_quotes"; Expression = { @($_.deactivated_orphan_quotes).Count } },
    @{ Name = "remaining_missing"; Expression = { @($_.remaining_missing_quote_headers).Count } } |
  Format-Table -AutoSize

Write-Host "OUTPUT_PATH=$outputJsonPath"
