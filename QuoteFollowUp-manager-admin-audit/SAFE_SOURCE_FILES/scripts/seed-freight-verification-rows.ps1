param(
  [string]$RepoRoot = "C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion",
  [string]$TargetEnvironmentUrl = "<URL>
  [string]$Username = "<EMAIL>",
  [string]$RunTag = "",
  [string]$OutputJson = "results\freight-verification-seed.json"
)

$ErrorActionPreference = "Stop"

. (Join-Path $RepoRoot "scripts\deploy-southern-alberta-pilot.ps1")
. (Join-Path $RepoRoot "scripts\deploy-freight-worklist.ps1")

function Reset-FreightVerificationRow {
  param(
    [Microsoft.Xrm.Tooling.Connector.CrmServiceClient]$Connection,
    [hashtable]$Fields
  )

  $sourceId = [string]$Fields.qfu_sourceid
  $existingRows = @((Get-CrmRecords -conn $Connection -EntityLogicalName "qfu_freightworkitem" -FilterAttribute "qfu_sourceid" -FilterOperator eq -FilterValue $sourceId -Fields @(
        "qfu_freightworkitemid",
        "qfu_sourceid"
      ) -TopCount 10).CrmRecords)

  foreach ($existing in $existingRows) {
    Remove-CrmRecord -conn $Connection -EntityLogicalName "qfu_freightworkitem" -Id $existing.qfu_freightworkitemid | Out-Null
  }

  $newId = New-CrmRecord -conn $Connection -EntityLogicalName "qfu_freightworkitem" -Fields $Fields
  return [pscustomobject]@{
    source_id = $sourceId
    record_id = [string]$newId
    result = if ($existingRows.Count -gt 0) { "recreated" } else { "created" }
    reference = [string]$Fields.qfu_reference
    status = [string]$Fields.qfu_status
    archived = [bool]$Fields.qfu_isarchived
  }
}

$target = Connect-Org -Url $TargetEnvironmentUrl
Write-Host "Connected target: $($target.ConnectedOrgFriendlyName)"

Ensure-FreightSchema -Connection $target

$now = [datetime]::UtcNow
$today = $now.Date
$old = $today.AddDays(-75)
$batchId = "VERIFICATION-20260410"
$normalizedRunTag = [string]$RunTag
if (-not $normalizedRunTag) {
  $normalizedRunTag = ""
}

function Add-RunTag {
  param(
    [string]$Value
  )

  if (-not $normalizedRunTag) {
    return $Value
  }

  return "$Value-$normalizedRunTag"
}

$portalSourceId = if ($normalizedRunTag) { "4171|freight-test|portal|$normalizedRunTag" } else { "4171|freight-test|portal" }
$archiveSourceId = if ($normalizedRunTag) { "4171|freight-test|archive|$normalizedRunTag" } else { "4171|freight-test|archive" }
$portalReference = Add-RunTag -Value "QFU-FREIGHT-PORTAL-VERIFY"
$archiveReference = Add-RunTag -Value "QFU-FREIGHT-ARCHIVE-VERIFY"

$portalRow = @{
  qfu_name = "4171 Freight Portal Verification Row"
  qfu_sourceid = $portalSourceId
  qfu_branchcode = "4171"
  qfu_branchslug = "4171-calgary"
  qfu_regionslug = "southern-alberta"
  qfu_sourcefamily = "FREIGHT_TEST"
  qfu_sourcefilename = "verification-portal-row.json"
  qfu_sourcecarrier = "Verification Carrier"
  qfu_importbatchid = $batchId
  qfu_rawrowjson = ('{"kind":"portal-verification","marker":"' + $portalReference + '"}')
  qfu_trackingnumber = (Add-RunTag -Value "QFU-TRACK-4171-PORTAL")
  qfu_pronumber = (Add-RunTag -Value "QFU-PRO-4171-PORTAL")
  qfu_invoicenumber = (Add-RunTag -Value "QFU-INV-4171-PORTAL")
  qfu_controlnumber = (Add-RunTag -Value "QFU-CTRL-4171-PORTAL")
  qfu_reference = $portalReference
  qfu_shipdate = $today
  qfu_invoicedate = $today
  qfu_closedate = $null
  qfu_billtype = "PRE"
  qfu_service = "Verification Express"
  qfu_servicecode = "QFU"
  qfu_sender = "Applied Industrial Technologies Calgary Verification Desk"
  qfu_destination = "Verification Destination Queue"
  qfu_zone = "V1"
  qfu_actualweight = [decimal]12.50
  qfu_billedweight = [decimal]12.50
  qfu_quantity = [decimal]1
  qfu_totalamount = [decimal]321.09
  qfu_freightamount = [decimal]300.00
  qfu_fuelamount = [decimal]12.09
  qfu_taxamount = [decimal]9.00
  qfu_gstamount = [decimal]9.00
  qfu_hstamount = [decimal]0
  qfu_qstamount = [decimal]0
  qfu_accessorialamount = [decimal]0
  qfu_accessorialpresent = $false
  qfu_unrealizedsavings = [decimal]0
  qfu_chargebreakdowntext = "Verification row for portal mutation tests."
  qfu_direction = "Outbound"
  qfu_status = "Open"
  qfu_priorityband = "High Value"
  qfu_ownername = ""
  qfu_owneridentifier = ""
  qfu_claimedon = $null
  qfu_comment = ""
  qfu_commentupdatedon = $null
  qfu_commentupdatedbyname = ""
  qfu_lastactivityon = $now
  qfu_isarchived = $false
  qfu_archivedon = $null
  qfu_lastseenon = $now
}

$archiveRow = @{
  qfu_name = "4171 Freight Archive Verification Row"
  qfu_sourceid = $archiveSourceId
  qfu_branchcode = "4171"
  qfu_branchslug = "4171-calgary"
  qfu_regionslug = "southern-alberta"
  qfu_sourcefamily = "FREIGHT_TEST"
  qfu_sourcefilename = "verification-archive-row.json"
  qfu_sourcecarrier = "Verification Carrier"
  qfu_importbatchid = $batchId
  qfu_rawrowjson = ('{"kind":"archive-verification","marker":"' + $archiveReference + '"}')
  qfu_trackingnumber = (Add-RunTag -Value "QFU-TRACK-4171-ARCHIVE")
  qfu_pronumber = (Add-RunTag -Value "QFU-PRO-4171-ARCHIVE")
  qfu_invoicenumber = (Add-RunTag -Value "QFU-INV-4171-ARCHIVE")
  qfu_controlnumber = (Add-RunTag -Value "QFU-CTRL-4171-ARCHIVE")
  qfu_reference = $archiveReference
  qfu_shipdate = $old
  qfu_invoicedate = $old
  qfu_closedate = $old
  qfu_billtype = "COL"
  qfu_service = "Verification Ground"
  qfu_servicecode = "QFU"
  qfu_sender = "Applied Industrial Technologies Calgary Verification Desk"
  qfu_destination = "Verification Archive Queue"
  qfu_zone = "V2"
  qfu_actualweight = [decimal]5
  qfu_billedweight = [decimal]5
  qfu_quantity = [decimal]1
  qfu_totalamount = [decimal]45.67
  qfu_freightamount = [decimal]40.00
  qfu_fuelamount = [decimal]2.67
  qfu_taxamount = [decimal]3.00
  qfu_gstamount = [decimal]3.00
  qfu_hstamount = [decimal]0
  qfu_qstamount = [decimal]0
  qfu_accessorialamount = [decimal]0
  qfu_accessorialpresent = $false
  qfu_unrealizedsavings = [decimal]0
  qfu_chargebreakdowntext = "Verification row for scheduled archive tests."
  qfu_direction = "Inbound"
  qfu_status = "Closed"
  qfu_priorityband = "Standard"
  qfu_ownername = ""
  qfu_owneridentifier = ""
  qfu_claimedon = $null
  qfu_comment = "Archive verification row"
  qfu_commentupdatedon = $old
  qfu_commentupdatedbyname = "Codex"
  qfu_lastactivityon = $old
  qfu_isarchived = $false
  qfu_archivedon = $null
  qfu_lastseenon = $old
}

$results = @(
  (Reset-FreightVerificationRow -Connection $target -Fields $portalRow)
  (Reset-FreightVerificationRow -Connection $target -Fields $archiveRow)
)

$result = [ordered]@{
  target_environment = $TargetEnvironmentUrl
  seeded_on_utc = $now.ToString("o")
  run_tag = $normalizedRunTag
  portal_source_id = $portalSourceId
  archive_source_id = $archiveSourceId
  portal_reference = $portalReference
  archive_reference = $archiveReference
  records = $results
  portal_url = ("<URL> + [uri]::EscapeDataString($portalReference))
  archive_url = ("<URL> + [uri]::EscapeDataString($archiveReference))
}

Write-Utf8Json -Path (Join-Path $RepoRoot $OutputJson) -Object $result
Write-Output ($result | ConvertTo-Json -Depth 6)
