param(
    [Parameter(Mandatory = $true)]
    [string]$BaseSourcePath,

    [Parameter(Mandatory = $true)]
    [string]$OutputSourcePath
)

$ErrorActionPreference = 'Stop'

$phase4Generator = Join-Path $PSScriptRoot 'New-RevenueFollowUpPhase4BMyWorkCanvasSource.ps1'
if (-not (Test-Path -LiteralPath $phase4Generator)) {
    throw "Phase 4B canvas generator not found: $phase4Generator"
}

& $phase4Generator -BaseSourcePath $BaseSourcePath -OutputSourcePath $OutputSourcePath | Out-Null

$screenPath = Join-Path $OutputSourcePath 'Src\Screen1.fx.yaml'
$screen = Get-Content -LiteralPath $screenPath -Raw

$screen = $screen.Replace(
    '=UpdateContext({varActiveTab:"All Open", varShowLog:false, varActionType:"Call", varRefreshStamp:Now()});',
    '=UpdateContext({varActiveTab:"My Queue", varWorkbenchMode:"My Queue", varQueueRoleFilter:"All", varShowLog:false, varActionType:"Call", varRefreshStamp:Now()});'
)
$screen = $screen.Replace('Text: ="My Work"', 'Text: ="Branch Workbench"')
$screen = $screen.Replace(
    'Text: ="Branch/team queue with staff filter fallback | " & Text(Today(), "[$-en-US]mmm d, yyyy")',
    'Text: ="My Queue first, Team View for managers | " & Text(Today(), "[$-en-US]mmm d, yyyy")'
)
$screen = $screen.Replace(
    'Notify("My Work data refreshed.", NotificationType.Success)',
    'Notify("Workbench data refreshed.", NotificationType.Success)'
)
$screen = $screen.Replace(
    'Text: ="Staff dropdown/filter"',
    'Text: ="Staff filter / picker"'
)
$screen = $screen.Replace(
    'Text: ="Current-user staff mapping is not ready, so Phase 4B uses branch/team and staff-name filters."',
    'Text: ="Current-user staff mapping is not ready. Use branch, staff, and queue-role filters for Phase 5."'
)

$modeControls = @'

    MyQueueModeButton As button:
        Color: =If(varWorkbenchMode="My Queue", Color.White, ColorValue("#21424d"))
        Fill: =If(varWorkbenchMode="My Queue", ColorValue("#087a9b"), Color.White)
        Font: =Font.'Segoe UI'
        Height: =32
        OnSelect: =UpdateContext({varWorkbenchMode:"My Queue", varActiveTab:"My Queue"})
        Text: ="My Queue"
        Width: =104
        X: =920
        Y: =106
        ZIndex: =101

    TeamViewModeButton As button:
        Color: =If(varWorkbenchMode="Team View", Color.White, ColorValue("#21424d"))
        Fill: =If(varWorkbenchMode="Team View", ColorValue("#087a9b"), Color.White)
        Font: =Font.'Segoe UI'
        Height: =32
        OnSelect: =UpdateContext({varWorkbenchMode:"Team View", varActiveTab:"Team Stats"})
        Text: ="Team View"
        Width: =112
        X: =1032
        Y: =106
        ZIndex: =102

    QueueRoleLabel As label:
        Color: =ColorValue("#405765")
        Font: =Font.'Segoe UI'
        FontWeight: =FontWeight.Semibold
        Height: =20
        Size: =9
        Text: ="Queue role"
        Width: =110
        X: =1160
        Y: =88
        ZIndex: =103

    QueueRoleFilterInput As 'Text box':
        AccessibleLabel: ="Queue role filter"
        DisplayMode: =DisplayMode.Edit
        FontSize: =10
        Height: =32
        Mode: ="SingleLine"
        Placeholder: ="All, TSR, CSSR"
        Value: =varQueueRoleFilter
        Width: =150
        X: =1160
        Y: =110
        ZIndex: =104

    TeamStatsSummary As label:
        Color: =ColorValue("#173540")
        Fill: =ColorValue("#edf8fb")
        Font: =Font.'Segoe UI'
        Height: =38
        Size: =9
        Text: ="Team View: open " & Text(CountRows(Filter('Work Items', Text('Status (qfu_status)') <> "Closed Won" And Text('Status (qfu_status)') <> "Closed Lost" And Text('Status (qfu_status)') <> "Cancelled"))) & " | overdue " & Text(CountRows(Filter('Work Items', Text('Status (qfu_status)') = "Overdue"))) & " | due today " & Text(CountRows(Filter('Work Items', Text('Status (qfu_status)') = "Due Today"))) & " | assignment issues " & Text(CountRows(Filter('Work Items', 'Assignment Status' <> 'QFU Assignment Status'.Assigned)))
        Visible: =varWorkbenchMode="Team View" Or varActiveTab="Team Stats"
        Width: =820
        X: =24
        Y: =260
        ZIndex: =105
'@

$screen = $screen.Replace("    DueTodayCard As button:", $modeControls + "`r`n`r`n    DueTodayCard As button:")

$screen = $screen.Replace('OnSelect: =UpdateContext({varActiveTab:"High Value"})', 'OnSelect: =UpdateContext({varActiveTab:"Quote Follow-Up"})')
$screen = $screen.Replace('Text: ="Quotes >= $3K"', 'Text: ="Quote Follow-Up"')

$screen = $screen.Replace(
    '    HighValueTab As button:',
    @'
    MyQueueTab As button:
        Color: =If(varActiveTab="My Queue", Color.White, ColorValue("#21424d"))
        Fill: =If(varActiveTab="My Queue", ColorValue("#087a9b"), Color.White)
        Height: =34
        OnSelect: =UpdateContext({varActiveTab:"My Queue", varWorkbenchMode:"My Queue"})
        Text: ="My Queue"
        Width: =110
        X: =24
        Y: =226
        ZIndex: =116

    TeamStatsTab As button:
        Color: =If(varActiveTab="Team Stats", Color.White, ColorValue("#21424d"))
        Fill: =If(varActiveTab="Team Stats", ColorValue("#087a9b"), Color.White)
        Height: =34
        OnSelect: =UpdateContext({varActiveTab:"Team Stats", varWorkbenchMode:"Team View"})
        Text: ="Team Stats"
        Width: =120
        X: =140
        Y: =226
        ZIndex: =117

    QuoteFollowUpTab As button:
        Color: =If(varActiveTab="Quote Follow-Up", Color.White, ColorValue("#21424d"))
        Fill: =If(varActiveTab="Quote Follow-Up", ColorValue("#087a9b"), Color.White)
        Height: =34
        OnSelect: =UpdateContext({varActiveTab:"Quote Follow-Up"})
        Text: ="Quote Follow-Up"
        Width: =150
        X: =266
        Y: =226
        ZIndex: =118

    OverdueOrdersTab As button:
        Color: =If(varActiveTab="Overdue Orders", Color.White, ColorValue("#21424d"))
        Fill: =If(varActiveTab="Overdue Orders", ColorValue("#9b2626"), Color.White)
        Height: =34
        OnSelect: =UpdateContext({varActiveTab:"Overdue Orders"})
        Text: ="Overdue Orders"
        Width: =150
        X: =422
        Y: =226
        ZIndex: =119

    HighValueTab As button:
'@
)

$itemsOld = @'
        Items: |-
            =SortByColumns(
                Filter(
                    'Work Items',
                    IsBlank(BranchFilterInput.Value) || StartsWith(Text(Branch.'Branch Code'), BranchFilterInput.Value) || StartsWith(Text(Branch.'Branch Name'), BranchFilterInput.Value),
                    IsBlank(StaffFilterInput.Value) || StartsWith(Text('TSR Staff'.'Staff Name'), StaffFilterInput.Value) || StartsWith(Text('CSSR Staff'.'Staff Name'), StaffFilterInput.Value),
                    Switch(
                        varActiveTab,
                        "Overdue", Text('Status (qfu_status)') = "Overdue",
                        "Due Today", Text('Status (qfu_status)') = "Due Today",
                        "High Value", 'Total Value' >= 3000,
                        "Needs Attempts", Coalesce('Completed Attempts', 0) < Coalesce('Required Attempts', 3),
                        "Waiting", Or(Text('Status (qfu_status)') = "Waiting on Customer", Text('Status (qfu_status)') = "Waiting on Vendor"),
                        "Roadblocks", Text('Status (qfu_status)') = "Roadblock",
                        "Assignment Issues", 'Assignment Status' <> 'QFU Assignment Status'.Assigned,
                        true
                    )
                ),
                "qfu_nextfollowupon",
                SortOrder.Ascending,
                "qfu_totalvalue",
                SortOrder.Descending
            )
'@

$itemsNew = @'
        Items: |-
            =SortByColumns(
                Filter(
                    'Work Items',
                    IsBlank(BranchFilterInput.Value) || StartsWith(Text(Branch.'Branch Code'), BranchFilterInput.Value) || StartsWith(Text(Branch.'Branch Name'), BranchFilterInput.Value),
                    IsBlank(StaffFilterInput.Value) || StartsWith(Text('TSR Staff'.'Staff Name'), StaffFilterInput.Value) || StartsWith(Text('CSSR Staff'.'Staff Name'), StaffFilterInput.Value),
                    Switch(
                        varActiveTab,
                        "My Queue", true,
                        "Team Stats", true,
                        "Quote Follow-Up", Text('Work Type') = "Quote",
                        "Overdue Orders", Text('Work Type') = "Backorder" And Text('Status (qfu_status)') = "Overdue",
                        "Overdue", Text('Status (qfu_status)') = "Overdue",
                        "Due Today", Text('Status (qfu_status)') = "Due Today",
                        "High Value", 'Total Value' >= 3000,
                        "Needs Attempts", Coalesce('Completed Attempts', 0) < Coalesce('Required Attempts', 3),
                        "Waiting", Or(Text('Status (qfu_status)') = "Waiting on Customer", Text('Status (qfu_status)') = "Waiting on Vendor"),
                        "Roadblocks", Text('Status (qfu_status)') = "Roadblock",
                        "Assignment Issues", 'Assignment Status' <> 'QFU Assignment Status'.Assigned,
                        true
                    )
                ),
                "qfu_nextfollowupon",
                SortOrder.Ascending,
                "qfu_totalvalue",
                SortOrder.Descending
            )
'@
$screen = $screen.Replace($itemsOld, $itemsNew)

$screen = $screen.Replace(
    'Text: ="Priority     Status       Quote / Source Document       Customer       Value       Attempts       Next Follow-Up       Last Followed Up       Sticky Note"',
    'Text: ="Queue      Status       Quote / Source Document       Customer       Value       Attempts       Next Follow-Up       Last Followed Up       Sticky Note"'
)

$screen = $screen.Replace(
    'Height: =Parent.Height - 100
        RadiusBottomLeft: =6',
    'Height: =Parent.Height - 100
        RadiusBottomLeft: =6'
)
$screen = $screen.Replace('Width: =Parent.Width - 1114', 'Width: =Max(420, Parent.Width - 940)')
$screen = $screen.Replace('X: =1090', 'X: =Parent.Width - Self.Width - 24')

$screen = $screen.Replace(
    'Text: ="TSR: " & Coalesce(WorkItemsGallery.Selected.''TSR Staff''.''Staff Name'', "Unassigned") & Char(10) & "CSSR: " & Coalesce(WorkItemsGallery.Selected.''CSSR Staff''.''Staff Name'', "Unassigned") & " | Branch: " & Coalesce(WorkItemsGallery.Selected.Branch.''Branch Code'', "")',
    'Text: ="Queue: " & Coalesce(WorkItemsGallery.Selected.''Current Queue Owner Staff''.''Staff Name'', "Unassigned") & " (" & Coalesce(Text(WorkItemsGallery.Selected.''Current Queue Role''), "No role") & ")" & Char(10) & "TSR: " & Coalesce(WorkItemsGallery.Selected.''TSR Staff''.''Staff Name'', "Unassigned") & " | CSSR: " & Coalesce(WorkItemsGallery.Selected.''CSSR Staff''.''Staff Name'', "Unassigned") & " | Branch: " & Coalesce(WorkItemsGallery.Selected.Branch.''Branch Code'', "")'
)

$handoffReason = @'

        HandoffReasonLabel As label:
            Color: =ColorValue("#405765")
            Font: =Font.'Segoe UI'
            Height: =20
            Size: =9
            Text: ="Queue handoff reason"
            Width: =180
            X: =16
            Y: =414
            ZIndex: =108

        "HandoffReasonInput As 'Text box'":
            AccessibleLabel: ="Queue handoff reason"
            DisplayMode: =DisplayMode.Edit
            FontSize: =9
            Height: =28
            Mode: ="SingleLine"
            Placeholder: ="Optional reason"
            Value: =""
            Width: =Parent.Width - 32
            X: =16
            Y: =436
            ZIndex: =109
'@
$screen = $screen.Replace("        LogCallButton As button:", $handoffReason + "`r`n`r`n        LogCallButton As button:")
$screen = $screen.Replace('Y: =430', 'Y: =474')
$screen = $screen.Replace('Y: =470', 'Y: =514')
$screen = $screen.Replace('Y: =510', 'Y: =554')
$screen = $screen.Replace('Y: =554', 'Y: =598')
$screen = $screen.Replace('Y: =588', 'Y: =632')

$escalateOld = @'
        EscalateButton As button:
            Color: =Color.White
            Fill: =ColorValue("#8a6a18")
            Height: =32
            OnSelect: =UpdateContext({varShowLog:true, varActionType:"Escalate"})
            Text: ="Escalate"
            Width: =96
            X: =302
            Y: =514
            ZIndex: =14
'@

$escalateNew = @'
        EscalateButton As button:
            Color: =Color.White
            DisplayMode: =If(IsBlank(WorkItemsGallery.Selected.'TSR Staff') Or Text(WorkItemsGallery.Selected.'Status (qfu_status)')="Closed Won" Or Text(WorkItemsGallery.Selected.'Status (qfu_status)')="Closed Lost" Or Text(WorkItemsGallery.Selected.'Status (qfu_status)')="Cancelled", DisplayMode.Disabled, DisplayMode.Edit)
            Fill: =ColorValue("#8a6a18")
            Height: =32
            OnSelect: |-
                =Patch('Work Items', WorkItemsGallery.Selected, {'Current Queue Owner Staff': WorkItemsGallery.Selected.'TSR Staff', 'Current Queue Role': 'Current Queue Role'.TSR, 'Queue Assigned On': Now(), 'Queue Handoff Count': Coalesce(WorkItemsGallery.Selected.'Queue Handoff Count', 0) + 1, 'Queue Handoff Reason': If(IsBlank(HandoffReasonInput.Value), "Escalated to TSR from Branch Workbench", HandoffReasonInput.Value)});
                Patch('Work Item Actions', Defaults('Work Item Actions'), {'Action Name': "Queue Handoff - " & WorkItemsGallery.Selected.'Work Item Number', 'Work Item': WorkItemsGallery.Selected, 'Action Type': 'QFU Action Type'.'Assignment/Reassignment', 'Action On': Now(), 'Counts As Attempt': false, Notes: If(IsBlank(HandoffReasonInput.Value), "Escalated to TSR from Branch Workbench", HandoffReasonInput.Value), Outcome: "TSR"});
                Refresh('Work Items'); Refresh('Work Item Actions'); UpdateContext({varQueueRoleFilter:"TSR", varRefreshStamp:Now()}); Notify("Queued to TSR.", NotificationType.Success)
            Text: ="Escalate to TSR"
            Width: =130
            X: =302
            Y: =514
            ZIndex: =14
'@
$screen = $screen.Replace($escalateOld, $escalateNew)
if ($screen -notmatch 'Text: ="Escalate to TSR"') {
    $screen = [regex]::Replace(
        $screen,
        '(?s)        EscalateButton As button:.*?        SendCssrButton As button:',
        ($escalateNew + "`r`n`r`n        SendCssrButton As button:"),
        1
    )
}

$sendCssr = @'

        SendCssrButton As button:
            Color: =Color.White
            DisplayMode: =If(IsBlank(WorkItemsGallery.Selected.'CSSR Staff') Or Text(WorkItemsGallery.Selected.'Status (qfu_status)')="Closed Won" Or Text(WorkItemsGallery.Selected.'Status (qfu_status)')="Closed Lost" Or Text(WorkItemsGallery.Selected.'Status (qfu_status)')="Cancelled", DisplayMode.Disabled, DisplayMode.Edit)
            Fill: =ColorValue("#0b4f66")
            Height: =32
            OnSelect: |-
                =Patch('Work Items', WorkItemsGallery.Selected, {'Current Queue Owner Staff': WorkItemsGallery.Selected.'CSSR Staff', 'Current Queue Role': 'Current Queue Role'.CSSR, 'Queue Assigned On': Now(), 'Queue Handoff Count': Coalesce(WorkItemsGallery.Selected.'Queue Handoff Count', 0) + 1, 'Queue Handoff Reason': If(IsBlank(HandoffReasonInput.Value), "Routed to CSSR from Branch Workbench", HandoffReasonInput.Value)});
                Patch('Work Item Actions', Defaults('Work Item Actions'), {'Action Name': "Queue Handoff - " & WorkItemsGallery.Selected.'Work Item Number', 'Work Item': WorkItemsGallery.Selected, 'Action Type': 'QFU Action Type'.'Assignment/Reassignment', 'Action On': Now(), 'Counts As Attempt': false, Notes: If(IsBlank(HandoffReasonInput.Value), "Routed to CSSR from Branch Workbench", HandoffReasonInput.Value), Outcome: "CSSR"});
                Refresh('Work Items'); Refresh('Work Item Actions'); UpdateContext({varQueueRoleFilter:"CSSR", varRefreshStamp:Now()}); Notify("Queued to CSSR.", NotificationType.Success)
            Text: ="Send to CSSR"
            Width: =120
            X: =266
            Y: =554
            ZIndex: =31
'@
$screen = $screen.Replace("        WonButton As button:", $sendCssr + "`r`n`r`n        WonButton As button:")
if ($screen -notmatch 'Text: ="Escalate to TSR"') {
    $screen = [regex]::Replace(
        $screen,
        '(?s)        EscalateButton As button:.*?        SendCssrButton As button:',
        ($escalateNew + "`r`n`r`n        SendCssrButton As button:"),
        1
    )
}
$screen = $screen.Replace('X: =16
            Y: =598
            ZIndex: =15', 'X: =16
            Y: =598
            ZIndex: =15')
$screen = $screen.Replace('Text: ="Action History"
            Width: =160
            X: =16
            Y: =598', 'Text: ="Action History"
            Width: =160
            X: =16
            Y: =638')
$screen = $screen.Replace('Height: =Parent.Height - 588
            Items:', 'Height: =Parent.Height - 684
            Items:')
$screen = $screen.Replace('X: =16
            Y: =582
            ZIndex: =19', 'X: =16
            Y: =668
            ZIndex: =19')

$hexToRgba = [ordered]@{
    'ColorValue("#21424d")' = 'RGBA(33, 66, 77, 1)'
    'ColorValue("#087a9b")' = 'RGBA(8, 122, 155, 1)'
    'ColorValue("#405765")' = 'RGBA(64, 87, 101, 1)'
    'ColorValue("#173540")' = 'RGBA(23, 53, 64, 1)'
    'ColorValue("#edf8fb")' = 'RGBA(237, 248, 251, 1)'
    'ColorValue("#9b2626")' = 'RGBA(155, 38, 38, 1)'
    'ColorValue("#8a6a18")' = 'RGBA(138, 106, 24, 1)'
    'ColorValue("#0b4f66")' = 'RGBA(11, 79, 102, 1)'
}
foreach ($entry in $hexToRgba.GetEnumerator()) {
    $screen = $screen.Replace($entry.Key, $entry.Value)
}

Set-Content -LiteralPath $screenPath -Value $screen -Encoding UTF8

$manifestPath = Join-Path $OutputSourcePath 'CanvasManifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$manifest.Properties.Name = 'Branch Workbench'
$manifest.PublishInfo.AppName = 'Branch Workbench'
$manifest | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

$workItemsDataSourcePath = Join-Path $OutputSourcePath 'DataSources\Work Items.json'
$workItemsDataSource = Get-Content -LiteralPath $workItemsDataSourcePath -Raw | ConvertFrom-Json
$workItemsNative = $workItemsDataSource | Where-Object { $_.Type -eq 'NativeCDSDataSourceInfo' -and $_.LogicalName -eq 'qfu_workitem' } | Select-Object -First 1
$mapping = $workItemsNative.NativeCDSDataSourceInfoNameMapping
$requiredMappings = [ordered]@{
    'qfu_CurrentQueueOwnerStaff' = 'Current Queue Owner Staff'
    'qfu_currentqueuerole' = 'Current Queue Role'
    'qfu_queueassignedon' = 'Queue Assigned On'
    'qfu_QueueAssignedBy' = 'Queue Assigned By'
    'qfu_queuehandoffreason' = 'Queue Handoff Reason'
    'qfu_queuehandoffcount' = 'Queue Handoff Count'
}
foreach ($entry in $requiredMappings.GetEnumerator()) {
    if (-not $mapping.PSObject.Properties[$entry.Key]) {
        $mapping | Add-Member -MemberType NoteProperty -Name $entry.Key -Value $entry.Value
    }
}
if (-not ($workItemsDataSource | Where-Object { $_.Type -eq 'OptionSetInfo' -and $_.Name -eq 'qfu_currentqueuerole' })) {
    $workItemsDataSource += [pscustomobject]@{
        DisplayName = 'Current Queue Role'
        Name = 'qfu_currentqueuerole'
        OptionSetInfoNameMapping = [ordered]@{
            '985020000' = 'TSR'
            '985020001' = 'CSSR'
            '985020002' = 'Manager'
            '985020003' = 'GM'
            '985020004' = 'Admin'
            '985020005' = 'Unassigned'
        }
        OptionSetIsBooleanValued = $false
        OptionSetIsGlobal = $false
        OptionSetReference = [ordered]@{
            OptionSetReferenceItem0 = [ordered]@{
                OptionSetReferenceColumnName = 'qfu_currentqueuerole'
                OptionSetReferenceEntityName = 'Work Items'
            }
        }
        OptionSetTypeKey = 'PicklistType'
        RelatedColumnInvariantName = 'qfu_currentqueuerole'
        RelatedEntityName = 'Work Items'
        Type = 'OptionSetInfo'
    }
}
$workItemsDataSource | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $workItemsDataSourcePath -Encoding UTF8

Write-Host "Generated Phase 5 Branch Workbench canvas source at $OutputSourcePath"
