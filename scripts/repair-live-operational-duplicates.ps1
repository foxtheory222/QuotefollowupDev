param(
  [string]$TargetEnvironmentUrl = "https://regionaloperationshub.crm.dynamics.com",
  [string]$Username = "smcfarlane@applied.com",
  [string[]]$BranchCodes = @("4171", "4172", "4173"),
  [string[]]$Entities = @("qfu_quote", "qfu_backorder", "qfu_marginexception", "qfu_deliverynotpgi"),
  [switch]$Apply,
  [string]$OutputPath = "results\\live-operational-duplicate-repair.json"
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

function New-EntityDefinition {
  param([string]$EntityLogicalName)

  switch ($EntityLogicalName) {
    "qfu_quote" {
      return @{
        EntityLogicalName = "qfu_quote"
        IdField = "qfu_quoteid"
        Fields = @("qfu_quoteid", "qfu_branchcode", "qfu_sourceid", "qfu_quotenumber", "qfu_active", "qfu_inactiveon", "qfu_lastseenon", "createdon", "modifiedon")
        ActiveField = "qfu_active"
        SnapshotField = "qfu_lastseenon"
        AllowInactiveHistoryDuplicates = $false
      }
    }
    "qfu_backorder" {
      return @{
        EntityLogicalName = "qfu_backorder"
        IdField = "qfu_backorderid"
        Fields = @("qfu_backorderid", "qfu_branchcode", "qfu_sourceid", "qfu_salesdocnumber", "qfu_active", "qfu_inactiveon", "qfu_lastseenon", "createdon", "modifiedon")
        ActiveField = "qfu_active"
        SnapshotField = "qfu_lastseenon"
        AllowInactiveHistoryDuplicates = $false
      }
    }
    "qfu_marginexception" {
      return @{
        EntityLogicalName = "qfu_marginexception"
        IdField = "qfu_marginexceptionid"
        Fields = @("qfu_marginexceptionid", "qfu_branchcode", "qfu_sourceid", "qfu_billingdocumentnumber", "qfu_reviewtype", "qfu_snapshotdate", "createdon", "modifiedon")
        ActiveField = $null
        SnapshotField = "qfu_snapshotdate"
        AllowInactiveHistoryDuplicates = $false
      }
    }
    "qfu_deliverynotpgi" {
      return @{
        EntityLogicalName = "qfu_deliverynotpgi"
        IdField = "qfu_deliverynotpgiid"
        Fields = @("qfu_deliverynotpgiid", "qfu_branchcode", "qfu_sourceid", "qfu_deliverynumber", "qfu_deliveryline", "qfu_active", "qfu_inactiveon", "qfu_snapshotcapturedon", "createdon", "modifiedon")
        ActiveField = "qfu_active"
        SnapshotField = "qfu_snapshotcapturedon"
        AllowInactiveHistoryDuplicates = $true
      }
    }
    default {
      throw "Unsupported entity: $EntityLogicalName"
    }
  }
}

function Compare-DuplicateRows {
  param(
    [object]$Left,
    [object]$Right,
    [string]$IdField
  )

  $leftModified = Get-DateValue $Left.modifiedon
  $rightModified = Get-DateValue $Right.modifiedon
  $leftModifiedTicks = if ($leftModified) { $leftModified.Ticks } else { 0 }
  $rightModifiedTicks = if ($rightModified) { $rightModified.Ticks } else { 0 }
  if ($leftModifiedTicks -ne $rightModifiedTicks) {
    return $rightModifiedTicks - $leftModifiedTicks
  }

  $leftSnapshot = Get-DateValue $Left.qfu_snapshotcapturedon
  $rightSnapshot = Get-DateValue $Right.qfu_snapshotcapturedon
  $leftSnapshotTicks = if ($leftSnapshot) { $leftSnapshot.Ticks } else { 0 }
  $rightSnapshotTicks = if ($rightSnapshot) { $rightSnapshot.Ticks } else { 0 }
  if ($leftSnapshotTicks -ne $rightSnapshotTicks) {
    return $rightSnapshotTicks - $leftSnapshotTicks
  }

  $leftActive = if ($Left.PSObject.Properties["qfu_active"] -and $Left.qfu_active) { 1 } else { 0 }
  $rightActive = if ($Right.PSObject.Properties["qfu_active"] -and $Right.qfu_active) { 1 } else { 0 }
  if ($leftActive -ne $rightActive) {
    return $rightActive - $leftActive
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

function Get-DuplicateResolutionPlan {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [hashtable]$Definition,
    [string[]]$BranchCodes
  )

  $groups = New-Object System.Collections.Generic.List[object]

  foreach ($branchCode in $BranchCodes) {
    $rows = @(
      (Get-CrmRecords -conn $Connection -EntityLogicalName $Definition.EntityLogicalName -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $branchCode -Fields $Definition.Fields -TopCount 5000).CrmRecords |
        Where-Object { $_.qfu_sourceid }
    )

    $duplicateGroups = @(
      $rows |
        Group-Object -Property qfu_sourceid |
        Where-Object { $_.Count -gt 1 }
    )

    foreach ($group in $duplicateGroups) {
      $candidateRows = @($group.Group)
      $activeRows = if ($Definition.ActiveField) {
        @(
          $group.Group | Where-Object {
            (Get-EntityBoolValue -EntityLogicalName $Definition.EntityLogicalName -Value $_.$($Definition.ActiveField)) -eq $true -and -not (Get-DateValue $_.qfu_inactiveon)
          }
        )
      } else {
        @($group.Group)
      }

      if ($Definition.AllowInactiveHistoryDuplicates -and $activeRows.Count -le 1) {
        $orderedHistory = @($group.Group | Sort-Object -Property @{
              Expression = {
                if ($Definition.ActiveField) {
                  if ((Get-EntityBoolValue -EntityLogicalName $Definition.EntityLogicalName -Value $_.$($Definition.ActiveField)) -eq $true -and -not (Get-DateValue $_.qfu_inactiveon)) { 1 } else { 0 }
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
            })
        $winnerHistory = $orderedHistory | Select-Object -First 1
        $groups.Add([pscustomobject]@{
          entity = $Definition.EntityLogicalName
          branch_code = $branchCode
          source_id = [string]$group.Name
          winner_id = [string]$winnerHistory.$($Definition.IdField)
          winner_createdon = if ($winnerHistory.createdon) { ([datetime]$winnerHistory.createdon).ToString("o") } else { $null }
          winner_active = if ($Definition.ActiveField) { Get-EntityBoolValue -EntityLogicalName $Definition.EntityLogicalName -Value $winnerHistory.$($Definition.ActiveField) } else { $null }
          winner_snapshotcapturedon = if ($Definition.SnapshotField -and $winnerHistory.PSObject.Properties[$Definition.SnapshotField]) { $snapshot = Get-DateValue $winnerHistory.$($Definition.SnapshotField); if ($snapshot) { $snapshot.ToString("o") } else { $null } } else { $null }
          removed_ids = @()
          action = "skip-history"
          reason = "inactive history reappearance is allowed; no duplicate active current rows were found for this canonical key."
        }) | Out-Null
        continue
      }

      if ($Definition.AllowInactiveHistoryDuplicates) {
        $candidateRows = @($activeRows)
      }

      $ordered = @($candidateRows | Sort-Object -Property @{
            Expression = {
              if ($Definition.ActiveField) {
                if ((Get-EntityBoolValue -EntityLogicalName $Definition.EntityLogicalName -Value $_.$($Definition.ActiveField)) -eq $true -and -not (Get-DateValue $_.qfu_inactiveon)) { 1 } else { 0 }
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
          })

      $winner = $ordered | Select-Object -First 1
      $duplicates = @($ordered | Select-Object -Skip 1)
      $groups.Add([pscustomobject]@{
        entity = $Definition.EntityLogicalName
        branch_code = $branchCode
        source_id = [string]$group.Name
        winner_id = [string]$winner.$($Definition.IdField)
        winner_createdon = if ($winner.createdon) { ([datetime]$winner.createdon).ToString("o") } else { $null }
        winner_active = if ($Definition.ActiveField) { Get-EntityBoolValue -EntityLogicalName $Definition.EntityLogicalName -Value $winner.$($Definition.ActiveField) } else { $null }
        winner_snapshotcapturedon = if ($Definition.SnapshotField -and $winner.PSObject.Properties[$Definition.SnapshotField]) { $snapshot = Get-DateValue $winner.$($Definition.SnapshotField); if ($snapshot) { $snapshot.ToString("o") } else { $null } } else { $null }
        removed_ids = @($duplicates | ForEach-Object { [string]$_.$($Definition.IdField) })
        action = "delete-duplicates"
        reason = "more than one current row exists for the canonical key; keep the newest winning row and delete the extras."
      }) | Out-Null
    }
  }

  return @($groups.ToArray())
}

$outputFullPath = Resolve-RepoPath -Path $OutputPath
$connection = Connect-Target -Url $TargetEnvironmentUrl -User $Username

$entityPlans = New-Object System.Collections.Generic.List[object]
$deletedCount = 0

foreach ($entityName in $Entities) {
  $definition = New-EntityDefinition -EntityLogicalName $entityName
  $planRows = @(Get-DuplicateResolutionPlan -Connection $connection -Definition $definition -BranchCodes $BranchCodes)

  if ($Apply) {
    foreach ($planRow in $planRows) {
      foreach ($recordId in @($planRow.removed_ids)) {
        if ([string]::IsNullOrWhiteSpace($recordId)) {
          continue
        }
        $connection.Delete($definition.EntityLogicalName, [guid]$recordId)
        $deletedCount += 1
      }
    }
  }

  $entityPlans.Add([pscustomobject]@{
    entity = $entityName
    duplicate_group_count = $planRows.Count
    repairable_group_count = @($planRows | Where-Object { $_.action -eq "delete-duplicates" }).Count
    ignored_history_group_count = @($planRows | Where-Object { $_.action -eq "skip-history" }).Count
    planned_deletes = @($planRows | ForEach-Object { @($_.removed_ids).Count } | Measure-Object -Sum).Sum
    groups = $planRows
  }) | Out-Null
}

$report = [pscustomobject]@{
  generated_on = (Get-Date).ToUniversalTime().ToString("o")
  target_environment_url = $TargetEnvironmentUrl
  branch_codes = @($BranchCodes)
  apply = [bool]$Apply
  deleted_count = $deletedCount
  entities = @($entityPlans.ToArray())
}

Write-Utf8Json -Path $outputFullPath -Object $report

Write-Host "OUTPUT_PATH=$outputFullPath"
Write-Host "APPLY=$([bool]$Apply)"
Write-Host "DELETED_COUNT=$deletedCount"
