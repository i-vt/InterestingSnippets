<#
.SYNOPSIS
  One-shot setup: enables OpenSSH Server + WinRM, opens firewall ports, and
  allows administrators to log in with existing local/AD credentials.

.DESCRIPTION
  SSH and WinRM are enabled independently inside guarded blocks. Each block
  records every change it makes; if ANY step fails (install, config, service,
  firewall, or final verification), all of that component's changes are rolled
  back automatically so the machine is left in its prior, working state.
  Failure of one component does not prevent the other from being enabled.

  Run from an elevated (Administrator) PowerShell session.
  Windows Server 2016+ / Windows 10 1809+.

.NOTES
  Security: password auth + WinRM/HTTP are enabled for lab-style access —
  restrict inbound firewall scope (-RemoteAddress) on production networks.

.EXITCODES
  0 = at least one component enabled & verified (both, or one with the other
      safely rolled back and recorded as SKIPPED)
  2 = neither component could be enabled / fatal precondition error

A full transcript is appended to %ProgramData%\SSH-WinRM-Setup\setup.log and
a JSON result record to setup-results.jsonl on every run, including which
component was SKIPPED and why.
#>

#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

# PowerShell 7.4+: native command failures (sc.exe, net, winrm) otherwise
# honor $ErrorActionPreference='Stop' and abort with raw stderr text, which
# bypasses our layered fallbacks. Turn that off so we control error handling.
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

# --- Run log: everything is recorded here so skipped components are auditable ---
$LogDir  = "$env:ProgramData\SSH-WinRM-Setup"
$LogFile = Join-Path $LogDir 'setup.log'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Start-Transcript -Path $LogFile -Append -ErrorAction SilentlyContinue | Out-Null
Write-Host "Log file: $LogFile" -ForegroundColor DarkGray

Write-Host "=== SSH / WinRM one-shot enable (safe-fail) ===" -ForegroundColor Cyan

# ---------------------------------------------------------------
# Helper: recorded-change log per component, with rollback
# ---------------------------------------------------------------
function New-RollbackLog { @{ Undo = @(); Note = @() } }
function Add-Undo($log, [scriptblock]$Action, [string]$Description) {
    $log.Undo += [pscustomobject]@{ Action = $Action; Description = $Description }
}
function Add-Note($log, [string]$Text) { $log.Note += $Text }

function Invoke-Rollback($log, [string]$Component) {
    Write-Warning "Rolling back $Component changes (restoring prior state)..."
    for ($i = $log.Undo.Count - 1; $i -ge 0; $i--) {
        $step = $log.Undo[$i]
        try {
            & $step.Action
            Write-Host "  undone: $($step.Description)" -ForegroundColor DarkGray
        } catch {
            Write-Warning "  rollback step failed (non-fatal): $($step.Description) -- $_"
        }
    }
}

function Wait-PortListen([int]$Port, [int]$TimeoutSec = 15) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

# Run a native command with merged output WITHOUT letting stderr become a
# throwing error record (2>&1 + $ErrorActionPreference='Stop' would otherwise
# throw and bypass our fallbacks).
function Invoke-Native {
    param([string]$File, [string[]]$Args)
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = & $File @Args 2>&1 | Out-String
    $ErrorActionPreference = $prevEAP
    return @{ Output = $out.Trim(); ExitCode = $LASTEXITCODE }
}

function Set-ServiceAuto([string]$Name) {
    # Layered approach - a previous OpenSSH install removed without reboot can
    # wedge the service so that every SCM API fails with ERROR_SERVICE_DISABLED.
    #   1) sc.exe (capturing output for diagnostics)
    #   2) Set-Service fallback
    #   3) direct registry write (Start=2 = Automatic), followed by another
    #      sc.exe config - direct registry edits do NOT notify the SCM, so we
    #      flush the change through ChangeServiceConfig afterwards.
    $sc = Invoke-Native sc.exe @('config', $Name, 'start=', 'auto')
    $setSvcErr = ''
    try { Set-Service -Name $Name -StartupType Automatic -ErrorAction Stop } catch { $setSvcErr = $_.Exception.Message.Trim() }

    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
    $regStart = (Get-ItemProperty $regPath -Name Start -ErrorAction SilentlyContinue).Start
    if ($regStart -ne 2) {
        Set-ItemProperty $regPath -Name Start -Value 2 -ErrorAction SilentlyContinue
        $regStart = (Get-ItemProperty $regPath -Name Start -ErrorAction SilentlyContinue).Start
        Invoke-Native sc.exe @('config', $Name, 'start=', 'auto') | Out-Null   # flush to SCM
    }

    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (($regStart -ne 2) -and (-not $svc -or $svc.StartType -ne 'Automatic')) {
        $q = Invoke-Native sc.exe @('query', $Name)
        throw ("Unable to set '$Name' to Automatic. sc.exe exit=$($sc.ExitCode), output='$($sc.Output)'; " +
               "Set-Service error='$setSvcErr'; registry Start=$regStart; sc query='$($q.Output)'. " +
               'The service is likely pending deletion from an earlier OpenSSH install/remove without reboot - reboot and re-run.')
    }
}

function Start-ServiceEx([string]$Name) {
    $startErr = ''
    # service registration after a capability install can take a moment to
    # settle - retry a few times before declaring failure
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try { Start-Service -Name $Name -ErrorAction Stop } catch { $startErr = $_.Exception.Message.Trim() }
        if ((Get-Service -Name $Name).Status -eq 'Running') { return }
        Start-Sleep -Seconds 2
    }
    $net = Invoke-Native net.exe @('start', $Name)
    if ((Get-Service -Name $Name).Status -ne 'Running') {
        throw ("Could not start service '$Name' (status: $((Get-Service -Name $Name).Status)). " +
               "Start-Service error: '$startErr' | net start: '$($net.Output)'. " +
               'A pending-reboot OpenSSH install/remove cycle commonly causes this - reboot and re-run.')
    }
}

# ---------------------------------------------------------------
# Component: OpenSSH Server
# ---------------------------------------------------------------
function Enable-SSH {
    $log = New-RollbackLog
    try {
        # --- diagnostics: recorded in the transcript so failures are traceable ---
        $os = Get-CimInstance Win32_OperatingSystem
        Write-Host "  diag: $($os.Caption) build $($os.BuildNumber), PS $($PSVersionTable.PSVersion)"
        $capState = (Get-WindowsCapability -Online -Name 'OpenSSH.Server*' -ErrorAction SilentlyContinue | Select-Object -First 1).State
        Write-Host "  diag: OpenSSH.Server capability state = $capState"
        $sshdSvc = Get-Service sshd -ErrorAction SilentlyContinue
        if ($sshdSvc) {
            Write-Host "  diag: sshd service exists, Status=$($sshdSvc.Status), StartType=$($sshdSvc.StartType)"
        } else {
            Write-Host "  diag: sshd service NOT present"
        }
        $wuSvc = Get-Service wuauserv -ErrorAction SilentlyContinue
        if ($wuSvc) {
            Write-Host "  diag: wuauserv (Windows Update) service Status=$($wuSvc.Status), StartType=$($wuSvc.StartType)"
        }
        # --- install if missing (recorded for rollback) ---
        $cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*' -ErrorAction SilentlyContinue |
               Where-Object Name -like 'OpenSSH.Server*'
        if ($cap -and $cap.State -ne 'Installed') {
            Write-Host "  Installing OpenSSH Server..." -ForegroundColor Yellow

            # --- unblock DISM: Add-WindowsCapability installs from Windows
            #     Update and fails with ERROR_SERVICE_DISABLED ("the service
            #     cannot be started...") when wuauserv is Disabled - common on
            #     server/VM images. Enable it for the install, restore after.
            $wuChanged = $false
            $wuSvc = Get-Service wuauserv -ErrorAction SilentlyContinue
            if ($wuSvc -and $wuSvc.Status -ne 'Running') {
                $wuPrevStart = $wuSvc.StartType
                Write-Host "  wuauserv is $($wuSvc.Status)/$($wuSvc.StartType) - starting it (required by DISM capability install)..."
                try {
                    Set-Service wuauserv -StartupType Manual -ErrorAction Stop
                    Start-Service wuauserv -ErrorAction Stop
                    $wuChanged = $true
                    Add-Undo $log {
                        try { Stop-Service wuauserv -Force -ErrorAction SilentlyContinue } catch {}
                        Set-Service wuauserv -StartupType $wuPrevStart -ErrorAction SilentlyContinue
                    } "restored wuauserv to '$wuPrevStart'"
                } catch {
                    Write-Warning "Could not start wuauserv ($($_.Exception.Message)) - capability install may fail."
                }
            }

            $cap | Add-WindowsCapability -Online | Out-Null
            Start-Sleep -Seconds 5   # let service registration finalize
            Add-Undo $log { Get-WindowsCapability -Online -Name 'OpenSSH.Server*' |
                            Where-Object Name -like 'OpenSSH.Server*' |
                            Remove-WindowsCapability -Online -ErrorAction SilentlyContinue | Out-Null
                          } 'removed OpenSSH.Server capability'
        } elseif (-not $cap) {
            throw 'OpenSSH.Server capability not found on this OS.'
        }

        # --- config changes (recorded with backup restore) ---
        $sshdConfig = "$env:ProgramData\ssh\sshd_config"
        $backup     = "$sshdConfig.bak_$(Get-Date -Format yyyyMMddHHmmss)"
        if (Test-Path $sshdConfig) {
            Copy-Item $sshdConfig $backup -Force
            $cfg = Get-Content $sshdConfig -Raw
            $changed = $false

            if ($cfg -notmatch '(?m)^\s*PasswordAuthentication\s+yes') {
                Add-Content $sshdConfig "`nPasswordAuthentication yes" -Encoding ASCII
                $changed = $true
                Add-Note $log 'sshd_config: PasswordAuthentication yes'
            }
            if ($cfg -match '(?m)^\s*Match Group administrators') {
                $cfg = $cfg -replace '(?m)^\s*Match Group administrators\s*\r?\n\s*AuthorizedKeysFile\s+\S+.*?(?=\r?\n\S|\z)', ''
                Set-Content $sshdConfig $cfg -Encoding ASCII
                $changed = $true
                Add-Note $log 'sshd_config: removed admin key-only override'
            }
            if ($changed) {
                Add-Undo $log { Copy-Item $backup $sshdConfig -Force -ErrorAction SilentlyContinue } "restored sshd_config from $backup"
            }
        }

        # --- service enable/start (recorded for rollback) ---
        if (-not (Get-Service sshd -ErrorAction SilentlyContinue)) {
            throw 'sshd service is not present after install - a reboot may be required to finish the capability install.'
        }
        $prevStart = (Get-Service sshd).StartType
        Set-ServiceAuto sshd
        Add-Undo $log { Set-Service sshd -StartupType $prevStart -ErrorAction SilentlyContinue } "sshd StartType -> $prevStart"

        Start-ServiceEx sshd
        Add-Undo $log { Stop-Service sshd -Force -ErrorAction SilentlyContinue } 'stopped sshd'

        # --- firewall (recorded for rollback) ---
        $ruleName = 'SSH (TCP 22)'
        $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        if (-not $existing) {
            New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow `
                -Protocol TCP -LocalPort 22 -Profile Any | Out-Null
            Add-Undo $log { Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue } "removed firewall rule '$ruleName'"
        } else {
            $wasEnabled = $existing.Enabled
            $existing | Set-NetFirewallRule -Enabled True
            Add-Undo $log { Set-NetFirewallRule -DisplayName $ruleName -Enabled $wasEnabled -ErrorAction SilentlyContinue } "firewall rule '$ruleName' Enabled -> $wasEnabled"
        }
        # installer rule: only touch its Enabled flag, and record it
        $instRule = Get-NetFirewallRule -DisplayName 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
        if ($instRule -and $instRule.Enabled -ne 'True') {
            $instRule | Set-NetFirewallRule -Enabled True
            Add-Undo $log { Set-NetFirewallRule -DisplayName 'OpenSSH-Server-In-TCP' -Enabled False -ErrorAction SilentlyContinue } "installer SSH rule disabled again"
        }

        # --- verification ---
        Start-Sleep -Seconds 2
        if ((Get-Service sshd).Status -ne 'Running')      { throw 'sshd service is not running after start.' }
        if (-not (Wait-PortListen 22))                    { throw 'port 22 is not listening after sshd start.' }
        if ((Get-NetFirewallRule -DisplayName $ruleName).Enabled -ne 'True') { throw "firewall rule '$ruleName' not enabled." }

        foreach ($n in $log.Note) { Write-Host "  $n" }
        return @{ Ok = $true; Messages = $log.Note }
    }
    catch {
        Invoke-Rollback $log 'OpenSSH Server'
        $src = $_.InvocationInfo
        $loc = "at line $($src.ScriptLineNumber): $(($src.Line -replace '\s+',' ').Trim())"
        return @{ Ok = $false; Error = ($_.Exception.Message.Trim() + " [$loc]") }
    }
}

# ---------------------------------------------------------------
# Component: WinRM
# ---------------------------------------------------------------
function Enable-WinRM {
    $log = New-RollbackLog
    try {
        # --- record pre-state for rollback ---
        $svc = Get-Service WinRM
        $prevStart = $svc.StartType
        $fwBefore  = Get-NetFirewallRule -DisplayGroup 'Windows Remote Management' -ErrorAction SilentlyContinue |
                     Select-Object DisplayName, Enabled
        $psRemotingBefore = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' `
                             -Name LocalAccountTokenFilterPolicy -ErrorAction SilentlyContinue).LocalAccountTokenFilterPolicy

        # quickconfig will create rules & enable service; capture any it creates
        $rulesBefore = (Get-NetFirewallRule -ErrorAction SilentlyContinue).DisplayName

        winrm quickconfig -q -force | Out-Null
        Enable-PSRemoting -Force -SkipNetworkProfileCheck -WarningAction SilentlyContinue | Out-Null

        $rulesAfter = Get-NetFirewallRule -ErrorAction SilentlyContinue |
                       Where-Object { $rulesBefore -notcontains $_.DisplayName }
        Add-Undo $log {
            $rulesAfter | ForEach-Object { Remove-NetFirewallRule -Name $_.Name -ErrorAction SilentlyContinue }
        } "removed newly created WinRM firewall rules"
        # restore prior state of pre-existing WinRM rules
        Add-Undo $log {
            foreach ($r in $fwBefore) {
                Set-NetFirewallRule -DisplayName $r.DisplayName -Enabled $r.Enabled -ErrorAction SilentlyContinue
            }
        } 'restored prior WinRM firewall rule states'

        Set-ServiceAuto WinRM
        Add-Undo $log { Set-Service WinRM -StartupType $prevStart -ErrorAction SilentlyContinue } "WinRM StartType -> $prevStart"
        Start-ServiceEx WinRM
        Add-Undo $log { Stop-Service WinRM -Force -ErrorAction SilentlyContinue } 'stopped WinRM'

        # auth config (rollback = set back to service defaults)
        winrm set winrm/config/service/auth '@{Basic="true"; Negotiate="true"; Kerberos="true"}' | Out-Null
        Add-Undo $log { winrm set winrm/config/service/auth '@{Basic="false"; Negotiate="true"; Kerberos="true"}' | Out-Null } 'WinRM auth reverted to defaults'

        # local admin token filtering (lets local admins remote in with existing creds)
        if ($psRemotingBefore -ne 1) {
            New-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' `
                -Name LocalAccountTokenFilterPolicy -PropertyType DWORD -Value 1 -Force | Out-Null
            Add-Undo $log {
                if ($null -eq $psRemotingBefore) {
                    Remove-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' `
                        -Name LocalAccountTokenFilterPolicy -ErrorAction SilentlyContinue
                } else {
                    Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' `
                        -Name LocalAccountTokenFilterPolicy -Value $psRemotingBefore -ErrorAction SilentlyContinue
                }
            } 'LocalAccountTokenFilterPolicy restored'
        }

        # --- verification ---
        Start-Sleep -Seconds 2
        if ((Get-Service WinRM).Status -ne 'Running') { throw 'WinRM service is not running.' }
        if (-not (Wait-PortListen 5985))              { throw 'port 5985 is not listening after WinRM start.' }

        return @{ Ok = $true }
    }
    catch {
        Invoke-Rollback $log 'WinRM'
        $src = $_.InvocationInfo
        $loc = "at line $($src.ScriptLineNumber): $(($src.Line -replace '\s+',' ').Trim())"
        return @{ Ok = $false; Error = ($_.Exception.Message.Trim() + " [$loc]") }
    }
}

# ---------------------------------------------------------------
# Run both components independently
# ---------------------------------------------------------------
Write-Host "`n[SSH] Enabling OpenSSH Server..." -ForegroundColor Cyan
$ssh = Enable-SSH
if ($ssh.Ok) {
    Write-Host "[SSH] ENABLED and verified." -ForegroundColor Green
} else {
    Write-Host "[SSH] FAILED: $($ssh.Error) -- rolled back cleanly. SSH will be SKIPPED." -ForegroundColor Yellow
}

Write-Host "`n[WinRM] Enabling WinRM..." -ForegroundColor Cyan
$winrm = Enable-WinRM
if ($winrm.Ok) {
    Write-Host "[WinRM] ENABLED and verified." -ForegroundColor Green
} else {
    Write-Host "[WinRM] FAILED: $($winrm.Error) -- rolled back cleanly. WinRM will be SKIPPED." -ForegroundColor Yellow
}

# ---------------------------------------------------------------
# Final summary, skipped-component notification & exit code
# ---------------------------------------------------------------
$ip = (Get-NetIPAddress -AddressFamily IPv4 |
       Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -ne '127.0.0.1' } |
       Select-Object -First 1 -ExpandProperty IPAddress)

# Build structured result records
$results = @(
    [pscustomobject]@{
        Component = 'OpenSSH Server'
        Status    = if ($ssh.Ok) { 'ENABLED' } else { 'SKIPPED' }
        Reason    = if ($ssh.Ok) { 'installed, configured, verified' } else { $ssh.Error }
        Detail    = if ($ssh.Ok) { "ssh <admin>@$ip  (existing password credentials)" } else { 'no changes left on system (rolled back)' }
    },
    [pscustomobject]@{
        Component = 'WinRM'
        Status    = if ($winrm.Ok) { 'ENABLED' } else { 'SKIPPED' }
        Reason    = if ($winrm.Ok) { 'configured, verified' } else { $winrm.Error }
        Detail    = if ($winrm.Ok) { "Enter-PSSession -ComputerName $ip -Credential (Get-Credential)" } else { 'no changes left on system (rolled back)' }
    }
)

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
$results | Format-Table -AutoSize

# --- Notify what was skipped ---
$skipped = $results | Where-Object Status -eq 'SKIPPED'
if ($skipped) {
    Write-Host "=== SKIPPED components ===" -ForegroundColor Yellow
    foreach ($s in $skipped) {
        Write-Host "  SKIPPED: $($s.Component)" -ForegroundColor Yellow
        Write-Host "    Reason : $($s.Reason)" -ForegroundColor Yellow
    }
} else {
    Write-Host "Nothing was skipped - both components are active." -ForegroundColor Green
}

# --- Persist machine-readable record (separate file: the transcript keeps its
#     own lock on setup.log, so we never write to it ourselves) ---
$ResultsFile = Join-Path $LogDir 'setup-results.jsonl'
$record = [pscustomobject]@{
    Timestamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    Host      = $env:COMPUTERNAME
    Address   = $ip
    Results   = $results
}
try {
    $record | ConvertTo-Json -Depth 4 -Compress | Add-Content -Path $ResultsFile -Encoding UTF8
    Write-Host "(Transcript: $LogFile | JSON results: $ResultsFile)" -ForegroundColor DarkGray
} catch {
    Write-Warning "Could not write results file: $_"
}
try { Stop-Transcript | Out-Null } catch {}

# --- Exit code: success as long as at least one component is usable ---
if ($ssh.Ok -and $winrm.Ok) {
    exit 0   # both enabled
} elseif ($ssh.Ok -or $winrm.Ok) {
    exit 0   # exactly one enabled, other safely skipped -> still a working result
} else {
    Write-Host "Both components failed; system unchanged from before this script ran." -ForegroundColor Red
    exit 2
}
