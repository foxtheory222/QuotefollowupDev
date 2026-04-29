param(
    [string]$EnvironmentUrl = 'https://orga632edd5.crm3.dynamics.com',
    [string]$SolutionUniqueName = 'qfu_revenuefollowupworkbench',
    [string]$OutputDir = 'results\phase7',
    [switch]$EnableDevCurrentUserAdminMapping
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

function Normalize-Text {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    ($Value.ToUpperInvariant() -replace '[^A-Z0-9]', '')
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

function Escape-ODataString {
    param([string]$Value)
    if ($null -eq $Value) { return '' }
    $Value.Replace("'", "''")
}

function New-SafeLabel {
    param([string]$Prefix, [int]$Index)
    "$Prefix-$('{0:d3}' -f $Index)"
}

function Append-Note {
    param([string]$Existing, [string]$Note)
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz')
    $line = "[$stamp] $Note"
    if ([string]::IsNullOrWhiteSpace($Existing)) { return $line }
    if ($Existing -like "*$Note*") { return $Existing }
    "$Existing`n$line"
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
    $rows
}

function Add-ComponentToSolution {
    param([int]$ComponentType, [guid]$ComponentId)
    try {
        Invoke-DvPost 'AddSolutionComponent' @{
            ComponentType             = $ComponentType
            ComponentId               = $ComponentId
            SolutionUniqueName        = $SolutionUniqueName
            AddRequiredComponents     = $true
            DoNotIncludeSubcomponents = $false
        } | Out-Null
        return $true
    }
    catch { return $false }
}

function New-LayoutXml {
    param([string]$EntityName, [int]$ObjectTypeCode, [string]$PrimaryId, [string[]]$Columns)
    $cells = ""
    foreach ($column in $Columns) { $cells += "<cell name=`"$column`" width=`"180`" />" }
    "<grid name=`"resultset`" object=`"$ObjectTypeCode`" jump=`"qfu_name`" select=`"1`" icon=`"1`" preview=`"1`"><row name=`"result`" id=`"$PrimaryId`">$cells</row></grid>"
}

function Ensure-View {
    param(
        [string]$Table,
        [string]$ViewName,
        [string[]]$Columns,
        [string]$FilterXml = '',
        [string]$OrderColumn = 'createdon'
    )

    $metadata = Invoke-DvGet "EntityDefinitions(LogicalName='$Table')?`$select=ObjectTypeCode,PrimaryIdAttribute,PrimaryNameAttribute"
    $escapedName = Escape-ODataString $ViewName
    $existing = Get-AllRows "savedqueries?`$select=savedqueryid,name,returnedtypecode,querytype&`$filter=returnedtypecode eq '$Table' and querytype eq 0 and name eq '$escapedName'&`$top=1" | Select-Object -First 1
    $attributeXml = ""
    foreach ($column in @($metadata.PrimaryIdAttribute) + $Columns) {
        if (-not [string]::IsNullOrWhiteSpace($column)) { $attributeXml += "<attribute name=`"$column`" />" }
    }
    $fetchXml = "<fetch version=`"1.0`" mapping=`"logical`"><entity name=`"$Table`">$attributeXml$FilterXml<order attribute=`"$OrderColumn`" descending=`"false`" /></entity></fetch>"
    $layoutXml = New-LayoutXml -EntityName $Table -ObjectTypeCode ([int]$metadata.ObjectTypeCode) -PrimaryId $metadata.PrimaryIdAttribute -Columns $Columns
    $body = @{
        name = $ViewName
        returnedtypecode = $Table
        querytype = 0
        isdefault = $false
        isquickfindquery = $false
        fetchxml = $fetchXml
        layoutxml = $layoutXml
    }

    if ($existing) {
        Invoke-DvPatchNoContent "savedqueries($($existing.savedqueryid))" $body
        $viewId = $existing.savedqueryid
        $status = 'updated'
    }
    else {
        $created = Invoke-DvPost 'savedqueries' $body
        $viewId = $created.savedqueryid
        if (-not $viewId) {
            $reloaded = Get-AllRows "savedqueries?`$select=savedqueryid,name,returnedtypecode,querytype&`$filter=returnedtypecode eq '$Table' and querytype eq 0 and name eq '$escapedName'&`$top=1" | Select-Object -First 1
            if ($reloaded) { $viewId = $reloaded.savedqueryid }
        }
        $status = 'created'
    }

    [pscustomobject]@{
        table = $Table
        viewName = $ViewName
        savedqueryid = $viewId
        status = $status
        addedToSolution = if ($viewId) { Add-ComponentToSolution -ComponentType 26 -ComponentId ([guid]$viewId) } else { $false }
    }
}

$solution = Get-AllRows "solutions?`$select=solutionid,uniquename,friendlyname&`$filter=uniquename eq '$SolutionUniqueName'&`$top=1" | Select-Object -First 1
if (-not $solution) { throw "Solution '$SolutionUniqueName' was not found in $EnvironmentUrl." }

$whoAmI = Invoke-DvGet 'WhoAmI()'
$currentUser = Invoke-DvGet "systemusers($($whoAmI.UserId))?`$select=systemuserid,fullname,internalemailaddress,domainname,employeeid,azureactivedirectoryobjectid,isdisabled,_businessunitid_value"

$systemUsers = Get-AllRows "systemusers?`$select=systemuserid,fullname,internalemailaddress,domainname,employeeid,azureactivedirectoryobjectid,isdisabled,accessmode,_businessunitid_value&`$filter=isdisabled eq false"
$staffRows = Get-AllRows "qfu_staffs?`$select=qfu_staffid,qfu_name,qfu_staffnumber,qfu_primaryemail,qfu_entraobjectid,_qfu_systemuser_value,qfu_active,statecode,qfu_notes&`$filter=statecode eq 0"
$membershipRows = Get-AllRows "qfu_branchmemberships?`$select=qfu_branchmembershipid,qfu_name,qfu_role,qfu_active,qfu_isprimary,_qfu_branch_value,_qfu_staff_value,statecode,qfu_notes&`$filter=statecode eq 0"
$branches = Get-AllRows "qfu_branchs?`$select=qfu_branchid,qfu_name,qfu_branchcode,statecode&`$filter=statecode eq 0"

$systemUserReadiness = New-Object System.Collections.Generic.List[object]
$userIndex = 0
foreach ($user in $systemUsers) {
    $userIndex++
    $systemUserReadiness.Add([pscustomobject]@{
        userLabel = New-SafeLabel -Prefix 'SystemUser' -Index $userIndex
        systemUserId = $user.systemuserid
        hasEmail = [bool](Test-EmailFormat ([string]$user.internalemailaddress))
        hasDomainName = -not [string]::IsNullOrWhiteSpace([string]$user.domainname)
        hasEmployeeId = -not [string]::IsNullOrWhiteSpace([string]$user.employeeid)
        hasEntraObjectId = -not [string]::IsNullOrWhiteSpace([string]$user.azureactivedirectoryobjectid)
        disabled = [bool]$user.isdisabled
        candidateNotes = 'Readiness only; raw names and emails intentionally excluded.'
    }) | Out-Null
}

$usersByEmail = @{}
$usersByDomain = @{}
$usersByEmployee = @{}
$usersByEntra = @{}
$usersByName = @{}
foreach ($user in $systemUsers) {
    foreach ($email in @([string]$user.internalemailaddress, [string]$user.domainname)) {
        if (-not [string]::IsNullOrWhiteSpace($email)) {
            $key = $email.Trim().ToLowerInvariant()
            if (-not $usersByEmail.ContainsKey($key)) { $usersByEmail[$key] = @() }
            $usersByEmail[$key] += $user
        }
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$user.domainname)) {
        $key = ([string]$user.domainname).Trim().ToLowerInvariant()
        if (-not $usersByDomain.ContainsKey($key)) { $usersByDomain[$key] = @() }
        $usersByDomain[$key] += $user
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$user.employeeid)) {
        $key = ([string]$user.employeeid).Trim().ToUpperInvariant()
        if (-not $usersByEmployee.ContainsKey($key)) { $usersByEmployee[$key] = @() }
        $usersByEmployee[$key] += $user
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$user.azureactivedirectoryobjectid)) {
        $key = ([string]$user.azureactivedirectoryobjectid).Trim().ToLowerInvariant()
        if (-not $usersByEntra.ContainsKey($key)) { $usersByEntra[$key] = @() }
        $usersByEntra[$key] += $user
    }
    $nameKey = Normalize-Text ([string]$user.fullname)
    if (-not [string]::IsNullOrWhiteSpace($nameKey)) {
        if (-not $usersByName.ContainsKey($nameKey)) { $usersByName[$nameKey] = @() }
        $usersByName[$nameKey] += $user
    }
}

$staffById = @{}
foreach ($staff in $staffRows) { $staffById[[string]$staff.qfu_staffid] = $staff }

$matchRows = New-Object System.Collections.Generic.List[object]
$updates = New-Object System.Collections.Generic.List[object]

foreach ($staff in $staffRows) {
    $staffId = [string]$staff.qfu_staffid
    $staffEmail = [string]$staff.qfu_primaryemail
    $staffEntra = [string]$staff.qfu_entraobjectid
    $staffNumber = [string]$staff.qfu_staffnumber
    $classification = 'NoMatch'
    $matchMethod = ''
    $matchedUsers = @()
    $productionVerified = $false
    $notes = ''

    if (-not [string]::IsNullOrWhiteSpace($staffEmail)) {
        $key = $staffEmail.Trim().ToLowerInvariant()
        if ($usersByEmail.ContainsKey($key)) {
            $matchedUsers = @($usersByEmail[$key])
            if ($matchedUsers.Count -eq 1) {
                $classification = 'AutoLinkedExactEmail'
                $matchMethod = 'qfu_primaryemail'
                $productionVerified = $true
            }
            else { $classification = 'Ambiguous'; $matchMethod = 'qfu_primaryemail' }
        }
    }
    if ($classification -eq 'NoMatch' -and -not [string]::IsNullOrWhiteSpace($staffEntra)) {
        $key = $staffEntra.Trim().ToLowerInvariant()
        if ($usersByEntra.ContainsKey($key)) {
            $matchedUsers = @($usersByEntra[$key])
            if ($matchedUsers.Count -eq 1) {
                $classification = 'AutoLinkedExactEntra'
                $matchMethod = 'qfu_entraobjectid'
                $productionVerified = $true
            }
            else { $classification = 'Ambiguous'; $matchMethod = 'qfu_entraobjectid' }
        }
    }
    if ($classification -eq 'NoMatch' -and -not [string]::IsNullOrWhiteSpace($staffNumber)) {
        $key = $staffNumber.Trim().ToUpperInvariant()
        if ($usersByEmployee.ContainsKey($key)) {
            $matchedUsers = @($usersByEmployee[$key])
            if ($matchedUsers.Count -eq 1) {
                $classification = 'AutoLinkedExactEmployeeId'
                $matchMethod = 'qfu_staffnumber-to-employeeid'
                $productionVerified = $true
            }
            else { $classification = 'Ambiguous'; $matchMethod = 'qfu_staffnumber-to-employeeid' }
        }
    }
    if ($classification -eq 'NoMatch') {
        $nameKey = Normalize-Text ([string]$staff.qfu_name)
        if (-not [string]::IsNullOrWhiteSpace($nameKey) -and $usersByName.ContainsKey($nameKey)) {
            $matchedUsers = @($usersByName[$nameKey])
            if ($matchedUsers.Count -eq 1) {
                $classification = 'CandidateHighConfidenceNameOnly'
                $matchMethod = 'name-only'
                $notes = 'Candidate only; not production-verified.'
            }
            else {
                $classification = 'Ambiguous'
                $matchMethod = 'name-only'
                $notes = 'Multiple active systemusers match normalized staff name.'
            }
        }
    }

    $matchedUser = $matchedUsers | Select-Object -First 1
    if ($productionVerified -and $matchedUser) {
        $body = @{
            'qfu_SystemUser@odata.bind' = "/systemusers($($matchedUser.systemuserid))"
            qfu_primaryemail = [string]$matchedUser.internalemailaddress
            qfu_notes = Append-Note -Existing ([string]$staff.qfu_notes) -Note "Phase 7 exact identity mapping via $matchMethod."
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$matchedUser.azureactivedirectoryobjectid)) {
            $body.qfu_entraobjectid = [string]$matchedUser.azureactivedirectoryobjectid
        }
        Invoke-DvPatchNoContent "qfu_staffs($staffId)" $body
        $updates.Add([pscustomobject]@{
            staffId = $staffId
            staffNumber = $staffNumber
            updateType = $classification
            systemUserLinked = $true
            emailSetMasked = Mask-Email ([string]$matchedUser.internalemailaddress)
            productionVerified = $true
            notes = "Exact mapping via $matchMethod."
        }) | Out-Null
    }

    $matchRows.Add([pscustomobject]@{
        staffId = $staffId
        staffNumber = $staffNumber
        staffEmailMasked = Mask-Email $staffEmail
        existingSystemUser = -not [string]::IsNullOrWhiteSpace([string](Get-Prop -Row $staff -Name '_qfu_systemuser_value'))
        classification = $classification
        matchMethod = $matchMethod
        matchedSystemUserId = if ($matchedUser) { [string]$matchedUser.systemuserid } else { '' }
        matchedEmailMasked = if ($matchedUser) { Mask-Email ([string]$matchedUser.internalemailaddress) } else { '' }
        productionVerified = $productionVerified
        notes = $notes
    }) | Out-Null
}

$devMapping = [ordered]@{
    enabled = [bool]$EnableDevCurrentUserAdminMapping
    status = 'not-requested'
    currentSystemUserId = [string]$currentUser.systemuserid
    currentUserEmailMasked = Mask-Email ([string]$currentUser.internalemailaddress)
    staffId = $null
    branchId = $null
    adminMembershipId = $null
    message = ''
}

if ($EnableDevCurrentUserAdminMapping) {
    $nameKey = Normalize-Text ([string]$currentUser.fullname)
    $candidateStaff = @($staffRows | Where-Object { (Normalize-Text ([string]$_.qfu_name)) -eq $nameKey })
    $branch4171 = @($branches | Where-Object { ([string]$_.qfu_branchcode) -eq '4171' -or ([string]$_.qfu_name) -like '*4171*' }) | Select-Object -First 1
    if ($candidateStaff.Count -eq 1 -and $branch4171) {
        $staff = $candidateStaff[0]
        $staffId = [string]$staff.qfu_staffid
        $devNote = 'PHASE7 DEV-ONLY CandidateHighConfidenceNameOnly current maker mapping; not production-verified.'
        $body = @{
            'qfu_SystemUser@odata.bind' = "/systemusers($($currentUser.systemuserid))"
            qfu_primaryemail = [string]$currentUser.internalemailaddress
            qfu_notes = Append-Note -Existing ([string]$staff.qfu_notes) -Note $devNote
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$currentUser.azureactivedirectoryobjectid)) {
            $body.qfu_entraobjectid = [string]$currentUser.azureactivedirectoryobjectid
        }
        Invoke-DvPatchNoContent "qfu_staffs($staffId)" $body

        $existingAdmin = @($membershipRows | Where-Object {
            ([string](Get-Prop -Row $_ -Name '_qfu_staff_value')) -eq $staffId -and
            ([string](Get-Prop -Row $_ -Name '_qfu_branch_value')) -eq ([string]$branch4171.qfu_branchid) -and
            [int]$_.qfu_role -eq $membershipRoleValues.Admin
        }) | Select-Object -First 1

        if ($existingAdmin) {
            $adminMembershipId = [string]$existingAdmin.qfu_branchmembershipid
            $membershipBody = @{
                qfu_active = $true
                qfu_notes = Append-Note -Existing ([string]$existingAdmin.qfu_notes) -Note 'PHASE7 DEV-ONLY Admin membership for current maker validation; not production security.'
            }
            Invoke-DvPatchNoContent "qfu_branchmemberships($adminMembershipId)" $membershipBody
            $membershipStatus = 'updated-existing'
        }
        else {
            $createBody = @{
                qfu_name = 'DEV-ONLY 4171 Admin current maker'
                qfu_role = $membershipRoleValues.Admin
                qfu_active = $true
                qfu_isprimary = $false
                qfu_notes = 'PHASE7 DEV-ONLY Admin membership for current maker validation; not production security.'
                'qfu_Staff@odata.bind' = "/qfu_staffs($staffId)"
                'qfu_Branch@odata.bind' = "/qfu_branchs($($branch4171.qfu_branchid))"
            }
            $created = Invoke-DvPost 'qfu_branchmemberships' $createBody
            $adminMembershipId = [string]$created.qfu_branchmembershipid
            if (-not $adminMembershipId) {
                $reload = Get-AllRows "qfu_branchmemberships?`$select=qfu_branchmembershipid,qfu_name,qfu_role,_qfu_staff_value,_qfu_branch_value&`$filter=_qfu_staff_value eq $staffId and _qfu_branch_value eq $($branch4171.qfu_branchid) and qfu_role eq $($membershipRoleValues.Admin)&`$top=1" | Select-Object -First 1
                if ($reload) { $adminMembershipId = [string]$reload.qfu_branchmembershipid }
            }
            $membershipStatus = 'created'
        }

        $updates.Add([pscustomobject]@{
            staffId = $staffId
            staffNumber = [string]$staff.qfu_staffnumber
            updateType = 'DevOnlyCurrentMakerAdminMapping'
            systemUserLinked = $true
            emailSetMasked = Mask-Email ([string]$currentUser.internalemailaddress)
            productionVerified = $false
            notes = "Dev-only current maker mapping and 4171 Admin membership $membershipStatus."
        }) | Out-Null

        $devMapping.status = 'completed-dev-only'
        $devMapping.staffId = $staffId
        $devMapping.branchId = [string]$branch4171.qfu_branchid
        $devMapping.adminMembershipId = $adminMembershipId
        $devMapping.message = 'Created/updated dev-only current maker staff mapping and Admin membership. Not production-verified.'
    }
    else {
        $devMapping.status = 'blocked'
        $devMapping.message = "Could not safely create dev-only mapping. CandidateStaffCount=$($candidateStaff.Count); Branch4171Found=$([bool]$branch4171)."
    }
}

$membershipRowsAfter = Get-AllRows "qfu_branchmemberships?`$select=qfu_branchmembershipid,qfu_name,qfu_role,qfu_active,qfu_isprimary,_qfu_branch_value,_qfu_staff_value,statecode,qfu_notes&`$filter=statecode eq 0"
$staffRowsAfter = Get-AllRows "qfu_staffs?`$select=qfu_staffid,qfu_name,qfu_staffnumber,qfu_primaryemail,_qfu_systemuser_value,qfu_active,statecode&`$filter=statecode eq 0"
$staffAfterById = @{}
foreach ($staff in $staffRowsAfter) { $staffAfterById[[string]$staff.qfu_staffid] = $staff }

$membershipReview = New-Object System.Collections.Generic.List[object]
foreach ($membership in $membershipRowsAfter) {
    $roleName = ($membershipRoleValues.GetEnumerator() | Where-Object { $_.Value -eq [int]$membership.qfu_role } | Select-Object -First 1).Key
    if (-not $roleName) { $roleName = "Unknown-$($membership.qfu_role)" }
    if ($roleName -in @('Manager','GM','Admin')) {
        $staff = $staffAfterById[[string](Get-Prop -Row $membership -Name '_qfu_staff_value')]
        $membershipReview.Add([pscustomobject]@{
            membershipId = $membership.qfu_branchmembershipid
            role = $roleName
            branchId = [string](Get-Prop -Row $membership -Name '_qfu_branch_value')
            staffId = [string](Get-Prop -Row $membership -Name '_qfu_staff_value')
            devOnly = ([string]$membership.qfu_notes) -like '*DEV-ONLY*'
            hasEmail = if ($staff) { Test-EmailFormat ([string]$staff.qfu_primaryemail) } else { $false }
            hasSystemUser = if ($staff) { -not [string]::IsNullOrWhiteSpace([string](Get-Prop -Row $staff -Name '_qfu_systemuser_value')) } else { $false }
            action = if (([string]$membership.qfu_notes) -like '*DEV-ONLY*') { 'Dev fallback only' } else { 'Existing production candidate membership requires human verification' }
        }) | Out-Null
    }
}

$importTemplate = @(
    [pscustomobject]@{
        qfu_branchcode = ''
        qfu_role = 'Manager|GM|Admin'
        qfu_staffnumber = ''
        qfu_isprimary = ''
        qfu_notes = 'Human-verified membership source required.'
        verifiedBy = ''
        verifiedOn = ''
    }
)

$views = @()
$views += Ensure-View -Table 'qfu_staff' -ViewName 'Staff Linked to System User' -Columns @('qfu_name','qfu_staffnumber','qfu_primaryemail','qfu_systemuser','qfu_active') -FilterXml '<filter type="and"><condition attribute="statecode" operator="eq" value="0" /><condition attribute="qfu_systemuser" operator="not-null" /></filter>' -OrderColumn 'qfu_name'
$views += Ensure-View -Table 'qfu_staff' -ViewName 'Staff Missing System User' -Columns @('qfu_name','qfu_staffnumber','qfu_primaryemail','qfu_systemuser','qfu_active') -FilterXml '<filter type="and"><condition attribute="statecode" operator="eq" value="0" /><condition attribute="qfu_systemuser" operator="null" /></filter>' -OrderColumn 'qfu_name'
$views += Ensure-View -Table 'qfu_staff' -ViewName 'Staff With Email' -Columns @('qfu_name','qfu_staffnumber','qfu_primaryemail','qfu_systemuser','qfu_active') -FilterXml '<filter type="and"><condition attribute="statecode" operator="eq" value="0" /><condition attribute="qfu_primaryemail" operator="not-null" /></filter>' -OrderColumn 'qfu_name'
$views += Ensure-View -Table 'qfu_staff' -ViewName 'Staff Missing Email' -Columns @('qfu_name','qfu_staffnumber','qfu_primaryemail','qfu_systemuser','qfu_active') -FilterXml '<filter type="and"><condition attribute="statecode" operator="eq" value="0" /><condition attribute="qfu_primaryemail" operator="null" /></filter>' -OrderColumn 'qfu_name'
$views += Ensure-View -Table 'qfu_branchmembership' -ViewName 'Active Manager GM Admin Memberships' -Columns @('qfu_name','qfu_branch','qfu_staff','qfu_role','qfu_active','qfu_isprimary','qfu_notes') -FilterXml '<filter type="and"><condition attribute="statecode" operator="eq" value="0" /><condition attribute="qfu_role" operator="in"><value>100000002</value><value>100000003</value><value>100000004</value></condition></filter>' -OrderColumn 'qfu_name'

$staffRowsFinal = Get-AllRows "qfu_staffs?`$select=qfu_staffid,qfu_name,qfu_staffnumber,qfu_primaryemail,_qfu_systemuser_value,qfu_active,statecode&`$filter=statecode eq 0"
$activeStaffRowsFinal = @($staffRowsFinal | Where-Object { $_.qfu_active -ne $false })
$membershipRowsFinal = Get-AllRows "qfu_branchmemberships?`$select=qfu_branchmembershipid,qfu_role,statecode,qfu_active,_qfu_staff_value&`$filter=statecode eq 0"
$roleCounts = @{}
foreach ($role in $membershipRoleValues.Keys) {
    $roleCounts[$role] = @($membershipRowsFinal | Where-Object { [int]$_.qfu_role -eq $membershipRoleValues[$role] }).Count
}

$summary = [ordered]@{
    timestamp = (Get-Date).ToString('o')
    environmentUrl = $EnvironmentUrl
    solutionFound = [bool]$solution
    currentUser = @{
        systemUserId = [string]$currentUser.systemuserid
        emailMasked = Mask-Email ([string]$currentUser.internalemailaddress)
        hasEntraObjectId = -not [string]::IsNullOrWhiteSpace([string]$currentUser.azureactivedirectoryobjectid)
    }
    counts = @{
        activeSystemUsers = @($systemUsers).Count
        activeStaff = @($activeStaffRowsFinal).Count
        activeStaffWithEmail = @($activeStaffRowsFinal | Where-Object { Test-EmailFormat ([string]$_.qfu_primaryemail) }).Count
        activeStaffMissingEmail = @($activeStaffRowsFinal | Where-Object { -not (Test-EmailFormat ([string]$_.qfu_primaryemail)) }).Count
        activeStaffLinkedToSystemUser = @($activeStaffRowsFinal | Where-Object { -not [string]::IsNullOrWhiteSpace([string](Get-Prop -Row $_ -Name '_qfu_systemuser_value')) }).Count
        activeStaffMissingSystemUser = @($activeStaffRowsFinal | Where-Object { [string]::IsNullOrWhiteSpace([string](Get-Prop -Row $_ -Name '_qfu_systemuser_value')) }).Count
        statecodeZeroStaffWithEmail = @($staffRowsFinal | Where-Object { Test-EmailFormat ([string]$_.qfu_primaryemail) }).Count
        statecodeZeroStaffLinkedToSystemUser = @($staffRowsFinal | Where-Object { -not [string]::IsNullOrWhiteSpace([string](Get-Prop -Row $_ -Name '_qfu_systemuser_value')) }).Count
        managerMemberships = $roleCounts.Manager
        gmMemberships = $roleCounts.GM
        adminMemberships = $roleCounts.Admin
        devOnlyAdminMemberships = @($membershipReview | Where-Object { $_.role -eq 'Admin' -and $_.devOnly }).Count
    }
    exactProductionUpdates = @($updates | Where-Object { $_.productionVerified }).Count
    devOnlyUpdates = @($updates | Where-Object { -not $_.productionVerified }).Count
    devMapping = $devMapping
    views = $views
    securityRoleAction = 'No QFU security role privileges were created by this script; Phase 7 records the privilege model as a controlled security task.'
}

$systemUserReadiness | Export-Csv -NoTypeInformation -Path (Join-Path $OutputDir 'systemuser-readiness.csv')
$matchRows | Export-Csv -NoTypeInformation -Path (Join-Path $OutputDir 'staff-systemuser-match-review.csv')
$updates | Export-Csv -NoTypeInformation -Path (Join-Path $OutputDir 'staff-identity-updates.csv')
$membershipReview | Export-Csv -NoTypeInformation -Path (Join-Path $OutputDir 'manager-gm-admin-membership-review.csv')
$importTemplate | Export-Csv -NoTypeInformation -Path (Join-Path $OutputDir 'manager-gm-admin-import-template.csv')
$summary | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 -Path (Join-Path $OutputDir 'identity-security-readiness-summary.json')

$summary | ConvertTo-Json -Depth 20
