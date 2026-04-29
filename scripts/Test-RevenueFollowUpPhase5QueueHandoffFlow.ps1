param(
    [string]$EnvironmentUrl = 'https://orga632edd5.crm3.dynamics.com',
    [string]$SourceExternalKey = 'PHASE5_COMPLETION_UI_HANDOFF_TEST_20260428',
    [string]$OutputPath = 'results\phase5-final-fix-queue-handoff-flow-validation.json',
    [int]$WaitSeconds = 75
)

$ErrorActionPreference = 'Stop'

$roleValues = @{
    TSR  = 985020000
    CSSR = 985020001
}

$actionTypeValues = @{
    AssignmentReassignment = 985010012
}

function Get-AccessToken {
    $tokenObject = Get-AzAccessToken -ResourceUrl "$EnvironmentUrl/"
    $token = $tokenObject.Token
    if ($token -is [System.Security.SecureString]) {
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($token)
        try {
            $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        }
        finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
    return $token
}

$headers = @{
    Authorization      = "Bearer $(Get-AccessToken)"
    Accept             = 'application/json'
    'Content-Type'     = 'application/json; charset=utf-8'
    'OData-MaxVersion' = '4.0'
    'OData-Version'    = '4.0'
}
$readHeaders = $headers.Clone()
$readHeaders.Remove('Content-Type')

function Invoke-DvGet {
    param([string]$RelativeUrl)
    Invoke-RestMethod -Method Get -Uri "$EnvironmentUrl/api/data/v9.2/$RelativeUrl" -Headers $readHeaders
}

function Invoke-DvPatch {
    param([string]$RelativeUrl, [object]$Body)
    Invoke-RestMethod -Method Patch -Uri "$EnvironmentUrl/api/data/v9.2/$RelativeUrl" -Headers $headers -Body ($Body | ConvertTo-Json -Depth 20)
}

function Invoke-DvPost {
    param([string]$RelativeUrl, [object]$Body)
    Invoke-RestMethod -Method Post -Uri "$EnvironmentUrl/api/data/v9.2/$RelativeUrl" -Headers $headers -Body ($Body | ConvertTo-Json -Depth 20)
}

function Get-AllRows {
    param([string]$RelativeUrl)
    $rows = @()
    $url = "$EnvironmentUrl/api/data/v9.2/$RelativeUrl"
    do {
        $response = Invoke-RestMethod -Method Get -Uri $url -Headers $readHeaders
        $rows += @($response.value)
        $url = $response.'@odata.nextLink'
    } while ($url)
    return $rows
}

function Escape-ODataString {
    param([string]$Value)
    return $Value.Replace("'", "''")
}

function Get-WorkItem {
    param([string]$Id)
    Invoke-DvGet "qfu_workitems($Id)?`$select=qfu_workitemid,qfu_workitemnumber,qfu_sourceexternalkey,qfu_sourcedocumentnumber,qfu_completedattempts,qfu_lastfollowedupon,qfu_lastactionon,qfu_currentqueuerole,qfu_currentqueueroletext,qfu_currentqueueownerstaffkey,qfu_currentqueueownername,qfu_queuehandoffcount,qfu_queuehandoffreason,_qfu_currentqueueownerstaff_value,_qfu_tsrstaff_value,_qfu_cssrstaff_value"
}

function Get-Staff {
    param([string]$Id)
    Invoke-DvGet "qfu_staffs($Id)?`$select=qfu_staffid,qfu_name,qfu_staffnumber"
}

function Set-QueueDirect {
    param(
        [object]$WorkItem,
        [string]$Role,
        [string]$Reason
    )

    $targetId = if ($Role -eq 'TSR') { $WorkItem.'_qfu_tsrstaff_value' } else { $WorkItem.'_qfu_cssrstaff_value' }
    if (-not $targetId) {
        throw "Controlled test item is missing $Role staff."
    }
    $staff = Get-Staff -Id $targetId
    Invoke-DvPatch "qfu_workitems($($WorkItem.qfu_workitemid))" @{
        'qfu_CurrentQueueOwnerStaff@odata.bind' = "/qfu_staffs($targetId)"
        qfu_currentqueuerole                    = $roleValues[$Role]
        qfu_currentqueueroletext                = $Role
        qfu_currentqueueownerstaffkey           = if ($staff.qfu_staffnumber) { [string]$staff.qfu_staffnumber } else { [string]$staff.qfu_staffid }
        qfu_currentqueueownername               = $staff.qfu_name
        qfu_queueassignedon                     = (Get-Date).ToUniversalTime().ToString('o')
        qfu_queuehandoffreason                  = $Reason
    } | Out-Null
}

function New-HandoffAction {
    param(
        [object]$WorkItem,
        [string]$TargetRole,
        [string]$Marker
    )

    Invoke-DvPost 'qfu_workitemactions' @{
        qfu_name = "Queue Handoff - $($WorkItem.qfu_workitemnumber)"
        'qfu_WorkItem@odata.bind' = "/qfu_workitems($($WorkItem.qfu_workitemid))"
        qfu_actiontype = $actionTypeValues.AssignmentReassignment
        qfu_actionon = (Get-Date).ToUniversalTime().ToString('o')
        qfu_countsasattempt = $false
        qfu_notes = "$Marker routed to $TargetRole from Phase 5 final fix validation."
        qfu_outcome = $TargetRole
    } | Out-Null
}

$escapedKey = Escape-ODataString $SourceExternalKey
$found = Get-AllRows "qfu_workitems?`$select=qfu_workitemid&`$filter=qfu_sourceexternalkey eq '$escapedKey'&`$top=1" | Select-Object -First 1
if (-not $found) {
    throw "Controlled test work item '$SourceExternalKey' was not found."
}

$initial = Get-WorkItem -Id $found.qfu_workitemid
$beforeAttempts = if ($null -ne $initial.qfu_completedattempts) { [int]$initial.qfu_completedattempts } else { 0 }
$beforeLastFollowed = $initial.qfu_lastfollowedupon

Set-QueueDirect -WorkItem $initial -Role CSSR -Reason 'Reset to CSSR before Phase 5 final fix flow validation.'
$resetCssr = Get-WorkItem -Id $initial.qfu_workitemid

$tsrMarker = "PHASE5_FINAL_FLOW_HANDOFF_TSR_$(Get-Date -Format yyyyMMddHHmmss)"
New-HandoffAction -WorkItem $resetCssr -TargetRole TSR -Marker $tsrMarker
Start-Sleep -Seconds $WaitSeconds
$afterTsr = Get-WorkItem -Id $initial.qfu_workitemid

$cssrMarker = "PHASE5_FINAL_FLOW_HANDOFF_CSSR_$(Get-Date -Format yyyyMMddHHmmss)"
New-HandoffAction -WorkItem $afterTsr -TargetRole CSSR -Marker $cssrMarker
Start-Sleep -Seconds $WaitSeconds
$afterCssr = Get-WorkItem -Id $initial.qfu_workitemid

$actions = Get-AllRows "qfu_workitemactions?`$select=qfu_workitemactionid,qfu_countsasattempt,qfu_actiontype,qfu_notes,qfu_outcome,qfu_actionon&`$filter=_qfu_workitem_value eq $($initial.qfu_workitemid) and statecode eq 0&`$orderby=qfu_actionon desc"
$flowActions = @($actions | Where-Object { $_.qfu_notes -like "*PHASE5_FINAL_FLOW_HANDOFF*" })

$result = [ordered]@{
    environmentUrl = $EnvironmentUrl
    timestamp = (Get-Date).ToString('o')
    sourceExternalKey = $SourceExternalKey
    workItemId = $initial.qfu_workitemid
    before = $initial
    resetCssr = $resetCssr
    afterTsr = $afterTsr
    afterCssr = $afterCssr
    markers = [ordered]@{
        tsr = $tsrMarker
        cssr = $cssrMarker
    }
    handoffActionRowsCreated = @($flowActions).Count
    allHandoffActionsNonAttempt = -not (@($flowActions) | Where-Object { $_.qfu_countsasattempt -eq $true })
    tsrOwnerMatched = ($afterTsr.'_qfu_currentqueueownerstaff_value' -eq $afterTsr.'_qfu_tsrstaff_value') -and ([int]$afterTsr.qfu_currentqueuerole -eq $roleValues.TSR) -and ($afterTsr.qfu_currentqueueroletext -eq 'TSR')
    cssrOwnerMatched = ($afterCssr.'_qfu_currentqueueownerstaff_value' -eq $afterCssr.'_qfu_cssrstaff_value') -and ([int]$afterCssr.qfu_currentqueuerole -eq $roleValues.CSSR) -and ($afterCssr.qfu_currentqueueroletext -eq 'CSSR')
    ownerStaffKeyPopulated = -not [string]::IsNullOrWhiteSpace($afterCssr.qfu_currentqueueownerstaffkey)
    completedAttemptsPreserved = ([int]$afterCssr.qfu_completedattempts -eq $beforeAttempts)
    lastFollowedUpPreserved = ([string]$afterCssr.qfu_lastfollowedupon -eq [string]$beforeLastFollowed)
    lastActionUpdatedOrConsistent = ($null -ne $afterCssr.qfu_lastactionon)
    validationPassed = $false
}

$result.validationPassed = (
    $result.handoffActionRowsCreated -ge 2 -and
    $result.allHandoffActionsNonAttempt -and
    $result.tsrOwnerMatched -and
    $result.cssrOwnerMatched -and
    $result.ownerStaffKeyPopulated -and
    $result.completedAttemptsPreserved -and
    $result.lastFollowedUpPreserved
)

$directory = Split-Path -Parent $OutputPath
if ($directory) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}
$result | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
$result | ConvertTo-Json -Depth 30
