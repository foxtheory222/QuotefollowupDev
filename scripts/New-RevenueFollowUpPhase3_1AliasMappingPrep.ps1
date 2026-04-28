param(
    [string]$EnvironmentUrl = "https://orga632edd5.crm3.dynamics.com/",
    [string]$SolutionUniqueName = "qfu_revenuefollowupworkbench",
    [string]$OutputDirectory = "results/phase3-1-alias-mapping"
)

$ErrorActionPreference = "Stop"

Import-Module Az.Accounts -ErrorAction Stop

if (-not $EnvironmentUrl.EndsWith("/")) {
    $EnvironmentUrl = "$EnvironmentUrl/"
}

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
    return @{
        Authorization      = "Bearer $script:token"
        "OData-MaxVersion" = "4.0"
        "OData-Version"    = "4.0"
        Accept             = "application/json"
        "Content-Type"     = "application/json; charset=utf-8"
    }
}

function Invoke-Dv {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $uri = "$($EnvironmentUrl)api/data/v9.2/$Path"
    return Invoke-RestMethod -Method $Method -Uri $uri -Headers (Get-Headers) -ErrorAction Stop
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

function Get-GroupKey {
    param(
        [AllowNull()][string]$BranchCode,
        [AllowNull()][string]$BranchSlug,
        [AllowNull()][string]$QuoteNumber
    )

    $branchPart = if (-not [string]::IsNullOrWhiteSpace($BranchCode)) { $BranchCode.Trim() } elseif (-not [string]::IsNullOrWhiteSpace($BranchSlug)) { $BranchSlug.Trim() } else { "UNKNOWN" }
    $quotePart = if (-not [string]::IsNullOrWhiteSpace($QuoteNumber)) { $QuoteNumber.Trim() } else { "UNKNOWN" }
    return "$branchPart|$quotePart"
}

function Select-SourceAlias {
    param(
        [object[]]$Rows,
        [string]$NumberField,
        [string]$NameField
    )

    $valid = @()
    $invalid = @()
    foreach ($row in $Rows) {
        $normalized = Normalize-QfuAlias -RawAlias $row.$NumberField
        if ($normalized.isValid) {
            $valid += [pscustomobject]$normalized
        }
        else {
            $invalid += [pscustomobject]$normalized
        }
    }

    $uniqueValid = @($valid | Group-Object normalized | ForEach-Object { $_.Group[0] })
    if ($uniqueValid.Count -eq 1) {
        return [ordered]@{
            status     = "valid"
            raw        = $uniqueValid[0].raw
            normalized = $uniqueValid[0].normalized
            reason     = ""
            display    = ($Rows | Where-Object { $_.$NameField } | Select-Object -First 1).$NameField
        }
    }
    if ($uniqueValid.Count -gt 1) {
        return [ordered]@{
            status     = "ambiguous-source"
            raw        = ($uniqueValid | ForEach-Object { $_.raw }) -join "|"
            normalized = ($uniqueValid | ForEach-Object { $_.normalized }) -join "|"
            reason     = "Multiple source number aliases on one quote"
            display    = ""
        }
    }

    $firstInvalid = if ($invalid.Count -gt 0) { $invalid[0] } else { [pscustomobject](Normalize-QfuAlias -RawAlias $null) }
    return [ordered]@{
        status     = "invalid"
        raw        = $firstInvalid.raw
        normalized = $firstInvalid.normalized
        reason     = $firstInvalid.reason
        display    = ($Rows | Where-Object { $_.$NameField } | Select-Object -First 1).$NameField
    }
}

function Resolve-Alias {
    param(
        [object[]]$Aliases,
        [int]$AliasType,
        [string]$NormalizedAlias,
        [AllowNull()][string]$BranchId,
        [AllowNull()][string]$BranchCode,
        [AllowNull()][string]$BranchSlug,
        [int]$SourceSystem
    )

    $matches = @($Aliases | Where-Object {
        [int]$_.qfu_sourcesystem -eq $SourceSystem -and
        [int]$_.qfu_aliastype -eq $AliasType -and
        $_.qfu_normalizedalias -eq $NormalizedAlias -and
        $_.'_qfu_staff_value'
    })

    if ($matches.Count -eq 0) {
        return [ordered]@{ status = "unmapped"; staffId = $null; matchCount = 0; reason = "No active alias mapping" }
    }

    $scored = @()
    foreach ($match in $matches) {
        $score = -1
        $matchBranch = $match.'_qfu_branch_value'
        $scope = if ($match.qfu_scopekey) { ([string]$match.qfu_scopekey).Trim() } else { "" }
        if ($BranchId -and $matchBranch -and $matchBranch -eq $BranchId) {
            $score = 3
        }
        elseif ($scope -and (($BranchCode -and $scope -eq $BranchCode) -or ($BranchSlug -and $scope -eq $BranchSlug))) {
            $score = 2
        }
        elseif (-not $matchBranch -and ([string]::IsNullOrWhiteSpace($scope) -or $scope -eq "GLOBAL")) {
            $score = 1
        }

        if ($score -ge 0) {
            $scored += [pscustomobject]@{
                score   = $score
                staffId = $match.'_qfu_staff_value'
                aliasId = $match.qfu_staffaliasid
            }
        }
    }

    if ($scored.Count -eq 0) {
        return [ordered]@{ status = "unmapped"; staffId = $null; matchCount = $matches.Count; reason = "Alias exists but no branch/scope match" }
    }

    $bestScore = ($scored | Measure-Object -Property score -Maximum).Maximum
    $best = @($scored | Where-Object { $_.score -eq $bestScore })
    $staffIds = @($best | Select-Object -ExpandProperty staffId -Unique)
    if ($staffIds.Count -gt 1) {
        return [ordered]@{ status = "ambiguous"; staffId = $null; matchCount = $best.Count; reason = "Multiple staff mappings at same scope priority" }
    }

    return [ordered]@{ status = "resolved"; staffId = $staffIds[0]; matchCount = $best.Count; reason = "" }
}

function Add-Example {
    param(
        [System.Collections.ArrayList]$List,
        [AllowNull()][string]$Value,
        [int]$Max = 5
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return }
    if ($List -contains $Value) { return }
    if ($List.Count -lt $Max) {
        [void]$List.Add($Value)
    }
}

function Get-OrCreateAliasAggregate {
    param(
        [hashtable]$Map,
        [string]$Key,
        [string]$AliasType,
        [string]$NormalizedAlias,
        [string]$BranchCode,
        [string]$BranchSlug,
        [string]$MappingStatus,
        [string]$SuggestedAction
    )

    if (-not $Map.ContainsKey($Key)) {
        $Map[$Key] = [ordered]@{
            source_system          = "SP830CA"
            alias_type             = $AliasType
            normalized_alias       = $NormalizedAlias
            raw_alias_examples     = New-Object System.Collections.ArrayList
            display_name_examples  = New-Object System.Collections.ArrayList
            branch_code            = $BranchCode
            branch_slug            = $BranchSlug
            high_value_quote_count = 0
            total_value_sum        = [decimal]0
            current_mapping_status = $MappingStatus
            suggested_action       = $SuggestedAction
            notes                  = "Human review required. Do not map from names alone."
        }
    }

    return $Map[$Key]
}

function Get-OrCreateInvalidAggregate {
    param(
        [hashtable]$Map,
        [string]$Key,
        [string]$AliasType,
        [string]$RawValue,
        [string]$NormalizedValue,
        [string]$Reason,
        [string]$BranchCode
    )

    if (-not $Map.ContainsKey($Key)) {
        $Map[$Key] = [ordered]@{
            source_system          = "SP830CA"
            alias_type             = $AliasType
            raw_value              = $RawValue
            normalized_value       = if ([string]::IsNullOrWhiteSpace($NormalizedValue)) { "BLANK" } else { $NormalizedValue }
            reason                 = $Reason
            branch_code            = $BranchCode
            high_value_quote_count = 0
            suggested_action       = "Source/manager review required. Do not create a staff alias mapping for invalid aliases."
        }
    }

    return $Map[$Key]
}

$outputRoot = Join-Path (Get-Location) $OutputDirectory
if (-not (Test-Path -LiteralPath $outputRoot)) {
    New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
}

$entitySets = [ordered]@{
    staff                = Get-EntitySetName -LogicalName "qfu_staff"
    staffAlias           = Get-EntitySetName -LogicalName "qfu_staffalias"
    branchMembership     = Get-EntitySetName -LogicalName "qfu_branchmembership"
    workItem             = Get-EntitySetName -LogicalName "qfu_workitem"
    assignmentException  = Get-EntitySetName -LogicalName "qfu_assignmentexception"
    quote                = Get-EntitySetName -LogicalName "qfu_quote"
    quoteLine            = Get-EntitySetName -LogicalName "qfu_quoteline"
    branch               = Get-EntitySetName -LogicalName "qfu_branch"
    policy               = Get-EntitySetName -LogicalName "qfu_policy"
}

$option = [ordered]@{
    quoteWorkType       = Get-OptionValue -ChoiceName "qfu_worktype" -Label "Quote"
    sp830SourceSystem   = Get-OptionValue -ChoiceName "qfu_sourcesystem" -Label "SP830CA"
    amNumberAliasType   = Get-OptionValue -ChoiceName "qfu_aliastype" -Label "AM Number"
    cssrNumberAliasType = Get-OptionValue -ChoiceName "qfu_aliastype" -Label "CSSR Number"
    gteOperator         = Get-OptionValue -ChoiceName "qfu_thresholdoperator" -Label "GreaterThanOrEqual"
    highValueOnlyMode   = Get-OptionValue -ChoiceName "qfu_workitemgenerationmode" -Label "HighValueOnly"
}

$solutionFilter = [System.Uri]::EscapeDataString("uniquename eq '$SolutionUniqueName'")
$solution = Get-First (Invoke-DvOrNull -Path "solutions?`$select=solutionid,uniquename,friendlyname,version,ismanaged&`$filter=$solutionFilter")
$appFilter = [System.Uri]::EscapeDataString("uniquename eq 'qfu_RevenueFollowUpWorkbench'")
$app = Get-First (Invoke-DvOrNull -Path "appmodules?`$select=appmoduleid,name,uniquename&`$filter=$appFilter")

$activeStaffFilter = [System.Uri]::EscapeDataString("statecode eq 0 and qfu_active eq true")
$activeAliasFilter = [System.Uri]::EscapeDataString("statecode eq 0 and qfu_active eq true")
$activeMembershipFilter = [System.Uri]::EscapeDataString("statecode eq 0 and qfu_active eq true")

$staff = Invoke-DvAll -Path "$($entitySets.staff)?`$select=qfu_staffid,qfu_name,qfu_primaryemail,qfu_staffnumber,qfu_active,_qfu_systemuser_value&`$filter=$activeStaffFilter"
$staffAliases = Invoke-DvAll -Path "$($entitySets.staffAlias)?`$select=qfu_staffaliasid,qfu_sourcesystem,qfu_aliastype,qfu_rawalias,qfu_normalizedalias,qfu_scopekey,qfu_active,_qfu_staff_value,_qfu_branch_value&`$filter=$activeAliasFilter"
$memberships = Invoke-DvAll -Path "$($entitySets.branchMembership)?`$select=qfu_branchmembershipid,qfu_role,qfu_active,_qfu_branch_value,_qfu_staff_value&`$filter=$activeMembershipFilter"

$duplicateAliasGroups = @(
    $staffAliases |
        Group-Object {
            "$($_.qfu_sourcesystem)|$($_.qfu_aliastype)|$($_.qfu_normalizedalias)|$($_.qfu_scopekey)"
        } |
        Where-Object { $_.Count -gt 1 } |
        ForEach-Object {
            [ordered]@{
                key   = $_.Name
                count = $_.Count
            }
        }
)

$multiStaffAtSameScope = @(
    $staffAliases |
        Group-Object {
            "$($_.qfu_sourcesystem)|$($_.qfu_aliastype)|$($_.qfu_normalizedalias)|$($_.qfu_scopekey)|$($_.'_qfu_branch_value')"
        } |
        Where-Object {
            @($_.Group | Select-Object -ExpandProperty '_qfu_staff_value' -Unique).Count -gt 1
        } |
        ForEach-Object {
            [ordered]@{
                key         = $_.Name
                alias_count = $_.Count
                staff_count = @($_.Group | Select-Object -ExpandProperty '_qfu_staff_value' -Unique).Count
            }
        }
)

$keyDefinitions = @(
    @{ table = "qfu_staffalias"; keyName = "qfu_key_staffalias_source_type_alias_scope" },
    @{ table = "qfu_branchmembership"; keyName = "qfu_key_branchmembership_branch_staff_role" },
    @{ table = "qfu_policy"; keyName = "qfu_key_policy_scope_worktype_activekey" },
    @{ table = "qfu_workitem"; keyName = "qfu_key_workitem_type_sourcekey" },
    @{ table = "qfu_alertlog"; keyName = "qfu_key_alertlog_dedupekey" },
    @{ table = "qfu_assignmentexception"; keyName = "qfu_key_assignmentexception_sourcekey_type_field_value" }
)
$keyResults = foreach ($definition in $keyDefinitions) {
    $key = Get-KeyBySchemaName -Table $definition.table -KeyName $definition.keyName
    [ordered]@{
        table                = $definition.table
        keyName              = $definition.keyName
        found                = [bool]$key
        entityKeyIndexStatus = if ($key) { $key.EntityKeyIndexStatus } else { $null }
        keyAttributes        = if ($key) { @($key.KeyAttributes) } else { @() }
        active               = if ($key) { $key.EntityKeyIndexStatus -eq "Active" } else { $false }
    }
}

$branches = Invoke-DvAll -Path "$($entitySets.branch)?`$select=qfu_branchid,qfu_branchcode,qfu_branchslug,qfu_name,qfu_active"
$branchByCode = @{}
$branchBySlug = @{}
foreach ($branch in $branches) {
    if ($branch.qfu_branchcode) { $branchByCode[[string]$branch.qfu_branchcode] = $branch }
    if ($branch.qfu_branchslug) { $branchBySlug[[string]$branch.qfu_branchslug] = $branch }
}

$activeQuoteFilter = [System.Uri]::EscapeDataString("statecode eq 0 and (qfu_active eq true or qfu_active eq null)")
$quoteSelect = "qfu_quoteid,qfu_quotenumber,qfu_branchcode,qfu_branchslug,qfu_amount,qfu_sourcedate,qfu_sourceupdatedon,qfu_sourceid,modifiedon,createdon,qfu_active"
$quotes = Invoke-DvAll -Path "$($entitySets.quote)?`$select=$quoteSelect&`$filter=$activeQuoteFilter"

$lineFilter = [System.Uri]::EscapeDataString("statecode eq 0")
$lineSelect = "qfu_quotelineid,qfu_quotenumber,qfu_branchcode,qfu_branchslug,qfu_tsr,qfu_tsrname,qfu_cssr,qfu_cssrname,qfu_linetotal,qfu_amount,qfu_sourcedate,qfu_lastimportdate,qfu_sourceid,qfu_uniquekey"
$quoteLines = Invoke-DvAll -Path "$($entitySets.quoteLine)?`$select=$lineSelect&`$filter=$lineFilter"

$policies = Invoke-DvAll -Path "$($entitySets.policy)?`$select=qfu_policyid,qfu_scopekey,qfu_worktype,qfu_highvaluethreshold,qfu_thresholdoperator,qfu_workitemgenerationmode,qfu_requiredattempts,qfu_active,_qfu_branch_value"
$globalPolicies = @($policies | Where-Object { $_.qfu_active -eq $true -and [int]$_.qfu_worktype -eq [int]$option.quoteWorkType -and $_.qfu_scopekey -eq "GLOBAL" })

$quoteByGroup = @{}
foreach ($quote in $quotes) {
    if ([string]::IsNullOrWhiteSpace($quote.qfu_quotenumber)) { continue }
    $key = Get-GroupKey -BranchCode $quote.qfu_branchcode -BranchSlug $quote.qfu_branchslug -QuoteNumber $quote.qfu_quotenumber
    if (-not $quoteByGroup.ContainsKey($key)) {
        $quoteByGroup[$key] = $quote
    }
}

$linesByGroup = @{}
foreach ($line in $quoteLines) {
    if ([string]::IsNullOrWhiteSpace($line.qfu_quotenumber)) { continue }
    $key = Get-GroupKey -BranchCode $line.qfu_branchcode -BranchSlug $line.qfu_branchslug -QuoteNumber $line.qfu_quotenumber
    if (-not $linesByGroup.ContainsKey($key)) {
        $linesByGroup[$key] = New-Object System.Collections.ArrayList
    }
    [void]$linesByGroup[$key].Add($line)
}

$lineOnlyGroups = @($linesByGroup.Keys | Where-Object { -not $quoteByGroup.ContainsKey($_) } | Sort-Object)
$headerOnlyGroups = @($quoteByGroup.Keys | Where-Object { -not $linesByGroup.ContainsKey($_) } | Sort-Object)

$unresolvedMap = @{}
$invalidMap = @{}

foreach ($groupKey in @($quoteByGroup.Keys | Sort-Object)) {
    $quote = $quoteByGroup[$groupKey]
    $groupLines = if ($linesByGroup.ContainsKey($groupKey)) { @($linesByGroup[$groupKey].ToArray()) } else { @() }
    $sourceRows = if ($groupLines.Count -gt 0) { $groupLines } else { @($quote) }

    $sourceBranchCode = if ($quote.qfu_branchcode) { [string]$quote.qfu_branchcode } elseif ($groupLines.Count -gt 0) { [string]$groupLines[0].qfu_branchcode } else { "" }
    $sourceBranchSlug = if ($quote.qfu_branchslug) { [string]$quote.qfu_branchslug } elseif ($groupLines.Count -gt 0) { [string]$groupLines[0].qfu_branchslug } else { "" }
    $branch = $null
    if ($sourceBranchCode -and $branchByCode.ContainsKey($sourceBranchCode)) {
        $branch = $branchByCode[$sourceBranchCode]
    }
    elseif ($sourceBranchSlug -and $branchBySlug.ContainsKey($sourceBranchSlug)) {
        $branch = $branchBySlug[$sourceBranchSlug]
    }

    $total = [decimal]0
    if ($groupLines.Count -gt 0) {
        foreach ($line in $groupLines) {
            if ($null -ne $line.qfu_linetotal) { $total += [decimal]$line.qfu_linetotal }
            elseif ($null -ne $line.qfu_amount) { $total += [decimal]$line.qfu_amount }
        }
    }
    if ($total -eq 0 -and $null -ne $quote.qfu_amount) {
        $total = [decimal]$quote.qfu_amount
    }

    $branchId = if ($branch) { $branch.qfu_branchid } else { $null }
    $branchPolicies = @()
    if ($branchId) {
        $branchPolicies = @($policies | Where-Object { $_.qfu_active -eq $true -and [int]$_.qfu_worktype -eq [int]$option.quoteWorkType -and $_.'_qfu_branch_value' -eq $branchId })
    }
    if ($branchPolicies.Count -eq 0 -and ($sourceBranchCode -or $sourceBranchSlug)) {
        $branchPolicies = @($policies | Where-Object {
            $_.qfu_active -eq $true -and
            [int]$_.qfu_worktype -eq [int]$option.quoteWorkType -and
            (($_.qfu_scopekey -eq $sourceBranchCode) -or ($_.qfu_scopekey -eq $sourceBranchSlug))
        })
    }
    $policy = if ($branchPolicies.Count -gt 0) { $branchPolicies[0] } elseif ($globalPolicies.Count -gt 0) { $globalPolicies[0] } else { $null }
    if (-not $policy) { continue }

    $threshold = if ($null -ne $policy.qfu_highvaluethreshold) { [decimal]$policy.qfu_highvaluethreshold } else { [decimal]3000 }
    $generationMode = if ($null -ne $policy.qfu_workitemgenerationmode) { [int]$policy.qfu_workitemgenerationmode } else { [int]$option.highValueOnlyMode }
    $qualifies = if ([int]$policy.qfu_thresholdoperator -eq [int]$option.gteOperator) { $total -ge $threshold } else { $total -gt $threshold }
    if (-not $qualifies -and $generationMode -eq [int]$option.highValueOnlyMode) { continue }

    foreach ($aliasSpec in @(
        @{ label = "AM Number"; typeValue = $option.amNumberAliasType; roleHint = "TSR"; numberField = "qfu_tsr"; nameField = "qfu_tsrname"; suggested = "Map verified AM Number alias to a qfu_staff TSR record." },
        @{ label = "CSSR Number"; typeValue = $option.cssrNumberAliasType; roleHint = "CSSR"; numberField = "qfu_cssr"; nameField = "qfu_cssrname"; suggested = "Map verified CSSR Number alias to a qfu_staff CSSR record." }
    )) {
        $sourceAlias = Select-SourceAlias -Rows $sourceRows -NumberField $aliasSpec.numberField -NameField $aliasSpec.nameField
        if ($sourceAlias.status -eq "valid") {
            $resolution = Resolve-Alias -Aliases $staffAliases -AliasType $aliasSpec.typeValue -NormalizedAlias $sourceAlias.normalized -BranchId $branchId -BranchCode $sourceBranchCode -BranchSlug $sourceBranchSlug -SourceSystem $option.sp830SourceSystem
            if ($resolution.status -ne "resolved") {
                $key = "SP830CA|$($aliasSpec.label)|$($sourceAlias.normalized)|$sourceBranchCode|$sourceBranchSlug"
                $row = Get-OrCreateAliasAggregate -Map $unresolvedMap -Key $key -AliasType $aliasSpec.label -NormalizedAlias $sourceAlias.normalized -BranchCode $sourceBranchCode -BranchSlug $sourceBranchSlug -MappingStatus $resolution.status -SuggestedAction $aliasSpec.suggested
                $row.high_value_quote_count++
                $row.total_value_sum += $total
                Add-Example -List $row.raw_alias_examples -Value $sourceAlias.raw
                Add-Example -List $row.display_name_examples -Value $sourceAlias.display
            }
        }
        elseif ($sourceAlias.status -eq "ambiguous-source") {
            $key = "SP830CA|$($aliasSpec.label)|$($sourceAlias.raw)|$sourceBranchCode|ambiguous"
            $row = Get-OrCreateInvalidAggregate -Map $invalidMap -Key $key -AliasType $aliasSpec.label -RawValue $sourceAlias.raw -NormalizedValue $sourceAlias.normalized -Reason $sourceAlias.reason -BranchCode $sourceBranchCode
            $row.high_value_quote_count++
        }
        else {
            $raw = if ($null -eq $sourceAlias.raw -or [string]::IsNullOrWhiteSpace([string]$sourceAlias.raw)) { "BLANK" } else { [string]$sourceAlias.raw }
            $normalized = if ([string]::IsNullOrWhiteSpace($sourceAlias.normalized)) { "BLANK" } else { $sourceAlias.normalized }
            $key = "SP830CA|$($aliasSpec.label)|$raw|$normalized|$sourceBranchCode"
            $row = Get-OrCreateInvalidAggregate -Map $invalidMap -Key $key -AliasType $aliasSpec.label -RawValue $raw -NormalizedValue $normalized -Reason $sourceAlias.reason -BranchCode $sourceBranchCode
            $row.high_value_quote_count++
        }
    }
}

$unresolvedRows = @(
    $unresolvedMap.Values |
        Sort-Object alias_type, normalized_alias, branch_code |
        ForEach-Object {
            [pscustomobject]@{
                source_system          = $_.source_system
                alias_type             = $_.alias_type
                normalized_alias       = $_.normalized_alias
                raw_alias_examples     = ($_.raw_alias_examples -join " | ")
                display_name_examples  = ($_.display_name_examples -join " | ")
                branch_code            = $_.branch_code
                branch_slug            = $_.branch_slug
                high_value_quote_count = $_.high_value_quote_count
                total_value_sum        = [Math]::Round($_.total_value_sum, 2)
                current_mapping_status = $_.current_mapping_status
                suggested_action       = $_.suggested_action
                notes                  = $_.notes
            }
        }
)

$invalidRows = @(
    $invalidMap.Values |
        Sort-Object alias_type, raw_value, branch_code |
        ForEach-Object {
            [pscustomobject]@{
                source_system          = $_.source_system
                alias_type             = $_.alias_type
                raw_value              = $_.raw_value
                normalized_value       = $_.normalized_value
                reason                 = $_.reason
                branch_code            = $_.branch_code
                high_value_quote_count = $_.high_value_quote_count
                suggested_action       = $_.suggested_action
            }
        }
)

$staffTemplateRows = @(
    $unresolvedRows |
        ForEach-Object {
            [pscustomobject]@{
                qfu_name                       = ""
                qfu_primaryemail               = ""
                qfu_staffnumber                = ""
                qfu_systemuser_email_or_domainname = ""
                qfu_entraobjectid              = ""
                qfu_defaultbranchcode          = $_.branch_code
                qfu_active                     = "TRUE"
                qfu_notes                      = "Optional staff creation row for $($_.alias_type) $($_.normalized_alias). Complete manually; do not infer staff from display name examples."
            }
        }
)

$staffAliasTemplateRows = @(
    $unresolvedRows |
        ForEach-Object {
            $roleHint = if ($_.alias_type -eq "AM Number") { "TSR" } else { "CSSR" }
            $scope = if (-not [string]::IsNullOrWhiteSpace($_.branch_code)) { $_.branch_code } else { "" }
            [pscustomobject]@{
                qfu_sourcesystem          = $_.source_system
                qfu_aliastype             = $_.alias_type
                qfu_rawalias              = ($_.raw_alias_examples -split "\s\|\s" | Select-Object -First 1)
                qfu_normalizedalias       = $_.normalized_alias
                qfu_rolehint              = $roleHint
                qfu_branchcode_or_global  = $scope
                qfu_scopekey              = $scope
                qfu_staff_name_or_key     = ""
                qfu_active                = "TRUE"
                qfu_verifiedon            = ""
                qfu_notes                 = "Human must set staff after review. Names are display/fallback only."
            }
        }
)

$membershipTemplateRows = @(
    $unresolvedRows |
        ForEach-Object {
            $role = if ($_.alias_type -eq "AM Number") { "TSR" } else { "CSSR" }
            [pscustomobject]@{
                qfu_branchcode        = $_.branch_code
                qfu_staff_name_or_key = ""
                qfu_role              = $role
                qfu_active            = "TRUE"
                qfu_startdate         = ""
                qfu_enddate           = ""
                qfu_isprimary         = ""
                qfu_notes             = "Complete only after staff mapping is verified."
            }
        } |
        Sort-Object qfu_branchcode, qfu_role -Unique
)

$unresolvedRows | Export-Csv -Path (Join-Path $outputRoot "unresolved-staff-alias-review.csv") -NoTypeInformation -Encoding UTF8
$invalidRows | Export-Csv -Path (Join-Path $outputRoot "invalid-alias-exceptions-review.csv") -NoTypeInformation -Encoding UTF8
$staffTemplateRows | Export-Csv -Path (Join-Path $outputRoot "qfu_staff-import-template.csv") -NoTypeInformation -Encoding UTF8
$staffAliasTemplateRows | Export-Csv -Path (Join-Path $outputRoot "qfu_staffalias-import-template.csv") -NoTypeInformation -Encoding UTF8
$membershipTemplateRows | Export-Csv -Path (Join-Path $outputRoot "qfu_branchmembership-import-template.csv") -NoTypeInformation -Encoding UTF8

$summary = [ordered]@{
    phase = "Phase 3.1"
    checkedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    environmentUrl = $EnvironmentUrl.TrimEnd("/")
    solutionFound = [bool]$solution
    appFound = [bool]$app
    entitySets = $entitySets
    alternateKeys = @($keyResults)
    liveCounts = [ordered]@{
        activeStaffRecords = $staff.Count
        activeStaffAliasRecords = $staffAliases.Count
        activeAmNumberAliases = @($staffAliases | Where-Object { [int]$_.qfu_sourcesystem -eq [int]$option.sp830SourceSystem -and [int]$_.qfu_aliastype -eq [int]$option.amNumberAliasType }).Count
        activeCssrNumberAliases = @($staffAliases | Where-Object { [int]$_.qfu_sourcesystem -eq [int]$option.sp830SourceSystem -and [int]$_.qfu_aliastype -eq [int]$option.cssrNumberAliasType }).Count
        activeBranchMemberships = $memberships.Count
        duplicateAliasMappingGroups = $duplicateAliasGroups.Count
        multiStaffSameScopeAliasGroups = $multiStaffAtSameScope.Count
        activeStaffMissingPrimaryEmail = @($staff | Where-Object { [string]::IsNullOrWhiteSpace($_.qfu_primaryemail) }).Count
        activeStaffMissingSystemUser = @($staff | Where-Object { -not $_.'_qfu_systemuser_value' }).Count
    }
    duplicateAliasMappingGroups = @($duplicateAliasGroups)
    multiStaffSameScopeAliasGroups = @($multiStaffAtSameScope)
    headerLineCompleteness = [ordered]@{
        quoteHeaderGroups = $quoteByGroup.Count
        quoteLineGroups = $linesByGroup.Count
        lineGroupsWithoutHeader = $lineOnlyGroups.Count
        headerGroupsWithoutLines = $headerOnlyGroups.Count
        recommendation = if ($lineOnlyGroups.Count -gt 0) { "Do not guess. Later resolver design should explicitly decide whether to process the union of header and line groups." } else { "Current resolver can continue using quote header groups for MVP dry-run/apply because no line-only groups were found." }
    }
    aliasMapping = [ordered]@{
        unresolvedAliasRows = $unresolvedRows.Count
        unresolvedAmNumberRows = @($unresolvedRows | Where-Object { $_.alias_type -eq "AM Number" }).Count
        unresolvedCssrNumberRows = @($unresolvedRows | Where-Object { $_.alias_type -eq "CSSR Number" }).Count
        invalidAliasRows = $invalidRows.Count
        guessedMappings = 0
        templatesDirectory = (Resolve-Path -LiteralPath $outputRoot).Path
        files = @(
            "unresolved-staff-alias-review.csv",
            "invalid-alias-exceptions-review.csv",
            "qfu_staff-import-template.csv",
            "qfu_staffalias-import-template.csv",
            "qfu_branchmembership-import-template.csv"
        )
    }
}

$summary | ConvertTo-Json -Depth 100 | Set-Content -Path (Join-Path $outputRoot "phase3-1-alias-mapping-summary.json") -Encoding UTF8
$summary.headerLineCompleteness | ConvertTo-Json -Depth 20 | Set-Content -Path (Join-Path $outputRoot "header-line-completeness.json") -Encoding UTF8

$summary | ConvertTo-Json -Depth 100
