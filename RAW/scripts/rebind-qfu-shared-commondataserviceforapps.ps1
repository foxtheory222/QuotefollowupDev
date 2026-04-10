param(
  [string]$TargetEnvironmentUrl = "https://regionaloperationshub.crm.dynamics.com",
  [string]$Username = "smcfarlane@applied.com",
  [string]$TargetConnectionId,
  [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($TargetConnectionId)) {
  throw "TargetConnectionId is required."
}

Import-Module Microsoft.Xrm.Data.Powershell

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

  $json = $Object | ConvertTo-Json -Depth 10
  [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

$conn = Connect-CrmOnline -ServerUrl $TargetEnvironmentUrl -ForceOAuth -Username $Username
if (-not $conn -or -not $conn.IsReady) {
  throw "Dataverse connection failed for $TargetEnvironmentUrl : $($conn.LastCrmError)"
}

$record = @(
  (Get-CrmRecords -conn $conn -EntityLogicalName "connectionreference" -FilterAttribute "connectionreferencelogicalname" -FilterOperator eq -FilterValue "qfu_shared_commondataserviceforapps" -Fields @(
    "connectionreferenceid",
    "connectionreferencelogicalname",
    "connectionid",
    "connectorid",
    "modifiedon"
  ) -TopCount 5).CrmRecords
) | Select-Object -First 1

if (-not $record) {
  throw "Connection reference qfu_shared_commondataserviceforapps not found."
}

$beforeConnectionId = [string]$record.connectionid

if ($beforeConnectionId -ne $TargetConnectionId) {
  Set-CrmRecord -conn $conn -EntityLogicalName "connectionreference" -Id $record.connectionreferenceid -Fields @{ connectionid = $TargetConnectionId } | Out-Null
}

$refreshed = Get-CrmRecord -conn $conn -EntityLogicalName "connectionreference" -Id $record.connectionreferenceid -Fields connectionreferencelogicalname, connectionid, connectorid, modifiedon

$report = [pscustomobject]@{
  captured_at = (Get-Date).ToUniversalTime().ToString("o")
  target_environment_url = $TargetEnvironmentUrl
  connection_reference = "qfu_shared_commondataserviceforapps"
  before_connection_id = $beforeConnectionId
  after_connection_id = [string]$refreshed.connectionid
  modified_on = $refreshed.modifiedon
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $OutputPath = Join-Path (Join-Path (Get-Location) "results") "qfu-shared-commondataserviceforapps-rebind-$stamp.json"
}

Write-Utf8Json -Path $OutputPath -Object $report

$report | Format-List
Write-Host "OUTPUT_PATH=$OutputPath"
