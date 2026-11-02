#Requires -Version 3.0
<#
.SYNOPSIS
    Rates how strongly this Windows machine appears to be defended, and
    produces the Decision Gate 1 one-line threat rating.

.DESCRIPTION
    Inventories the watchers (EDR/XDR processes and services, registered AV,
    Defender posture, credential protection, logging and policy depth, egress
    shaping, and mid-incident smells) and converts them into a 1-10 rating
    with one of three bands that map directly to the Phase 5 comms table:

        Rating  Band       Comms tempo (Phase 5)
        1-3     Legacy     faster acceptable; audit flips without notice
        4-6     Moderate   measured tempo
        7-10    Watched    long-haul, identity-first, small tasking

    Raw evidence is scored around zero (positive points = watched signals,
    negative points = legacy/open signals); +5 is then added to shift
    "no evidence either way" to the neutral 5. Every matched signal is
    listed with the points it added or subtracted, so the verdict is
    auditable and the weights are easy to tweak after lab runs.

    The script is read-only: CIM/WMI, registry, and certificate store reads
    only. It deliberately spawns NOTHING - netsh.exe, sc.exe, tasklist.exe,
    and wevtutil.exe are all replaced by in-process equivalents, per the
    Phase 1 ground rules.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-ThreatRating.ps1

.EXAMPLE
    # Add one justified reachability test against your redirector (-Port 443)
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-ThreatRating.ps1 -Redirector c2.example.com

.NOTES
    Read-only; no admin required for most signals. A few reads (LSA keys,
    DeviceGuard namespace on some builds) may return nothing without
    elevation - missing evidence scores neutral and is listed as "not
    visible", never as "not configured". Run elevated when you can.

    Design notes for tricky cases:
      - Block-vs-audit mode can NOT be proven passively. This script guesses:
        RTP on + tamper on + a cloud sensor (MDE Sense, CrowdStrike, S1,
        etc.) is treated as "block-guess"; product present but RTP/tamper
        off is treated as "audit-guess". The guess is printed, not hidden.
      - SenseIR.exe / SenseCNR.exe are MDE investigation/remediation
        processes. Their presence means MDE is actively working THIS host -
        scored as an incident multiplier, not as ordinary sensor presence.
      - winhttp proxy is read from the registry binary
        (HKLM\...\Internet Settings\Connections\WinHttpSettings) instead of
        spawning netsh.exe. The binary layout is undocumented; the proxy
        string is extracted at the community-documented offset 8 and the raw
        finding is printed so you can verify against netsh output in the lab.
      - The TLS-inspection check matches corporate-sounding issuing CAs
        (Zscaler/Netskope/Forti/etc.). Matching bare "CA" was rejected
        because public roots like "DigiCert Global Root CA" would
        false-positive on every patched machine on earth.
      - SecurityServicesRunning integer mapping (1 vs 2 for Credential
        Guard) is inconsistent across documentation. This script treats 2 as
        Credential Guard to match the course notes, cross-checks against
        LsaCfgFlags, and prints the raw integers so the lab can verify.
      - This script is one long ScriptBlock-logging confession on a box
        where section 1.4 found EnableScriptBlockLogging=1. From a beacon,
        prefer inlining it; from disk, prefer staging before the engagement.
        The course doctrine applies to the course tooling.
#>
[CmdletBinding()]
param(
    # Optional: your redirector FQDN for ONE justified reachability test
    # (TCP 443). Empty = skip the test entirely, which is the default.
    [string]$Redirector = ''
)

$ErrorActionPreference = 'SilentlyContinue'

$script:score   = 0
$script:reasons = New-Object System.Collections.Generic.List[string]

function Add-Signal {
    param(
        [int]$Points,
        [string]$Why
    )
    $script:score += $Points
    [void]$script:reasons.Add(('{0:+0;-0;0}' -f $Points, $Why))
}

# ---------------------------- signal patterns ------------------------------
# Running security products (process names). MDE pieces are separated out
# because SenseIR/SenseCNR mean active investigation, not just presence.
$edrProcessPattern   = 'MsMpEng|csagent|csfalcon|SentinelAgent|SentinelOne|elastic-endpoint|edpa|fcags|Tanium|CbDefense|CarbonBlack|ossec|wazuh|qualys|TMBMSRV|Sophos|bdagent|avp|xagt|mdatp|Cylance|cybereason'
$mdePresencePattern = 'MsMpEng|MsSense|^Sense$|SenseCM'
$mdeActivePattern   = 'SenseIR|SenseCNR'

# Log shippers are scored separately from EDR: a beat means a pipeline
# exists, which means a SOC exists - telemetry without enforcement.
$shipperPattern     = 'winlogbeat|filebeat'

# Security services worth naming in the evidence list.
$edrServicePattern = 'windefend|sense$|csagent|sentinel|tanium|elastic|qualys|sav$|macmnsvc|CylanceSvc|cybereason'

# Threat-hunt agents: presence implies a hunt program, not just endpoint
# protection - that is the incident multiplier, and it is worth more.
$huntPattern = 'Velociraptor|osqueryd|ir-agent|Tanium'

# Recently-installed security software under Program Files.
$secDirPattern = 'Defender|CrowdStrike|Sentinel|Sophos|Tanium|Velociraptor|osquery|Carbon|Cybereason|Cylance|FireEye|Mandiant|Qualys|Elastic|Wazuh|Rapid7|Vectra|Extrahop|Huntress'

# Corporate TLS-interception issuing CAs. Deliberately NOT bare 'CA'.
$tlsCaPattern = 'Zscaler|Netskope|Forti|Blue Coat|Palo Alto|Inspect|WEBFILTER|Interception|Squid|Proxy'

# ------------------------------- data harvest -------------------------------
$isElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

$processes = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -match "$edrProcessPattern|$mdePresencePattern|$mdeActivePattern|$shipperPattern" } | Select-Object -ExpandProperty Name)
$services  = @(Get-CimInstance Win32_Service | ForEach-Object { $_.Name })
$avProducts = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct | Select-Object -ExpandProperty displayName)

try { $mp = Get-MpComputerStatus } catch { $mp = $null }

# ----------------------- evidence: EDR / AV presence ------------------------
$mdeActive   = @($processes | Where-Object { $_ -match $mdeActivePattern })
$mdePresent  = ($processes | Where-Object { $_ -match $mdePresencePattern }).Count -gt 0 -or
               (@($services | Where-Object { $_ -match '^sense$' })).Count -gt 0
$otherEdr    = @($processes | Where-Object { $_ -match $edrProcessPattern })
$edrServices = @($services | Where-Object { $_ -match $edrServicePattern })

if ($mdeActive.Count -gt 0) {
    Add-Signal 2 "MDE investigation process '$($mdeActive[0])' is running - active IR on THIS host (incident multiplier)"
}
if ($mdePresent) {
    Add-Signal 4 "Defender plus MDE cloud sensor present (Sense/MsMpEng) - cloud analytics, block-mode guess"
}
elseif ($otherEdr.Count -gt 0) {
    Add-Signal 3 "Third-party EDR process '$($otherEdr[0])' present - block-mode guess"
}
$shippers = @($processes | Where-Object { $_ -match $shipperPattern })
if ($shippers.Count -gt 0 -and $otherEdr.Count -eq 0) {
    Add-Signal 2 "Log shipper '$($shippers[0])' present - a log pipeline exists, so a SOC exists"
}

if ($avProducts.Count -gt 0) {
    Add-Signal 1 "Registered AV product(s): $($avProducts -join ', ')"
}

# -------------------------- evidence: Defender posture ----------------------
if ($mp) {
    if ($mp.RealTimeProtectionEnabled)     { Add-Signal 2 "Defender RealTimeProtectionEnabled = True" }
    else                                   { Add-Signal -1 "Defender present but RTP is OFF - audit/disabled posture" }
    if ($mp.BehaviorMonitorEnabled)        { Add-Signal 1 "Defender BehaviorMonitorEnabled = True" }
    if ($mp.NISEnabled)                    { Add-Signal 1 "Defender NISEnabled = True (network inspection)" }
    if ($mp.TamperProtected)               { Add-Signal 1 "Defender TamperProtected = True - do not touch the product" }
    if ($mp.AntivirusSignatureLastUpdated -gt (Get-Date).AddHours(-36)) {
        Add-Signal 1 "Signatures fresh ($($mp.AntivirusSignatureLastUpdated)) - actively managed fleet"
    }
}
elseif ($avProducts.Count -gt 0) {
    Add-Signal 0 "Get-MpComputerStatus unavailable (non-Defender AV or no access); Defender posture unknown"
}

if ($processes.Count -eq 0 -and $avProducts.Count -eq 0) {
    Add-Signal -2 "No security product processes and nothing registered in SecurityCenter2"
}

# ---------------------- evidence: credential protection ---------------------
$lsa       = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
$lsaCfg    = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name LsaCfgFlags
$runAsPPL  = $lsa.RunAsPPL
$cgFlags   = if ($lsaCfg) { [int]$lsaCfg.LsaCfgFlags } else { $null }

$dg = $null
try {
    $dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard
} catch { $dg = $null }

$secServicesRunning = @()
$vbsRunning = $false
if ($dg) {
    $secServicesRunning = @($dg.SecurityServicesRunning)
    $vbsRunning = ($dg.VirtualizationBasedSecurityStatus -eq 2)
}

# Cross-check: LsaCfgFlags >= 1 or SecurityServicesRunning containing 2 both
# indicate Credential Guard (2 matches the course notes; raw values printed).
$credGuardRunning = ($cgFlags -ge 1) -or ($secServicesRunning -contains 2)

if ($runAsPPL -eq 1)   { Add-Signal 2 "RunAsPPL = 1 - LSASS runs as protected process" }
if ($credGuardRunning) {
    Add-Signal 3 "Credential Guard active (LsaCfgFlags=$cgFlags SecurityServicesRunning=$($secServicesRunning -join ',')) - shift to tickets/tokens, not hashes"
}
elseif ($vbsRunning)   { Add-Signal 1 "VBS running without Credential Guard (SecurityServicesRunning=$($secServicesRunning -join ','))" }
if (-not $lsa)         { Add-Signal 0 "LSA key not visible (not elevated?) - PPL/CG state unknown, scored neutral" }

# ------------------------ evidence: logging and policy ----------------------
$languageMode = $ExecutionContext.SessionState.LanguageMode
if ($languageMode -eq 'ConstrainedLanguage') {
    Add-Signal 3 "PowerShell LanguageMode = ConstrainedLanguage - tooling menu shrinks hard"
}
elseif ($languageMode -eq 'FullLanguage') {
    Add-Signal 0 "LanguageMode = FullLanguage"
}

$sbl = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'
if ($sbl.EnableScriptBlockLogging -eq 1) {
    Add-Signal 2 "EnableScriptBlockLogging = 1 - every command string reaches the SIEM"
}
$mod = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging'
if ($mod.EnableModuleLogging -eq 1) {
    Add-Signal 1 "EnableModuleLogging = 1"
}
$trn = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription'
if ($trn.EnableTranscripting -eq 1) {
    Add-Signal 1 "PowerShell Transcription enabled - script contents are being written to disk"
}

# AppLocker: cmdlet first (needs module/elevation), registry fallback.
$appLockerXml = $null
try { $appLockerXml = Get-AppLockerPolicy -Effective -Xml } catch { $appLockerXml = $null }
if ($appLockerXml -match 'EnforcementMode="Enabled"') {
    Add-Signal 3 "AppLocker enforce-mode rules present - dropper menu is constrained"
}
elseif ($appLockerXml -match 'EnforcementMode="AuditOnly"') {
    Add-Signal 1 "AppLocker audit-only - assume the rules are being read"
}
elseif (Test-Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SrpV2') {
    Add-Signal 1 "SrpV2 policy keys exist (AppLocker/WDAC via policy); effective mode unreadable without the module"
}

# WDAC: enforced code-integrity policies on disk.
$wdacActive = (Test-Path 'C:\Windows\System32\CodeIntegrity\CiPolicies\Active') -or
              (Test-Path 'C:\Windows\System32\CodeIntegrity\SiPolicy.p7b')
if ($wdacActive) {
    Add-Signal 3 "WDAC code-integrity policy present (CiPolicies\Active or SiPolicy.p7b)"
}

# Sysmon service + driver.
$sysmonSvc = @(Get-CimInstance Win32_Service | Where-Object { $_.Name -match '^Sysmon' })
if ($sysmonSvc.Count -gt 0 -and $sysmonSvc[0].State -eq 'Running') {
    Add-Signal 2 "Sysmon service '$($sysmonSvc[0].Name)' running - process/network telemetry likely flowing"
}
$sysmonDrv = Get-CimInstance Win32_SystemDriver -Filter "Name='SysmonDrv'"
if ($sysmonDrv -and $sysmonDrv.State -eq 'Running') {
    Add-Signal 1 "SysmonDrv kernel driver loaded"
}

# WEF subscription: the line that upgrades every cleanup plan.
$wef = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\EventLog\EventForwarding\SubscriptionManager'
if ($wef.SubscriptionManager) {
    Add-Signal 3 "WEF subscription configured: $($wef.SubscriptionManager) - logs already left the box"
}

# Security log budget: small logs overwrite your activity quickly.
$secLog = Get-WinEvent -ListLog Security
if ($secLog -and $secLog.MaximumSizeInBytes -lt 20MB) {
    Add-Signal 1 "Security log capped at $([math]::Round($secLog.MaximumSizeInBytes / 1MB, 0)) MB (mode $($secLog.LogMode)) - short local retention"
}

# ------------------------------ evidence: egress ----------------------------
$inet = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$hasUserProxy = ($inet.ProxyEnable -eq 1) -or ($inet.AutoConfigURL)
if ($inet.AutoConfigURL)     { Add-Signal 1 "WPAD/PAC in use: $($inet.AutoConfigURL) - browser-shaped traffic is steered" }
if ($inet.ProxyEnable -eq 1) { Add-Signal 1 "Userland proxy: $($inet.ProxyServer) - beacon needs proxy-aware comms" }

# winhttp machine proxy, parsed from the registry binary instead of netsh.exe.
$winhttp = 'direct'
$wh = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Connections' -Name WinHttpSettings
if ($wh -and $wh.WinHttpSettings) {
    $bytes = [byte[]]$wh.WinHttpSettings
    if ($bytes.Length -gt 8) {
        $candidate = ([System.Text.Encoding]::ASCII.GetString($bytes, 8, $bytes.Length - 8) -split "`0")[0]
        if ($candidate) {
            $winhttp = $candidate
            Add-Signal 1 "winhttp machine proxy: $candidate"
        }
    }
}

$tlsCa = @(Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -match $tlsCaPattern } | Select-Object -ExpandProperty Subject)
if ($tlsCa.Count -gt 0) {
    Add-Signal 2 "Corporate issuing CA in root store: $($tlsCa[0]) - TLS interception likely; C2 is visible to inspection"
}

$v6 = @(Get-NetIPAddress -AddressFamily IPv6 | Where-Object { $_.AddressState -eq 'Preferred' })
if ($v6.Count -gt 0) {
    Add-Signal 0 "Live IPv6 present ($($v6[0].IPAddress)) - often less inspected; noted, not committed"
}

if (-not $hasUserProxy -and $winhttp -eq 'direct' -and $tlsCa.Count -eq 0) {
    Add-Signal -1 "Fully direct egress: no proxy, no PAC, no TLS-inspection CA"
}

# -------------------------- evidence: mid-incident --------------------------
$pfDirs = @(Get-ChildItem 'C:\Program Files', 'C:\Program Files (x86)' -Directory |
            Where-Object { $_.CreationTime -gt (Get-Date).AddDays(-14) })
$newSec = @($pfDirs | Where-Object { $_.Name -match $secDirPattern })
if ($newSec.Count -gt 0) {
    Add-Signal 2 "Security software installed within 14 days: $($newSec[0].Name) ($($newSec[0].CreationTime.ToString('yyyy-MM-dd'))) - environment may be mid-response"
}
$huntAgents = @($services | Where-Object { $_ -match $huntPattern })
if ($huntAgents.Count -gt 0) {
    Add-Signal 2 "Threat-hunt agent present: $($huntAgents[0]) - a hunt program exists here"
}

# ---------------------- optional: one justified reachability -----------------
if ($Redirector) {
    $tnc = Test-NetConnection -ComputerName $Redirector -Port 443
    if ($tnc.TcpTestSucceeded) {
        Add-Signal 0 "Redirector $Redirector :443 reachable - channel alive before it is needed"
    }
    else {
        Add-Signal 0 "Redirector $Redirector :443 NOT reachable - find out now, not mid-tasking"
    }
}

# ---------------------------------- scoring ----------------------------------
$rawScore = $script:score
$rating   = [Math]::Max(1, [Math]::Min(10, $rawScore + 5))   # shift so "no evidence" = 5 = moderate

$band = switch ($rating) {
    { $_ -le 3 } { 'Legacy / audit'; break }
    { $_ -le 6 } { 'Moderate'; break }
    default      { 'Watched' }
}

$color = if ($rating -le 3) { 'Green' } elseif ($rating -le 6) { 'Yellow' } else { 'Red' }

# ----------------- Gate 1 field summary (the notes' fill-ins) ----------------
$edrGuess = if ($mdePresent) { 'Defender+MDE (block-guess)' }
            elseif ($otherEdr.Count -gt 0) { "$($otherEdr[0]) (block-guess)" }
            elseif ($avProducts.Count -gt 0) { "$($avProducts[0]) (mode unknown)" }
            else { 'none found' }
$credLine = "PPL $(if ($runAsPPL -eq 1) { 'on' } else { 'off' }) / CG $(if ($credGuardRunning) { 'on' } else { 'off' })"
$logLine  = "SBL $(if ($sbl.EnableScriptBlockLogging -eq 1) { 'on' } else { 'off' }) / LM $languageMode / AppLocker $(if ($appLockerXml -match 'EnforcementMode=.Enabled.') { 'enforce' } elseif ($appLockerXml -match 'AuditOnly') { 'audit' } else { '-' }) / WDAC $(if ($wdacActive) { 'on' } else { '-' })"
$sysBits  = @()
if ($sysmonSvc.Count -gt 0 -and $sysmonSvc[0].State -eq 'Running') { $sysBits += 'svc' }
if ($sysmonDrv -and $sysmonDrv.State -eq 'Running')               { $sysBits += 'drv' }
$sysLine  = "Sysmon $(if ($sysBits.Count -gt 0) { $sysBits -join '+' } else { 'none' }) / WEF $(if ($wef.SubscriptionManager) { 'on' } else { 'off' })"
$egrLine  = if ($tlsCa.Count -gt 0) { "TLS-inspect ($($inet.ProxyServer))" }
            elseif ($hasUserProxy) { "proxy ($($inet.ProxyServer))" }
            elseif ($winhttp -ne 'direct') { "winhttp $winhttp" }
            else { 'direct' }
$incLine  = if ($mdeActive.Count -gt 0) { "ACTIVE IR ($($mdeActive[0]))" }
            elseif ($newSec.Count -gt 0) { "recent install ($($newSec[0].Name))" }
            elseif ($huntAgents.Count -gt 0) { "hunt agent ($($huntAgents[0]))" }
            else { 'none' }

# ---------------------------------- output -----------------------------------
Write-Host ''
Write-Host '=============================================================='
Write-Host ("  Threat rating : {0}/10 ({1})" -f $rating, $band) -ForegroundColor $color
Write-Host '=============================================================='
Write-Host ("  Raw evidence score: {0}  (positive = watched, negative = legacy/open)" -f $rawScore)
Write-Host '--------------------------------------------------------------'
if ($script:reasons.Count -gt 0) {
    foreach ($r in $script:reasons) { Write-Host "   $r" }
}
else {
    Write-Host '   (no signals collected - unable to determine anything)'
}
Write-Host '--------------------------------------------------------------'
Write-Host '  Gate 1 fields:'
Write-Host ("    EDR/XDR      : {0}" -f $edrGuess)
Write-Host ("    LSASS/CredGd : {0}" -f $credLine)
Write-Host ("    Logging      : {0}" -f $logLine)
Write-Host ("    Sysmon/WEF   : {0}" -f $sysLine)
Write-Host ("    Egress       : {0}" -f $egrLine)
Write-Host ("    Incident x   : {0}" -f $incLine)
if (-not $isElevated) { Write-Host '    (not elevated: some reads were not visible; missing = neutral, not absent)' }
Write-Host '--------------------------------------------------------------'
Write-Host '  Bands: 1-3 Legacy/audit | 4-6 Moderate | 7-10 Watched'
Write-Host '=============================================================='
Write-Host ''
Write-Host ("THREAT-RATING: {0}/10 ({1})" -f $rating, $band) -ForegroundColor $color
