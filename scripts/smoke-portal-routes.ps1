[CmdletBinding()]
param(
  [string]$BaseUrl = "https://quoteoperations.powerappsportals.com",
  [string]$Session = "qfu-dev",
  [string]$OutputJson = "output\\phase0\\portal-route-smoke.json",
  [string]$OutputMarkdown = "output\\phase0\\portal-route-smoke.md"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-RepoPath {
  param([string]$Path)

  if ([System.IO.Path]::IsPathRooted($Path)) {
    return $Path
  }

  return Join-Path $RepoRoot $Path
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

  $resolved = Resolve-RepoPath -Path $Path
  $directory = Split-Path -Parent $resolved
  Ensure-Directory $directory
  [System.IO.File]::WriteAllText($resolved, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Invoke-PlaywrightCli {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  $allArgs = @("--yes", "--package", "@playwright/cli", "playwright-cli", "--session", $Session) + $Arguments
  $output = & npx @allArgs 2>&1
  return [pscustomobject]@{
    ExitCode = $LASTEXITCODE
    Output = ($output | Out-String)
  }
}

function Navigate-WithinSession {
  param([string]$Url)

  $script = @"
await page.goto('$Url', { waitUntil: 'domcontentloaded' });
await page.waitForTimeout(1500);
"@
  $result = Invoke-PlaywrightCli -Arguments @("run-code", $script)
  if ($result.ExitCode -ne 0) {
    throw "Playwright navigation failed for $Url`n$($result.Output)"
  }
  return $result
}

function Get-EvalJson {
  param([string]$Url)

  $payload = "JSON.stringify({url:location.href,title:document.title,signedIn:document.body.innerText.includes('Signed in as'),hasPageNotFound:document.body.innerText.includes('Page Not Found'),hasLoadingShell:document.body.innerText.includes('Loading'),hasRuntimeFailed:document.body.innerText.includes('Runtime failed'),hasBranchNavigation:document.body.innerText.includes('Branch Navigation'),hasAdminPanelLink:document.body.innerText.includes('Admin Panel'),hasManagerPanelLink:document.body.innerText.includes('Manager Panel'),h1:(document.querySelector('h1') ? document.querySelector('h1').innerText.trim() : ''),excerpt:document.body.innerText.slice(0,1500)})"
  $evalResult = Invoke-PlaywrightCli -Arguments @("eval", $payload)
  if ($evalResult.ExitCode -ne 0) {
    throw "Playwright eval failed for $Url`n$($evalResult.Output)"
  }

  $lines = @($evalResult.Output -split "`r?`n")
  $resultLineIndex = [Array]::IndexOf($lines, "### Result")
  if ($resultLineIndex -lt 0 -or $resultLineIndex + 1 -ge $lines.Length) {
    throw "Could not parse Playwright eval output for $Url`n$($evalResult.Output)"
  }

  $jsonLine = $lines[$resultLineIndex + 1].Trim()
  if ($jsonLine.StartsWith('"') -and $jsonLine.EndsWith('"')) {
    $jsonLine = ($jsonLine | ConvertFrom-Json)
  }

  return ($jsonLine | ConvertFrom-Json)
}

$routes = @(
  [pscustomobject]@{ Slug = "root"; Route = "/" },
  [pscustomobject]@{ Slug = "region-southern-alberta"; Route = "/southern-alberta/" },
  [pscustomobject]@{ Slug = "branch-4171"; Route = "/southern-alberta/4171-calgary/" },
  [pscustomobject]@{ Slug = "detail-follow-up-queue"; Route = "/southern-alberta/4171-calgary/detail?view=follow-up-queue" },
  [pscustomobject]@{ Slug = "detail-quotes"; Route = "/southern-alberta/4171-calgary/detail?view=quotes" },
  [pscustomobject]@{ Slug = "detail-overdue-backorders"; Route = "/southern-alberta/4171-calgary/detail?view=overdue-backorders" },
  [pscustomobject]@{ Slug = "detail-ready-to-ship"; Route = "/southern-alberta/4171-calgary/detail?view=ready-to-ship-not-pgid" },
  [pscustomobject]@{ Slug = "detail-team-progress"; Route = "/southern-alberta/4171-calgary/detail?view=team-progress" },
  [pscustomobject]@{ Slug = "detail-analytics"; Route = "/southern-alberta/4171-calgary/detail?view=analytics" }
)

$results = foreach ($route in $routes) {
  $url = $BaseUrl.TrimEnd("/") + $route.Route
  $navigateResult = Navigate-WithinSession -Url $url
  $page = Get-EvalJson -Url $url
  [pscustomobject]@{
    slug = $route.Slug
    expectedUrl = $url
    actualUrl = $page.url
    title = $page.title
    h1 = $page.h1
    signedIn = [bool]$page.signedIn
    hasPageNotFound = [bool]$page.hasPageNotFound
    hasLoadingShell = [bool]$page.hasLoadingShell
    hasRuntimeFailed = [bool]$page.hasRuntimeFailed
    hasBranchNavigation = [bool]$page.hasBranchNavigation
    hasAdminPanelLink = [bool]$page.hasAdminPanelLink
    hasManagerPanelLink = [bool]$page.hasManagerPanelLink
    navigateExitCode = $navigateResult.ExitCode
    excerpt = [string]$page.excerpt
  }
}

$report = [pscustomobject]@{
  generatedAt = (Get-Date).ToString("o")
  baseUrl = $BaseUrl
  session = $Session
  routes = @($results)
}

$markdown = @(
  "# Portal Route Smoke",
  "",
  "- Generated: $($report.generatedAt)",
  "- Base URL: $BaseUrl",
  "- Session: $Session",
  "",
  "| Route | Title | H1 | Signed In | 404 | Loading | Runtime Failed | Admin Link | Manager Link |",
  "| --- | --- | --- | --- | --- | --- | --- | --- | --- |"
)

foreach ($row in $results) {
  $markdown += "| $($row.slug) | $($row.title) | $($row.h1) | $($row.signedIn) | $($row.hasPageNotFound) | $($row.hasLoadingShell) | $($row.hasRuntimeFailed) | $($row.hasAdminPanelLink) | $($row.hasManagerPanelLink) |"
}

Write-Utf8File -Path $OutputJson -Content ($report | ConvertTo-Json -Depth 8)
Write-Utf8File -Path $OutputMarkdown -Content ($markdown -join [Environment]::NewLine)

Write-Host "JSON_PATH=$(Resolve-RepoPath -Path $OutputJson)"
Write-Host "MARKDOWN_PATH=$(Resolve-RepoPath -Path $OutputMarkdown)"
