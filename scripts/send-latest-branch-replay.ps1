param(
  [string]$LatestRoot = "C:\Users\smcfarlane\Desktop\WorkBench\QuoteFollowUpRegion\Latest",
  [Alias("BranchCodes")]
  [string[]]$Branches = @("4171", "4172", "4173"),
  [string[]]$Families = @(),
  [int]$RepeatCount = 1,
  [int]$PauseSeconds = 5,
  [string]$OutputPath = "results\latest-branch-replay-send-summary.json",
  [switch]$AllowProductionReplay,
  [switch]$AllowDuplicateReplay,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

if ($RepeatCount -lt 1) {
  throw "RepeatCount must be at least 1."
}

if (-not $DryRun -and -not $AllowProductionReplay) {
  throw "Latest replay is blocked by default because it can duplicate or overwrite live current-state. Re-run with -AllowProductionReplay only for an intentional production replay."
}

if ($RepeatCount -gt 1 -and -not $AllowDuplicateReplay) {
  throw "RepeatCount greater than 1 is blocked by default because it can duplicate current-state imports. Re-run with -AllowDuplicateReplay only when an intentional duplicate replay is required."
}

function Ensure-Directory {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Normalize-StringArray {
  param([string[]]$Values)

  $set = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($value in @($Values)) {
    foreach ($candidate in @(([string]$value) -split ",")) {
      $trimmed = [string]$candidate
      if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
        [void]$set.Add($trimmed.Trim())
      }
    }
  }

  return @($set)
}

function Get-FamilySpecs {
  return @(
    [pscustomobject]@{
      Family = "SP830CA"
      AttachmentPattern = "*SP830*.xlsx"
      Subject = "SP830-Excel Report"
    },
    [pscustomobject]@{
      Family = "ZBO"
      AttachmentPattern = "*ZBO*.xlsx"
      Subject = $null
    },
    [pscustomobject]@{
      Family = "SA1300"
      AttachmentPattern = "SA1300*.xlsx"
      Subject = "SA1300-Excel Report"
    }
  )
}

function Get-BranchAttachments {
  param(
    [string]$Root,
    [string]$BranchCode
  )

  $branchPath = Join-Path $Root $BranchCode
  if (-not (Test-Path -LiteralPath $branchPath)) {
    throw "Branch folder not found: $branchPath"
  }

  $files = @(Get-ChildItem -LiteralPath $branchPath -File | Sort-Object Name)
  if ($files.Count -eq 0) {
    throw "No files found for branch $BranchCode in $branchPath"
  }

  return $files
}

function Get-BranchFamilyAttachment {
  param(
    [string]$Root,
    [string]$BranchCode,
    [object]$FamilySpec
  )

  $branchPath = Join-Path $Root $BranchCode
  if (-not (Test-Path -LiteralPath $branchPath)) {
    throw "Branch folder not found: $branchPath"
  }

  $attachment = Get-ChildItem -LiteralPath $branchPath -Filter $FamilySpec.AttachmentPattern -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if (-not $attachment) {
    throw "No $($FamilySpec.Family) attachment matched $($FamilySpec.AttachmentPattern) in $branchPath"
  }

  $subject = if ([string]::IsNullOrWhiteSpace([string]$FamilySpec.Subject)) {
    switch ($FamilySpec.Family.ToUpperInvariant()) {
      "ZBO" { "Daily Backorder Report $BranchCode" }
      default { throw "No subject mapping defined for $($FamilySpec.Family)." }
    }
  } else {
    [string]$FamilySpec.Subject
  }

  return [pscustomobject]@{
    Branch = $BranchCode
    Family = [string]$FamilySpec.Family
    Recipient = "$BranchCode@applied.com"
    Subject = $subject
    Attachments = @($attachment)
  }
}

function Write-Utf8Json {
  param(
    [string]$Path,
    [object]$Object
  )

  $fullPath = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path -Path (Get-Location).Path -ChildPath $Path }
  $parent = Split-Path -Parent $fullPath
  if ($parent) {
    Ensure-Directory -Path $parent
  }

  $json = $Object | ConvertTo-Json -Depth 20
  [System.IO.File]::WriteAllText([string]$fullPath, [string]$json, [System.Text.UTF8Encoding]::new($false))
  return $fullPath
}

$selectedFamilies = Normalize-StringArray -Values $Families
$familySpecs = Get-FamilySpecs
$outlook = $null
if (-not $DryRun) {
  $outlook = New-Object -ComObject Outlook.Application
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$summary = New-Object System.Collections.Generic.List[object]

foreach ($branch in $Branches) {
  $branchRuns = if ($selectedFamilies.Count -gt 0) {
    foreach ($family in $selectedFamilies) {
      $familySpec = $familySpecs | Where-Object { $_.Family -eq $family } | Select-Object -First 1
      if (-not $familySpec) {
        throw "Unsupported family for latest replay: $family"
      }
      Get-BranchFamilyAttachment -Root $LatestRoot -BranchCode $branch -FamilySpec $familySpec
    }
  } else {
    @([pscustomobject]@{
        Branch = $branch
        Family = "ALL"
        Recipient = "$branch@applied.com"
        Subject = "QFU replay $branch pass {0} $timestamp"
        Attachments = @(Get-BranchAttachments -Root $LatestRoot -BranchCode $branch)
      })
  }

  foreach ($runSpec in @($branchRuns)) {
    for ($pass = 1; $pass -le $RepeatCount; $pass += 1) {
      $subject = if ($runSpec.Family -eq "ALL") {
        [string]::Format($runSpec.Subject, $pass)
      } else {
        [string]$runSpec.Subject
      }
      $body = @"
Automated QFU replay for branch $branch.

Pass: $pass of $RepeatCount
Family: $($runSpec.Family)
Attachments: $($runSpec.Attachments.Count)
Source folder: $(Join-Path $LatestRoot $branch)
"@

      if (-not $DryRun) {
        $mail = $outlook.CreateItem(0)
        $mail.To = $runSpec.Recipient
        $mail.Subject = $subject
        $mail.Body = $body

        foreach ($file in @($runSpec.Attachments)) {
          [void]$mail.Attachments.Add($file.FullName)
        }

        $mail.Send()
      }

      $summary.Add([pscustomobject]@{
        branch = $branch
        family = $runSpec.Family
        recipient = $runSpec.Recipient
        pass = $pass
        subject = $subject
        production_replay_allowed = [bool]$AllowProductionReplay
        dry_run = [bool]$DryRun
        attachment_count = $runSpec.Attachments.Count
        attachments = @($runSpec.Attachments | ForEach-Object { $_.Name })
        sent_at = (Get-Date).ToUniversalTime().ToString("o")
      }) | Out-Null

      if ($pass -lt $RepeatCount -and $PauseSeconds -gt 0) {
        Start-Sleep -Seconds $PauseSeconds
      }
    }
  }
}

$report = [ordered]@{
  latest_root = $LatestRoot
  branches = @($Branches)
  families = @($selectedFamilies)
  repeat_count = $RepeatCount
  production_replay_allowed = [bool]$AllowProductionReplay
  dry_run = [bool]$DryRun
  runs = @($summary.ToArray())
}

$savedPath = Write-Utf8Json -Path $OutputPath -Object $report

Write-Host "OUTPUT_PATH=$savedPath"
