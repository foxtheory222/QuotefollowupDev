param(
  [string]$RepoRoot = "C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion",
  [string]$TargetEnvironmentUrl = "<URL>
  [string]$Username = "<EMAIL>",
  [string[]]$BranchCodes = @("4171", "4172", "4173"),
  [datetime]$SinceUtc = [datetime]::MinValue,
  [int]$TopCount = 10,
  [switch]$ValidationReplayOnly,
  [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

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

  $json = $Object | ConvertTo-Json -Depth 50
  [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Connect-Org {
  param(
    [string]$Url,
    [string]$User
  )

  Import-Module Microsoft.Xrm.Data.Powershell

  $conn = Connect-CrmOnline -ServerUrl $Url -ForceOAuth -Username $User
  if (-not $conn -or -not $conn.IsReady) {
    throw "Dataverse connection failed for $Url : $($conn.LastCrmError)"
  }

  return $conn
}

function Get-RowMoment {
  param([object]$Row)

  foreach ($fieldName in @("createdon", "modifiedon", "qfu_receivedon", "qfu_startedon", "qfu_completedon")) {
    if (-not $Row.PSObject.Properties[$fieldName]) {
      continue
    }

    $value = $Row.$fieldName
    if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) {
      continue
    }

    try {
      return [datetime]$value
    } catch {
    }
  }

  return [datetime]::MinValue
}

function Get-FilteredRows {
  param(
    [object[]]$Rows,
    [string]$BranchCode,
    [string]$SourceFamily,
    [datetime]$Since,
    [bool]$ValidationReplayFilter
  )

  return @(
    $Rows |
      Where-Object {
        $sourceFileValue = if ($_.PSObject.Properties["qfu_sourcefile"]) {
          [string]$_.qfu_sourcefile
        } elseif ($_.PSObject.Properties["qfu_sourcefilename"]) {
          [string]$_.qfu_sourcefilename
        } else {
          $null
        }

        [string]$_.qfu_branchcode -eq $BranchCode -and
        [string]$_.qfu_sourcefamily -eq $SourceFamily -and
        (
          -not $ValidationReplayFilter -or
          $sourceFileValue -eq ("{0}-GL060 Report - Profit Center - CanSC - Publish.pdf" -f $BranchCode)
        ) -and
        (Get-RowMoment -Row $_).ToUniversalTime() -ge $Since.ToUniversalTime()
      } |
      Sort-Object { Get-RowMoment -Row $_ } -Descending
  )
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $RepoRoot "results\gl060-mailbox-ingress-proof-$stamp.json"
}

$connection = Connect-Org -Url $TargetEnvironmentUrl -User $Username
$rawRows = @(
  (Get-CrmRecords -conn $connection -EntityLogicalName "qfu_rawdocument" -FilterAttribute "qfu_sourcefamily" -FilterOperator eq -FilterValue "GL060" -Fields @(
      "qfu_rawdocumentid",
      "qfu_sourceid",
      "qfu_branchcode",
      "qfu_sourcefamily",
      "qfu_sourcefile",
      "qfu_status",
      "qfu_receivedon",
      "qfu_processedon",
      "qfu_processingnotes",
      "createdon",
      "modifiedon"
    ) -TopCount 5000).CrmRecords
)
$batchRows = @(
  (Get-CrmRecords -conn $connection -EntityLogicalName "qfu_ingestionbatch" -FilterAttribute "qfu_sourcefamily" -FilterOperator eq -FilterValue "GL060" -Fields @(
      "qfu_ingestionbatchid",
      "qfu_sourceid",
      "qfu_branchcode",
      "qfu_sourcefamily",
      "qfu_sourcefilename",
      "qfu_status",
      "qfu_startedon",
      "qfu_completedon",
      "qfu_notes",
      "qfu_triggerflow",
      "createdon",
      "modifiedon"
    ) -TopCount 5000).CrmRecords
)

$rows = foreach ($branchCode in @($BranchCodes | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
  $branchRaw = @(Get-FilteredRows -Rows $rawRows -BranchCode $branchCode -SourceFamily "GL060" -Since $SinceUtc -ValidationReplayFilter ([bool]$ValidationReplayOnly))
  $branchBatches = @(Get-FilteredRows -Rows $batchRows -BranchCode $branchCode -SourceFamily "GL060" -Since $SinceUtc -ValidationReplayFilter ([bool]$ValidationReplayOnly))

  [pscustomobject]@{
    branch_code = $branchCode
    since_utc = $SinceUtc.ToUniversalTime().ToString("o")
    rawdocument_count_since = $branchRaw.Count
    ingestionbatch_count_since = $branchBatches.Count
    rawdocuments = @(
      $branchRaw |
        Select-Object -First $TopCount qfu_rawdocumentid, qfu_sourceid, qfu_sourcefile, qfu_status, qfu_receivedon, qfu_processedon, createdon, modifiedon, qfu_processingnotes
    )
    ingestionbatches = @(
      $branchBatches |
        Select-Object -First $TopCount qfu_ingestionbatchid, qfu_sourceid, qfu_sourcefilename, qfu_status, qfu_startedon, qfu_completedon, createdon, modifiedon, qfu_triggerflow, qfu_notes
    )
  }
}

$report = [pscustomobject]@{
  captured_at = (Get-Date).ToUniversalTime().ToString("o")
  target_environment_url = $TargetEnvironmentUrl
  branch_codes = @($BranchCodes)
  since_utc = $SinceUtc.ToUniversalTime().ToString("o")
  validation_replay_only = [bool]$ValidationReplayOnly
  rows = @($rows)
}

Write-Utf8Json -Path $OutputPath -Object $report

$report.rows |
  Select-Object branch_code, rawdocument_count_since, ingestionbatch_count_since |
  Format-Table -AutoSize

Write-Host "OUTPUT_PATH=$OutputPath"
