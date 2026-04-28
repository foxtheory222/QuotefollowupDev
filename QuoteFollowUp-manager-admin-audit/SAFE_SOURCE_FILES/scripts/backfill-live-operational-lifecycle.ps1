param(
  [string]$TargetEnvironmentUrl = "<URL>
  [string]$Username = "<EMAIL>",
  [string[]]$BranchCodes = @("4171", "4172", "4173"),
  [switch]$Apply,
  [string]$OutputPath = "results\\live-operational-lifecycle-backfill.json"
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

  $directory = Split-Path -Parent $Path
  if ($directory) {
    Ensure-Directory -Path $directory
  }

  [System.IO.File]::WriteAllText($Path, ($Object | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
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

function Resolve-LastSeenOn {
  param(
    [object]$Row,
    [string[]]$CandidateFields
  )

  foreach ($field in @($CandidateFields)) {
    $property = $Row.PSObject.Properties[$field]
    if (-not $property) {
      continue
    }
    $value = Get-DateValue $property.Value
    if ($value) {
      return $value
    }
  }

  return $null
}

$definitions = @(
  @{
    EntityLogicalName = "qfu_quote"
    IdField = "qfu_quoteid"
    Fields = @("qfu_quoteid", "qfu_branchcode", "qfu_sourceid", "qfu_active", "qfu_inactiveon", "qfu_lastseenon", "qfu_sourceupdatedon", "qfu_sourcedate", "createdon")
    LastSeenTargetField = "qfu_lastseenon"
    LastSeenFields = @("qfu_lastseenon", "qfu_sourceupdatedon", "qfu_sourcedate", "createdon")
  },
  @{
    EntityLogicalName = "qfu_backorder"
    IdField = "qfu_backorderid"
    Fields = @("qfu_backorderid", "qfu_branchcode", "qfu_sourceid", "qfu_active", "qfu_inactiveon", "qfu_lastseenon", "modifiedon", "createdon", "qfu_ontimedate")
    LastSeenTargetField = "qfu_lastseenon"
    LastSeenFields = @("qfu_lastseenon", "modifiedon", "createdon", "qfu_ontimedate")
  },
  @{
    EntityLogicalName = "qfu_deliverynotpgi"
    IdField = "qfu_deliverynotpgiid"
    Fields = @("qfu_deliverynotpgiid", "qfu_branchcode", "qfu_sourceid", "qfu_active", "qfu_inactiveon", "qfu_snapshotcapturedon", "modifiedon", "createdon")
    LastSeenTargetField = $null
    LastSeenFields = @("qfu_snapshotcapturedon", "modifiedon", "createdon")
  }
)

$connection = Connect-Target -Url $TargetEnvironmentUrl -User $Username
$entitySummaries = New-Object System.Collections.Generic.List[object]
$updatedCount = 0

foreach ($definition in $definitions) {
  $entityRows = @()
  foreach ($branchCode in $BranchCodes) {
    $entityRows += @(
      (Get-CrmRecords -conn $connection -EntityLogicalName $definition.EntityLogicalName -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $branchCode -Fields $definition.Fields -TopCount 5000).CrmRecords
    )
  }

  $changes = New-Object System.Collections.Generic.List[object]
  foreach ($row in @($entityRows | Where-Object { $_.qfu_sourceid })) {
    $currentActive = Get-EntityBoolValue -EntityLogicalName $definition.EntityLogicalName -Value $row.qfu_active
    $inactiveOn = Get-DateValue $row.qfu_inactiveon
    $desiredActive = if ($inactiveOn) { $false } else { $true }
    $currentLastSeen = if ($definition.LastSeenTargetField) { Get-DateValue $row.$($definition.LastSeenTargetField) } else { $null }
    $desiredLastSeen = Resolve-LastSeenOn -Row $row -CandidateFields $definition.LastSeenFields

    $fields = [ordered]@{}
    if ($currentActive -ne $desiredActive) {
      $fields["qfu_active"] = $desiredActive
    }
    if ($definition.LastSeenTargetField -and -not $currentLastSeen -and $desiredLastSeen) {
      $fields[$definition.LastSeenTargetField] = $desiredLastSeen
    }

    if ($fields.Count -eq 0) {
      continue
    }

    if ($Apply) {
      Set-CrmRecord -conn $connection -EntityLogicalName $definition.EntityLogicalName -Id $row.$($definition.IdField) -Fields $fields | Out-Null
      $updatedCount += 1
    }

    $changes.Add([pscustomobject]@{
      entity = $definition.EntityLogicalName
      branch_code = [string]$row.qfu_branchcode
      record_id = [string]$row.$($definition.IdField)
      source_id = [string]$row.qfu_sourceid
      desired_active = $desiredActive
      desired_lastseenon = if ($desiredLastSeen) { $desiredLastSeen.ToString("o") } else { $null }
      fields = [pscustomobject]$fields
    }) | Out-Null
  }

  $entitySummaries.Add([pscustomobject]@{
    entity = $definition.EntityLogicalName
    candidate_updates = $changes.Count
    changes = @($changes.ToArray())
  }) | Out-Null
}

$report = [pscustomobject]@{
  generated_on = (Get-Date).ToUniversalTime().ToString("o")
  target_environment_url = $TargetEnvironmentUrl
  branch_codes = @($BranchCodes)
  apply = [bool]$Apply
  updated_count = $updatedCount
  entities = @($entitySummaries.ToArray())
}

$outputFullPath = Resolve-RepoPath -Path $OutputPath
Write-Utf8Json -Path $outputFullPath -Object $report

Write-Host "OUTPUT_PATH=$outputFullPath"
Write-Host "APPLY=$([bool]$Apply)"
Write-Host "UPDATED_COUNT=$updatedCount"
