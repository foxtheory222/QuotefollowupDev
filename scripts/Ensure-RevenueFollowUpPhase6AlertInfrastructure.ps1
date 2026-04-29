param(
    [string]$EnvironmentUrl = 'https://orga632edd5.crm3.dynamics.com',
    [string]$SolutionUniqueName = 'qfu_revenuefollowupworkbench',
    [string]$OutputPath = 'results\phase6\phase6-alert-infrastructure.json'
)

$ErrorActionPreference = 'Stop'

$alertModeValues = [ordered]@{
    Disabled          = 985060000
    DryRunOnly        = 985060001
    TestRecipientOnly = 985060002
    Live              = 985060003
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

function Invoke-DvPatch {
    param([string]$RelativeUrl, [object]$Body)
    Invoke-RestMethod -Method Patch -Uri "$EnvironmentUrl/api/data/v9.2/$RelativeUrl" -Headers $headers -Body ($Body | ConvertTo-Json -Depth 100)
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

function Get-AttributeMetadata {
    param([string]$Table, [string]$LogicalName)
    try {
        Invoke-DvGet "EntityDefinitions(LogicalName='$Table')/Attributes(LogicalName='$LogicalName')?`$select=LogicalName,SchemaName,MetadataId,AttributeType"
    }
    catch {
        if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) {
            return $null
        }
        throw
    }
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
    catch {
        return $false
    }
}

function Ensure-PolicyAlertModeField {
    $logicalName = 'qfu_alertmode'
    $existing = Get-AttributeMetadata -Table 'qfu_policy' -LogicalName $logicalName
    if ($existing) {
        return [ordered]@{
            logicalName = $logicalName
            status = 'found'
            metadataId = $existing.MetadataId
            addedToSolution = if ($existing.MetadataId) { Add-ComponentToSolution -ComponentType 2 -ComponentId ([guid]$existing.MetadataId) } else { $false }
        }
    }

    Invoke-DvPost "EntityDefinitions(LogicalName='qfu_policy')/Attributes" @{
        '@odata.type' = 'Microsoft.Dynamics.CRM.PicklistAttributeMetadata'
        SchemaName = 'qfu_AlertMode'
        DisplayName = New-Label 'Alert Mode'
        Description = New-Label 'Controls QFU alert and digest execution mode. Default for Phase 6 is DryRunOnly.'
        RequiredLevel = @{
            Value = 'None'
            CanBeChanged = $true
            ManagedPropertyLogicalName = 'canmodifyrequirementlevelsettings'
        }
        OptionSet = @{
            '@odata.type' = 'Microsoft.Dynamics.CRM.OptionSetMetadata'
            IsGlobal = $false
            OptionSetType = 'Picklist'
            Options = @(
                @{ Value = $alertModeValues.Disabled; Label = New-Label 'Disabled' }
                @{ Value = $alertModeValues.DryRunOnly; Label = New-Label 'DryRunOnly' }
                @{ Value = $alertModeValues.TestRecipientOnly; Label = New-Label 'TestRecipientOnly' }
                @{ Value = $alertModeValues.Live; Label = New-Label 'Live' }
            )
        }
    } | Out-Null
    Start-Sleep -Seconds 8
    $created = Get-AttributeMetadata -Table 'qfu_policy' -LogicalName $logicalName
    Invoke-DvPost 'PublishXml' @{
        ParameterXml = '<importexportxml><entities><entity>qfu_policy</entity></entities><nodes/><securityroles/><settings/><workflows/></importexportxml>'
    } | Out-Null
    Start-Sleep -Seconds 8

    [ordered]@{
        logicalName = $logicalName
        status = 'created'
        metadataId = if ($created) { $created.MetadataId } else { $null }
        addedToSolution = if ($created -and $created.MetadataId) { Add-ComponentToSolution -ComponentType 2 -ComponentId ([guid]$created.MetadataId) } else { $false }
    }
}

function Ensure-DefaultPolicy {
    $existing = Get-AllRows "qfu_policies?`$select=qfu_policyid,qfu_name,qfu_policykey,qfu_scopekey,qfu_worktype,qfu_highvaluethreshold,qfu_requiredattempts,qfu_digestenabled,qfu_targetedalertenabled,qfu_escalateafterbusinessdays,qfu_alertmode,qfu_active&`$filter=qfu_policykey eq 'GLOBAL|Quote|Active'&`$top=1" | Select-Object -First 1
    $body = @{
        qfu_name = 'Default Quote Follow-Up Policy'
        qfu_policykey = 'GLOBAL|Quote|Active'
        qfu_scopekey = 'GLOBAL'
        qfu_worktype = 985010000
        qfu_highvaluethreshold = 3000
        qfu_requiredattempts = 3
        qfu_digestenabled = $true
        qfu_targetedalertenabled = $true
        qfu_escalateafterbusinessdays = 1
        qfu_alertmode = $alertModeValues.DryRunOnly
        qfu_active = $true
    }

    if ($existing) {
        Invoke-DvPatchNoContent "qfu_policies($($existing.qfu_policyid))" $body
        $after = Invoke-DvGet "qfu_policies($($existing.qfu_policyid))?`$select=qfu_policyid,qfu_name,qfu_policykey,qfu_scopekey,qfu_worktype,qfu_highvaluethreshold,qfu_requiredattempts,qfu_digestenabled,qfu_targetedalertenabled,qfu_escalateafterbusinessdays,qfu_alertmode,qfu_active"
        return [ordered]@{
            policyId = $existing.qfu_policyid
            status = 'updated'
            policy = $after
        }
    }

    $response = Invoke-WebRequest -UseBasicParsing -Method Post -Uri "$EnvironmentUrl/api/data/v9.2/qfu_policies" -Headers $headers -Body ($body | ConvertTo-Json -Depth 20)
    $policyId = $null
    if ($response.Headers['OData-EntityId'] -match '\(([^)]+)\)') {
        $policyId = $Matches[1]
    }
    $after = if ($policyId) { Invoke-DvGet "qfu_policies($policyId)?`$select=qfu_policyid,qfu_name,qfu_policykey,qfu_scopekey,qfu_worktype,qfu_highvaluethreshold,qfu_requiredattempts,qfu_digestenabled,qfu_targetedalertenabled,qfu_escalateafterbusinessdays,qfu_alertmode,qfu_active" } else { $null }
    [ordered]@{
        policyId = $policyId
        status = 'created'
        policy = $after
    }
}

function Get-KeyBySchemaName {
    param([string]$Table, [string]$KeyName)
    $keys = Invoke-DvGet "EntityDefinitions(LogicalName='$Table')/Keys?`$select=SchemaName,KeyAttributes,EntityKeyIndexStatus"
    foreach ($key in @($keys.value)) {
        if ($key.SchemaName -eq $KeyName) { return $key }
    }
    return $null
}

function Ensure-AlertLogDedupeKey {
    $existing = Get-KeyBySchemaName -Table 'qfu_alertlog' -KeyName 'qfu_key_alertlog_dedupekey'
    if ($existing) {
        return [ordered]@{
            status = 'found'
            schemaName = $existing.SchemaName
            keyAttributes = @($existing.KeyAttributes)
            entityKeyIndexStatus = $existing.EntityKeyIndexStatus
        }
    }

    Invoke-DvPost "EntityDefinitions(LogicalName='qfu_alertlog')/Keys" @{
        '@odata.type' = 'Microsoft.Dynamics.CRM.EntityKeyMetadata'
        SchemaName = 'qfu_key_alertlog_dedupekey'
        DisplayName = New-Label 'QFU Alert Log Dedupe Key'
        KeyAttributes = @('qfu_dedupekey')
    } | Out-Null
    Start-Sleep -Seconds 5
    $created = Get-KeyBySchemaName -Table 'qfu_alertlog' -KeyName 'qfu_key_alertlog_dedupekey'
    [ordered]@{
        status = if ($created) { 'created' } else { 'create-requested' }
        schemaName = 'qfu_key_alertlog_dedupekey'
        keyAttributes = @('qfu_dedupekey')
        entityKeyIndexStatus = if ($created) { $created.EntityKeyIndexStatus } else { 'unknown' }
    }
}

function New-Phase6FlowClientData {
    param([string]$FlowPurpose)

    @{
        properties = @{
            connectionReferences = @{}
            definition = @{
                '$schema' = 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
                contentVersion = '1.0.0.0'
                parameters = @{
                    '$authentication' = @{
                        defaultValue = @{}
                        type = 'SecureObject'
                    }
                }
                triggers = @{
                    manual = @{
                        type = 'Request'
                        kind = 'Button'
                        inputs = @{
                            schema = @{
                                type = 'object'
                                properties = @{
                                    alertMode = @{ type = 'string' }
                                    branchScope = @{ type = 'string' }
                                    maxRecords = @{ type = 'integer' }
                                    requestSource = @{ type = 'string' }
                                }
                            }
                        }
                    }
                }
                actions = @{
                    Compose_Phase_6_Safe_Mode = @{
                        runAfter = @{}
                        type = 'Compose'
                        inputs = @{
                            purpose = $FlowPurpose
                            defaultMode = 'DryRunOnly'
                            sendsEmail = $false
                            sendsTeams = $false
                            note = 'Phase 6 solution-aware no-send flow shell. Operational dry-run candidate creation and dedupe validation are performed by the checked-in Phase 6 validation harness until live alert enablement is approved.'
                        }
                    }
                }
                outputs = @{}
            }
        }
        schemaVersion = '1.0.0.0'
    }
}

function Ensure-Flow {
    param([string]$FlowName, [string]$Purpose)

    $escapedName = Escape-ODataString $FlowName
    $existing = Get-AllRows "workflows?`$select=workflowid,name,statecode,statuscode,category,type,primaryentity&`$filter=category eq 5 and name eq '$escapedName'&`$top=1" | Select-Object -First 1
    $clientDataJson = (New-Phase6FlowClientData -FlowPurpose $Purpose) | ConvertTo-Json -Depth 100 -Compress
    $workflowId = $null
    $mode = 'created'
    $activationResult = 'not-attempted'
    $activationFailure = $null

    if ($existing) {
        $workflowId = $existing.workflowid
        $mode = 'updated'
        if ([int]$existing.statecode -eq 1) {
            Invoke-DvPatchNoContent "workflows($workflowId)" @{ statecode = 0; statuscode = 1 }
            Start-Sleep -Seconds 4
        }
        Invoke-DvPatchNoContent "workflows($workflowId)" @{
            name = $FlowName
            description = "$Purpose Phase 6 no-send safe-mode flow shell. Default alert mode is DryRunOnly."
            clientdata = $clientDataJson
            category = 5
            type = 1
            primaryentity = 'none'
        }
    }
    else {
        $response = Invoke-WebRequest -UseBasicParsing -Method Post -Uri "$EnvironmentUrl/api/data/v9.2/workflows" -Headers $headers -Body (@{
            category = 5
            name = $FlowName
            type = 1
            description = "$Purpose Phase 6 no-send safe-mode flow shell. Default alert mode is DryRunOnly."
            primaryentity = 'none'
            clientdata = $clientDataJson
        } | ConvertTo-Json -Depth 100)
        if ($response.Headers['OData-EntityId'] -match '\(([^)]+)\)') {
            $workflowId = $Matches[1]
        }
        if (-not $workflowId) {
            $created = Get-AllRows "workflows?`$select=workflowid,name&`$filter=category eq 5 and name eq '$escapedName'&`$top=1" | Select-Object -First 1
            $workflowId = $created.workflowid
        }
    }

    $addedToSolution = $false
    if ($workflowId) {
        $addedToSolution = Add-ComponentToSolution -ComponentType 29 -ComponentId ([guid]$workflowId)
        try {
            Invoke-DvPatchNoContent "workflows($workflowId)" @{ statecode = 1; statuscode = 2 }
            Start-Sleep -Seconds 4
            $activationResult = 'activated'
        }
        catch {
            $activationResult = 'activation-failed'
            $activationFailure = $_.Exception.Message
            try {
                Invoke-DvPatchNoContent "workflows($workflowId)" @{ statecode = 0; statuscode = 1 }
            }
            catch {
                $null = $true
            }
        }
    }

    $after = if ($workflowId) { Invoke-DvGet "workflows($workflowId)?`$select=workflowid,name,statecode,statuscode,category,type,primaryentity" } else { $null }
    [ordered]@{
        flowName = $FlowName
        workflowId = $workflowId
        mode = $mode
        addedToSolution = $addedToSolution
        activationResult = $activationResult
        activationFailure = $activationFailure
        statecode = if ($after) { $after.statecode } else { $null }
        statuscode = if ($after) { $after.statuscode } else { $null }
        purpose = $Purpose
        noSend = $true
    }
}

function New-LayoutXml {
    param([string]$EntityName, [int]$ObjectTypeCode, [string]$PrimaryId, [string[]]$Columns)
    $cells = ""
    foreach ($column in $Columns) {
        $cells += "<cell name=`"$column`" width=`"180`" />"
    }
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
        if (-not [string]::IsNullOrWhiteSpace($column)) {
            $attributeXml += "<attribute name=`"$column`" />"
        }
    }
    $fetchXml = "<fetch version=`"1.0`" mapping=`"logical`"><entity name=`"$Table`">$attributeXml$FilterXml<order attribute=`"$OrderColumn`" descending=`"true`" /></entity></fetch>"
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
            if ($reloaded) {
                $viewId = $reloaded.savedqueryid
            }
        }
        $status = 'created'
    }

    $addedToSolution = $false
    if ($viewId) {
        $addedToSolution = Add-ComponentToSolution -ComponentType 26 -ComponentId ([guid]$viewId)
    }

    [ordered]@{
        table = $Table
        viewName = $ViewName
        savedqueryid = $viewId
        status = $status
        addedToSolution = $addedToSolution
    }
}

function Ensure-AdminViews {
    $views = @()
    $alertCols = @('qfu_name','qfu_alerttype','qfu_status','qfu_recipientstaff','qfu_recipientemail','qfu_dedupekey','qfu_senton','qfu_failuremessage','createdon')
    $views += Ensure-View -Table 'qfu_alertlog' -ViewName 'All Alert Logs' -Columns $alertCols -OrderColumn 'createdon'
    $views += Ensure-View -Table 'qfu_alertlog' -ViewName 'Dry Run Alert Logs' -Columns $alertCols -FilterXml '<filter type="and"><condition attribute="qfu_status" operator="eq" value="985010003" /></filter>' -OrderColumn 'createdon'
    $views += Ensure-View -Table 'qfu_alertlog' -ViewName 'Skipped Alerts' -Columns $alertCols -FilterXml '<filter type="and"><condition attribute="qfu_status" operator="eq" value="985010004" /></filter>' -OrderColumn 'createdon'
    $views += Ensure-View -Table 'qfu_alertlog' -ViewName 'Missing Recipient Email' -Columns $alertCols -FilterXml '<filter type="and"><condition attribute="qfu_status" operator="eq" value="985010004" /><condition attribute="qfu_notes" operator="like" value="%Missing recipient email%" /></filter>' -OrderColumn 'createdon'
    $views += Ensure-View -Table 'qfu_alertlog' -ViewName 'Failed Alerts' -Columns $alertCols -FilterXml '<filter type="and"><condition attribute="qfu_status" operator="eq" value="985010002" /></filter>' -OrderColumn 'createdon'
    $views += Ensure-View -Table 'qfu_alertlog' -ViewName 'Sent Alerts' -Columns $alertCols -FilterXml '<filter type="and"><condition attribute="qfu_status" operator="eq" value="985010001" /></filter>' -OrderColumn 'createdon'
    $views += Ensure-View -Table 'qfu_alertlog' -ViewName 'Duplicate Suppressed Alerts' -Columns $alertCols -FilterXml '<filter type="and"><condition attribute="qfu_notes" operator="like" value="%Duplicate suppressed%" /></filter>' -OrderColumn 'createdon'
    $views += Ensure-View -Table 'qfu_alertlog' -ViewName 'Alerts by Work Item' -Columns @('qfu_workitem','qfu_alerttype','qfu_status','qfu_recipientstaff','qfu_dedupekey','createdon') -OrderColumn 'createdon'
    $views += Ensure-View -Table 'qfu_alertlog' -ViewName 'Alerts by Recipient' -Columns @('qfu_recipientstaff','qfu_recipientemail','qfu_alerttype','qfu_status','qfu_dedupekey','createdon') -OrderColumn 'createdon'

    $views += Ensure-View -Table 'qfu_staff' -ViewName 'Staff Missing Email' -Columns @('qfu_name','qfu_staffnumber','qfu_primaryemail','qfu_active','qfu_systemuser') -FilterXml '<filter type="and"><condition attribute="statecode" operator="eq" value="0" /><condition attribute="qfu_primaryemail" operator="null" /></filter>' -OrderColumn 'qfu_name'
    $views += Ensure-View -Table 'qfu_staff' -ViewName 'Staff With Email' -Columns @('qfu_name','qfu_staffnumber','qfu_primaryemail','qfu_active','qfu_systemuser') -FilterXml '<filter type="and"><condition attribute="statecode" operator="eq" value="0" /><condition attribute="qfu_primaryemail" operator="not-null" /></filter>' -OrderColumn 'qfu_name'
    $views += Ensure-View -Table 'qfu_staff' -ViewName 'Staff Missing Systemuser' -Columns @('qfu_name','qfu_staffnumber','qfu_primaryemail','qfu_systemuser','qfu_active') -FilterXml '<filter type="and"><condition attribute="statecode" operator="eq" value="0" /><condition attribute="qfu_systemuser" operator="null" /></filter>' -OrderColumn 'qfu_name'
    $views += Ensure-View -Table 'qfu_staff' -ViewName 'Active Staff With Work Items' -Columns @('qfu_name','qfu_staffnumber','qfu_primaryemail','qfu_defaultbranch','qfu_active') -FilterXml '<filter type="and"><condition attribute="statecode" operator="eq" value="0" /></filter>' -OrderColumn 'qfu_name'

    $membershipCols = @('qfu_name','qfu_branch','qfu_staff','qfu_role','qfu_active','qfu_startdate','qfu_enddate')
    $views += Ensure-View -Table 'qfu_branchmembership' -ViewName 'Managers Missing Email' -Columns $membershipCols -FilterXml '<filter type="and"><condition attribute="statecode" operator="eq" value="0" /><condition attribute="qfu_role" operator="eq" value="100000002" /></filter>' -OrderColumn 'qfu_name'
    $views += Ensure-View -Table 'qfu_branchmembership' -ViewName 'GMs Missing Email' -Columns $membershipCols -FilterXml '<filter type="and"><condition attribute="statecode" operator="eq" value="0" /><condition attribute="qfu_role" operator="eq" value="100000003" /></filter>' -OrderColumn 'qfu_name'
    $views += Ensure-View -Table 'qfu_branchmembership' -ViewName 'Admins Missing Email' -Columns $membershipCols -FilterXml '<filter type="and"><condition attribute="statecode" operator="eq" value="0" /><condition attribute="qfu_role" operator="eq" value="100000004" /></filter>' -OrderColumn 'qfu_name'
    $views += Ensure-View -Table 'qfu_branchmembership' -ViewName 'Active Alert Recipients' -Columns $membershipCols -FilterXml '<filter type="and"><condition attribute="statecode" operator="eq" value="0" /><condition attribute="qfu_role" operator="in"><value>100000002</value><value>100000003</value><value>100000004</value></condition></filter>' -OrderColumn 'qfu_name'

    $policyCols = @('qfu_name','qfu_policykey','qfu_worktype','qfu_alertmode','qfu_digestenabled','qfu_targetedalertenabled','qfu_highvaluethreshold','qfu_requiredattempts','qfu_active')
    $views += Ensure-View -Table 'qfu_policy' -ViewName 'Active Alert Policies' -Columns $policyCols -FilterXml '<filter type="and"><condition attribute="statecode" operator="eq" value="0" /><condition attribute="qfu_active" operator="eq" value="1" /></filter>' -OrderColumn 'qfu_name'
    $views += Ensure-View -Table 'qfu_policy' -ViewName 'Quote Alert Policies' -Columns $policyCols -FilterXml '<filter type="and"><condition attribute="qfu_worktype" operator="eq" value="985010000" /></filter>' -OrderColumn 'qfu_name'
    $views += Ensure-View -Table 'qfu_policy' -ViewName 'Digest Enabled Policies' -Columns $policyCols -FilterXml '<filter type="and"><condition attribute="qfu_digestenabled" operator="eq" value="1" /></filter>' -OrderColumn 'qfu_name'
    $views += Ensure-View -Table 'qfu_policy' -ViewName 'Targeted Alert Enabled Policies' -Columns $policyCols -FilterXml '<filter type="and"><condition attribute="qfu_targetedalertenabled" operator="eq" value="1" /></filter>' -OrderColumn 'qfu_name'

    $exceptionCols = @('qfu_name','qfu_branch','qfu_exceptiontype','qfu_status','qfu_workitem','createdon','qfu_notes')
    $views += Ensure-View -Table 'qfu_assignmentexception' -ViewName 'Open Exceptions by Branch' -Columns $exceptionCols -FilterXml '<filter type="and"><condition attribute="qfu_status" operator="eq" value="985010000" /></filter>' -OrderColumn 'createdon'
    $views += Ensure-View -Table 'qfu_assignmentexception' -ViewName 'Exceptions Needing Manager Review' -Columns $exceptionCols -FilterXml '<filter type="and"><condition attribute="qfu_status" operator="in"><value>985010000</value><value>985010001</value></condition></filter>' -OrderColumn 'createdon'

    return $views
}

$solution = Get-AllRows "solutions?`$select=solutionid,uniquename,friendlyname&`$filter=uniquename eq '$SolutionUniqueName'&`$top=1" | Select-Object -First 1
if (-not $solution) {
    throw "Solution '$SolutionUniqueName' was not found in $EnvironmentUrl."
}

$policyAlertMode = Ensure-PolicyAlertModeField
$policyResult = Ensure-DefaultPolicy
$dedupeKey = Ensure-AlertLogDedupeKey

$flows = @()
$flows += Ensure-Flow -FlowName 'QFU Alert Dispatcher - Phase 6' -Purpose 'Processes targeted new-assignment, due-today, overdue, roadblock, and escalation alert candidates'
$flows += Ensure-Flow -FlowName 'QFU Daily Staff Digest - Phase 6' -Purpose 'Builds daily staff digest candidates grouped by current queue owner'
$flows += Ensure-Flow -FlowName 'QFU Manager Digest - Phase 6' -Purpose 'Builds manager and GM branch/team digest candidates'
$flows += Ensure-Flow -FlowName 'QFU Escalation Processor - Phase 6' -Purpose 'Builds overdue, roadblock, and missing-assignment escalation candidates'
$flows += Ensure-Flow -FlowName 'QFU Assignment Exception Digest - Phase 6' -Purpose 'Builds assignment-exception digest candidates for managers, GMs, and admins'
$flows += Ensure-Flow -FlowName 'QFU Alert Flow Health Monitor - Phase 6' -Purpose 'Surfaces failed, skipped, duplicate-suppressed, and dry-run alert-log health'

$views = Ensure-AdminViews

Invoke-DvPost 'PublishAllXml' @{} | Out-Null
Start-Sleep -Seconds 8

$result = [ordered]@{
    environmentUrl = $EnvironmentUrl
    timestamp = (Get-Date).ToString('o')
    solutionUniqueName = $SolutionUniqueName
    solutionFound = $true
    alertModeField = $policyAlertMode
    defaultPolicy = $policyResult
    alertLogDedupeKey = $dedupeKey
    flowShells = @($flows)
    adminViews = @($views)
    defaultMode = 'DryRunOnly'
    sendsEmail = $false
    sendsTeams = $false
    note = 'Phase 6 infrastructure is safe by default. Flow shells are solution-aware and no-send; dry-run candidates and qfu_alertlog dedupe are validated by Test-RevenueFollowUpPhase6DryRun.ps1.'
}

$directory = Split-Path -Parent $OutputPath
if ($directory) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}
$result | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
$result | ConvertTo-Json -Depth 100
