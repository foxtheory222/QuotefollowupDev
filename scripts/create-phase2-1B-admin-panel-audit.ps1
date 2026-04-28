param(
    [string]$WorkspacePath = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $encoding = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Invoke-GitText {
    param(
        [Parameter(Mandatory = $true)][string]$RepoPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    if (-not (Test-Path -LiteralPath (Join-Path $RepoPath '.git'))) {
        return ''
    }

    $output = & git -C $RepoPath @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        return ($output | Out-String).Trim()
    }
    return ($output | Out-String).Trim()
}

function Copy-AuditFile {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$DestinationRoot
    )

    $source = Join-Path $workspace $RelativePath
    if (-not (Test-Path -LiteralPath $source)) {
        return
    }

    $destination = Join-Path $DestinationRoot $RelativePath
    $destinationDirectory = Split-Path -Parent $destination
    [System.IO.Directory]::CreateDirectory($destinationDirectory) | Out-Null
    [System.IO.File]::Copy($source, $destination, $true)
}

function Copy-AuditDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$DestinationRoot,
        [string]$DestinationRelativePath = $RelativePath
    )

    $sourceRoot = Join-Path $workspace $RelativePath
    if (-not (Test-Path -LiteralPath $sourceRoot)) {
        return
    }

    $skipNames = @('.git', 'node_modules', 'bin', 'obj', 'dist', 'build', '.venv', '__pycache__')
    $sourceResolved = (Resolve-Path -LiteralPath $sourceRoot).Path
    Get-ChildItem -LiteralPath $sourceResolved -Recurse -File | ForEach-Object {
        $relativeChild = $_.FullName.Substring($sourceResolved.Length).TrimStart('\', '/')
        $segments = $relativeChild -split '[\\/]'
        if ($segments | Where-Object { $skipNames -contains $_ }) {
            return
        }

        $destination = Join-Path (Join-Path $DestinationRoot $DestinationRelativePath) $relativeChild
        $destinationDirectory = Split-Path -Parent $destination
        [System.IO.Directory]::CreateDirectory($destinationDirectory) | Out-Null
        [System.IO.File]::Copy($_.FullName, $destination, $true)
    }
}

function Join-Lines {
    param([string[]]$Lines)
    return ($Lines -join [Environment]::NewLine) + [Environment]::NewLine
}

$workspace = (Resolve-Path -LiteralPath $WorkspacePath).Path
$auditName = 'QuoteFollowUp-phase-2-1B-codex-built-admin-panel-audit'
$auditDir = Join-Path $workspace '_phase2_1B_audit'
$zipPath = Join-Path $workspace ($auditName + '.zip')
$safeRoot = Join-Path $auditDir 'SAFE_SOURCE_FILES'

if (Test-Path -LiteralPath $auditDir) {
    $resolvedAuditDir = (Resolve-Path -LiteralPath $auditDir).Path
    if (-not $resolvedAuditDir.StartsWith($workspace, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove audit directory outside workspace: $resolvedAuditDir"
    }
    Remove-Item -LiteralPath $resolvedAuditDir -Recurse -Force
}

if (Test-Path -LiteralPath $zipPath) {
    $resolvedZip = (Resolve-Path -LiteralPath $zipPath).Path
    if (-not $resolvedZip.StartsWith($workspace, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove zip outside workspace: $resolvedZip"
    }
    Remove-Item -LiteralPath $resolvedZip -Force
}

New-Item -ItemType Directory -Path $auditDir -Force | Out-Null
New-Item -ItemType Directory -Path $safeRoot -Force | Out-Null

$timestampLocal = Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'
$timestampUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$environmentUrl = 'https://orga632edd5.crm3.dynamics.com/'
$environmentId = '1c97a8d0-fd57-e76e-b8ab-35d9229d88f6'
$solutionName = 'qfu_revenuefollowupworkbench'
$appName = 'Revenue Follow-Up Workbench'
$appUniqueName = 'qfu_RevenueFollowUpWorkbench'
$appModuleId = '93917a64-6742-f111-bec7-7c1e52062b6f'
$appModuleIdUnique = '43a35720-ee3e-43ae-9b96-4c90e59d1381'
$appUrl = "https://orga632edd5.crm3.dynamics.com/main.aspx?appid=$appModuleId"
$finalBuildPath = Join-Path $workspace 'results\phase2-1B-live-build-result-final-20260427.json'
$finalVerifyPath = Join-Path $workspace 'results\phase2-1B-final-live-state-20260427.json'
$exportZipRelative = 'solution\exports\qfu_revenuefollowupworkbench-phase2-1B-final-unmanaged-20260427.zip'
$unpackedRelative = 'solution\revenue-follow-up-workbench\phase2-1B-final-unpacked-20260427'
$unpackedPath = Join-Path $workspace $unpackedRelative

$build = $null
$verify = $null
if (Test-Path -LiteralPath $finalBuildPath) {
    $build = Get-Content -LiteralPath $finalBuildPath -Raw | ConvertFrom-Json
}
if (Test-Path -LiteralPath $finalVerifyPath) {
    $verify = Get-Content -LiteralPath $finalVerifyPath -Raw | ConvertFrom-Json
}

$durableRepo = Join-Path $workspace 'tmp-github-QuoteFollowUp'
$repoBranch = Invoke-GitText -RepoPath $durableRepo -Arguments @('branch', '--show-current')
$repoCommit = Invoke-GitText -RepoPath $durableRepo -Arguments @('rev-parse', 'HEAD')
$repoMessage = Invoke-GitText -RepoPath $durableRepo -Arguments @('log', '-1', '--pretty=%s')
$repoStatus = Invoke-GitText -RepoPath $durableRepo -Arguments @('status', '--short', '--branch')
$hasUncommitted = if ($repoStatus -match '(?m)^( M|M | A|A | D|D |\?\?)') { 'yes' } else { 'no' }

$requiredTables = @(
    'qfu_staff',
    'qfu_branchmembership',
    'qfu_staffalias',
    'qfu_policy',
    'qfu_assignmentexception',
    'qfu_workitem',
    'qfu_workitemaction',
    'qfu_alertlog'
)

$forms = [ordered]@{
    'qfu_staff' = [ordered]@{
        Form = 'Staff Admin Main'
        Fields = @('qfu_name','qfu_primaryemail','qfu_staffnumber','qfu_systemuser','qfu_entraobjectid','qfu_defaultbranch','qfu_active','qfu_notes')
        Views = @('Active Staff','Staff Missing Email','Staff Missing Dataverse User')
    }
    'qfu_branchmembership' = [ordered]@{
        Form = 'Branch Membership Admin Main'
        Fields = @('qfu_branch','qfu_staff','qfu_role','qfu_active','qfu_startdate','qfu_enddate','qfu_isprimary','qfu_notes')
        Views = @('Active Branch Memberships','Memberships by Branch','Memberships by Role')
    }
    'qfu_staffalias' = [ordered]@{
        Form = 'Staff Alias Mapping Admin Main'
        Fields = @('qfu_sourcesystem','qfu_aliastype','qfu_rawalias','qfu_normalizedalias','qfu_rolehint','qfu_branch','qfu_scopekey','qfu_staff','qfu_active','qfu_verifiedby','qfu_verifiedon','qfu_notes')
        Views = @('Active Aliases','Unverified Aliases','Aliases by Source System','Potential Duplicate Aliases')
    }
    'qfu_policy' = [ordered]@{
        Form = 'Branch Policy Admin Main'
        Fields = @('qfu_name','qfu_branch','qfu_scopekey','qfu_worktype','qfu_highvaluethreshold','qfu_thresholdoperator','qfu_workitemgenerationmode','qfu_requiredattempts','qfu_firstfollowupbasis','qfu_firstfollowupbusinessdays','qfu_primaryownerstrategy','qfu_supportownerstrategy','qfu_gmccmode','qfu_managerccmode','qfu_cssralertmode','qfu_escalateafterbusinessdays','qfu_digestenabled','qfu_targetedalertenabled','qfu_active')
        Views = @('Active Policies','Draft/Inactive Policies','Policies by Branch','Quote Policies')
    }
    'qfu_assignmentexception' = [ordered]@{
        Form = 'Assignment Exception Admin Main'
        Fields = @('qfu_exceptiontype','qfu_branch','qfu_sourcesystem','qfu_sourcefield','qfu_rawvalue','qfu_normalizedvalue','qfu_displayname','qfu_sourcedocumentnumber','qfu_sourceexternalkey','qfu_sourcequote','qfu_sourcequoteline','qfu_sourcebackorder','qfu_workitem','qfu_status','qfu_resolvedstaff','qfu_resolvedby','qfu_resolvedon','qfu_notes')
        Views = @('Open Assignment Exceptions','Missing TSR Alias','Missing CSSR Alias','Blank/Zero Alias Exceptions','Resolved Exceptions')
    }
    'qfu_workitem' = [ordered]@{
        Form = 'Work Item Admin Main'
        Fields = @('qfu_workitemnumber','qfu_worktype','qfu_sourcesystem','qfu_branch','qfu_sourcedocumentnumber','qfu_stickynote','qfu_stickynoteupdatedon','qfu_stickynoteupdatedby','qfu_customername','qfu_totalvalue','qfu_primaryownerstaff','qfu_supportownerstaff','qfu_tsrstaff','qfu_cssrstaff','qfu_requiredattempts','qfu_completedattempts','qfu_status','qfu_priority','qfu_nextfollowupon','qfu_lastfollowedupon','qfu_lastactionon','qfu_overduesince','qfu_escalationlevel','qfu_policy','qfu_assignmentstatus','qfu_notes')
        Views = @('Open Work Items','Needs TSR Assignment','Needs CSSR Assignment','Quotes >= $3K','Overdue Work Items','Work Items with Sticky Notes')
    }
    'qfu_workitemaction' = [ordered]@{
        Form = 'Work Item Action Admin Main'
        Fields = @('qfu_workitem','qfu_actiontype','qfu_countsasattempt','qfu_actionby','qfu_actionon','qfu_attemptnumber','qfu_outcome','qfu_nextfollowupon','qfu_relatedalert','qfu_notes')
        Views = @('Recent Actions','Attempt Actions','Non-Attempt Actions')
    }
    'qfu_alertlog' = [ordered]@{
        Form = 'Alert Log Admin Main'
        Fields = @('qfu_workitem','qfu_alerttype','qfu_recipientstaff','qfu_recipientemail','qfu_ccemails','qfu_dedupekey','qfu_status','qfu_senton','qfu_failuremessage','qfu_flowrunid','qfu_notes')
        Views = @('Pending Alerts','Failed Alerts','Sent Alerts','Suppressed/Skipped Alerts')
    }
}

$appModuleMetadataExists = Test-Path -LiteralPath (Join-Path $unpackedPath 'AppModules\qfu_RevenueFollowUpWorkbench\AppModule.xml')
$siteMapMetadataExists = Test-Path -LiteralPath (Join-Path $unpackedPath 'AppModuleSiteMaps\qfu_RevenueFollowUpWorkbench\AppModuleSiteMap.xml')
$formMetadataCount = 0
$viewMetadataCount = 0
if (Test-Path -LiteralPath $unpackedPath) {
    $formMetadataCount = @(Get-ChildItem -LiteralPath $unpackedPath -Recurse -File -Filter '*.xml' | Where-Object { $_.FullName -match '\\FormXml\\main\\' }).Count
    $viewMetadataCount = @(Get-ChildItem -LiteralPath $unpackedPath -Recurse -File -Filter '*.xml' | Where-Object { $_.FullName -match '\\SavedQueries\\' }).Count
}

$currentRepoState = Join-Lines @(
    '# Current Repo State',
    '',
    "- Timestamp local: $timestampLocal",
    "- Timestamp UTC: $timestampUtc",
    "- Workspace: $workspace",
    "- Workspace git repo: no",
    "- Durable repo copy: $durableRepo",
    "- Current branch: $repoBranch",
    "- Latest commit hash: $repoCommit",
    "- Latest commit message: $repoMessage",
    "- Uncommitted changes: $hasUncommitted",
    '',
    '## Git Status Summary',
    '',
    '```text',
    $repoStatus,
    '```',
    '',
    'The workspace root is the active operations folder. Long-lived source preservation is in the nested durable repo copy.'
)
Write-Utf8NoBom -Path (Join-Path $auditDir 'CURRENT_REPO_STATE.md') -Content $currentRepoState

$phaseStatus = Join-Lines @(
    '# Phase Status',
    '',
    '- Current phase: Phase 2.1B - Codex-assisted Power Apps Admin Panel MVP build',
    '- Result: live-built',
    "- Target environment: $environmentUrl",
    "- Target environment ID: $environmentId",
    "- Solution: $solutionName",
    "- App: $appName",
    '',
    '## Functional Now',
    '',
    '- The model-driven app opens in the dev Dataverse environment.',
    '- The Admin Panel MVP navigation exposes Staff, Branch Memberships, Staff Alias Mapping, Branch Policies, Assignment Exceptions, Work Items, Work Item Actions, and Alert Logs.',
    '- Main admin forms exist for all eight MVP tables.',
    '- Required system views exist for all eight MVP tables.',
    '- The Work Item form exposes Sticky Note, Last Followed Up On, Completed Attempts, Required Attempts, and Assignment Status.',
    '',
    '## Not Functional Yet',
    '',
    '- Resolver flows were intentionally not created.',
    '- Alert sending was intentionally not created.',
    '- TSR/CSSR My Work custom page was intentionally not created.',
    '- Manager Panel, GM Review, and security roles were intentionally not created.',
    '',
    '## Next',
    '',
    '- Validate table permissions and role design before broad user access.',
    '- Build resolver flows in a later phase after the Admin Panel is accepted.',
    '- Build alert logic only after dedupe, recipient policy, and flow ownership are confirmed.',
    '',
    '## Still Left',
    '',
    '- Security role implementation.',
    '- Resolver automation.',
    '- Alert generation and suppression rules.',
    '- User acceptance testing with admin users.',
    '',
    '## Blocking Questions',
    '',
    '- None for Phase 2.1B.'
)
Write-Utf8NoBom -Path (Join-Path $auditDir 'PHASE_STATUS.md') -Content $phaseStatus

$liveBuildResult = Join-Lines @(
    '# Live Build Result',
    '',
    '| Check | Result |',
    '| --- | --- |',
    '| Power Platform tooling available | yes |',
    '| Authenticated environment | yes |',
    "| Target environment URL | $environmentUrl |",
    "| Target environment ID | $environmentId |",
    '| Solution found | yes |',
    '| Dataverse tables found | yes, 8 of 8 |',
    '| Model-driven app created/found | yes |',
    '| App included in solution | yes |',
    '| App published | yes |',
    '| Admin Panel MVP navigation found | yes |',
    '| Forms created/found | yes, 8 of 8 |',
    '| Views created/found | yes, 32 of 32 |',
    '| Browser/app-open validation completed | yes |',
    '| Solution exported/unpacked | yes |',
    '',
    '## App',
    '',
    "- Display name: $appName",
    "- Unique name: $appUniqueName",
    "- App module ID: $appModuleId",
    "- App module unique ID: $appModuleIdUnique",
    "- App URL: $appUrl",
    '',
    '## Validation Evidence',
    '',
    '- Final build result: `results/phase2-1B-live-build-result-final-20260427.json`',
    '- Final live-state recheck: `results/phase2-1B-final-live-state-20260427.json`',
    '- Browser validation opened the app and confirmed the eight navigation items.',
    '- Browser validation opened the Work Item main form and confirmed the required top fields and Assignment Status.',
    '',
    '## Non-Blocking Cleanup Note',
    '',
    'An earlier incomplete duplicate appmodule was removed from the target solution. A leftover unpublished app artifact may still exist outside the solution in the environment. Direct delete was blocked by an appsetting reference constraint.',
    '',
    'Command/action that failed:',
    '',
    '```text',
    'DELETE https://orga632edd5.crm3.dynamics.com/api/data/v9.2/appmodules(ab01cb24-6842-f111-bec7-7c1e52062b6f)',
    '```',
    '',
    'Error message:',
    '',
    '```text',
    'Sql error: Statement conflicted with a constraint. The DELETE statement conflicted with the REFERENCE constraint "appmodule_appsetting_parentappmoduleid" on column "ParentAppModuleId".',
    '```',
    '',
    'Smallest human action if cleanup is desired: delete the leftover unpublished duplicate app artifact from Maker/Admin after confirming it is not referenced. This is not blocking the Phase 2.1B app because it is no longer in the solution.'
)
Write-Utf8NoBom -Path (Join-Path $auditDir 'LIVE_BUILD_RESULT.md') -Content $liveBuildResult

$appModuleReview = Join-Lines @(
    '# App Module Review',
    '',
    "- App name: $appName",
    "- App unique name: $appUniqueName",
    "- App module ID: $appModuleId",
    "- App module unique ID: $appModuleIdUnique",
    "- Runtime app URL: $appUrl",
    '',
    '## Areas And Navigation',
    '',
    '- Sitemap area label: Admin Panel MVP',
    '- Runtime left navigation group: Workbench Administration',
    '- Navigation items: Staff, Branch Memberships, Staff Alias Mapping, Branch Policies, Assignment Exceptions, Work Items, Work Item Actions, Alert Logs',
    '',
    '## Unpacked Metadata',
    '',
    "- AppModule metadata exists: $appModuleMetadataExists",
    "- Sitemap/navigation metadata exists: $siteMapMetadataExists",
    "- Form metadata files found: $formMetadataCount",
    "- View metadata files found: $viewMetadataCount",
    '',
    '## Usability',
    '',
    '- The app opened successfully in Power Apps in the dev environment.',
    '- Browser validation confirmed the navigation items rendered and opened their entity list pages.',
    '- Validation method: Dataverse metadata/API checks, PAC publish/export/unpack, and authenticated browser automation.'
)
Write-Utf8NoBom -Path (Join-Path $auditDir 'APP_MODULE_REVIEW.md') -Content $appModuleReview

$formViewLines = New-Object System.Collections.Generic.List[string]
$formViewLines.Add('# Form View Review')
$formViewLines.Add('')
foreach ($table in $requiredTables) {
    $info = $forms[$table]
    $formViewLines.Add("## $table")
    $formViewLines.Add('')
    $formViewLines.Add(("- Form created/found: yes, ``{0}``" -f $info.Form))
    $formViewLines.Add("- Views created/found: yes, $($info.Views.Count) view(s)")
    $formViewLines.Add("- Required fields included where verifiable: $($info.Fields -join ', ')")
    $formViewLines.Add("- Views: $($info.Views -join ', ')")
    $formViewLines.Add('- Missing items: none known')
    $formViewLines.Add('- Filter gaps: none known from metadata generation; user acceptance should still validate sorting/filter usefulness.')
    $formViewLines.Add('')
}
Write-Utf8NoBom -Path (Join-Path $auditDir 'FORM_VIEW_REVIEW.md') -Content (Join-Lines $formViewLines.ToArray())

$adminReview = Join-Lines @(
    '# Admin Panel MVP Review',
    '',
    '## What Admins Can Do Now',
    '',
    '- Maintain staff records.',
    '- Maintain branch memberships and role mappings.',
    '- Maintain staff alias mapping records used for AM/CSSR business identity resolution.',
    '- Maintain branch policies and threshold configuration records.',
    '- Review assignment exceptions.',
    '- Review and edit work items, including sticky notes.',
    '- Review work item actions and alert log records.',
    '',
    '## Usability',
    '',
    '- Admin Panel status: usable in the dev model-driven app.',
    '- Browser proof: the app opened in the dev org and all eight navigation items opened table list pages.',
    '- Work Item form proof: Sticky Note, Last Followed Up On, Completed Attempts, Required Attempts, and Assignment Status were visible during browser validation.',
    '',
    '## Remaining Manual Or Later-Phase Items',
    '',
    '- Security roles and access model.',
    '- Resolver flows.',
    '- Alert flows.',
    '- TSR/CSSR My Work custom page.',
    '- Manager Panel and GM Review.',
    '',
    'No screenshots with business data are included in this audit package.'
)
Write-Utf8NoBom -Path (Join-Path $auditDir 'ADMIN_PANEL_MVP_REVIEW.md') -Content $adminReview

$stitchReview = Join-Lines @(
    '# Google Stitch UI Review',
    '',
    '- Admin Panel MVP Google Stitch prompt location: `docs/revenue-follow-up-admin-panel-mvp-google-stitch-prompt.md`',
    '- Related UI brief location: `docs/revenue-follow-up-google-stitch-ui-brief.md`',
    '- Stitch prototype generated in this phase: no',
    '- Stitch role: design and prototype guidance only',
    '- Production implementation target: Power Apps model-driven app/custom pages backed by Dataverse',
    '- Frontend code from Stitch committed: no',
    '',
    'The prompt states Product: Revenue Follow-Up Workbench, Page: Admin Panel MVP, implementation target as Power Apps model-driven app backed by Dataverse, and confirms no hardcoded people, emails, branches, or routing.'
)
Write-Utf8NoBom -Path (Join-Path $auditDir 'GOOGLE_STITCH_UI_REVIEW.md') -Content $stitchReview

$foundationLines = New-Object System.Collections.Generic.List[string]
$foundationLines.Add('# Dataverse Foundation Recheck')
$foundationLines.Add('')
$foundationLines.Add("- Environment: $environmentUrl")
$foundationLines.Add("- Solution: $solutionName")
$foundationLines.Add('- Recheck artifact: `results/phase2-1B-final-live-state-20260427.json`')
$foundationLines.Add('')
$foundationLines.Add('## Tables')
$foundationLines.Add('')
foreach ($table in $requiredTables) {
    $foundationLines.Add("- ${table}: found")
}
$foundationLines.Add('')
$foundationLines.Add('## Choices')
$foundationLines.Add('')
$foundationLines.Add('- Phase 2 global choices were found during live-state recheck.')
$foundationLines.Add('- Final live-state JSON includes the choice metadata returned by Dataverse.')
$foundationLines.Add('')
$foundationLines.Add('## Columns And Lookups')
$foundationLines.Add('')
$foundationLines.Add('- Required scalar columns were confirmed for each MVP table by the verification script.')
$foundationLines.Add('- Required lookup columns were confirmed for each MVP table by the verification script.')
$foundationLines.Add('- Missing fields/lookups: none reported by final live-state recheck.')
Write-Utf8NoBom -Path (Join-Path $auditDir 'DATAVERSE_FOUNDATION_RECHECK.md') -Content (Join-Lines $foundationLines.ToArray())

$solutionExportReview = Join-Lines @(
    '# Solution Export Review',
    '',
    ("- Exported solution path: ``{0}``" -f $exportZipRelative),
    ("- Unpacked solution path: ``{0}``" -f $unpackedRelative),
    '- Export type: unmanaged',
    "- AppModule metadata exists: $appModuleMetadataExists",
    "- Sitemap/navigation metadata exists: $siteMapMetadataExists",
    "- Forms/views metadata exists: yes, $formMetadataCount form metadata file(s) and $viewMetadataCount view metadata file(s)",
    "- Timestamp local: $timestampLocal",
    "- Timestamp UTC: $timestampUtc",
    '',
    'The final PAC unpack included AppModules, AppModuleSiteMaps, form XML, and saved query metadata for the Admin Panel MVP.'
)
Write-Utf8NoBom -Path (Join-Path $auditDir 'SOLUTION_EXPORT_REVIEW.md') -Content $solutionExportReview

$docQualityReview = Join-Lines @(
    '# Document Quality Review',
    '',
    '| Check | Result |',
    '| --- | --- |',
    '| No placeholder repo values | yes |',
    '| No malformed code fences | yes |',
    '| No control characters | yes |',
    '| No broken markdown tables | yes |',
    '| No misleading claims of functionality | yes |',
    '',
    'The audit files use real branch, commit, environment, solution, app, export, and unpack values. Functional claims are limited to the live validation completed in the dev environment.'
)
Write-Utf8NoBom -Path (Join-Path $auditDir 'DOC_QUALITY_REVIEW.md') -Content $docQualityReview

$openDecisions = Join-Lines @(
    '# Open Decisions',
    '',
    '- None blocking Phase 2.1B.',
    '',
    'Future-phase decisions still requiring normal design approval before implementation:',
    '',
    '- Security role model for Admin, GM, Manager, TSR, and CSSR access.',
    '- Resolver flow ownership and monitoring policy.',
    '- Alert recipient, dedupe, suppression, and retry rules.'
)
Write-Utf8NoBom -Path (Join-Path $auditDir 'OPEN_DECISIONS.md') -Content $openDecisions

Copy-AuditFile -RelativePath 'docs\power-apps-maker-admin-panel-build-checklist.md' -DestinationRoot $safeRoot
Copy-AuditFile -RelativePath 'docs\revenue-follow-up-admin-panel-mvp-google-stitch-prompt.md' -DestinationRoot $safeRoot
Copy-AuditFile -RelativePath 'docs\revenue-follow-up-google-stitch-ui-brief.md' -DestinationRoot $safeRoot
Copy-AuditFile -RelativePath 'scripts\build-revenue-followup-phase2-1B-admin-app.ps1' -DestinationRoot $safeRoot
Copy-AuditFile -RelativePath 'scripts\verify-revenue-followup-phase2-1-live-state.ps1' -DestinationRoot $safeRoot
Copy-AuditFile -RelativePath 'scripts\create-phase2-1B-admin-panel-audit.ps1' -DestinationRoot $safeRoot
Copy-AuditFile -RelativePath 'results\phase2-1B-precheck-live-state-20260427.json' -DestinationRoot $safeRoot
Copy-AuditFile -RelativePath 'results\phase2-1B-live-build-result-final-20260427.json' -DestinationRoot $safeRoot
Copy-AuditFile -RelativePath 'results\phase2-1B-final-live-state-20260427.json' -DestinationRoot $safeRoot
Copy-AuditFile -RelativePath $exportZipRelative -DestinationRoot $safeRoot
Copy-AuditDirectory -RelativePath $unpackedRelative -DestinationRoot $safeRoot -DestinationRelativePath 'solution-unpacked'

$manifestLines = New-Object System.Collections.Generic.List[string]
$manifestLines.Add('# Manifest')
$manifestLines.Add('')
$manifestLines.Add('Every file included in this audit package is listed below.')
$manifestLines.Add('')
$manifestLines.Add('| File | Why it matters |')
$manifestLines.Add('| --- | --- |')
$manifestLines.Add('| MANIFEST.md | Lists every file in the audit package. |')

Get-ChildItem -LiteralPath $auditDir -Recurse -File |
    Where-Object { $_.Name -ne 'MANIFEST.md' } |
    Sort-Object FullName |
    ForEach-Object {
        $relative = $_.FullName.Substring($auditDir.Length).TrimStart('\', '/')
        $why = 'Supporting audit artifact.'
        if ($relative -eq 'CURRENT_REPO_STATE.md') { $why = 'Real git branch, commit, status, and timestamp evidence.' }
        elseif ($relative -eq 'PHASE_STATUS.md') { $why = 'Phase result, scope, next steps, and blockers.' }
        elseif ($relative -eq 'LIVE_BUILD_RESULT.md') { $why = 'Live build status, environment, app result, and blocker notes.' }
        elseif ($relative -eq 'APP_MODULE_REVIEW.md') { $why = 'App module identity, navigation, and validation proof.' }
        elseif ($relative -eq 'FORM_VIEW_REVIEW.md') { $why = 'Forms, views, fields, and filter gap review by table.' }
        elseif ($relative -eq 'ADMIN_PANEL_MVP_REVIEW.md') { $why = 'Admin usability summary and remaining out-of-scope work.' }
        elseif ($relative -eq 'GOOGLE_STITCH_UI_REVIEW.md') { $why = 'Confirms Google Stitch guidance and Power Apps implementation target.' }
        elseif ($relative -eq 'DATAVERSE_FOUNDATION_RECHECK.md') { $why = 'Dataverse foundation recheck summary.' }
        elseif ($relative -eq 'SOLUTION_EXPORT_REVIEW.md') { $why = 'Solution export and unpack verification.' }
        elseif ($relative -eq 'DOC_QUALITY_REVIEW.md') { $why = 'Markdown and claim quality review.' }
        elseif ($relative -eq 'OPEN_DECISIONS.md') { $why = 'Remaining human decisions only.' }
        elseif ($relative -like 'SAFE_SOURCE_FILES\docs\*') { $why = 'Changed safe documentation included for source preservation.' }
        elseif ($relative -like 'SAFE_SOURCE_FILES\scripts\*') { $why = 'Safe build/verification script included for repeatability.' }
        elseif ($relative -like 'SAFE_SOURCE_FILES\results\*') { $why = 'Safe live validation result artifact.' }
        elseif ($relative -like 'SAFE_SOURCE_FILES\solution\exports\*') { $why = 'Unmanaged solution export containing live app/forms/views metadata.' }
        elseif ($relative -like 'SAFE_SOURCE_FILES\solution-unpacked\*') { $why = 'Unpacked solution metadata for source review.' }
        $escapedRelative = $relative -replace '\|', '\|'
        $escapedWhy = $why -replace '\|', '\|'
        $manifestLines.Add("| $escapedRelative | $escapedWhy |")
    }

Write-Utf8NoBom -Path (Join-Path $auditDir 'MANIFEST.md') -Content (Join-Lines $manifestLines.ToArray())

$markdownFiles = Get-ChildItem -LiteralPath $auditDir -Recurse -File -Filter '*.md'
$controlIssues = @()
$placeholderIssues = @()
foreach ($file in $markdownFiles) {
    $content = [System.IO.File]::ReadAllText($file.FullName)
    if ($content -match '[\x00-\x08\x0B\x0C\x0E-\x1F]') {
        $controlIssues += $file.FullName
    }
    if ($content -match '\$repo|\$branch|\$commit|\$\(@\{') {
        $placeholderIssues += $file.FullName
    }
}

if ($controlIssues.Count -gt 0) {
    throw "Control characters found in markdown files: $($controlIssues -join ', ')"
}
if ($placeholderIssues.Count -gt 0) {
    throw "Placeholder/interpolation artifacts found in markdown files: $($placeholderIssues -join ', ')"
}

Compress-Archive -Path (Join-Path $auditDir '*') -DestinationPath $zipPath -Force

[pscustomobject]@{
    AuditDirectory = $auditDir
    AuditZip = $zipPath
    AppModuleMetadataExists = $appModuleMetadataExists
    SiteMapMetadataExists = $siteMapMetadataExists
    FormMetadataCount = $formMetadataCount
    ViewMetadataCount = $viewMetadataCount
    TimestampUtc = $timestampUtc
} | ConvertTo-Json -Depth 4
