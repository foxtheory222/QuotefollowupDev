param(
    [string]$EnvironmentUrl = 'https://orga632edd5.crm3.dynamics.com',
    [string]$OutputDir = 'results\phase7'
)

$ErrorActionPreference = 'Stop'

$membershipRoleValues = @{
    TSR     = 100000000
    CSSR    = 100000001
    Manager = 100000002
    GM      = 100000003
    Admin   = 100000004
}

$workItemStatusValues = @{
    Open        = 985010000
    DueToday    = 985010001
    Overdue     = 985010002
    Roadblock   = 985010005
    ClosedWon   = 985010008
    ClosedLost  = 985010009
    Cancelled   = 985010010
}

$assignmentStatusValues = @{
    Assigned            = 985010000
    PartiallyAssigned   = 985010001
    NeedsTSRAssignment  = 985010002
    NeedsCSSRAssignment = 985010003
    Unmapped            = 985010004
    Error               = 985010005
}

$alertStatusValues = @{
    Pending    = 985010000
    Sent       = 985010001
    Failed     = 985010002
    Suppressed = 985010003
    Skipped    = 985010004
}

function Convert-AccessTokenToString {
    param([object]$Token)
    if ($Token -is [securestring]) {
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Token)
        try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    }
    return [string]$Token
}

function Get-AccessToken {
    $tokenObject = Get-AzAccessToken -ResourceUrl "$EnvironmentUrl/"
    Convert-AccessTokenToString -Token $tokenObject.Token
}

function Get-Prop {
    param([object]$Row, [string]$Name)
    if ($null -eq $Row) { return $null }
    $prop = $Row.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    return $null
}

function Test-EmailFormat {
    param([string]$Email)
    if ([string]::IsNullOrWhiteSpace($Email)) { return $false }
    [bool]($Email -match '^[^@\s]+@[^@\s]+\.[^@\s]+$')
}

function Mask-Email {
    param([string]$Email)
    if ([string]::IsNullOrWhiteSpace($Email)) { return '' }
    $parts = $Email.Split('@', 2)
    if ($parts.Count -ne 2) { return 'invalid-format' }
    $local = $parts[0]
    $maskedLocal = if ($local.Length -le 1) { '*' } else { "$($local.Substring(0,1))***" }
    "$maskedLocal@$($parts[1])"
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$headers = @{
    Authorization      = "Bearer $(Get-AccessToken)"
    Accept             = 'application/json'
    'OData-MaxVersion' = '4.0'
    'OData-Version'    = '4.0'
}

function Invoke-DvGet {
    param([string]$RelativeUrl)
    Invoke-RestMethod -Method Get -Uri "$EnvironmentUrl/api/data/v9.2/$RelativeUrl" -Headers $headers
}

function Get-AllRows {
    param([string]$RelativeUrl)
    $rows = @()
    $url = "$EnvironmentUrl/api/data/v9.2/$RelativeUrl"
    do {
        $response = Invoke-RestMethod -Method Get -Uri $url -Headers $headers
        $rows += @($response.value)
        $url = $response.'@odata.nextLink'
    } while ($url)
    $rows
}

function New-RecipientCandidate {
    param(
        [string]$Processor,
        [string]$AlertType,
        [string]$ScopeId,
        [string]$BranchId,
        [string]$RecipientStaffId,
        [string]$Role,
        [string]$Reason,
        [hashtable]$StaffById
    )

    $staff = if (-not [string]::IsNullOrWhiteSpace($RecipientStaffId) -and $StaffById.ContainsKey($RecipientStaffId)) { $StaffById[$RecipientStaffId] } else { $null }
    $email = if ($staff) { [string]$staff.qfu_primaryemail } else { '' }
    $hasEmail = Test-EmailFormat $email
    [pscustomobject]@{
        processor = $Processor
        alertType = $AlertType
        scopeId = $ScopeId
        branchId = $BranchId
        recipientStaffId = $RecipientStaffId
        role = $Role
        staffFound = [bool]$staff
        emailFound = $hasEmail
        recipientEmailMasked = Mask-Email $email
        outcome = if (-not $staff) { 'SkippedMissingStaff' } elseif (-not $hasEmail) { 'SkippedMissingEmail' } else { 'ResolvableDryRun' }
        reason = $Reason
    }
}

$whoAmI = Invoke-DvGet 'WhoAmI()'
$currentUser = Invoke-DvGet "systemusers($($whoAmI.UserId))?`$select=systemuserid,fullname,internalemailaddress,domainname,isdisabled"

$solution = Get-AllRows "solutions?`$select=solutionid,uniquename,friendlyname&`$filter=uniquename eq 'qfu_revenuefollowupworkbench'&`$top=1" | Select-Object -First 1
$apps = Get-AllRows "appmodules?`$select=appmoduleid,name,uniquename&`$filter=name eq 'Revenue Follow-Up Workbench' or uniquename eq 'qfu_RevenueFollowUpWorkbench'"
$workflows = Get-AllRows "workflows?`$select=workflowid,name,statecode,statuscode,category,type,primaryentity,clientdata&`$filter=category eq 5 and startswith(name,'QFU ')"
$roles = Get-AllRows "roles?`$select=roleid,name,_businessunitid_value&`$filter=startswith(name,'QFU ') or contains(name,'Quote Follow')"
$teams = Get-AllRows "teams?`$select=teamid,name,teamtype,_businessunitid_value&`$filter=startswith(name,'QFU ') or contains(name,'Quote Follow')"

$staffRows = Get-AllRows "qfu_staffs?`$select=qfu_staffid,qfu_name,qfu_staffnumber,qfu_primaryemail,_qfu_systemuser_value,qfu_active,statecode&`$filter=statecode eq 0"
$membershipRows = Get-AllRows "qfu_branchmemberships?`$select=qfu_branchmembershipid,qfu_name,qfu_role,qfu_active,_qfu_branch_value,_qfu_staff_value,statecode,qfu_notes&`$filter=statecode eq 0"
$workItems = Get-AllRows "qfu_workitems?`$select=qfu_workitemid,qfu_workitemnumber,qfu_worktype,qfu_status,qfu_assignmentstatus,qfu_completedattempts,qfu_requiredattempts,qfu_nextfollowupon,qfu_currentqueuerole,qfu_currentqueueroletext,qfu_sourceexternalkey,_qfu_branch_value,_qfu_currentqueueownerstaff_value,_qfu_tsrstaff_value,_qfu_cssrstaff_value,statecode&`$filter=statecode eq 0"
$actions = Get-AllRows "qfu_workitemactions?`$select=qfu_workitemactionid,qfu_actiontype,qfu_countsasattempt,qfu_actionon,_qfu_workitem_value,statecode&`$filter=statecode eq 0"
$alertLogs = Get-AllRows "qfu_alertlogs?`$select=qfu_alertlogid,qfu_status,qfu_alerttype,qfu_dedupekey,qfu_senton,statecode&`$filter=statecode eq 0"
$exceptions = Get-AllRows "qfu_assignmentexceptions?`$select=qfu_assignmentexceptionid,qfu_exceptionkey,qfu_status,_qfu_branch_value,statecode&`$filter=statecode eq 0"
$quotes = Get-AllRows "qfu_quotes?`$select=qfu_quoteid,qfu_sourceid,statecode&`$filter=statecode eq 0&`$top=1"
$quoteLines = Get-AllRows "qfu_quotelines?`$select=qfu_quotelineid,statecode&`$filter=statecode eq 0&`$top=1"
$backorders = Get-AllRows "qfu_backorders?`$select=qfu_backorderid,qfu_sourceid,statecode&`$filter=statecode eq 0&`$top=1"

$staffById = @{}
foreach ($staff in $staffRows) { $staffById[[string]$staff.qfu_staffid] = $staff }
$activeStaffRows = @($staffRows | Where-Object { $_.qfu_active -ne $false })

$roleCounts = @{}
foreach ($role in $membershipRoleValues.Keys) {
    $roleCounts[$role] = @($membershipRows | Where-Object { [int]$_.qfu_role -eq $membershipRoleValues[$role] }).Count
}

$today = (Get-Date).Date
$terminalStatuses = @($workItemStatusValues.ClosedWon, $workItemStatusValues.ClosedLost, $workItemStatusValues.Cancelled)
$activeWorkItems = @($workItems | Where-Object { $terminalStatuses -notcontains [int]$_.qfu_status })
$dueToday = @($activeWorkItems | Where-Object {
    if (-not $_.qfu_nextfollowupon) { return $false }
    ([datetime]$_.qfu_nextfollowupon).Date -eq $today
})
$overdue = @($activeWorkItems | Where-Object {
    if (-not $_.qfu_nextfollowupon) { return $false }
    ([datetime]$_.qfu_nextfollowupon).Date -lt $today
})
$missingAttempts = @($activeWorkItems | Where-Object { [int]$_.qfu_completedattempts -lt [int]$_.qfu_requiredattempts })
$assignmentIssues = @($activeWorkItems | Where-Object { [int]$_.qfu_assignmentstatus -in @($assignmentStatusValues.NeedsTSRAssignment,$assignmentStatusValues.NeedsCSSRAssignment,$assignmentStatusValues.Unmapped,$assignmentStatusValues.Error) })

$resolverCandidates = New-Object System.Collections.Generic.List[object]
foreach ($item in $dueToday | Select-Object -First 50) {
    $recipient = [string](Get-Prop -Row $item -Name '_qfu_currentqueueownerstaff_value')
    if ([string]::IsNullOrWhiteSpace($recipient)) { $recipient = [string](Get-Prop -Row $item -Name '_qfu_tsrstaff_value') }
    $resolverCandidates.Add((New-RecipientCandidate -Processor 'AlertDispatcherReadOnly' -AlertType 'DueToday' -ScopeId ([string]$item.qfu_workitemid) -BranchId ([string](Get-Prop -Row $item -Name '_qfu_branch_value')) -RecipientStaffId $recipient -Role 'CurrentQueueOwner' -Reason 'Due today candidate' -StaffById $staffById)) | Out-Null
}
foreach ($item in $overdue | Select-Object -First 50) {
    $recipient = [string](Get-Prop -Row $item -Name '_qfu_currentqueueownerstaff_value')
    if ([string]::IsNullOrWhiteSpace($recipient)) { $recipient = [string](Get-Prop -Row $item -Name '_qfu_tsrstaff_value') }
    $resolverCandidates.Add((New-RecipientCandidate -Processor 'AlertDispatcherReadOnly' -AlertType 'Overdue' -ScopeId ([string]$item.qfu_workitemid) -BranchId ([string](Get-Prop -Row $item -Name '_qfu_branch_value')) -RecipientStaffId $recipient -Role 'CurrentQueueOwner' -Reason 'Overdue candidate' -StaffById $staffById)) | Out-Null
}
foreach ($staff in $staffRows | Where-Object { $_.qfu_active -ne $false }) {
    $resolverCandidates.Add((New-RecipientCandidate -Processor 'DailyStaffDigestReadOnly' -AlertType 'DailyStaffDigest' -ScopeId ([string]$staff.qfu_staffid) -BranchId '' -RecipientStaffId ([string]$staff.qfu_staffid) -Role 'Staff' -Reason 'Active staff digest candidate' -StaffById $staffById)) | Out-Null
}
foreach ($membership in $membershipRows | Where-Object { [int]$_.qfu_role -in @($membershipRoleValues.Manager,$membershipRoleValues.GM,$membershipRoleValues.Admin) }) {
    $roleName = ($membershipRoleValues.GetEnumerator() | Where-Object { $_.Value -eq [int]$membership.qfu_role } | Select-Object -First 1).Key
    $resolverCandidates.Add((New-RecipientCandidate -Processor 'ManagerEscalationReadOnly' -AlertType 'ManagerDigestOrEscalation' -ScopeId ([string]$membership.qfu_branchmembershipid) -BranchId ([string](Get-Prop -Row $membership -Name '_qfu_branch_value')) -RecipientStaffId ([string](Get-Prop -Row $membership -Name '_qfu_staff_value')) -Role $roleName -Reason 'Manager/GM/Admin membership recipient candidate' -StaffById $staffById)) | Out-Null
}

$duplicateAlertKeys = @($alertLogs | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.qfu_dedupekey) } | Group-Object qfu_dedupekey | Where-Object Count -gt 1)
$duplicateWorkItemKeys = @($workItems | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.qfu_sourceexternalkey) } | Group-Object qfu_sourceexternalkey | Where-Object Count -gt 1)
$duplicateExceptionKeys = @($exceptions | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.qfu_exceptionkey) } | Group-Object qfu_exceptionkey | Where-Object Count -gt 1)

$flowReview = @($workflows | ForEach-Object {
    $client = [string]$_.clientdata
    [pscustomobject]@{
        workflowId = $_.workflowid
        name = $_.name
        statecode = $_.statecode
        statuscode = $_.statuscode
        containsSendMail = $client -match 'SendEmail|sendmail|shared_office365|smtp|Send_an_email'
        containsTeams = $client -match 'shared_teams|Post_message|chatMessage'
    }
})

$recipientResolver = @($resolverCandidates.ToArray())
$recipientResolver | Export-Csv -NoTypeInformation -Path (Join-Path $OutputDir 'recipient-resolver-readonly-rerun.csv')

$summary = [ordered]@{
    timestamp = (Get-Date).ToString('o')
    environmentUrl = $EnvironmentUrl
    currentUser = @{
        systemUserId = [string]$currentUser.systemuserid
        emailMasked = Mask-Email ([string]$currentUser.internalemailaddress)
    }
    solutionFound = [bool]$solution
    modelDrivenAppFound = @($apps).Count -gt 0
    tablesAccessible = @{
        qfu_staff = @($staffRows).Count -ge 0
        qfu_branchmembership = @($membershipRows).Count -ge 0
        qfu_workitem = @($workItems).Count -ge 0
        qfu_workitemaction = @($actions).Count -ge 0
        qfu_alertlog = @($alertLogs).Count -ge 0
        qfu_assignmentexception = @($exceptions).Count -ge 0
        qfu_quote = @($quotes).Count -ge 0
        qfu_quoteline = @($quoteLines).Count -ge 0
        qfu_backorder = @($backorders).Count -ge 0
    }
    counts = @{
        activeStaff = @($activeStaffRows).Count
        activeStaffWithEmail = @($activeStaffRows | Where-Object { Test-EmailFormat ([string]$_.qfu_primaryemail) }).Count
        activeStaffMissingEmail = @($activeStaffRows | Where-Object { -not (Test-EmailFormat ([string]$_.qfu_primaryemail)) }).Count
        activeStaffLinkedToSystemUser = @($activeStaffRows | Where-Object { -not [string]::IsNullOrWhiteSpace([string](Get-Prop -Row $_ -Name '_qfu_systemuser_value')) }).Count
        activeStaffMissingSystemUser = @($activeStaffRows | Where-Object { [string]::IsNullOrWhiteSpace([string](Get-Prop -Row $_ -Name '_qfu_systemuser_value')) }).Count
        statecodeZeroStaffWithEmail = @($staffRows | Where-Object { Test-EmailFormat ([string]$_.qfu_primaryemail) }).Count
        statecodeZeroStaffLinkedToSystemUser = @($staffRows | Where-Object { -not [string]::IsNullOrWhiteSpace([string](Get-Prop -Row $_ -Name '_qfu_systemuser_value')) }).Count
        tsrMemberships = $roleCounts.TSR
        cssrMemberships = $roleCounts.CSSR
        managerMemberships = $roleCounts.Manager
        gmMemberships = $roleCounts.GM
        adminMemberships = $roleCounts.Admin
        activeWorkItems = @($workItems).Count
        dueTodayWorkItems = @($dueToday).Count
        overdueWorkItems = @($overdue).Count
        roadblockWorkItems = @($activeWorkItems | Where-Object { [int]$_.qfu_status -eq $workItemStatusValues.Roadblock }).Count
        missingAttemptsWorkItems = @($missingAttempts).Count
        assignmentIssues = @($assignmentIssues).Count
        activeAssignmentExceptions = @($exceptions).Count
        workItemActions = @($actions).Count
        alertLogsTotal = @($alertLogs).Count
        sentAlertLogs = @($alertLogs | Where-Object { [int]$_.qfu_status -eq $alertStatusValues.Sent }).Count
        failedAlertLogs = @($alertLogs | Where-Object { [int]$_.qfu_status -eq $alertStatusValues.Failed }).Count
        duplicateAlertDedupeKeys = @($duplicateAlertKeys).Count
        duplicateWorkItemSourceKeys = @($duplicateWorkItemKeys).Count
        duplicateAssignmentExceptionKeys = @($duplicateExceptionKeys).Count
        recipientCandidates = @($recipientResolver).Count
        recipientCandidatesResolvable = @($recipientResolver | Where-Object { $_.outcome -eq 'ResolvableDryRun' }).Count
        recipientCandidatesMissingEmail = @($recipientResolver | Where-Object { $_.outcome -eq 'SkippedMissingEmail' }).Count
        recipientCandidatesMissingStaff = @($recipientResolver | Where-Object { $_.outcome -eq 'SkippedMissingStaff' }).Count
    }
    phase6FlowReview = $flowReview | Select-Object workflowId,name,statecode,statuscode,containsSendMail,containsTeams
    noUnapprovedSend = @{
        sentAlertLogs = @($alertLogs | Where-Object { [int]$_.qfu_status -eq $alertStatusValues.Sent }).Count
        containsSendMailInQfuFlows = @($flowReview | Where-Object containsSendMail).Count
        containsTeamsInQfuFlows = @($flowReview | Where-Object containsTeams).Count
    }
    securityReadiness = @{
        qfuSecurityRolesFound = @($roles).Count
        qfuTeamsFound = @($teams).Count
        productionRoleSecurityComplete = $false
        blocker = 'No production-verified Manager/GM/Admin roster and no approved final privilege matrix were present in the environment.'
    }
}

$summary | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 -Path (Join-Path $OutputDir 'phase7-readiness-regression.json')
$flowReview | Export-Csv -NoTypeInformation -Path (Join-Path $OutputDir 'phase6-flow-no-send-review.csv')
$summary | ConvertTo-Json -Depth 20
