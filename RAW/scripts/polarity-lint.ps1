[CmdletBinding()]
param(
  [string[]]$AuthoritativeFiles,
  [string]$ProbePath,
  [string]$OutputMarkdown,
  [string]$OutputJson
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-FirstExistingPath {
  param([string[]]$Candidates)

  foreach ($candidate in @($Candidates)) {
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
      return $candidate
    }
  }

  return $null
}

function Ensure-Directory {
  param([string]$Path)

  if (-not [string]::IsNullOrWhiteSpace($Path) -and -not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Write-Utf8File {
  param(
    [string]$Path,
    [string]$Content
  )

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return
  }

  $parent = Split-Path -Parent $Path
  Ensure-Directory $parent
  [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

if (-not $AuthoritativeFiles -or -not $AuthoritativeFiles.Count) {
  $AuthoritativeFiles = @(
    (Resolve-FirstExistingPath @(
      (Join-Path $RepoRoot "powerpages-live\operations-hub---operationhub\web-templates\qfu-regional-runtime\QFU-Regional-Runtime.webtemplate.source.html"),
      (Join-Path $RepoRoot "site\web-templates\qfu-regional-runtime\QFU-Regional-Runtime.webtemplate.source.html")
    )),
    (Resolve-FirstExistingPath @(
      (Join-Path $RepoRoot "scripts\create-southern-alberta-pilot-flow-solution.ps1"),
      (Join-Path $RepoRoot "RAW\scripts\create-southern-alberta-pilot-flow-solution.ps1")
    )),
    (Resolve-FirstExistingPath @(
      (Join-Path $RepoRoot "scripts\normalize-live-sa1300-current-budgets.ps1"),
      (Join-Path $RepoRoot "RAW\scripts\normalize-live-sa1300-current-budgets.ps1")
    )),
    (Resolve-FirstExistingPath @(
      (Join-Path $RepoRoot "scripts\repair-southern-alberta-live-dashboard-data.ps1"),
      (Join-Path $RepoRoot "RAW\scripts\repair-southern-alberta-live-dashboard-data.ps1")
    )),
    (Resolve-FirstExistingPath @(
      (Join-Path $RepoRoot "scripts\standardize-sa1300-budget-flows.py"),
      (Join-Path $RepoRoot "RAW\scripts\standardize-sa1300-budget-flows.py")
    ))
  ) | Where-Object { $_ }
}

if ([string]::IsNullOrWhiteSpace($ProbePath)) {
  $ProbePath = Resolve-FirstExistingPath @(
    (Join-Path $RepoRoot "results\portal-runtime-data-probe-20260409.json")
  )
}

if ([string]::IsNullOrWhiteSpace($OutputMarkdown)) {
  $OutputMarkdown = Join-Path $RepoRoot "VERIFICATION\polarity-lint-results.md"
}

if ([string]::IsNullOrWhiteSpace($OutputJson)) {
  $OutputJson = Join-Path $RepoRoot "VERIFICATION\polarity-lint-results.json"
}

$lintEntries = [System.Collections.Generic.List[object]]::new()
$suspicious = [System.Collections.Generic.List[object]]::new()

foreach ($file in @($AuthoritativeFiles | Sort-Object -Unique)) {
  if (-not (Test-Path -LiteralPath $file)) {
    continue
  }

  $lines = Get-Content -LiteralPath $file
  for ($i = 0; $i -lt $lines.Length; $i += 1) {
    $line = $lines[$i]
    if ($line -notmatch 'qfu_isactive|Test-BudgetRowIsActive|parseBoolean\(record && record\.qfu_isactive\)') {
      continue
    }

    $classification = "manual-review"
    if ($line -match 'qfu_isactive eq false|parseBoolean\(record && record\.qfu_isactive\) === false|return \(-not \$value\)|qfu_isactive = \$false|qfu_isactive": false') {
      $classification = "active-aware"
    } elseif ($line -match 'qfu_isactive = \$true|qfu_isactive": true') {
      $classification = "explicit-inactive-write"
    } elseif ($line -match 'qfu_isactive.*-eq\s+"(yes|no)"|qfu_isactive.*===\s*(true|false)|qfu_isactive eq true') {
      $classification = "suspicious"
    }

    $entry = [pscustomobject]@{
      file = $file
      line = $i + 1
      classification = $classification
      text = $line.Trim()
    }

    $lintEntries.Add($entry) | Out-Null
    if ($classification -eq "suspicious") {
      $suspicious.Add($entry) | Out-Null
    }
  }
}

$probeEvidence = @()
if ($ProbePath -and (Test-Path -LiteralPath $ProbePath)) {
  $probe = Get-Content -LiteralPath $ProbePath -Raw | ConvertFrom-Json
  $probeEvidence = @($probe.budgets.json.value | Where-Object {
      $_.qfu_branchcode -and $_.PSObject.Properties['qfu_isactive']
    } | Select-Object -First 6 | ForEach-Object {
      [pscustomobject]@{
        branchCode = [string]$_.qfu_branchcode
        budgetId = [string]$_.qfu_budgetid
        rawValue = $_.qfu_isactive
        formattedValue = $_.'qfu_isactive@OData.Community.Display.V1.FormattedValue'
      }
    })
}

$report = [pscustomobject]@{
  generatedOn = (Get-Date).ToString("s")
  authoritativeFiles = @($AuthoritativeFiles)
  suspiciousCount = $suspicious.Count
  matches = @($lintEntries)
  probeEvidence = @($probeEvidence)
}

$markdown = @(
  "# Polarity Lint Results",
  "",
  "- Authoritative files checked: $(@($AuthoritativeFiles).Count)",
  "- Suspicious polarity hits: $($suspicious.Count)",
  ""
)

if ($probeEvidence.Count) {
  $markdown += @(
    "## Current Portal Probe Evidence",
    "",
    "| Branch | Budget Id | Raw qfu_isactive | Formatted Label |",
    "| --- | --- | --- | --- |"
  )
  foreach ($row in $probeEvidence) {
    $markdown += "| $($row.branchCode) | $($row.budgetId) | $($row.rawValue) | $($row.formattedValue) |"
  }
  $markdown += ""
}

$grouped = $lintEntries | Group-Object classification | Sort-Object Name
foreach ($group in $grouped) {
  $markdown += @(
    "## $($group.Name)",
    ""
  )
  foreach ($entry in $group.Group) {
    $markdown += "- $($entry.file):$($entry.line): $($entry.text)"
  }
  $markdown += ""
}

Write-Utf8File -Path $OutputMarkdown -Content ($markdown -join [Environment]::NewLine)
Write-Utf8File -Path $OutputJson -Content ($report | ConvertTo-Json -Depth 8)

$report | ConvertTo-Json -Depth 8
