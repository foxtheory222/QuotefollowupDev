param(
    [string]$EnvironmentUrl = "https://orga632edd5.crm3.dynamics.com/",
    [string]$OutputDirectory = "results/phase3-2B-controlled-apply",
    [int]$MaxQuoteGroups = 5,
    [string]$PreferredBranchCode = "4171"
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
        return [ordered]@{ status = "unmapped"; staffId = $null; matchCount = 0 }
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
            }
        }
    }

    if ($scored.Count -eq 0) {
        return [ordered]@{ status = "unmapped"; staffId = $null; matchCount = 0 }
    }

    $bestScore = ($scored | Measure-Object score -Maximum).Maximum
    $best = @($scored | Where-Object { $_.score -eq $bestScore })
    $uniqueStaff = @($best | Select-Object -ExpandProperty staffId -Unique)
    if ($uniqueStaff.Count -eq 1) {
        return [ordered]@{ status = "resolved"; staffId = $uniqueStaff[0]; matchCount = $best.Count }
    }

    return [ordered]@{ status = "ambiguous"; staffId = $null; matchCount = $best.Count }
}

function Get-ResolutionStatus {
    param(
        [object]$SourceAlias,
        [object]$Resolution
    )

    if ($SourceAlias.status -eq "valid") { return $Resolution.status }
    if ($SourceAlias.status -eq "ambiguous-source") { return "ambiguous-source" }
    if ($SourceAlias.reason -eq "Zero") { return "invalid-zero" }
    return "invalid-blank"
}

$outputRoot = Join-Path (Get-Location) $OutputDirectory
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

$entitySets = [ordered]@{
    quote      = Get-EntitySetName -LogicalName "qfu_quote"
    quoteLine  = Get-EntitySetName -LogicalName "qfu_quoteline"
    branch     = Get-EntitySetName -LogicalName "qfu_branch"
    staffAlias = Get-EntitySetName -LogicalName "qfu_staffalias"
    workItem   = Get-EntitySetName -LogicalName "qfu_workitem"
}

$option = [ordered]@{
    sp830SourceSystem   = Get-OptionValue -ChoiceName "qfu_sourcesystem" -Label "SP830CA"
    amNumberAliasType   = Get-OptionValue -ChoiceName "qfu_aliastype" -Label "AM Number"
    cssrNumberAliasType = Get-OptionValue -ChoiceName "qfu_aliastype" -Label "CSSR Number"
    quoteWorkType       = Get-OptionValue -ChoiceName "qfu_worktype" -Label "Quote"
}

$activeQuoteFilter = [System.Uri]::EscapeDataString("statecode eq 0 and (qfu_active eq true or qfu_active eq null)")
$quoteSelect = "qfu_quoteid,qfu_quotenumber,qfu_branchcode,qfu_branchslug,qfu_amount,qfu_sourcedate,qfu_sourceupdatedon,qfu_sourceid,modifiedon,createdon,qfu_active"
$quotes = Invoke-DvAll -Path "$($entitySets.quote)?`$select=$quoteSelect&`$filter=$activeQuoteFilter"
$lineFilter = [System.Uri]::EscapeDataString("statecode eq 0")
$lineSelect = "qfu_quotelineid,qfu_quotenumber,qfu_branchcode,qfu_branchslug,qfu_tsr,qfu_tsrname,qfu_cssr,qfu_cssrname,qfu_linetotal,qfu_amount,qfu_sourcedate,qfu_lastimportdate,qfu_sourceid,qfu_uniquekey"
$quoteLines = Invoke-DvAll -Path "$($entitySets.quoteLine)?`$select=$lineSelect&`$filter=$lineFilter"
$branches = Invoke-DvAll -Path "$($entitySets.branch)?`$select=qfu_branchid,qfu_branchcode,qfu_branchslug,qfu_name,qfu_active"
$aliases = Invoke-DvAll -Path "$($entitySets.staffAlias)?`$select=qfu_staffaliasid,qfu_sourcesystem,qfu_aliastype,qfu_normalizedalias,qfu_scopekey,qfu_active,_qfu_staff_value,_qfu_branch_value&`$filter=$([System.Uri]::EscapeDataString('statecode eq 0 and qfu_active eq true'))"
$existingWorkItems = Invoke-DvAll -Path "$($entitySets.workItem)?`$select=qfu_workitemid,qfu_sourceexternalkey,qfu_worktype&`$filter=$([System.Uri]::EscapeDataString('statecode eq 0'))"

$branchByCode = @{}
$branchBySlug = @{}
foreach ($branch in $branches) {
    if ($branch.qfu_branchcode) { $branchByCode[[string]$branch.qfu_branchcode] = $branch }
    if ($branch.qfu_branchslug) { $branchBySlug[[string]$branch.qfu_branchslug] = $branch }
}

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

$existingWorkItemBySourceKey = @{}
foreach ($workItem in $existingWorkItems) {
    if ($workItem.qfu_sourceexternalkey -and [int]$workItem.qfu_worktype -eq [int]$option.quoteWorkType) {
        $existingWorkItemBySourceKey[$workItem.qfu_sourceexternalkey] = $workItem
    }
}

$candidates = New-Object System.Collections.ArrayList
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
    $branchId = if ($branch) { $branch.qfu_branchid } else { $null }

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
    if ($total -lt [decimal]3000) { continue }

    $sourceExternalKey = "SP830CA|$sourceBranchCode|$($quote.qfu_quotenumber)"
    $tsrSource = Select-SourceAlias -Rows $sourceRows -NumberField "qfu_tsr" -NameField "qfu_tsrname"
    $cssrSource = Select-SourceAlias -Rows $sourceRows -NumberField "qfu_cssr" -NameField "qfu_cssrname"
    $tsrResolution = if ($tsrSource.status -eq "valid") { Resolve-Alias -Aliases $aliases -AliasType $option.amNumberAliasType -NormalizedAlias $tsrSource.normalized -BranchId $branchId -BranchCode $sourceBranchCode -BranchSlug $sourceBranchSlug -SourceSystem $option.sp830SourceSystem } else { [ordered]@{ status = "not-resolved" } }
    $cssrResolution = if ($cssrSource.status -eq "valid") { Resolve-Alias -Aliases $aliases -AliasType $option.cssrNumberAliasType -NormalizedAlias $cssrSource.normalized -BranchId $branchId -BranchCode $sourceBranchCode -BranchSlug $sourceBranchSlug -SourceSystem $option.sp830SourceSystem } else { [ordered]@{ status = "not-resolved" } }

    $tsrStatus = Get-ResolutionStatus -SourceAlias $tsrSource -Resolution $tsrResolution
    $cssrStatus = Get-ResolutionStatus -SourceAlias $cssrSource -Resolution $cssrResolution
    $exceptionCount = 0
    if ($tsrStatus -ne "resolved") { $exceptionCount++ }
    if ($cssrStatus -ne "resolved") { $exceptionCount++ }

    $assignmentStatus = if ($tsrStatus -eq "resolved" -and $cssrStatus -eq "resolved") {
        "Assigned"
    }
    elseif ($tsrStatus -ne "resolved" -and $cssrStatus -eq "resolved") {
        "Needs TSR Assignment"
    }
    elseif ($tsrStatus -eq "resolved" -and $cssrStatus -ne "resolved") {
        "Needs CSSR Assignment"
    }
    else {
        "Unmapped"
    }

    [void]$candidates.Add([pscustomobject]@{
        selected                   = "FALSE"
        selection_reason           = ""
        branch_code                = $sourceBranchCode
        source_system              = "SP830CA"
        sourceexternalkey          = $sourceExternalKey
        sourcedocumentnumber       = [string]$quote.qfu_quotenumber
        quote_total                = [math]::Round($total, 2)
        tsr_alias_status           = $tsrStatus
        cssr_alias_status          = $cssrStatus
        expected_assignment_status = $assignmentStatus
        expected_workitem_action   = if ($existingWorkItemBySourceKey.ContainsKey($sourceExternalKey)) { "update" } else { "create" }
        expected_exception_count   = $exceptionCount
        sanitized_notes            = if ($exceptionCount -eq 0) { "Both TSR and CSSR resolve; no customer data included." } else { "Controlled exception candidate; no customer data included." }
    })
}

$cleanPreferred = @($candidates | Where-Object { $_.branch_code -eq $PreferredBranchCode -and $_.tsr_alias_status -eq "resolved" -and $_.cssr_alias_status -eq "resolved" } | Sort-Object sourcedocumentnumber)
if ($cleanPreferred.Count -ge $MaxQuoteGroups) {
    $selected = @($cleanPreferred | Select-Object -First $MaxQuoteGroups)
    $reason = "Preferred branch $PreferredBranchCode had at least $MaxQuoteGroups high-value quote groups with both TSR and CSSR resolved."
}
else {
    $cleanByBranch = @(
        $candidates |
            Where-Object { $_.tsr_alias_status -eq "resolved" -and $_.cssr_alias_status -eq "resolved" } |
            Group-Object branch_code |
            Sort-Object -Property @{ Expression = "Count"; Descending = $true }, @{ Expression = "Name"; Ascending = $true }
    )
    if ($cleanByBranch.Count -eq 0) {
        throw "No clean high-value quote groups with both TSR and CSSR resolved were found."
    }
    $selectedBranch = $cleanByBranch[0].Name
    $selected = @($candidates | Where-Object { $_.branch_code -eq $selectedBranch -and $_.tsr_alias_status -eq "resolved" -and $_.cssr_alias_status -eq "resolved" } | Sort-Object sourcedocumentnumber | Select-Object -First $MaxQuoteGroups)
    $reason = "Branch $selectedBranch had the highest number of high-value quote groups with both TSR and CSSR resolved."
}

$selectedKeys = @{}
foreach ($row in $selected) {
    $selectedKeys[$row.sourceexternalkey] = $true
}

$scopeRows = @(
    $candidates |
        Where-Object { $selectedKeys.ContainsKey($_.sourceexternalkey) } |
        Sort-Object branch_code, sourcedocumentnumber |
        ForEach-Object {
            $_.selected = "TRUE"
            $_.selection_reason = $reason
            $_
        }
)

$scopePath = Join-Path $outputRoot "pre-apply-scope-review.csv"
$scopeRows | Export-Csv -Path $scopePath -NoTypeInformation

$allCandidatesPath = Join-Path $outputRoot "controlled-scope-candidates.csv"
$candidates | Sort-Object branch_code, sourcedocumentnumber | Export-Csv -Path $allCandidatesPath -NoTypeInformation

$summary = [ordered]@{
    timestamp                      = (Get-Date).ToString("o")
    environmentUrl                 = $EnvironmentUrl
    preferredBranchCode            = $PreferredBranchCode
    maxQuoteGroups                 = $MaxQuoteGroups
    selectedBranchCode             = if ($scopeRows.Count -gt 0) { $scopeRows[0].branch_code } else { "" }
    selectedQuoteGroupCount        = $scopeRows.Count
    selectedBothTsrCssrResolved    = @($scopeRows | Where-Object { $_.tsr_alias_status -eq "resolved" -and $_.cssr_alias_status -eq "resolved" }).Count
    selectedExpectedExceptionCount = ($scopeRows | Measure-Object expected_exception_count -Sum).Sum
    selectedExpectedAlertsSent     = 0
    selectionReason                = $reason
    totalHighValueCandidates       = $candidates.Count
    outputFiles                    = @("pre-apply-scope-review.csv", "controlled-scope-candidates.csv")
}

$summaryPath = Join-Path $outputRoot "controlled-scope-summary.json"
$summary | ConvertTo-Json -Depth 100 | Set-Content -Path $summaryPath -Encoding UTF8

Write-Host "Controlled scope selected: branch $($summary.selectedBranchCode), quote groups $($summary.selectedQuoteGroupCount)."
Write-Host "Both TSR/CSSR resolved: $($summary.selectedBothTsrCssrResolved); expected exceptions: $($summary.selectedExpectedExceptionCount); alerts: 0."
Write-Host "Scope file: $scopePath"
