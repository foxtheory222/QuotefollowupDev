[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$LiveDownloadPath,

  [Parameter(Mandatory = $true)]
  [string]$UploadPath
)

$ErrorActionPreference = "Stop"

function Resolve-RepoPath {
  param([string]$Path)

  if ([System.IO.Path]::IsPathRooted($Path)) {
    return $Path
  }

  return Join-Path (Get-Location) $Path
}

function Get-YamlValue {
  param(
    [string[]]$Lines,
    [string]$Key
  )

  $line = $Lines | Where-Object { $_ -match ('^' + [regex]::Escape($Key) + '\s*:') } | Select-Object -First 1
  if (-not $line) {
    return $null
  }

  return (($line -replace ('^' + [regex]::Escape($Key) + '\s*:\s*'), '')).Trim()
}

function Get-YamlList {
  param(
    [string[]]$Lines,
    [string]$Key
  )

  $values = New-Object System.Collections.Generic.List[string]
  $startIndex = -1

  for ($i = 0; $i -lt $Lines.Length; $i++) {
    if ($Lines[$i] -match ('^' + [regex]::Escape($Key) + '\s*:')) {
      $startIndex = $i + 1
      break
    }
  }

  if ($startIndex -lt 0) {
    return @()
  }

  for ($i = $startIndex; $i -lt $Lines.Length; $i++) {
    $line = $Lines[$i]
    if ($line -match '^\S') {
      break
    }
    if ($line -match '^\s*-\s*(.+?)\s*$') {
      $values.Add($Matches[1].Trim())
      continue
    }
    if ($line.Trim().Length -gt 0) {
      break
    }
  }

  return @($values)
}

function Set-YamlScalar {
  param(
    [string[]]$Lines,
    [string]$Key,
    [string]$Value
  )

  for ($i = 0; $i -lt $Lines.Length; $i++) {
    if ($Lines[$i] -match ('^' + [regex]::Escape($Key) + '\s*:')) {
      $Lines[$i] = "${Key}: $Value"
      return ,$Lines
    }
  }

  return @($Lines + "${Key}: $Value")
}

function Set-YamlList {
  param(
    [string[]]$Lines,
    [string]$Key,
    [string[]]$Values
  )

  $startIndex = -1
  $endIndex = -1

  for ($i = 0; $i -lt $Lines.Length; $i++) {
    if ($Lines[$i] -match ('^' + [regex]::Escape($Key) + '\s*:')) {
      $startIndex = $i
      $endIndex = $i
      for ($j = $i + 1; $j -lt $Lines.Length; $j++) {
        if ($Lines[$j] -match '^\S') {
          break
        }
        $endIndex = $j
      }
      break
    }
  }

  $replacement = @($Key + ':') + ($Values | ForEach-Object { '- ' + $_ })

  if ($startIndex -ge 0) {
    $before = if ($startIndex -gt 0) { $Lines[0..($startIndex - 1)] } else { @() }
    $after = if ($endIndex + 1 -lt $Lines.Length) { $Lines[($endIndex + 1)..($Lines.Length - 1)] } else { @() }
    return @($before + $replacement + $after)
  }

  return @($Lines + $replacement)
}

$liveRoot = Resolve-RepoPath -Path $LiveDownloadPath
$uploadRoot = Resolve-RepoPath -Path $UploadPath

if (-not (Test-Path -LiteralPath $liveRoot)) {
  throw "Live download path not found: $liveRoot"
}

if (-not (Test-Path -LiteralPath $uploadRoot)) {
  throw "Upload path not found: $uploadRoot"
}

$report = Get-ChildItem -LiteralPath $liveRoot -Filter '*.yml' | Sort-Object Name | ForEach-Object {
  $livePath = $_.FullName
  $uploadPath = Join-Path $uploadRoot $_.Name

  if (-not (Test-Path -LiteralPath $uploadPath)) {
    return [pscustomobject]@{
      File = $_.Name
      Status = "missing-upload-file"
      LiveId = $null
      UploadId = $null
      WebRoleCount = 0
    }
  }

  $liveLines = Get-Content -LiteralPath $livePath
  $uploadLines = Get-Content -LiteralPath $uploadPath
  $liveId = Get-YamlValue -Lines $liveLines -Key 'adx_entitypermissionid'
  $uploadId = Get-YamlValue -Lines $uploadLines -Key 'adx_entitypermissionid'
  $uploadRoles = Get-YamlList -Lines $uploadLines -Key 'adx_entitypermission_webrole'

  $newLines = $uploadLines
  if ($liveId) {
    $newLines = Set-YamlScalar -Lines $newLines -Key 'adx_entitypermissionid' -Value $liveId
  }
  if ($uploadRoles.Count -gt 0) {
    $newLines = Set-YamlList -Lines $newLines -Key 'adx_entitypermission_webrole' -Values $uploadRoles
  }

  [System.IO.File]::WriteAllLines($uploadPath, $newLines, [System.Text.UTF8Encoding]::new($false))

  [pscustomobject]@{
    File = $_.Name
    Status = if ($liveId -and $uploadId -and $liveId -ne $uploadId) { "synced-id-and-webroles" } else { "webroles-restated" }
    LiveId = $liveId
    UploadId = $uploadId
    WebRoleCount = $uploadRoles.Count
  }
}

$report | Format-Table -AutoSize
