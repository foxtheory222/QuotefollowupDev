param(
    [string]$EnvironmentUrl = 'https://orga632edd5.crm3.dynamics.com',
    [string]$OutputDir = 'results\phase6',
    [switch]$AllowTestRecipientSend
)

$ErrorActionPreference = 'Stop'

$alertTypeValues = @{
    NewAssignment       = 985010000
    DueToday            = 985010001
    Overdue             = 985010002
    Escalation          = 985010003
    DailyDigest         = 985010004
    AssignmentException = 985010005
    FlowFailure         = 985010006
}

$alertStatusValues = @{
    Pending    = 985010000
    Sent       = 985010001
    Failed     = 985010002
    Suppressed = 985010003
    Skipped    = 985010004
}

$workItemStatusValues = @{
    Open              = 985010000
    DueToday          = 985010001
    Overdue           = 985010002
    WaitingCustomer   = 985010003
    WaitingVendor     = 985010004
    Roadblock         = 985010005
    Escalated         = 985010006
    Completed         = 985010007
    ClosedWon         = 985010008
    ClosedLost        = 985010009
    Cancelled         = 985010010
}

$assignmentStatusValues = @{
    Assigned            = 985010000
    PartiallyAssigned   = 985010001
    NeedsTSRAssignment  = 985010002
    NeedsCSSRAssignment = 985010003
    Unmapped            = 985010004
    Error               = 985010005
}

$membershipRoleValues = @{
    TSR     = 100000000
    CSSR    = 100000001
    Manager = 100000002
    GM      = 100000003
    Admin   = 100000004
}

function Convert-AccessTokenToString {
    param([object]$Token)

    if ($Token -is [securestring]) {
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Token)
        try {
            return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        }
        finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }

    return [string]$Token
}

function Get-AccessToken {
    $tokenObject = Get-AzAccessToken -ResourceUrl "$EnvironmentUrl/"
    return Convert-AccessTokenToString -Token $tokenObject.Token
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

function Invoke-DvPost {
    param([string]$RelativeUrl, [object]$Body)
    Invoke-RestMethod -Method Post -Uri "$EnvironmentUrl/api/data/v9.2/$RelativeUrl" -Headers $headers -Body ($Body | ConvertTo-Json -Depth 100)
}

function Invoke-DvPatchNoContent {
    param([string]$RelativeUrl, [object]$Body)
    Invoke-WebRequest -UseBasicParsing -Method Patch -Uri "$EnvironmentUrl/api/data/v9.2/$RelativeUrl" -Headers $headers -Body ($Body | ConvertTo-Json -Depth 100) | Out-Null
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
    if ($null -eq $Value) { return '' }
    return $Value.Replace("'", "''")
}

function Get-Prop {
    param([object]$Row, [string]$Name)
    if ($null -eq $Row) { return $null }
    $prop = $Row.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    return $null
}

function Test-ActiveFlag {
    param([object]$Value)
    if ($null -eq $Value) { return $true }
    return [bool]$Value
}

function Test-EmailFormat {
    param([string]$Email)
    if ([string]::IsNullOrWhiteSpace($Email)) { return $false }
    return [bool]($Email -match '^[^@\s]+@[^@\s]+\.[^@\s]+$')
}

function Mask-Email {
    param([string]$Email)
    if ([string]::IsNullOrWhiteSpace($Email)) { return '' }
    $parts = $Email.Split('@', 2)
    if ($parts.Count -ne 2) { return 'invalid-format' }
    $local = $parts[0]
    $maskedLocal = if ($local.Length -le 1) { '*' } else { "$($local.Substring(0,1))***" }
    return "$maskedLocal@$($parts[1])"
}

function Add-Candidate {
    param(
        [System.Collections.Generic.List[object]]$List,
        [string]$Processor,
        [string]$AlertTypeName,
        [int]$AlertTypeValue,
        [string]$WorkItemId,
        [string]$BranchId,
        [string]$RecipientStaffId,
        [string]$IntendedRole,
        [string]$DueDate,
        [string]$EscalationLevel,
        [string]$DigestDate,
        [string]$Reason,
        [string]$Outcome
    )

    $recipientKey = if ([string]::IsNullOrWhiteSpace($RecipientStaffId)) { "NO_RECIPIENT_$IntendedRole" } else { $RecipientStaffId }
    $scopeKey = if ([string]::IsNullOrWhiteSpace($WorkItemId)) { $BranchId } else { $WorkItemId }
    if ([string]::IsNullOrWhiteSpace($scopeKey)) { $scopeKey = 'GLOBAL' }

    if ($AlertTypeName -eq 'DailyStaffDigest') {
        $dedupeKey = "$recipientKey|DailyStaffDigest|$DigestDate"
    }
    elseif ($AlertTypeName -eq 'ManagerDigest') {
        $dedupeKey = "$BranchId|ManagerDigest|$recipientKey|$DigestDate"
    }
    elseif ($AlertTypeName -eq 'AssignmentExceptionDigest') {
        $dedupeKey = "$BranchId|AssignmentExceptionDigest|$recipientKey|$DigestDate"
    }
    else {
        $dedupeKey = "$scopeKey|$AlertTypeName|$recipientKey|$DueDate|$EscalationLevel|$DigestDate"
    }

    $List.Add([pscustomobject]@{
        processor = $Processor
        alertTypeName = $AlertTypeName
        alertTypeValue = $AlertTypeValue
        workItemId = $WorkItemId
        branchId = $BranchId
        recipientStaffId = $RecipientStaffId
        intendedRole = $IntendedRole
        dueDate = $DueDate
        escalationLevel = $EscalationLevel
        digestDate = $DigestDate
        reason = $Reason
        outcome = $Outcome
        dedupeKey = $dedupeKey
    }) | Out-Null
}

function Resolve-StaffRecipient {
    param(
        [string]$StaffId,
        [string]$IntendedRole,
        [hashtable]$StaffById
    )

    $staff = if (-not [string]::IsNullOrWhiteSpace($StaffId) -and $StaffById.ContainsKey($StaffId)) { $StaffById[$StaffId] } else { $null }
    $email = if ($staff) { [string](Get-Prop -Row $staff -Name 'qfu_primaryemail') } else { '' }
    $active = if ($staff) { Test-ActiveFlag (Get-Prop -Row $staff -Name 'qfu_active') } else { $false }
    $emailValid = Test-EmailFormat -Email $email

    [pscustomobject]@{
        staff = $staff
        staffId = if ($staff) { [string]$staff.qfu_staffid } else { $StaffId }
        intendedRole = $IntendedRole
        staffFound = [bool]$staff
        staffActive = $active
        email = if ($emailValid) { $email } else { '' }
        emailFound = $emailValid
        maskedEmail = if ($emailValid) { Mask-Email -Email $email } else { '' }
        reason = if (-not $staff) { 'Recipient staff not found' } elseif (-not $active) { 'Recipient staff inactive' } elseif (-not $emailValid) { 'Missing recipient email' } else { 'Resolved' }
    }
}

function Resolve-MembershipRecipients {
    param(
        [string]$BranchId,
        [string]$RoleName,
        [hashtable]$MembershipsByBranchRole
    )

    $key = "$BranchId|$RoleName"
    if ($MembershipsByBranchRole.ContainsKey($key)) {
        return @($MembershipsByBranchRole[$key])
    }
    return @()
}

function Write-CsvSafe {
    param([string]$Path, [object[]]$Rows)
    $directory = Split-Path -Parent $Path
    if ($directory) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    @($Rows) | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
}

function New-AlertLogBody {
    param([object]$Candidate, [object]$Resolved, [int]$Status, [string]$StatusText)

    $body = @{
        qfu_name = "Phase 6 $($Candidate.alertTypeName) $StatusText"
        qfu_alerttype = $Candidate.alertTypeValue
        qfu_status = $Status
        qfu_dedupekey = $Candidate.dedupeKey
        qfu_notes = "Phase 6 $StatusText. Mode=DryRunOnly. Processor=$($Candidate.processor). IntendedRole=$($Candidate.intendedRole). Reason=$($Candidate.reason). Resolver=$($Resolved.reason). No email or Teams message sent."
        qfu_ccemails = ''
        qfu_flowrunid = 'Phase6DryRunHarness'
    }

    if (-not [string]::IsNullOrWhiteSpace($Candidate.workItemId)) {
        $body['qfu_WorkItem@odata.bind'] = "/qfu_workitems($($Candidate.workItemId))"
    }
    if ($Resolved.staffFound -and -not [string]::IsNullOrWhiteSpace($Resolved.staffId)) {
        $body['qfu_RecipientStaff@odata.bind'] = "/qfu_staffs($($Resolved.staffId))"
    }
    if ($Resolved.emailFound) {
        $body['qfu_recipientemail'] = $Resolved.email
    }

    return $body
}

function Upsert-AlertLog {
    param([object]$Candidate, [object]$Resolved)

    $escaped = Escape-ODataString $Candidate.dedupeKey
    $existing = Get-AllRows "qfu_alertlogs?`$select=qfu_alertlogid,qfu_name,qfu_dedupekey,qfu_status,qfu_notes&`$filter=qfu_dedupekey eq '$escaped'&`$top=1" | Select-Object -First 1
    if ($existing) {
        $notes = [string]$existing.qfu_notes
        if ($notes -notlike '*Duplicate suppressed*') {
            try {
                Invoke-DvPatchNoContent "qfu_alertlogs($($existing.qfu_alertlogid))" @{
                    qfu_notes = "$notes Duplicate suppressed by Phase 6 dry-run dedupe recheck."
                }
            }
            catch {
                $null = $true
            }
        }
        return [pscustomobject]@{
            action = 'existing'
            alertLogId = $existing.qfu_alertlogid
            dedupeKey = $Candidate.dedupeKey
            status = $existing.qfu_status
        }
    }

    $status = if ($Resolved.emailFound) { $alertStatusValues.Suppressed } else { $alertStatusValues.Skipped }
    $statusText = if ($Resolved.emailFound) { 'DryRunOnly' } else { 'SkippedMissingRecipient' }
    $body = New-AlertLogBody -Candidate $Candidate -Resolved $Resolved -Status $status -StatusText $statusText
    try {
        $created = Invoke-DvPost 'qfu_alertlogs' $body
        return [pscustomobject]@{
            action = 'created'
            alertLogId = $created.qfu_alertlogid
            dedupeKey = $Candidate.dedupeKey
            status = $status
        }
    }
    catch {
        $message = $_.Exception.Message
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $message = $_.ErrorDetails.Message }
        return [pscustomobject]@{
            action = 'failed'
            alertLogId = $null
            dedupeKey = $Candidate.dedupeKey
            status = $alertStatusValues.Failed
            failure = $message
        }
    }
}

function Get-AlertLogCounts {
    $rows = Get-AllRows "qfu_alertlogs?`$select=qfu_alertlogid,qfu_status,qfu_dedupekey&`$filter=statecode eq 0"
    $duplicateDedupeKeys = @($rows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.qfu_dedupekey) } | Group-Object qfu_dedupekey | Where-Object { $_.Count -gt 1 })
    [ordered]@{
        total = @($rows).Count
        sent = @($rows | Where-Object { [int]$_.qfu_status -eq $alertStatusValues.Sent }).Count
        failed = @($rows | Where-Object { [int]$_.qfu_status -eq $alertStatusValues.Failed }).Count
        skipped = @($rows | Where-Object { [int]$_.qfu_status -eq $alertStatusValues.Skipped }).Count
        suppressed = @($rows | Where-Object { [int]$_.qfu_status -eq $alertStatusValues.Suppressed }).Count
        duplicateDedupeKeys = @($duplicateDedupeKeys).Count
    }
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$digestDate = (Get-Date).ToString('yyyy-MM-dd')
$today = (Get-Date).Date
$terminalStatuses = @($workItemStatusValues.ClosedWon, $workItemStatusValues.ClosedLost, $workItemStatusValues.Cancelled, $workItemStatusValues.Completed)

$policy = Get-AllRows "qfu_policies?`$select=qfu_policyid,qfu_name,qfu_policykey,qfu_worktype,qfu_highvaluethreshold,qfu_requiredattempts,qfu_digestenabled,qfu_targetedalertenabled,qfu_escalateafterbusinessdays,qfu_alertmode,qfu_active&`$filter=qfu_policykey eq 'GLOBAL|Quote|Active'&`$top=1" | Select-Object -First 1
if (-not $policy) {
    throw 'GLOBAL|Quote|Active policy was not found. Run Ensure-RevenueFollowUpPhase6AlertInfrastructure.ps1 first.'
}
if ([int](Get-Prop -Row $policy -Name 'qfu_alertmode') -eq 985060003) {
    throw 'Policy alert mode is Live. Phase 6 dry-run harness refuses to run in Live mode.'
}

$alertCountsBefore = Get-AlertLogCounts

$staffRows = Get-AllRows "qfu_staffs?`$select=qfu_staffid,qfu_name,qfu_staffnumber,qfu_primaryemail,qfu_active,_qfu_systemuser_value,statecode&`$filter=statecode eq 0"
$staffById = @{}
foreach ($staff in $staffRows) {
    $staffById[[string]$staff.qfu_staffid] = $staff
}

$membershipRows = Get-AllRows "qfu_branchmemberships?`$select=qfu_branchmembershipid,qfu_name,qfu_role,qfu_active,_qfu_branch_value,_qfu_staff_value,statecode&`$filter=statecode eq 0"
$membershipsByBranchRole = @{}
foreach ($membership in $membershipRows) {
    if (-not (Test-ActiveFlag (Get-Prop -Row $membership -Name 'qfu_active'))) { continue }
    $branchId = [string](Get-Prop -Row $membership -Name '_qfu_branch_value')
    $roleValue = [int](Get-Prop -Row $membership -Name 'qfu_role')
    $roleName = ($membershipRoleValues.GetEnumerator() | Where-Object { $_.Value -eq $roleValue } | Select-Object -First 1).Key
    if ([string]::IsNullOrWhiteSpace($branchId) -or [string]::IsNullOrWhiteSpace($roleName)) { continue }
    $key = "$branchId|$roleName"
    if (-not $membershipsByBranchRole.ContainsKey($key)) {
        $membershipsByBranchRole[$key] = New-Object System.Collections.Generic.List[object]
    }
    $membershipsByBranchRole[$key].Add($membership) | Out-Null
}

$workItems = Get-AllRows "qfu_workitems?`$select=qfu_workitemid,qfu_workitemnumber,qfu_worktype,qfu_status,qfu_assignmentstatus,qfu_completedattempts,qfu_requiredattempts,qfu_nextfollowupon,qfu_overduesince,qfu_totalvalue,qfu_currentqueueroletext,qfu_sourceexternalkey,_qfu_currentqueueownerstaff_value,_qfu_tsrstaff_value,_qfu_cssrstaff_value,_qfu_branch_value,statecode&`$filter=statecode eq 0"
$assignmentExceptions = Get-AllRows "qfu_assignmentexceptions?`$select=qfu_assignmentexceptionid,qfu_exceptionkey,qfu_exceptiontype,qfu_status,_qfu_branch_value,statecode&`$filter=statecode eq 0 and qfu_status eq 985010000"

$staffWorkItemCounts = @{}
foreach ($wi in $workItems) {
    $ownerId = [string](Get-Prop -Row $wi -Name '_qfu_currentqueueownerstaff_value')
    if (-not [string]::IsNullOrWhiteSpace($ownerId)) {
        if (-not $staffWorkItemCounts.ContainsKey($ownerId)) { $staffWorkItemCounts[$ownerId] = 0 }
        $staffWorkItemCounts[$ownerId]++
    }
}

$staffEmailRows = foreach ($staff in $staffRows) {
    $staffId = [string]$staff.qfu_staffid
    $email = [string](Get-Prop -Row $staff -Name 'qfu_primaryemail')
    $memberships = @($membershipRows | Where-Object { [string](Get-Prop -Row $_ -Name '_qfu_staff_value') -eq $staffId })
    [pscustomobject]@{
        staffId = $staffId
        staffNumber = [string](Get-Prop -Row $staff -Name 'qfu_staffnumber')
        hasPrimaryEmail = Test-EmailFormat -Email $email
        maskedEmail = Mask-Email -Email $email
        active = Test-ActiveFlag (Get-Prop -Row $staff -Name 'qfu_active')
        activeWorkItemCount = if ($staffWorkItemCounts.ContainsKey($staffId)) { $staffWorkItemCounts[$staffId] } else { 0 }
        managerMembershipCount = @($memberships | Where-Object { [int](Get-Prop -Row $_ -Name 'qfu_role') -eq $membershipRoleValues.Manager }).Count
        gmMembershipCount = @($memberships | Where-Object { [int](Get-Prop -Row $_ -Name 'qfu_role') -eq $membershipRoleValues.GM }).Count
        adminMembershipCount = @($memberships | Where-Object { [int](Get-Prop -Row $_ -Name 'qfu_role') -eq $membershipRoleValues.Admin }).Count
    }
}
Write-CsvSafe -Path (Join-Path $OutputDir 'staff-email-readiness.csv') -Rows $staffEmailRows

$candidates = New-Object System.Collections.Generic.List[object]

foreach ($wi in $workItems) {
    $status = [int](Get-Prop -Row $wi -Name 'qfu_status')
    if ($terminalStatuses -contains $status) { continue }
    $branchId = [string](Get-Prop -Row $wi -Name '_qfu_branch_value')
    $workItemId = [string]$wi.qfu_workitemid
    $dueDate = ''
    $nextFollowUp = Get-Prop -Row $wi -Name 'qfu_nextfollowupon'
    if ($nextFollowUp) {
        $dueDate = ([datetime]$nextFollowUp).ToString('yyyy-MM-dd')
    }
    $ownerId = [string](Get-Prop -Row $wi -Name '_qfu_currentqueueownerstaff_value')
    if ([string]::IsNullOrWhiteSpace($ownerId)) {
        $ownerId = [string](Get-Prop -Row $wi -Name '_qfu_tsrstaff_value')
    }
    if ([string]::IsNullOrWhiteSpace($ownerId)) {
        $ownerId = [string](Get-Prop -Row $wi -Name '_qfu_cssrstaff_value')
    }
    $ownerRole = [string](Get-Prop -Row $wi -Name 'qfu_currentqueueroletext')
    if ([string]::IsNullOrWhiteSpace($ownerRole)) { $ownerRole = 'PrimaryOwner' }

    if ([bool](Get-Prop -Row $policy -Name 'qfu_targetedalertenabled')) {
        if ($status -eq $workItemStatusValues.DueToday) {
            Add-Candidate -List $candidates -Processor 'AlertDispatcher' -AlertTypeName 'DueToday' -AlertTypeValue $alertTypeValues.DueToday -WorkItemId $workItemId -BranchId $branchId -RecipientStaffId $ownerId -IntendedRole $ownerRole -DueDate $dueDate -EscalationLevel '0' -DigestDate $digestDate -Reason 'Work item is Due Today' -Outcome 'Dry-run due-today targeted alert'
        }
        elseif ($status -eq $workItemStatusValues.Overdue) {
            Add-Candidate -List $candidates -Processor 'AlertDispatcher' -AlertTypeName 'Overdue' -AlertTypeValue $alertTypeValues.Overdue -WorkItemId $workItemId -BranchId $branchId -RecipientStaffId $ownerId -IntendedRole $ownerRole -DueDate $dueDate -EscalationLevel '0' -DigestDate $digestDate -Reason 'Work item is Overdue' -Outcome 'Dry-run overdue targeted alert'
        }
        elseif ([int](Get-Prop -Row $wi -Name 'qfu_assignmentstatus') -ne $assignmentStatusValues.Assigned) {
            Add-Candidate -List $candidates -Processor 'AlertDispatcher' -AlertTypeName 'AssignmentException' -AlertTypeValue $alertTypeValues.AssignmentException -WorkItemId $workItemId -BranchId $branchId -RecipientStaffId $ownerId -IntendedRole $ownerRole -DueDate $dueDate -EscalationLevel '0' -DigestDate $digestDate -Reason 'Work item has assignment issue' -Outcome 'Dry-run assignment targeted alert'
        }
    }

    $completed = [int](Get-Prop -Row $wi -Name 'qfu_completedattempts')
    $required = [int](Get-Prop -Row $wi -Name 'qfu_requiredattempts')
    if ($required -le 0) { $required = [int](Get-Prop -Row $policy -Name 'qfu_requiredattempts') }
    if ($status -eq $workItemStatusValues.Overdue -or $status -eq $workItemStatusValues.Roadblock -or $completed -lt $required -or [int](Get-Prop -Row $wi -Name 'qfu_assignmentstatus') -ne $assignmentStatusValues.Assigned) {
        $managerMemberships = Resolve-MembershipRecipients -BranchId $branchId -RoleName 'Manager' -MembershipsByBranchRole $membershipsByBranchRole
        if (@($managerMemberships).Count -eq 0) {
            Add-Candidate -List $candidates -Processor 'EscalationProcessor' -AlertTypeName 'Escalation' -AlertTypeValue $alertTypeValues.Escalation -WorkItemId $workItemId -BranchId $branchId -RecipientStaffId '' -IntendedRole 'Manager' -DueDate $dueDate -EscalationLevel '1' -DigestDate $digestDate -Reason 'Escalation candidate; no manager membership found' -Outcome 'Skipped until manager recipient is configured'
        }
        foreach ($membership in $managerMemberships) {
            Add-Candidate -List $candidates -Processor 'EscalationProcessor' -AlertTypeName 'Escalation' -AlertTypeValue $alertTypeValues.Escalation -WorkItemId $workItemId -BranchId $branchId -RecipientStaffId ([string](Get-Prop -Row $membership -Name '_qfu_staff_value')) -IntendedRole 'Manager' -DueDate $dueDate -EscalationLevel '1' -DigestDate $digestDate -Reason 'Escalation candidate for manager review' -Outcome 'Dry-run escalation alert'
        }
    }
}

if ([bool](Get-Prop -Row $policy -Name 'qfu_digestenabled')) {
    foreach ($staffId in $staffWorkItemCounts.Keys) {
        Add-Candidate -List $candidates -Processor 'DailyStaffDigest' -AlertTypeName 'DailyStaffDigest' -AlertTypeValue $alertTypeValues.DailyDigest -WorkItemId '' -BranchId 'GLOBAL' -RecipientStaffId $staffId -IntendedRole 'Staff' -DueDate '' -EscalationLevel '0' -DigestDate $digestDate -Reason 'Staff has current queue work' -Outcome 'Dry-run staff digest'
    }

    $branchIds = @($workItems | ForEach-Object { [string](Get-Prop -Row $_ -Name '_qfu_branch_value') } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    foreach ($branchId in $branchIds) {
        $managerMemberships = Resolve-MembershipRecipients -BranchId $branchId -RoleName 'Manager' -MembershipsByBranchRole $membershipsByBranchRole
        if (@($managerMemberships).Count -eq 0) {
            Add-Candidate -List $candidates -Processor 'ManagerDigest' -AlertTypeName 'ManagerDigest' -AlertTypeValue $alertTypeValues.DailyDigest -WorkItemId '' -BranchId $branchId -RecipientStaffId '' -IntendedRole 'Manager' -DueDate '' -EscalationLevel '0' -DigestDate $digestDate -Reason 'Branch has work but no manager recipient membership' -Outcome 'Skipped until manager recipient is configured'
        }
        foreach ($membership in $managerMemberships) {
            Add-Candidate -List $candidates -Processor 'ManagerDigest' -AlertTypeName 'ManagerDigest' -AlertTypeValue $alertTypeValues.DailyDigest -WorkItemId '' -BranchId $branchId -RecipientStaffId ([string](Get-Prop -Row $membership -Name '_qfu_staff_value')) -IntendedRole 'Manager' -DueDate '' -EscalationLevel '0' -DigestDate $digestDate -Reason 'Branch/team digest candidate' -Outcome 'Dry-run manager digest'
        }
    }
}

$exceptionBranchIds = @($assignmentExceptions | ForEach-Object { [string](Get-Prop -Row $_ -Name '_qfu_branch_value') } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
foreach ($branchId in $exceptionBranchIds) {
    $managerMemberships = Resolve-MembershipRecipients -BranchId $branchId -RoleName 'Manager' -MembershipsByBranchRole $membershipsByBranchRole
    if (@($managerMemberships).Count -eq 0) {
        Add-Candidate -List $candidates -Processor 'AssignmentExceptionDigest' -AlertTypeName 'AssignmentExceptionDigest' -AlertTypeValue $alertTypeValues.AssignmentException -WorkItemId '' -BranchId $branchId -RecipientStaffId '' -IntendedRole 'Manager' -DueDate '' -EscalationLevel '0' -DigestDate $digestDate -Reason 'Open assignment exceptions with no manager recipient membership' -Outcome 'Skipped until manager recipient is configured'
    }
    foreach ($membership in $managerMemberships) {
        Add-Candidate -List $candidates -Processor 'AssignmentExceptionDigest' -AlertTypeName 'AssignmentExceptionDigest' -AlertTypeValue $alertTypeValues.AssignmentException -WorkItemId '' -BranchId $branchId -RecipientStaffId ([string](Get-Prop -Row $membership -Name '_qfu_staff_value')) -IntendedRole 'Manager' -DueDate '' -EscalationLevel '0' -DigestDate $digestDate -Reason 'Open assignment exceptions grouped by branch' -Outcome 'Dry-run assignment exception digest'
    }
}

$resolverRows = New-Object System.Collections.Generic.List[object]
function Invoke-CandidateRun {
    param([string]$RunName)
    $runResults = New-Object System.Collections.Generic.List[object]
    foreach ($candidate in $candidates) {
        $resolved = Resolve-StaffRecipient -StaffId $candidate.recipientStaffId -IntendedRole $candidate.intendedRole -StaffById $staffById
        $upsert = Upsert-AlertLog -Candidate $candidate -Resolved $resolved
        $resolverRows.Add([pscustomobject]@{
            runName = $RunName
            processor = $candidate.processor
            alertTypeName = $candidate.alertTypeName
            workItemId = $candidate.workItemId
            branchId = $candidate.branchId
            intendedRole = $candidate.intendedRole
            recipientStaffFound = $resolved.staffFound
            recipientEmailFound = $resolved.emailFound
            maskedEmail = $resolved.maskedEmail
            action = $upsert.action
            status = if ($resolved.emailFound) { 'DryRunOnly' } else { 'SkippedMissingRecipient' }
            reason = $resolved.reason
            dedupeKey = $candidate.dedupeKey
        }) | Out-Null
        $runResults.Add($upsert) | Out-Null
    }
    return $runResults.ToArray()
}

$firstRun = Invoke-CandidateRun -RunName 'first'
$secondRun = Invoke-CandidateRun -RunName 'second'
$alertCountsAfter = Get-AlertLogCounts

$resolverArray = @($resolverRows.ToArray())
$activeStaffRows = @($staffRows | Where-Object { Test-ActiveFlag (Get-Prop -Row $_ -Name 'qfu_active') })
Write-CsvSafe -Path (Join-Path $OutputDir 'recipient-resolver-dry-run.csv') -Rows $resolverArray
Write-CsvSafe -Path (Join-Path $OutputDir 'missing-recipient-email-review.csv') -Rows @($resolverArray | Where-Object { $_.reason -eq 'Missing recipient email' -or $_.reason -eq 'Recipient staff not found' })
Write-CsvSafe -Path (Join-Path $OutputDir 'alert-dispatcher-dry-run.csv') -Rows @($resolverArray | Where-Object { $_.processor -eq 'AlertDispatcher' })
Write-CsvSafe -Path (Join-Path $OutputDir 'staff-digest-dry-run.csv') -Rows @($resolverArray | Where-Object { $_.processor -eq 'DailyStaffDigest' })
Write-CsvSafe -Path (Join-Path $OutputDir 'manager-digest-dry-run.csv') -Rows @($resolverArray | Where-Object { $_.processor -eq 'ManagerDigest' })
Write-CsvSafe -Path (Join-Path $OutputDir 'escalation-dry-run.csv') -Rows @($resolverArray | Where-Object { $_.processor -eq 'EscalationProcessor' })
Write-CsvSafe -Path (Join-Path $OutputDir 'assignment-exception-digest-dry-run.csv') -Rows @($resolverArray | Where-Object { $_.processor -eq 'AssignmentExceptionDigest' })

$candidateArray = @($candidates.ToArray())
$workItemDuplicateGroups = @($workItems | Where-Object { -not [string]::IsNullOrWhiteSpace((Get-Prop -Row $_ -Name 'qfu_sourceexternalkey')) } | Group-Object qfu_sourceexternalkey | Where-Object { $_.Count -gt 1 })
$exceptionDuplicateGroups = @($assignmentExceptions | Where-Object { -not [string]::IsNullOrWhiteSpace((Get-Prop -Row $_ -Name 'qfu_exceptionkey')) } | Group-Object qfu_exceptionkey | Where-Object { $_.Count -gt 1 })

$summary = [ordered]@{
    environmentUrl = $EnvironmentUrl
    timestamp = (Get-Date).ToString('o')
    policy = [ordered]@{
        policyId = $policy.qfu_policyid
        policyKey = $policy.qfu_policykey
        alertMode = if ([int](Get-Prop -Row $policy -Name 'qfu_alertmode') -eq 985060001) { 'DryRunOnly' } else { [string](Get-Prop -Row $policy -Name 'qfu_alertmode') }
        digestEnabled = [bool](Get-Prop -Row $policy -Name 'qfu_digestenabled')
        targetedAlertEnabled = [bool](Get-Prop -Row $policy -Name 'qfu_targetedalertenabled')
        highValueThreshold = Get-Prop -Row $policy -Name 'qfu_highvaluethreshold'
        requiredAttempts = Get-Prop -Row $policy -Name 'qfu_requiredattempts'
        escalateAfterBusinessDays = Get-Prop -Row $policy -Name 'qfu_escalateafterbusinessdays'
    }
    liveCounts = [ordered]@{
        activeStaff = @($activeStaffRows).Count
        staffWithPrimaryEmail = @($activeStaffRows | Where-Object { Test-EmailFormat -Email ([string](Get-Prop -Row $_ -Name 'qfu_primaryemail')) }).Count
        staffMissingPrimaryEmail = @($activeStaffRows | Where-Object { -not (Test-EmailFormat -Email ([string](Get-Prop -Row $_ -Name 'qfu_primaryemail'))) }).Count
        activeBranchMemberships = @($membershipRows | Where-Object { Test-ActiveFlag (Get-Prop -Row $_ -Name 'qfu_active') }).Count
        managerMemberships = @($membershipRows | Where-Object { [int](Get-Prop -Row $_ -Name 'qfu_role') -eq $membershipRoleValues.Manager }).Count
        gmMemberships = @($membershipRows | Where-Object { [int](Get-Prop -Row $_ -Name 'qfu_role') -eq $membershipRoleValues.GM }).Count
        adminMemberships = @($membershipRows | Where-Object { [int](Get-Prop -Row $_ -Name 'qfu_role') -eq $membershipRoleValues.Admin }).Count
        activeWorkItems = @($workItems).Count
        dueTodayWorkItems = @($workItems | Where-Object { [int](Get-Prop -Row $_ -Name 'qfu_status') -eq $workItemStatusValues.DueToday }).Count
        overdueWorkItems = @($workItems | Where-Object { [int](Get-Prop -Row $_ -Name 'qfu_status') -eq $workItemStatusValues.Overdue }).Count
        roadblockWorkItems = @($workItems | Where-Object { [int](Get-Prop -Row $_ -Name 'qfu_status') -eq $workItemStatusValues.Roadblock }).Count
        missingAttemptsWorkItems = @($workItems | Where-Object { [int](Get-Prop -Row $_ -Name 'qfu_completedattempts') -lt [int](Get-Prop -Row $_ -Name 'qfu_requiredattempts') }).Count
        assignmentIssues = @($workItems | Where-Object { [int](Get-Prop -Row $_ -Name 'qfu_assignmentstatus') -ne $assignmentStatusValues.Assigned }).Count
        openAssignmentExceptions = @($assignmentExceptions).Count
    }
    alertCountsBefore = $alertCountsBefore
    alertCountsAfter = $alertCountsAfter
    candidates = [ordered]@{
        total = @($candidateArray).Count
        alertDispatcher = @($candidateArray | Where-Object { $_.processor -eq 'AlertDispatcher' }).Count
        staffDigest = @($candidateArray | Where-Object { $_.processor -eq 'DailyStaffDigest' }).Count
        managerDigest = @($candidateArray | Where-Object { $_.processor -eq 'ManagerDigest' }).Count
        escalation = @($candidateArray | Where-Object { $_.processor -eq 'EscalationProcessor' }).Count
        assignmentExceptionDigest = @($candidateArray | Where-Object { $_.processor -eq 'AssignmentExceptionDigest' }).Count
    }
    firstRun = [ordered]@{
        created = @($firstRun | Where-Object { $_.action -eq 'created' }).Count
        existing = @($firstRun | Where-Object { $_.action -eq 'existing' }).Count
        failed = @($firstRun | Where-Object { $_.action -eq 'failed' }).Count
    }
    secondRun = [ordered]@{
        created = @($secondRun | Where-Object { $_.action -eq 'created' }).Count
        existing = @($secondRun | Where-Object { $_.action -eq 'existing' }).Count
        failed = @($secondRun | Where-Object { $_.action -eq 'failed' }).Count
        duplicateSuppressionPassed = (@($secondRun | Where-Object { $_.action -eq 'created' }).Count -eq 0)
    }
    resolver = [ordered]@{
        resolvedWithEmail = @($resolverArray | Where-Object { $_.runName -eq 'first' -and $_.recipientEmailFound }).Count
        missingEmailOrStaff = @($resolverArray | Where-Object { $_.runName -eq 'first' -and -not $_.recipientEmailFound }).Count
    }
    sendValidation = [ordered]@{
        productionEmailsSent = 0
        teamsMessagesSent = 0
        liveDigestsSent = 0
        testRecipientSendTest = if ($AllowTestRecipientSend) { 'not-run-no-verified-recipient-configured-in-script' } else { 'skipped-no-verified-test-recipient' }
        noUnapprovedSends = ($alertCountsAfter.sent -eq $alertCountsBefore.sent)
    }
    duplicateChecks = [ordered]@{
        duplicateAlertDedupeKeys = $alertCountsAfter.duplicateDedupeKeys
        duplicateWorkItemSourceKeys = @($workItemDuplicateGroups).Count
        duplicateAssignmentExceptionKeys = @($exceptionDuplicateGroups).Count
    }
    outputFiles = @(
        'staff-email-readiness.csv',
        'missing-recipient-email-review.csv',
        'recipient-resolver-dry-run.csv',
        'alert-dispatcher-dry-run.csv',
        'staff-digest-dry-run.csv',
        'manager-digest-dry-run.csv',
        'escalation-dry-run.csv',
        'assignment-exception-digest-dry-run.csv'
    )
}

$summaryPath = Join-Path $OutputDir 'phase6-dry-run-summary.json'
$summary | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 100
