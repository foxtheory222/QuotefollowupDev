param(
  [string]$TargetEnvironmentUrl = "https://regionaloperationshub.crm.dynamics.com",
  [string]$TargetEnvironmentName = "9f2e54c6-c349-e7e1-ac7c-010d3adf3c03",
  [string]$Username = "smcfarlane@applied.com",
  [string[]]$BranchCodes = @("4171", "4172", "4173"),
  [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

$flowCatalog = @(
  [pscustomobject]@{ BranchCode = "4171"; SourceFamily = "SP830CA"; DisplayName = "4171-QuoteFollowUp-Import-Staging" },
  [pscustomobject]@{ BranchCode = "4171"; SourceFamily = "ZBO"; DisplayName = "4171-BackOrder-Update-ZBO" },
  [pscustomobject]@{ BranchCode = "4171"; SourceFamily = "SA1300"; DisplayName = "4171-Budget-Update-SA1300" },
  [pscustomobject]@{ BranchCode = "4171"; SourceFamily = "GL060"; DisplayName = "4171-GL060-Inbox-Ingress" },
  [pscustomobject]@{ BranchCode = "4172"; SourceFamily = "SP830CA"; DisplayName = "4172-QuoteFollowUp-Import-Staging" },
  [pscustomobject]@{ BranchCode = "4172"; SourceFamily = "ZBO"; DisplayName = "4172-BackOrder-Update-ZBO" },
  [pscustomobject]@{ BranchCode = "4172"; SourceFamily = "SA1300"; DisplayName = "4172-Budget-Update-SA1300" },
  [pscustomobject]@{ BranchCode = "4172"; SourceFamily = "GL060"; DisplayName = "4172-GL060-Inbox-Ingress" },
  [pscustomobject]@{ BranchCode = "4173"; SourceFamily = "SP830CA"; DisplayName = "4173-QuoteFollowUp-Import-Staging" },
  [pscustomobject]@{ BranchCode = "4173"; SourceFamily = "ZBO"; DisplayName = "4173-BackOrder-Update-ZBO" },
  [pscustomobject]@{ BranchCode = "4173"; SourceFamily = "SA1300"; DisplayName = "4173-Budget-Update-SA1300" },
  [pscustomobject]@{ BranchCode = "4173"; SourceFamily = "GL060"; DisplayName = "4173-GL060-Inbox-Ingress" }
)

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

function Get-FlowAdminSnapshot {
  param(
    [string]$EnvironmentName,
    [string]$User
  )

  Import-Module Microsoft.PowerApps.Administration.PowerShell
  Add-PowerAppsAccount -Endpoint prod -Username $User | Out-Null

  return @(Get-AdminFlow -EnvironmentName $EnvironmentName)
}

function Get-TargetConnection {
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

function Get-BatchMoment {
  param([object]$Row)

  foreach ($fieldName in @("qfu_completedon", "qfu_startedon", "createdon")) {
    if (-not $Row -or -not $Row.PSObject.Properties[$fieldName]) {
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

function Get-LatestIngestionBatch {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$BranchCode,
    [string]$SourceFamily
  )

  $rows = @(
    (Get-CrmRecords -conn $Connection -EntityLogicalName "qfu_ingestionbatch" -FilterAttribute "qfu_branchcode" -FilterOperator eq -FilterValue $BranchCode -Fields @(
      "qfu_name",
      "qfu_branchcode",
      "qfu_sourcefamily",
      "qfu_triggerflow",
      "qfu_status",
      "qfu_sourcefilename",
      "qfu_startedon",
      "qfu_completedon",
      "createdon"
    ) -TopCount 5000).CrmRecords
  )

  return @(
    $rows |
      Where-Object { $_.qfu_sourcefamily -eq $SourceFamily } |
      Sort-Object { Get-BatchMoment -Row $_ } -Descending
  ) | Select-Object -First 1
}

$selectedFlows = @($flowCatalog | Where-Object { $_.BranchCode -in $BranchCodes })
$adminFlows = Get-FlowAdminSnapshot -EnvironmentName $TargetEnvironmentName -User $Username
$connection = Get-TargetConnection -Url $TargetEnvironmentUrl -User $Username

$rows = foreach ($flow in $selectedFlows) {
  $admin = $adminFlows | Where-Object { $_.DisplayName -eq $flow.DisplayName } | Select-Object -First 1
  $batch = Get-LatestIngestionBatch -Connection $connection -BranchCode $flow.BranchCode -SourceFamily $flow.SourceFamily

  [pscustomobject]@{
    branch_code = $flow.BranchCode
    source_family = $flow.SourceFamily
    flow_display_name = $flow.DisplayName
    flow_enabled = if ($admin) { [bool]$admin.Enabled } else { $false }
    flow_state = if ($admin) { $admin.State } else { "missing" }
    latest_batch_name = if ($batch) { $batch.qfu_name } else { $null }
    latest_batch_status = if ($batch) { $batch.qfu_status } else { $null }
    latest_batch_file = if ($batch) { $batch.qfu_sourcefilename } else { $null }
    latest_batch_trigger = if ($batch) { $batch.qfu_triggerflow } else { $null }
    latest_batch_startedon = if ($batch) { $batch.qfu_startedon } else { $null }
    latest_batch_completedon = if ($batch) { $batch.qfu_completedon } else { $null }
    latest_batch_createdon = if ($batch) { $batch.createdon } else { $null }
  }
}

$report = [pscustomobject]@{
  captured_at = (Get-Date).ToUniversalTime().ToString("o")
  environment_url = $TargetEnvironmentUrl
  environment_name = $TargetEnvironmentName
  branch_codes = @($BranchCodes)
  rows = @($rows)
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $OutputPath = Join-Path (Join-Path (Get-Location) "results") "southern-alberta-flow-health-$stamp.json"
}

Write-Utf8Json -Path $OutputPath -Object $report

$rows |
  Sort-Object branch_code, source_family |
  Select-Object branch_code, source_family, flow_enabled, latest_batch_createdon, latest_batch_status, latest_batch_file |
  Format-Table -AutoSize

Write-Host "OUTPUT_PATH=$OutputPath"
