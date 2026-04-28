param(
    [string]$EnvironmentUrl = 'https://orga632edd5.crm3.dynamics.com',
    [string]$SolutionUniqueName = 'qfu_revenuefollowupworkbench',
    [int]$BackorderSampleLimit = 5,
    [string]$BranchCode = '4171'
)

$ErrorActionPreference = 'Stop'

$roleValues = @{
    TSR        = 985020000
    CSSR       = 985020001
    Manager    = 985020002
    GM         = 985020003
    Admin      = 985020004
    Unassigned = 985020005
}

$statusValues = @{
    Open       = 985010000
    DueToday   = 985010001
    Overdue    = 985010002
    Roadblock  = 985010005
    Escalated  = 985010006
    ClosedWon  = 985010008
    ClosedLost = 985010009
    Cancelled  = 985010010
}

$assignmentValues = @{
    Assigned           = 985010000
    PartiallyAssigned  = 985010001
    NeedsTSRAssignment = 985010002
    NeedsCSSRAssignment = 985010003
    Unmapped           = 985010004
    Error              = 985010005
}

$workTypeValues = @{
    Quote     = 985010000
    Backorder = 985010001
    Freight   = 985010002
}

$sourceSystemValues = @{
    SP830CA = 985010000
    ZBO     = 985010001
    Freight = 985010002
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
    Authorization          = "Bearer $(Get-AccessToken)"
    Accept                 = 'application/json'
    'Content-Type'         = 'application/json; charset=utf-8'
    'OData-MaxVersion'     = '4.0'
    'OData-Version'        = '4.0'
    'MSCRM.SolutionUniqueName' = $SolutionUniqueName
}

$readHeaders = $headers.Clone()
$readHeaders.Remove('Content-Type')

function Invoke-DvGet {
    param([string]$RelativeUrl)
    Invoke-RestMethod -Method Get -Uri "$EnvironmentUrl/api/data/v9.2/$RelativeUrl" -Headers $readHeaders
}

function Invoke-DvPost {
    param(
        [string]$RelativeUrl,
        [object]$Body
    )
    $json = $Body | ConvertTo-Json -Depth 20
    Invoke-RestMethod -Method Post -Uri "$EnvironmentUrl/api/data/v9.2/$RelativeUrl" -Headers $headers -Body $json
}

function Invoke-DvPatch {
    param(
        [string]$RelativeUrl,
        [object]$Body
    )
    $json = $Body | ConvertTo-Json -Depth 20
    Invoke-RestMethod -Method Patch -Uri "$EnvironmentUrl/api/data/v9.2/$RelativeUrl" -Headers $headers -Body $json
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

function New-Label {
    param([string]$Text)
    @{
        '@odata.type' = 'Microsoft.Dynamics.CRM.Label'
        LocalizedLabels = @(
            @{
                '@odata.type' = 'Microsoft.Dynamics.CRM.LocalizedLabel'
                Label = $Text
                LanguageCode = 1033
            }
        )
        UserLocalizedLabel = @{
            '@odata.type' = 'Microsoft.Dynamics.CRM.LocalizedLabel'
            Label = $Text
            LanguageCode = 1033
        }
    }
}

function Test-AttributeExists {
    param([string]$LogicalName)
    try {
        $null = Invoke-DvGet "EntityDefinitions(LogicalName='qfu_workitem')/Attributes(LogicalName='$LogicalName')?`$select=LogicalName"
        return $true
    }
    catch {
        return $false
    }
}

function Ensure-IntegerAttribute {
    param([string]$SchemaName, [string]$DisplayName)
    $logical = $SchemaName.ToLowerInvariant()
    if (Test-AttributeExists $logical) {
        return @{ name = $logical; status = 'found' }
    }
    Invoke-DvPost "EntityDefinitions(LogicalName='qfu_workitem')/Attributes" @{
        '@odata.type' = 'Microsoft.Dynamics.CRM.IntegerAttributeMetadata'
        SchemaName = $SchemaName
        DisplayName = New-Label $DisplayName
        Description = New-Label $DisplayName
        RequiredLevel = @{ Value = 'None'; CanBeChanged = $true; ManagedPropertyLogicalName = 'canmodifyrequirementlevelsettings' }
        MinValue = 0
        MaxValue = 1000000
        Format = 'None'
    } | Out-Null
    return @{ name = $logical; status = 'created' }
}

function Ensure-MemoAttribute {
    param([string]$SchemaName, [string]$DisplayName)
    $logical = $SchemaName.ToLowerInvariant()
    if (Test-AttributeExists $logical) {
        return @{ name = $logical; status = 'found' }
    }
    Invoke-DvPost "EntityDefinitions(LogicalName='qfu_workitem')/Attributes" @{
        '@odata.type' = 'Microsoft.Dynamics.CRM.MemoAttributeMetadata'
        SchemaName = $SchemaName
        DisplayName = New-Label $DisplayName
        Description = New-Label $DisplayName
        RequiredLevel = @{ Value = 'None'; CanBeChanged = $true; ManagedPropertyLogicalName = 'canmodifyrequirementlevelsettings' }
        MaxLength = 4000
        Format = 'TextArea'
        ImeMode = 'Auto'
    } | Out-Null
    return @{ name = $logical; status = 'created' }
}

function Ensure-DateTimeAttribute {
    param([string]$SchemaName, [string]$DisplayName)
    $logical = $SchemaName.ToLowerInvariant()
    if (Test-AttributeExists $logical) {
        return @{ name = $logical; status = 'found' }
    }
    Invoke-DvPost "EntityDefinitions(LogicalName='qfu_workitem')/Attributes" @{
        '@odata.type' = 'Microsoft.Dynamics.CRM.DateTimeAttributeMetadata'
        SchemaName = $SchemaName
        DisplayName = New-Label $DisplayName
        Description = New-Label $DisplayName
        RequiredLevel = @{ Value = 'None'; CanBeChanged = $true; ManagedPropertyLogicalName = 'canmodifyrequirementlevelsettings' }
        Format = 'DateAndTime'
        DateTimeBehavior = @{ Value = 'UserLocal' }
        ImeMode = 'Inactive'
    } | Out-Null
    return @{ name = $logical; status = 'created' }
}

function Ensure-QueueRoleAttribute {
    $logical = 'qfu_currentqueuerole'
    if (Test-AttributeExists $logical) {
        return @{ name = $logical; status = 'found' }
    }
    Invoke-DvPost "EntityDefinitions(LogicalName='qfu_workitem')/Attributes" @{
        '@odata.type' = 'Microsoft.Dynamics.CRM.PicklistAttributeMetadata'
        SchemaName = 'qfu_CurrentQueueRole'
        DisplayName = New-Label 'Current Queue Role'
        Description = New-Label 'Role that currently owns the queue item.'
        RequiredLevel = @{ Value = 'None'; CanBeChanged = $true; ManagedPropertyLogicalName = 'canmodifyrequirementlevelsettings' }
        OptionSet = @{
            '@odata.type' = 'Microsoft.Dynamics.CRM.OptionSetMetadata'
            IsGlobal = $false
            OptionSetType = 'Picklist'
            Options = @(
                @{ Value = $roleValues.TSR; Label = New-Label 'TSR' }
                @{ Value = $roleValues.CSSR; Label = New-Label 'CSSR' }
                @{ Value = $roleValues.Manager; Label = New-Label 'Manager' }
                @{ Value = $roleValues.GM; Label = New-Label 'GM' }
                @{ Value = $roleValues.Admin; Label = New-Label 'Admin' }
                @{ Value = $roleValues.Unassigned; Label = New-Label 'Unassigned' }
            )
        }
    } | Out-Null
    return @{ name = $logical; status = 'created' }
}

function Ensure-StaffLookup {
    param([string]$SchemaName, [string]$DisplayName, [string]$RelationshipSchemaName)
    $logical = $SchemaName.ToLowerInvariant()
    if (Test-AttributeExists $logical) {
        return @{ name = $logical; status = 'found' }
    }
    $payload = @{
        '@odata.type' = 'Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata'
        SchemaName = $RelationshipSchemaName
        ReferencedEntity = 'qfu_staff'
        ReferencingEntity = 'qfu_workitem'
        ReferencedAttribute = 'qfu_staffid'
        AssociatedMenuConfiguration = @{
            Behavior = 'UseCollectionName'
            Group = 'Details'
            Label = New-Label 'Work Items'
            Order = 10000
        }
        CascadeConfiguration = @{
            Assign = 'NoCascade'
            Delete = 'RemoveLink'
            Merge = 'NoCascade'
            Reparent = 'NoCascade'
            Share = 'NoCascade'
            Unshare = 'NoCascade'
        }
        Lookup = @{
            '@odata.type' = 'Microsoft.Dynamics.CRM.LookupAttributeMetadata'
            AttributeType = 'Lookup'
            AttributeTypeName = @{ Value = 'LookupType' }
            SchemaName = $SchemaName
            DisplayName = New-Label $DisplayName
            Description = New-Label $DisplayName
            RequiredLevel = @{ Value = 'None'; CanBeChanged = $true; ManagedPropertyLogicalName = 'canmodifyrequirementlevelsettings' }
        }
    }
    Invoke-DvPost 'RelationshipDefinitions' $payload | Out-Null
    return @{ name = $logical; status = 'created' }
}

$fieldResults = @()
$fieldResults += Ensure-StaffLookup -SchemaName 'qfu_CurrentQueueOwnerStaff' -DisplayName 'Current Queue Owner Staff' -RelationshipSchemaName 'qfu_staff_qfu_workitem_currentqueueownerstaff'
$fieldResults += Ensure-QueueRoleAttribute
$fieldResults += Ensure-DateTimeAttribute -SchemaName 'qfu_QueueAssignedOn' -DisplayName 'Queue Assigned On'
$fieldResults += Ensure-StaffLookup -SchemaName 'qfu_QueueAssignedBy' -DisplayName 'Queue Assigned By' -RelationshipSchemaName 'qfu_staff_qfu_workitem_queueassignedby'
$fieldResults += Ensure-MemoAttribute -SchemaName 'qfu_QueueHandoffReason' -DisplayName 'Queue Handoff Reason'
$fieldResults += Ensure-IntegerAttribute -SchemaName 'qfu_QueueHandoffCount' -DisplayName 'Queue Handoff Count'

Invoke-DvPost 'PublishAllXml' @{} | Out-Null
Start-Sleep -Seconds 10

$queueInit = @{
    scanned = 0
    updated = 0
    skipped_existing_owner = 0
    no_staff_available = 0
}

$workItems = Get-AllRows "qfu_workitems?`$select=qfu_workitemid,_qfu_primaryownerstaff_value,_qfu_tsrstaff_value,_qfu_cssrstaff_value,_qfu_currentqueueownerstaff_value,qfu_currentqueuerole,statecode&`$filter=statecode eq 0"
foreach ($wi in $workItems) {
    $queueInit.scanned++
    if ($wi.'_qfu_currentqueueownerstaff_value') {
        $queueInit.skipped_existing_owner++
        continue
    }

    $targetId = $wi.'_qfu_tsrstaff_value'
    $role = $roleValues.TSR
    if (-not $targetId) {
        $targetId = $wi.'_qfu_cssrstaff_value'
        $role = $roleValues.CSSR
    }

    if (-not $targetId) {
        $queueInit.no_staff_available++
        $body = @{
            qfu_currentqueuerole = $roleValues.Unassigned
            qfu_queueassignedon = (Get-Date).ToUniversalTime().ToString('o')
            qfu_queuehandoffcount = 0
        }
    }
    else {
        $body = @{
            'qfu_CurrentQueueOwnerStaff@odata.bind' = "/qfu_staffs($targetId)"
            qfu_currentqueuerole = $role
            qfu_queueassignedon = (Get-Date).ToUniversalTime().ToString('o')
            qfu_queuehandoffcount = 0
        }
    }
    Invoke-DvPatch "qfu_workitems($($wi.qfu_workitemid))" $body | Out-Null
    $queueInit.updated++
}

$branchRows = Get-AllRows "qfu_branchs?`$select=qfu_branchid,qfu_branchcode,qfu_name&`$filter=qfu_branchcode eq '$BranchCode' or qfu_name eq '$BranchCode'"
$branch = $branchRows | Select-Object -First 1
$backorderResult = @{
    source = 'qfu_backorder'
    branch = $BranchCode
    scanned = 0
    created = 0
    updated = 0
    skipped_no_branch = 0
    owner_assignment = 'deferred-no-verified-backorder-staff-number'
}

if (-not $branch) {
    $backorderResult.skipped_no_branch = 1
}
else {
    $filter = "statecode eq 0 and (qfu_active eq true or qfu_active eq null) and qfu_branchcode eq '$BranchCode' and qfu_daysoverdue gt 0"
    $encodedFilter = [System.Uri]::EscapeDataString($filter)
    $backorders = Get-AllRows "qfu_backorders?`$select=qfu_backorderid,qfu_sourceid,qfu_salesdocnumber,qfu_sourceline,qfu_customername,qfu_totalvalue,qfu_daysoverdue,qfu_ontimedate,qfu_branchcode&`$filter=$encodedFilter&`$orderby=qfu_daysoverdue desc,qfu_totalvalue desc&`$top=$BackorderSampleLimit"
    foreach ($bo in $backorders) {
        $backorderResult.scanned++
        $sourceKey = if ($bo.qfu_sourceid) { $bo.qfu_sourceid } else { "ZBO|$BranchCode|$($bo.qfu_salesdocnumber)|$($bo.qfu_sourceline)" }
        $existing = Get-AllRows "qfu_workitems?`$select=qfu_workitemid&`$filter=qfu_worktype eq $($workTypeValues.Backorder) and qfu_sourceexternalkey eq '$([System.Uri]::EscapeDataString($sourceKey).Replace('%7C','|'))'"
        $payload = @{
            qfu_workitemnumber = "Backorder $($bo.qfu_salesdocnumber)"
            qfu_worktype = $workTypeValues.Backorder
            qfu_sourcesystem = $sourceSystemValues.ZBO
            'qfu_Branch@odata.bind' = "/qfu_branchs($($branch.qfu_branchid))"
            qfu_sourceexternalkey = $sourceKey
            qfu_sourcedocumentnumber = [string]$bo.qfu_salesdocnumber
            'qfu_SourceBackorder@odata.bind' = "/qfu_backorders($($bo.qfu_backorderid))"
            qfu_customername = [string]$bo.qfu_customername
            qfu_totalvalue = if ($null -ne $bo.qfu_totalvalue) { [decimal]$bo.qfu_totalvalue } else { 0 }
            qfu_requiredattempts = 0
            qfu_completedattempts = 0
            qfu_status = $statusValues.Overdue
            qfu_assignmentstatus = $assignmentValues.Unmapped
            qfu_currentqueuerole = $roleValues.Unassigned
            qfu_queueassignedon = (Get-Date).ToUniversalTime().ToString('o')
            qfu_queuehandoffcount = 0
            qfu_notes = 'Phase 5 controlled dev overdue-order work item from qfu_backorder. Owner assignment deferred pending verified staff alias source.'
        }
        if ($existing.Count -gt 0) {
            Invoke-DvPatch "qfu_workitems($($existing[0].qfu_workitemid))" $payload | Out-Null
            $backorderResult.updated++
        }
        else {
            Invoke-DvPost 'qfu_workitems' $payload | Out-Null
            $backorderResult.created++
        }
    }
}

Invoke-DvPost 'PublishAllXml' @{} | Out-Null

$result = [ordered]@{
    environmentUrl = $EnvironmentUrl
    timestamp = (Get-Date).ToString('o')
    fieldResults = $fieldResults
    queueInitialization = $queueInit
    backorderWorkItems = $backorderResult
    serverSideRollup = @{
        implemented = $false
        blocker = 'No safe automated Power Automate flow creation path was available through PAC in this session, and dotnet/plugin build tooling is not installed. App-side rollup remains live; server-side flow/plugin is documented as next required reliability work.'
    }
}

$result | ConvertTo-Json -Depth 10
