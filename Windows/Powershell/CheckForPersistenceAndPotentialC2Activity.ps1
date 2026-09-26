<#
.SYNOPSIS
    Hunts for common persistence mechanisms and potential C2 activity on the local host.

.DESCRIPTION
    Read-only IR / threat-hunting triage. Checks:
      * Processes: suspicious paths, encoded/LOLBin command lines, system-name masquerading
      * Established TCP connections mapped to owning processes, external IPs, common C2 ports
      * Running services: binaries outside %SystemRoot%, unquoted service paths
      * Scheduled tasks: non-Microsoft tasks, suspicious actions, COM handlers
      * Registry Run/RunOnce keys (HKLM, HKCU, WOW6432Node)
      * IFEO debuggers, SilentProcessExit monitors, Winlogon Shell/Userinit, AppInit_DLLs
      * WMI event subscription persistence
      * Startup folder items
      * Targeted event review: 7045 service installs, 4698/4702 task changes,
        4720 new accounts, 4728/4732/4756 privileged group adds, 1102 log cleared

    Heuristic matches print as [!] flags and repeat in a summary at the end.
    Flags are leads, not verdicts - expect false positives and tune the lists to your environment.

.PARAMETER LogCount
    Max entries to pull per event log query. Default 50.

.PARAMETER OutputPath
    Optional transcript file for evidence collection.

.EXAMPLE
    .\CheckForPersistenceAndPotentialC2Activity.ps1 -OutputPath ".\triage-$env:COMPUTERNAME.txt"

.NOTES
    Run elevated for full coverage (Security log and WMI subscriptions require admin).
#>
[CmdletBinding()]
param(
    [int]$LogCount = 50,
    [string]$OutputPath
)

#requires -Version 5.1

# ---------------- Heuristic lists (tune these) ----------------

$SuspiciousPathFragments = @(
    '\temp\', '\tmp\', '\appdata\', '\programdata\', '\users\public\',
    '$recycle.bin', '\recycler\', '\perflogs\', '\downloads\',
    '\windows\fonts\', '\windows\help\', '\windows\debug\'
)

$SuspiciousCmdPatterns = @(
    '-enc', '-ec ', '-e ', 'frombase64string', 'invoke-expression', ' iex ',
    'downloadstring', 'downloadfile', 'net.webclient', '-nop', '-ep bypass',
    'executionpolicy bypass', '-w hidden', 'windowstyle hidden',
    'certutil -decode', 'certutil -urlcache', 'bitsadmin /transfer', 'mshta'
)

# Ports frequently abused by commodity C2 frameworks (heuristic only)
$SuspiciousPorts = @(4444, 5555, 1337, 6667, 9001, 9050, 31337, 12345, 54321)

# Names that should only ever run from System32 (or %SystemRoot% for explorer.exe)
$SystemBinaryNames = @(
    'svchost.exe','lsass.exe','csrss.exe','smss.exe','winlogon.exe',
    'services.exe','spoolsv.exe','wininit.exe','rundll32.exe','explorer.exe'
)

$script:Findings = [System.Collections.Generic.List[string]]::new()

# ---------------- Helpers ----------------

function Write-Section([string]$Title) {
    Write-Host "`n=== $Title ===" -ForegroundColor Cyan
}

function Write-Flag([string]$Message, [string]$Reason) {
    Write-Host "  [!] $Message" -ForegroundColor Red
    Write-Host "      Reason: $Reason" -ForegroundColor DarkYellow
    $script:Findings.Add("$Message  ($Reason)")
}

function Test-SuspiciousPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $p = $Path.ToLower()
    foreach ($f in $SuspiciousPathFragments) { if ($p.Contains($f)) { return $true } }
    return $false
}

function Test-SuspiciousCommandLine([string]$CommandLine) {
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $null }
    $c = $CommandLine.ToLower()
    foreach ($pat in $SuspiciousCmdPatterns) { if ($c.Contains($pat)) { return $pat } }
    return $null
}

function Test-ExternalIP([string]$IP) {
    return ($IP -notmatch '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|127\.|169\.254\.|0\.|::1|fe80:|ff)')
}

# ---------------- Setup ----------------

$isElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($OutputPath) {
    try { Start-Transcript -Path $OutputPath -Append | Out-Null }
    catch { Write-Warning "Could not start transcript: $_" }
}

try {

    Write-Section 'Host Context'
    [pscustomobject]@{
        Hostname  = $env:COMPUTERNAME
        User      = "$env:USERDOMAIN\$env:USERNAME"
        Timestamp = Get-Date
        Elevated  = $isElevated
    } | Format-List
    if (-not $isElevated) {
        Write-Host '  [*] Not elevated - Security log, WMI subscriptions and some HKLM data will be incomplete.' -ForegroundColor Yellow
    }

    # Snapshot processes once; reused by network section
    $procs = Get-CimInstance Win32_Process
    $procById = @{}
    foreach ($p in $procs) { $procById[$p.ProcessId] = $p }

    # ---------------- 1. Processes ----------------

    Write-Section 'Top 10 Processes by Memory'
    $procs | Sort-Object WorkingSetSize -Descending | Select-Object -First 10 |
        Select-Object Name, ProcessId,
            @{n='WorkingSetMB'; e={[math]::Round($_.WorkingSetSize / 1MB, 1)}} |
        Format-Table -AutoSize

    Write-Section 'Process Hunt'
    foreach ($p in $procs) {
        $path = $p.ExecutablePath
        $cmd  = $p.CommandLine

        if ($path -and (Test-SuspiciousPath $path)) {
            Write-Flag "Process in suspicious location: $($p.Name) (PID $($p.ProcessId)) - $path" 'Execution from user/temp/profile directories'
        }
        $hit = Test-SuspiciousCommandLine $cmd
        if ($hit) {
            Write-Flag "Suspicious command line: $($p.Name) (PID $($p.ProcessId)) contains '$hit'" 'Encoded/obfuscated command or LOLBin abuse'
            Write-Host "      $($cmd.Substring(0, [Math]::Min(200, $cmd.Length)))" -ForegroundColor DarkGray
        }
        if ($path -and ($p.Name -in $SystemBinaryNames)) {
            if ($path -notlike "$env:SystemRoot\System32\*" -and
                $path -notlike "$env:SystemRoot\SysWOW64\*" -and
                $path -cne "$env:SystemRoot\explorer.exe") {
                Write-Flag "Possible masquerade: $($p.Name) running from $path" 'System binary name outside System32'
            }
        }
    }

    # ---------------- 2. Network connections ----------------

    Write-Section 'Established TCP Connections'
    $conns = Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
             Where-Object { $_.RemoteAddress -notin '127.0.0.1','::1','0.0.0.0','::' }

    $connRows = foreach ($c in $conns) {
        $owner    = $procById[[int]$c.OwningProcess]
        $procName = if ($owner) { $owner.Name } else { '<unknown>' }

        if (Test-ExternalIP $c.RemoteAddress) {
            if ($c.RemotePort -in $SuspiciousPorts) {
                Write-Flag "External connection on suspicious port: $procName (PID $($c.OwningProcess)) -> $($c.RemoteAddress):$($c.RemotePort)" 'Common C2 port'
            }
            if ($owner -and $owner.ExecutablePath -and (Test-SuspiciousPath $owner.ExecutablePath)) {
                Write-Flag "External connection from binary in suspicious path: $procName ($($owner.ExecutablePath)) -> $($c.RemoteAddress):$($c.RemotePort)" 'Outbound session from user-writable location'
            }
            if (-not $owner) {
                Write-Flag "External connection with no resolvable owning process -> $($c.RemoteAddress):$($c.RemotePort)" 'Orphaned/hidden connection'
            }
        }

        [pscustomobject]@{
            Local   = "$($c.LocalAddress):$($c.LocalPort)"
            Remote  = "$($c.RemoteAddress):$($c.RemotePort)"
            PID     = $c.OwningProcess
            Process = $procName
        }
    }
    $connRows | Sort-Object Remote | Format-Table -AutoSize

    # ---------------- 3. Services ----------------

    Write-Section 'Running Services'
    $services = Get-CimInstance Win32_Service -Filter "State='Running'"
    $nonStandard = foreach ($s in $services) {
        $pn = $s.PathName
        if (-not $pn) { continue }
        $pnTrim = $pn.Trim('"')

        if (Test-SuspiciousPath $pnTrim) {
            Write-Flag "Service binary in suspicious location: $($s.Name) - $pn" 'Service persistence from user-writable path'
        }
        $hit = Test-SuspiciousCommandLine $pn
        if ($hit) {
            Write-Flag "Service with suspicious command line: $($s.Name) contains '$hit'" 'Service launching script/encoded content'
        }
        if (($pn -notlike '"*') -and (($idx = $pn.IndexOf('.exe')) -gt 0)) {
            if ($pn.Substring(0, $idx).Contains(' ')) {
                Write-Flag "Unquoted service path with spaces: $($s.Name) - $pn" 'Executable-path hijack opportunity'
            }
        }
        if ($pnTrim -notlike "$env:SystemRoot\*") { $s }   # emit for display
    }
    Write-Host "  $($services.Count) running; $($nonStandard.Count) not rooted in $env:SystemRoot (worth reviewing):"
    $nonStandard | Select-Object Name, DisplayName, PathName | Format-Table -AutoSize -Wrap

    # ---------------- 4. Scheduled tasks ----------------

    Write-Section 'Scheduled Tasks (non-Microsoft)'
    $tasks = Get-ScheduledTask | Where-Object { $_.State -in 'Ready','Running' -and $_.TaskPath -notlike '\Microsoft\*' }
    $taskRows = foreach ($t in $tasks) {
        $actionStrings = foreach ($a in $t.Actions) {
            if ($a.Execute) { "$($a.Execute) $($a.Arguments)".Trim() } else { '<COM handler>' }
        }
        foreach ($a in $actionStrings) {
            if ($a -eq '<COM handler>') {
                Write-Flag "Task '$($t.TaskName)' uses a custom COM handler" 'COM-hijack persistence vector'
            } else {
                if (Test-SuspiciousPath $a) {
                    Write-Flag "Task '$($t.TaskName)' executes from suspicious path: $a" 'Task persistence from user-writable path'
                }
                $hit = Test-SuspiciousCommandLine $a
                if ($hit) {
                    Write-Flag "Task '$($t.TaskName)' has suspicious action ('$hit'): $a" 'Encoded/obfuscated task action'
                }
            }
        }
        $lastRun = ($t | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue).LastRunTime
        [pscustomobject]@{
            Name    = $t.TaskName
            Path    = $t.TaskPath
            State   = $t.State
            LastRun = $lastRun
            Action  = ($actionStrings -join ' | ')
        }
    }
    $taskRows | Format-Table -AutoSize -Wrap

    # ---------------- 5. Registry Run keys ----------------

    Write-Section 'Registry Run Keys'
    $runKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
    )
    foreach ($key in $runKeys) {
        if (-not (Test-Path $key)) { continue }
        $item = Get-ItemProperty -Path $key
        foreach ($v in ($item.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' })) {
            $data = [string]$v.Value
            Write-Host "  [$key]"
            Write-Host "    $($v.Name) = $data"
            if (Test-SuspiciousPath $data) {
                Write-Flag "Autorun from suspicious path: $($v.Name) = $data" 'Run-key persistence from user-writable path'
            }
            $hit = Test-SuspiciousCommandLine $data
            if ($hit) {
                Write-Flag "Autorun with suspicious command ('$hit'): $($v.Name) = $data" 'Encoded/obfuscated autorun'
            }
        }
    }

    # ---------------- 6. Other registry persistence points ----------------

    Write-Section 'Registry Persistence Points (IFEO / Winlogon / AppInit)'

    Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options' -ErrorAction SilentlyContinue |
        ForEach-Object {
            $dbg = (Get-ItemProperty -Path $_.PSPath -Name Debugger -ErrorAction SilentlyContinue).Debugger
            if ($dbg) { Write-Flag "IFEO Debugger set for $($_.PSChildName): $dbg" 'Debugger redirect = persistence / logon hijack' }
        }

    Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SilentProcessExit' -ErrorAction SilentlyContinue |
        ForEach-Object {
            $mp = (Get-ItemProperty -Path $_.PSPath -Name MonitorProcess -ErrorAction SilentlyContinue).MonitorProcess
            if ($mp) { Write-Flag "SilentProcessExit monitor for $($_.PSChildName): $mp" 'Process-exit monitor persistence' }
        }

    $wl = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction SilentlyContinue
    if ($wl) {
        if ($wl.Shell -cne 'explorer.exe') {
            Write-Flag "Winlogon Shell modified: $($wl.Shell)" 'Expected: explorer.exe'
        }
        if ($wl.Userinit -cne 'C:\Windows\system32\userinit.exe,') {
            Write-Flag "Winlogon Userinit modified: $($wl.Userinit)" 'Expected: C:\Windows\system32\userinit.exe,'
        }
    }

    $win = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows' -ErrorAction SilentlyContinue
    if ($win -and $win.AppInit_DLLs) {
        Write-Flag "AppInit_DLLs set: $($win.AppInit_DLLs)" 'DLL load into user-mode processes'
    }

    # ---------------- 7. WMI subscriptions ----------------

    Write-Section 'WMI Event Subscriptions'
    try {
        $filters   = @(Get-CimInstance -Namespace 'root/subscription' -ClassName '__EventFilter' -ErrorAction Stop)
        $consumers = @(Get-CimInstance -Namespace 'root/subscription' -ClassName '__EventConsumer' -ErrorAction Stop)
        $bindings  = @(Get-CimInstance -Namespace 'root/subscription' -ClassName '__FilterToConsumerBinding' -ErrorAction Stop)
        Write-Host "  Filters: $($filters.Count)  Consumers: $($consumers.Count)  Bindings: $($bindings.Count)"
        foreach ($c in $consumers) {
            $className = $c.CimClass.CimClassName
            $detail = if ($c.PSObject.Properties['CommandLineTemplate'] -and $c.CommandLineTemplate) {
                $c.CommandLineTemplate
            } elseif ($c.PSObject.Properties['ScriptText'] -and $c.ScriptText) {
                '<script> ' + $c.ScriptText.Substring(0, [Math]::Min(120, $c.ScriptText.Length))
            } else { '' }
            Write-Flag "WMI consumer: [$className] $($c.Name) $detail" 'WMI subscription persistence (survives reboot, runs as SYSTEM)'
        }
    } catch {
        Write-Host "  Could not query root/subscription (run elevated): $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # ---------------- 8. Startup folders ----------------

    Write-Section 'Startup Folders'
    $startupDirs = @(
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
    )
    foreach ($d in $startupDirs) {
        if (-not (Test-Path $d)) { continue }
        Get-ChildItem $d -File -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Host "  $($_.FullName)"
            if ($_.Extension -in '.ps1','.bat','.cmd','.vbs','.js','.jse','.hta','.exe','.dll','.scr') {
                Write-Flag "Executable content in Startup folder: $($_.FullName)" 'Script/executable autostart'
            }
        }
    }

    # ---------------- 9. Event logs (targeted) ----------------

    Write-Section "Event Log: Recently Installed Services (System 7045, last $LogCount)"
    $svcEvents = Get-WinEvent -FilterHashtable @{LogName='System'; Id=7045} -MaxEvents $LogCount -ErrorAction SilentlyContinue
    if ($svcEvents) {
        $svcRows = foreach ($e in $svcEvents) {
            $bin = $e.Properties[1].Value
            if (Test-SuspiciousPath $bin) {
                Write-Flag "7045: service installed from suspicious path: $bin" 'New-service persistence'
            }
            [pscustomobject]@{ TimeCreated = $e.TimeCreated; Service = $e.Properties[0].Value; Binary = $bin }
        }
        $svcRows | Format-Table -AutoSize -Wrap
    } else { Write-Host '  None found.' }

    Write-Section "Event Log: Security - Persistence-Relevant Events (last $LogCount)"
    try {
        $sec = Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4698,4702,4720,4728,4732,4756,1102} -MaxEvents $LogCount -ErrorAction Stop
        $secRows = foreach ($e in $sec) {
            [pscustomobject]@{
                TimeCreated = $e.TimeCreated
                Id          = $e.Id
                Summary     = ($e.Message -split "`n")[0]
            }
        }
        $secRows | Format-Table -AutoSize -Wrap
    } catch {
        Write-Host '  Security log not accessible (run elevated).' -ForegroundColor Yellow
    }

    # ---------------- Summary ----------------

    Write-Section 'Flag Summary'
    if ($script:Findings.Count -eq 0) {
        Write-Host '  No heuristic flags raised. This does NOT prove the host is clean - review the raw output and correlate with telemetry.' -ForegroundColor Green
    } else {
        Write-Host "  $($script:Findings.Count) item(s) flagged for review:" -ForegroundColor Red
        $script:Findings | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    }

} finally {
    if ($OutputPath) { try { Stop-Transcript | Out-Null } catch {} }
}
