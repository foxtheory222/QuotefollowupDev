param(
  [string]$Url = 'https://operationhub.powerappsportals.com/southern-alberta',
  [int]$Port = 9333,
  [switch]$Wait
)

$projectRoot = Split-Path -Parent $PSScriptRoot
$launcherPath = Join-Path $PSScriptRoot 'open-operationhub-auth-browser.js'
$npxCommand = Get-Command npx.cmd -ErrorAction Stop
$argumentList = @(
  '--yes',
  '-p',
  'playwright',
  'node',
  $launcherPath,
  $Url
)

if ($Wait) {
  $env:QFU_AUTH_BROWSER_PORT = [string]$Port
  & $npxCommand.Source @argumentList
  exit $LASTEXITCODE
}

$joinedArgs = (($argumentList | ForEach-Object {
  if ($_ -match '\s') { '"' + $_ + '"' } else { $_ }
}) -join ' ')
$command = "set QFU_AUTH_BROWSER_PORT=$Port&& `"$($npxCommand.Source)`" $joinedArgs"

$process = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', $command -WorkingDirectory $projectRoot -PassThru
Write-Output ("Started OperationHub auth browser launcher. PID={0}" -f $process.Id)
