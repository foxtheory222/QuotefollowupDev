param(
    [string]$EnvironmentUrl = 'https://orga632edd5.crm3.dynamics.com',
    [string]$OutputDir = 'results\beta-release-candidate',
    [string]$BranchCode = '4171'
)

$ErrorActionPreference = 'Stop'

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

function Mask-Email {
    param([string]$Email)
    if ([string]::IsNullOrWhiteSpace($Email)) { return '' }
    $parts = $Email.Split('@', 2)
    if ($parts.Count -ne 2) { return 'invalid-format' }
    $local = $parts[0]
    $maskedLocal = if ($local.Length -le 1) { '*' } else { "$($local.Substring(0,1))***" }
    "$maskedLocal@$($parts[1])"
}

function Test-EmailFormat {
    param([string]$Email)
    if ([string]::IsNullOrWhiteSpace($Email)) { return $false }
    [bool]($Email -match '^[^@\s]+@[^@\s]+\.[^@\s]+$')
}

function Escape-ODataString {
    param([string]$Value)
    if ($null -eq $Value) { return '' }
    $Value.Replace("'", "''")
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

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

function Get-AllRows {
    param([string]$RelativeUrl)
    $rows = @()
    $url = "$EnvironmentUrl/api/data/v9.2/$RelativeUrl"
    do {
        $response = Invoke-RestMethod -Method Get -Uri $url -Headers $readHeaders
        $rows += @($response.value)
        $url = $response.'@odata.nextLink'
    } while ($url)
    $rows
}

$whoAmI = Invoke-DvGet 'WhoAmI()'
$currentUser = Invoke-DvGet "systemusers($($whoAmI.UserId))?`$select=systemuserid,fullname,internalemailaddress,domainname,isdisabled"

$systemUsers = Get-AllRows "systemusers?`$select=systemuserid,fullname,internalemailaddress,domainname,employeeid,azureactivedirectoryobjectid,isdisabled&`$filter=isdisabled eq false"
$testUserPatterns = @('QFU Test','qfu-test','QFU Beta','beta qfu','Test Staff','Test Manager','Test Admin','Test GM','No Access','NoAccess')
$testUsers = @($systemUsers | Where-Object {
    $text = "$($_.fullname) $($_.internalemailaddress) $($_.domainname)"
    foreach ($pattern in $testUserPatterns) {
        if ($text -like "*$pattern*") { return $true }
    }
    return $false
})

$staffRows = Get-AllRows "qfu_staffs?`$select=qfu_staffid,qfu_name,qfu_staffnumber,qfu_primaryemail,_qfu_systemuser_value,qfu_active,statecode,qfu_notes"
$testStaff = @($staffRows | Where-Object {
    $text = "$($_.qfu_name) $($_.qfu_staffnumber) $($_.qfu_primaryemail) $($_.qfu_notes)"
    foreach ($pattern in $testUserPatterns) {
        if ($text -like "*$pattern*") { return $true }
    }
    return $false
})

$branchRows = Get-AllRows "qfu_branchs?`$select=qfu_branchid,qfu_name,qfu_branchcode,statecode&`$filter=qfu_branchcode eq '$(Escape-ODataString $BranchCode)' or qfu_name eq '$(Escape-ODataString $BranchCode)'"
$branch = @($branchRows | Select-Object -First 1)
$branchId = if ($branch) { [string]$branch.qfu_branchid } else { '' }

$membershipRows = Get-AllRows "qfu_branchmemberships?`$select=qfu_branchmembershipid,qfu_name,qfu_role,statecode,_qfu_staff_value,_qfu_branch_value,qfu_notes"
$testStaffIds = @($testStaff | ForEach-Object { [string]$_.qfu_staffid })
$testMemberships = @($membershipRows | Where-Object {
    $staffId = [string](Get-Prop -Row $_ -Name '_qfu_staff_value')
    $notes = [string]$_.qfu_notes
    $name = [string]$_.qfu_name
    ($testStaffIds -contains $staffId) -or $notes -like '*beta test*' -or $name -like '*QFU Test*'
})

$roleRows = Get-AllRows "roles?`$select=roleid,name,businessunitid&`$filter=startswith(name,'QFU ')"
$teamRows = Get-AllRows "teams?`$select=teamid,name,businessunitid,teamtype&`$filter=startswith(name,'QFU Branch')"

$rolePrivilegeRows = @()
foreach ($role in $roleRows) {
    try {
        $roleId = [string]$role.roleid
        $privileges = Get-AllRows "roleprivilegescollection?`$select=roleprivilegeid,privilegedepthmask&`$filter=roleid eq $roleId"
        $rolePrivilegeRows += [pscustomobject]@{
            roleName       = $role.name
            roleId         = $roleId
            privilegeCount = @($privileges).Count
        }
    }
    catch {
        $rolePrivilegeRows += [pscustomobject]@{
            roleName       = $role.name
            roleId         = [string]$role.roleid
            privilegeCount = $null
            error          = $_.Exception.Message
        }
    }
}

$alertLogs = Get-AllRows "qfu_alertlogs?`$select=qfu_alertlogid,qfu_status,qfu_dedupekey,qfu_recipientemail,qfu_alerttype,statecode,qfu_notes"
$workItems = Get-AllRows "qfu_workitems?`$select=qfu_workitemid,qfu_sourceexternalkey,statecode,qfu_status,qfu_currentqueueroletext"
$assignmentExceptions = Get-AllRows "qfu_assignmentexceptions?`$select=qfu_assignmentexceptionid,qfu_exceptionkey,statecode"
$staffAliases = Get-AllRows "qfu_staffaliases?`$select=qfu_staffaliasid,qfu_normalizedalias,qfu_rawalias,qfu_aliastype,statecode,_qfu_staff_value,_qfu_branch_value"

$duplicateWorkItemKeys = @($workItems |
    Where-Object { $_.statecode -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$_.qfu_sourceexternalkey) } |
    Group-Object qfu_sourceexternalkey |
    Where-Object { $_.Count -gt 1 })
$duplicateExceptionKeys = @($assignmentExceptions |
    Where-Object { $_.statecode -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$_.qfu_exceptionkey) } |
    Group-Object qfu_exceptionkey |
    Where-Object { $_.Count -gt 1 })
$duplicateAlertKeys = @($alertLogs |
    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.qfu_dedupekey) } |
    Group-Object qfu_dedupekey |
    Where-Object { $_.Count -gt 1 })
$duplicateAliasKeys = @($staffAliases |
    Where-Object { $_.statecode -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$_.qfu_normalizedalias) } |
    Group-Object { "$($_.qfu_normalizedalias)|$($_.qfu_aliastype)|$((Get-Prop -Row $_ -Name '_qfu_branch_value'))" } |
    Where-Object { $_.Count -gt 1 })

$testUserReport = @($testUsers | ForEach-Object {
    [pscustomobject]@{
        systemUserId   = $_.systemuserid
        displayName    = if ([string]::IsNullOrWhiteSpace([string]$_.fullname)) { 'not-populated' } else { $_.fullname }
        emailMasked    = Mask-Email ([string]$_.internalemailaddress)
        hasEmail       = Test-EmailFormat ([string]$_.internalemailaddress)
        hasDomainName  = -not [string]::IsNullOrWhiteSpace([string]$_.domainname)
        hasEmployeeId  = -not [string]::IsNullOrWhiteSpace([string]$_.employeeid)
        hasEntraObject = -not [string]::IsNullOrWhiteSpace([string]$_.azureactivedirectoryobjectid)
        disabled       = [bool]$_.isdisabled
    }
})

$testStaffReport = @($testStaff | ForEach-Object {
    [pscustomobject]@{
        staffId         = $_.qfu_staffid
        staffName       = $_.qfu_name
        staffNumber     = $_.qfu_staffnumber
        emailMasked     = Mask-Email ([string]$_.qfu_primaryemail)
        hasEmail        = Test-EmailFormat ([string]$_.qfu_primaryemail)
        hasSystemUser   = -not [string]::IsNullOrWhiteSpace([string](Get-Prop -Row $_ -Name '_qfu_systemuser_value'))
        active          = [bool]$_.qfu_active
        notesHasBetaTag = ([string]$_.qfu_notes) -like '*beta*'
    }
})

$membershipReport = @($testMemberships | ForEach-Object {
    $membership = $_
    $roleValue = [int]$membership.qfu_role
    $roleName = ($membershipRoleValues.GetEnumerator() | Where-Object { $_.Value -eq $roleValue } | Select-Object -First 1).Key
    [pscustomobject]@{
        membershipId = $membership.qfu_branchmembershipid
        name         = $membership.qfu_name
        role         = if ($roleName) { $roleName } else { "Unknown-$($membership.qfu_role)" }
        staffId      = Get-Prop -Row $membership -Name '_qfu_staff_value'
        branchId     = Get-Prop -Row $membership -Name '_qfu_branch_value'
        active       = $membership.statecode -eq 0
        betaTagged   = ([string]$membership.qfu_notes) -like '*beta*'
    }
})

$testUserReport | Export-Csv -NoTypeInformation -Encoding UTF8 -Path (Join-Path $OutputDir 'beta-test-systemuser-discovery.csv')
$testStaffReport | Export-Csv -NoTypeInformation -Encoding UTF8 -Path (Join-Path $OutputDir 'beta-test-staff-discovery.csv')
$membershipReport | Export-Csv -NoTypeInformation -Encoding UTF8 -Path (Join-Path $OutputDir 'beta-test-membership-discovery.csv')
$rolePrivilegeRows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path (Join-Path $OutputDir 'beta-security-role-privilege-counts.csv')

$accountSetupRequired = @"
# Account Setup Required

Status: Required unless real test accounts already exist outside the current Dataverse discovery.

No complete set of separate QFU beta test personas was verified in Dataverse.

Required accounts:

| Persona | Required user | Required access |
| --- | --- | --- |
| QFU Test Staff | qfu-test-staff | Power Apps/Dataverse access, QFU Staff role, branch 4171 TSR or CSSR membership |
| QFU Test Manager | qfu-test-manager | Power Apps/Dataverse access, QFU Manager role, branch 4171 Manager membership |
| QFU Test Admin | qfu-test-admin | Power Apps/Dataverse access, QFU Admin role, Admin membership |
| QFU Test No Access | qfu-test-noaccess | No QFU app role or no QFU branch membership |
| QFU Test GM | qfu-test-gm | Optional; QFU GM role and branch 4171 GM membership |

Rules:

- Do not use name-only matches for production identity.
- Use verified tenant email/domainname and active Dataverse systemuser rows.
- Do not share or store passwords in this repository or audit.
- Do not enable Live alert mode for beta validation.
- Configure TestRecipientOnly only after a verified test mailbox exists.
"@
Set-Content -Encoding UTF8 -Path (Join-Path $OutputDir 'ACCOUNT_SETUP_REQUIRED.md') -Value $accountSetupRequired

$sentAlertLogs = @($alertLogs | Where-Object { [int]$_.qfu_status -eq 985010001 })
$failedAlertLogs = @($alertLogs | Where-Object { [int]$_.qfu_status -eq 985010002 })

$summary = [pscustomobject]@{
    timestamp = (Get-Date).ToString('o')
    environmentUrl = $EnvironmentUrl
    currentUser = [pscustomobject]@{
        systemUserId = $currentUser.systemuserid
        emailMasked = Mask-Email ([string]$currentUser.internalemailaddress)
    }
    branchCode = $BranchCode
    branchFound = [bool]$branch
    branchId = $branchId
    testAccounts = [pscustomobject]@{
        systemUsersFound = @($testUserReport).Count
        staffRowsFound = @($testStaffReport).Count
        membershipsFound = @($membershipReport).Count
        completePersonaSetFound = $false
    }
    security = [pscustomobject]@{
        qfuRolesFound = @($roleRows).Count
        qfuTeamsFound = @($teamRows).Count
        rolePrivilegeCounts = $rolePrivilegeRows
        rolePrivilegesPresent = @($rolePrivilegeRows | Where-Object { $_.privilegeCount -gt 0 }).Count -eq @($roleRows).Count -and @($roleRows).Count -ge 5
        privilegesAppliedEnoughForBeta = $false
        privilegesValidationNote = 'Privilege rows are present, but beta least-privilege validation requires separate role-specific users and cannot be accepted from counts alone.'
    }
    counts = [pscustomobject]@{
        activeWorkItems = @($workItems | Where-Object { $_.statecode -eq 0 }).Count
        sentAlertLogs = @($sentAlertLogs).Count
        failedAlertLogs = @($failedAlertLogs).Count
        duplicateAlertDedupeKeys = @($duplicateAlertKeys).Count
        duplicateWorkItemSourceKeys = @($duplicateWorkItemKeys).Count
        duplicateAssignmentExceptionKeys = @($duplicateExceptionKeys).Count
        duplicateActiveAliasKeys = @($duplicateAliasKeys).Count
    }
    betaReady = $false
    blockers = @(
        'Separate QFU beta test accounts were not verified as a complete persona set.',
        'Tenant/user creation requires admin approval if accounts are missing.',
        'QFU security role privileges must be approved and validated with role-specific users.',
        'TestRecipientOnly requires a verified test mailbox and controlled send approval.'
    )
}

$summary | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 -Path (Join-Path $OutputDir 'beta-readiness-summary.json')
$summary | ConvertTo-Json -Depth 20
