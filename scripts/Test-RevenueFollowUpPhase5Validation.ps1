param(
    [string]$EnvironmentUrl = 'https://orga632edd5.crm3.dynamics.com',
    [string]$BranchCode = '4171',
    [string]$OutputPath = 'results\phase5-validation-20260428.json',
    [switch]$RunControlledHandoff
)

$ErrorActionPreference = 'Stop'

$roleValues = @{
    TSR        = 985020000
    CSSR       = 985020001
    Unassigned = 985020005
}

$actionTypeValues = @{
    AssignmentReassignment = 985010012
}

$workTypeValues = @{
    Quote     = 985010000
    Backorder = 985010001
}

$statusValues = @{
    ClosedWon  = 985010008
    ClosedLost = 985010009
    Cancelled  = 985010010
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

function Get-Count {
    param([string]$RelativeUrl)
    $separator = if ($RelativeUrl.Contains('?')) { '&' } else { '?' }
    $response = Invoke-DvGet "$RelativeUrl$separator`$count=true&`$top=0"
    return [int]$response.'@odata.count'
}

function Escape-ODataString {
    param([string]$Value)
    return $Value.Replace("'", "''")
}

$solution = Get-AllRows "solutions?`$select=solutionid,uniquename,friendlyname&`$filter=uniquename eq 'qfu_revenuefollowupworkbench'" | Select-Object -First 1
$app = Get-AllRows "appmodules?`$select=appmoduleid,name,uniquename&`$filter=uniquename eq 'qfu_RevenueFollowUpWorkbench'" | Select-Object -First 1
$canvasApps = Get-AllRows "canvasapps?`$select=canvasappid,name,displayname&`$filter=name eq 'qfu_mywork_6e7ed'"

$attributes = Invoke-DvGet "EntityDefinitions(LogicalName='qfu_workitem')/Attributes?`$select=LogicalName"
$queueFields = @(
    'qfu_currentqueueownerstaff',
    'qfu_currentqueuerole',
    'qfu_currentqueueroletext',
    'qfu_currentqueueownerstaffkey',
    'qfu_currentqueueownername',
    'qfu_queueassignedon',
    'qfu_queueassignedby',
    'qfu_queuehandoffreason',
    'qfu_queuehandoffcount'
)
$fieldNames = @($attributes.value | ForEach-Object { $_.LogicalName })
$rollupFlow = Get-AllRows "workflows?`$select=workflowid,name,statecode,statuscode,category,type,createdon,modifiedon&`$filter=name eq 'QFU Work Item Action Rollup - Phase 5'" | Select-Object -First 1

$activeWorkItems = Get-AllRows "qfu_workitems?`$select=qfu_workitemid,qfu_sourceexternalkey,qfu_worktype,qfu_status,qfu_assignmentstatus,qfu_completedattempts,qfu_requiredattempts,qfu_currentqueuerole,_qfu_currentqueueownerstaff_value,_qfu_tsrstaff_value,_qfu_cssrstaff_value,qfu_queuehandoffcount,qfu_stickynote,qfu_stickynoteupdatedon&`$filter=statecode eq 0"
$activeActions = Get-AllRows "qfu_workitemactions?`$select=qfu_workitemactionid,qfu_countsasattempt,qfu_actiontype&`$filter=statecode eq 0"
$activeExceptions = Get-AllRows "qfu_assignmentexceptions?`$select=qfu_assignmentexceptionid,qfu_sourceexternalkey,qfu_exceptiontype,qfu_sourcefield,qfu_normalizedvalue&`$filter=statecode eq 0"
$activeAlerts = Get-AllRows "qfu_alertlogs?`$select=qfu_alertlogid,qfu_status&`$filter=statecode eq 0"

$duplicateWorkItemKeys = @(
    $activeWorkItems |
        Where-Object { $_.qfu_sourceexternalkey } |
        Group-Object qfu_worktype,qfu_sourceexternalkey |
        Where-Object Count -gt 1 |
        ForEach-Object { [pscustomobject]@{ key = $_.Name; count = $_.Count } }
)

$duplicateExceptionKeys = @(
    $activeExceptions |
        Where-Object { $_.qfu_sourceexternalkey } |
        Group-Object qfu_sourceexternalkey,qfu_exceptiontype,qfu_sourcefield,qfu_normalizedvalue |
        Where-Object Count -gt 1 |
        ForEach-Object { [pscustomobject]@{ key = $_.Name; count = $_.Count } }
)

$handoffResult = [ordered]@{
    run = [bool]$RunControlledHandoff
    itemSelected = $false
    sourceExternalKey = $null
    sourceDocumentNumber = $null
    beforeOwnerRole = $null
    afterCssrOwnerMatched = $false
    afterTsrOwnerMatched = $false
    actionLogsCreated = 0
    countsAsAttemptFalse = $false
    completedAttemptsPreserved = $false
    alertsSentAfter = 0
    error = $null
}

if ($RunControlledHandoff) {
    try {
        $candidate = Get-AllRows "qfu_workitems?`$select=qfu_workitemid,qfu_workitemnumber,qfu_sourcedocumentnumber,qfu_sourceexternalkey,qfu_completedattempts,qfu_currentqueuerole,qfu_queuehandoffcount,_qfu_tsrstaff_value,_qfu_cssrstaff_value&`$filter=statecode eq 0 and qfu_worktype eq $($workTypeValues.Quote) and _qfu_tsrstaff_value ne null and _qfu_cssrstaff_value ne null and qfu_status ne $($statusValues.ClosedWon) and qfu_status ne $($statusValues.ClosedLost) and qfu_status ne $($statusValues.Cancelled)&`$top=1" | Select-Object -First 1
        if ($candidate) {
            $handoffResult.itemSelected = $true
            $handoffResult.sourceExternalKey = $candidate.qfu_sourceexternalkey
            $handoffResult.sourceDocumentNumber = $candidate.qfu_sourcedocumentnumber
            $handoffResult.beforeOwnerRole = $candidate.qfu_currentqueuerole
            $beforeAttemptCount = if ($null -ne $candidate.qfu_completedattempts) { [int]$candidate.qfu_completedattempts } else { 0 }
            $beforeHandoffCount = if ($null -ne $candidate.qfu_queuehandoffcount) { [int]$candidate.qfu_queuehandoffcount } else { 0 }
            $marker = "PHASE5_HANDOFF_TEST $(Get-Date -Format o)"

            Invoke-DvPatch "qfu_workitems($($candidate.qfu_workitemid))" @{
                'qfu_CurrentQueueOwnerStaff@odata.bind' = "/qfu_staffs($($candidate.'_qfu_cssrstaff_value'))"
                qfu_currentqueuerole = $roleValues.CSSR
                qfu_queueassignedon = (Get-Date).ToUniversalTime().ToString('o')
                qfu_queuehandoffcount = $beforeHandoffCount + 1
                qfu_queuehandoffreason = "Controlled Phase 5 test route to CSSR. $marker"
            } | Out-Null
            Invoke-DvPost 'qfu_workitemactions' @{
                qfu_name = "Queue Handoff - $($candidate.qfu_workitemnumber)"
                'qfu_WorkItem@odata.bind' = "/qfu_workitems($($candidate.qfu_workitemid))"
                qfu_actiontype = $actionTypeValues.AssignmentReassignment
                qfu_actionon = (Get-Date).ToUniversalTime().ToString('o')
                qfu_countsasattempt = $false
                qfu_notes = "Controlled Phase 5 test route to CSSR. $marker"
                qfu_outcome = 'CSSR'
            } | Out-Null

            $afterCssr = Invoke-DvGet "qfu_workitems($($candidate.qfu_workitemid))?`$select=qfu_completedattempts,qfu_currentqueuerole,_qfu_currentqueueownerstaff_value,qfu_queuehandoffcount"
            $handoffResult.afterCssrOwnerMatched = ($afterCssr.'_qfu_currentqueueownerstaff_value' -eq $candidate.'_qfu_cssrstaff_value') -and ([int]$afterCssr.qfu_currentqueuerole -eq $roleValues.CSSR)

            Invoke-DvPatch "qfu_workitems($($candidate.qfu_workitemid))" @{
                'qfu_CurrentQueueOwnerStaff@odata.bind' = "/qfu_staffs($($candidate.'_qfu_tsrstaff_value'))"
                qfu_currentqueuerole = $roleValues.TSR
                qfu_queueassignedon = (Get-Date).ToUniversalTime().ToString('o')
                qfu_queuehandoffcount = ([int]$afterCssr.qfu_queuehandoffcount) + 1
                qfu_queuehandoffreason = "Controlled Phase 5 test route back to TSR. $marker"
            } | Out-Null
            Invoke-DvPost 'qfu_workitemactions' @{
                qfu_name = "Queue Handoff - $($candidate.qfu_workitemnumber)"
                'qfu_WorkItem@odata.bind' = "/qfu_workitems($($candidate.qfu_workitemid))"
                qfu_actiontype = $actionTypeValues.AssignmentReassignment
                qfu_actionon = (Get-Date).ToUniversalTime().ToString('o')
                qfu_countsasattempt = $false
                qfu_notes = "Controlled Phase 5 test route back to TSR. $marker"
                qfu_outcome = 'TSR'
            } | Out-Null

            $afterTsr = Invoke-DvGet "qfu_workitems($($candidate.qfu_workitemid))?`$select=qfu_completedattempts,qfu_currentqueuerole,_qfu_currentqueueownerstaff_value,qfu_queuehandoffcount"
            $handoffResult.afterTsrOwnerMatched = ($afterTsr.'_qfu_currentqueueownerstaff_value' -eq $candidate.'_qfu_tsrstaff_value') -and ([int]$afterTsr.qfu_currentqueuerole -eq $roleValues.TSR)
            $handoffResult.completedAttemptsPreserved = ([int]$afterTsr.qfu_completedattempts -eq $beforeAttemptCount)

            $escapedMarker = Escape-ODataString $marker
            $handoffActions = Get-AllRows "qfu_workitemactions?`$select=qfu_workitemactionid,qfu_countsasattempt,qfu_notes&`$filter=_qfu_workitem_value eq $($candidate.qfu_workitemid) and contains(qfu_notes,'$escapedMarker')"
            $handoffResult.actionLogsCreated = @($handoffActions).Count
            $handoffResult.countsAsAttemptFalse = -not (@($handoffActions) | Where-Object { $_.qfu_countsasattempt -eq $true })
            $handoffResult.alertsSentAfter = 0
        }
    }
    catch {
        $handoffResult.error = $_.Exception.Message
    }
}

$result = [ordered]@{
    environmentUrl = $EnvironmentUrl
    timestamp = (Get-Date).ToString('o')
    solutionFound = [bool]$solution
    appFound = [bool]$app
    canvasAppFound = (@($canvasApps).Count -gt 0)
    queueFieldsPresent = [ordered]@{}
    counts = [ordered]@{
        activeWorkItems = @($activeWorkItems).Count
        activeQuoteWorkItems = @($activeWorkItems | Where-Object { $_.qfu_worktype -eq $workTypeValues.Quote }).Count
        activeBackorderWorkItems = @($activeWorkItems | Where-Object { $_.qfu_worktype -eq $workTypeValues.Backorder }).Count
        activeAssignmentExceptions = @($activeExceptions).Count
        activeAlertLogs = @($activeAlerts).Count
        sentAlertLogs = 0
        workItemActions = @($activeActions).Count
        handoffActions = @($activeActions | Where-Object { $_.qfu_actiontype -eq $actionTypeValues.AssignmentReassignment }).Count
        dueToday = @($activeWorkItems | Where-Object { $_.qfu_status -eq 985010001 }).Count
        overdue = @($activeWorkItems | Where-Object { $_.qfu_status -eq 985010002 }).Count
        open = @($activeWorkItems | Where-Object { $_.qfu_status -eq 985010000 }).Count
        roadblocks = @($activeWorkItems | Where-Object { $_.qfu_status -eq 985010005 }).Count
        assignmentIssues = @($activeWorkItems | Where-Object { $_.qfu_assignmentstatus -ne 985010000 }).Count
        missingAttempts = @($activeWorkItems | Where-Object { $null -ne $_.qfu_requiredattempts -and ([int]$_.qfu_completedattempts) -lt ([int]$_.qfu_requiredattempts) }).Count
        workItemsWithStickyNotes = @($activeWorkItems | Where-Object { -not [string]::IsNullOrWhiteSpace($_.qfu_stickynote) }).Count
        phase5StickyMarkerFound = @($activeWorkItems | Where-Object { $_.qfu_stickynote -like '*PHASE5_UI_TEST_STICKY_NOTE*' }).Count
        currentQueueTsr = @($activeWorkItems | Where-Object { $_.qfu_currentqueuerole -eq $roleValues.TSR }).Count
        currentQueueCssr = @($activeWorkItems | Where-Object { $_.qfu_currentqueuerole -eq $roleValues.CSSR }).Count
        currentQueueUnassigned = @($activeWorkItems | Where-Object { $_.qfu_currentqueuerole -eq $roleValues.Unassigned }).Count
    }
    duplicateWorkItemSourceKeys = @($duplicateWorkItemKeys).Count
    duplicateAssignmentExceptionKeys = @($duplicateExceptionKeys).Count
    controlledHandoff = $handoffResult
    serverSideRollup = [ordered]@{
        implemented = [bool]$rollupFlow
        flowName = if ($rollupFlow) { $rollupFlow.name } else { $null }
        workflowId = if ($rollupFlow) { $rollupFlow.workflowid } else { $null }
        statecode = if ($rollupFlow) { $rollupFlow.statecode } else { $null }
        statuscode = if ($rollupFlow) { $rollupFlow.statuscode } else { $null }
        validation = if ($rollupFlow) { 'Rollup flow found. Use Test-RevenueFollowUpPhase5ServerRollup.ps1 for behavior validation.' } else { 'Rollup flow not found by name.' }
    }
}

foreach ($field in $queueFields) {
    $result.queueFieldsPresent[$field] = $fieldNames -contains $field
}

$dir = Split-Path -Parent $OutputPath
if ($dir -and -not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}
$result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
$result | ConvertTo-Json -Depth 20
