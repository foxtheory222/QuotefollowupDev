param(
    [Parameter(Mandatory = $true)]
    [string]$BaseSourcePath,

    [Parameter(Mandatory = $true)]
    [string]$OutputSourcePath
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $BaseSourcePath)) {
    throw "Base source path not found: $BaseSourcePath"
}

if (Test-Path -LiteralPath $OutputSourcePath) {
    Remove-Item -LiteralPath $OutputSourcePath -Recurse -Force
}

Copy-Item -LiteralPath $BaseSourcePath -Destination $OutputSourcePath -Recurse -Force

$screenFx = @'
"Screen1 As screen.'teamsHeroApp_ver1.0'":
    Fill: =ColorValue("#f5f8fa")
    LoadingSpinnerColor: =RGBA(0, 120, 212, 1)
    OnVisible: |-
        =UpdateContext({varActiveTab:"All Open", varShowLog:false, varActionType:"Call", varRefreshStamp:Now()});

    HeaderBand As rectangle:
        Fill: =ColorValue("#0b4f66")
        Height: =76
        Width: =Parent.Width
        ZIndex: =1

    HeaderTitle As label:
        Color: =Color.White
        Font: =Font.'Segoe UI'
        FontWeight: =FontWeight.Semibold
        Height: =34
        Size: =22
        Text: ="My Work"
        Width: =260
        X: =24
        Y: =10
        ZIndex: =2

    HeaderContext As label:
        Color: =ColorValue("#d9edf2")
        Font: =Font.'Segoe UI'
        Height: =24
        Size: =10
        Text: ="Branch/team queue with staff filter fallback | " & Text(Today(), "[$-en-US]mmm d, yyyy")
        Width: =620
        X: =26
        Y: =44
        ZIndex: =3

    RefreshStamp As label:
        Align: =Align.Right
        Color: =ColorValue("#d9edf2")
        Font: =Font.'Segoe UI'
        Height: =24
        Size: =10
        Text: ="Refreshed " & Text(varRefreshStamp, "[$-en-US]h:mm AM/PM")
        Width: =260
        X: =Parent.Width - Self.Width - 150
        Y: =26
        ZIndex: =4

    RefreshButton As button:
        BorderColor: =ColorValue("#d9edf2")
        Color: =Color.White
        Fill: =ColorValue("#087a9b")
        Font: =Font.'Segoe UI'
        Height: =36
        HoverFill: =ColorValue("#0a6d88")
        OnSelect: |-
            =Refresh('Work Items'); Refresh('Work Item Actions'); Refresh('Assignment Exceptions'); UpdateContext({varRefreshStamp:Now()}); Notify("My Work data refreshed.", NotificationType.Success)
        Text: ="Refresh"
        Width: =110
        X: =Parent.Width - Self.Width - 24
        Y: =20
        ZIndex: =5

    BranchFilterLabel As label:
        Color: =ColorValue("#405765")
        Font: =Font.'Segoe UI'
        FontWeight: =FontWeight.Semibold
        Height: =20
        Size: =9
        Text: ="Branch/team filter"
        Width: =160
        X: =24
        Y: =88
        ZIndex: =6

    "BranchFilterInput As 'Text box'":
        AccessibleLabel: ="Branch/team filter"
        DisplayMode: =DisplayMode.Edit
        FontSize: =10
        Height: =32
        Mode: ="SingleLine"
        Placeholder: ="4171 or branch"
        Value: =""
        Width: =190
        X: =24
        Y: =110
        ZIndex: =7

    StaffFilterLabel As label:
        Color: =ColorValue("#405765")
        Font: =Font.'Segoe UI'
        FontWeight: =FontWeight.Semibold
        Height: =20
        Size: =9
        Text: ="Staff dropdown/filter"
        Width: =170
        X: =230
        Y: =88
        ZIndex: =8

    "StaffFilterInput As 'Text box'":
        AccessibleLabel: ="Staff filter fallback"
        DisplayMode: =DisplayMode.Edit
        FontSize: =10
        Height: =32
        Mode: ="SingleLine"
        Placeholder: ="TSR or CSSR name"
        Value: =""
        Width: =210
        X: =230
        Y: =110
        ZIndex: =9

    FilterNote As label:
        Color: =ColorValue("#607987")
        Font: =Font.'Segoe UI'
        Height: =38
        Size: =9
        Text: ="Current-user staff mapping is not ready, so Phase 4B uses branch/team and staff-name filters."
        Width: =430
        X: =460
        Y: =100
        ZIndex: =10

    DueTodayCard As button:
        Align: =Align.Left
        BorderColor: =ColorValue("#bdd6df")
        Color: =ColorValue("#173540")
        Fill: =Color.White
        Font: =Font.'Segoe UI'
        Height: =58
        OnSelect: =UpdateContext({varActiveTab:"Due Today"})
        PaddingLeft: =14
        Text: ="Due Today" & Char(10) & Text(CountRows(Filter('Work Items', Text('Status (qfu_status)') = "Due Today")))
        Width: =150
        X: =24
        Y: =154
        ZIndex: =11

    OverdueCard As button:
        Align: =Align.Left
        BorderColor: =ColorValue("#e1b8b8")
        Color: =ColorValue("#5a1c1c")
        Fill: =ColorValue("#fff4f4")
        Font: =Font.'Segoe UI'
        FontWeight: =FontWeight.Semibold
        Height: =58
        OnSelect: =UpdateContext({varActiveTab:"Overdue"})
        PaddingLeft: =14
        Text: ="Overdue" & Char(10) & Text(CountRows(Filter('Work Items', Text('Status (qfu_status)') = "Overdue")))
        Width: =150
        X: =184
        Y: =154
        ZIndex: =12

    HighValueCard As button:
        Align: =Align.Left
        BorderColor: =ColorValue("#bdd6df")
        Color: =ColorValue("#173540")
        Fill: =Color.White
        Font: =Font.'Segoe UI'
        Height: =58
        OnSelect: =UpdateContext({varActiveTab:"High Value"})
        PaddingLeft: =14
        Text: ="Quotes >= $3K" & Char(10) & Text(CountRows(Filter('Work Items', 'Total Value' >= 3000)))
        Width: =150
        X: =344
        Y: =154
        ZIndex: =13

    MissingAttemptsCard As button:
        Align: =Align.Left
        BorderColor: =ColorValue("#bdd6df")
        Color: =ColorValue("#173540")
        Fill: =Color.White
        Font: =Font.'Segoe UI'
        Height: =58
        OnSelect: =UpdateContext({varActiveTab:"Needs Attempts"})
        PaddingLeft: =14
        Text: ="Missing Attempts" & Char(10) & Text(CountRows(Filter('Work Items', Coalesce('Completed Attempts', 0) < Coalesce('Required Attempts', 3))))
        Width: =170
        X: =504
        Y: =154
        ZIndex: =14

    RoadblocksCard As button:
        Align: =Align.Left
        BorderColor: =ColorValue("#bdd6df")
        Color: =ColorValue("#173540")
        Fill: =Color.White
        Font: =Font.'Segoe UI'
        Height: =58
        OnSelect: =UpdateContext({varActiveTab:"Roadblocks"})
        PaddingLeft: =14
        Text: ="Roadblocks" & Char(10) & Text(CountRows(Filter('Work Items', Text('Status (qfu_status)') = "Roadblock")))
        Width: =150
        X: =684
        Y: =154
        ZIndex: =15

    AssignmentIssuesCard As button:
        Align: =Align.Left
        BorderColor: =ColorValue("#d6c6a3")
        Color: =ColorValue("#4f3910")
        Fill: =ColorValue("#fff9ec")
        Font: =Font.'Segoe UI'
        Height: =58
        OnSelect: =UpdateContext({varActiveTab:"Assignment Issues"})
        PaddingLeft: =14
        Text: ="Assignment Issues" & Char(10) & Text(CountRows(Filter('Work Items', 'Assignment Status' <> 'QFU Assignment Status'.Assigned)))
        Width: =180
        X: =844
        Y: =154
        ZIndex: =16

    OverdueTab As button:
        Color: =If(varActiveTab="Overdue", Color.White, ColorValue("#21424d"))
        Fill: =If(varActiveTab="Overdue", ColorValue("#9b2626"), Color.White)
        Height: =34
        OnSelect: =UpdateContext({varActiveTab:"Overdue"})
        Text: ="Overdue"
        Width: =110
        X: =24
        Y: =226
        ZIndex: =17

    DueTodayTab As button:
        Color: =If(varActiveTab="Due Today", Color.White, ColorValue("#21424d"))
        Fill: =If(varActiveTab="Due Today", ColorValue("#087a9b"), Color.White)
        Height: =34
        OnSelect: =UpdateContext({varActiveTab:"Due Today"})
        Text: ="Due Today"
        Width: =120
        X: =140
        Y: =226
        ZIndex: =18

    HighValueTab As button:
        Color: =If(varActiveTab="High Value", Color.White, ColorValue("#21424d"))
        Fill: =If(varActiveTab="High Value", ColorValue("#087a9b"), Color.White)
        Height: =34
        OnSelect: =UpdateContext({varActiveTab:"High Value"})
        Text: ="High Value"
        Width: =120
        X: =266
        Y: =226
        ZIndex: =19

    NeedsAttemptsTab As button:
        Color: =If(varActiveTab="Needs Attempts", Color.White, ColorValue("#21424d"))
        Fill: =If(varActiveTab="Needs Attempts", ColorValue("#087a9b"), Color.White)
        Height: =34
        OnSelect: =UpdateContext({varActiveTab:"Needs Attempts"})
        Text: ="Needs Attempts"
        Width: =150
        X: =392
        Y: =226
        ZIndex: =20

    WaitingTab As button:
        Color: =If(varActiveTab="Waiting", Color.White, ColorValue("#21424d"))
        Fill: =If(varActiveTab="Waiting", ColorValue("#087a9b"), Color.White)
        Height: =34
        OnSelect: =UpdateContext({varActiveTab:"Waiting"})
        Text: ="Waiting"
        Width: =105
        X: =548
        Y: =226
        ZIndex: =21

    RoadblocksTab As button:
        Color: =If(varActiveTab="Roadblocks", Color.White, ColorValue("#21424d"))
        Fill: =If(varActiveTab="Roadblocks", ColorValue("#087a9b"), Color.White)
        Height: =34
        OnSelect: =UpdateContext({varActiveTab:"Roadblocks"})
        Text: ="Roadblocks"
        Width: =125
        X: =659
        Y: =226
        ZIndex: =22

    AllOpenTab As button:
        Color: =If(varActiveTab="All Open", Color.White, ColorValue("#21424d"))
        Fill: =If(varActiveTab="All Open", ColorValue("#087a9b"), Color.White)
        Height: =34
        OnSelect: =UpdateContext({varActiveTab:"All Open"})
        Text: ="All Open"
        Width: =110
        X: =790
        Y: =226
        ZIndex: =23

    AssignmentIssuesTab As button:
        Color: =If(varActiveTab="Assignment Issues", Color.White, ColorValue("#21424d"))
        Fill: =If(varActiveTab="Assignment Issues", ColorValue("#8a6a18"), Color.White)
        Height: =34
        OnSelect: =UpdateContext({varActiveTab:"Assignment Issues"})
        Text: ="Assignment Issues"
        Width: =170
        X: =906
        Y: =226
        ZIndex: =24

    ListHeader As label:
        Color: =ColorValue("#516b78")
        Font: =Font.'Segoe UI'
        FontWeight: =FontWeight.Semibold
        Height: =24
        Size: =10
        Text: ="Priority     Status       Quote / Source Document       Customer       Value       Attempts       Next Follow-Up       Last Followed Up       Sticky Note"
        Width: =820
        X: =24
        Y: =274
        ZIndex: =25

    WorkItemsGallery As gallery.BrowseLayout_Vertical_TwoTextOneImageVariant_pcfCore:
        BorderColor: =ColorValue("#d7e3e8")
        Default: =First(Self.AllItems)
        DelayItemLoading: =true
        Fill: =Color.White
        FocusedBorderColor: =ColorValue("#087a9b")
        Height: =Parent.Height - 314
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
        Layout: =Layout.Vertical
        LoadingSpinner: =LoadingSpinner.Data
        OnSelect: =UpdateContext({varShowLog:false})
        TemplateFill: =If(ThisItem.IsSelected, ColorValue("#edf8fb"), If(Text(ThisItem.'Status (qfu_status)') = "Overdue", ColorValue("#fff4f4"), If(Text(ThisItem.'Status (qfu_status)') = "Due Today", ColorValue("#eef9fc"), Color.White)))
        TemplatePadding: =0
        TemplateSize: =64
        Width: =820
        X: =24
        Y: =304
        ZIndex: =26

        RowDivider As rectangle:
            Fill: =ColorValue("#dbe7ec")
            Height: =1
            OnSelect: =Select(Parent)
            Width: =Parent.TemplateWidth
            Y: =Parent.TemplateHeight - 1
            ZIndex: =1

        RowStatusBand As rectangle:
            Fill: =If(Text(ThisItem.'Status (qfu_status)') = "Overdue", ColorValue("#b3261e"), If(Text(ThisItem.'Status (qfu_status)') = "Due Today", ColorValue("#087a9b"), ColorValue("#6b8791")))
            Height: =Parent.TemplateHeight
            OnSelect: =Select(Parent)
            Width: =5
            ZIndex: =2

        RowTitle As label:
            Color: =ColorValue("#102d38")
            Font: =Font.'Segoe UI'
            FontWeight: =FontWeight.Semibold
            Height: =22
            OnSelect: =Select(Parent)
            Size: =10
            Text: =Coalesce(ThisItem.'Source Document Number', ThisItem.'Work Item Number')
            Width: =160
            X: =16
            Y: =8
            ZIndex: =3

        RowCustomer As label:
            Color: =ColorValue("#304f5b")
            Font: =Font.'Segoe UI'
            Height: =22
            OnSelect: =Select(Parent)
            Size: =9
            Text: =Coalesce(ThisItem.'Customer Name', "Customer not loaded")
            Width: =230
            X: =16
            Y: =32
            ZIndex: =4

        RowStatus As label:
            Align: =Align.Center
            Color: =If(Text(ThisItem.'Status (qfu_status)') = "Overdue", ColorValue("#7b1515"), ColorValue("#0b4f66"))
            Fill: =If(Text(ThisItem.'Status (qfu_status)') = "Overdue", ColorValue("#ffe5e5"), ColorValue("#e4f5f8"))
            Font: =Font.'Segoe UI'
            FontWeight: =FontWeight.Semibold
            Height: =24
            OnSelect: =Select(Parent)
            Size: =8
            Text: =Text(ThisItem.'Status (qfu_status)')
            Width: =92
            X: =260
            Y: =8
            ZIndex: =5

        RowAssignment As label:
            Align: =Align.Center
            Color: =If(ThisItem.'Assignment Status' = 'QFU Assignment Status'.Assigned, ColorValue("#185b2b"), ColorValue("#664a0c"))
            Fill: =If(ThisItem.'Assignment Status' = 'QFU Assignment Status'.Assigned, ColorValue("#e8f6ec"), ColorValue("#fff4d6"))
            Font: =Font.'Segoe UI'
            Height: =24
            OnSelect: =Select(Parent)
            Size: =8
            Text: =Text(ThisItem.'Assignment Status')
            Width: =112
            X: =360
            Y: =8
            ZIndex: =6

        RowValue As label:
            Align: =Align.Right
            Color: =ColorValue("#102d38")
            Font: =Font.'Segoe UI'
            FontWeight: =FontWeight.Semibold
            Height: =22
            OnSelect: =Select(Parent)
            Size: =9
            Text: =Text(ThisItem.'Total Value', "[$-en-US]$0")
            Width: =92
            X: =486
            Y: =10
            ZIndex: =7

        RowAttempts As label:
            Align: =Align.Center
            Color: =ColorValue("#102d38")
            Font: =Font.'Segoe UI'
            FontWeight: =FontWeight.Semibold
            Height: =22
            OnSelect: =Select(Parent)
            Size: =9
            Text: =Text(Coalesce(ThisItem.'Completed Attempts', 0)) & "/" & Text(Coalesce(ThisItem.'Required Attempts', 3))
            Width: =70
            X: =594
            Y: =10
            ZIndex: =8

        RowNextFollowUp As label:
            Color: =ColorValue("#304f5b")
            Font: =Font.'Segoe UI'
            Height: =22
            OnSelect: =Select(Parent)
            Size: =8
            Text: =If(IsBlank(ThisItem.'Next Follow-Up On'), "No next date", Text(ThisItem.'Next Follow-Up On', "[$-en-US]mmm d"))
            Width: =90
            X: =672
            Y: =10
            ZIndex: =9

        RowSticky As label:
            Color: =ColorValue("#516b78")
            Font: =Font.'Segoe UI'
            Height: =22
            OnSelect: =Select(Parent)
            Size: =8
            Text: =If(IsBlank(ThisItem.'Sticky Note'), "No sticky note", Left(ThisItem.'Sticky Note', 42))
            Width: =300
            X: =260
            Y: =34
            ZIndex: =10

        RowNextAction As label:
            Color: =ColorValue("#0b4f66")
            Font: =Font.'Segoe UI'
            FontWeight: =FontWeight.Semibold
            Height: =22
            OnSelect: =Select(Parent)
            Size: =8
            Text: =If(Coalesce(ThisItem.'Completed Attempts', 0) < Coalesce(ThisItem.'Required Attempts', 3), "Log follow-up", "Review/close")
            Width: =130
            X: =672
            Y: =34
            ZIndex: =11

    DetailPanel As groupContainer:
        DropShadow: =DropShadow.Light
        Fill: =Color.White
        Height: =Parent.Height - 100
        RadiusBottomLeft: =6
        RadiusBottomRight: =6
        RadiusTopLeft: =6
        RadiusTopRight: =6
        Width: =Parent.Width - 1114
        X: =1090
        Y: =100
        ZIndex: =27

        DetailTitle As label:
            Color: =ColorValue("#102d38")
            Font: =Font.'Segoe UI'
            FontWeight: =FontWeight.Semibold
            Height: =28
            Size: =15
            Text: =Coalesce(WorkItemsGallery.Selected.'Source Document Number', WorkItemsGallery.Selected.'Work Item Number', "Select a work item")
            Width: =Parent.Width - 32
            X: =16
            Y: =14
            ZIndex: =1

        DetailSummary As label:
            Color: =ColorValue("#405765")
            Font: =Font.'Segoe UI'
            Height: =76
            Size: =10
            Text: |-
                ="Customer: " & Coalesce(WorkItemsGallery.Selected.'Customer Name', "not loaded") & Char(10) &
                "Value: " & Text(WorkItemsGallery.Selected.'Total Value', "[$-en-US]$0.00") & " | Attempts: " & Text(Coalesce(WorkItemsGallery.Selected.'Completed Attempts', 0)) & "/" & Text(Coalesce(WorkItemsGallery.Selected.'Required Attempts', 3)) & Char(10) &
                "Status: " & Text(WorkItemsGallery.Selected.'Status (qfu_status)') & " | Assignment: " & Text(WorkItemsGallery.Selected.'Assignment Status')
            Width: =Parent.Width - 32
            X: =16
            Y: =48
            ZIndex: =2

        DetailDates As label:
            Color: =ColorValue("#405765")
            Font: =Font.'Segoe UI'
            Height: =58
            Size: =9
            Text: |-
                ="Next follow-up: " & If(IsBlank(WorkItemsGallery.Selected.'Next Follow-Up On'), "not set", Text(WorkItemsGallery.Selected.'Next Follow-Up On', "[$-en-US]mmm d, yyyy h:mm AM/PM")) & Char(10) &
                "Last followed up: " & If(IsBlank(WorkItemsGallery.Selected.'Last Followed Up On'), "none", Text(WorkItemsGallery.Selected.'Last Followed Up On', "[$-en-US]mmm d, yyyy h:mm AM/PM")) & Char(10) &
                "Last action: " & If(IsBlank(WorkItemsGallery.Selected.'Last Action On'), "none", Text(WorkItemsGallery.Selected.'Last Action On', "[$-en-US]mmm d, yyyy h:mm AM/PM"))
            Width: =Parent.Width - 32
            X: =16
            Y: =126
            ZIndex: =3

        DetailOwners As label:
            Color: =ColorValue("#405765")
            Font: =Font.'Segoe UI'
            Height: =46
            Size: =9
            Text: ="TSR: " & Coalesce(WorkItemsGallery.Selected.'TSR Staff'.'Staff Name', "Unassigned") & Char(10) & "CSSR: " & Coalesce(WorkItemsGallery.Selected.'CSSR Staff'.'Staff Name', "Unassigned") & " | Branch: " & Coalesce(WorkItemsGallery.Selected.Branch.'Branch Code', "")
            Width: =Parent.Width - 32
            X: =16
            Y: =190
            ZIndex: =4

        StickyNoteLabel As label:
            Color: =ColorValue("#664a0c")
            Font: =Font.'Segoe UI'
            FontWeight: =FontWeight.Semibold
            Height: =22
            Size: =10
            Text: ="Sticky Note"
            Width: =140
            X: =16
            Y: =246
            ZIndex: =5

        "StickyNoteInput As 'Text box'":
            AccessibleLabel: ="Sticky note"
            DisplayMode: =DisplayMode.Edit
            FontSize: =10
            Height: =82
            Mode: ="Multiline"
            Value: =Coalesce(WorkItemsGallery.Selected.'Sticky Note', "")
            Width: =Parent.Width - 32
            X: =16
            Y: =272
            ZIndex: =6

        StickyUpdatedLabel As label:
            Color: =ColorValue("#607987")
            Font: =Font.'Segoe UI'
            Height: =20
            Size: =8
            Text: ="Updated: " & If(IsBlank(WorkItemsGallery.Selected.'Sticky Note Updated On'), "not yet", Text(WorkItemsGallery.Selected.'Sticky Note Updated On', "[$-en-US]mmm d, h:mm AM/PM"))
            Width: =Parent.Width - 32
            X: =16
            Y: =358
            ZIndex: =7

        SaveStickyButton As button:
            Color: =Color.White
            Fill: =ColorValue("#087a9b")
            Height: =32
            OnSelect: |-
                =Patch('Work Items', WorkItemsGallery.Selected, {'Sticky Note': StickyNoteInput.Value, 'Sticky Note Updated On': Now()}); Refresh('Work Items'); UpdateContext({varRefreshStamp:Now()}); Notify("Sticky note saved.", NotificationType.Success)
            Text: ="Save Sticky Note"
            Width: =150
            X: =16
            Y: =382
            ZIndex: =8

        LogCallButton As button:
            Color: =Color.White
            Fill: =ColorValue("#0b4f66")
            Height: =32
            OnSelect: =UpdateContext({varShowLog:true, varActionType:"Call"})
            Text: ="Log Call"
            Width: =96
            X: =16
            Y: =430
            ZIndex: =9

        LogEmailButton As button:
            Color: =Color.White
            Fill: =ColorValue("#0b4f66")
            Height: =32
            OnSelect: =UpdateContext({varShowLog:true, varActionType:"Email"})
            Text: ="Log Email"
            Width: =100
            X: =120
            Y: =430
            ZIndex: =10

        CustomerAdvisedButton As button:
            Color: =Color.White
            Fill: =ColorValue("#0b4f66")
            Height: =32
            OnSelect: =UpdateContext({varShowLog:true, varActionType:"Customer Advised"})
            Text: ="Customer Advised"
            Width: =150
            X: =228
            Y: =430
            ZIndex: =11

        SetNextButton As button:
            Color: =ColorValue("#173540")
            Fill: =ColorValue("#e4f5f8")
            Height: =32
            OnSelect: =UpdateContext({varShowLog:true, varActionType:"Set Next Follow-Up"})
            Text: ="Set Next Follow-Up"
            Width: =160
            X: =16
            Y: =470
            ZIndex: =12

        RoadblockButton As button:
            Color: =Color.White
            Fill: =ColorValue("#9b2626")
            Height: =32
            OnSelect: =UpdateContext({varShowLog:true, varActionType:"Roadblock"})
            Text: ="Roadblock"
            Width: =110
            X: =184
            Y: =470
            ZIndex: =13

        EscalateButton As button:
            Color: =Color.White
            Fill: =ColorValue("#8a6a18")
            Height: =32
            OnSelect: =UpdateContext({varShowLog:true, varActionType:"Escalate"})
            Text: ="Escalate"
            Width: =96
            X: =302
            Y: =470
            ZIndex: =14

        WonButton As button:
            Color: =Color.White
            Fill: =ColorValue("#1f7a3d")
            Height: =32
            OnSelect: =UpdateContext({varShowLog:true, varActionType:"Won"})
            Text: ="Won"
            Width: =72
            X: =16
            Y: =510
            ZIndex: =15

        LostButton As button:
            Color: =Color.White
            Fill: =ColorValue("#576b74")
            Height: =32
            OnSelect: =UpdateContext({varShowLog:true, varActionType:"Lost"})
            Text: ="Lost"
            Width: =72
            X: =96
            Y: =510
            ZIndex: =16

        NoteButton As button:
            Color: =ColorValue("#173540")
            Fill: =ColorValue("#e8f0f3")
            Height: =32
            OnSelect: =UpdateContext({varShowLog:true, varActionType:"Note"})
            Text: ="Note"
            Width: =82
            X: =176
            Y: =510
            ZIndex: =17

        HistoryLabel As label:
            Color: =ColorValue("#102d38")
            Font: =Font.'Segoe UI'
            FontWeight: =FontWeight.Semibold
            Height: =24
            Size: =10
            Text: ="Action History"
            Width: =160
            X: =16
            Y: =554
            ZIndex: =18

        ActionHistoryGallery As gallery.BrowseLayout_Vertical_TwoTextOneImageVariant_pcfCore:
            BorderColor: =ColorValue("#d7e3e8")
            Fill: =ColorValue("#fbfdfe")
            Height: =Parent.Height - 588
            Items: =FirstN(SortByColumns(Filter('Work Item Actions', EndsWith('Action Name', WorkItemsGallery.Selected.'Work Item Number')), "qfu_actionon", SortOrder.Descending), 12)
            Layout: =Layout.Vertical
            LoadingSpinner: =LoadingSpinner.Data
            TemplateFill: =Color.Transparent
            TemplatePadding: =0
            TemplateSize: =46
            Width: =Parent.Width - 32
            X: =16
            Y: =582
            ZIndex: =19

            ActionHistoryTitle As label:
                Color: =ColorValue("#102d38")
                Font: =Font.'Segoe UI'
                FontWeight: =FontWeight.Semibold
                Height: =20
                OnSelect: =Select(Parent)
                Size: =8
                Text: =Text(ThisItem.'Action Type') & " | " & If(ThisItem.'Counts As Attempt', "Attempt", "Non-attempt")
                Width: =Parent.TemplateWidth - 10
                X: =4
                Y: =4
                ZIndex: =1

            ActionHistorySub As label:
                Color: =ColorValue("#607987")
                Font: =Font.'Segoe UI'
                Height: =20
                OnSelect: =Select(Parent)
                Size: =8
                Text: =If(IsBlank(ThisItem.'Action On'), "No action time", Text(ThisItem.'Action On', "[$-en-US]mmm d h:mm AM/PM")) & " | " & Left(Coalesce(ThisItem.Notes, ""), 48)
                Width: =Parent.TemplateWidth - 10
                X: =4
                Y: =24
                ZIndex: =2

    LogModalOverlay As rectangle:
        Fill: =RGBA(0, 0, 0, 0.25)
        Height: =Parent.Height
        Visible: =varShowLog
        Width: =Parent.Width
        ZIndex: =40

    LogModal As groupContainer:
        DropShadow: =DropShadow.Semibold
        Fill: =Color.White
        Height: =480
        RadiusBottomLeft: =8
        RadiusBottomRight: =8
        RadiusTopLeft: =8
        RadiusTopRight: =8
        Visible: =varShowLog
        Width: =560
        X: =(Parent.Width - Self.Width) / 2
        Y: =120
        ZIndex: =41

        LogTitle As label:
            Color: =ColorValue("#102d38")
            Font: =Font.'Segoe UI'
            FontWeight: =FontWeight.Semibold
            Height: =34
            Size: =16
            Text: ="Log Follow-Up - " & varActionType
            Width: =Parent.Width - 32
            X: =18
            Y: =16
            ZIndex: =1

        LogDefaults As label:
            Color: =ColorValue("#607987")
            Font: =Font.'Segoe UI'
            Height: =40
            Size: =9
            Text: ="Followed Up On defaults to now. Call, Email, and Customer Advised count as attempts. Roadblock requires notes."
            Width: =Parent.Width - 36
            X: =18
            Y: =52
            ZIndex: =2

        FollowedUpOnLabel As label:
            Color: =ColorValue("#405765")
            FontWeight: =FontWeight.Semibold
            Height: =20
            Size: =9
            Text: ="Followed Up On"
            Width: =160
            X: =18
            Y: =96
            ZIndex: =3

        "FollowedUpOnInput As 'Text box'":
            AccessibleLabel: ="Followed up on"
            DisplayMode: =DisplayMode.Edit
            FontSize: =10
            Height: =32
            Mode: ="SingleLine"
            Placeholder: ="m/d/yyyy h:mm AM/PM"
            Value: =Text(Now(), "[$-en-US]m/d/yyyy h:mm AM/PM")
            Width: =250
            X: =18
            Y: =120
            ZIndex: =4

        ActionNotesLabel As label:
            Color: =ColorValue("#405765")
            FontWeight: =FontWeight.Semibold
            Height: =20
            Size: =9
            Text: ="Follow-Up Notes"
            Width: =160
            X: =18
            Y: =164
            ZIndex: =5

        "ActionNotesInput As 'Text box'":
            AccessibleLabel: ="Follow-up notes"
            DisplayMode: =DisplayMode.Edit
            FontSize: =10
            Height: =96
            Mode: ="Multiline"
            Placeholder: ="What happened?"
            Value: =""
            Width: =Parent.Width - 36
            X: =18
            Y: =188
            ZIndex: =6

        OutcomeLabel As label:
            Color: =ColorValue("#405765")
            FontWeight: =FontWeight.Semibold
            Height: =20
            Size: =9
            Text: ="Outcome"
            Width: =100
            X: =18
            Y: =296
            ZIndex: =7

        "OutcomeInput As 'Text box'":
            AccessibleLabel: ="Outcome"
            DisplayMode: =DisplayMode.Edit
            FontSize: =10
            Height: =32
            Mode: ="SingleLine"
            Placeholder: ="Optional outcome"
            Value: =""
            Width: =250
            X: =18
            Y: =320
            ZIndex: =8

        NextFollowUpLabel As label:
            Color: =ColorValue("#405765")
            FontWeight: =FontWeight.Semibold
            Height: =20
            Size: =9
            Text: ="Next Follow-Up On"
            Width: =160
            X: =288
            Y: =296
            ZIndex: =9

        "NextFollowUpInput As 'Text box'":
            AccessibleLabel: ="Next follow-up on"
            DisplayMode: =DisplayMode.Edit
            FontSize: =10
            Height: =32
            Mode: ="SingleLine"
            Placeholder: ="yyyy-mm-dd or blank"
            Value: =""
            Width: =250
            X: =288
            Y: =320
            ZIndex: =10

        CountsLabel As label:
            Color: =ColorValue("#405765")
            Font: =Font.'Segoe UI'
            Height: =24
            Size: =10
            Text: ="Counts As Attempt: " & If(Or(varActionType="Call", varActionType="Email", varActionType="Customer Advised"), "Yes", "No")
            Width: =260
            X: =18
            Y: =366
            ZIndex: =11

        SaveActionButton As button:
            Color: =Color.White
            Fill: =ColorValue("#087a9b")
            Height: =38
            OnSelect: |-
                =If(
                    And(varActionType="Roadblock", IsBlank(ActionNotesInput.Value)),
                    Notify("Roadblock requires a follow-up note.", NotificationType.Error),
                    If(
                        And(Or(varActionType="Call", varActionType="Email", varActionType="Customer Advised"), IsBlank(FollowedUpOnInput.Value)),
                        Notify("Followed Up On is required for attempt actions.", NotificationType.Error),
                        If(
                            And(!IsBlank(NextFollowUpInput.Value), DateValue(NextFollowUpInput.Value) < IfError(DateValue(FollowedUpOnInput.Value), Today())),
                            Notify("Next Follow-Up cannot be before Followed Up On.", NotificationType.Error),
                            Set(varActionOn, If(IsBlank(FollowedUpOnInput.Value), Now(), IfError(DateTimeValue(FollowedUpOnInput.Value), Now())));
                        Set(varCountsAsAttempt, Or(varActionType="Call", varActionType="Email", varActionType="Customer Advised"));
                        Patch(
                            'Work Item Actions',
                            Defaults('Work Item Actions'),
                            {
                                'Action Name': varActionType & " - " & WorkItemsGallery.Selected.'Work Item Number',
                                'Work Item': WorkItemsGallery.Selected,
                                'Action Type': Switch(varActionType, "Call", 'QFU Action Type'.Call, "Email", 'QFU Action Type'.Email, "Customer Advised", 'QFU Action Type'.'Customer Advised', "Roadblock", 'QFU Action Type'.Roadblock, "Escalate", 'QFU Action Type'.Escalated, "Won", 'QFU Action Type'.Won, "Lost", 'QFU Action Type'.Lost, "Set Next Follow-Up", 'QFU Action Type'.'Due Date Updated', "Note", 'QFU Action Type'.Note, 'QFU Action Type'.Note),
                                'Action On': varActionOn,
                                'Counts As Attempt': varCountsAsAttempt,
                                Notes: ActionNotesInput.Value,
                                Outcome: OutcomeInput.Value,
                                'Next Follow-Up On': If(IsBlank(NextFollowUpInput.Value), Blank(), DateValue(NextFollowUpInput.Value))
                            }
                        );
                        Patch(
                            'Work Items',
                            WorkItemsGallery.Selected,
                            {
                                'Completed Attempts': Coalesce(WorkItemsGallery.Selected.'Completed Attempts', 0) + If(varCountsAsAttempt, 1, 0),
                                'Last Action On': varActionOn,
                                'Last Followed Up On': If(varCountsAsAttempt, varActionOn, WorkItemsGallery.Selected.'Last Followed Up On'),
                                'Next Follow-Up On': If(IsBlank(NextFollowUpInput.Value), WorkItemsGallery.Selected.'Next Follow-Up On', DateValue(NextFollowUpInput.Value)),
                                'Status (qfu_status)': Switch(
                                    varActionType,
                                    "Roadblock", 'QFU Work Item Status'.Roadblock,
                                    "Escalate", 'QFU Work Item Status'.Escalated,
                                    "Won", 'QFU Work Item Status'.'Closed Won',
                                    "Lost", 'QFU Work Item Status'.'Closed Lost',
                                    If(
                                        !IsBlank(NextFollowUpInput.Value),
                                        If(
                                            Or(
                                                WorkItemsGallery.Selected.'Status (qfu_status)' = 'QFU Work Item Status'.Roadblock,
                                                WorkItemsGallery.Selected.'Status (qfu_status)' = 'QFU Work Item Status'.Escalated,
                                                WorkItemsGallery.Selected.'Status (qfu_status)' = 'QFU Work Item Status'.Completed,
                                                WorkItemsGallery.Selected.'Status (qfu_status)' = 'QFU Work Item Status'.'Closed Won',
                                                WorkItemsGallery.Selected.'Status (qfu_status)' = 'QFU Work Item Status'.'Closed Lost',
                                                WorkItemsGallery.Selected.'Status (qfu_status)' = 'QFU Work Item Status'.Cancelled,
                                                WorkItemsGallery.Selected.'Status (qfu_status)' = 'QFU Work Item Status'.'Waiting on Customer',
                                                WorkItemsGallery.Selected.'Status (qfu_status)' = 'QFU Work Item Status'.'Waiting on Vendor'
                                            ),
                                            WorkItemsGallery.Selected.'Status (qfu_status)',
                                            'QFU Work Item Status'.Open
                                        ),
                                        WorkItemsGallery.Selected.'Status (qfu_status)'
                                    )
                                )
                            }
                        );
                        Reset(ActionNotesInput); Reset(OutcomeInput); Reset(NextFollowUpInput); Reset(FollowedUpOnInput);
                        Refresh('Work Item Actions'); Refresh('Work Items');
                        UpdateContext({varShowLog:false, varRefreshStamp:Now()});
                        Notify("Follow-up saved.", NotificationType.Success)
                        )
                    )
                )
            Text: ="Save Follow-Up"
            Width: =150
            X: =18
            Y: =414
            ZIndex: =12

        CancelLogButton As button:
            Color: =ColorValue("#173540")
            Fill: =ColorValue("#e8f0f3")
            Height: =38
            OnSelect: =UpdateContext({varShowLog:false})
            Text: ="Cancel"
            Width: =100
            X: =180
            Y: =414
            ZIndex: =13
'@

$srcPath = Join-Path $OutputSourcePath 'Src\Screen1.fx.yaml'
$screenFx = [regex]::Replace($screenFx, 'ColorValue\("#([0-9a-fA-F]{6})"\)', {
    param($match)
    $hex = $match.Groups[1].Value
    $r = [Convert]::ToInt32($hex.Substring(0, 2), 16)
    $g = [Convert]::ToInt32($hex.Substring(2, 2), 16)
    $b = [Convert]::ToInt32($hex.Substring(4, 2), 16)
    "RGBA($r, $g, $b, 1)"
})
Set-Content -LiteralPath $srcPath -Value $screenFx -Encoding UTF8

Write-Host "Generated Phase 4B My Work canvas source at $OutputSourcePath"
