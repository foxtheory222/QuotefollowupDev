param(
  [string]$TargetEnvironmentUrl = "https://regionaloperationshub.crm.dynamics.com",
  [string]$Username = "smcfarlane@applied.com",
  [string]$AppliedPlanPath = "results\live-freight-invoice-survivor-restore-applied-20260424.json",
  [string]$OutputPath = "results\live-freight-invoice-survivor-restore-postcheck.json"
)

$ErrorActionPreference = "Stop"

Import-Module Microsoft.Xrm.Data.Powershell

function Resolve-PathFromLocation {
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

  $resolvedPath = Resolve-PathFromLocation $Path
  $directory = Split-Path -Parent $resolvedPath
  if ($directory) {
    Ensure-Directory -Path $directory
  }
  [System.IO.File]::WriteAllText($resolvedPath, ($Object | ConvertTo-Json -Depth 30), [System.Text.UTF8Encoding]::new($false))
}

function Get-TextValue {
  param([AllowNull()][object]$Value)
  if ($null -eq $Value) { return "" }
  return ([string]$Value).Trim()
}

function Get-DecimalValue {
  param([AllowNull()][object]$Value)
  if ($null -eq $Value) { return $null }
  try {
    return [decimal]$Value
  } catch {
    $text = (Get-TextValue $Value) -replace ",", ""
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    try { return [decimal]$text } catch { return $null }
  }
}

function Get-BoolValue {
  param([AllowNull()][object]$Value)
  if ($null -eq $Value) { return $false }
  if ($Value -is [bool]) { return [bool]$Value }
  return ((Get-TextValue $Value).ToLowerInvariant() -in @("true", "1", "yes"))
}

$planPath = Resolve-PathFromLocation $AppliedPlanPath
$applied = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
$branchCodes = @($applied.branch_codes)

$conn = Connect-CrmOnline -ServerUrl $TargetEnvironmentUrl -ForceOAuth -Username $Username
if (-not $conn -or -not $conn.IsReady) {
  throw "Dataverse connection failed for $TargetEnvironmentUrl : $($conn.LastCrmError)"
}
Write-Host "Connected target: $($conn.ConnectedOrgFriendlyName)"

$fields = @(
  "qfu_freightworkitemid",
  "qfu_sourceid",
  "qfu_branchcode",
  "qfu_sourcefamily",
  "qfu_invoicenumber",
  "qfu_totalamount",
  "qfu_ownername",
  "qfu_isarchived",
  "qfu_archivedon",
  "qfu_lastseenon",
  "modifiedon"
)

$rows = New-Object System.Collections.Generic.List[object]
foreach ($branchCode in $branchCodes) {
  $branchRows = @((Get-CrmRecords -conn $conn -EntityLogicalName "qfu_freightworkitem" -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $branchCode -Fields $fields -TopCount 5000).CrmRecords)
  foreach ($row in $branchRows) {
    $rows.Add($row) | Out-Null
  }
}
$allRows = @($rows.ToArray())

$rowsById = @{}
$rowsBySourceId = @{}
foreach ($row in $allRows) {
  $id = [string]$row.qfu_freightworkitemid
  if ($id) { $rowsById[$id] = $row }
  $sourceId = Get-TextValue $row.qfu_sourceid
  if ($sourceId) {
    if (-not $rowsBySourceId.ContainsKey($sourceId)) {
      $rowsBySourceId[$sourceId] = New-Object System.Collections.Generic.List[object]
    }
    $rowsBySourceId[$sourceId].Add($row) | Out-Null
  }
}

$planChecks = New-Object System.Collections.Generic.List[object]
foreach ($plan in @($applied.plans)) {
  $invoiceRows = @($plan.invoice_survivor_ids | ForEach-Object { $rowsById[[string]$_] } | Where-Object { $null -ne $_ })
  $restoredRows = New-Object System.Collections.Generic.List[object]
  $duplicateSourceIds = New-Object System.Collections.Generic.List[string]
  foreach ($sourceId in @($plan.restored_sourceids)) {
    $sourceRows = if ($rowsBySourceId.ContainsKey([string]$sourceId)) { @($rowsBySourceId[[string]$sourceId].ToArray()) } else { @() }
    if ($sourceRows.Count -gt 1) {
      $duplicateSourceIds.Add([string]$sourceId) | Out-Null
    }
    foreach ($sourceRow in $sourceRows) {
      if (-not (Get-BoolValue $sourceRow.qfu_isarchived)) {
        $restoredRows.Add($sourceRow) | Out-Null
      }
    }
  }

  $restoredTotal = [decimal]0
  foreach ($restoredRow in @($restoredRows.ToArray())) {
    $amount = Get-DecimalValue $restoredRow.qfu_totalamount
    if ($null -ne $amount) {
      $restoredTotal += $amount
    }
  }

  $planChecks.Add([pscustomobject]@{
      key = [string]$plan.key
      invoice_survivor_count = @($invoiceRows).Count
      invoice_survivors_archived = @($invoiceRows | Where-Object { Get-BoolValue $_.qfu_isarchived }).Count
      expected_restored_count = [int]$plan.restored_record_count
      active_restored_count = @($restoredRows.ToArray()).Count
      expected_restored_total = Get-DecimalValue $plan.restored_total_amount
      active_restored_total = [decimal]::Round($restoredTotal, 2)
      duplicate_restored_sourceids = @($duplicateSourceIds.ToArray())
    }) | Out-Null
}

$activeInvoiceRows = @($allRows | Where-Object {
    (Get-TextValue $_.qfu_sourceid) -match "\|invoice\|" -and
    (Get-TextValue $_.qfu_sourcefamily).ToUpperInvariant() -ne "FREIGHT_REDWOOD" -and
    -not (Get-BoolValue $_.qfu_isarchived)
  })

$failedChecks = @($planChecks.ToArray() | Where-Object {
    $_.invoice_survivors_archived -ne $_.invoice_survivor_count -or
    $_.active_restored_count -ne $_.expected_restored_count -or
    $_.active_restored_total -ne $_.expected_restored_total -or
    @($_.duplicate_restored_sourceids).Count -gt 0
  })

$result = [ordered]@{
  target_environment = $TargetEnvironmentUrl
  captured_at = ([datetime]::UtcNow.ToString("o"))
  applied_plan = $AppliedPlanPath
  branch_codes = @($branchCodes)
  active_nonredwood_invoice_sourceid_count = @($activeInvoiceRows).Count
  active_nonredwood_invoice_sourceids = @($activeInvoiceRows | ForEach-Object { Get-TextValue $_.qfu_sourceid })
  plan_check_count = $planChecks.Count
  failed_check_count = @($failedChecks).Count
  plan_checks = @($planChecks.ToArray())
}

Write-Utf8Json -Path $OutputPath -Object $result
Write-Output ($result | ConvertTo-Json -Depth 30)
