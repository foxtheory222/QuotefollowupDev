param(
  [string]$TargetEnvironmentUrl = "https://regionaloperationshub.crm.dynamics.com",
  [string]$Username = "smcfarlane@applied.com",
  [string[]]$BranchCodes = @("4171", "4172", "4173"),
  [string]$JsonOutputPath = "results\live-current-state-audit-20260409.json",
  [string]$MarkdownOutputPath = "results\live-current-state-audit-20260409.md"
)

$ErrorActionPreference = "Stop"

Import-Module Microsoft.Xrm.Data.Powershell

function Get-TargetConnection {
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

function Ensure-ParentDirectory {
  param([string]$Path)

  $directory = Split-Path -Parent $Path
  if ($directory -and -not (Test-Path -LiteralPath $directory)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
  }
}

function Write-Utf8File {
  param(
    [string]$Path,
    [string]$Content
  )

  Ensure-ParentDirectory -Path $Path
  [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Get-BranchRecords {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$EntityLogicalName,
    [string]$BranchCode,
    [string[]]$Fields
  )

  return @(
    (Get-CrmRecords -conn $Connection -EntityLogicalName $EntityLogicalName -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $BranchCode -Fields $Fields -TopCount 5000).CrmRecords
  )
}

function Get-DuplicateGroups {
  param(
    [object[]]$Rows,
    [string]$PropertyName
  )

  return @(
    $Rows |
      Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.($PropertyName)) } |
      Group-Object -Property $PropertyName |
      Where-Object { $_.Count -gt 1 } |
      Sort-Object -Property Count, Name -Descending
  )
}

function Get-DateText {
  param([object]$Value)

  if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
    return $null
  }

  return ([datetime]$Value).ToString("yyyy-MM-dd HH:mm:ss")
}

function New-DuplicateSample {
  param(
    [object]$Group,
    [string]$EntityKind
  )

  $rows = @($Group.Group | Sort-Object modifiedon, createdon -Descending)
  $winner = @($rows | Select-Object -First 1)[0]
  $losers = if ($rows.Count -gt 1) { @($rows[1..($rows.Count - 1)]) } else { @() }

  return [pscustomobject]@{
    key = $Group.Name
    count = $Group.Count
    entity_kind = $EntityKind
    winner_record_id = switch ($EntityKind) {
      "quote" { $winner.qfu_quoteid }
      "backorder" { $winner.qfu_backorderid }
      "margin" { $winner.qfu_marginexceptionid }
      "delivery" { $winner.qfu_deliverynotpgiid }
      "batch" { $winner.qfu_ingestionbatchid }
      default { $null }
    }
    winner_createdon = Get-DateText $winner.createdon
    winner_modifiedon = Get-DateText $winner.modifiedon
    winner_importbatchid = if ($winner.PSObject.Properties["qfu_importbatchid"]) { $winner.qfu_importbatchid } else { $null }
    winner_status = if ($winner.PSObject.Properties["qfu_status"]) { $winner.qfu_status } else { $null }
    winner_snapshotdate = if ($winner.PSObject.Properties["qfu_snapshotdate"]) { $winner.qfu_snapshotdate } else { $null }
    loser_record_ids = @(
      $losers |
        ForEach-Object {
          switch ($EntityKind) {
            "quote" { $_.qfu_quoteid }
            "backorder" { $_.qfu_backorderid }
            "margin" { $_.qfu_marginexceptionid }
            "delivery" { $_.qfu_deliverynotpgiid }
            "batch" { $_.qfu_ingestionbatchid }
            default { $null }
          }
        } |
        Where-Object { $_ }
    )
  }
}

function Get-LatestFamilyRows {
  param([object[]]$Rows)

  $families = @("SP830CA", "ZBO", "SA1300", "SA1300-ABNORMALMARGIN", "SA1300-LATEORDER", "GL060")
  return @(
    foreach ($family in $families) {
      $latest = @($Rows | Where-Object { $_.qfu_sourcefamily -eq $family } | Sort-Object createdon -Descending | Select-Object -First 1)
      [pscustomobject]@{
        source_family = $family
        latest_status = if ($latest) { $latest[0].qfu_status } else { $null }
        latest_createdon = if ($latest) { Get-DateText $latest[0].createdon } else { $null }
        latest_startedon = if ($latest) { Get-DateText $latest[0].qfu_startedon } else { $null }
        latest_completedon = if ($latest) { Get-DateText $latest[0].qfu_completedon } else { $null }
        latest_file = if ($latest) { $latest[0].qfu_sourcefilename } else { $null }
        latest_trigger = if ($latest) { $latest[0].qfu_triggerflow } else { $null }
      }
    }
  )
}

function New-BranchAudit {
  param(
    [string]$BranchCode,
    [object[]]$Quotes,
    [object[]]$Backorders,
    [object[]]$Margins,
    [object[]]$DeliveryRows,
    [object[]]$Batches
  )

  $quoteDup = Get-DuplicateGroups -Rows $Quotes -PropertyName "qfu_sourceid"
  $backorderDup = Get-DuplicateGroups -Rows $Backorders -PropertyName "qfu_sourceid"
  $marginDup = Get-DuplicateGroups -Rows $Margins -PropertyName "qfu_sourceid"
  $deliveryDup = Get-DuplicateGroups -Rows $DeliveryRows -PropertyName "qfu_sourceid"
  $deliveryActive = @($DeliveryRows | Where-Object { -not $_.qfu_inactiveon })
  $deliveryInactive = @($DeliveryRows | Where-Object { $_.qfu_inactiveon })
  $deliveryActiveDup = Get-DuplicateGroups -Rows $deliveryActive -PropertyName "qfu_sourceid"
  $deliveryReappearanceGroups = @(
    $deliveryDup |
      Where-Object {
        $activeInGroup = @($_.Group | Where-Object { -not $_.qfu_inactiveon }).Count
        $inactiveInGroup = @($_.Group | Where-Object { $_.qfu_inactiveon }).Count
        $activeInGroup -eq 1 -and $inactiveInGroup -ge 1
      }
  )
  $batchDup = Get-DuplicateGroups -Rows $Batches -PropertyName "qfu_sourceid"
  $latestQuote = @($Quotes | Sort-Object createdon -Descending | Select-Object -First 1)[0]
  $latestBackorder = @($Backorders | Sort-Object createdon -Descending | Select-Object -First 1)[0]
  $latestMargin = @($Margins | Sort-Object createdon -Descending | Select-Object -First 1)[0]
  $latestDelivery = @($DeliveryRows | Sort-Object qfu_snapshotcapturedon, createdon -Descending | Select-Object -First 1)[0]
  $latestBatch = @($Batches | Sort-Object createdon -Descending | Select-Object -First 1)[0]
  $marginSnapshotGroups = @(
    $Margins |
      Group-Object qfu_snapshotdate |
      Sort-Object Name -Descending |
      Select-Object -First 10 |
      ForEach-Object {
        [pscustomobject]@{
          snapshotdate = $_.Name
          row_count = $_.Count
        }
      }
  )

  return [pscustomobject]@{
    branch_code = $BranchCode
    quotes = [pscustomobject]@{
      total_rows = @($Quotes).Count
      duplicate_groups = @($quoteDup).Count
      duplicate_rows = (@($quoteDup | Measure-Object -Property Count -Sum).Sum)
      latest_createdon = Get-DateText $latestQuote.createdon
      sample_groups = @($quoteDup | Select-Object -First 10 | ForEach-Object { New-DuplicateSample -Group $_ -EntityKind "quote" })
    }
    backorders = [pscustomobject]@{
      total_rows = @($Backorders).Count
      duplicate_groups = @($backorderDup).Count
      duplicate_rows = (@($backorderDup | Measure-Object -Property Count -Sum).Sum)
      latest_createdon = Get-DateText $latestBackorder.createdon
      sample_groups = @($backorderDup | Select-Object -First 10 | ForEach-Object { New-DuplicateSample -Group $_ -EntityKind "backorder" })
    }
    margins = [pscustomobject]@{
      total_rows = @($Margins).Count
      duplicate_groups = @($marginDup).Count
      duplicate_rows = (@($marginDup | Measure-Object -Property Count -Sum).Sum)
      latest_createdon = Get-DateText $latestMargin.createdon
      latest_snapshotdate = if ($latestMargin) { [string]$latestMargin.qfu_snapshotdate } else { $null }
      snapshot_groups = $marginSnapshotGroups
      sample_groups = @($marginDup | Select-Object -First 10 | ForEach-Object { New-DuplicateSample -Group $_ -EntityKind "margin" })
    }
    delivery_not_pgi = [pscustomobject]@{
      total_rows = @($DeliveryRows).Count
      active_rows = @($deliveryActive).Count
      inactive_rows = @($deliveryInactive).Count
      duplicate_groups = @($deliveryDup).Count
      duplicate_rows = (@($deliveryDup | Measure-Object -Property Count -Sum).Sum)
      active_duplicate_groups = @($deliveryActiveDup).Count
      active_duplicate_rows = (@($deliveryActiveDup | Measure-Object -Property Count -Sum).Sum)
      reappearance_history_groups = @($deliveryReappearanceGroups).Count
      latest_snapshotcapturedon = Get-DateText $latestDelivery.qfu_snapshotcapturedon
      sample_groups = @($deliveryDup | Select-Object -First 10 | ForEach-Object { New-DuplicateSample -Group $_ -EntityKind "delivery" })
    }
    ingestion_batches = [pscustomobject]@{
      total_rows = @($Batches).Count
      duplicate_groups = @($batchDup).Count
      duplicate_rows = (@($batchDup | Measure-Object -Property Count -Sum).Sum)
      latest_createdon = Get-DateText $latestBatch.createdon
      sample_groups = @($batchDup | Select-Object -First 10 | ForEach-Object { New-DuplicateSample -Group $_ -EntityKind "batch" })
      latest_by_family = Get-LatestFamilyRows -Rows $Batches
    }
  }
}

function New-MarkdownSummary {
  param(
    [object]$Report,
    [string]$JsonPath
  )

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("# Live Current-State Audit")
  $lines.Add("")
  $lines.Add("Captured at: $($Report.captured_at)")
  $lines.Add("Environment: $($Report.environment_url)")
  $lines.Add("JSON evidence: $JsonPath")
  $lines.Add("")

  foreach ($branch in @($Report.branches)) {
    $lines.Add("## Branch $($branch.branch_code)")
    $lines.Add("")
    $lines.Add("- Quotes: $($branch.quotes.total_rows) rows, $($branch.quotes.duplicate_groups) duplicate key groups, $($branch.quotes.duplicate_rows) duplicate rows")
    $lines.Add("- Backorders: $($branch.backorders.total_rows) rows, $($branch.backorders.duplicate_groups) duplicate key groups, $($branch.backorders.duplicate_rows) duplicate rows")
    $lines.Add("- Margin exceptions: $($branch.margins.total_rows) rows, $($branch.margins.duplicate_groups) duplicate key groups, $(if ($branch.margins.duplicate_rows) { $branch.margins.duplicate_rows } else { 0 }) duplicate rows")
    $lines.Add("- Delivery not PGI: $($branch.delivery_not_pgi.total_rows) rows, active $($branch.delivery_not_pgi.active_rows), inactive $($branch.delivery_not_pgi.inactive_rows), active duplicate groups $($branch.delivery_not_pgi.active_duplicate_groups), history reappearance groups $($branch.delivery_not_pgi.reappearance_history_groups)")
    $lines.Add("- Ingestion batches: $($branch.ingestion_batches.total_rows) rows, $($branch.ingestion_batches.duplicate_groups) duplicate source-id groups")
    $lines.Add("- Latest quote created: $($branch.quotes.latest_createdon)")
    $lines.Add("- Latest backorder created: $($branch.backorders.latest_createdon)")
    $lines.Add("- Latest margin snapshot: $($branch.margins.latest_snapshotdate)")
    $lines.Add("- Latest delivery snapshot captured: $($branch.delivery_not_pgi.latest_snapshotcapturedon)")
    $lines.Add("")
  }

  return ($lines -join [Environment]::NewLine)
}

$connection = Get-TargetConnection -Url $TargetEnvironmentUrl -User $Username
$branchAudits = @()

foreach ($branchCode in $BranchCodes) {
  $quotes = Get-BranchRecords -Connection $connection -EntityLogicalName "qfu_quote" -BranchCode $branchCode -Fields @(
    "qfu_quoteid",
    "qfu_sourceid",
    "qfu_importbatchid",
    "createdon",
    "modifiedon"
  )
  $backorders = Get-BranchRecords -Connection $connection -EntityLogicalName "qfu_backorder" -BranchCode $branchCode -Fields @(
    "qfu_backorderid",
    "qfu_sourceid",
    "qfu_importbatchid",
    "createdon",
    "modifiedon"
  )
  $margins = Get-BranchRecords -Connection $connection -EntityLogicalName "qfu_marginexception" -BranchCode $branchCode -Fields @(
    "qfu_marginexceptionid",
    "qfu_sourceid",
    "qfu_snapshotdate",
    "createdon",
    "modifiedon"
  )
  $deliveryRows = Get-BranchRecords -Connection $connection -EntityLogicalName "qfu_deliverynotpgi" -BranchCode $branchCode -Fields @(
    "qfu_deliverynotpgiid",
    "qfu_sourceid",
    "qfu_active",
    "qfu_inactiveon",
    "qfu_snapshotcapturedon",
    "qfu_importbatchid",
    "createdon",
    "modifiedon"
  )
  $batches = Get-BranchRecords -Connection $connection -EntityLogicalName "qfu_ingestionbatch" -BranchCode $branchCode -Fields @(
    "qfu_ingestionbatchid",
    "qfu_sourceid",
    "qfu_sourcefamily",
    "qfu_status",
    "qfu_sourcefilename",
    "qfu_triggerflow",
    "qfu_insertedcount",
    "qfu_updatedcount",
    "qfu_startedon",
    "qfu_completedon",
    "createdon",
    "modifiedon"
  )

  $branchAudits += New-BranchAudit -BranchCode $branchCode -Quotes $quotes -Backorders $backorders -Margins $margins -DeliveryRows $deliveryRows -Batches $batches
}

$report = [pscustomobject]@{
  captured_at = (Get-Date).ToUniversalTime().ToString("o")
  environment_url = $TargetEnvironmentUrl
  branch_codes = $BranchCodes
  branches = $branchAudits
}

$jsonPath = if ([System.IO.Path]::IsPathRooted($JsonOutputPath)) { $JsonOutputPath } else { Join-Path (Get-Location) $JsonOutputPath }
$markdownPath = if ([System.IO.Path]::IsPathRooted($MarkdownOutputPath)) { $MarkdownOutputPath } else { Join-Path (Get-Location) $MarkdownOutputPath }

Write-Utf8File -Path $jsonPath -Content ($report | ConvertTo-Json -Depth 20)
Write-Utf8File -Path $markdownPath -Content (New-MarkdownSummary -Report $report -JsonPath $jsonPath)

$report.branches |
  Select-Object branch_code,
    @{ Name = "quote_dup"; Expression = { $_.quotes.duplicate_groups } },
    @{ Name = "backorder_dup"; Expression = { $_.backorders.duplicate_groups } },
    @{ Name = "margin_dup"; Expression = { $_.margins.duplicate_groups } },
    @{ Name = "delivery_active_dup"; Expression = { $_.delivery_not_pgi.active_duplicate_groups } },
    @{ Name = "batch_dup"; Expression = { $_.ingestion_batches.duplicate_groups } } |
  Format-Table -AutoSize

Write-Host "JSON_OUTPUT_PATH=$jsonPath"
Write-Host "MARKDOWN_OUTPUT_PATH=$markdownPath"
