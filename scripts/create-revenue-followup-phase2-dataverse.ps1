param(
    [Parameter(Mandatory = $true)]
    [string]$EnvironmentUrl,

    [string]$SolutionUniqueName = "qfu_revenuefollowupworkbench",

    [string]$ResultPath = "results/phase2-live-build-result.json"
)

$ErrorActionPreference = "Stop"

Import-Module Az.Accounts -ErrorAction Stop

function New-Label {
    param([string]$Text)
    return @{
        LocalizedLabels = @(
            @{
                Label        = $Text
                LanguageCode = 1033
            }
        )
    }
}

function New-RequiredLevel {
    param([string]$Value = "None")
    return @{
        Value      = $Value
        CanBeChanged = $true
        ManagedPropertyLogicalName = "canmodifyrequirementlevelsettings"
    }
}

function Get-DataverseToken {
    $secureToken = (Get-AzAccessToken -ResourceUrl $EnvironmentUrl).Token
    if ($secureToken -is [securestring]) {
        return [System.Net.NetworkCredential]::new("", $secureToken).Password
    }
    return [string]$secureToken
}

$token = Get-DataverseToken
$baseHeaders = @{
    Authorization              = "Bearer $token"
    "OData-MaxVersion"         = "4.0"
    "OData-Version"            = "4.0"
    Accept                     = "application/json"
    "Content-Type"             = "application/json; charset=utf-8"
    "MSCRM.SolutionUniqueName" = $SolutionUniqueName
}

$result = [ordered]@{
    solution       = $SolutionUniqueName
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    choices        = @()
    tables         = @()
    columns        = @()
    lookups        = @()
    warnings       = @()
    errors         = @()
}

function Invoke-Dv {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        [object]$Body = $null
    )

    $uri = "$EnvironmentUrl/api/data/v9.2/$Path"
    if ($null -eq $Body) {
        return Invoke-RestMethod -Method $Method -Uri $uri -Headers $baseHeaders -ErrorAction Stop
    }

    $json = $Body | ConvertTo-Json -Depth 80
    return Invoke-RestMethod -Method $Method -Uri $uri -Headers $baseHeaders -Body $json -ErrorAction Stop
}

function Test-DvPath {
    param([string]$Path)
    try {
        Invoke-Dv -Method Get -Path $Path | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Add-Warning {
    param([string]$Message)
    $script:result.warnings += $Message
    Write-Warning $Message
}

function Add-ErrorRecord {
    param([string]$Message)
    $script:result.errors += $Message
    Write-Warning $Message
}

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$ScriptBlock
    )

    try {
        & $ScriptBlock
    }
    catch {
        $detail = $_.Exception.Message
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $detail = "$detail $($_.ErrorDetails.Message)"
        }
        elseif ($_.Exception.Response) {
            try {
                $reader = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
                $responseText = $reader.ReadToEnd()
                if ($responseText) {
                    $detail = "$detail $responseText"
                }
            }
            catch {
                # Best effort only. The outer failure message is still recorded.
            }
        }
        Add-ErrorRecord "$Name failed: $detail"
    }
}

function Ensure-Choice {
    param(
        [string]$Name,
        [string]$DisplayName,
        [string[]]$Values
    )

    if (Test-DvPath "GlobalOptionSetDefinitions(Name='$Name')") {
        $script:result.choices += [ordered]@{ name = $Name; status = "exists"; values = $Values }
        Write-Host "CHOICE_EXISTS=$Name"
        return
    }

    $options = @()
    $value = 985010000
    foreach ($label in $Values) {
        $options += @{
            Value = $value
            Label = New-Label $label
        }
        $value++
    }

    $body = @{
        "@odata.type" = "Microsoft.Dynamics.CRM.OptionSetMetadata"
        Name          = $Name
        DisplayName   = New-Label $DisplayName
        Description   = New-Label $DisplayName
        OptionSetType = "Picklist"
        Options       = $options
    }

    Invoke-Dv -Method Post -Path "GlobalOptionSetDefinitions" -Body $body | Out-Null
    $script:result.choices += [ordered]@{ name = $Name; status = "created"; values = $Values }
    Write-Host "CHOICE_CREATED=$Name"
}

function Ensure-Table {
    param(
        [string]$LogicalName,
        [string]$SchemaName,
        [string]$DisplayName,
        [string]$CollectionName,
        [string]$PrimaryNameSchema = "qfu_Name",
        [string]$PrimaryNameDisplay = "Name"
    )

    if (Test-DvPath "EntityDefinitions(LogicalName='$LogicalName')") {
        $script:result.tables += [ordered]@{ name = $LogicalName; status = "exists" }
        Write-Host "TABLE_EXISTS=$LogicalName"
        return
    }

    $body = @{
        "@odata.type"          = "Microsoft.Dynamics.CRM.EntityMetadata"
        SchemaName             = $SchemaName
        DisplayName            = New-Label $DisplayName
        DisplayCollectionName  = New-Label $CollectionName
        Description            = New-Label $DisplayName
        OwnershipType          = "UserOwned"
        IsActivity             = $false
        HasActivities          = $false
        HasNotes               = $false
        Attributes             = @(
            @{
                "@odata.type"       = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
                AttributeType       = "String"
                AttributeTypeName   = @{ Value = "StringType" }
                SchemaName          = $PrimaryNameSchema
                IsPrimaryName       = $true
                RequiredLevel       = New-RequiredLevel "ApplicationRequired"
                DisplayName         = New-Label $PrimaryNameDisplay
                Description         = New-Label $PrimaryNameDisplay
                MaxLength           = 200
                FormatName          = @{ Value = "Text" }
            }
        )
    }

    Invoke-Dv -Method Post -Path "EntityDefinitions" -Body $body | Out-Null
    $script:result.tables += [ordered]@{ name = $LogicalName; status = "created" }
    Write-Host "TABLE_CREATED=$LogicalName"
}

function Test-Attribute {
    param(
        [string]$Entity,
        [string]$Attribute
    )
    return Test-DvPath "EntityDefinitions(LogicalName='$Entity')/Attributes(LogicalName='$Attribute')"
}

function Add-ColumnResult {
    param(
        [string]$Entity,
        [string]$Attribute,
        [string]$Type,
        [string]$Status
    )
    $script:result.columns += [ordered]@{
        table  = $Entity
        column = $Attribute
        type   = $Type
        status = $Status
    }
    Write-Host "COLUMN_$($Status.ToUpper())=$Entity.$Attribute"
}

function Get-ChoiceMetadataId {
    param([string]$Name)
    $choice = Invoke-Dv -Method Get -Path "GlobalOptionSetDefinitions(Name='$Name')?`$select=Name,MetadataId"
    return [string]$choice.MetadataId
}

function Ensure-StringColumn {
    param(
        [string]$Entity,
        [string]$SchemaName,
        [string]$DisplayName,
        [int]$MaxLength = 200,
        [string]$Format = "Text",
        [string]$Required = "None"
    )
    $logical = $SchemaName.ToLower()
    if (Test-Attribute $Entity $logical) {
        Add-ColumnResult $Entity $logical "string" "exists"
        return
    }

    $body = @{
        "@odata.type"       = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
        AttributeType       = "String"
        AttributeTypeName   = @{ Value = "StringType" }
        SchemaName          = $SchemaName
        RequiredLevel       = New-RequiredLevel $Required
        DisplayName         = New-Label $DisplayName
        Description         = New-Label $DisplayName
        MaxLength           = $MaxLength
        FormatName          = @{ Value = $Format }
    }
    Invoke-Dv -Method Post -Path "EntityDefinitions(LogicalName='$Entity')/Attributes" -Body $body | Out-Null
    Add-ColumnResult $Entity $logical "string" "created"
}

function Ensure-MemoColumn {
    param(
        [string]$Entity,
        [string]$SchemaName,
        [string]$DisplayName,
        [int]$MaxLength = 4000
    )
    $logical = $SchemaName.ToLower()
    if (Test-Attribute $Entity $logical) {
        Add-ColumnResult $Entity $logical "memo" "exists"
        return
    }

    $body = @{
        "@odata.type"       = "Microsoft.Dynamics.CRM.MemoAttributeMetadata"
        AttributeType       = "Memo"
        AttributeTypeName   = @{ Value = "MemoType" }
        SchemaName          = $SchemaName
        RequiredLevel       = New-RequiredLevel "None"
        DisplayName         = New-Label $DisplayName
        Description         = New-Label $DisplayName
        MaxLength           = $MaxLength
        FormatName          = @{ Value = "TextArea" }
    }
    Invoke-Dv -Method Post -Path "EntityDefinitions(LogicalName='$Entity')/Attributes" -Body $body | Out-Null
    Add-ColumnResult $Entity $logical "memo" "created"
}

function Ensure-BooleanColumn {
    param(
        [string]$Entity,
        [string]$SchemaName,
        [string]$DisplayName,
        [bool]$DefaultValue = $false
    )
    $logical = $SchemaName.ToLower()
    if (Test-Attribute $Entity $logical) {
        Add-ColumnResult $Entity $logical "boolean" "exists"
        return
    }

    $body = @{
        "@odata.type"       = "Microsoft.Dynamics.CRM.BooleanAttributeMetadata"
        AttributeType       = "Boolean"
        AttributeTypeName   = @{ Value = "BooleanType" }
        SchemaName          = $SchemaName
        RequiredLevel       = New-RequiredLevel "None"
        DisplayName         = New-Label $DisplayName
        Description         = New-Label $DisplayName
        DefaultValue        = $DefaultValue
        OptionSet           = @{
            TrueOption = @{
                Value = 1
                Label = New-Label "Yes"
            }
            FalseOption = @{
                Value = 0
                Label = New-Label "No"
            }
            OptionSetType = "Boolean"
        }
    }
    Invoke-Dv -Method Post -Path "EntityDefinitions(LogicalName='$Entity')/Attributes" -Body $body | Out-Null
    Add-ColumnResult $Entity $logical "boolean" "created"
}

function Ensure-IntegerColumn {
    param(
        [string]$Entity,
        [string]$SchemaName,
        [string]$DisplayName,
        [int]$MinValue = 0,
        [int]$MaxValue = 2147483647
    )
    $logical = $SchemaName.ToLower()
    if (Test-Attribute $Entity $logical) {
        Add-ColumnResult $Entity $logical "integer" "exists"
        return
    }

    $body = @{
        "@odata.type"       = "Microsoft.Dynamics.CRM.IntegerAttributeMetadata"
        AttributeType       = "Integer"
        AttributeTypeName   = @{ Value = "IntegerType" }
        SchemaName          = $SchemaName
        RequiredLevel       = New-RequiredLevel "None"
        DisplayName         = New-Label $DisplayName
        Description         = New-Label $DisplayName
        MinValue            = $MinValue
        MaxValue            = $MaxValue
        Format              = "None"
    }
    Invoke-Dv -Method Post -Path "EntityDefinitions(LogicalName='$Entity')/Attributes" -Body $body | Out-Null
    Add-ColumnResult $Entity $logical "integer" "created"
}

function Ensure-DecimalColumn {
    param(
        [string]$Entity,
        [string]$SchemaName,
        [string]$DisplayName
    )
    $logical = $SchemaName.ToLower()
    if (Test-Attribute $Entity $logical) {
        Add-ColumnResult $Entity $logical "decimal" "exists"
        return
    }

    $body = @{
        "@odata.type"       = "Microsoft.Dynamics.CRM.DecimalAttributeMetadata"
        AttributeType       = "Decimal"
        AttributeTypeName   = @{ Value = "DecimalType" }
        SchemaName          = $SchemaName
        RequiredLevel       = New-RequiredLevel "None"
        DisplayName         = New-Label $DisplayName
        Description         = New-Label $DisplayName
        MinValue            = 0
        MaxValue            = 100000000000
        Precision           = 2
    }
    Invoke-Dv -Method Post -Path "EntityDefinitions(LogicalName='$Entity')/Attributes" -Body $body | Out-Null
    Add-ColumnResult $Entity $logical "decimal" "created"
}

function Ensure-DateTimeColumn {
    param(
        [string]$Entity,
        [string]$SchemaName,
        [string]$DisplayName
    )
    $logical = $SchemaName.ToLower()
    if (Test-Attribute $Entity $logical) {
        Add-ColumnResult $Entity $logical "datetime" "exists"
        return
    }

    $body = @{
        "@odata.type"       = "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata"
        AttributeType       = "DateTime"
        AttributeTypeName   = @{ Value = "DateTimeType" }
        SchemaName          = $SchemaName
        RequiredLevel       = New-RequiredLevel "None"
        DisplayName         = New-Label $DisplayName
        Description         = New-Label $DisplayName
        Format              = "DateAndTime"
        DateTimeBehavior    = @{ Value = "UserLocal" }
    }
    Invoke-Dv -Method Post -Path "EntityDefinitions(LogicalName='$Entity')/Attributes" -Body $body | Out-Null
    Add-ColumnResult $Entity $logical "datetime" "created"
}

function Ensure-PicklistColumn {
    param(
        [string]$Entity,
        [string]$SchemaName,
        [string]$DisplayName,
        [string]$OptionSetName
    )
    $logical = $SchemaName.ToLower()
    if (Test-Attribute $Entity $logical) {
        Add-ColumnResult $Entity $logical "picklist:$OptionSetName" "exists"
        return
    }

    $optionSetMetadataId = Get-ChoiceMetadataId $OptionSetName
    if (-not $optionSetMetadataId) {
        throw "Global choice $OptionSetName was not found."
    }

    $body = @{
        "@odata.type"       = "Microsoft.Dynamics.CRM.PicklistAttributeMetadata"
        AttributeType       = "Picklist"
        AttributeTypeName   = @{ Value = "PicklistType" }
        SchemaName          = $SchemaName
        RequiredLevel       = New-RequiredLevel "None"
        DisplayName         = New-Label $DisplayName
        Description         = New-Label $DisplayName
        "GlobalOptionSet@odata.bind" = "/GlobalOptionSetDefinitions($optionSetMetadataId)"
    }
    Invoke-Dv -Method Post -Path "EntityDefinitions(LogicalName='$Entity')/Attributes" -Body $body | Out-Null
    Add-ColumnResult $Entity $logical "picklist:$OptionSetName" "created"
}

function Ensure-LookupColumn {
    param(
        [string]$ReferencingEntity,
        [string]$LookupSchemaName,
        [string]$LookupDisplayName,
        [string]$ReferencedEntity,
        [string]$ReferencedAttribute,
        [string]$RelationshipSchemaName
    )

    $logical = $LookupSchemaName.ToLower()
    if (Test-Attribute $ReferencingEntity $logical) {
        $script:result.lookups += [ordered]@{
            table        = $ReferencingEntity
            column       = $logical
            referenced   = $ReferencedEntity
            relationship = $RelationshipSchemaName
            status       = "exists"
        }
        Write-Host "LOOKUP_EXISTS=$ReferencingEntity.$logical"
        return
    }

    if (-not (Test-DvPath "EntityDefinitions(LogicalName='$ReferencedEntity')")) {
        Add-Warning "Referenced table $ReferencedEntity does not exist; skipped lookup $ReferencingEntity.$logical."
        return
    }

    $body = @{
        "@odata.type"                = "Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata"
        SchemaName                   = $RelationshipSchemaName
        ReferencedEntity             = $ReferencedEntity
        ReferencedAttribute          = $ReferencedAttribute
        ReferencingEntity            = $ReferencingEntity
        AssociatedMenuConfiguration  = @{
            Behavior = "UseCollectionName"
            Group    = "Details"
            Label    = New-Label $LookupDisplayName
            Order    = 10000
        }
        CascadeConfiguration         = @{
            Assign   = "NoCascade"
            Delete   = "RemoveLink"
            Merge    = "NoCascade"
            Reparent = "NoCascade"
            Share    = "NoCascade"
            Unshare  = "NoCascade"
        }
        Lookup                       = @{
            "@odata.type"       = "Microsoft.Dynamics.CRM.LookupAttributeMetadata"
            AttributeType       = "Lookup"
            AttributeTypeName   = @{ Value = "LookupType" }
            SchemaName          = $LookupSchemaName
            RequiredLevel       = New-RequiredLevel "None"
            DisplayName         = New-Label $LookupDisplayName
            Description         = New-Label $LookupDisplayName
        }
    }

    Invoke-Dv -Method Post -Path "RelationshipDefinitions" -Body $body | Out-Null
    $script:result.lookups += [ordered]@{
        table        = $ReferencingEntity
        column       = $logical
        referenced   = $ReferencedEntity
        relationship = $RelationshipSchemaName
        status       = "created"
    }
    Write-Host "LOOKUP_CREATED=$ReferencingEntity.$logical"
}

$choices = @(
    @{ Name = "qfu_role"; Display = "QFU Role"; Values = @("TSR", "CSSR", "Manager", "GM", "Admin") },
    @{ Name = "qfu_worktype"; Display = "QFU Work Type"; Values = @("Quote", "Backorder", "Freight", "Pickup", "General") },
    @{ Name = "qfu_sourcesystem"; Display = "QFU Source System"; Values = @("SP830CA", "ZBO", "Freight", "Pickup", "Manual", "Other") },
    @{ Name = "qfu_aliastype"; Display = "QFU Alias Type"; Values = @("AM Number", "AM Name", "CSSR Number", "CSSR Name", "Created By", "Email", "Other") },
    @{ Name = "qfu_rolehint"; Display = "QFU Role Hint"; Values = @("TSR", "CSSR", "Manager", "GM", "Admin", "Unknown") },
    @{ Name = "qfu_thresholdoperator"; Display = "QFU Threshold Operator"; Values = @("GreaterThan", "GreaterThanOrEqual") },
    @{ Name = "qfu_workitemgenerationmode"; Display = "QFU Work Item Generation Mode"; Values = @("HighValueOnly", "AllQuotes", "ReportingOnly") },
    @{ Name = "qfu_firstfollowupbasis"; Display = "QFU First Follow-Up Basis"; Values = @("ImportDate", "QuoteDate", "SourceDueDate", "Manual", "Disabled") },
    @{ Name = "qfu_alertmode"; Display = "QFU Alert Mode"; Values = @("Disabled", "NewHighValue", "DueToday", "Overdue", "EscalatedOrRoadblock", "DailyDigestOnly") },
    @{ Name = "qfu_cssralertmode"; Display = "QFU CSSR Alert Mode"; Values = @("VisibilityOnly", "DailyDigestOnly", "TargetedAlerts", "CCOnly", "Disabled") },
    @{ Name = "qfu_workitemstatus"; Display = "QFU Work Item Status"; Values = @("Open", "Due Today", "Overdue", "Waiting on Customer", "Waiting on Vendor", "Roadblock", "Escalated", "Completed", "Closed Won", "Closed Lost", "Cancelled") },
    @{ Name = "qfu_priority"; Display = "QFU Priority"; Values = @("Low", "Normal", "High", "Critical") },
    @{ Name = "qfu_escalationlevel"; Display = "QFU Escalation Level"; Values = @("None", "Manager", "GM", "Admin") },
    @{ Name = "qfu_assignmentstatus"; Display = "QFU Assignment Status"; Values = @("Assigned", "Partially Assigned", "Needs TSR Assignment", "Needs CSSR Assignment", "Unmapped", "Error") },
    @{ Name = "qfu_actiontype"; Display = "QFU Action Type"; Values = @("Call", "Email", "Customer Advised", "Vendor Contacted", "Due Date Updated", "Follow-Up Scheduled", "Roadblock", "Escalated", "Won", "Lost", "Cancelled", "Note", "Assignment/Reassignment", "Sticky Note Updated") },
    @{ Name = "qfu_alerttype"; Display = "QFU Alert Type"; Values = @("New Assignment", "Due Today", "Overdue", "Escalation", "Daily Digest", "Assignment Exception", "Flow Failure") },
    @{ Name = "qfu_alertstatus"; Display = "QFU Alert Status"; Values = @("Pending", "Sent", "Failed", "Suppressed", "Skipped") },
    @{ Name = "qfu_exceptiontype"; Display = "QFU Exception Type"; Values = @("Missing TSR Alias", "Missing CSSR Alias", "Blank Alias", "Zero Alias", "Ambiguous Alias", "Missing Branch", "Missing Policy", "Other") },
    @{ Name = "qfu_exceptionstatus"; Display = "QFU Exception Status"; Values = @("Open", "In Review", "Resolved", "Ignored") }
)

foreach ($choice in $choices) {
    Invoke-Step "Choice $($choice.Name)" {
        Ensure-Choice -Name $choice.Name -DisplayName $choice.Display -Values $choice.Values
    }
}

$tables = @(
    @{ Logical = "qfu_staff"; Schema = "qfu_Staff"; Display = "Staff"; Collection = "Staff"; PrimarySchema = "qfu_Name"; PrimaryDisplay = "Staff Name" },
    @{ Logical = "qfu_staffalias"; Schema = "qfu_StaffAlias"; Display = "Staff Alias"; Collection = "Staff Aliases"; PrimarySchema = "qfu_Name"; PrimaryDisplay = "Alias Name" },
    @{ Logical = "qfu_branchmembership"; Schema = "qfu_BranchMembership"; Display = "Branch Membership"; Collection = "Branch Memberships"; PrimarySchema = "qfu_Name"; PrimaryDisplay = "Membership Name" },
    @{ Logical = "qfu_policy"; Schema = "qfu_Policy"; Display = "Branch Policy"; Collection = "Branch Policies"; PrimarySchema = "qfu_Name"; PrimaryDisplay = "Policy Name" },
    @{ Logical = "qfu_workitem"; Schema = "qfu_WorkItem"; Display = "Work Item"; Collection = "Work Items"; PrimarySchema = "qfu_WorkItemNumber"; PrimaryDisplay = "Work Item Number" },
    @{ Logical = "qfu_workitemaction"; Schema = "qfu_WorkItemAction"; Display = "Work Item Action"; Collection = "Work Item Actions"; PrimarySchema = "qfu_Name"; PrimaryDisplay = "Action Name" },
    @{ Logical = "qfu_alertlog"; Schema = "qfu_AlertLog"; Display = "Alert Log"; Collection = "Alert Logs"; PrimarySchema = "qfu_Name"; PrimaryDisplay = "Alert Name" },
    @{ Logical = "qfu_assignmentexception"; Schema = "qfu_AssignmentException"; Display = "Assignment Exception"; Collection = "Assignment Exceptions"; PrimarySchema = "qfu_Name"; PrimaryDisplay = "Exception Name" }
)

foreach ($table in $tables) {
    Invoke-Step "Table $($table.Logical)" {
        Ensure-Table -LogicalName $table.Logical -SchemaName $table.Schema -DisplayName $table.Display -CollectionName $table.Collection -PrimaryNameSchema $table.PrimarySchema -PrimaryNameDisplay $table.PrimaryDisplay
    }
}

Invoke-Step "qfu_staff columns" {
    Ensure-StringColumn "qfu_staff" "qfu_PrimaryEmail" "Primary Email" 320 "Email"
    Ensure-StringColumn "qfu_staff" "qfu_StaffNumber" "Staff Number" 100
    Ensure-StringColumn "qfu_staff" "qfu_EntraObjectId" "Entra Object ID" 100
    Ensure-BooleanColumn "qfu_staff" "qfu_Active" "Active" $true
    Ensure-MemoColumn "qfu_staff" "qfu_Notes" "Notes"
    Ensure-LookupColumn "qfu_staff" "qfu_SystemUser" "Dataverse User" "systemuser" "systemuserid" "qfu_systemuser_qfu_staff"
    Ensure-LookupColumn "qfu_staff" "qfu_DefaultBranch" "Default Branch" "qfu_branch" "qfu_branchid" "qfu_branch_qfu_staff_defaultbranch"
}

Invoke-Step "qfu_staffalias columns" {
    Ensure-PicklistColumn "qfu_staffalias" "qfu_SourceSystem" "Source System" "qfu_sourcesystem"
    Ensure-PicklistColumn "qfu_staffalias" "qfu_AliasType" "Alias Type" "qfu_aliastype"
    Ensure-StringColumn "qfu_staffalias" "qfu_RawAlias" "Raw Alias" 200
    Ensure-StringColumn "qfu_staffalias" "qfu_NormalizedAlias" "Normalized Alias" 200
    Ensure-PicklistColumn "qfu_staffalias" "qfu_RoleHint" "Role Hint" "qfu_rolehint"
    Ensure-LookupColumn "qfu_staffalias" "qfu_Branch" "Branch" "qfu_branch" "qfu_branchid" "qfu_branch_qfu_staffalias"
    Ensure-StringColumn "qfu_staffalias" "qfu_ScopeKey" "Scope Key" 100
    Ensure-LookupColumn "qfu_staffalias" "qfu_Staff" "Staff" "qfu_staff" "qfu_staffid" "qfu_staff_qfu_staffalias"
    Ensure-BooleanColumn "qfu_staffalias" "qfu_Active" "Active" $true
    Ensure-LookupColumn "qfu_staffalias" "qfu_VerifiedBy" "Verified By" "systemuser" "systemuserid" "qfu_systemuser_qfu_staffalias_verifiedby"
    Ensure-DateTimeColumn "qfu_staffalias" "qfu_VerifiedOn" "Verified On"
    Ensure-MemoColumn "qfu_staffalias" "qfu_Notes" "Notes"
}

Invoke-Step "qfu_branchmembership columns" {
    Ensure-LookupColumn "qfu_branchmembership" "qfu_Branch" "Branch" "qfu_branch" "qfu_branchid" "qfu_branch_qfu_branchmembership"
    Ensure-LookupColumn "qfu_branchmembership" "qfu_Staff" "Staff" "qfu_staff" "qfu_staffid" "qfu_staff_qfu_branchmembership"
    Ensure-PicklistColumn "qfu_branchmembership" "qfu_Role" "Role" "qfu_role"
    Ensure-BooleanColumn "qfu_branchmembership" "qfu_Active" "Active" $true
    Ensure-DateTimeColumn "qfu_branchmembership" "qfu_StartDate" "Start Date"
    Ensure-DateTimeColumn "qfu_branchmembership" "qfu_EndDate" "End Date"
    Ensure-BooleanColumn "qfu_branchmembership" "qfu_IsPrimary" "Primary" $false
    Ensure-MemoColumn "qfu_branchmembership" "qfu_Notes" "Notes"
}

Invoke-Step "qfu_policy columns" {
    Ensure-LookupColumn "qfu_policy" "qfu_Branch" "Branch" "qfu_branch" "qfu_branchid" "qfu_branch_qfu_policy"
    Ensure-StringColumn "qfu_policy" "qfu_ScopeKey" "Scope Key" 100
    Ensure-PicklistColumn "qfu_policy" "qfu_WorkType" "Work Type" "qfu_worktype"
    Ensure-DecimalColumn "qfu_policy" "qfu_HighValueThreshold" "High Value Threshold"
    Ensure-PicklistColumn "qfu_policy" "qfu_ThresholdOperator" "Threshold Operator" "qfu_thresholdoperator"
    Ensure-PicklistColumn "qfu_policy" "qfu_WorkItemGenerationMode" "Work Item Generation Mode" "qfu_workitemgenerationmode"
    Ensure-IntegerColumn "qfu_policy" "qfu_RequiredAttempts" "Required Attempts"
    Ensure-PicklistColumn "qfu_policy" "qfu_FirstFollowUpBasis" "First Follow-Up Basis" "qfu_firstfollowupbasis"
    Ensure-IntegerColumn "qfu_policy" "qfu_FirstFollowUpBusinessDays" "First Follow-Up Business Days"
    Ensure-StringColumn "qfu_policy" "qfu_PrimaryOwnerStrategy" "Primary Owner Strategy" 200
    Ensure-StringColumn "qfu_policy" "qfu_SupportOwnerStrategy" "Support Owner Strategy" 200
    Ensure-PicklistColumn "qfu_policy" "qfu_GmCcMode" "GM CC Mode" "qfu_alertmode"
    Ensure-PicklistColumn "qfu_policy" "qfu_ManagerCcMode" "Manager CC Mode" "qfu_alertmode"
    Ensure-PicklistColumn "qfu_policy" "qfu_CssrAlertMode" "CSSR Alert Mode" "qfu_cssralertmode"
    Ensure-IntegerColumn "qfu_policy" "qfu_EscalateAfterBusinessDays" "Escalate After Business Days"
    Ensure-BooleanColumn "qfu_policy" "qfu_DigestEnabled" "Digest Enabled" $false
    Ensure-BooleanColumn "qfu_policy" "qfu_TargetedAlertEnabled" "Targeted Alert Enabled" $false
    Ensure-BooleanColumn "qfu_policy" "qfu_Active" "Active" $false
}

Invoke-Step "qfu_workitem columns" {
    Ensure-PicklistColumn "qfu_workitem" "qfu_WorkType" "Work Type" "qfu_worktype"
    Ensure-PicklistColumn "qfu_workitem" "qfu_SourceSystem" "Source System" "qfu_sourcesystem"
    Ensure-LookupColumn "qfu_workitem" "qfu_Branch" "Branch" "qfu_branch" "qfu_branchid" "qfu_branch_qfu_workitem"
    Ensure-StringColumn "qfu_workitem" "qfu_CustomerName" "Customer Name" 250
    Ensure-LookupColumn "qfu_workitem" "qfu_SourceQuote" "Source Quote" "qfu_quote" "qfu_quoteid" "qfu_quote_qfu_workitem"
    Ensure-LookupColumn "qfu_workitem" "qfu_SourceQuoteLine" "Source Quote Line" "qfu_quoteline" "qfu_quotelineid" "qfu_quoteline_qfu_workitem"
    Ensure-LookupColumn "qfu_workitem" "qfu_SourceBackorder" "Source Backorder" "qfu_backorder" "qfu_backorderid" "qfu_backorder_qfu_workitem"
    Ensure-LookupColumn "qfu_workitem" "qfu_SourceFreightWorkItem" "Source Freight Work Item" "qfu_freightworkitem" "qfu_freightworkitemid" "qfu_freightworkitem_qfu_workitem"
    Ensure-LookupColumn "qfu_workitem" "qfu_SourceDeliveryNotPgi" "Source Delivery Not PGI" "qfu_deliverynotpgi" "qfu_deliverynotpgiid" "qfu_deliverynotpgi_qfu_workitem"
    Ensure-StringColumn "qfu_workitem" "qfu_SourceDocumentNumber" "Source Document Number" 200
    Ensure-StringColumn "qfu_workitem" "qfu_SourceExternalKey" "Source External Key" 500
    Ensure-DecimalColumn "qfu_workitem" "qfu_TotalValue" "Total Value"
    Ensure-LookupColumn "qfu_workitem" "qfu_PrimaryOwnerStaff" "Primary Owner Staff" "qfu_staff" "qfu_staffid" "qfu_staff_qfu_workitem_primaryowner"
    Ensure-LookupColumn "qfu_workitem" "qfu_SupportOwnerStaff" "Support Owner Staff" "qfu_staff" "qfu_staffid" "qfu_staff_qfu_workitem_supportowner"
    Ensure-LookupColumn "qfu_workitem" "qfu_TsrStaff" "TSR Staff" "qfu_staff" "qfu_staffid" "qfu_staff_qfu_workitem_tsr"
    Ensure-LookupColumn "qfu_workitem" "qfu_CssrStaff" "CSSR Staff" "qfu_staff" "qfu_staffid" "qfu_staff_qfu_workitem_cssr"
    Ensure-IntegerColumn "qfu_workitem" "qfu_RequiredAttempts" "Required Attempts"
    Ensure-IntegerColumn "qfu_workitem" "qfu_CompletedAttempts" "Completed Attempts"
    Ensure-PicklistColumn "qfu_workitem" "qfu_Status" "Status" "qfu_workitemstatus"
    Ensure-PicklistColumn "qfu_workitem" "qfu_Priority" "Priority" "qfu_priority"
    Ensure-DateTimeColumn "qfu_workitem" "qfu_NextFollowUpOn" "Next Follow-Up On"
    Ensure-DateTimeColumn "qfu_workitem" "qfu_LastFollowedUpOn" "Last Followed Up On"
    Ensure-DateTimeColumn "qfu_workitem" "qfu_LastActionOn" "Last Action On"
    Ensure-DateTimeColumn "qfu_workitem" "qfu_OverdueSince" "Overdue Since"
    Ensure-MemoColumn "qfu_workitem" "qfu_StickyNote" "Sticky Note" 10000
    Ensure-DateTimeColumn "qfu_workitem" "qfu_StickyNoteUpdatedOn" "Sticky Note Updated On"
    Ensure-LookupColumn "qfu_workitem" "qfu_StickyNoteUpdatedBy" "Sticky Note Updated By" "qfu_staff" "qfu_staffid" "qfu_staff_qfu_workitem_stickynoteupdatedby"
    Ensure-PicklistColumn "qfu_workitem" "qfu_EscalationLevel" "Escalation Level" "qfu_escalationlevel"
    Ensure-LookupColumn "qfu_workitem" "qfu_Policy" "Policy" "qfu_policy" "qfu_policyid" "qfu_policy_qfu_workitem"
    Ensure-PicklistColumn "qfu_workitem" "qfu_AssignmentStatus" "Assignment Status" "qfu_assignmentstatus"
    Ensure-MemoColumn "qfu_workitem" "qfu_Notes" "Notes"
}

Invoke-Step "qfu_workitemaction columns" {
    Ensure-LookupColumn "qfu_workitemaction" "qfu_WorkItem" "Work Item" "qfu_workitem" "qfu_workitemid" "qfu_workitem_qfu_workitemaction"
    Ensure-PicklistColumn "qfu_workitemaction" "qfu_ActionType" "Action Type" "qfu_actiontype"
    Ensure-BooleanColumn "qfu_workitemaction" "qfu_CountsAsAttempt" "Counts As Attempt" $false
    Ensure-LookupColumn "qfu_workitemaction" "qfu_ActionBy" "Action By" "qfu_staff" "qfu_staffid" "qfu_staff_qfu_workitemaction_actionby"
    Ensure-DateTimeColumn "qfu_workitemaction" "qfu_ActionOn" "Action On"
    Ensure-IntegerColumn "qfu_workitemaction" "qfu_AttemptNumber" "Attempt Number"
    Ensure-StringColumn "qfu_workitemaction" "qfu_Outcome" "Outcome" 500
    Ensure-DateTimeColumn "qfu_workitemaction" "qfu_NextFollowUpOn" "Next Follow-Up On"
    Ensure-MemoColumn "qfu_workitemaction" "qfu_Notes" "Notes"
}

Invoke-Step "qfu_alertlog columns" {
    Ensure-LookupColumn "qfu_alertlog" "qfu_WorkItem" "Work Item" "qfu_workitem" "qfu_workitemid" "qfu_workitem_qfu_alertlog"
    Ensure-PicklistColumn "qfu_alertlog" "qfu_AlertType" "Alert Type" "qfu_alerttype"
    Ensure-LookupColumn "qfu_alertlog" "qfu_RecipientStaff" "Recipient Staff" "qfu_staff" "qfu_staffid" "qfu_staff_qfu_alertlog_recipient"
    Ensure-StringColumn "qfu_alertlog" "qfu_RecipientEmail" "Recipient Email" 320 "Email"
    Ensure-MemoColumn "qfu_alertlog" "qfu_CcEmails" "CC Emails"
    Ensure-StringColumn "qfu_alertlog" "qfu_DedupeKey" "Dedupe Key" 500
    Ensure-PicklistColumn "qfu_alertlog" "qfu_Status" "Status" "qfu_alertstatus"
    Ensure-DateTimeColumn "qfu_alertlog" "qfu_SentOn" "Sent On"
    Ensure-MemoColumn "qfu_alertlog" "qfu_FailureMessage" "Failure Message"
    Ensure-StringColumn "qfu_alertlog" "qfu_FlowRunId" "Flow Run ID" 500
    Ensure-MemoColumn "qfu_alertlog" "qfu_Notes" "Notes"
}

Invoke-Step "qfu_workitemaction related alert lookup" {
    Ensure-LookupColumn "qfu_workitemaction" "qfu_RelatedAlert" "Related Alert" "qfu_alertlog" "qfu_alertlogid" "qfu_alertlog_qfu_workitemaction_relatedalert"
}

Invoke-Step "qfu_assignmentexception columns" {
    Ensure-PicklistColumn "qfu_assignmentexception" "qfu_ExceptionType" "Exception Type" "qfu_exceptiontype"
    Ensure-LookupColumn "qfu_assignmentexception" "qfu_Branch" "Branch" "qfu_branch" "qfu_branchid" "qfu_branch_qfu_assignmentexception"
    Ensure-PicklistColumn "qfu_assignmentexception" "qfu_SourceSystem" "Source System" "qfu_sourcesystem"
    Ensure-StringColumn "qfu_assignmentexception" "qfu_SourceField" "Source Field" 200
    Ensure-StringColumn "qfu_assignmentexception" "qfu_RawValue" "Raw Value" 200
    Ensure-StringColumn "qfu_assignmentexception" "qfu_NormalizedValue" "Normalized Value" 200
    Ensure-StringColumn "qfu_assignmentexception" "qfu_DisplayName" "Display Name" 250
    Ensure-StringColumn "qfu_assignmentexception" "qfu_SourceDocumentNumber" "Source Document Number" 200
    Ensure-StringColumn "qfu_assignmentexception" "qfu_SourceExternalKey" "Source External Key" 500
    Ensure-StringColumn "qfu_assignmentexception" "qfu_ExceptionKey" "Exception Key" 500
    Ensure-LookupColumn "qfu_assignmentexception" "qfu_SourceQuote" "Source Quote" "qfu_quote" "qfu_quoteid" "qfu_quote_qfu_assignmentexception"
    Ensure-LookupColumn "qfu_assignmentexception" "qfu_SourceQuoteLine" "Source Quote Line" "qfu_quoteline" "qfu_quotelineid" "qfu_quoteline_qfu_assignmentexception"
    Ensure-LookupColumn "qfu_assignmentexception" "qfu_SourceBackorder" "Source Backorder" "qfu_backorder" "qfu_backorderid" "qfu_backorder_qfu_assignmentexception"
    Ensure-LookupColumn "qfu_assignmentexception" "qfu_WorkItem" "Work Item" "qfu_workitem" "qfu_workitemid" "qfu_workitem_qfu_assignmentexception"
    Ensure-PicklistColumn "qfu_assignmentexception" "qfu_Status" "Status" "qfu_exceptionstatus"
    Ensure-LookupColumn "qfu_assignmentexception" "qfu_ResolvedStaff" "Resolved Staff" "qfu_staff" "qfu_staffid" "qfu_staff_qfu_assignmentexception_resolvedstaff"
    Ensure-LookupColumn "qfu_assignmentexception" "qfu_ResolvedBy" "Resolved By" "systemuser" "systemuserid" "qfu_systemuser_qfu_assignmentexception_resolvedby"
    Ensure-DateTimeColumn "qfu_assignmentexception" "qfu_ResolvedOn" "Resolved On"
    Ensure-MemoColumn "qfu_assignmentexception" "qfu_Notes" "Notes"
}

$resultDir = Split-Path -Parent $ResultPath
if ($resultDir -and -not (Test-Path $resultDir)) {
    New-Item -ItemType Directory -Path $resultDir -Force | Out-Null
}

$result | ConvertTo-Json -Depth 80 | Set-Content -Path $ResultPath -Encoding UTF8
Write-Host "RESULT_PATH=$ResultPath"
