#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Install the tor watchdog and let a normal user restart the tor service.

.DESCRIPTION
  1. Registers scheduled task "Tor_Watchdog": runs scripts\tor-watchdog.ps1 as SYSTEM every
     5 minutes (and 3 minutes after boot). It restarts tor when the onion self-test fails twice
     in a row (at most once per 15 min) and writes watchdog-state.json / watchdog.log.
  2. Grants <GrantUser> (default: you) start / stop / query rights on the "tor" service only,
     so `Restart-Service tor` works without an admin shell. No right to change or delete it.

.PARAMETER GrantUser
  Account that may start/stop tor. Default: the user running this script. Use -GrantUser '' to skip.

.PARAMETER Uninstall
  Remove the scheduled task (the service permission is left as is).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\install-tor-watchdog.ps1
#>
[CmdletBinding()]
param(
  [string]$GrantUser = "$env:USERDOMAIN\$env:USERNAME",
  [string]$SshServiceDir = 'TorHiddenService1',
  [switch]$Uninstall
)
$ErrorActionPreference = 'Stop'
$TaskName = 'Tor_Watchdog'
$Script   = Join-Path $PSScriptRoot 'tor-watchdog.ps1'

if ($Uninstall) {
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
  Write-Host "Removed task $TaskName" -ForegroundColor Yellow
  return
}
if (-not (Test-Path $Script)) { throw "missing $Script" }
if (-not (Get-Service tor -ErrorAction SilentlyContinue)) { throw "service 'tor' not installed - run install-tor-service.ps1 first" }

# 1. scheduled task (SYSTEM, every 5 min + at boot)
Write-Host "==> Registering scheduled task $TaskName" -ForegroundColor Cyan
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
  -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$Script`" -SshServiceDir $SshServiceDir"
$every = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
$boot  = New-ScheduledTaskTrigger -AtStartup
$boot.Delay = 'PT3M'
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 4) `
  -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($every, $boot) -Principal $principal `
  -Settings $settings -Description 'Checks the tor SSH onion service every 5 min and restarts tor when stuck' -Force | Out-Null

# 2. let GrantUser start/stop/query the tor service
if ($GrantUser) {
  Write-Host "==> Allowing $GrantUser to start/stop the tor service" -ForegroundColor Cyan
  $sid = (New-Object System.Security.Principal.NTAccount($GrantUser)).Translate([System.Security.Principal.SecurityIdentifier]).Value
  $sd  = ((sc.exe sdshow tor) | Where-Object { $_ -match 'D:' } | Select-Object -First 1).Trim()
  $ace = "(A;;RPWPLCRC;;;$sid)"
  if ($sd -match [regex]::Escape(";;;$sid)")) { Write-Host "   already granted" }
  else {
    $new = $sd -replace '^D:', "D:$ace"
    sc.exe sdset tor $new | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "sc sdset failed ($LASTEXITCODE)" }
  }
}

# 3. first run now
Write-Host "==> First check (can take up to ~90 s)" -ForegroundColor Cyan
Start-ScheduledTask -TaskName $TaskName
$stateFile = Join-Path (Split-Path -Parent $PSScriptRoot) 'TorExpertBundle\tor\watchdog-state.json'
for ($i = 0; $i -lt 60; $i++) {
  Start-Sleep -Seconds 2
  if ((Get-ScheduledTask -TaskName $TaskName).State -ne 'Running' -and (Test-Path $stateFile)) { break }
}
if (Test-Path $stateFile) { Get-Content $stateFile } else { Write-Warning "no state file yet - check again in 5 min" }
Get-ScheduledTaskInfo -TaskName $TaskName | Format-List LastRunTime, LastTaskResult, NextRunTime
