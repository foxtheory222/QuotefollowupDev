param(
    [string]$EnvironmentUrl = 'https://orga632edd5.crm3.dynamics.com',
    [string]$SourceDocumentNumber
)

$ErrorActionPreference = 'Stop'

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

$headers = @{
    Authorization      = "Bearer $token"
    Accept             = 'application/json'
    Prefer             = 'odata.include-annotations="OData.Community.Display.V1.FormattedValue"'
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

    return $rows
}

$workItems = Get-AllRows "qfu_workitems?`$select=qfu_workitemid,statecode,qfu_sourcedocumentnumber,qfu_totalvalue,qfu_completedattempts,qfu_requiredattempts,qfu_status,qfu_assignmentstatus,qfu_stickynote,qfu_lastfollowedupon,qfu_lastactionon,qfu_nextfollowupon&`$filter=statecode eq 0"
$actions = Get-AllRows "qfu_workitemactions?`$select=qfu_workitemactionid,statecode,qfu_countsasattempt,qfu_actiontype,qfu_actionon,qfu_notes,_qfu_workitem_value&`$filter=statecode eq 0"
$alerts = Get-AllRows "qfu_alertlogs?`$select=qfu_alertlogid,statecode,qfu_status&`$filter=statecode eq 0"
$exceptions = Get-AllRows "qfu_assignmentexceptions?`$select=qfu_assignmentexceptionid,statecode,qfu_status,qfu_sourceexternalkey,qfu_exceptiontype,qfu_sourcefield,qfu_normalizedvalue"

$counts = [ordered]@{
    ActiveWorkItems          = $workItems.Count
    Open                     = @($workItems | Where-Object { $_.'qfu_status@OData.Community.Display.V1.FormattedValue' -eq 'Open' }).Count
    DueToday                 = @($workItems | Where-Object { $_.'qfu_status@OData.Community.Display.V1.FormattedValue' -eq 'Due Today' }).Count
    Overdue                  = @($workItems | Where-Object { $_.'qfu_status@OData.Community.Display.V1.FormattedValue' -eq 'Overdue' }).Count
    Roadblocks               = @($workItems | Where-Object { $_.'qfu_status@OData.Community.Display.V1.FormattedValue' -eq 'Roadblock' }).Count
    QuotesGte3K              = @($workItems | Where-Object { [decimal]$_.qfu_totalvalue -ge 3000 }).Count
    MissingAttempts          = @($workItems | Where-Object { [int]$_.qfu_completedattempts -lt [int]$_.qfu_requiredattempts }).Count
    AssignmentIssues         = @($workItems | Where-Object { $_.'qfu_assignmentstatus@OData.Community.Display.V1.FormattedValue' -ne 'Assigned' }).Count
    WorkItemsWithStickyNotes = @($workItems | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.qfu_stickynote) }).Count
    ActiveActions            = $actions.Count
    AttemptActions           = @($actions | Where-Object { $_.qfu_countsasattempt -eq $true }).Count
    ActiveAssignmentExceptions = @($exceptions | Where-Object { $_.statecode -eq 0 }).Count
    ActiveAlertLogs          = $alerts.Count
    SentAlertLogs            = @($alerts | Where-Object { $_.'qfu_status@OData.Community.Display.V1.FormattedValue' -eq 'Sent' }).Count
}

$duplicateWorkItemKeys = @(
    $workItems |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.qfu_sourcedocumentnumber) } |
        Group-Object qfu_sourcedocumentnumber |
        Where-Object { $_.Count -gt 1 } |
        Select-Object Name, Count
)

$duplicateExceptionKeys = @(
    $exceptions |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.qfu_sourceexternalkey) } |
        Group-Object {
            '{0}|{1}|{2}|{3}' -f $_.qfu_sourceexternalkey, $_.qfu_exceptiontype, $_.qfu_sourcefield, $_.qfu_normalizedvalue
        } |
        Where-Object { $_.Count -gt 1 } |
        Select-Object Name, Count
)

$selectedWorkItem = $null
$selectedActions = @()
if ($SourceDocumentNumber) {
    $selectedWorkItem = $workItems | Where-Object { $_.qfu_sourcedocumentnumber -eq $SourceDocumentNumber } | Select-Object -First 1
    if ($selectedWorkItem) {
        $selectedActions = @($actions | Where-Object { $_.'_qfu_workitem_value' -eq $selectedWorkItem.qfu_workitemid } | Sort-Object qfu_actionon -Descending)
    }
}

[pscustomobject]@{
    EnvironmentUrl           = $EnvironmentUrl
    Timestamp                = (Get-Date).ToString('o')
    Counts                   = $counts
    StatusGroups             = @($workItems | Group-Object { $_.'qfu_status@OData.Community.Display.V1.FormattedValue' } | Select-Object Name, Count)
    AssignmentGroups         = @($workItems | Group-Object { $_.'qfu_assignmentstatus@OData.Community.Display.V1.FormattedValue' } | Select-Object Name, Count)
    DuplicateWorkItemKeys    = $duplicateWorkItemKeys
    DuplicateExceptionKeys   = $duplicateExceptionKeys
    SelectedWorkItem         = $selectedWorkItem
    SelectedWorkItemActions  = $selectedActions
} | ConvertTo-Json -Depth 8
