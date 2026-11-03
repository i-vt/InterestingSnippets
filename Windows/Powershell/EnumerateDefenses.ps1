#Requires -Version 3.0
<#
.SYNOPSIS
    Phase 1 enumeration: inventories the defensive landscape of this Windows
    machine and prints everything it finds, grouped to feed Decision Gate 1.

.DESCRIPTION
    Produces the raw material for the Gate 1 one-line threat rating - nothing
    more. There is deliberately NO score: rating the environment is the
    student's judgment call, and a number on a script output is not a
    substitute for reading the evidence (the notes' whole point is converting
    findings into a tempo decision, not into a dial position).

    Groups, mirroring the course notes:
      1. Endpoint protection  (EDR/AV processes, services, SecurityCenter2
         registrations with productState decode, Defender status, Defender
         preferences, exclusions, ASR rules, Defender threat history)
      2. Credential & platform protection (PPL, Credential Guard, VBS, LSA
         auditing values, WDigest, cached logons, NTLM level, Kerberos
         crypto, LAPS, TPM, Secure Boot, BitLocker)
      3. Logging & telemetry  (PowerShell logging keys, full value walk,
         WinRM, event log inventory, WEF, Sysmon, effective audit policy)
      4. Policy & hardening   (AppLocker detail, WDAC detail, UAC, process
         mitigations, firewall, SmartScreen, SMB signing, LLMNR/mDNS/NetBIOS)
      5. Egress & network     (userland/machine proxy, PAC, DNS, DoH, IPv6,
         Teredo, winsock catalog, non-standard root CAs)
      6. Management plane     (SCCM, Intune/Entra join, applied GPO history,
         recent security installs, recent security tasks, MDE active IR)
      7. Patch state          (OS build/UBR, last hotfixes)

    Read-only throughout. Spawns nothing except ONE justified auditpol.exe
    call (reading the effective audit policy has no in-process equivalent).
    Everything else is CIM/WMI, registry, certificate store, or cmdlet reads.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-DefensiveLandscape.ps1

.EXAMPLE
    # Add one justified reachability test against your redirector (TCP 443)
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-DefensiveLandscape.ps1 -Redirector c2.example.com

.NOTES
    Read-only; most signals visible without elevation. Reads that fail
    because of missing elevation or missing RSAT modules are printed as
    "not visible", never silently assumed absent - on a red engagement the
    difference between "not configured" and "could not read" matters.

    productState decode (SecurityCenter2): 6 hex digits; digit pair 2 is
    real-time state (00 on, 01 expired, 10 off/snoozed), pair 3 is signature
    freshness (00 up to date, 10 out of date). Raw value printed alongside.

    This script is one long ScriptBlock-logging confession on a box where
    PowerShell logging is enabled. From a beacon, prefer inlining it; from
    disk, prefer staging before the engagement. Course doctrine applies to
    course tooling.
#>
[CmdletBinding()]
param(
    # Optional: your redirector FQDN for ONE justified reachability test
    # (TCP 443). Empty = skip the test entirely, which is the default.
    [string]$Redirector = ''
)

$ErrorActionPreference = 'SilentlyContinue'

# ------------------------------- output helpers ------------------------------
function Write-Section([string]$Title) {
    Write-Host ''
    Write-Host "== $Title ==" -ForegroundColor Cyan
}
function Write-Finding([string]$Text)   { Write-Host "  - $Text" }
function Write-Note([string]$Text)      { Write-Host "    [note] $Text" -ForegroundColor DarkGray }

# Walk ALL values under a registry key instead of hardcoding names.
function Show-RegValues([string]$Path, [string]$Label) {
    $k = Get-Item $Path
    if (-not $k) { Write-Note "$Label : key not present (or not visible without elevation)"; return }
    $props = $k.Property
    if (-not $props -or $props.Count -eq 0) { Write-Note "$Label : key exists, no values set"; return }
    foreach ($p in $props) {
        $v = (Get-ItemProperty $Path -Name $p).$p
        if ($v -is [byte[]]) { $v = 'binary[' + $v.Length + ' bytes]' }
        Write-Finding "$Label : $p = $v"
    }
}

# ------------------------------ vendor patterns ------------------------------
# Running security-product processes. Extensible; add your lab's products.
$edrProcessPattern = 'MsMpEng|MsSense|Sense|csagent|csfalcon|Cybereason|Cylance|SentinelAgent|SentinelOne|elastic-endpoint|edpa|fcags|ssav|savservice|Tanium|CbDefense|ossec|wazuh|qualys|QAGENT|TMBMSRV|TmListen|TmCCSF|ntrtscan|Sophos|bdagent|avp|kavfs|xagt|mdatp|WRSA|avast|aswService|avg|ccSvcHst|mcshield|McAfee|mfeaskm|mfemms|winlogbeat|filebeat|Velociraptor|osqueryd'
$edrServicePattern = 'windefend|WdNisSvc|^sense$|CSAgent|csfalcon|SentinelAgent|Tanium Client|elastic-agent|qualys|savsvc|Sophos|bdagent|avp|xagt|mdatp|CylanceSvc|CybereasonCRS|ossec|WazuhSvc|TMBMSRV|WRSVC|mcshield|mfemms|Velociraptor|osqueryd|huntress'
$secDirPattern     = 'Defender|CrowdStrike|Sentinel|Sophos|Tanium|Velociraptor|osquery|Carbon|Cybereason|Cylance|FireEye|Mandiant|Qualys|Elastic|Wazuh|Rapid7|Vectra|Extrahop|Huntress|Trend|McAfee|Kaspersky|Bitdefender|Avast|AVG|Webroot|Malwarebytes'
$tlsCaPattern      = 'Zscaler|Netskope|Forti|Blue Coat|Palo Alto|Inspect|WEBFILTER|Interception|Squid|Proxy|Data443|GigaTrust|Bitglass'

# Well-known public CA names; roots NOT matching this list are printed as
# possible TLS-interception / enterprise-issuing CAs.
$publicCaPattern = 'DigiCert|VeriSign|Baltimore|Entrust|GlobalSign|Sectigo|Comodo|GeoTrust|Thawte|Go Daddy|Starfield|USERTrust|AAA|Amazon|Google|Microsoft|Let''s Encrypt|ISRG|QuoVadis|Symantec|GTE|AddTrust|DST|Cybertrust|Equifax|D-TRUST|Hellenic|LuxTrust|NetLock|Buypass|Certum|Chambers|ePKI|HiPKI|Hongkong|POSTAR|SecureSign|SecureTrust|Sonera|Staat|SwissSign|T-TeleSec|Trustwave|TWCA|UCA|ACCV|AC RAIZ|A-Trust|Autoridad|certSIGN|CFCA|Disig|EBG|E-Tugra|FNMT|Microsec|OISTE|SK ID|Swisscom|Telia|TUBITAK|Visa|Wells|XRamp|IdenTrust|SECOM|Trustis|Telesec|Juur|Firmaprofesional|Global Chambers|KISA|Netrust|Government|Ministry|WISeKey|OpenTrust|Opentrust|TeliaSonera|CNNIC|Cairometrics|Castilla|Certinomis|certum|CFuK|China|CIK|Cisco|CTPS|Deutsche|DFN|DocuSign|Echoworx|EDICOM|e-Szigno|Fina|FNMT|German|IGC|Izenpe|KOREA|Luxtrust|MACP|ncipher|Open Access|Polskie|PRV|RSA|SGC|SSL|S-TRUST|StartCom|Swiss Government|Taiwan|Thawte|TWCA|Unizeto|VRK|WISeKey'

# ------------------------------- data harvest -------------------------------
$isElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

$os         = Get-CimInstance Win32_OperatingSystem
$cs         = Get-CimInstance Win32_ComputerSystem
$procs      = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -match $edrProcessPattern } | Select-Object Name, ProcessId, ExecutablePath)
$svcs       = @(Get-CimInstance Win32_Service | Where-Object { $_.Name -match $edrServicePattern } | Select-Object Name, State, StartMode, PathName, StartName)
$avProducts = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct)
$asProducts = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiSpywareProduct)
$fwProducts = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName FirewallProduct)
try { $mp = Get-MpComputerStatus } catch { $mp = $null }
try { $mpPref = Get-MpPreference } catch { $mpPref = $null }
try { $dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard } catch { $dg = $null }

Write-Host ''
Write-Host '=============================================================='
Write-Host ("  Defensive landscape : {0} / {1}" -f $cs.Name, $os.Caption)
Write-Host ("  Build {0}.{1}  ({2})" -f $os.Version, (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name UBR).UBR, $os.InstallDate)
Write-Host ("  Elevated: {0}" -f $isElevated)
Write-Host '=============================================================='

# ============================================================================
# 1. Endpoint protection
# ============================================================================
Write-Section '1. Endpoint protection'

foreach ($p in $procs) {
    Write-Finding ("process {0} (pid {1}) - {2}" -f $p.Name, $p.ProcessId, $p.ExecutablePath)
}
if ($procs.Count -eq 0) { Write-Note 'no known security-product processes running (pattern list is in $edrProcessPattern)' }

foreach ($s in $svcs) {
    Write-Finding ("service {0}: {1}, start {2}, runs as {3}" -f $s.Name, $s.State, $s.StartMode, $s.StartName)
    Write-Finding ("    binary: $($s.PathName)")
}

# SecurityCenter2 productState decode: pair 2 = real-time, pair 3 = freshness.
function Show-WscProduct($prod, $kind) {
    foreach ($p in $prod) {
        $hx  = '{0:x6}' -f ([int]$p.productState)
        $rt  = $hx.Substring(2, 2)
        $utd = $hx.Substring(4, 2)
        $rtTxt  = switch ($rt)  { '00' { 'real-time ON' } '01' { 'EXPIRED' } '10' { 'real-time OFF / snoozed' } default { "0x$rt" } }
        $utdTxt = switch ($utd) { '00' { 'signatures up to date' } '10' { 'signatures OUT OF DATE' } default { "0x$utd" } }
        Write-Finding ("{0}: {1} [{2}; {3}] (raw productState 0x{4})" -f $kind, $p.displayName, $rtTxt, $utdTxt, $hx)
        Write-Finding ("    exe: $($p.pathToSignedProductExe)")
    }
}
Show-WscProduct $avProducts 'AV'
Show-WscProduct $asProducts 'Anti-spyware'
Show-WscProduct $fwProducts 'Firewall'
if ($avProducts.Count -eq 0 -and $asProducts.Count -eq 0 -and $fwProducts.Count -eq 0) {
    Write-Note 'nothing registered in SecurityCenter2'
}

if ($mp) {
    Write-Finding ("Defender AM service v{0}, AV engine v{1}, NIS v{2}" -f $mp.AMServiceVersion, $mp.AntivirusVersion, $mp.NISEngineVersion)
    Write-Finding ("RTP=$($mp.RealTimeProtectionEnabled) BehaviorMonitor=$($mp.BehaviorMonitorEnabled) NIS=$($mp.NISEnabled) OnAccess=$($mp.OnAccessProtectionEnabled) Tamper=$($mp.TamperProtected)")
    Write-Finding ("definitions: AV $($mp.AntivirusSignatureLastUpdated) | NIS $($mp.NISSignatureLastUpdated) | quick scan $($mp.QuickScanEndTime)")
    Write-Finding ("Defender state: $($mp.AMRunningMode)  (Normal = active, Passive = another AV primary, SxS passive = secondary, EDR = MDE block mode)")
}

if ($mpPref) {
    if ($mpPref.DisableRealtimeMonitoring)            { Write-Finding '!! Real-time protection DISABLED via policy' }
    if ($mpPref.DisableBehaviorMonitoring)            { Write-Finding '!! Behavior monitoring DISABLED via policy' }
    if ($mpPref.DisableScriptScanning)                { Write-Finding '!! Script scanning DISABLED via policy' }
    if ($mpPref.DisableArchiveScanning)               { Write-Finding 'Archive scanning disabled (default off - noting only)' }
    if ($mpPref.PUAProtection -eq 1)                  { Write-Finding 'PUA protection enabled' }
    if ($mpPref.EnableNetworkProtection -ne 0)        { Write-Finding ("Network Protection: {0} (0 default, 1 audit, 2 block)" -f $mpPref.EnableNetworkProtection) }
    if ($mpPref.EnableControlledFolderAccess -ne 0)   { Write-Finding ("Controlled Folder Access: {0}" -f $mpPref.EnableControlledFolderAccess) }
    if ($mpPref.MAPSReporting)                        { Write-Finding "MAPS/cloud reporting: $($mpPref.MAPSReporting) (0 off, 1 basic, 2 advanced)"
        Write-Finding "Sample submission consent: $($mpPref.SubmitSamplesConsent)" }
    if ($mpPref.CloudBlockLevel)                      { Write-Finding "Cloud block level: $($mpPref.CloudBlockLevel), extended timeout $($mpPref.CloudExtendedTimeout)s" }
    # Exclusions: high-value both for planning and as a compromise smell.
    foreach ($x in $mpPref.ExclusionPath)     { Write-Finding "!! exclusion (path): $x" }
    foreach ($x in $mpPref.ExclusionProcess)  { Write-Finding "!! exclusion (process): $x" }
    foreach ($x in $mpPref.ExclusionExtension){ Write-Finding "!! exclusion (extension): $x" }
    foreach ($x in $mpPref.ExclusionIpAddress){ Write-Finding "!! exclusion (ip): $x" }
    # ASR rules: parallel id/action arrays. 0 off, 1 block, 2 audit, 6 warn.
    $asrOn = @()
    for ($i = 0; $i -lt $mpPref.AttackSurfaceReductionRules_Ids.Count; $i++) {
        $action = $mpPref.AttackSurfaceReductionRules_Actions[$i]
        if ($action -ne 0) { $asrOn += ("{0} = {1}" -f $mpPref.AttackSurfaceReductionRules_Ids[$i], @(switch ($action) { 1 {'block'} 2 {'audit'} 6 {'warn'} default {$action} })) }
    }
    if ($asrOn.Count -gt 0) { Write-Finding "ASR rules active ($($asrOn.Count)): $($asrOn -join '; ')" }
    else { Write-Note 'no ASR rules configured' }
}

# Defender detection history on this box: the loudest mid-incident smell.
try {
    $threats = @(Get-MpThreat)
    if ($threats.Count -gt 0) {
        foreach ($t in $threats) { Write-Finding "!! active/known threat: $($t.ThreatName) (id $($t.ThreatID), severity $($t.SeverityID))" }
    }
    $detections = @(Get-MpThreatDetection | Sort-Object InitialDetectionTime -Descending | Select-Object -First 5)
    foreach ($d in $detections) {
        Write-Finding ("detection {0}: action={1} success={2} time={3}" -f $d.ThreatID, $d.ActionID, $d.ActionSuccess, $d.InitialDetectionTime)
        foreach ($r in @($d.Resources | Select-Object -First 3)) { Write-Finding "    resource: $r" }
    }
    if ($threats.Count -eq 0 -and $detections.Count -eq 0) { Write-Note 'no Defender threat history on this box' }
} catch { Write-Note 'Defender threat history not readable' }

# ============================================================================
# 2. Credential & platform protection
# ============================================================================
Write-Section '2. Credential & platform protection'

Show-RegValues 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'LSA'
$pplBoot = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name RunAsPPLBoot).RunAsPPLBoot
if ($pplBoot -eq 1) { Write-Finding 'RunAsPPLBoot = 1 (PPL survives safe mode)' }

if ($dg) {
    Write-Finding ("VBS status: $($dg.VirtualizationBasedSecurityStatus) (0 off, 1 configured-not-running, 2 running)")
    Write-Finding ("security services configured: {0} | running: {1}" -f ($dg.SecurityServicesConfigured -join ','), ($dg.SecurityServicesRunning -join ','))
    Write-Finding ("  (1 = Credential Guard, 2 = HVCI per the course notes; verify on lab builds)")
    $ci = [int]$dg.CodeIntegrityPolicyEnforcementStatus
    $um = [int]$dg.UsermodeCodeIntegrityPolicyEnforcementStatus
    Write-Finding ("WDAC kernel CI enforcement: {0} | user-mode (UMCI): {1} (0 off, 1 audit, 2 enforce)" -f $ci, $um)
}
else { Write-Note 'DeviceGuard namespace not readable (older OS or no access)' }

# Dynamic walk: any LSA values mentioning audit (credential-dump detection).
$lsaKey = Get-Item 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
foreach ($p in @($lsaKey.Property)) {
    if ($p -match 'Audit') { Write-Finding "LSA audit knob: $p = $((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name $p).$p)" }
}

Show-RegValues 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' 'WDigest'
Write-Note 'WDigest UseLogonCredential = 1 means cleartext credentials in memory (KB2871997 undone)'

Show-RegValues 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' 'Winlogon'
$cached = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name CachedLogonsCount).CachedLogonsCount
if ($null -ne $cached) { Write-Finding "cached logons allowed: $cached (0 = no cached credentials)" }

$krb = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Kerberos\Parameters' -Name SupportedEncryptionTypes
if ($krb) {
    $et = [int]$krb.SupportedEncryptionTypes
    $algos = @()
    if ($et -band 0x1)  { $algos += 'DES' }
    if ($et -band 0x4)  { $algos += 'RC4' }
    if ($et -band 0x8)  { $algos += 'AES128' }
    if ($et -band 0x10) { $algos += 'AES256' }
    Write-Finding "Kerberos SupportedEncryptionTypes = 0x{0:x} ({1})" -f $et, ($algos -join '+')
    if (($et -band 0x4) -and -not ($et -band 0x10)) { Write-Finding '!! RC4 permitted without AES256 (roast-friendly crypto policy)' }
}
else { Write-Note 'Kerberos SupportedEncryptionTypes not set (default permits RC4)' }

# LAPS posture: legacy LAPS CSE and Windows LAPS policy.
$lapsLegacy = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft Services\AdmPwd' -Name AdmPwdEnabled
if ($lapsLegacy -and $lapsLegacy.AdmPwdEnabled -eq 1) { Write-Finding 'legacy LAPS client installed and enabled' }
$lapsNew = Get-Item 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\LAPS'
if ($lapsNew -and $lapsNew.Property.Count -gt 0) { Write-Finding "Windows LAPS policy keys present: $($lapsNew.Property -join ', ')" }

# Platform: TPM, Secure Boot, BitLocker.
$tpm = Get-CimInstance Win32_Tpm
if ($tpm) { Write-Finding ("TPM: present, spec {0}, ready {1}" -f $tpm.SpecVersion, $tpm.IsReady_InitialValue) }
else { Write-Note 'TPM not readable (absent, or no admin)' }
try {
    $sb = Confirm-SecureBootUEFI
    Write-Finding "Secure Boot: $sb"
} catch { Write-Note 'Secure Boot check unavailable (legacy BIOS or no access)' }
$bl = Get-CimInstance -Namespace 'root/cimv2/Security/MicrosoftVolumeEncryption' -ClassName Win32_EncryptableVolume -Filter "DriveLetter='C:'"
if ($bl) {
    $blTxt = switch ([int]$bl.ProtectionStatus) { 0 {'NOT encrypted'} 1 {'encrypted'} 2 {'encryption in progress'} default {$bl.ProtectionStatus} }
    Write-Finding "BitLocker C: $blTxt"
}

# ============================================================================
# 3. Logging & telemetry
# ============================================================================
Write-Section '3. Logging & telemetry'

Write-Finding ("PowerShell LanguageMode: $ExecutionContext.SessionState.LanguageMode")
Show-RegValues 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell' 'PowerShell policy'
Show-RegValues 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging' 'ScriptBlock logging'
Show-RegValues 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging' 'Module logging'
Show-RegValues 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription' 'Transcription'
Show-RegValues 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\UpdatableHelp' 'UpdatableHelp'

# WinRM / PS remoting.
$winrm = Get-CimInstance Win32_Service -Filter "Name='WinRM'"
if ($winrm) {
    Write-Finding ("WinRM service: $($winrm.State), start $($winrm.StartMode)")
    if ($winrm.State -eq 'Running') {
        Get-ChildItem WSMan:\localhost\Listener | ForEach-Object {
            $addr = ($_ | Get-ChildItem | Where-Object Name -eq 'Address').Value
            $tran = ($_ | Get-ChildItem | Where-Object Name -eq 'Transport').Value
            $port = ($_ | Get-ChildItem | Where-Object Name -eq 'Port').Value
            Write-Finding "  WinRM listener: $addr/$tran :$port"
        }
    }
}
else { Write-Note 'WinRM service not present' }

# Event log inventory: the big enabled logs, plus the ones that matter here.
$logs = @(Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | Where-Object { $_.IsEnabled -and $_.FileSize -gt 0 } | Sort-Object FileSize -Descending)
foreach ($l in ($logs | Select-Object -First 20)) {
    Write-Finding ("log {0}: {1} MB now, max {2} MB, mode {3}" -f $l.LogName, [math]::Round($l.FileSize/1MB,1), [math]::Round($l.MaximumSizeInBytes/1MB,0), $l.LogMode)
}
foreach ($name in 'Security','Microsoft-Windows-PowerShell/Operational','Microsoft-Windows-WMI-Activity/Operational','Microsoft-Windows-Windows Defender/Operational','Microsoft-Windows-Sysmon/Operational','Microsoft-Windows-TaskScheduler/Operational') {
    $l = $logs | Where-Object LogName -eq $name
    if ($l) { Write-Finding ("watch log {0}: {1} MB, max {2} MB, mode {3}" -f $l.LogName, [math]::Round($l.FileSize/1MB,1), [math]::Round($l.MaximumSizeInBytes/1MB,0), $l.LogMode) }
}
Write-Note "top 20 enabled logs by size shown; Security-log mode 'Retain' or tiny max size shortens your local forensic shadow"

Show-RegValues 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\EventLog\EventForwarding\SubscriptionManager' 'WEF'
$wefSvc = Get-CimInstance Win32_Service | Where-Object { $_.Name -match 'WecSvc|Windows Event Collector' } | Select-Object -First 1
if ($wefSvc) { Write-Finding "collector service present locally (this box forwards FROM others too?): $($wefSvc.State)" }

# Sysmon, with binary version since config requires executing it.
$sysmonSvc = Get-CimInstance Win32_Service | Where-Object { $_.Name -match '^Sysmon' } | Select-Object -First 1
if ($sysmonSvc) {
    $bin = $sysmonSvc.PathName -replace '^"|"$',''
    $ver = (Get-Item $bin).VersionInfo.FileVersion
    Write-Finding "Sysmon service $($sysmonSvc.Name): $($sysmonSvc.State), binary $bin (v$ver)"
    Write-Note 'config contents require running Sysmon -c; binary version at least dates the rule-schema era'
}
$sysmonDrv = Get-CimInstance Win32_SystemDriver -Filter "Name='SysmonDrv'"
if ($sysmonDrv) { Write-Finding "SysmonDrv driver: $($sysmonDrv.State)" }

# Effective audit policy. The ONE justified spawn: no in-process equivalent.
Write-Finding 'audit policy (auditpol /get):'
try {
    $audit = @(auditpol.exe /get /category:* /r 2>$null | ConvertFrom-Csv | Where-Object { $_.'Inclusion Setting' -ne 'No Auditing' })
    if ($audit.Count -gt 0) {
        foreach ($a in $audit) { Write-Finding ("    {0} = {1}" -f $a.Subcategory, $a.'Inclusion Setting') }
    }
    else { Write-Note 'audit policy: everything at default (No Audging)' }
}
catch { Write-Note 'auditpol not available' }

# What GPOs actually applied last cycle (names only).
$gpoHist = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\History' |
           Where-Object { $_.GetValue('DisplayName') }
foreach ($g in $gpoHist) {
    Write-Finding ("applied GPO: {0} (link '{1}')" -f $g.GetValue('DisplayName'), $g.GetValue('Link'))
}
if (-not $gpoHist) { Write-Note 'no GPO history (workgroup, or never processed policy)' }

# ============================================================================
# 4. Policy & hardening
# ============================================================================
Write-Section '4. Policy & hardening'

# AppLocker: per-collection modes and rule counts when the module exists.
$appLockerXml = $null
try { $appLockerXml = Get-AppLockerPolicy -Effective -Xml } catch { $appLockerXml = $null }
if ($appLockerXml) {
    try {
        [xml]$al = $appLockerXml
        foreach ($rc in $al.AppLockerPolicy.RuleCollection) {
            $ruleCount = @($rc.FilePathRule + $rc.FileHashRule + $rc.FilePublisherRule + $rc.MsiRule + $rc.ScriptRule + $rc.DllRule + $rc.AppxRule).Count
            Write-Finding ("AppLocker {0}: {1} ({2} rules)" -f $rc.Type, $rc.EnforcementMode, $ruleCount)
        }
    } catch { Write-Finding "AppLocker effective XML retrieved but unparsable; first 200 chars: $($appLockerXml.Substring(0,200))" }
}
elseif (Test-Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SrpV2') {
    foreach ($sub in (Get-ChildItem 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SrpV2').PSChildName) {
        Write-Finding "SrpV2 policy area present: $sub (effective mode needs the AppLocker module to decode)"
    }
}
else { Write-Note 'no AppLocker/WDAC GPO keys (SrpV2 absent)' }

if ($dg) {
    $cip = @(Get-ChildItem 'C:\Windows\System32\CodeIntegrity\CiPolicies\Active' -Filter *.cip)
    foreach ($f in $cip) { Write-Finding "WDAC policy file: $($f.Name) ({0} KB, {1})" -f [math]::Round($f.Length/1KB,1), $f.LastWriteTime }
}
$ciPol = Get-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CodeIntegrity'
if ($ciPol) { foreach ($p in $ciPol.Property) { Write-Finding "CodeIntegrity policy key: $p = $($ciPol.GetValue($p))" } }

# UAC posture.
$uac = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
Write-Finding ("UAC: EnableLUA=$($uac.EnableLUA) ConsentPromptBehaviorAdmin=$($uac.ConsentPromptBehaviorAdmin) PromptOnSecureDesktop=$($uac.PromptOnSecureDesktop)")
$latfp = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name LocalAccountTokenFilterPolicy).LocalAccountTokenFilterPolicy
if ($latfp -eq 1) { Write-Finding 'LocalAccountTokenFilterPolicy = 1 (UAC remote restrictions disabled - remote local-admin logons are full tokens)' }

# Process mitigations (system-wide): print every switch that is ON.
try {
    $mit = Get-ProcessMitigation -System
    $on = @()
    foreach ($prop in $mit.PSObject.Properties) {
        if ($prop.Value -is [bool] -and $prop.Value) { $on += $prop.Name }
        elseif ($prop.Value -is [string] -and $prop.Value -notin @('OFF','NotSet','False','') -and $prop.Name -notmatch 'PS') { $on += "$($prop.Name)=$($prop.Value)" }
    }
    if ($on.Count -gt 0) { Write-Finding "system exploit mitigations ON: $($on -join ', ')" }
    else { Write-Note 'no system-wide exploit mitigations enabled' }
} catch { Write-Note 'Get-ProcessMitigation unavailable on this build' }

# Firewall profiles and their logging.
$fwProfiles = @(Get-NetFirewallProfile)
foreach ($p in $fwProfiles) {
    Write-Finding ("firewall [{0}] enabled={1} inbound={2} log=allowed:{3} blocked:{4} max:{5}MB file:{6}" -f $p.Name, $p.Enabled, $p.DefaultInboundAction, $p.LogAllowed, $p.LogBlocked, [math]::Round($p.LogMaxSizeKilobytes/1024,0), $p.LogFileName)
}
if ($fwProfiles.Count -gt 0 -and -not ($fwProfiles | Where-Object Enabled).Count) { Write-Finding '!! all firewall profiles DISABLED' }

Show-RegValues 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'SmartScreen policy'
$smartApp = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name EnableSmartScreen).EnableSmartScreen
if ($smartApp -eq 0) { Write-Finding 'SmartScreen explicitly disabled by policy' }

# SMB posture.
$srvParams = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'
Write-Finding ("SMB server: SMB1=$($srvParams.SMB1) require-signing=$($srvParams.RequireSecuritySignature) enable-signing=$($srvParams.EnableSecuritySignature) (SMB1 absent = default, usually off on Win10+)")
$wkParams = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'
Write-Finding ("SMB client: require-signing=$($wkParams.RequireSecuritySignature)")

# Name-resolution protocols (poisoning surface, both directions).
$llmnr = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' -Name EnableMulticast).EnableMulticast
Write-Finding ("LLMNR: $(if ($llmnr -eq 0) {'disabled by policy'} elseif ($null -eq $llmnr) {'default (ENABLED)'} else {"value $llmnr"})")
$mdns = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' -Name EnableMDNS).EnableMDNS
Write-Finding ("mDNS: $(if ($mdns -eq 0) {'disabled'} elseif ($null -eq $mdns) {'default (enabled)'} else {"value $mdns"})")
foreach ($if in (Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces')) {
    $opt = $if.GetValue('NetbiosOptions')
    if ($null -ne $opt) { Write-Finding ("NetBIOS on $($if.PSChildName): $(switch ($opt) { 0 {'default (NetBIOS on if DHCP says so)'} 1 {'ENABLED'} 2 {'disabled'} })") }
}

# ============================================================================
# 5. Egress & network
# ============================================================================
Write-Section '5. Egress & network'

Show-RegValues 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' 'user proxy'
Show-RegValues 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings' 'machine proxy'

# winhttp binary parse instead of spawning netsh.exe.
$wh = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Connections' -Name WinHttpSettings
if ($wh -and $wh.WinHttpSettings) {
    $bytes = [byte[]]$wh.WinHttpSettings
    if ($bytes.Length -gt 8) {
        $proxy = ([System.Text.Encoding]::ASCII.GetString($bytes, 8, $bytes.Length - 8) -split "`0")[0]
        if ($proxy) { Write-Finding "winhttp machine proxy: $proxy" }
        else { Write-Note 'winhttp: direct (no proxy string in the binary)' }
    }
    else { Write-Note 'winhttp: direct (header only)' }
}

foreach ($d in (Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { $_.ServerAddresses })) {
    Write-Finding ("DNS v4 on {0}: {1}" -f $d.InterfaceAlias, ($d.ServerAddresses -join ', '))
}
$globalDns = Get-DnsClientGlobalSetting
if ($globalDns) { Write-Finding "DNS suffix search list: $($globalDns.SuffixSearchList -join ', ')" }
try {
    foreach ($d in (Get-DnsClientDohServerAddress)) { Write-Finding "DoH server: $($d.ServerAddress) template=$($d.DohTemplate) auto-upgrade=$($d.AutoUpgrade)" }
} catch { }

$v6 = @(Get-NetIPAddress -AddressFamily IPv6 | Where-Object { $_.AddressState -eq 'Preferred' })
if ($v6.Count -gt 0) { Write-Finding "live IPv6: $(($v6 | ForEach-Object IPAddress) -join ', ') - often less inspected" }
foreach ($t in (Get-NetAdapter | Where-Object { $_.Name -match 'Teredo|ISATAP|6to4' -and $_.Status -eq 'Up' })) {
    Write-Finding "transition adapter up: $($t.Name) - tunnel surface worth a look"
}

# Winsock catalog: layered providers and filters.
$lsp = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\WinSock2\Parameters\NameSpace_Catalog5\CatalogEntries'
foreach ($e in $lsp) { Write-Finding ("winsock namespace provider: {0}" -f $e.GetValue('Description')) }
$lsp2 = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\WinSock2\Parameters\Protocol_Catalog9\CatalogEntries'
foreach ($e in $lsp2) {
    $name = $e.GetValue('PackedCatalogItem')  # binary blob; provider name not directly readable here
}
Write-Note "protocol catalog has $($lsp2.Count) entries (count only; names live in a binary blob)"

# Root CAs that are NOT well-known public CAs: interception candidates.
$roots = @(Get-ChildItem Cert:\LocalMachine\Root)
$unusual = @($roots | Where-Object { $_.Subject -notmatch $publicCaPattern })
foreach ($c in $unusual) { Write-Finding "non-standard root CA: $($c.Subject) (thumb $($c.Thumbprint.Substring(0,8))...)" }
if ($unusual.Count -eq 0) { Write-Note "all $($roots.Count) root CAs match the well-known public list" }

# ============================================================================
# 6. Management plane & incident smells
# ============================================================================
Write-Section '6. Management plane & incident smells'

$ccm = Get-CimInstance Win32_Service -Filter "Name='CcmExec'"
if ($ccm) {
    Write-Finding "SCCM client running (CcmExec)"
    $site = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client' -Name SMSCurrentAssignedSite).SMSCurrentAssignedSite
    if ($site) { Write-Finding "SCCM assigned site: $site" }
}
$mdm = @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Enrollments' | Where-Object { $_.GetValue('DiscoveryServiceFullName') -or $_.GetValue('EnrollmentType') })
foreach ($m in $mdm) {
    Write-Finding ("enrollment: type {0} at {1} (UPN {2})" -f $m.GetValue('EnrollmentType'), $m.GetValue('DiscoveryServiceFullName'), $m.GetValue('UPN'))
}
$joinInfo = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\JoinInfo'
foreach ($j in $joinInfo) {
    Write-Finding ("Entra join: tenant {0}, idp {1}, user {2}" -f $j.GetValue('TenantId'), $j.GetValue('IdpDomain'), $j.GetValue('UserEmail'))
}
if (-not $mdm -and -not $joinInfo) { Write-Note 'no MDM enrollment, no Entra join' }

# Recent security-software installs from the uninstall registry (more
# reliable than directory timestamps).
$uninstall = @(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' |
                Where-Object { $_.DisplayName -match $secDirPattern })
foreach ($u in $uninstall) {
    Write-Finding ("installed security product: {0} {1} (installed {2})" -f $u.DisplayName, $u.DisplayVersion, $u.InstallDate)
}

$pfNew = @(Get-ChildItem 'C:\Program Files', 'C:\Program Files (x86)' -Directory | Where-Object { $_.CreationTime -gt (Get-Date).AddDays(-14) })
foreach ($d in $pfNew) { Write-Finding ("new Program Files dir (<14d): {0} ({1})" -f $d.FullName, $d.CreationTime.ToString('yyyy-MM-dd')) }
if ($pfNew.Count -eq 0) { Write-Note 'no Program Files directories created in the last 14 days' }

foreach ($t in (Get-ScheduledTask | Where-Object { $_.TaskPath -notlike '\Microsoft*' })) {
    $info = Get-ScheduledTaskInfo $t
    if ($info.Date -gt (Get-Date).AddDays(-14)) {
        $exe = $t.Actions[0].Execute
        if ($exe -match $secDirPattern) {
            Write-Finding ("task created <14d (security tool): {0}{1} -> {2} {3} (runas {4})" -f $t.TaskPath, $t.TaskName, $exe, $t.Actions[0].Arguments, $t.Principal.UserId)
        }
    }
}

$mdeActive = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'SenseIR|SenseCNR' } | Select-Object -ExpandProperty Name)
foreach ($m in $mdeActive) { Write-Finding "!! MDE investigation process running: $m - active IR on this host" }

if ($Redirector) {
    $tnc = Test-NetConnection -ComputerName $Redirector -Port 443
    Write-Finding ("redirector {0}:443 reachable: {1}" -f $Redirector, $tnc.TcpTestSucceeded)
}

# ============================================================================
# 7. Patch state
# ============================================================================
Write-Section '7. Patch state'

$cur = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
Write-Finding ("OS: $($os.Caption) build $($cur.CurrentBuild).$($cur.UBR), installed $($os.InstallDate), last boot $($os.LastBootUpTime)")
$hotfixes = @(Get-CimInstance Win32_QuickFixEngineering | Sort-Object InstalledOn -Descending | Select-Object -First 5)
foreach ($h in $hotfixes) { Write-Finding ("hotfix {0} installed {1}" -f $h.HotFixID, $h.InstalledOn) }
Write-Note 'compare CurrentBuild.UBR against the vendor servicing timeline to date the patch gap - that expectation-setter feeds Phase 4'

# ============================================================================
# Gate 1: fill in one line (the notes' decision gate - YOUR judgment)
# ============================================================================
Write-Section 'Gate 1 - fill in one line (student judgment; script does not score)'

$edrGuess = if ($svcs.Name -contains 'Sense' -or ($procs.Name -match 'MsSense|Sense')) { 'Defender+MDE (block vs audit: GUESS)' }
            elseif ($procs) { "$($procs[0].Name) (block vs audit: GUESS)" }
            elseif ($avProducts) { "$($avProducts[0].displayName) (mode unknown)" }
            else { 'none found' }
Write-Host ("  EDR/XDR: {0}" -f $edrGuess)
Write-Host ("  LSASS/CredGuard: PPL $(if ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name RunAsPPL).RunAsPPL -eq 1) {'on'} else {'off'}) / CG $(if ($dg -and (($dg.SecurityServicesRunning -contains 2) -or ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name LsaCfgFlags).LsaCfgFlags -ge 1))) {'on'} else {'off'})")
Write-Host '  Script logging / CLM / AppLocker: (see sections 3-4)'
Write-Host '  Sysmon + WEF: (see section 3)'
Write-Host '  Egress: (see section 5)'
Write-Host '  Incident multiplier: (see section 6)'
Write-Host ''
Write-Host '  Threat rating, one line: _______________________________________'
Write-Host ''
