param(
  [string]$TargetEnvironmentUrl = "https://regionaloperationshub.crm.dynamics.com",
  [string]$Username = "smcfarlane@applied.com",
  [string[]]$BranchCodes = @("4171", "4172", "4173"),
  [switch]$Apply,
  [string]$OutputPath = "results\live-freight-current-state-duplicate-repair.json"
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

  [System.IO.File]::WriteAllText($resolvedPath, ($Object | ConvertTo-Json -Depth 30), [System.Text.UTF8Encoding]::new($false))
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

function Convert-ToSlugComponent {
  param(
    [AllowNull()][object]$Value,
    [int]$MaxLength = 72
  )

  $text = (Get-TextValue $Value).ToLowerInvariant()
  $text = [regex]::Replace($text, "[^a-z0-9]+", "-").Trim("-")
  if ([string]::IsNullOrWhiteSpace($text)) {
    return "none"
  }
  if ($text.Length -gt $MaxLength) {
    $text = $text.Substring(0, $MaxLength).Trim("-")
  }
  if ([string]::IsNullOrWhiteSpace($text)) {
    return "none"
  }
  return $text
}

function Get-CanonicalFreightSourceId {
  param([object]$Row)

  $branch = Convert-ToSlugComponent $Row.qfu_branchcode 16
  $family = Convert-ToSlugComponent $Row.qfu_sourcefamily 40
  $invoice = Convert-ToSlugComponent $Row.qfu_invoicenumber 96
  return "$branch|$family|invoice|$invoice"
}

function Get-CanonicalGroupKey {
  param([object]$Row)

  $branch = (Get-TextValue $Row.qfu_branchcode).ToUpperInvariant()
  $family = (Get-TextValue $Row.qfu_sourcefamily).ToUpperInvariant()
  $invoice = (Get-TextValue $Row.qfu_invoicenumber).ToUpperInvariant()
  if ([string]::IsNullOrWhiteSpace($branch) -or [string]::IsNullOrWhiteSpace($family) -or [string]::IsNullOrWhiteSpace($invoice)) {
    return ""
  }
  return "$branch|$family|$invoice"
}

function Get-IsArchived {
  param([object]$Row)
  return (Get-BoolValue $Row.qfu_isarchived)
}

function Get-WorkScore {
  param([object]$Row)

  $score = 0
  $status = Get-TextValue $Row.qfu_status
  if ($status -and $status -notin @("Open", "Unreviewed")) { $score += 1000 }
  if (Get-TextValue $Row.qfu_ownername) { $score += 500 }
  if (Get-TextValue $Row.qfu_owneridentifier) { $score += 500 }
  if (Get-TextValue $Row.qfu_comment) { $score += 300 }
  if (Get-DateValue $Row.qfu_commentupdatedon) { $score += 100 }
  if (Get-DateValue $Row.qfu_claimedon) { $score += 100 }
  if (-not (Get-IsArchived $Row)) { $score += 50 }
  return $score
}

function Get-LatestDate {
  param([object[]]$Values)

  $dates = @($Values | ForEach-Object { Get-DateValue $_ } | Where-Object { $null -ne $_ })
  if (-not $dates.Count) {
    return $null
  }
  return ($dates | Sort-Object | Select-Object -Last 1)
}

function Get-PreferredText {
  param([object[]]$Values)

  $candidates = @($Values | ForEach-Object { Get-TextValue $_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  if (-not $candidates.Count) {
    return ""
  }
  return ($candidates | Sort-Object { $_.Length } -Descending | Select-Object -First 1)
}

function Get-FreightRows {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string[]]$Branches
  )

  $fields = @(
    "qfu_freightworkitemid",
    "qfu_name",
    "qfu_sourceid",
    "qfu_branchcode",
    "qfu_branchslug",
    "qfu_regionslug",
    "qfu_sourcefamily",
    "qfu_sourcecarrier",
    "qfu_sourcefilename",
    "qfu_importbatchid",
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
    "qfu_direction",
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
    "qfu_lastseenon",
    "qfu_totalamount",
    "createdon",
    "modifiedon"
  )

  $rows = New-Object System.Collections.Generic.List[object]
  foreach ($branchCode in $Branches) {
    $branchRows = @((Get-CrmRecords -conn $Connection -EntityLogicalName "qfu_freightworkitem" -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $branchCode -Fields $fields -TopCount 5000).CrmRecords)
    foreach ($row in $branchRows) {
      $rows.Add($row) | Out-Null
    }
  }

  return @($rows.ToArray())
}

function Select-SurvivorRow {
  param(
    [object[]]$Rows,
    [object[]]$ActiveRows,
    [string]$CanonicalSourceId
  )

  $canonicalRows = @($Rows | Where-Object { (Get-TextValue $_.qfu_sourceid) -eq $CanonicalSourceId })
  if ($canonicalRows.Count) {
    return @($canonicalRows | Sort-Object @{ Expression = { Get-IsArchived $_ } }, @{ Expression = { Get-DateValue $_.modifiedon }; Descending = $true })[0]
  }

  return @($ActiveRows | Sort-Object @{ Expression = { Get-WorkScore $_ }; Descending = $true }, @{ Expression = { Get-DateValue $_.modifiedon }; Descending = $true }, @{ Expression = { Get-DecimalValue $_.qfu_totalamount }; Descending = $true })[0]
}

function New-FreightDuplicateRepairPlan {
  param([object[]]$Rows)

  $groups = @{}
  foreach ($row in $Rows) {
    $key = Get-CanonicalGroupKey $row
    if ([string]::IsNullOrWhiteSpace($key)) {
      continue
    }
    if (-not $groups.ContainsKey($key)) {
      $groups[$key] = New-Object System.Collections.Generic.List[object]
    }
    $groups[$key].Add($row) | Out-Null
  }

  $plans = New-Object System.Collections.Generic.List[object]
  foreach ($key in @($groups.Keys | Sort-Object)) {
    $groupRows = @($groups[$key].ToArray())
    $activeRows = @($groupRows | Where-Object { -not (Get-IsArchived $_) })
    if (-not $activeRows.Count) {
      continue
    }

    if ($activeRows.Count -le 1) {
      continue
    }

    $canonicalSourceId = Get-CanonicalFreightSourceId $activeRows[0]
    $survivor = Select-SurvivorRow -Rows $groupRows -ActiveRows $activeRows -CanonicalSourceId $canonicalSourceId
    $stateSource = @($activeRows | Sort-Object @{ Expression = { Get-WorkScore $_ }; Descending = $true }, @{ Expression = { Get-DateValue $_.modifiedon }; Descending = $true })[0]
    $duplicateRows = @($activeRows | Where-Object { [string]$_.qfu_freightworkitemid -ne [string]$survivor.qfu_freightworkitemid })

    $amountBySourceId = @{}
    foreach ($row in $activeRows) {
      $sourceId = Get-TextValue $row.qfu_sourceid
      if ([string]::IsNullOrWhiteSpace($sourceId)) {
        $sourceId = [string]$row.qfu_freightworkitemid
      }
      if (-not $amountBySourceId.ContainsKey($sourceId)) {
        $amountBySourceId[$sourceId] = (Get-DecimalValue $row.qfu_totalamount)
      }
    }
    $totalAmount = [decimal]0
    foreach ($amount in $amountBySourceId.Values) {
      if ($null -ne $amount) {
        $totalAmount += [decimal]$amount
      }
    }

    $latestLastSeen = Get-LatestDate @($activeRows | ForEach-Object { $_.qfu_lastseenon })
    if (-not $latestLastSeen) {
      $latestLastSeen = Get-LatestDate @($activeRows | ForEach-Object { $_.modifiedon })
    }
    $latestActivity = Get-LatestDate @($activeRows | ForEach-Object { @($_.qfu_lastactivityon, $_.qfu_commentupdatedon, $_.qfu_claimedon, $_.modifiedon) })

    $survivorFields = @{
      qfu_sourceid = $canonicalSourceId
      qfu_name = "$($stateSource.qfu_branchcode) Freight $($stateSource.qfu_invoicenumber)"
      qfu_isarchived = $false
    }
    if ($totalAmount -ne 0) { $survivorFields.qfu_totalamount = [decimal]::Round($totalAmount, 2) }
    if ($latestLastSeen) { $survivorFields.qfu_lastseenon = $latestLastSeen }
    if ($latestActivity) { $survivorFields.qfu_lastactivityon = $latestActivity }
    if (Get-TextValue $stateSource.qfu_status) { $survivorFields.qfu_status = Get-TextValue $stateSource.qfu_status }
    if (Get-TextValue $stateSource.qfu_ownername) { $survivorFields.qfu_ownername = Get-TextValue $stateSource.qfu_ownername }
    if (Get-TextValue $stateSource.qfu_owneridentifier) { $survivorFields.qfu_owneridentifier = Get-TextValue $stateSource.qfu_owneridentifier }
    if (Get-DateValue $stateSource.qfu_claimedon) { $survivorFields.qfu_claimedon = Get-DateValue $stateSource.qfu_claimedon }
    if ($null -ne $stateSource.qfu_comment) { $survivorFields.qfu_comment = [string]$stateSource.qfu_comment }
    if (Get-DateValue $stateSource.qfu_commentupdatedon) { $survivorFields.qfu_commentupdatedon = Get-DateValue $stateSource.qfu_commentupdatedon }
    if (Get-TextValue $stateSource.qfu_commentupdatedbyname) { $survivorFields.qfu_commentupdatedbyname = Get-TextValue $stateSource.qfu_commentupdatedbyname }
    if (Get-PreferredText @($activeRows | ForEach-Object { $_.qfu_trackingnumber })) { $survivorFields.qfu_trackingnumber = Get-PreferredText @($activeRows | ForEach-Object { $_.qfu_trackingnumber }) }
    if (Get-PreferredText @($activeRows | ForEach-Object { $_.qfu_reference })) { $survivorFields.qfu_reference = Get-PreferredText @($activeRows | ForEach-Object { $_.qfu_reference }) }

    $statefulRows = @($activeRows | Where-Object { (Get-WorkScore $_) -ge 300 })
    $plan = [pscustomobject]@{
      group_key = $key
      canonical_sourceid = $canonicalSourceId
      branch_code = Get-TextValue $stateSource.qfu_branchcode
      source_family = Get-TextValue $stateSource.qfu_sourcefamily
      invoice_number = Get-TextValue $stateSource.qfu_invoicenumber
      active_row_count_before = $activeRows.Count
      total_row_count_before = $groupRows.Count
      survivor_id = [string]$survivor.qfu_freightworkitemid
      survivor_sourceid_before = Get-TextValue $survivor.qfu_sourceid
      survivor_fields = $survivorFields
      duplicate_ids_to_archive = @($duplicateRows | ForEach-Object { [string]$_.qfu_freightworkitemid })
      duplicate_sourceids_to_archive = @($duplicateRows | ForEach-Object { Get-TextValue $_.qfu_sourceid })
      rolled_total_amount = [decimal]::Round($totalAmount, 2)
      stateful_row_count = $statefulRows.Count
      stateful_row_ids = @($statefulRows | ForEach-Object { [string]$_.qfu_freightworkitemid })
    }
    $plans.Add($plan) | Out-Null
  }

  return @($plans.ToArray())
}

function Apply-FreightDuplicateRepairPlan {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [object[]]$Plans
  )

  $now = [datetime]::UtcNow
  foreach ($plan in $Plans) {
    Set-CrmRecord -conn $Connection -EntityLogicalName "qfu_freightworkitem" -Id $plan.survivor_id -Fields $plan.survivor_fields | Out-Null
    foreach ($duplicateId in @($plan.duplicate_ids_to_archive)) {
      Set-CrmRecord -conn $Connection -EntityLogicalName "qfu_freightworkitem" -Id $duplicateId -Fields @{
        qfu_isarchived = $true
        qfu_archivedon = $now
      } | Out-Null
    }
  }
}

$target = Connect-Target -Url $TargetEnvironmentUrl -User $Username
Write-Host "Connected target: $($target.ConnectedOrgFriendlyName)"

$rows = Get-FreightRows -Connection $target -Branches $BranchCodes
$plans = New-FreightDuplicateRepairPlan -Rows $rows

if ($Apply) {
  Apply-FreightDuplicateRepairPlan -Connection $target -Plans $plans
}

$result = [ordered]@{
  target_environment = $TargetEnvironmentUrl
  captured_at = ([datetime]::UtcNow.ToString("o"))
  applied = [bool]$Apply
  branch_codes = @($BranchCodes)
  scanned_rows = @($rows).Count
  duplicate_groups = @($plans).Count
  active_rows_before = @($plans | ForEach-Object { $_.active_row_count_before } | Measure-Object -Sum).Sum
  survivors_to_update = @($plans).Count
  duplicate_rows_to_archive = @($plans | ForEach-Object { @($_.duplicate_ids_to_archive).Count } | Measure-Object -Sum).Sum
  plans = @($plans)
}

Write-Utf8Json -Path $OutputPath -Object $result
Write-Output ($result | ConvertTo-Json -Depth 30)
