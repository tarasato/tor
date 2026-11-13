<#
.SYNOPSIS
  Health check for the tor service and its SSH onion service. Restarts tor when it is stuck.

.DESCRIPTION
  Run every 5 minutes by the "Tor_Watchdog" scheduled task (as SYSTEM, see install-tor-watchdog.ps1).
  Each run:
    1. service "tor" is running and SOCKS 127.0.0.1:<SocksPort> is listening
    2. self-test: connects to this machine's own .onion (port 22) through tor's SOCKS port and
       expects an "SSH-" banner - this proves the onion service is published and reachable
  After <FailLimit> failed runs in a row it restarts the service (at most once per <RestartGapMin>).
  State  -> TorExpertBundle\tor\watchdog-state.json   (read by the Telegram alert)
  Log    -> TorExpertBundle\tor\watchdog.log           (last ~500 lines kept)

.PARAMETER CheckOnly
  Only check and print the result. No restart, no state/log written. Safe to run as a normal user.
#>
[CmdletBinding()]
param(
  [string]$SshServiceDir = 'TorHiddenService1',
  [int]$SocksPort = 9050,
  [int]$OnionPort = 22,
  [int]$FailLimit = 2,
  [int]$RestartGapMin = 15,
  [int]$TimeoutSec = 90,
  [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
$Repo   = Split-Path -Parent $PSScriptRoot
$TorDir = Join-Path $Repo 'TorExpertBundle\tor'
$State  = Join-Path $TorDir 'watchdog-state.json'
$Log    = Join-Path $TorDir 'watchdog.log'
$Svc    = 'tor'

function Test-OnionBanner([string]$OnionHost, [int]$Port, [int]$SocksPort, [int]$TimeoutSec) {
  # minimal SOCKS5 client: no-auth, CONNECT by domain name (tor resolves the .onion)
  $client = New-Object System.Net.Sockets.TcpClient
  try {
    $client.ReceiveTimeout = $TimeoutSec * 1000
    $client.SendTimeout = 10000
    $client.Connect('127.0.0.1', $SocksPort)
    $s = $client.GetStream()
    $s.Write([byte[]](5, 1, 0), 0, 3)
    $r = New-Object byte[] 2
    if ($s.Read($r, 0, 2) -ne 2 -or $r[0] -ne 5 -or $r[1] -ne 0) { return 'socks greeting rejected' }
    $h = [Text.Encoding]::ASCII.GetBytes($OnionHost)
    $req = [byte[]](@(5, 1, 0, 3, $h.Length) + $h + @([byte]($Port -shr 8), [byte]($Port -band 255)))
    $s.Write($req, 0, $req.Length)
    $rep = New-Object byte[] 10          # tor answers with an IPv4-style 10-byte reply
    $n = 0
    while ($n -lt 10) { $k = $s.Read($rep, $n, 10 - $n); if ($k -le 0) { break }; $n += $k }
    if ($n -lt 2) { return 'no socks reply' }
    if ($rep[1] -ne 0) { return "socks connect failed (code $($rep[1]))" }
    $buf = New-Object byte[] 64
    $k = $s.Read($buf, 0, 64)
    $banner = [Text.Encoding]::ASCII.GetString($buf, 0, [Math]::Max($k, 0))
    if ($banner -like 'SSH-*') { return 'ok' }
    return "unexpected banner '$($banner.Trim())'"
  } catch {
    return "error: $($_.Exception.Message)"
  } finally { $client.Close() }
}

function Write-Log($line) {
  $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz')
  Add-Content -Path $Log -Value "$stamp $line" -Encoding utf8
  $all = Get-Content $Log -ErrorAction SilentlyContinue
  if ($all.Count -gt 600) { $all | Select-Object -Last 500 | Set-Content $Log -Encoding utf8 }
}

# ---- checks ----
$problems = @()
$svc = Get-Service $Svc -ErrorAction SilentlyContinue
if (-not $svc)                     { $problems += 'service not installed' }
elseif ($svc.Status -ne 'Running') { $problems += "service $($svc.Status)" }
$listen = Get-NetTCPConnection -State Listen -LocalPort $SocksPort -ErrorAction SilentlyContinue
if (-not $listen)                  { $problems += "socks port $SocksPort not listening" }

$hostFile = Join-Path (Join-Path $TorDir $SshServiceDir) 'hostname'
$onion = if (Test-Path $hostFile) { (Get-Content $hostFile -Raw).Trim() } else { $null }
if (-not $onion)                   { $problems += 'no onion hostname file' }

$self = 'skipped'
if (-not $problems) {
  $self = Test-OnionBanner $onion $OnionPort $SocksPort $TimeoutSec
  if ($self -ne 'ok') { $problems += "onion self-test: $self" }
}
$ok = ($problems.Count -eq 0)
$summary = if ($ok) { 'OK onion reachable' } else { 'FAIL ' + ($problems -join '; ') }

if ($CheckOnly) { $summary; return }

# ---- state + action ----
$now = Get-Date
$st = [ordered]@{ last_ok = $null; last_check = $null; consecutive_fail = 0; last_restart = $null; last_result = '' }
if (Test-Path $State) {
  try { (Get-Content $State -Raw | ConvertFrom-Json).psobject.Properties | ForEach-Object { $st[$_.Name] = $_.Value } } catch {}
}
$st.last_check  = $now.ToString('o')
$st.last_result = $summary
if ($ok) {
  if ($st.consecutive_fail -gt 0) { Write-Log "RECOVERED after $($st.consecutive_fail) failed check(s)" }
  $st.last_ok = $now.ToString('o'); $st.consecutive_fail = 0
} else {
  $st.consecutive_fail = [int]$st.consecutive_fail + 1
  Write-Log "$summary (fail #$($st.consecutive_fail))"
  $since = if ($st.last_restart) { ($now - [datetime]$st.last_restart).TotalMinutes } else { 1e9 }
  if ($st.consecutive_fail -ge $FailLimit -and $since -ge $RestartGapMin) {
    try {
      if ($svc) { Restart-Service $Svc -Force } else { Write-Log 'cannot restart: service missing' }
      $st.last_restart = $now.ToString('o')
      Write-Log 'RESTARTED tor service'
    } catch { Write-Log "restart failed: $($_.Exception.Message)" }
  }
}
$st | ConvertTo-Json | Set-Content $State -Encoding utf8
$summary
