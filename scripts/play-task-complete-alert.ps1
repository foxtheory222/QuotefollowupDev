[CmdletBinding()]
param(
  [int]$Repeat = 2,
  [int]$DelayMs = 220,
  [switch]$Voice,
  [string]$Message = "Codex task complete"
)

$ErrorActionPreference = "Stop"

function Invoke-Beep {
  try {
    [System.Media.SystemSounds]::Exclamation.Play()
    return
  }
  catch {
  }

  try {
    [console]::Beep(1046, 220)
  }
  catch {
  }
}

$Repeat = [Math]::Max(1, $Repeat)
$DelayMs = [Math]::Max(0, $DelayMs)

for ($i = 0; $i -lt $Repeat; $i++) {
  Invoke-Beep
  if ($i -lt ($Repeat - 1) -and $DelayMs -gt 0) {
    Start-Sleep -Milliseconds $DelayMs
  }
}

if ($Voice.IsPresent) {
  try {
    Add-Type -AssemblyName System.Speech
    $speaker = New-Object System.Speech.Synthesis.SpeechSynthesizer
    $speaker.Speak($Message)
    $speaker.Dispose()
  }
  catch {
    Write-Warning "Voice alert unavailable: $($_.Exception.Message)"
  }
}

Write-Host ("TASK_ALERT_PLAYED repeat={0} voice={1} message=""{2}""" -f $Repeat, $Voice.IsPresent.ToString().ToLowerInvariant(), $Message)
