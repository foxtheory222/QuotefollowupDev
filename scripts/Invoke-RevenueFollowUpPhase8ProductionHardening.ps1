param(
    [string]$EnvironmentUrl = 'https://orga632edd5.crm3.dynamics.com',
    [string]$SolutionUniqueName = 'qfu_revenuefollowupworkbench',
    [string]$OutputDir = 'results\phase8',
    [switch]$CreateSecurityShells,
    [switch]$CreateBranchTeamShells
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

function Escape-ODataString {
    param([string]$Value)
    if ($null -eq $Value) { return '' }
    $Value.Replace("'", "''")
}

function Test-EmailFormat {
    param([string]$Email)
    if ([string]::IsNullOrWhiteSpace($Email)) { return $false }
    [bool]($Email -match '^[^@\s]+@[^@\s]+\.[^@\s]+$')
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
    param([string]$EntityName, [int]$ObjectTypeCode, [string]$PrimaryId, [string]$PrimaryName, [string[]]$Columns)
    $cells = ""
    foreach ($column in $Columns) { $cells += "<cell name=`"$column`" width=`"180`" />" }
    "<grid name=`"resultset`" object=`"$ObjectTypeCode`" jump=`"$PrimaryName`" select=`"1`" icon=`"1`" preview=`"1`"><row name=`"result`" id=`"$PrimaryId`">$cells</row></grid>"
}

function Ensure-View {
    param(
        [string]$Table,
        [string]$ViewName,
        [string[]]$Columns,
        [string]$FilterXml = '',
        [string]$OrderColumn = 'createdon'
    )

    try {
        $metadata = Invoke-DvGet "EntityDefinitions(LogicalName='$Table')?`$select=ObjectTypeCode,PrimaryIdAttribute,PrimaryNameAttribute"
        $escapedName = Escape-ODataString $ViewName
        $existing = Get-AllRows "savedqueries?`$select=savedqueryid,name,returnedtypecode,querytype&`$filter=returnedtypecode eq '$Table' and querytype eq 0 and name eq '$escapedName'&`$top=1" | Select-Object -First 1
        $attributeXml = ""
        foreach ($column in @($metadata.PrimaryIdAttribute) + $Columns) {
            if (-not [string]::IsNullOrWhiteSpace($column)) { $attributeXml += "<attribute name=`"$column`" />" }
        }
        $fetchXml = "<fetch version=`"1.0`" mapping=`"logical`"><entity name=`"$Table`">$attributeXml$FilterXml<order attribute=`"$OrderColumn`" descending=`"false`" /></entity></fetch>"
        $layoutXml = New-LayoutXml -EntityName $Table -ObjectTypeCode ([int]$metadata.ObjectTypeCode) -PrimaryId $metadata.PrimaryIdAttribute -PrimaryName $metadata.PrimaryNameAttribute -Columns $Columns
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
            failure = ''
        }
    }
    catch {
        [pscustomobject]@{
            table = $Table
            viewName = $ViewName
            savedqueryid = ''
            status = 'failed'
            addedToSolution = $false
            failure = $_.Exception.Message
        }
    }
}

function Ensure-RoleShell {
    param([string]$RoleName, [string]$BusinessUnitId)
    $escaped = Escape-ODataString $RoleName
    $existing = Get-AllRows "roles?`$select=roleid,name,_businessunitid_value&`$filter=name eq '$escaped' and _businessunitid_value eq $BusinessUnitId&`$top=1" | Select-Object -First 1
    if ($existing) {
        return [pscustomobject]@{ name = $RoleName; roleId = $existing.roleid; status = 'found'; addedToSolution = Add-ComponentToSolution -ComponentType 20 -ComponentId ([guid]$existing.roleid); failure = '' }
    }
    try {
        $created = Invoke-DvPost 'roles' @{
            name = $RoleName
            'businessunitid@odata.bind' = "/businessunits($BusinessUnitId)"
        }
        $roleId = [string]$created.roleid
        if (-not $roleId) {
            $reload = Get-AllRows "roles?`$select=roleid,name,_businessunitid_value&`$filter=name eq '$escaped' and _businessunitid_value eq $BusinessUnitId&`$top=1" | Select-Object -First 1
            if ($reload) { $roleId = [string]$reload.roleid }
        }
        [pscustomobject]@{ name = $RoleName; roleId = $roleId; status = 'created-shell'; addedToSolution = if ($roleId) { Add-ComponentToSolution -ComponentType 20 -ComponentId ([guid]$roleId) } else { $false }; failure = '' }
    }
    catch {
        [pscustomobject]@{ name = $RoleName; roleId = ''; status = 'failed'; addedToSolution = $false; failure = $_.Exception.Message }
    }
}

function Ensure-TeamShell {
    param([string]$TeamName, [string]$BusinessUnitId, [string]$AdminUserId)
    $escaped = Escape-ODataString $TeamName
    $existing = Get-AllRows "teams?`$select=teamid,name,_businessunitid_value&`$filter=name eq '$escaped' and _businessunitid_value eq $BusinessUnitId&`$top=1" | Select-Object -First 1
    if ($existing) {
        return [pscustomobject]@{ name = $TeamName; teamId = $existing.teamid; status = 'found'; addedToSolution = Add-ComponentToSolution -ComponentType 9 -ComponentId ([guid]$existing.teamid); failure = '' }
    }
    try {
        $created = Invoke-DvPost 'teams' @{
            name = $TeamName
            teamtype = 0
            description = 'QFU Phase 8 branch owner-team shell. Privileges and membership pending final approval.'
            'businessunitid@odata.bind' = "/businessunits($BusinessUnitId)"
            'administratorid@odata.bind' = "/systemusers($AdminUserId)"
        }
        $teamId = [string]$created.teamid
        if (-not $teamId) {
            $reload = Get-AllRows "teams?`$select=teamid,name,_businessunitid_value&`$filter=name eq '$escaped' and _businessunitid_value eq $BusinessUnitId&`$top=1" | Select-Object -First 1
            if ($reload) { $teamId = [string]$reload.teamid }
        }
        [pscustomobject]@{ name = $TeamName; teamId = $teamId; status = 'created-shell'; addedToSolution = if ($teamId) { Add-ComponentToSolution -ComponentType 9 -ComponentId ([guid]$teamId) } else { $false }; failure = '' }
    }
    catch {
        [pscustomobject]@{ name = $TeamName; teamId = ''; status = 'failed'; addedToSolution = $false; failure = $_.Exception.Message }
    }
}

$solution = Get-AllRows "solutions?`$select=solutionid,uniquename,friendlyname&`$filter=uniquename eq '$SolutionUniqueName'&`$top=1" | Select-Object -First 1
if (-not $solution) { throw "Solution '$SolutionUniqueName' was not found in $EnvironmentUrl." }

$whoAmI = Invoke-DvGet 'WhoAmI()'
$currentUser = Invoke-DvGet "systemusers($($whoAmI.UserId))?`$select=systemuserid,fullname,internalemailaddress,_businessunitid_value,isdisabled"
$businessUnitId = [string](Get-Prop -Row $currentUser -Name '_businessunitid_value')

$staff = Get-AllRows "qfu_staffs?`$select=qfu_staffid,qfu_name,qfu_staffnumber,qfu_primaryemail,_qfu_systemuser_value,qfu_active,statecode&`$filter=statecode eq 0"
$memberships = Get-AllRows "qfu_branchmemberships?`$select=qfu_branchmembershipid,qfu_role,qfu_active,_qfu_branch_value,_qfu_staff_value,statecode,qfu_notes&`$filter=statecode eq 0"
$branches = Get-AllRows "qfu_branchs?`$select=qfu_branchid,qfu_name,qfu_branchcode,statecode&`$filter=statecode eq 0"
$workItems = Get-AllRows "qfu_workitems?`$select=qfu_workitemid,qfu_status,qfu_assignmentstatus,qfu_sourceexternalkey,_qfu_branch_value,statecode&`$filter=statecode eq 0"
$exceptions = Get-AllRows "qfu_assignmentexceptions?`$select=qfu_assignmentexceptionid,qfu_exceptionkey,qfu_status,_qfu_branch_value,statecode&`$filter=statecode eq 0"
$alertLogs = Get-AllRows "qfu_alertlogs?`$select=qfu_alertlogid,qfu_status,qfu_dedupekey,statecode&`$filter=statecode eq 0"
$policies = Get-AllRows "qfu_policies?`$select=qfu_policyid,qfu_name,qfu_policykey,qfu_alertmode,qfu_digestenabled,qfu_targetedalertenabled,qfu_active,statecode&`$filter=statecode eq 0"
$workflows = Get-AllRows "workflows?`$select=workflowid,name,statecode,statuscode,category,type,primaryentity,_ownerid_value,_createdby_value,_modifiedby_value,clientdata&`$filter=category eq 5 and startswith(name,'QFU ')"

$roleShells = @()
if ($CreateSecurityShells) {
    foreach ($roleName in @('QFU Staff','QFU Manager','QFU GM','QFU Admin','QFU Service Account')) {
        $roleShells += Ensure-RoleShell -RoleName $roleName -BusinessUnitId $businessUnitId
    }
}

$branchIdsWithData = New-Object System.Collections.Generic.HashSet[string]
foreach ($m in $memberships) { [void]$branchIdsWithData.Add([string](Get-Prop -Row $m -Name '_qfu_branch_value')) }
foreach ($wi in $workItems) { [void]$branchIdsWithData.Add([string](Get-Prop -Row $wi -Name '_qfu_branch_value')) }
$branchTeamShells = @()
if ($CreateBranchTeamShells) {
    foreach ($branch in $branches | Where-Object { $branchIdsWithData.Contains([string]$_.qfu_branchid) }) {
        $code = if ($branch.qfu_branchcode) { [string]$branch.qfu_branchcode } else { ([string]$branch.qfu_name -replace '[^0-9A-Za-z -]', '').Trim() }
        if ([string]::IsNullOrWhiteSpace($code)) { $code = [string]$branch.qfu_branchid }
        $branchTeamShells += Ensure-TeamShell -TeamName "QFU Branch $code" -BusinessUnitId $businessUnitId -AdminUserId ([string]$currentUser.systemuserid)
    }
}

$views = @()
$views += Ensure-View -Table 'qfu_staff' -ViewName 'Phase 8 Identity Setup - Missing Email' -Columns @('qfu_name','qfu_staffnumber','qfu_primaryemail','qfu_systemuser','qfu_active','qfu_notes') -FilterXml '<filter type="and"><condition attribute="statecode" operator="eq" value="0" /><condition attribute="qfu_primaryemail" operator="null" /></filter>' -OrderColumn 'qfu_name'
$views += Ensure-View -Table 'qfu_staff' -ViewName 'Phase 8 Identity Setup - Missing System User' -Columns @('qfu_name','qfu_staffnumber','qfu_primaryemail','qfu_systemuser','qfu_active','qfu_notes') -FilterXml '<filter type="and"><condition attribute="statecode" operator="eq" value="0" /><condition attribute="qfu_systemuser" operator="null" /></filter>' -OrderColumn 'qfu_name'
$views += Ensure-View -Table 'qfu_staff' -ViewName 'Phase 8 Identity Setup - Linked Staff' -Columns @('qfu_name','qfu_staffnumber','qfu_primaryemail','qfu_systemuser','qfu_active','qfu_notes') -FilterXml '<filter type="and"><condition attribute="statecode" operator="eq" value="0" /><condition attribute="qfu_systemuser" operator="not-null" /></filter>' -OrderColumn 'qfu_name'
$views += Ensure-View -Table 'qfu_staff' -ViewName 'Phase 8 Identity Setup - Active Staff' -Columns @('qfu_name','qfu_staffnumber','qfu_primaryemail','qfu_systemuser','qfu_defaultbranch','qfu_active') -FilterXml '<filter type="and"><condition attribute="statecode" operator="eq" value="0" /></filter>' -OrderColumn 'qfu_name'
$views += Ensure-View -Table 'qfu_branchmembership' -ViewName 'Phase 8 Role Setup - Manager GM Admin' -Columns @('qfu_name','qfu_branch','qfu_staff','qfu_role','qfu_active','qfu_isprimary','qfu_notes') -FilterXml '<filter type="and"><condition attribute="statecode" operator="eq" value="0" /><condition attribute="qfu_role" operator="in"><value>100000002</value><value>100000003</value><value>100000004</value></condition></filter>' -OrderColumn 'qfu_name'
$views += Ensure-View -Table 'qfu_branchmembership' -ViewName 'Phase 8 Role Setup - Admin Memberships' -Columns @('qfu_name','qfu_branch','qfu_staff','qfu_role','qfu_active','qfu_notes') -FilterXml '<filter type="and"><condition attribute="statecode" operator="eq" value="0" /><condition attribute="qfu_role" operator="eq" value="100000004" /></filter>' -OrderColumn 'qfu_name'
$views += Ensure-View -Table 'qfu_workitem' -ViewName 'Phase 8 Monitoring - Overdue Work Items' -Columns @('qfu_workitemnumber','qfu_branch','qfu_status','qfu_assignmentstatus','qfu_currentqueueownerstaff','qfu_nextfollowupon','qfu_completedattempts','qfu_requiredattempts') -FilterXml '<filter type="and"><condition attribute="statecode" operator="eq" value="0" /><condition attribute="qfu_status" operator="eq" value="985010002" /></filter>' -OrderColumn 'qfu_nextfollowupon'
$views += Ensure-View -Table 'qfu_workitem' -ViewName 'Phase 8 Monitoring - Roadblocks' -Columns @('qfu_workitemnumber','qfu_branch','qfu_status','qfu_assignmentstatus','qfu_currentqueueownerstaff','qfu_nextfollowupon','qfu_stickynote') -FilterXml '<filter type="and"><condition attribute="statecode" operator="eq" value="0" /><condition attribute="qfu_status" operator="eq" value="985010005" /></filter>' -OrderColumn 'modifiedon'
$views += Ensure-View -Table 'qfu_workitem' -ViewName 'Phase 8 Monitoring - Assignment Issues' -Columns @('qfu_workitemnumber','qfu_branch','qfu_status','qfu_assignmentstatus','qfu_tsrstaff','qfu_cssrstaff','qfu_currentqueueroletext') -FilterXml '<filter type="and"><condition attribute="statecode" operator="eq" value="0" /><condition attribute="qfu_assignmentstatus" operator="in"><value>985010002</value><value>985010003</value><value>985010004</value><value>985010005</value></condition></filter>' -OrderColumn 'qfu_workitemnumber'
$views += Ensure-View -Table 'qfu_alertlog' -ViewName 'Phase 8 Monitoring - Skipped Alerts' -Columns @('qfu_name','qfu_alerttype','qfu_status','qfu_recipientstaff','qfu_recipientemail','qfu_dedupekey','qfu_notes','createdon') -FilterXml '<filter type="and"><condition attribute="statecode" operator="eq" value="0" /><condition attribute="qfu_status" operator="eq" value="985010004" /></filter>' -OrderColumn 'createdon'
$views += Ensure-View -Table 'qfu_alertlog' -ViewName 'Phase 8 Monitoring - Failed Alerts' -Columns @('qfu_name','qfu_alerttype','qfu_status','qfu_recipientstaff','qfu_recipientemail','qfu_failuremessage','createdon') -FilterXml '<filter type="and"><condition attribute="statecode" operator="eq" value="0" /><condition attribute="qfu_status" operator="eq" value="985010002" /></filter>' -OrderColumn 'createdon'
$views += Ensure-View -Table 'qfu_assignmentexception' -ViewName 'Phase 8 Monitoring - Open Assignment Exceptions' -Columns @('qfu_name','qfu_branch','qfu_exceptiontype','qfu_status','qfu_workitem','qfu_notes','createdon') -FilterXml '<filter type="and"><condition attribute="statecode" operator="eq" value="0" /><condition attribute="qfu_status" operator="eq" value="985010000" /></filter>' -OrderColumn 'createdon'
$views += Ensure-View -Table 'qfu_policy' -ViewName 'Phase 8 Monitoring - Alert Policies' -Columns @('qfu_name','qfu_policykey','qfu_worktype','qfu_alertmode','qfu_digestenabled','qfu_targetedalertenabled','qfu_active') -FilterXml '<filter type="and"><condition attribute="statecode" operator="eq" value="0" /></filter>' -OrderColumn 'qfu_name'

$staffById = @{}
foreach ($s in $staff) { $staffById[[string]$s.qfu_staffid] = $s }
$branchReadiness = New-Object System.Collections.Generic.List[object]
foreach ($branch in $branches | Where-Object { $branchIdsWithData.Contains([string]$_.qfu_branchid) }) {
    $branchId = [string]$branch.qfu_branchid
    $branchMemberships = @($memberships | Where-Object { [string](Get-Prop -Row $_ -Name '_qfu_branch_value') -eq $branchId -and $_.qfu_active -ne $false })
    $branchWorkItems = @($workItems | Where-Object { [string](Get-Prop -Row $_ -Name '_qfu_branch_value') -eq $branchId })
    $branchExceptions = @($exceptions | Where-Object { [string](Get-Prop -Row $_ -Name '_qfu_branch_value') -eq $branchId })
    $branchReadiness.Add([pscustomobject]@{
        branchId = $branchId
        branchCode = [string]$branch.qfu_branchcode
        hasTSR = @($branchMemberships | Where-Object { [int]$_.qfu_role -eq $membershipRoleValues.TSR }).Count -gt 0
        hasCSSR = @($branchMemberships | Where-Object { [int]$_.qfu_role -eq $membershipRoleValues.CSSR }).Count -gt 0
        hasManager = @($branchMemberships | Where-Object { [int]$_.qfu_role -eq $membershipRoleValues.Manager }).Count -gt 0
        hasGM = @($branchMemberships | Where-Object { [int]$_.qfu_role -eq $membershipRoleValues.GM }).Count -gt 0
        hasAdmin = @($branchMemberships | Where-Object { [int]$_.qfu_role -eq $membershipRoleValues.Admin }).Count -gt 0
        activeWorkItems = @($branchWorkItems).Count
        assignmentExceptions = @($branchExceptions).Count
        readinessStatus = if (@($branchMemberships | Where-Object { [int]$_.qfu_role -eq $membershipRoleValues.Manager }).Count -gt 0 -and @($branchMemberships | Where-Object { [int]$_.qfu_role -eq $membershipRoleValues.GM }).Count -gt 0) { 'ReadyForSecurityPilot' } else { 'MissingManagerOrGM' }
    }) | Out-Null
}

$flowOwnership = @($workflows | ForEach-Object {
    $client = [string]$_.clientdata
    [pscustomobject]@{
        workflowId = $_.workflowid
        name = $_.name
        statecode = $_.statecode
        statuscode = $_.statuscode
        ownerId = [string](Get-Prop -Row $_ -Name '_ownerid_value')
        createdBy = [string](Get-Prop -Row $_ -Name '_createdby_value')
        modifiedBy = [string](Get-Prop -Row $_ -Name '_modifiedby_value')
        containsSendMail = $client -match 'SendEmail|sendmail|shared_office365|smtp|Send_an_email'
        containsTeams = $client -match 'shared_teams|Post_message|chatMessage'
        risk = 'Owner/connection references should be reviewed before production.'
    }
})

$duplicateAlertKeys = @($alertLogs | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.qfu_dedupekey) } | Group-Object qfu_dedupekey | Where-Object Count -gt 1)
$duplicateWorkItemKeys = @($workItems | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.qfu_sourceexternalkey) } | Group-Object qfu_sourceexternalkey | Where-Object Count -gt 1)
$duplicateExceptionKeys = @($exceptions | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.qfu_exceptionkey) } | Group-Object qfu_exceptionkey | Where-Object Count -gt 1)

$staffActive = @($staff | Where-Object { $_.qfu_active -ne $false })
$summary = [ordered]@{
    timestamp = (Get-Date).ToString('o')
    environmentUrl = $EnvironmentUrl
    solutionFound = [bool]$solution
    currentUser = @{
        systemUserId = [string]$currentUser.systemuserid
        businessUnitId = $businessUnitId
    }
    counts = @{
        activeStaff = @($staffActive).Count
        activeStaffWithEmail = @($staffActive | Where-Object { Test-EmailFormat ([string]$_.qfu_primaryemail) }).Count
        activeStaffMissingEmail = @($staffActive | Where-Object { -not (Test-EmailFormat ([string]$_.qfu_primaryemail)) }).Count
        activeStaffLinkedToSystemUser = @($staffActive | Where-Object { -not [string]::IsNullOrWhiteSpace([string](Get-Prop -Row $_ -Name '_qfu_systemuser_value')) }).Count
        activeStaffMissingSystemUser = @($staffActive | Where-Object { [string]::IsNullOrWhiteSpace([string](Get-Prop -Row $_ -Name '_qfu_systemuser_value')) }).Count
        managerMemberships = @($memberships | Where-Object { [int]$_.qfu_role -eq $membershipRoleValues.Manager }).Count
        gmMemberships = @($memberships | Where-Object { [int]$_.qfu_role -eq $membershipRoleValues.GM }).Count
        adminMemberships = @($memberships | Where-Object { [int]$_.qfu_role -eq $membershipRoleValues.Admin }).Count
        qfuSecurityRoleShells = @($roleShells | Where-Object { $_.status -in @('found','created-shell') }).Count
        qfuBranchTeamShells = @($branchTeamShells | Where-Object { $_.status -in @('found','created-shell') }).Count
        activeWorkItems = @($workItems).Count
        alertLogs = @($alertLogs).Count
        sentAlertLogs = @($alertLogs | Where-Object { [int]$_.qfu_status -eq 985010001 }).Count
        duplicateAlertDedupeKeys = @($duplicateAlertKeys).Count
        duplicateWorkItemSourceKeys = @($duplicateWorkItemKeys).Count
        duplicateAssignmentExceptionKeys = @($duplicateExceptionKeys).Count
    }
    securityRoleShells = $roleShells
    branchTeamShells = $branchTeamShells
    views = $views
    productionSecurityComplete = $false
    productionSecurityBlocker = 'Verified staff roster, Manager/GM/Admin roster, and final privilege matrix are still required before production role enforcement.'
}

$roleShells | Export-Csv -NoTypeInformation -Path (Join-Path $OutputDir 'security-role-shells.csv')
$branchTeamShells | Export-Csv -NoTypeInformation -Path (Join-Path $OutputDir 'branch-team-shells.csv')
$views | Export-Csv -NoTypeInformation -Path (Join-Path $OutputDir 'monitoring-admin-views.csv')
$branchReadiness | Export-Csv -NoTypeInformation -Path (Join-Path $OutputDir 'branch-readiness.csv')
$flowOwnership | Export-Csv -NoTypeInformation -Path (Join-Path $OutputDir 'flow-ownership-and-connection-risk.csv')
$summary | ConvertTo-Json -Depth 30 | Set-Content -Encoding UTF8 -Path (Join-Path $OutputDir 'phase8-production-hardening-summary.json')
$summary | ConvertTo-Json -Depth 30
