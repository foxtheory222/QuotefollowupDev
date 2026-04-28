param(
    [string]$EnvironmentUrl = "https://orga632edd5.crm3.dynamics.com/",
    [string]$SolutionUniqueName = "qfu_revenuefollowupworkbench",
    [string]$OutputDirectory = "results/phase3-2A-revised"
)

$ErrorActionPreference = "Stop"

Import-Module Az.Accounts -ErrorAction Stop

if (-not $EnvironmentUrl.EndsWith("/")) {
    $EnvironmentUrl = "$EnvironmentUrl/"
}

$sourceSystemLabel = "SP830CA"
$staffNote = "source-generated provisional staff from SP830CA Phase 3.2A revised"
$aliasNote = "source-generated provisional alias from SP830CA Phase 3.2A revised"
$membershipNote = "source-generated provisional branch membership from SP830CA Phase 3.2A revised"

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

function Invoke-DvAll {
    param([Parameter(Mandatory = $true)][string]$Path)

    $items = New-Object System.Collections.ArrayList
    $uri = "$($EnvironmentUrl)api/data/v9.2/$Path"
    $headers = Get-Headers

    while ($uri) {
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -ErrorAction Stop
        if ($response.value) {
            foreach ($item in @($response.value)) {
                [void]$items.Add($item)
            }
        }
        $uri = $response.'@odata.nextLink'
    }

    return @($items)
}

function Get-First {
    param([object]$Response)

    if ($Response -and $null -ne $Response.value) {
        $values = @($Response.value)
        if ($values.Count -gt 0) {
            return $values[0]
        }
    }

    return $null
}

function Get-EntitySetName {
    param([Parameter(Mandatory = $true)][string]$LogicalName)

    $metadata = Invoke-Dv -Method Get -Path "EntityDefinitions(LogicalName='$LogicalName')?`$select=EntitySetName"
    return $metadata.EntitySetName
}

function Get-OptionValue {
    param(
        [Parameter(Mandatory = $true)][string]$ChoiceName,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $choice = Invoke-Dv -Method Get -Path "GlobalOptionSetDefinitions(Name='$ChoiceName')"
    foreach ($option in $choice.Options) {
        $localized = $option.Label.UserLocalizedLabel.Label
        if ($localized -eq $Label) {
            return [int]$option.Value
        }
    }

    throw "Choice option not found: $ChoiceName / $Label"
}

function Get-KeyBySchemaName {
    param(
        [Parameter(Mandatory = $true)][string]$Table,
        [Parameter(Mandatory = $true)][string]$KeyName
    )

    $keys = Invoke-DvOrNull -Path "EntityDefinitions(LogicalName='$Table')/Keys?`$select=SchemaName,KeyAttributes,EntityKeyIndexStatus"
    if (-not $keys) { return $null }

    foreach ($key in $keys.value) {
        if ($key.SchemaName -eq $KeyName) {
            return $key
        }
    }

    return $null
}

function Normalize-QfuAlias {
    param([AllowNull()][object]$RawAlias)

    if ($null -eq $RawAlias) {
        return [ordered]@{ raw = $null; normalized = ""; isValid = $false; reason = "Blank" }
    }

    $rawText = ([string]$RawAlias).Trim()
    if ($rawText.Length -eq 0) {
        return [ordered]@{ raw = $rawText; normalized = ""; isValid = $false; reason = "Blank" }
    }

    $normalized = $rawText
    if ($rawText -match '^[+-]?\d+\.0+$') {
        $normalized = $rawText -replace '\.0+$', ''
    }
    elseif ($rawText -notmatch '^\d+$') {
        $normalized = $rawText.ToUpperInvariant()
    }

    $invalidTokens = @("", "0", "00000000", "NULL", "N/A", "NA", "NONE")
    $upper = $normalized.ToUpperInvariant()
    if ($invalidTokens -contains $upper) {
        $reason = if ($upper -eq "0" -or $upper -eq "00000000") { "Zero" } else { "Blank" }
        return [ordered]@{ raw = $rawText; normalized = $normalized; isValid = $false; reason = $reason }
    }

    return [ordered]@{ raw = $rawText; normalized = $normalized; isValid = $true; reason = "" }
}

function Normalize-DisplayName {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return "" }
    $text = ([string]$Value).Trim()
    if ($text.Length -eq 0) { return "" }
    $text = [regex]::Replace($text, '\s+', ' ')
    return $text.ToUpperInvariant()
}

function Format-DisplayName {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return "" }
    $text = ([string]$Value).Trim()
    if ($text.Length -eq 0) { return "" }
    return [regex]::Replace($text, '\s+', ' ')
}

function Get-BranchKey {
    param(
        [AllowNull()][string]$BranchCode,
        [AllowNull()][string]$BranchSlug
    )

    if (-not [string]::IsNullOrWhiteSpace($BranchCode)) { return $BranchCode.Trim() }
    if (-not [string]::IsNullOrWhiteSpace($BranchSlug)) { return $BranchSlug.Trim() }
    return "UNKNOWN"
}

function Join-MapKeys {
    param([hashtable]$Map)

    if (-not $Map) { return "" }
    return (@($Map.Keys) | Sort-Object) -join "|"
}

function New-Candidate {
    param([string]$NormalizedAlias)

    return [ordered]@{
        normalizedAlias = $NormalizedAlias
        rawAliases      = @{}
        names           = @{}
        roles           = @{}
        branches        = @{}
        roleBranches    = @{}
        occurrences     = 0
    }
}

function Add-CandidateObservation {
    param(
        [hashtable]$CandidateByNumber,
        [object]$Line,
        [string]$RoleLabel,
        [string]$AliasTypeLabel,
        [string]$NumberField,
        [string]$NameField
    )

    $normalized = Normalize-QfuAlias -RawAlias $Line.$NumberField
    $branchCode = if ($Line.qfu_branchcode) { ([string]$Line.qfu_branchcode).Trim() } else { "" }
    $branchSlug = if ($Line.qfu_branchslug) { ([string]$Line.qfu_branchslug).Trim() } else { "" }
    $displayName = Format-DisplayName -Value $Line.$NameField

    if (-not $normalized.isValid) {
        return [ordered]@{
            isValid         = $false
            source_system   = $sourceSystemLabel
            alias_type      = $AliasTypeLabel
            raw_value       = if ($null -eq $normalized.raw -or [string]::IsNullOrWhiteSpace([string]$normalized.raw)) { "BLANK" } else { [string]$normalized.raw }
            normalized_value = if ([string]::IsNullOrWhiteSpace([string]$normalized.normalized)) { "BLANK" } else { [string]$normalized.normalized }
            reason          = $normalized.reason
            branch_code     = $branchCode
            branch_slug     = $branchSlug
        }
    }

    $norm = [string]$normalized.normalized
    if (-not $CandidateByNumber.ContainsKey($norm)) {
        $CandidateByNumber[$norm] = New-Candidate -NormalizedAlias $norm
    }

    $candidate = $CandidateByNumber[$norm]
    $candidate["occurrences"] = [int]$candidate["occurrences"] + 1
    $candidate["rawAliases"][[string]$normalized.raw] = $true
    $candidate["roles"][$RoleLabel] = $true

    $displayNorm = Normalize-DisplayName -Value $displayName
    if (-not [string]::IsNullOrWhiteSpace($displayNorm)) {
        $candidate["names"][$displayNorm] = $displayName
    }

    $branchKey = Get-BranchKey -BranchCode $branchCode -BranchSlug $branchSlug
    $candidate["branches"][$branchKey] = [ordered]@{
        branchCode = $branchCode
        branchSlug = $branchSlug
    }

    $roleBranchKey = "$RoleLabel|$branchKey"
    if (-not $candidate["roleBranches"].ContainsKey($roleBranchKey)) {
        $candidate["roleBranches"][$roleBranchKey] = [ordered]@{
            roleLabel      = $RoleLabel
            aliasTypeLabel = $AliasTypeLabel
            branchCode     = $branchCode
            branchSlug     = $branchSlug
            rawAliases     = @{}
            count          = 0
        }
    }
    $candidate["roleBranches"][$roleBranchKey]["rawAliases"][[string]$normalized.raw] = $true
    $candidate["roleBranches"][$roleBranchKey]["count"] = [int]$candidate["roleBranches"][$roleBranchKey]["count"] + 1

    return [ordered]@{ isValid = $true }
}

function Get-StaffNumberMap {
    param([object[]]$StaffRows)

    $map = @{}
    foreach ($staff in $StaffRows) {
        if ([string]::IsNullOrWhiteSpace([string]$staff.qfu_staffnumber)) { continue }
        $staffNumber = ([string]$staff.qfu_staffnumber).Trim()
        if (-not $map.ContainsKey($staffNumber)) {
            $map[$staffNumber] = New-Object System.Collections.ArrayList
        }
        [void]$map[$staffNumber].Add($staff)
    }
    return $map
}

function Get-AliasKey {
    param(
        [int]$SourceSystem,
        [int]$AliasType,
        [string]$NormalizedAlias,
        [string]$ScopeKey
    )

    return "$SourceSystem|$AliasType|$NormalizedAlias|$ScopeKey"
}

function Get-ActiveAliasMap {
    param([object[]]$AliasRows)

    $map = @{}
    foreach ($alias in $AliasRows) {
        if (-not $alias.qfu_normalizedalias) { continue }
        $scope = if ($alias.qfu_scopekey) { ([string]$alias.qfu_scopekey).Trim() } else { "GLOBAL" }
        $key = Get-AliasKey -SourceSystem ([int]$alias.qfu_sourcesystem) -AliasType ([int]$alias.qfu_aliastype) -NormalizedAlias ([string]$alias.qfu_normalizedalias) -ScopeKey $scope
        if (-not $map.ContainsKey($key)) {
            $map[$key] = New-Object System.Collections.ArrayList
        }
        [void]$map[$key].Add($alias)
    }
    return $map
}

function Get-MembershipKey {
    param(
        [string]$BranchId,
        [string]$StaffId,
        [int]$Role
    )

    return "$BranchId|$StaffId|$Role"
}

function Get-ActiveMembershipMap {
    param([object[]]$MembershipRows)

    $map = @{}
    foreach ($membership in $MembershipRows) {
        $branchId = $membership.'_qfu_branch_value'
        $staffId = $membership.'_qfu_staff_value'
        if (-not $branchId -or -not $staffId -or $null -eq $membership.qfu_role) { continue }
        $key = Get-MembershipKey -BranchId $branchId -StaffId $staffId -Role ([int]$membership.qfu_role)
        if (-not $map.ContainsKey($key)) {
            $map[$key] = New-Object System.Collections.ArrayList
        }
        [void]$map[$key].Add($membership)
    }
    return $map
}

function Get-LiveCounts {
    param(
        [hashtable]$EntitySets,
        [hashtable]$Option
    )

    $filterActive = [System.Uri]::EscapeDataString("statecode eq 0 and qfu_active eq true")
    $activeStaff = @(Invoke-DvAll -Path "$($EntitySets.staff)?`$select=qfu_staffid,qfu_name,qfu_primaryemail,qfu_staffnumber,_qfu_systemuser_value&`$filter=$filterActive")
    $activeAliases = @(Invoke-DvAll -Path "$($EntitySets.staffAlias)?`$select=qfu_staffaliasid,qfu_sourcesystem,qfu_aliastype,qfu_normalizedalias,qfu_scopekey,_qfu_staff_value&`$filter=$filterActive")
    $activeMemberships = @(Invoke-DvAll -Path "$($EntitySets.branchMembership)?`$select=qfu_branchmembershipid,qfu_role,_qfu_branch_value,_qfu_staff_value&`$filter=$filterActive")

    $duplicateGroups = @(
        $activeAliases |
            Group-Object {
                $scope = if ($_.qfu_scopekey) { ([string]$_.qfu_scopekey).Trim() } else { "GLOBAL" }
                "$($_.qfu_sourcesystem)|$($_.qfu_aliastype)|$($_.qfu_normalizedalias)|$scope"
            } |
            Where-Object {
                $_.Count -gt 1 -or @($_.Group | Select-Object -ExpandProperty '_qfu_staff_value' -Unique).Count -gt 1
            }
    )

    return [ordered]@{
        activeStaffRecords       = $activeStaff.Count
        activeStaffAliasRecords  = $activeAliases.Count
        activeAmNumberAliases    = @($activeAliases | Where-Object { [int]$_.qfu_sourcesystem -eq [int]$Option.sp830SourceSystem -and [int]$_.qfu_aliastype -eq [int]$Option.amNumberAliasType }).Count
        activeCssrNumberAliases  = @($activeAliases | Where-Object { [int]$_.qfu_sourcesystem -eq [int]$Option.sp830SourceSystem -and [int]$_.qfu_aliastype -eq [int]$Option.cssrNumberAliasType }).Count
        activeBranchMemberships  = $activeMemberships.Count
        duplicateAliasGroups     = $duplicateGroups.Count
        staffMissingEmail        = @($activeStaff | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.qfu_primaryemail) }).Count
        staffMissingSystemUser   = @($activeStaff | Where-Object { -not $_.'_qfu_systemuser_value' }).Count
    }
}

function Export-ConflictCsv {
    param(
        [System.Collections.ArrayList]$Rows,
        [string]$Path
    )

    if ($Rows.Count -gt 0) {
        $Rows | Export-Csv -Path $Path -NoTypeInformation
        return
    }

    '"conflict_type","normalized_alias","roles","branch_code","details","action_taken"' | Set-Content -Path $Path -Encoding UTF8
}

function Add-Conflict {
    param(
        [System.Collections.ArrayList]$Conflicts,
        [string]$ConflictType,
        [string]$NormalizedAlias,
        [string]$Roles,
        [string]$BranchCode,
        [string]$Details,
        [string]$ActionTaken
    )

    [void]$Conflicts.Add([pscustomobject]@{
        conflict_type    = $ConflictType
        normalized_alias = $NormalizedAlias
        roles            = $Roles
        branch_code      = $BranchCode
        details          = $Details
        action_taken     = $ActionTaken
    })
}

$outputRoot = Join-Path (Get-Location) $OutputDirectory
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

$solution = Get-First (Invoke-Dv -Method Get -Path "solutions?`$select=solutionid,uniquename,friendlyname&`$filter=$([System.Uri]::EscapeDataString("uniquename eq '$SolutionUniqueName'"))")
$app = Get-First (Invoke-Dv -Method Get -Path "appmodules?`$select=appmoduleid,name,uniquename&`$filter=$([System.Uri]::EscapeDataString("name eq 'Revenue Follow-Up Workbench'"))")

$entitySets = [ordered]@{
    staff               = Get-EntitySetName -LogicalName "qfu_staff"
    staffAlias          = Get-EntitySetName -LogicalName "qfu_staffalias"
    branchMembership    = Get-EntitySetName -LogicalName "qfu_branchmembership"
    quote               = Get-EntitySetName -LogicalName "qfu_quote"
    quoteLine           = Get-EntitySetName -LogicalName "qfu_quoteline"
    branch              = Get-EntitySetName -LogicalName "qfu_branch"
    workItem            = Get-EntitySetName -LogicalName "qfu_workitem"
    assignmentException = Get-EntitySetName -LogicalName "qfu_assignmentexception"
}

$option = [ordered]@{
    sp830SourceSystem   = Get-OptionValue -ChoiceName "qfu_sourcesystem" -Label "SP830CA"
    amNumberAliasType   = Get-OptionValue -ChoiceName "qfu_aliastype" -Label "AM Number"
    cssrNumberAliasType = Get-OptionValue -ChoiceName "qfu_aliastype" -Label "CSSR Number"
    tsrRoleHint         = Get-OptionValue -ChoiceName "qfu_rolehint" -Label "TSR"
    cssrRoleHint        = Get-OptionValue -ChoiceName "qfu_rolehint" -Label "CSSR"
    tsrRole             = Get-OptionValue -ChoiceName "qfu_role" -Label "TSR"
    cssrRole            = Get-OptionValue -ChoiceName "qfu_role" -Label "CSSR"
}

$keyChecks = @(
    @{ table = "qfu_staffalias"; keyName = "qfu_key_staffalias_source_type_alias_scope" },
    @{ table = "qfu_branchmembership"; keyName = "qfu_key_branchmembership_branch_staff_role" },
    @{ table = "qfu_policy"; keyName = "qfu_key_policy_scope_worktype_activekey" },
    @{ table = "qfu_workitem"; keyName = "qfu_key_workitem_type_sourcekey" },
    @{ table = "qfu_alertlog"; keyName = "qfu_key_alertlog_dedupekey" },
    @{ table = "qfu_assignmentexception"; keyName = "qfu_key_assignmentexception_sourcekey_type_field_value" }
) | ForEach-Object {
    $key = Get-KeyBySchemaName -Table $_.table -KeyName $_.keyName
    [ordered]@{
        table       = $_.table
        keyName     = $_.keyName
        found       = [bool]$key
        indexStatus = if ($key) { $key.EntityKeyIndexStatus } else { "missing" }
        attributes  = if ($key) { (@($key.KeyAttributes) -join ", ") } else { "" }
    }
}

$filterActiveState = [System.Uri]::EscapeDataString("statecode eq 0")
$staff = Invoke-DvAll -Path "$($entitySets.staff)?`$select=qfu_staffid,qfu_name,qfu_primaryemail,qfu_staffnumber,qfu_notes,_qfu_systemuser_value&`$filter=$filterActiveState"
$staffAliases = Invoke-DvAll -Path "$($entitySets.staffAlias)?`$select=qfu_staffaliasid,qfu_name,qfu_sourcesystem,qfu_aliastype,qfu_rawalias,qfu_normalizedalias,qfu_rolehint,qfu_scopekey,qfu_active,qfu_notes,_qfu_staff_value,_qfu_branch_value&`$filter=$filterActiveState"
$memberships = Invoke-DvAll -Path "$($entitySets.branchMembership)?`$select=qfu_branchmembershipid,qfu_name,qfu_role,qfu_active,qfu_notes,_qfu_branch_value,_qfu_staff_value&`$filter=$filterActiveState"
$branches = Invoke-DvAll -Path "$($entitySets.branch)?`$select=qfu_branchid,qfu_branchcode,qfu_branchslug,qfu_name,qfu_active&`$filter=$filterActiveState"
$quoteCount = (Invoke-DvAll -Path "$($entitySets.quote)?`$select=qfu_quoteid&`$filter=$filterActiveState").Count

$lineSelect = "qfu_quotelineid,qfu_quotenumber,qfu_branchcode,qfu_branchslug,qfu_tsr,qfu_tsrname,qfu_cssr,qfu_cssrname"
$quoteLines = Invoke-DvAll -Path "$($entitySets.quoteLine)?`$select=$lineSelect&`$filter=$filterActiveState"

$preCounts = Get-LiveCounts -EntitySets $entitySets -Option $option

$branchByCode = @{}
$branchBySlug = @{}
foreach ($branch in $branches) {
    if ($branch.qfu_branchcode) { $branchByCode[[string]$branch.qfu_branchcode] = $branch }
    if ($branch.qfu_branchslug) { $branchBySlug[[string]$branch.qfu_branchslug] = $branch }
}

$candidateByNumber = @{}
$invalidObservations = New-Object System.Collections.ArrayList
foreach ($line in $quoteLines) {
    $tsrResult = Add-CandidateObservation -CandidateByNumber $candidateByNumber -Line $line -RoleLabel "TSR" -AliasTypeLabel "AM Number" -NumberField "qfu_tsr" -NameField "qfu_tsrname"
    if (-not $tsrResult.isValid) { [void]$invalidObservations.Add([pscustomobject]$tsrResult) }

    $cssrResult = Add-CandidateObservation -CandidateByNumber $candidateByNumber -Line $line -RoleLabel "CSSR" -AliasTypeLabel "CSSR Number" -NumberField "qfu_cssr" -NameField "qfu_cssrname"
    if (-not $cssrResult.isValid) { [void]$invalidObservations.Add([pscustomobject]$cssrResult) }
}

$conflicts = New-Object System.Collections.ArrayList
$staffRows = New-Object System.Collections.ArrayList
$aliasRows = New-Object System.Collections.ArrayList
$membershipRows = New-Object System.Collections.ArrayList

$staffByNumber = Get-StaffNumberMap -StaffRows $staff
$aliasByKey = Get-ActiveAliasMap -AliasRows $staffAliases
$membershipByKey = Get-ActiveMembershipMap -MembershipRows $memberships

foreach ($number in @($candidateByNumber.Keys | Sort-Object)) {
    $candidate = $candidateByNumber[$number]
    $roles = Join-MapKeys -Map $candidate["roles"]
    $branchesSeen = Join-MapKeys -Map $candidate["branches"]
    $names = @($candidate["names"].Keys)

    if ($names.Count -eq 0) {
        Add-Conflict -Conflicts $conflicts -ConflictType "MissingDisplayName" -NormalizedAlias $number -Roles $roles -BranchCode $branchesSeen -Details "Valid number appeared without a report-provided display name." -ActionTaken "Skipped provisional staff and mappings for this number."
        continue
    }

    if ($names.Count -gt 1) {
        Add-Conflict -Conflicts $conflicts -ConflictType "MultipleNamesForSameNumber" -NormalizedAlias $number -Roles $roles -BranchCode $branchesSeen -Details (@($candidate["names"].Values) -join " | ") -ActionTaken "Skipped provisional staff and mappings for this number."
        continue
    }

    $displayName = @($candidate["names"].Values)[0]
    $existingStaffRows = if ($staffByNumber.ContainsKey($number)) { @($staffByNumber[$number].ToArray()) } else { @() }
    if ($existingStaffRows.Count -gt 1) {
        Add-Conflict -Conflicts $conflicts -ConflictType "DuplicateExistingStaffNumber" -NormalizedAlias $number -Roles $roles -BranchCode $branchesSeen -Details "More than one active qfu_staff record already has qfu_staffnumber $number." -ActionTaken "Skipped provisional updates and mappings for this number."
        continue
    }

    $staffRecord = $null
    $staffAction = "created"
    if ($existingStaffRows.Count -eq 1) {
        $staffRecord = $existingStaffRows[0]
        $existingNameNorm = Normalize-DisplayName -Value $staffRecord.qfu_name
        $sourceNameNorm = Normalize-DisplayName -Value $displayName
        if (-not [string]::IsNullOrWhiteSpace($existingNameNorm) -and $existingNameNorm -ne $sourceNameNorm) {
            Add-Conflict -Conflicts $conflicts -ConflictType "ExistingStaffNameMismatch" -NormalizedAlias $number -Roles $roles -BranchCode $branchesSeen -Details "Existing staff name '$($staffRecord.qfu_name)' differs from source display name '$displayName'." -ActionTaken "Skipped provisional updates and mappings for this number."
            continue
        }

        $patch = [ordered]@{
            qfu_active = $true
        }
        if ([string]::IsNullOrWhiteSpace([string]$staffRecord.qfu_name)) {
            $patch.qfu_name = $displayName
        }
        if ([string]::IsNullOrWhiteSpace([string]$staffRecord.qfu_notes)) {
            $patch.qfu_notes = $staffNote
        }
        Invoke-DvNoContent -Method Patch -Path "$($entitySets.staff)($($staffRecord.qfu_staffid))" -Body $patch -WriteOperation:$true | Out-Null
        $staffId = $staffRecord.qfu_staffid
        $staffAction = "updated"
    }
    else {
        $body = [ordered]@{
            qfu_name        = $displayName
            qfu_staffnumber = $number
            qfu_active      = $true
            qfu_notes       = $staffNote
        }
        $staffRecord = Invoke-Dv -Method Post -Path $entitySets.staff -Body $body -WriteOperation:$true
        $staffId = $staffRecord.qfu_staffid
        $staffByNumber[$number] = New-Object System.Collections.ArrayList
        [void]$staffByNumber[$number].Add($staffRecord)
    }

    [void]$staffRows.Add([pscustomobject]@{
        action            = $staffAction
        qfu_staffid       = $staffId
        qfu_staffnumber   = $number
        qfu_name          = $displayName
        roles_seen        = $roles
        branches_seen     = $branchesSeen
        qfu_notes         = $staffNote
        email_guessed     = "FALSE"
        systemuser_guessed = "FALSE"
        entra_guessed     = "FALSE"
    })

    foreach ($roleBranchKey in @($candidate["roleBranches"].Keys | Sort-Object)) {
        $roleBranch = $candidate["roleBranches"][$roleBranchKey]
        $roleLabel = [string]$roleBranch["roleLabel"]
        $aliasTypeLabel = [string]$roleBranch["aliasTypeLabel"]
        $branchCode = [string]$roleBranch["branchCode"]
        $branchSlug = [string]$roleBranch["branchSlug"]
        $scopeKey = Get-BranchKey -BranchCode $branchCode -BranchSlug $branchSlug

        $branch = $null
        if ($branchCode -and $branchByCode.ContainsKey($branchCode)) {
            $branch = $branchByCode[$branchCode]
        }
        elseif ($branchSlug -and $branchBySlug.ContainsKey($branchSlug)) {
            $branch = $branchBySlug[$branchSlug]
        }

        if (-not $branch) {
            Add-Conflict -Conflicts $conflicts -ConflictType "MissingBranchRecord" -NormalizedAlias $number -Roles $roleLabel -BranchCode $scopeKey -Details "No qfu_branch record was found for the source branch." -ActionTaken "Staff retained if created, but alias and membership were skipped for this branch."
            continue
        }

        $aliasTypeValue = if ($aliasTypeLabel -eq "AM Number") { [int]$option.amNumberAliasType } else { [int]$option.cssrNumberAliasType }
        $roleHintValue = if ($roleLabel -eq "TSR") { [int]$option.tsrRoleHint } else { [int]$option.cssrRoleHint }
        $roleValue = if ($roleLabel -eq "TSR") { [int]$option.tsrRole } else { [int]$option.cssrRole }
        $rawAliasExample = (@($roleBranch["rawAliases"].Keys) | Sort-Object | Select-Object -First 1)

        $aliasKey = Get-AliasKey -SourceSystem ([int]$option.sp830SourceSystem) -AliasType $aliasTypeValue -NormalizedAlias $number -ScopeKey $scopeKey
        $existingAliases = if ($aliasByKey.ContainsKey($aliasKey)) { @($aliasByKey[$aliasKey].ToArray()) } else { @() }
        if ($existingAliases.Count -gt 1) {
            Add-Conflict -Conflicts $conflicts -ConflictType "DuplicateExistingAliasKey" -NormalizedAlias $number -Roles $roleLabel -BranchCode $scopeKey -Details "More than one qfu_staffalias already exists for the same source/type/alias/scope." -ActionTaken "Skipped alias update/create for this scope."
        }
        elseif ($existingAliases.Count -eq 1 -and $existingAliases[0].'_qfu_staff_value' -and $existingAliases[0].'_qfu_staff_value' -ne $staffId) {
            Add-Conflict -Conflicts $conflicts -ConflictType "ExistingAliasMapsDifferentStaff" -NormalizedAlias $number -Roles $roleLabel -BranchCode $scopeKey -Details "Existing alias maps to staff $($existingAliases[0].'_qfu_staff_value'), not $staffId." -ActionTaken "Skipped alias update/create for this scope."
        }
        else {
            $aliasAction = "created"
            if ($existingAliases.Count -eq 1) {
                $aliasPatch = [ordered]@{
                    qfu_active = $true
                }
                if ([string]::IsNullOrWhiteSpace([string]$existingAliases[0].qfu_notes)) {
                    $aliasPatch.qfu_notes = $aliasNote
                }
                Invoke-DvNoContent -Method Patch -Path "$($entitySets.staffAlias)($($existingAliases[0].qfu_staffaliasid))" -Body $aliasPatch -WriteOperation:$true | Out-Null
                $aliasId = $existingAliases[0].qfu_staffaliasid
                $aliasAction = "updated"
            }
            else {
                $aliasBody = [ordered]@{
                    qfu_name            = "$sourceSystemLabel $aliasTypeLabel $number $scopeKey"
                    qfu_sourcesystem    = [int]$option.sp830SourceSystem
                    qfu_aliastype       = $aliasTypeValue
                    qfu_rawalias        = [string]$rawAliasExample
                    qfu_normalizedalias = $number
                    qfu_rolehint        = $roleHintValue
                    qfu_scopekey        = $scopeKey
                    qfu_active          = $true
                    qfu_notes           = $aliasNote
                    "qfu_Staff@odata.bind"  = "/$($entitySets.staff)($staffId)"
                    "qfu_Branch@odata.bind" = "/$($entitySets.branch)($($branch.qfu_branchid))"
                }
                $aliasRecord = Invoke-Dv -Method Post -Path $entitySets.staffAlias -Body $aliasBody -WriteOperation:$true
                $aliasId = $aliasRecord.qfu_staffaliasid
                $aliasByKey[$aliasKey] = New-Object System.Collections.ArrayList
                [void]$aliasByKey[$aliasKey].Add($aliasRecord)
            }

            [void]$aliasRows.Add([pscustomobject]@{
                action              = $aliasAction
                qfu_staffaliasid    = $aliasId
                qfu_sourcesystem    = $sourceSystemLabel
                qfu_aliastype       = $aliasTypeLabel
                qfu_rawalias        = [string]$rawAliasExample
                qfu_normalizedalias = $number
                qfu_rolehint        = $roleLabel
                branch_code         = $branchCode
                branch_slug         = $branchSlug
                qfu_scopekey        = $scopeKey
                qfu_staffnumber     = $number
                qfu_staff_name      = $displayName
                qfu_notes           = $aliasNote
            })
        }

        $membershipKey = Get-MembershipKey -BranchId $branch.qfu_branchid -StaffId $staffId -Role $roleValue
        $existingMemberships = if ($membershipByKey.ContainsKey($membershipKey)) { @($membershipByKey[$membershipKey].ToArray()) } else { @() }
        if ($existingMemberships.Count -gt 1) {
            Add-Conflict -Conflicts $conflicts -ConflictType "DuplicateExistingBranchMembership" -NormalizedAlias $number -Roles $roleLabel -BranchCode $scopeKey -Details "More than one branch membership already exists for this branch/staff/role." -ActionTaken "Skipped membership update/create for this scope."
            continue
        }

        $membershipAction = "created"
        if ($existingMemberships.Count -eq 1) {
            $membershipPatch = [ordered]@{
                qfu_active = $true
            }
            if ([string]::IsNullOrWhiteSpace([string]$existingMemberships[0].qfu_notes)) {
                $membershipPatch.qfu_notes = $membershipNote
            }
            Invoke-DvNoContent -Method Patch -Path "$($entitySets.branchMembership)($($existingMemberships[0].qfu_branchmembershipid))" -Body $membershipPatch -WriteOperation:$true | Out-Null
            $membershipId = $existingMemberships[0].qfu_branchmembershipid
            $membershipAction = "updated"
        }
        else {
            $membershipBody = [ordered]@{
                qfu_name            = "$scopeKey $roleLabel $displayName"
                qfu_role            = $roleValue
                qfu_active          = $true
                qfu_notes           = $membershipNote
                "qfu_Staff@odata.bind"  = "/$($entitySets.staff)($staffId)"
                "qfu_Branch@odata.bind" = "/$($entitySets.branch)($($branch.qfu_branchid))"
            }
            $membershipRecord = Invoke-Dv -Method Post -Path $entitySets.branchMembership -Body $membershipBody -WriteOperation:$true
            $membershipId = $membershipRecord.qfu_branchmembershipid
            $membershipByKey[$membershipKey] = New-Object System.Collections.ArrayList
            [void]$membershipByKey[$membershipKey].Add($membershipRecord)
        }

        [void]$membershipRows.Add([pscustomobject]@{
            action                  = $membershipAction
            qfu_branchmembershipid  = $membershipId
            branch_code             = $branchCode
            branch_slug             = $branchSlug
            qfu_staffnumber         = $number
            qfu_staff_name          = $displayName
            qfu_role                = $roleLabel
            qfu_notes               = $membershipNote
        })
    }
}

$invalidRows = @(
    $invalidObservations |
        Group-Object {
            "$($_.source_system)|$($_.alias_type)|$($_.raw_value)|$($_.normalized_value)|$($_.reason)|$($_.branch_code)|$($_.branch_slug)"
        } |
        Sort-Object Name |
        ForEach-Object {
            $first = $_.Group[0]
            [pscustomobject]@{
                source_system          = $first.source_system
                alias_type             = $first.alias_type
                raw_value              = $first.raw_value
                normalized_value       = $first.normalized_value
                reason                 = $first.reason
                branch_code            = $first.branch_code
                branch_slug            = $first.branch_slug
                occurrence_count       = $_.Count
                suggested_action       = "Source/manager review required. Do not create staff alias mapping."
            }
        }
)

$staffRows | Export-Csv -Path (Join-Path $outputRoot "provisional-staff-created.csv") -NoTypeInformation
$aliasRows | Export-Csv -Path (Join-Path $outputRoot "provisional-aliases-created.csv") -NoTypeInformation
$membershipRows | Export-Csv -Path (Join-Path $outputRoot "provisional-branchmemberships-created.csv") -NoTypeInformation
Export-ConflictCsv -Rows $conflicts -Path (Join-Path $outputRoot "identity-conflicts-review.csv")
$invalidRows | Export-Csv -Path (Join-Path $outputRoot "invalid-alias-review.csv") -NoTypeInformation

$postCounts = Get-LiveCounts -EntitySets $entitySets -Option $option

$summary = [ordered]@{
    timestamp                         = (Get-Date).ToString("o")
    environmentUrl                    = $EnvironmentUrl
    solutionFound                     = [bool]$solution
    appFound                          = [bool]$app
    entitySets                        = $entitySets
    keyChecks                         = $keyChecks
    quoteHeaderRecordsScanned         = $quoteCount
    quoteLineRecordsScanned           = $quoteLines.Count
    distinctValidStaffNumbersFound    = $candidateByNumber.Count
    invalidAliasGroups                = $invalidRows.Count
    conflictRows                      = $conflicts.Count
    provisionalStaffCreated           = @($staffRows | Where-Object { $_.action -eq "created" }).Count
    provisionalStaffUpdated           = @($staffRows | Where-Object { $_.action -eq "updated" }).Count
    provisionalAliasesCreated         = @($aliasRows | Where-Object { $_.action -eq "created" }).Count
    provisionalAliasesUpdated         = @($aliasRows | Where-Object { $_.action -eq "updated" }).Count
    provisionalBranchMembershipsCreated = @($membershipRows | Where-Object { $_.action -eq "created" }).Count
    provisionalBranchMembershipsUpdated = @($membershipRows | Where-Object { $_.action -eq "updated" }).Count
    emailsGuessed                     = 0
    systemUsersGuessed                = 0
    entraIdsGuessed                   = 0
    resolverApplyModeRun              = $false
    workItemsCreated                  = 0
    assignmentExceptionsCreated       = 0
    alertsSent                        = 0
    preCounts                         = $preCounts
    postCounts                        = $postCounts
    outputFiles                       = @(
        "provisional-staff-created.csv",
        "provisional-aliases-created.csv",
        "provisional-branchmemberships-created.csv",
        "identity-conflicts-review.csv",
        "invalid-alias-review.csv"
    )
}

$summaryPath = Join-Path $outputRoot "bootstrap-summary.json"
$summary | ConvertTo-Json -Depth 100 | Set-Content -Path $summaryPath -Encoding UTF8

Write-Host "Phase 3.2A revised provisional bootstrap complete."
Write-Host "Staff created/updated: $($summary.provisionalStaffCreated)/$($summary.provisionalStaffUpdated)"
Write-Host "Aliases created/updated: $($summary.provisionalAliasesCreated)/$($summary.provisionalAliasesUpdated)"
Write-Host "Branch memberships created/updated: $($summary.provisionalBranchMembershipsCreated)/$($summary.provisionalBranchMembershipsUpdated)"
Write-Host "Conflicts: $($summary.conflictRows); invalid alias groups: $($summary.invalidAliasGroups)"
Write-Host "Summary: $summaryPath"
