param(
  [string]$RepoRoot = "C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion",
  [string]$TargetEnvironmentUrl = "https://regionaloperationshub.crm.dynamics.com",
  [string]$Username = "smcfarlane@applied.com",
  [string]$SampleRoot = "example\vendor direct",
  [string]$AttachmentOutputRoot = "output\freight-samples\attachments",
  [string]$ManifestJson = "results\freight-sample-attachment-manifest.json",
  [string]$OutputJson = "results\freight-queue-seed-summary.json",
  [string[]]$BranchCodes = @("4171")
)

$ErrorActionPreference = "Stop"

. (Join-Path $RepoRoot "scripts\deploy-southern-alberta-pilot.ps1")
. (Join-Path $RepoRoot "scripts\deploy-freight-worklist.ps1")

$branchMap = @{
  "4171" = [pscustomobject]@{ BranchSlug = "4171-calgary"; RegionSlug = "southern-alberta" }
  "4172" = [pscustomobject]@{ BranchSlug = "4172-lethbridge"; RegionSlug = "southern-alberta" }
  "4173" = [pscustomobject]@{ BranchSlug = "4173-medicine-hat"; RegionSlug = "southern-alberta" }
}

function Get-FreightSourceFamilyFromFileName {
  param([string]$FileName)

  $name = [string]$FileName
  if ($name -match 'Loomis') { return "FREIGHT_LOOMIS_F15" }
  if ($name -match 'Purolator') { return "FREIGHT_PUROLATOR_F07" }
  if ($name -match 'UPS') { return "FREIGHT_UPS_F06" }
  if ($name -match 'Applied Canada') { return "FREIGHT_REDWOOD" }
  throw "Unsupported freight file name: $FileName"
}

function New-QueuedFreightRecord {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [string]$BranchCode,
    [string]$BranchSlug,
    [string]$RegionSlug,
    [string]$AttachmentPath
  )

  $fileName = Split-Path -Leaf $AttachmentPath
  $sourceFamily = Get-FreightSourceFamilyFromFileName -FileName $fileName
  $sourceId = "{0}|raw|{1}|{2}" -f $BranchCode, $sourceFamily, ([guid]::NewGuid().Guid)
  $base64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($AttachmentPath))

  New-CrmRecord -conn $Connection -EntityLogicalName "qfu_rawdocument" -Fields @{
    qfu_name = "$BranchCode $sourceFamily $fileName"
    qfu_sourceid = $sourceId
    qfu_branchcode = $BranchCode
    qfu_branchslug = $BranchSlug
    qfu_regionslug = $RegionSlug
    qfu_sourcefamily = $sourceFamily
    qfu_sourcefile = $fileName
    qfu_status = "queued"
    qfu_receivedon = [datetime]::UtcNow
    qfu_rawcontentbase64 = $base64
    qfu_processingnotes = "Queued from freight sample replay helper."
  } | Out-Null

  New-CrmRecord -conn $Connection -EntityLogicalName "qfu_ingestionbatch" -Fields @{
    qfu_name = "$BranchCode Freight Replay Import"
    qfu_sourceid = $sourceId
    qfu_branchcode = $BranchCode
    qfu_branchslug = $BranchSlug
    qfu_regionslug = $RegionSlug
    qfu_sourcefamily = $sourceFamily
    qfu_sourcefilename = $fileName
    qfu_status = "queued"
    qfu_insertedcount = 0
    qfu_updatedcount = 0
    qfu_startedon = [datetime]::UtcNow
    qfu_triggerflow = "Freight Sample Replay Helper"
    qfu_notes = "Queued from sample freight replay helper."
  } | Out-Null

  return [pscustomobject]@{
    branch_code = $BranchCode
    source_family = $sourceFamily
    source_id = $sourceId
    file_name = $fileName
  }
}

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
  throw "python is required to extract freight sample attachments."
}

$sourceRootPath = Join-Path $RepoRoot $SampleRoot
$attachmentOutputPath = Join-Path $RepoRoot $AttachmentOutputRoot
$manifestPath = Join-Path $RepoRoot $ManifestJson
$extractScript = Join-Path $RepoRoot "scripts\extract-freight-email-attachments.py"

& $python.Source $extractScript --source-root $sourceRootPath --output-root $attachmentOutputPath --output-json $manifestPath | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $manifestPath)) {
  throw "Freight attachment extraction failed."
}

$target = Connect-Org -Url $TargetEnvironmentUrl
Write-Host "Connected target: $($target.ConnectedOrgFriendlyName)"

Ensure-FreightSchema -Connection $target

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$results = New-Object System.Collections.Generic.List[object]
foreach ($emailItem in @($manifest.emails)) {
  if (@($BranchCodes) -notcontains [string]$emailItem.branch_code) {
    continue
  }

  $branch = $branchMap[[string]$emailItem.branch_code]
  if (-not $branch) {
    throw "Unsupported branch code in manifest: $($emailItem.branch_code)"
  }

  foreach ($attachmentPath in @($emailItem.attachments)) {
    $results.Add((New-QueuedFreightRecord -Connection $target -BranchCode $emailItem.branch_code -BranchSlug $branch.BranchSlug -RegionSlug $branch.RegionSlug -AttachmentPath $attachmentPath)) | Out-Null
  }
}

$result = [ordered]@{
  target_environment = $TargetEnvironmentUrl
  sample_root = $sourceRootPath
  attachment_output_root = $attachmentOutputPath
  queued = @($results.ToArray())
}

Write-Utf8Json -Path (Join-Path $RepoRoot $OutputJson) -Object $result
Write-Output ($result | ConvertTo-Json -Depth 6)
