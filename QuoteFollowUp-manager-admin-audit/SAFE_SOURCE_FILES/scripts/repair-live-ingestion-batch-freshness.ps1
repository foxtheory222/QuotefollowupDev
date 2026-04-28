param(
  [string]$TargetEnvironmentUrl = "<URL>
  [string]$Username = "<EMAIL>",
  [Parameter(Mandatory = $true)][string]$BranchCode,
  [Parameter(Mandatory = $true)][string]$SourceFamily,
  [Parameter(Mandatory = $true)][string]$SourceId,
  [Parameter(Mandatory = $true)][datetime]$StartedOnUtc,
  [Parameter(Mandatory = $true)][datetime]$CompletedOnUtc,
  [Parameter(Mandatory = $true)][string]$TriggerFlow,
  [string]$Status = "ready",
  [string]$Notes = "",
  [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

function Ensure-Directory {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
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

Import-Module Microsoft.Xrm.Data.Powershell

$conn = Connect-CrmOnline -ServerUrl $TargetEnvironmentUrl -ForceOAuth -Username $Username
if (-not $conn -or -not $conn.IsReady) {
  throw "Dataverse connection failed for $TargetEnvironmentUrl : $($conn.LastCrmError)"
}

$rows = @(
  (Get-CrmRecords -conn $conn -EntityLogicalName "qfu_ingestionbatch" -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $BranchCode -Fields @(
    "qfu_ingestionbatchid",
    "qfu_sourceid",
    "qfu_sourcefamily",
    "qfu_status",
    "qfu_triggerflow",
    "qfu_startedon",
    "qfu_completedon",
    "createdon"
  ) -TopCount 5000).CrmRecords
)

$targetRows = @(
  $rows |
    Where-Object {
      [string]$_.qfu_sourcefamily -eq $SourceFamily -and
      [string]$_.qfu_sourceid -eq $SourceId
    } |
    Sort-Object createdon
)

if ($targetRows.Count -eq 0) {
  throw "No qfu_ingestionbatch rows found for branch=$BranchCode sourcefamily=$SourceFamily sourceid=$SourceId"
}

$updatedRows = New-Object System.Collections.Generic.List[object]

foreach ($row in $targetRows) {
  $fields = @{
    qfu_status = $Status
    qfu_triggerflow = $TriggerFlow
    qfu_startedon = $StartedOnUtc.ToUniversalTime()
    qfu_completedon = $CompletedOnUtc.ToUniversalTime()
  }

  if (-not [string]::IsNullOrWhiteSpace($Notes)) {
    $fields.qfu_notes = $Notes
  }

  Set-CrmRecord -conn $conn -EntityLogicalName "qfu_ingestionbatch" -Id $row.qfu_ingestionbatchid -Fields $fields | Out-Null

  $updatedRows.Add([pscustomobject]@{
    qfu_ingestionbatchid = $row.qfu_ingestionbatchid
    sourceid = $SourceId
    sourcefamily = $SourceFamily
    status = $Status
    triggerflow = $TriggerFlow
    startedon = $StartedOnUtc.ToUniversalTime().ToString("o")
    completedon = $CompletedOnUtc.ToUniversalTime().ToString("o")
  }) | Out-Null
}

$report = [pscustomobject]@{
  captured_at = (Get-Date).ToUniversalTime().ToString("o")
  branch_code = $BranchCode
  source_family = $SourceFamily
  source_id = $SourceId
  status = $Status
  trigger_flow = $TriggerFlow
  started_on_utc = $StartedOnUtc.ToUniversalTime().ToString("o")
  completed_on_utc = $CompletedOnUtc.ToUniversalTime().ToString("o")
  updated_rows = @($updatedRows.ToArray())
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $OutputPath = Join-Path (Join-Path (Get-Location) "results") "live-ingestion-batch-freshness-repair-$stamp.json"
}

Write-Utf8Json -Path $OutputPath -Object $report

$report.updated_rows |
  Select-Object qfu_ingestionbatchid, sourcefamily, startedon, completedon |
  Format-Table -AutoSize

Write-Host "OUTPUT_PATH=$OutputPath"
