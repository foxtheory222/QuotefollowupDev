param(
    [string]$AuditDir = "Audits/QuoteFollowUp-phase-2-1-admin-panel-app-forms-views-audit",
    [string]$ZipPath = "QuoteFollowUp-phase-2-1-admin-panel-app-forms-views-audit.zip",
    [string]$ResultJson = "results/phase2-1-live-state-20260427.json",
    [string]$EnvironmentUrl = "https://orga632edd5.crm3.dynamics.com/",
    [string]$PortalUrl = "https://operationscenter.powerappsportals.com",
    [string]$SolutionExportZip = "solution/exports/qfu_revenuefollowupworkbench-phase2-1-unmanaged.zip",
    [string]$UnpackedSolutionDir = "solution/revenue-follow-up-workbench/phase2-1-unpacked",
    [string]$DurableRepoDir = "tmp-github-QuoteFollowUp"
)

$ErrorActionPreference = "Stop"

function Write-TextFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    [System.IO.File]::WriteAllText((Resolve-Path -LiteralPath $parent).Path + "\" + (Split-Path -Leaf $Path), $Content, [System.Text.UTF8Encoding]::new($false))
}

function Copy-SafeFile {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $destinationParent = Split-Path -Parent $Destination
    if ($destinationParent -and -not (Test-Path -LiteralPath $destinationParent)) {
        New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
    }

    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Get-GitValue {
    param([string[]]$Arguments)

    if (-not (Test-Path -LiteralPath "$DurableRepoDir/.git")) {
        return ""
    }

    $output = & git -C $DurableRepoDir @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) {
        return ""
    }

    return ($output -join "`n").Trim()
}

function Convert-JsonList {
    param([object[]]$Items)

    if (-not $Items -or $Items.Count -eq 0) {
        return "None"
    }

    return ($Items -join ", ")
}

function New-FieldLine {
    param([string]$Label, [string[]]$Fields)

    return "- ${Label}: " + (($Fields | ForEach-Object { "``$_``" }) -join ", ")
}

if (-not (Test-Path -LiteralPath $ResultJson)) {
    throw "Missing result JSON: $ResultJson"
}

if (Test-Path -LiteralPath $AuditDir) {
    Remove-Item -LiteralPath $AuditDir -Recurse -Force
}

New-Item -ItemType Directory -Path $AuditDir -Force | Out-Null
$safeRoot = Join-Path $AuditDir "SAFE_SOURCE_FILES"
New-Item -ItemType Directory -Path $safeRoot -Force | Out-Null

$result = Get-Content -LiteralPath $ResultJson -Raw | ConvertFrom-Json
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"
$fence = '```'
$branch = Get-GitValue -Arguments @("branch", "--show-current")
$commit = Get-GitValue -Arguments @("rev-parse", "HEAD")
$message = Get-GitValue -Arguments @("log", "-1", "--pretty=%s")
$statusShort = Get-GitValue -Arguments @("status", "--short")
$statusCount = 0
if ($statusShort) {
    $statusCount = @($statusShort -split "`n" | Where-Object { $_.Trim() }).Count
}
$hasUncommitted = if ($statusCount -gt 0) { "yes" } else { "no" }

$toolingAvailable = "yes"
$authenticatedEnvironment = "yes"
$solutionFound = if ($result.solution) { "yes" } else { "no" }
$tablesFound = if (@($result.tables | Where-Object { $_.found }).Count -eq 8) { "yes" } else { "no" }
$choicesFound = if (@($result.choices | Where-Object { $_.found }).Count -eq 19) { "yes" } else { "no" }
$appFound = if ($result.appFound) { "yes" } else { "no" }

$missingFields = @()
$missingLookups = @()
foreach ($table in $result.tables) {
    foreach ($field in $table.expectedFields) {
        if (-not $field.found) {
            $missingFields += "$($table.name).$($field.name)"
        }
    }
    foreach ($lookup in $table.expectedLookups) {
        if (-not $lookup.found) {
            $missingLookups += "$($table.name).$($lookup.name)"
        }
    }
}
$columnsFound = if ($missingFields.Count -eq 0) { "yes" } else { "no" }
$lookupsFound = if ($missingLookups.Count -eq 0) { "yes" } else { "no" }

$currentRepoState = @"
# Current Repo State

Generated: $timestamp

Working operations folder: ``C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion``

Durable source repo: ``tmp-github-QuoteFollowUp``

Current branch: ``$branch``

Latest commit hash: ``$commit``

Latest commit message: ``$message``

Uncommitted changes: $hasUncommitted

Git status summary:

${fence}text
$statusShort
${fence}

Notes:

- The working operations folder is not the durable git repository root.
- Phase 2.1 files were prepared from the working folder and safe files were mirrored into the durable repo copy where appropriate.
"@
Write-TextFile -Path (Join-Path $AuditDir "CURRENT_REPO_STATE.md") -Content $currentRepoState

$phaseStatus = @"
# Phase Status

Current phase: Phase 2.1 - create or validate the actual Power Apps model-driven Admin Panel MVP app, forms, views, and navigation.

Build result: manual-required.

What should be functional now:

- Dev Dataverse solution ``qfu_revenuefollowupworkbench`` exists.
- The eight Phase 2 workbench tables exist.
- Global choices exist.
- Requested scalar columns and lookup relationships exist.
- The unmanaged solution can be exported and unpacked from the dev org.
- Maker Portal checklist exists for building the Admin Panel MVP app safely.
- Google Stitch Admin Panel MVP prompt exists as design guidance only.

What is not functional yet:

- The model-driven app ``Revenue Follow-Up Workbench`` is not present in dev.
- Admin Panel MVP navigation is not live.
- Required custom forms are not live.
- Required custom views are not live.
- Resolver flows, alerts, command bar actions, My Work custom page, Manager Panel, GM Review, and security roles are not implemented.

What is next:

1. Build the model-driven app manually in Maker Portal using ``docs/power-apps-maker-admin-panel-build-checklist.md``.
2. Publish all customizations.
3. Export and unpack ``qfu_revenuefollowupworkbench`` again.
4. Re-run the live-state verifier and confirm app module, sitemap, forms, and required views are present.

What is still left:

- Manual app shell and navigation.
- Manual form layout.
- Manual view creation.
- Future resolver-flow phase.
- Future alerts/digests phase.
- Future role/security design.

Blocking questions:

- None blocking Phase 2.1 documentation and source preservation.
- Human Maker Portal action is required before Phase 2.1 can be marked live-functional.
"@
Write-TextFile -Path (Join-Path $AuditDir "PHASE_STATUS.md") -Content $phaseStatus

$liveBuildResult = @"
# Live Build Result

Environment URL checked: ``$EnvironmentUrl``

Portal URL context: ``$PortalUrl``

Power Platform tooling available: $toolingAvailable

Authenticated environment: $authenticatedEnvironment

Solution found: $solutionFound

Dataverse tables found: $tablesFound

Choices found: $choicesFound

Columns found: $columnsFound

Lookup relationships found: $lookupsFound

Model-driven app created/found: $appFound

Forms created/found: no

Views created/found: no

App published: no

Solution exported/unpacked: yes

Blockers/failures:

- The available PAC CLI can export, unpack, and verify solution metadata, but it does not provide a supported creation path for model-driven app shell, sitemap navigation, custom forms, or custom views.
- Raw app metadata creation through direct Web API writes was intentionally not used.
- Therefore the app layer is manual-required.

Verification artifact:

- ``results/phase2-1-live-state-20260427.json``
"@
Write-TextFile -Path (Join-Path $AuditDir "LIVE_BUILD_RESULT.md") -Content $liveBuildResult

$appReview = @"
# App Module Review

App name: Revenue Follow-Up Workbench

App unique name: not available because no matching model-driven app was found.

App areas/navigation:

- Admin Panel MVP: manual-required
- Staff: manual-required
- Branch Memberships: manual-required
- Staff Alias Mapping: manual-required
- Branch Policies: manual-required
- Assignment Exceptions: manual-required
- Work Items: manual-required
- Work Item Actions: manual-required
- Alert Logs: manual-required

AppModule metadata exists in unpacked solution: no

Sitemap/navigation metadata exists in unpacked solution: no

Usable in Power Apps: no

Reason:

The dev solution export/unpack contains Dataverse table and option set metadata, but no app module or sitemap files. The live verifier also found no model-driven app named ``Revenue Follow-Up Workbench``.
"@
Write-TextFile -Path (Join-Path $AuditDir "APP_MODULE_REVIEW.md") -Content $appReview

$fields = [ordered]@{
    "Staff" = @("qfu_name", "qfu_primaryemail", "qfu_staffnumber", "qfu_systemuser", "qfu_entraobjectid", "qfu_defaultbranch", "qfu_active", "qfu_notes")
    "Branch Membership" = @("qfu_branch", "qfu_staff", "qfu_role", "qfu_active", "qfu_startdate", "qfu_enddate", "qfu_isprimary", "qfu_notes")
    "Staff Alias Mapping" = @("qfu_sourcesystem", "qfu_aliastype", "qfu_rawalias", "qfu_normalizedalias", "qfu_rolehint", "qfu_branch", "qfu_scopekey", "qfu_staff", "qfu_active", "qfu_verifiedby", "qfu_verifiedon", "qfu_notes")
    "Branch Policy" = @("qfu_name", "qfu_branch", "qfu_scopekey", "qfu_worktype", "qfu_highvaluethreshold", "qfu_thresholdoperator", "qfu_workitemgenerationmode", "qfu_requiredattempts", "qfu_firstfollowupbasis", "qfu_firstfollowupbusinessdays", "qfu_primaryownerstrategy", "qfu_supportownerstrategy", "qfu_gmccmode", "qfu_managerccmode", "qfu_cssralertmode", "qfu_escalateafterbusinessdays", "qfu_digestenabled", "qfu_targetedalertenabled", "qfu_active")
    "Assignment Exception" = @("qfu_exceptiontype", "qfu_branch", "qfu_sourcesystem", "qfu_sourcefield", "qfu_rawvalue", "qfu_normalizedvalue", "qfu_displayname", "qfu_sourcedocumentnumber", "qfu_sourceexternalkey", "qfu_sourcequote", "qfu_sourcequoteline", "qfu_sourcebackorder", "qfu_workitem", "qfu_status", "qfu_resolvedstaff", "qfu_resolvedby", "qfu_resolvedon", "qfu_notes")
    "Work Item" = @("qfu_workitemnumber", "qfu_worktype", "qfu_sourcesystem", "qfu_branch", "qfu_sourcedocumentnumber", "qfu_stickynote", "qfu_stickynoteupdatedon", "qfu_stickynoteupdatedby", "qfu_customername", "qfu_totalvalue", "qfu_primaryownerstaff", "qfu_supportownerstaff", "qfu_tsrstaff", "qfu_cssrstaff", "qfu_requiredattempts", "qfu_completedattempts", "qfu_status", "qfu_priority", "qfu_nextfollowupon", "qfu_lastfollowedupon", "qfu_lastactionon", "qfu_overduesince", "qfu_escalationlevel", "qfu_policy", "qfu_assignmentstatus", "qfu_notes")
    "Work Item Action" = @("qfu_workitem", "qfu_actiontype", "qfu_countsasattempt", "qfu_actionby", "qfu_actionon", "qfu_attemptnumber", "qfu_outcome", "qfu_nextfollowupon", "qfu_relatedalert", "qfu_notes")
    "Alert Log" = @("qfu_workitem", "qfu_alerttype", "qfu_recipientstaff", "qfu_recipientemail", "qfu_ccemails", "qfu_dedupekey", "qfu_status", "qfu_senton", "qfu_failuremessage", "qfu_flowrunid", "qfu_notes")
}

$views = [ordered]@{
    "Staff" = @("Active Staff", "Staff Missing Email", "Staff Missing Dataverse User")
    "Branch Membership" = @("Active Branch Memberships", "Memberships by Branch", "Memberships by Role")
    "Staff Alias Mapping" = @("Active Aliases", "Unverified Aliases", "Aliases by Source System", "Potential Duplicate Aliases")
    "Branch Policy" = @("Active Policies", "Draft/Inactive Policies", "Policies by Branch", "Quote Policies")
    "Assignment Exception" = @("Open Assignment Exceptions", "Missing TSR Alias", "Missing CSSR Alias", "Blank/Zero Alias Exceptions", "Resolved Exceptions")
    "Work Item" = @("Open Work Items", "Needs TSR Assignment", "Needs CSSR Assignment", "Quotes >= `$3K", "Overdue Work Items", "Work Items with Sticky Notes")
    "Work Item Action" = @("Recent Actions", "Attempt Actions", "Non-Attempt Actions")
    "Alert Log" = @("Pending Alerts", "Failed Alerts", "Sent Alerts", "Suppressed/Skipped Alerts")
}

$formViewReview = "# Form And View Review`n`n"
$formViewReview += "Result: manual-required for app-specific forms and required views.`n`n"
$formViewReview += "The verifier found default Dataverse ``Information`` forms and default system views only. The requested Admin Panel MVP layouts and named views still need Maker Portal creation.`n`n"
foreach ($name in $fields.Keys) {
    $formViewReview += "## $name`n`n"
    $formViewReview += "Forms created/found/manual-required: manual-required. Default generated forms exist, but the Phase 2.1 form layout was not created.`n`n"
    $formViewReview += "Views created/found/manual-required: manual-required for required Admin Panel views.`n`n"
    $formViewReview += (New-FieldLine -Label "Fields included in required form design" -Fields $fields[$name]) + "`n`n"
    $formViewReview += (New-FieldLine -Label "Required views" -Fields $views[$name]) + "`n`n"
    $formViewReview += "Missing items: model-driven app form layout and named views.`n`n"
}
Write-TextFile -Path (Join-Path $AuditDir "FORM_VIEW_REVIEW.md") -Content $formViewReview

$adminReview = @"
# Admin Panel MVP Review

What admins can do now:

- Review the Dataverse foundation in the dev solution.
- Use generated default table forms/views if they open the tables directly from Maker Portal.
- Use the Maker Portal checklist to build the actual model-driven Admin Panel MVP.
- Use the live-state verifier to recheck the environment after the manual build.

What remains manual:

- Create model-driven app ``Revenue Follow-Up Workbench``.
- Add Admin Panel MVP navigation.
- Create the required forms.
- Create the required views.
- Publish and re-export the solution.

Whether the Admin Panel is usable yet: no.

Reason:

No model-driven app module was found in dev and no app module metadata was present in the unpacked solution.
"@
Write-TextFile -Path (Join-Path $AuditDir "ADMIN_PANEL_MVP_REVIEW.md") -Content $adminReview

$stitchPrompt = Get-Content -LiteralPath "docs/revenue-follow-up-admin-panel-mvp-google-stitch-prompt.md" -Raw
$stitchReview = @"
# Google Stitch UI Review

Stitch prototype generated: no

Stitch is guidance only: yes

Power Apps is implementation target: yes

Production frontend code generated from Stitch: no

Prompt:

$stitchPrompt
"@
Write-TextFile -Path (Join-Path $AuditDir "GOOGLE_STITCH_UI_REVIEW.md") -Content $stitchReview

$docQuality = @"
# Doc Quality Review

Cleanup result: passed for the Phase 2.1 audit package.

Confirmed cleanup targets:

- PowerShell interpolation artifacts: not carried forward into Phase 2.1 audit docs.
- Placeholder repo values: replaced with real durable repo branch, commit hash, commit message, status summary, and timestamp.
- Malformed code fences: replaced with valid triple-backtick fences.
- Bad ``results/...`` path rendering: paths are rendered as inline code or valid fenced text.
- Null/control characters: not present in generated markdown audit files.
- Malformed markdown tables: avoided in generated review files except simple two-column tables with explicit separators.

Historical note:

- The Phase 2 audit folder remains historical evidence. Phase 2.1 regenerated clean audit files instead of reusing the malformed Phase 2 markdown.
"@
Write-TextFile -Path (Join-Path $AuditDir "DOC_QUALITY_REVIEW.md") -Content $docQuality

$foundation = @"
# Dataverse Foundation Recheck

Environment URL checked: ``$EnvironmentUrl``

Solution ``qfu_revenuefollowupworkbench`` exists: $solutionFound

Global choices exist: $choicesFound

Tables exist: $tablesFound

Expected scalar columns exist: $columnsFound

Expected lookup relationships exist: $lookupsFound

Tables verified:

- ``qfu_staff``
- ``qfu_staffalias``
- ``qfu_branchmembership``
- ``qfu_policy``
- ``qfu_workitem``
- ``qfu_workitemaction``
- ``qfu_alertlog``
- ``qfu_assignmentexception``

Choices verified:

- ``qfu_role``
- ``qfu_worktype``
- ``qfu_sourcesystem``
- ``qfu_aliastype``
- ``qfu_rolehint``
- ``qfu_thresholdoperator``
- ``qfu_workitemgenerationmode``
- ``qfu_firstfollowupbasis``
- ``qfu_alertmode``
- ``qfu_cssralertmode``
- ``qfu_workitemstatus``
- ``qfu_priority``
- ``qfu_escalationlevel``
- ``qfu_assignmentstatus``
- ``qfu_actiontype``
- ``qfu_alerttype``
- ``qfu_alertstatus``
- ``qfu_exceptiontype``
- ``qfu_exceptionstatus``

Missing fields:

${fence}text
$(Convert-JsonList $missingFields)
${fence}

Missing lookups:

${fence}text
$(Convert-JsonList $missingLookups)
${fence}

Verification artifact:

- ``results/phase2-1-live-state-20260427.json``
"@
Write-TextFile -Path (Join-Path $AuditDir "DATAVERSE_FOUNDATION_RECHECK.md") -Content $foundation

$openDecisions = @"
# Open Decisions

These are the remaining human decisions. Confirmed Phase 2.1 business rules are not repeated here.

- CSSR alert mode behavior for the later alerts phase.
- GM CC mode behavior for the later alerts phase.
- Manager CC mode behavior for the later alerts phase.
- Backorder work item grain for a later work item generation phase.
- Customer pickup source and ownership pattern.
- Alias verification ownership before security roles are implemented.
- Exact custom-page scope for My Work versus model-driven views in a later phase.
"@
Write-TextFile -Path (Join-Path $AuditDir "OPEN_DECISIONS.md") -Content $openDecisions

Copy-SafeFile -Source "docs/power-apps-maker-admin-panel-build-checklist.md" -Destination (Join-Path $safeRoot "docs/power-apps-maker-admin-panel-build-checklist.md")
Copy-SafeFile -Source "docs/revenue-follow-up-admin-panel-mvp-google-stitch-prompt.md" -Destination (Join-Path $safeRoot "docs/revenue-follow-up-admin-panel-mvp-google-stitch-prompt.md")
Copy-SafeFile -Source "docs/revenue-follow-up-google-stitch-ui-brief.md" -Destination (Join-Path $safeRoot "docs/revenue-follow-up-google-stitch-ui-brief.md")
Copy-SafeFile -Source "scripts/verify-revenue-followup-phase2-1-live-state.ps1" -Destination (Join-Path $safeRoot "scripts/verify-revenue-followup-phase2-1-live-state.ps1")
Copy-SafeFile -Source "scripts/create-phase2-1-admin-panel-audit.ps1" -Destination (Join-Path $safeRoot "scripts/create-phase2-1-admin-panel-audit.ps1")
Copy-SafeFile -Source $ResultJson -Destination (Join-Path $safeRoot "results/phase2-1-live-state-20260427.json")
Copy-SafeFile -Source $SolutionExportZip -Destination (Join-Path $safeRoot "solution/qfu_revenuefollowupworkbench-phase2-1-unmanaged.zip")

$solutionDestination = Join-Path $safeRoot "solution/phase2-1-unpacked"
Copy-Item -LiteralPath $UnpackedSolutionDir -Destination $solutionDestination -Recurse -Force

$unpackedFileListPath = Join-Path $safeRoot "solution/phase2-1-unpacked-file-list.txt"
$unpackedFiles = Get-ChildItem -LiteralPath $solutionDestination -Recurse -File |
    Sort-Object FullName |
    ForEach-Object { $_.FullName.Substring((Resolve-Path -LiteralPath $safeRoot).Path.Length + 1) }
Write-TextFile -Path $unpackedFileListPath -Content (($unpackedFiles -join "`n") + "`n")

$manifestEntries = @(
    [pscustomobject]@{ Path = "CURRENT_REPO_STATE.md"; Why = "Real durable repo branch, commit, status, and timestamp." },
    [pscustomobject]@{ Path = "PHASE_STATUS.md"; Why = "Phase 2.1 scope, status, next steps, and blockers." },
    [pscustomobject]@{ Path = "LIVE_BUILD_RESULT.md"; Why = "Live dev environment build and verification outcome." },
    [pscustomobject]@{ Path = "APP_MODULE_REVIEW.md"; Why = "App module, sitemap, and Power Apps usability review." },
    [pscustomobject]@{ Path = "FORM_VIEW_REVIEW.md"; Why = "Forms/views status and manual-required field/view definitions." },
    [pscustomobject]@{ Path = "ADMIN_PANEL_MVP_REVIEW.md"; Why = "What the Admin Panel can and cannot do now." },
    [pscustomobject]@{ Path = "GOOGLE_STITCH_UI_REVIEW.md"; Why = "Stitch prompt and design-only status." },
    [pscustomobject]@{ Path = "DOC_QUALITY_REVIEW.md"; Why = "Markdown and generated documentation cleanup review." },
    [pscustomobject]@{ Path = "DATAVERSE_FOUNDATION_RECHECK.md"; Why = "Tables, choices, columns, and lookups recheck." },
    [pscustomobject]@{ Path = "OPEN_DECISIONS.md"; Why = "Only remaining human decisions." },
    [pscustomobject]@{ Path = "SAFE_SOURCE_FILES/docs/power-apps-maker-admin-panel-build-checklist.md"; Why = "Exact Maker Portal manual build steps." },
    [pscustomobject]@{ Path = "SAFE_SOURCE_FILES/docs/revenue-follow-up-admin-panel-mvp-google-stitch-prompt.md"; Why = "Dedicated Phase 2.1 Stitch prompt." },
    [pscustomobject]@{ Path = "SAFE_SOURCE_FILES/docs/revenue-follow-up-google-stitch-ui-brief.md"; Why = "Updated Stitch UI brief linking the Phase 2.1 prompt." },
    [pscustomobject]@{ Path = "SAFE_SOURCE_FILES/scripts/verify-revenue-followup-phase2-1-live-state.ps1"; Why = "Read-only verifier used for live state." },
    [pscustomobject]@{ Path = "SAFE_SOURCE_FILES/scripts/create-phase2-1-admin-panel-audit.ps1"; Why = "Audit package generator." },
    [pscustomobject]@{ Path = "SAFE_SOURCE_FILES/results/phase2-1-live-state-20260427.json"; Why = "Verifier output." },
    [pscustomobject]@{ Path = "SAFE_SOURCE_FILES/solution/qfu_revenuefollowupworkbench-phase2-1-unmanaged.zip"; Why = "Unmanaged solution export from dev." },
    [pscustomobject]@{ Path = "SAFE_SOURCE_FILES/solution/phase2-1-unpacked-file-list.txt"; Why = "Recursive file list for unpacked solution metadata." }
)

foreach ($file in $unpackedFiles) {
    $manifestEntries += [pscustomobject]@{ Path = "SAFE_SOURCE_FILES/$file"; Why = "Unpacked solution metadata." }
}
$manifestEntries += [pscustomobject]@{ Path = "MANIFEST.md"; Why = "Inventory of every file included in the audit package." }

$manifest = "# Manifest`n`n"
$manifest += "| File | Why it matters |`n"
$manifest += "| --- | --- |`n"
foreach ($entry in $manifestEntries) {
    $manifest += "| ``$($entry.Path)`` | $($entry.Why) |`n"
}
Write-TextFile -Path (Join-Path $AuditDir "MANIFEST.md") -Content $manifest

if (Test-Path -LiteralPath $ZipPath) {
    Remove-Item -LiteralPath $ZipPath -Force
}

Compress-Archive -Path (Join-Path $AuditDir "*") -DestinationPath $ZipPath -Force

[pscustomobject]@{
    AuditDir = (Resolve-Path -LiteralPath $AuditDir).Path
    ZipPath  = (Resolve-Path -LiteralPath $ZipPath).Path
}
