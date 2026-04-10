[CmdletBinding()]
param(
  [string]$RuntimePath = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "site\web-templates\qfu-regional-runtime\QFU-Regional-Runtime.webtemplate.source.html"),
  [string]$SiteSettingsPath = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "site\sitesetting.yml"),
  [string]$OutputMarkdown
)

$ErrorActionPreference = "Stop"

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

  $parent = Split-Path -Parent $Path
  Ensure-Directory $parent
  [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

$entityMap = @{
  qfu_quotes = "qfu_quote"
  qfu_backorders = "qfu_backorder"
  qfu_budgets = "qfu_budget"
  qfu_budgetarchives = "qfu_budgetarchive"
  qfu_branchdailysummaries = "qfu_branchdailysummary"
  qfu_financesnapshots = "qfu_financesnapshot"
  qfu_financevariances = "qfu_financevariance"
  qfu_marginexceptions = "qfu_marginexception"
  qfu_lateorderexceptions = "qfu_lateorderexception"
  qfu_branchs = "qfu_branch"
  qfu_regions = "qfu_region"
  qfu_sourcefeeds = "qfu_sourcefeed"
  qfu_ingestionbatchs = "qfu_ingestionbatch"
  qfu_deliverynotpgis = "qfu_deliverynotpgi"
  qfu_quotelines = "qfu_quoteline"
}

$runtimeText = Get-Content -LiteralPath $RuntimePath -Raw
$siteSettingLines = Get-Content -LiteralPath $SiteSettingsPath

$runtimeFieldsByTable = @{}
$runtimeMatches = [regex]::Matches($runtimeText, '/_api/(?<entity>qfu_[a-z0-9]+)\?\$select=(?<fields>[^"&]+)')
foreach ($match in $runtimeMatches) {
  $entitySet = $match.Groups["entity"].Value
  if (-not $entityMap.ContainsKey($entitySet)) {
    continue
  }
  $table = $entityMap[$entitySet]
  if (-not $runtimeFieldsByTable.ContainsKey($table)) {
    $runtimeFieldsByTable[$table] = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
  }
  foreach ($field in ($match.Groups["fields"].Value -split ",")) {
    $trimmed = $field.Trim()
    if ($trimmed) {
      [void]$runtimeFieldsByTable[$table].Add($trimmed)
    }
  }
}

$allowListByTable = @{}
for ($i = 0; $i -lt $siteSettingLines.Length; $i += 1) {
  $line = $siteSettingLines[$i]
  if ($line -match 'adx_name:\s+Webapi/([^/]+)/fields') {
    $table = $matches[1]
    for ($j = $i + 1; $j -lt [Math]::Min($siteSettingLines.Length, $i + 6); $j += 1) {
      if ($siteSettingLines[$j] -match 'adx_value:\s+(.+)$') {
        $allowListByTable[$table] = @($matches[1].Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        break
      }
    }
  }
}

$tables = @($runtimeFieldsByTable.Keys + $allowListByTable.Keys | Sort-Object -Unique)
$rows = foreach ($table in $tables) {
  $runtimeFields = if ($runtimeFieldsByTable.ContainsKey($table)) { @($runtimeFieldsByTable[$table]) | Sort-Object } else { @() }
  $allowFields = if ($allowListByTable.ContainsKey($table)) { @($allowListByTable[$table]) | Sort-Object } else { @() }
  $missing = @($runtimeFields | Where-Object { $_ -notin $allowFields })
  $extra = @($allowFields | Where-Object { $_ -notin $runtimeFields })

  [pscustomobject]@{
    table = $table
    runtimeFieldCount = $runtimeFields.Count
    allowListFieldCount = $allowFields.Count
    missingFields = $missing
    extraFields = $extra
  }
}

$markdown = @(
  "# Runtime vs Web API Allow-List Lint",
  "",
  "- Runtime: $RuntimePath",
  "- Site settings: $SiteSettingsPath",
  ""
)

foreach ($row in $rows) {
  $markdown += @(
    "## $($row.table)",
    "",
    "- Runtime fields: $($row.runtimeFieldCount)",
    "- Allow-list fields: $($row.allowListFieldCount)",
    "- Missing in allow-list: $($(if ($row.missingFields.Count) { $row.missingFields -join ', ' } else { 'None' }))",
    "- Extra in allow-list: $($(if ($row.extraFields.Count) { $row.extraFields -join ', ' } else { 'None' }))",
    ""
  )
}

if ($OutputMarkdown) {
  Write-Utf8File -Path $OutputMarkdown -Content ($markdown -join [Environment]::NewLine)
}

$rows | ConvertTo-Json -Depth 6
