param(
  [string]$TargetEnvironmentUrl = "<URL>
  [string]$Username = "<EMAIL>",
  [string]$CaptureRoot = "results\\live-zbo-mailbox-capture-20260413",
  [string[]]$BranchCodes = @("4171", "4172", "4173"),
  [string]$ReplayLabel = "Primary inbox live ZBO recovery",
  [string]$OutputJson = "results\\live-zbo-current-state-from-mailbox-capture.json",
  [string]$ParsedOutputJson = ""
)

$ErrorActionPreference = "Stop"

function Resolve-RepoPath {
  param([string]$Path)

  if ([System.IO.Path]::IsPathRooted($Path)) {
    return $Path
  }

  return Join-Path (Get-Location) $Path
}

$captureRootPath = Resolve-RepoPath -Path $CaptureRoot
$outputPath = Resolve-RepoPath -Path $OutputJson
$parsedOutputPath = if ([string]::IsNullOrWhiteSpace($ParsedOutputJson)) {
  [System.IO.Path]::ChangeExtension($outputPath, ".parsed.json")
} else {
  Resolve-RepoPath -Path $ParsedOutputJson
}

$parserScript = Join-Path (Get-Location) "scripts\\parse-zbo-mailbox-capture.py"
$repairScript = Join-Path (Get-Location) "scripts\\repair-live-current-state-from-parsed-workbooks.ps1"

$pythonArgs = @(
  $parserScript,
  "--capture-root",
  $captureRootPath,
  "--output",
  $parsedOutputPath,
  "--branches"
) + @($BranchCodes)

& python @pythonArgs
if ($LASTEXITCODE -ne 0) {
  throw "Failed to parse mailbox capture workbooks from $captureRootPath"
}

& $repairScript `
  -TargetEnvironmentUrl $TargetEnvironmentUrl `
  -Username $Username `
  -ParsedWorkbookJson $parsedOutputPath `
  -BranchCodes $BranchCodes `
  -ReplayLabel $ReplayLabel `
  -OutputJson $outputPath `
  -SkipOpsDaily `
  -SkipBudget `
  -SkipSummary `
  -SkipBatches

if ($LASTEXITCODE -ne 0) {
  throw "Failed to repair live ZBO current-state from $parsedOutputPath"
}
