param(
    [string]$EnvironmentUrl = "https://orga632edd5.crm3.dynamics.com/",
    [string]$SolutionUniqueName = "qfu_revenuefollowupworkbench",
    [string]$ResultPath = "results/phase2-1B-live-build-result-20260427.json"
)

$ErrorActionPreference = "Stop"

Import-Module Az.Accounts -ErrorAction Stop

if (-not $EnvironmentUrl.EndsWith("/")) {
    $EnvironmentUrl = "$EnvironmentUrl/"
}

$AppDisplayName = "Revenue Follow-Up Workbench"
$AppUniqueName = "qfu_RevenueFollowUpWorkbench"
$AreaLabel = "Admin Panel MVP"
$standardControlClassId = "{4273EDBD-AC1D-40d3-9FB2-095C621B552D}"

function Convert-AccessTokenToString {
    param([object]$Token)

    if ($Token -is [securestring]) {
        return [System.Net.NetworkCredential]::new("", $Token).Password
    }

    return [string]$Token
}

function Get-DataverseToken {
    $tokenResult = Get-AzAccessToken -ResourceUrl $EnvironmentUrl
    return Convert-AccessTokenToString -Token $tokenResult.Token
}

$script:token = Get-DataverseToken

function Get-Headers {
    param([bool]$WriteOperation = $false)

    $headers = @{
        Authorization      = "Bearer $script:token"
        "OData-MaxVersion" = "4.0"
        "OData-Version"    = "4.0"
        Accept             = "application/json"
        "Content-Type"     = "application/json; charset=utf-8"
    }

    if ($WriteOperation) {
        $headers["MSCRM.SolutionUniqueName"] = $SolutionUniqueName
        $headers["Prefer"] = "return=representation"
    }

    return $headers
}

function Invoke-Dv {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        [object]$Body = $null,
        [bool]$WriteOperation = $false
    )

    $uri = "$($EnvironmentUrl)api/data/v9.2/$Path"
    $headers = Get-Headers -WriteOperation:$WriteOperation

    if ($null -eq $Body) {
        return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -ErrorAction Stop
    }

    $json = $Body | ConvertTo-Json -Depth 100
    return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -Body $json -ErrorAction Stop
}

function Invoke-DvNoContent {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        [object]$Body = $null,
        [bool]$WriteOperation = $false
    )

    $uri = "$($EnvironmentUrl)api/data/v9.2/$Path"
    $headers = Get-Headers -WriteOperation:$WriteOperation
    if ($headers.ContainsKey("Prefer")) {
        $headers.Remove("Prefer")
    }

    if ($null -eq $Body) {
        return Invoke-WebRequest -UseBasicParsing -Method $Method -Uri $uri -Headers $headers -ErrorAction Stop
    }

    $json = $Body | ConvertTo-Json -Depth 100
    return Invoke-WebRequest -UseBasicParsing -Method $Method -Uri $uri -Headers $headers -Body $json -ErrorAction Stop
}

function Invoke-DvOrNull {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        return Invoke-Dv -Method Get -Path $Path
    }
    catch {
        return $null
    }
}

function Escape-ODataValue {
    param([string]$Value)
    return $Value.Replace("'", "''")
}

function Escape-XmlValue {
    param([string]$Value)
    return [System.Security.SecurityElement]::Escape($Value)
}

function New-Id {
    return ([guid]::NewGuid()).ToString("D")
}

function Get-First {
    param([object]$Response)

    if ($Response -and $Response.value -and $Response.value.Count -gt 0) {
        return $Response.value[0]
    }

    return $null
}

function Get-OptionValue {
    param(
        [string]$ChoiceName,
        [string]$Label
    )

    $choice = Invoke-Dv -Method Get -Path "GlobalOptionSetDefinitions(Name='$ChoiceName')"
    foreach ($option in $choice.Options) {
        $localized = $option.Label.UserLocalizedLabel.Label
        if ($localized -eq $Label) {
            return [int]$option.Value
        }
    }

    return $null
}

function New-FormXml {
    param(
        [string]$TabLabel,
        [array]$Sections
    )

    $tabId = New-Id
    $xml = "<form><tabs><tab verticallayout=`"true`" id=`"{$tabId}`" IsUserDefined=`"1`"><labels><label description=`"$(Escape-XmlValue $TabLabel)`" languagecode=`"1033`" /></labels><columns><column width=`"100%`"><sections>"

    foreach ($section in $Sections) {
        $sectionId = New-Id
        $sectionLabel = Escape-XmlValue $section.Label
        $xml += "<section showlabel=`"true`" showbar=`"false`" IsUserDefined=`"1`" id=`"{$sectionId}`"><labels><label description=`"$sectionLabel`" languagecode=`"1033`" /></labels><rows>"
        foreach ($field in $section.Fields) {
            $cellId = New-Id
            $label = Escape-XmlValue $field.Label
            $logicalName = Escape-XmlValue $field.Name
            $xml += "<row><cell id=`"{$cellId}`"><labels><label description=`"$label`" languagecode=`"1033`" /></labels><control id=`"$logicalName`" classid=`"$standardControlClassId`" datafieldname=`"$logicalName`" /></cell></row>"
        }
        $xml += "</rows></section>"
    }

    $xml += "</sections></column></columns></tab></tabs></form>"
    return $xml
}

function New-LayoutXml {
    param(
        [string]$EntityName,
        [int]$ObjectTypeCode,
        [string]$PrimaryId,
        [string]$JumpColumn,
        [string[]]$Columns
    )

    $xml = "<grid name=`"resultset`" jump=`"$JumpColumn`" select=`"1`" icon=`"1`" preview=`"1`" object=`"$ObjectTypeCode`"><row name=`"result`" id=`"$PrimaryId`">"
    foreach ($column in $Columns | Select-Object -First 10) {
        $width = if ($column -match "note|message|failure|external|customer") { 250 } elseif ($column -match "date|on$|since") { 150 } else { 175 }
        $xml += "<cell name=`"$column`" width=`"$width`" />"
    }
    $xml += "</row></grid>"
    return $xml
}

function New-FetchXml {
    param(
        [string]$EntityName,
        [string[]]$Columns,
        [string]$OrderColumn,
        [string]$FilterXml = ""
    )

    $xml = "<fetch version=`"1.0`" mapping=`"logical`"><entity name=`"$EntityName`">"
    foreach ($column in @($Columns | Select-Object -Unique)) {
        $xml += "<attribute name=`"$column`" />"
    }
    if ($OrderColumn) {
        $xml += "<order attribute=`"$OrderColumn`" descending=`"false`" />"
    }
    if ($FilterXml) {
        $xml += $FilterXml
    }
    $xml += "</entity></fetch>"
    return $xml
}

function New-ConditionFilter {
    param([string[]]$Conditions)

    if (-not $Conditions -or $Conditions.Count -eq 0) {
        return ""
    }

    return "<filter type=`"and`">" + ($Conditions -join "") + "</filter>"
}

function Condition {
    param(
        [string]$Attribute,
        [string]$Operator,
        [object]$Value = $null
    )

    if ($null -eq $Value -or $Operator -in @("null", "not-null")) {
        return "<condition attribute=`"$Attribute`" operator=`"$Operator`" />"
    }

    return "<condition attribute=`"$Attribute`" operator=`"$Operator`" value=`"$Value`" />"
}

function Ensure-AdminForm {
    param(
        [string]$Table,
        [string]$DisplayName,
        [array]$Sections
    )

    $filter = [System.Uri]::EscapeDataString("objecttypecode eq '$Table' and type eq 2")
    $forms = Invoke-Dv -Method Get -Path "systemforms?`$select=formid,name,type,objecttypecode&`$filter=$filter"
    $form = Get-First $forms
    if (-not $form) {
        throw "No main form found for $Table"
    }

    $formName = "$DisplayName Admin Main"
    $formXml = New-FormXml -TabLabel $formName -Sections $Sections
    $body = @{
        name        = $formName
        description = "Phase 2.1B Revenue Follow-Up Workbench Admin Panel MVP form."
        formxml     = $formXml
    }
    Invoke-DvNoContent -Method Patch -Path "systemforms($($form.formid))" -Body $body -WriteOperation:$true | Out-Null

    return [ordered]@{
        table  = $Table
        name   = $formName
        formid = $form.formid
        fields = @($Sections | ForEach-Object { $_.Fields } | ForEach-Object { $_.Name })
    }
}

function Ensure-View {
    param(
        [string]$Table,
        [object]$EntityMetadata,
        [string]$ViewName,
        [string[]]$Columns,
        [string]$FilterXml,
        [string]$OrderColumn
    )

    $escapedName = Escape-ODataValue $ViewName
    $filter = [System.Uri]::EscapeDataString("returnedtypecode eq '$Table' and querytype eq 0 and name eq '$escapedName'")
    $existing = Invoke-Dv -Method Get -Path "savedqueries?`$select=savedqueryid,name,returnedtypecode,querytype&`$filter=$filter"
    $view = Get-First $existing
    $layoutXml = New-LayoutXml -EntityName $Table -ObjectTypeCode ([int]$EntityMetadata.ObjectTypeCode) -PrimaryId $EntityMetadata.PrimaryIdAttribute -JumpColumn $EntityMetadata.PrimaryNameAttribute -Columns $Columns
    $fetchXml = New-FetchXml -EntityName $Table -Columns (@($EntityMetadata.PrimaryIdAttribute) + $Columns) -OrderColumn $OrderColumn -FilterXml $FilterXml
    $body = @{
        name             = $ViewName
        returnedtypecode = $Table
        querytype        = 0
        isdefault        = $false
        isquickfindquery = $false
        fetchxml         = $fetchXml
        layoutxml        = $layoutXml
    }

    if ($view) {
        Invoke-DvNoContent -Method Patch -Path "savedqueries($($view.savedqueryid))" -Body $body -WriteOperation:$true | Out-Null
        $viewId = $view.savedqueryid
        $created = $false
    }
    else {
        $createdView = Invoke-Dv -Method Post -Path "savedqueries" -Body $body -WriteOperation:$true
        $viewId = $createdView.savedqueryid
        $created = $true
    }

    return [ordered]@{
        table        = $Table
        name         = $ViewName
        savedqueryid = $viewId
        created      = $created
        columns      = $Columns
        filterxml    = $FilterXml
    }
}

function Ensure-SiteMap {
    param([array]$NavItems)

    $subareas = ""
    foreach ($item in $NavItems) {
        $subareas += "<SubArea Id=`"$($item.Id)`" Entity=`"$($item.Table)`" Client=`"All,Outlook,OutlookLaptopClient,OutlookWorkstationClient,Web`" AvailableOffline=`"true`" PassParams=`"false`" Sku=`"All,OnPremise,Live,SPLA`"><Titles><Title LCID=`"1033`" Title=`"$(Escape-XmlValue $item.Label)`" /></Titles></SubArea>"
    }

    $sitemapXml = "<SiteMap IntroducedVersion=`"7.0.0.0`"><Area Id=`"qfu_admin_panel_mvp`" ShowGroups=`"true`" IntroducedVersion=`"7.0.0.0`"><Titles><Title LCID=`"1033`" Title=`"$AreaLabel`" /></Titles><Group Id=`"qfu_admin_group`" IsProfile=`"false`" IntroducedVersion=`"7.0.0.0`"><Titles><Title LCID=`"1033`" Title=`"Workbench Administration`" /></Titles>$subareas</Group></Area></SiteMap>"

    $filter = [System.Uri]::EscapeDataString("sitemapnameunique eq '$AppUniqueName' or sitemapname eq '$AppDisplayName'")
    $existing = Invoke-Dv -Method Get -Path "sitemaps?`$select=sitemapid,sitemapname,sitemapnameunique&`$filter=$filter"
    $siteMap = Get-First $existing
    $body = @{
        sitemapname             = $AppDisplayName
        sitemapnameunique       = $AppUniqueName
        sitemapxml              = $sitemapXml
        isappaware              = $true
        showhome                = $true
        showrecents             = $true
        showpinned              = $true
        enablecollapsiblegroups = $true
    }

    if ($siteMap) {
        Invoke-DvNoContent -Method Patch -Path "sitemaps($($siteMap.sitemapid))" -Body $body -WriteOperation:$true | Out-Null
        return [ordered]@{ sitemapid = $siteMap.sitemapid; created = $false; sitemapxml = $sitemapXml }
    }

    $created = Invoke-Dv -Method Post -Path "sitemaps" -Body $body -WriteOperation:$true
    return [ordered]@{ sitemapid = $created.sitemapid; created = $true; sitemapxml = $sitemapXml }
}

function Ensure-AppModule {
    param(
        [string]$WebResourceId,
        [string]$PublisherId
    )

    $select = "appmoduleid,appmoduleidunique,name,uniquename,clienttype,formfactor,navigationtype,url"
    $nameFilter = [System.Uri]::EscapeDataString("uniquename eq '$AppUniqueName' or name eq '$AppDisplayName'")
    $existing = Invoke-Dv -Method Get -Path "appmodules?`$select=$select&`$filter=$nameFilter"
    $app = Get-First $existing
    if (-not $app) {
        $unpublished = Invoke-Dv -Method Get -Path "appmodules/Microsoft.Dynamics.CRM.RetrieveUnpublishedMultiple()?`$select=$select"
        $app = @($unpublished.value | Where-Object { $_.uniquename -eq $AppUniqueName -or $_.name -eq $AppDisplayName } | Select-Object -First 1)[0]
    }
    $body = @{
        name           = $AppDisplayName
        uniquename     = $AppUniqueName
        clienttype     = 4
        formfactor     = 1
        navigationtype = 0
        isfeatured     = $false
        isdefault      = $false
        description    = "Revenue Follow-Up Workbench Admin Panel MVP."
        webresourceid  = $WebResourceId
    }

    if ($app) {
        Invoke-DvNoContent -Method Patch -Path "appmodules($($app.appmoduleid))" -Body $body -WriteOperation:$true | Out-Null
        $refreshed = Invoke-DvOrNull -Path "appmodules($($app.appmoduleid))?`$select=$select"
        if (-not $refreshed) {
            $unpublished = Invoke-Dv -Method Get -Path "appmodules/Microsoft.Dynamics.CRM.RetrieveUnpublishedMultiple()?`$select=$select"
            $refreshed = @($unpublished.value | Where-Object { $_.appmoduleid -eq $app.appmoduleid } | Select-Object -First 1)[0]
        }
        return [ordered]@{ app = $refreshed; created = $false }
    }

    $createBody = $body.Clone()
    $createBody["appmoduleidunique"] = (New-Id)
    if ($PublisherId) {
        $createBody["publisher_appmodule_appmodule@odata.bind"] = "/publishers($PublisherId)"
    }
    Invoke-DvNoContent -Method Post -Path "appmodules" -Body $createBody -WriteOperation:$true | Out-Null
    Start-Sleep -Seconds 3
    $createdLookupFilter = [System.Uri]::EscapeDataString("uniquename eq '$AppUniqueName'")
    $createdLookup = Invoke-Dv -Method Get -Path "appmodules?`$select=$select&`$filter=$createdLookupFilter"
    $created = Get-First $createdLookup
    if (-not $created) {
        $unpublished = Invoke-Dv -Method Get -Path "appmodules/Microsoft.Dynamics.CRM.RetrieveUnpublishedMultiple()?`$select=$select"
        $created = @($unpublished.value | Where-Object { $_.uniquename -eq $AppUniqueName } | Select-Object -First 1)[0]
    }
    if (-not $created) {
        throw "Appmodule create returned no content and the app could not be retrieved by uniquename $AppUniqueName."
    }
    return [ordered]@{ app = $created; created = $true }
}

function Ensure-AppIconWebResource {
    $name = "qfu_/RevenueFollowUpWorkbenchIcon.svg"
    $displayName = "Revenue Follow-Up Workbench App Icon"
    $svg = @"
<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">
  <rect width="32" height="32" rx="6" fill="#0F6C81"/>
  <path d="M8 9h16v3H8zM8 15h12v3H8zM8 21h16v3H8z" fill="#FFFFFF"/>
  <circle cx="24" cy="16" r="3" fill="#F6C343"/>
</svg>
"@
    $content = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($svg))
    $filter = [System.Uri]::EscapeDataString("name eq '$name'")
    $existing = Invoke-Dv -Method Get -Path "webresourceset?`$select=webresourceid,name,displayname,webresourcetype&`$filter=$filter"
    $body = @{
        name            = $name
        displayname     = $displayName
        description     = "Phase 2.1B app icon for Revenue Follow-Up Workbench."
        webresourcetype = 11
        content         = $content
    }

    $webResource = Get-First $existing
    if ($webResource) {
        Invoke-DvNoContent -Method Patch -Path "webresourceset($($webResource.webresourceid))" -Body $body -WriteOperation:$true | Out-Null
        return [ordered]@{ webresourceid = $webResource.webresourceid; name = $name; created = $false }
    }

    $created = Invoke-Dv -Method Post -Path "webresourceset" -Body $body -WriteOperation:$true
    return [ordered]@{ webresourceid = $created.webresourceid; name = $name; created = $true }
}

function Try-AddAppComponentsAction {
    param(
        [string]$AppId,
        [array]$Components
    )

    for ($i = 0; $i -lt $Components.Count; $i += 10) {
        $chunk = @($Components | Select-Object -Skip $i -First 10)
        $body = @{
            AppId      = $AppId
            Components = $chunk
        }

        Invoke-DvNoContent -Method Post -Path "AddAppComponents" -Body $body -WriteOperation:$true | Out-Null
    }
}

function Publish-AppModule {
    param([string]$AppId)

    $parameterXml = "<importexportxml><appmodules><appmodule>$AppId</appmodule></appmodules></importexportxml>"
    Invoke-DvNoContent -Method Post -Path "PublishXml" -Body @{ ParameterXml = $parameterXml } -WriteOperation:$true | Out-Null
}

function Ensure-AppModuleComponentDirect {
    param(
        [string]$AppModuleId,
        [string]$ObjectId,
        [int]$ComponentType
    )

    $filter = [System.Uri]::EscapeDataString("_appmoduleidunique_value eq $AppModuleId and objectid eq $ObjectId and componenttype eq $ComponentType")
    $existing = Invoke-DvOrNull -Path "appmodulecomponents?`$select=appmodulecomponentid&`$filter=$filter"
    if ($existing -and $existing.value.Count -gt 0) {
        return $existing.value[0].appmodulecomponentid
    }

    $body = @{
        "appmoduleidunique@odata.bind" = "/appmodules($AppModuleId)"
        objectid                       = $ObjectId
        componenttype                  = $ComponentType
        isdefault                      = $false
    }
    $created = Invoke-Dv -Method Post -Path "appmodulecomponents" -Body $body -WriteOperation:$true
    return $created.appmodulecomponentid
}

function Invoke-Pac {
    param([string[]]$Arguments)

    $output = & pac @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    return [ordered]@{
        command  = "pac " + ($Arguments -join " ")
        exitCode = $exitCode
        output   = ($output -join "`n")
    }
}

$result = [ordered]@{
    phase                 = "Phase 2.1B"
    checkedAtUtc          = (Get-Date).ToUniversalTime().ToString("o")
    environmentUrl        = $EnvironmentUrl.TrimEnd("/")
    solutionUniqueName    = $SolutionUniqueName
    appDisplayName        = $AppDisplayName
    appUniqueName         = $AppUniqueName
    solutionFound         = $false
    tablesFound           = @()
    choices               = @{}
    forms                 = @()
    views                 = @()
    sitemap               = $null
    webResource           = $null
    app                   = $null
    appComponentsMethod   = $null
    directComponents      = @()
    pacAddComponent       = @()
    publish               = $null
    validateApp           = $null
    retrieveComponents    = @()
    errors                = @()
    warnings              = @()
}

try {
    $solutionFilter = [System.Uri]::EscapeDataString("uniquename eq '$SolutionUniqueName'")
    $solution = Invoke-Dv -Method Get -Path "solutions?`$select=solutionid,uniquename,friendlyname,version,ismanaged&`$filter=$solutionFilter"
    if (-not $solution.value -or $solution.value.Count -eq 0) {
        throw "Solution $SolutionUniqueName not found in $EnvironmentUrl"
    }
    $result.solutionFound = $true
    $result.solution = $solution.value[0]
    $solutionDetail = Invoke-Dv -Method Get -Path "solutions($($result.solution.solutionid))?`$select=solutionid,uniquename,_publisherid_value"
    $publisherId = $solutionDetail._publisherid_value

    $navItems = @(
        [ordered]@{ Id = "qfu_nav_staff"; Label = "Staff"; Table = "qfu_staff" },
        [ordered]@{ Id = "qfu_nav_branchmembership"; Label = "Branch Memberships"; Table = "qfu_branchmembership" },
        [ordered]@{ Id = "qfu_nav_staffalias"; Label = "Staff Alias Mapping"; Table = "qfu_staffalias" },
        [ordered]@{ Id = "qfu_nav_policy"; Label = "Branch Policies"; Table = "qfu_policy" },
        [ordered]@{ Id = "qfu_nav_assignmentexception"; Label = "Assignment Exceptions"; Table = "qfu_assignmentexception" },
        [ordered]@{ Id = "qfu_nav_workitem"; Label = "Work Items"; Table = "qfu_workitem" },
        [ordered]@{ Id = "qfu_nav_workitemaction"; Label = "Work Item Actions"; Table = "qfu_workitemaction" },
        [ordered]@{ Id = "qfu_nav_alertlog"; Label = "Alert Logs"; Table = "qfu_alertlog" }
    )

    $metadata = @{}
    foreach ($item in $navItems) {
        $entity = Invoke-Dv -Method Get -Path "EntityDefinitions(LogicalName='$($item.Table)')?`$select=LogicalName,MetadataId,ObjectTypeCode,PrimaryIdAttribute,PrimaryNameAttribute"
        if (-not $entity) {
            throw "Required table $($item.Table) not found"
        }
        $metadata[$item.Table] = $entity
        $result.tablesFound += [ordered]@{
            logicalName          = $entity.LogicalName
            metadataId           = $entity.MetadataId
            objectTypeCode       = $entity.ObjectTypeCode
            primaryIdAttribute   = $entity.PrimaryIdAttribute
            primaryNameAttribute = $entity.PrimaryNameAttribute
        }
    }

    foreach ($choiceName in @("qfu_worktype", "qfu_exceptiontype", "qfu_exceptionstatus", "qfu_workitemstatus", "qfu_assignmentstatus", "qfu_alertstatus")) {
        $choice = Invoke-Dv -Method Get -Path "GlobalOptionSetDefinitions(Name='$choiceName')"
        $result.choices[$choiceName] = @($choice.Options | ForEach-Object { [ordered]@{ value = $_.Value; label = $_.Label.UserLocalizedLabel.Label } })
    }

    $workTypeQuote = Get-OptionValue -ChoiceName "qfu_worktype" -Label "Quote"
    $exceptionOpen = Get-OptionValue -ChoiceName "qfu_exceptionstatus" -Label "Open"
    $exceptionResolved = Get-OptionValue -ChoiceName "qfu_exceptionstatus" -Label "Resolved"
    $missingTsrAlias = Get-OptionValue -ChoiceName "qfu_exceptiontype" -Label "Missing TSR Alias"
    $missingCssrAlias = Get-OptionValue -ChoiceName "qfu_exceptiontype" -Label "Missing CSSR Alias"
    $blankAlias = Get-OptionValue -ChoiceName "qfu_exceptiontype" -Label "Blank Alias"
    $zeroAlias = Get-OptionValue -ChoiceName "qfu_exceptiontype" -Label "Zero Alias"
    $workOpen = Get-OptionValue -ChoiceName "qfu_workitemstatus" -Label "Open"
    $needsTsr = Get-OptionValue -ChoiceName "qfu_assignmentstatus" -Label "Needs TSR Assignment"
    $needsCssr = Get-OptionValue -ChoiceName "qfu_assignmentstatus" -Label "Needs CSSR Assignment"
    $alertPending = Get-OptionValue -ChoiceName "qfu_alertstatus" -Label "Pending"
    $alertSent = Get-OptionValue -ChoiceName "qfu_alertstatus" -Label "Sent"
    $alertFailed = Get-OptionValue -ChoiceName "qfu_alertstatus" -Label "Failed"
    $alertSuppressed = Get-OptionValue -ChoiceName "qfu_alertstatus" -Label "Suppressed"
    $alertSkipped = Get-OptionValue -ChoiceName "qfu_alertstatus" -Label "Skipped"

    $forms = [ordered]@{
        qfu_staff = [ordered]@{
            DisplayName = "Staff"
            Sections    = @(
                [ordered]@{ Label = "Staff"; Fields = @(
                    [ordered]@{ Name = "qfu_name"; Label = "Staff Name" },
                    [ordered]@{ Name = "qfu_primaryemail"; Label = "Primary Email" },
                    [ordered]@{ Name = "qfu_staffnumber"; Label = "Staff Number" },
                    [ordered]@{ Name = "qfu_systemuser"; Label = "Dataverse User" },
                    [ordered]@{ Name = "qfu_entraobjectid"; Label = "Entra Object ID" },
                    [ordered]@{ Name = "qfu_defaultbranch"; Label = "Default Branch" },
                    [ordered]@{ Name = "qfu_active"; Label = "Active" },
                    [ordered]@{ Name = "qfu_notes"; Label = "Notes" }
                ) }
            )
        }
        qfu_branchmembership = [ordered]@{
            DisplayName = "Branch Membership"
            Sections    = @(
                [ordered]@{ Label = "Membership"; Fields = @(
                    [ordered]@{ Name = "qfu_branch"; Label = "Branch" },
                    [ordered]@{ Name = "qfu_staff"; Label = "Staff" },
                    [ordered]@{ Name = "qfu_role"; Label = "Role" },
                    [ordered]@{ Name = "qfu_active"; Label = "Active" },
                    [ordered]@{ Name = "qfu_startdate"; Label = "Start Date" },
                    [ordered]@{ Name = "qfu_enddate"; Label = "End Date" },
                    [ordered]@{ Name = "qfu_isprimary"; Label = "Is Primary" },
                    [ordered]@{ Name = "qfu_notes"; Label = "Notes" }
                ) }
            )
        }
        qfu_staffalias = [ordered]@{
            DisplayName = "Staff Alias Mapping"
            Sections    = @(
                [ordered]@{ Label = "Alias"; Fields = @(
                    [ordered]@{ Name = "qfu_sourcesystem"; Label = "Source System" },
                    [ordered]@{ Name = "qfu_aliastype"; Label = "Alias Type" },
                    [ordered]@{ Name = "qfu_rawalias"; Label = "Raw Alias" },
                    [ordered]@{ Name = "qfu_normalizedalias"; Label = "Normalized Alias" },
                    [ordered]@{ Name = "qfu_rolehint"; Label = "Role Hint" },
                    [ordered]@{ Name = "qfu_branch"; Label = "Branch" },
                    [ordered]@{ Name = "qfu_scopekey"; Label = "Scope Key" },
                    [ordered]@{ Name = "qfu_staff"; Label = "Staff" },
                    [ordered]@{ Name = "qfu_active"; Label = "Active" },
                    [ordered]@{ Name = "qfu_verifiedby"; Label = "Verified By" },
                    [ordered]@{ Name = "qfu_verifiedon"; Label = "Verified On" },
                    [ordered]@{ Name = "qfu_notes"; Label = "Notes" }
                ) }
            )
        }
        qfu_policy = [ordered]@{
            DisplayName = "Branch Policy"
            Sections    = @(
                [ordered]@{ Label = "Policy"; Fields = @(
                    [ordered]@{ Name = "qfu_name"; Label = "Policy Name" },
                    [ordered]@{ Name = "qfu_branch"; Label = "Branch" },
                    [ordered]@{ Name = "qfu_scopekey"; Label = "Scope Key" },
                    [ordered]@{ Name = "qfu_worktype"; Label = "Work Type" },
                    [ordered]@{ Name = "qfu_highvaluethreshold"; Label = "High-Value Threshold" },
                    [ordered]@{ Name = "qfu_thresholdoperator"; Label = "Threshold Operator" },
                    [ordered]@{ Name = "qfu_workitemgenerationmode"; Label = "Work Item Generation Mode" },
                    [ordered]@{ Name = "qfu_requiredattempts"; Label = "Required Attempts" },
                    [ordered]@{ Name = "qfu_firstfollowupbasis"; Label = "First Follow-Up Basis" },
                    [ordered]@{ Name = "qfu_firstfollowupbusinessdays"; Label = "First Follow-Up Business Days" },
                    [ordered]@{ Name = "qfu_primaryownerstrategy"; Label = "Primary Owner Strategy" },
                    [ordered]@{ Name = "qfu_supportownerstrategy"; Label = "Support Owner Strategy" },
                    [ordered]@{ Name = "qfu_gmccmode"; Label = "GM CC Mode" },
                    [ordered]@{ Name = "qfu_managerccmode"; Label = "Manager CC Mode" },
                    [ordered]@{ Name = "qfu_cssralertmode"; Label = "CSSR Alert Mode" },
                    [ordered]@{ Name = "qfu_escalateafterbusinessdays"; Label = "Escalate After Business Days" },
                    [ordered]@{ Name = "qfu_digestenabled"; Label = "Digest Enabled" },
                    [ordered]@{ Name = "qfu_targetedalertenabled"; Label = "Targeted Alert Enabled" },
                    [ordered]@{ Name = "qfu_active"; Label = "Active" }
                ) }
            )
        }
        qfu_assignmentexception = [ordered]@{
            DisplayName = "Assignment Exception"
            Sections    = @(
                [ordered]@{ Label = "Exception"; Fields = @(
                    [ordered]@{ Name = "qfu_exceptiontype"; Label = "Exception Type" },
                    [ordered]@{ Name = "qfu_branch"; Label = "Branch" },
                    [ordered]@{ Name = "qfu_sourcesystem"; Label = "Source System" },
                    [ordered]@{ Name = "qfu_sourcefield"; Label = "Source Field" },
                    [ordered]@{ Name = "qfu_rawvalue"; Label = "Raw Value" },
                    [ordered]@{ Name = "qfu_normalizedvalue"; Label = "Normalized Value" },
                    [ordered]@{ Name = "qfu_displayname"; Label = "Display Name" },
                    [ordered]@{ Name = "qfu_sourcedocumentnumber"; Label = "Source Document Number" },
                    [ordered]@{ Name = "qfu_sourceexternalkey"; Label = "Source External Key" },
                    [ordered]@{ Name = "qfu_sourcequote"; Label = "Source Quote" },
                    [ordered]@{ Name = "qfu_sourcequoteline"; Label = "Source Quote Line" },
                    [ordered]@{ Name = "qfu_sourcebackorder"; Label = "Source Backorder" },
                    [ordered]@{ Name = "qfu_workitem"; Label = "Work Item" },
                    [ordered]@{ Name = "qfu_status"; Label = "Status" },
                    [ordered]@{ Name = "qfu_resolvedstaff"; Label = "Resolved Staff" },
                    [ordered]@{ Name = "qfu_resolvedby"; Label = "Resolved By" },
                    [ordered]@{ Name = "qfu_resolvedon"; Label = "Resolved On" },
                    [ordered]@{ Name = "qfu_notes"; Label = "Notes" }
                ) }
            )
        }
        qfu_workitem = [ordered]@{
            DisplayName = "Work Item"
            Sections    = @(
                [ordered]@{ Label = "Follow-Up Priority"; Fields = @(
                    [ordered]@{ Name = "qfu_workitemnumber"; Label = "Work Item Number" },
                    [ordered]@{ Name = "qfu_worktype"; Label = "Work Type" },
                    [ordered]@{ Name = "qfu_sourcesystem"; Label = "Source System" },
                    [ordered]@{ Name = "qfu_branch"; Label = "Branch" },
                    [ordered]@{ Name = "qfu_sourcedocumentnumber"; Label = "Source Document Number" },
                    [ordered]@{ Name = "qfu_stickynote"; Label = "Sticky Note" },
                    [ordered]@{ Name = "qfu_stickynoteupdatedon"; Label = "Sticky Note Updated On" },
                    [ordered]@{ Name = "qfu_stickynoteupdatedby"; Label = "Sticky Note Updated By" },
                    [ordered]@{ Name = "qfu_customername"; Label = "Customer Name" },
                    [ordered]@{ Name = "qfu_totalvalue"; Label = "Total Value" },
                    [ordered]@{ Name = "qfu_primaryownerstaff"; Label = "Primary Owner Staff" },
                    [ordered]@{ Name = "qfu_supportownerstaff"; Label = "Support Owner Staff" },
                    [ordered]@{ Name = "qfu_tsrstaff"; Label = "TSR Staff" },
                    [ordered]@{ Name = "qfu_cssrstaff"; Label = "CSSR Staff" },
                    [ordered]@{ Name = "qfu_requiredattempts"; Label = "Required Attempts" },
                    [ordered]@{ Name = "qfu_completedattempts"; Label = "Completed Attempts" },
                    [ordered]@{ Name = "qfu_status"; Label = "Status" },
                    [ordered]@{ Name = "qfu_priority"; Label = "Priority" },
                    [ordered]@{ Name = "qfu_nextfollowupon"; Label = "Next Follow-Up On" },
                    [ordered]@{ Name = "qfu_lastfollowedupon"; Label = "Last Followed Up On" },
                    [ordered]@{ Name = "qfu_lastactionon"; Label = "Last Action On" },
                    [ordered]@{ Name = "qfu_overduesince"; Label = "Overdue Since" },
                    [ordered]@{ Name = "qfu_escalationlevel"; Label = "Escalation Level" },
                    [ordered]@{ Name = "qfu_policy"; Label = "Policy" },
                    [ordered]@{ Name = "qfu_assignmentstatus"; Label = "Assignment Status" },
                    [ordered]@{ Name = "qfu_notes"; Label = "Notes" }
                ) }
            )
        }
        qfu_workitemaction = [ordered]@{
            DisplayName = "Work Item Action"
            Sections    = @(
                [ordered]@{ Label = "Action"; Fields = @(
                    [ordered]@{ Name = "qfu_workitem"; Label = "Work Item" },
                    [ordered]@{ Name = "qfu_actiontype"; Label = "Action Type" },
                    [ordered]@{ Name = "qfu_countsasattempt"; Label = "Counts As Attempt" },
                    [ordered]@{ Name = "qfu_actionby"; Label = "Action By" },
                    [ordered]@{ Name = "qfu_actionon"; Label = "Action On" },
                    [ordered]@{ Name = "qfu_attemptnumber"; Label = "Attempt Number" },
                    [ordered]@{ Name = "qfu_outcome"; Label = "Outcome" },
                    [ordered]@{ Name = "qfu_nextfollowupon"; Label = "Next Follow-Up On" },
                    [ordered]@{ Name = "qfu_relatedalert"; Label = "Related Alert" },
                    [ordered]@{ Name = "qfu_notes"; Label = "Notes" }
                ) }
            )
        }
        qfu_alertlog = [ordered]@{
            DisplayName = "Alert Log"
            Sections    = @(
                [ordered]@{ Label = "Alert"; Fields = @(
                    [ordered]@{ Name = "qfu_workitem"; Label = "Work Item" },
                    [ordered]@{ Name = "qfu_alerttype"; Label = "Alert Type" },
                    [ordered]@{ Name = "qfu_recipientstaff"; Label = "Recipient Staff" },
                    [ordered]@{ Name = "qfu_recipientemail"; Label = "Recipient Email" },
                    [ordered]@{ Name = "qfu_ccemails"; Label = "CC Emails" },
                    [ordered]@{ Name = "qfu_dedupekey"; Label = "Dedupe Key" },
                    [ordered]@{ Name = "qfu_status"; Label = "Status" },
                    [ordered]@{ Name = "qfu_senton"; Label = "Sent On" },
                    [ordered]@{ Name = "qfu_failuremessage"; Label = "Failure Message" },
                    [ordered]@{ Name = "qfu_flowrunid"; Label = "Flow Run ID" },
                    [ordered]@{ Name = "qfu_notes"; Label = "Notes" }
                ) }
            )
        }
    }

    foreach ($table in $forms.Keys) {
        $result.forms += Ensure-AdminForm -Table $table -DisplayName $forms[$table].DisplayName -Sections $forms[$table].Sections
    }

    $viewSpecs = @(
        [ordered]@{ Table = "qfu_staff"; Name = "Active Staff"; Columns = @("qfu_name", "qfu_primaryemail", "qfu_staffnumber", "qfu_systemuser", "qfu_defaultbranch", "qfu_active"); Filter = New-ConditionFilter @((Condition "statecode" "eq" 0), (Condition "qfu_active" "eq" 1)); Order = "qfu_name" },
        [ordered]@{ Table = "qfu_staff"; Name = "Staff Missing Email"; Columns = @("qfu_name", "qfu_staffnumber", "qfu_primaryemail", "qfu_defaultbranch", "qfu_active"); Filter = New-ConditionFilter @((Condition "statecode" "eq" 0), (Condition "qfu_primaryemail" "null")); Order = "qfu_name" },
        [ordered]@{ Table = "qfu_staff"; Name = "Staff Missing Dataverse User"; Columns = @("qfu_name", "qfu_staffnumber", "qfu_systemuser", "qfu_defaultbranch", "qfu_active"); Filter = New-ConditionFilter @((Condition "statecode" "eq" 0), (Condition "qfu_systemuser" "null")); Order = "qfu_name" },

        [ordered]@{ Table = "qfu_branchmembership"; Name = "Active Branch Memberships"; Columns = @("qfu_branch", "qfu_staff", "qfu_role", "qfu_isprimary", "qfu_startdate", "qfu_enddate", "qfu_active"); Filter = New-ConditionFilter @((Condition "statecode" "eq" 0), (Condition "qfu_active" "eq" 1)); Order = "qfu_branch" },
        [ordered]@{ Table = "qfu_branchmembership"; Name = "Memberships by Branch"; Columns = @("qfu_branch", "qfu_staff", "qfu_role", "qfu_isprimary", "qfu_active"); Filter = New-ConditionFilter @((Condition "statecode" "eq" 0)); Order = "qfu_branch" },
        [ordered]@{ Table = "qfu_branchmembership"; Name = "Memberships by Role"; Columns = @("qfu_role", "qfu_staff", "qfu_branch", "qfu_isprimary", "qfu_active"); Filter = New-ConditionFilter @((Condition "statecode" "eq" 0)); Order = "qfu_role" },

        [ordered]@{ Table = "qfu_staffalias"; Name = "Active Aliases"; Columns = @("qfu_sourcesystem", "qfu_aliastype", "qfu_rawalias", "qfu_normalizedalias", "qfu_rolehint", "qfu_branch", "qfu_staff", "qfu_active"); Filter = New-ConditionFilter @((Condition "statecode" "eq" 0), (Condition "qfu_active" "eq" 1)); Order = "qfu_rawalias" },
        [ordered]@{ Table = "qfu_staffalias"; Name = "Unverified Aliases"; Columns = @("qfu_sourcesystem", "qfu_rawalias", "qfu_normalizedalias", "qfu_rolehint", "qfu_branch", "qfu_staff", "qfu_verifiedon"); Filter = New-ConditionFilter @((Condition "statecode" "eq" 0), (Condition "qfu_verifiedon" "null")); Order = "qfu_rawalias" },
        [ordered]@{ Table = "qfu_staffalias"; Name = "Aliases by Source System"; Columns = @("qfu_sourcesystem", "qfu_aliastype", "qfu_rawalias", "qfu_normalizedalias", "qfu_rolehint", "qfu_staff"); Filter = New-ConditionFilter @((Condition "statecode" "eq" 0)); Order = "qfu_sourcesystem" },
        [ordered]@{ Table = "qfu_staffalias"; Name = "Potential Duplicate Aliases"; Columns = @("qfu_normalizedalias", "qfu_rawalias", "qfu_sourcesystem", "qfu_aliastype", "qfu_branch", "qfu_staff", "qfu_active"); Filter = New-ConditionFilter @((Condition "statecode" "eq" 0), (Condition "qfu_normalizedalias" "not-null")); Order = "qfu_normalizedalias" },

        [ordered]@{ Table = "qfu_policy"; Name = "Active Policies"; Columns = @("qfu_name", "qfu_branch", "qfu_scopekey", "qfu_worktype", "qfu_highvaluethreshold", "qfu_thresholdoperator", "qfu_requiredattempts", "qfu_active"); Filter = New-ConditionFilter @((Condition "statecode" "eq" 0), (Condition "qfu_active" "eq" 1)); Order = "qfu_name" },
        [ordered]@{ Table = "qfu_policy"; Name = "Draft/Inactive Policies"; Columns = @("qfu_name", "qfu_branch", "qfu_scopekey", "qfu_worktype", "qfu_active"); Filter = New-ConditionFilter @((Condition "qfu_active" "eq" 0)); Order = "qfu_name" },
        [ordered]@{ Table = "qfu_policy"; Name = "Policies by Branch"; Columns = @("qfu_branch", "qfu_name", "qfu_scopekey", "qfu_worktype", "qfu_highvaluethreshold", "qfu_requiredattempts", "qfu_active"); Filter = New-ConditionFilter @((Condition "statecode" "eq" 0)); Order = "qfu_branch" },
        [ordered]@{ Table = "qfu_policy"; Name = "Quote Policies"; Columns = @("qfu_name", "qfu_branch", "qfu_scopekey", "qfu_highvaluethreshold", "qfu_thresholdoperator", "qfu_requiredattempts", "qfu_firstfollowupbasis", "qfu_firstfollowupbusinessdays", "qfu_active"); Filter = New-ConditionFilter @((Condition "statecode" "eq" 0), (Condition "qfu_worktype" "eq" $workTypeQuote)); Order = "qfu_name" },

        [ordered]@{ Table = "qfu_assignmentexception"; Name = "Open Assignment Exceptions"; Columns = @("qfu_exceptiontype", "qfu_branch", "qfu_sourcesystem", "qfu_rawvalue", "qfu_normalizedvalue", "qfu_sourcedocumentnumber", "qfu_status", "qfu_workitem"); Filter = New-ConditionFilter @((Condition "statecode" "eq" 0), (Condition "qfu_status" "eq" $exceptionOpen)); Order = "qfu_sourcedocumentnumber" },
        [ordered]@{ Table = "qfu_assignmentexception"; Name = "Missing TSR Alias"; Columns = @("qfu_branch", "qfu_sourcesystem", "qfu_rawvalue", "qfu_normalizedvalue", "qfu_sourcedocumentnumber", "qfu_status"); Filter = New-ConditionFilter @((Condition "qfu_exceptiontype" "eq" $missingTsrAlias), (Condition "qfu_status" "eq" $exceptionOpen)); Order = "qfu_rawvalue" },
        [ordered]@{ Table = "qfu_assignmentexception"; Name = "Missing CSSR Alias"; Columns = @("qfu_branch", "qfu_sourcesystem", "qfu_rawvalue", "qfu_normalizedvalue", "qfu_sourcedocumentnumber", "qfu_status"); Filter = New-ConditionFilter @((Condition "qfu_exceptiontype" "eq" $missingCssrAlias), (Condition "qfu_status" "eq" $exceptionOpen)); Order = "qfu_rawvalue" },
        [ordered]@{ Table = "qfu_assignmentexception"; Name = "Blank/Zero Alias Exceptions"; Columns = @("qfu_exceptiontype", "qfu_branch", "qfu_sourcesystem", "qfu_sourcefield", "qfu_rawvalue", "qfu_sourcedocumentnumber", "qfu_status"); Filter = "<filter type=`"and`"><filter type=`"or`">$(Condition "qfu_exceptiontype" "eq" $blankAlias)$(Condition "qfu_exceptiontype" "eq" $zeroAlias)</filter>$(Condition "qfu_status" "eq" $exceptionOpen)</filter>"; Order = "qfu_sourcedocumentnumber" },
        [ordered]@{ Table = "qfu_assignmentexception"; Name = "Resolved Exceptions"; Columns = @("qfu_exceptiontype", "qfu_branch", "qfu_rawvalue", "qfu_resolvedstaff", "qfu_resolvedby", "qfu_resolvedon", "qfu_status"); Filter = New-ConditionFilter @((Condition "qfu_status" "eq" $exceptionResolved)); Order = "qfu_resolvedon" },

        [ordered]@{ Table = "qfu_workitem"; Name = "Open Work Items"; Columns = @("qfu_workitemnumber", "qfu_worktype", "qfu_branch", "qfu_customername", "qfu_totalvalue", "qfu_primaryownerstaff", "qfu_supportownerstaff", "qfu_completedattempts", "qfu_requiredattempts", "qfu_nextfollowupon", "qfu_status", "qfu_assignmentstatus"); Filter = New-ConditionFilter @((Condition "statecode" "eq" 0), (Condition "qfu_status" "eq" $workOpen)); Order = "qfu_nextfollowupon" },
        [ordered]@{ Table = "qfu_workitem"; Name = "Needs TSR Assignment"; Columns = @("qfu_workitemnumber", "qfu_branch", "qfu_customername", "qfu_totalvalue", "qfu_tsrstaff", "qfu_assignmentstatus", "qfu_nextfollowupon"); Filter = New-ConditionFilter @((Condition "statecode" "eq" 0), (Condition "qfu_assignmentstatus" "eq" $needsTsr)); Order = "qfu_nextfollowupon" },
        [ordered]@{ Table = "qfu_workitem"; Name = "Needs CSSR Assignment"; Columns = @("qfu_workitemnumber", "qfu_branch", "qfu_customername", "qfu_totalvalue", "qfu_cssrstaff", "qfu_assignmentstatus", "qfu_nextfollowupon"); Filter = New-ConditionFilter @((Condition "statecode" "eq" 0), (Condition "qfu_assignmentstatus" "eq" $needsCssr)); Order = "qfu_nextfollowupon" },
        [ordered]@{ Table = "qfu_workitem"; Name = "Quotes >= `$3K"; Columns = @("qfu_workitemnumber", "qfu_branch", "qfu_customername", "qfu_totalvalue", "qfu_primaryownerstaff", "qfu_completedattempts", "qfu_requiredattempts", "qfu_lastfollowedupon", "qfu_status"); Filter = New-ConditionFilter @((Condition "statecode" "eq" 0), (Condition "qfu_worktype" "eq" $workTypeQuote), (Condition "qfu_totalvalue" "ge" 3000)); Order = "qfu_totalvalue" },
        [ordered]@{ Table = "qfu_workitem"; Name = "Overdue Work Items"; Columns = @("qfu_workitemnumber", "qfu_branch", "qfu_customername", "qfu_totalvalue", "qfu_primaryownerstaff", "qfu_overduesince", "qfu_nextfollowupon", "qfu_status"); Filter = New-ConditionFilter @((Condition "statecode" "eq" 0), (Condition "qfu_overduesince" "not-null")); Order = "qfu_overduesince" },
        [ordered]@{ Table = "qfu_workitem"; Name = "Work Items with Sticky Notes"; Columns = @("qfu_workitemnumber", "qfu_branch", "qfu_customername", "qfu_stickynote", "qfu_stickynoteupdatedon", "qfu_stickynoteupdatedby", "qfu_status"); Filter = New-ConditionFilter @((Condition "statecode" "eq" 0), (Condition "qfu_stickynote" "not-null")); Order = "qfu_stickynoteupdatedon" },

        [ordered]@{ Table = "qfu_workitemaction"; Name = "Recent Actions"; Columns = @("qfu_workitem", "qfu_actiontype", "qfu_countsasattempt", "qfu_actionby", "qfu_actionon", "qfu_attemptnumber", "qfu_outcome", "qfu_nextfollowupon"); Filter = New-ConditionFilter @((Condition "statecode" "eq" 0)); Order = "qfu_actionon" },
        [ordered]@{ Table = "qfu_workitemaction"; Name = "Attempt Actions"; Columns = @("qfu_workitem", "qfu_actiontype", "qfu_countsasattempt", "qfu_actionby", "qfu_actionon", "qfu_attemptnumber", "qfu_outcome"); Filter = New-ConditionFilter @((Condition "qfu_countsasattempt" "eq" 1)); Order = "qfu_actionon" },
        [ordered]@{ Table = "qfu_workitemaction"; Name = "Non-Attempt Actions"; Columns = @("qfu_workitem", "qfu_actiontype", "qfu_countsasattempt", "qfu_actionby", "qfu_actionon", "qfu_outcome"); Filter = New-ConditionFilter @((Condition "qfu_countsasattempt" "eq" 0)); Order = "qfu_actionon" },

        [ordered]@{ Table = "qfu_alertlog"; Name = "Pending Alerts"; Columns = @("qfu_workitem", "qfu_alerttype", "qfu_recipientstaff", "qfu_recipientemail", "qfu_ccemails", "qfu_dedupekey", "qfu_status"); Filter = New-ConditionFilter @((Condition "qfu_status" "eq" $alertPending)); Order = "qfu_recipientemail" },
        [ordered]@{ Table = "qfu_alertlog"; Name = "Failed Alerts"; Columns = @("qfu_workitem", "qfu_alerttype", "qfu_recipientemail", "qfu_status", "qfu_failuremessage", "qfu_flowrunid"); Filter = New-ConditionFilter @((Condition "qfu_status" "eq" $alertFailed)); Order = "qfu_recipientemail" },
        [ordered]@{ Table = "qfu_alertlog"; Name = "Sent Alerts"; Columns = @("qfu_workitem", "qfu_alerttype", "qfu_recipientemail", "qfu_ccemails", "qfu_status", "qfu_senton"); Filter = New-ConditionFilter @((Condition "qfu_status" "eq" $alertSent)); Order = "qfu_senton" },
        [ordered]@{ Table = "qfu_alertlog"; Name = "Suppressed/Skipped Alerts"; Columns = @("qfu_workitem", "qfu_alerttype", "qfu_recipientemail", "qfu_status", "qfu_dedupekey"); Filter = "<filter type=`"and`"><filter type=`"or`">$(Condition "qfu_status" "eq" $alertSuppressed)$(Condition "qfu_status" "eq" $alertSkipped)</filter></filter>"; Order = "qfu_recipientemail" }
    )

    foreach ($viewSpec in $viewSpecs) {
        $result.views += Ensure-View -Table $viewSpec.Table -EntityMetadata $metadata[$viewSpec.Table] -ViewName $viewSpec.Name -Columns $viewSpec.Columns -FilterXml $viewSpec.Filter -OrderColumn $viewSpec.Order
    }

    $result.sitemap = Ensure-SiteMap -NavItems $navItems
    $result.webResource = Ensure-AppIconWebResource
    $appResult = Ensure-AppModule -WebResourceId $result.webResource.webresourceid -PublisherId $publisherId
    $result.app = [ordered]@{
        appmoduleid       = $appResult.app.appmoduleid
        appmoduleidunique = $appResult.app.appmoduleidunique
        name              = $appResult.app.name
        uniquename        = $appResult.app.uniquename
        created           = $appResult.created
    }

    $components = @()
    $components += @{ "@odata.type" = "Microsoft.Dynamics.CRM.sitemap"; sitemapid = $result.sitemap.sitemapid }
    foreach ($form in $result.forms) {
        $components += @{ "@odata.type" = "Microsoft.Dynamics.CRM.systemform"; formid = $form.formid }
    }
    foreach ($view in $result.views) {
        $components += @{ "@odata.type" = "Microsoft.Dynamics.CRM.savedquery"; savedqueryid = $view.savedqueryid }
    }

    try {
        Try-AddAppComponentsAction -AppId $result.app.appmoduleid -Components $components
        $result.appComponentsMethod = "AddAppComponents"
    }
    catch {
        $result.warnings += "AddAppComponents failed: $($_.Exception.Message). Attempting direct appmodulecomponent rows."
        $result.appComponentsMethod = "direct-appmodulecomponent"
        $componentRefs = @()
        $componentRefs += [ordered]@{ objectid = $result.sitemap.sitemapid; type = 62 }
        foreach ($item in $navItems) {
            $componentRefs += [ordered]@{ objectid = $metadata[$item.Table].MetadataId; type = 1 }
        }
        foreach ($form in $result.forms) {
            $componentRefs += [ordered]@{ objectid = $form.formid; type = 60 }
        }
        foreach ($view in $result.views) {
            $componentRefs += [ordered]@{ objectid = $view.savedqueryid; type = 26 }
        }
        foreach ($component in $componentRefs) {
            $componentId = Ensure-AppModuleComponentDirect -AppModuleId $result.app.appmoduleid -ObjectId $component.objectid -ComponentType $component.type
            $result.directComponents += [ordered]@{
                appmodulecomponentid = $componentId
                objectid             = $component.objectid
                componenttype        = $component.type
            }
        }
    }

    $toAdd = @(
        [ordered]@{ component = $result.app.appmoduleid; type = "80"; label = "appmodule" },
        [ordered]@{ component = $result.webResource.webresourceid; type = "61"; label = "app icon webresource" },
        [ordered]@{ component = $result.sitemap.sitemapid; type = "62"; label = "sitemap" }
    )
    foreach ($form in $result.forms) {
        $toAdd += [ordered]@{ component = $form.formid; type = "60"; label = "form $($form.table)" }
    }
    foreach ($view in $result.views) {
        $toAdd += [ordered]@{ component = $view.savedqueryid; type = "26"; label = "view $($view.name)" }
    }

    foreach ($component in $toAdd) {
        $pacResult = Invoke-Pac -Arguments @("solution", "add-solution-component", "--environment", $EnvironmentUrl.TrimEnd("/"), "--solutionUniqueName", $SolutionUniqueName, "--component", $component.component, "--componentType", $component.type, "--AddRequiredComponents")
        $pacResult.label = $component.label
        $result.pacAddComponent += $pacResult
        if ($pacResult.exitCode -ne 0 -and $pacResult.output -notmatch "already") {
            $result.warnings += "pac add-solution-component warning for $($component.label): $($pacResult.output)"
        }
    }

    $publish = Invoke-Pac -Arguments @("solution", "publish", "--environment", $EnvironmentUrl.TrimEnd("/"))
    $result.publish = $publish
    if ($publish.exitCode -ne 0) {
        throw "Publish failed: $($publish.output)"
    }

    Publish-AppModule -AppId $result.app.appmoduleid

    $validated = Invoke-DvOrNull -Path "ValidateApp(AppModuleId=$($result.app.appmoduleid))"
    $result.validateApp = $validated
    $retrieved = Invoke-DvOrNull -Path "RetrieveAppComponents(AppModuleId=$($result.app.appmoduleid))"
    if ($retrieved -and $retrieved.value) {
        $result.retrieveComponents = $retrieved.value
    }
}
catch {
    $detail = $_.Exception.Message
    if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
        $detail = "$detail $($_.ErrorDetails.Message)"
    }
    $result.errors += $detail
}

$resultDir = Split-Path -Parent $ResultPath
if ($resultDir -and -not (Test-Path -LiteralPath $resultDir)) {
    New-Item -ItemType Directory -Path $resultDir -Force | Out-Null
}

$json = $result | ConvertTo-Json -Depth 100
[System.IO.File]::WriteAllText((Resolve-Path -LiteralPath $resultDir).Path + "\" + (Split-Path -Leaf $ResultPath), $json, [System.Text.UTF8Encoding]::new($false))

$summary = [ordered]@{
    environmentUrl      = $result.environmentUrl
    solutionFound       = $result.solutionFound
    appId               = if ($result.app) { $result.app.appmoduleid } else { $null }
    appUniqueName       = if ($result.app) { $result.app.uniquename } else { $null }
    formsTouched        = @($result.forms).Count
    viewsTouched        = @($result.views).Count
    appComponentsMethod = $result.appComponentsMethod
    published           = if ($result.publish) { $result.publish.exitCode -eq 0 } else { $false }
    errors              = $result.errors
    warnings            = $result.warnings
    resultPath          = $ResultPath
}

$summary | ConvertTo-Json -Depth 20
