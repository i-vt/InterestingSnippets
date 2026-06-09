#Requires -Version 5.1
<#
.SYNOPSIS
    Forensic script to retrieve print job history and active print queue data.

.DESCRIPTION
    Collects print job evidence from:
      - Active print queues (all local printers)
      - Windows Event Log (PrintService operational log)
      - Registry (last-used printer keys)
      - Spool folder artifacts
    Outputs results to the console and optionally exports to CSV/JSON.

.PARAMETER ExportPath
    Directory to save output files. Defaults to the current directory.

.PARAMETER ExportFormat
    Output format: CSV, JSON, or Both. Defaults to Both.

.PARAMETER MaxEvents
    Maximum number of Event Log entries to retrieve. Defaults to 1000.

.PARAMETER IncludeSpoolFiles
    If set, lists spool file artifacts (.SPL / .SHD) from the spool directory.

.EXAMPLE
    .\Get-GetPrinterEvidence.ps1 -ExportPath "C:\ForensicOutput" -ExportFormat Both -IncludeSpoolFiles

.NOTES
    Run as Administrator for full access to event logs and spool directory.
    Tested on Windows 10/11 and Windows Server 2016+.
#>

[CmdletBinding()]
param (
    [string]$ExportPath     = (Get-Location).Path,
    [ValidateSet("CSV","JSON","Both","None")]
    [string]$ExportFormat   = "Both",
    [int]$MaxEvents         = 1000,
    [switch]$IncludeSpoolFiles
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-Section {
    param([string]$Title)
    $line = "=" * 70
    Write-Host "`n$line" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "$line" -ForegroundColor Cyan
}

function ConvertTo-SafeString {
    param($Value)
    if ($null -eq $Value) { return "" }
    return $Value.ToString()
}

# ── 1. Active Print Queue ─────────────────────────────────────────────────────

function Get-ActivePrintJobs {
    Write-Section "ACTIVE PRINT QUEUE JOBS"

    $allJobs = @()

    try {
        $printers = Get-Printer -ErrorAction Stop
    } catch {
        Write-Warning "Could not enumerate printers: $_"
        return $allJobs
    }

    foreach ($printer in $printers) {
        try {
            $jobs = Get-PrintJob -PrinterName $printer.Name -ErrorAction SilentlyContinue
            foreach ($job in $jobs) {
                $entry = [PSCustomObject]@{
                    Source          = "ActiveQueue"
                    TimeStamp       = $job.SubmittedTime
                    PrinterName     = $printer.Name
                    PrinterPort     = $printer.PortName
                    JobId           = $job.Id
                    DocumentName    = $job.DocumentName
                    UserName        = $job.UserName
                    HostMachineName = $job.HostMachineName
                    JobStatus       = $job.JobStatus
                    TotalPages      = $job.TotalPages
                    PagesPrinted    = $job.PagesPrinted
                    Size_Bytes      = $job.Size
                    Priority        = $job.Priority
                    Position        = $job.Position
                    DataType        = $job.Datatype
                }
                $allJobs += $entry
                Write-Host ("[{0}] {1,-40} User: {2,-20} Doc: {3}" -f
                    $job.SubmittedTime, $printer.Name, $job.UserName, $job.DocumentName) -ForegroundColor Green
            }
        } catch {
            Write-Verbose "No jobs or access denied for printer: $($printer.Name)"
        }
    }

    if ($allJobs.Count -eq 0) {
        Write-Host "  No active print jobs found." -ForegroundColor Yellow
    }

    return $allJobs
}

# ── 2. Event Log – PrintService Operational ──────────────────────────────────

function Get-PrintEventLog {
    Write-Section "WINDOWS EVENT LOG — PrintService/Operational"

    $results = @()

    # Ensure the log is enabled
    $logName = "Microsoft-Windows-PrintService/Operational"
    try {
        $logConfig = Get-WinEvent -ListLog $logName -ErrorAction Stop
        if (-not $logConfig.IsEnabled) {
            Write-Warning "PrintService/Operational log is DISABLED. Enabling now requires elevation."
            Write-Warning "To enable manually: wevtutil sl Microsoft-Windows-PrintService/Operational /e:true"
            return $results
        }
    } catch {
        Write-Warning "Cannot access PrintService log: $_"
        return $results
    }

    # Event IDs of interest
    # 307 = Document printed successfully
    # 805 = Print job deleted
    # 316 = Printer driver installed
    # 300 = Printer added
    # 301 = Printer deleted
    $interestingIds = @(300, 301, 307, 316, 805)

    try {
        $filterHash = @{
            LogName = $logName
            Id      = $interestingIds
        }

        $events = Get-WinEvent -FilterHashtable $filterHash -MaxEvents $MaxEvents -ErrorAction Stop

        foreach ($evt in $events) {
            $msg = $evt.Message -replace "`r`n", " " -replace "`n", " "

            # Parse key fields from Event ID 307 (the richest print record)
            $docName    = ""
            $userName   = ""
            $printerName= ""
            $pages      = ""
            $size       = ""
            $port       = ""

            if ($evt.Id -eq 307) {
                # Properties: 0=Doc, 1=JobId, 2=Printer, 3=Port, 4=User, 5=Pages, 6=Size, 7=Flags
                $p = $evt.Properties
                if ($p.Count -ge 7) {
                    $docName     = ConvertTo-SafeString $p[0].Value
                    $printerName = ConvertTo-SafeString $p[2].Value
                    $port        = ConvertTo-SafeString $p[3].Value
                    $userName    = ConvertTo-SafeString $p[4].Value
                    $pages       = ConvertTo-SafeString $p[5].Value
                    $size        = ConvertTo-SafeString $p[6].Value
                }
            }

            $entry = [PSCustomObject]@{
                Source        = "EventLog"
                TimeStamp     = $evt.TimeCreated
                EventId       = $evt.Id
                EventAction   = switch ($evt.Id) {
                    307  { "DocumentPrinted" }
                    805  { "JobDeleted" }
                    316  { "DriverInstalled" }
                    300  { "PrinterAdded" }
                    301  { "PrinterDeleted" }
                    default { "Other" }
                }
                MachineName   = $evt.MachineName
                UserName      = if ($userName) { $userName } else { ConvertTo-SafeString $evt.UserId }
                PrinterName   = $printerName
                PrinterPort   = $port
                DocumentName  = $docName
                Pages         = $pages
                Size_Bytes    = $size
                Message       = $msg.Substring(0, [Math]::Min(200, $msg.Length))
            }

            $results += $entry

            $color = if ($evt.Id -eq 307) { "White" } else { "DarkYellow" }
            Write-Host ("[{0}] ID:{1,-4} {2,-18} User:{3,-20} Doc:{4}" -f
                $evt.TimeCreated, $evt.Id, $entry.EventAction, $entry.UserName, $docName) -ForegroundColor $color
        }

        Write-Host "`n  Total events retrieved: $($results.Count)" -ForegroundColor Cyan

    } catch {
        if ($_.Exception.Message -match "No events|selection criteria|нет событий|условию|No matching") {
            Write-Host "  No matching events found in the log." -ForegroundColor Yellow
        } else {
            Write-Warning "Error reading event log: $_"
        }
    }

    return $results
}

# ── 3. Registry - Printer MRU and Settings ───────────────────────────────────

function Get-PrinterRegistry {
    Write-Section "REGISTRY — Printer Artifacts"

    $results = @()

    $regPaths = @(
        # Per-user printer preferences
        "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\PrinterPorts",
        "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Devices",
        "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows",
        # System-wide printers
        "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Printers",
        # Recent docs printed (if present)
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs"
    )

    foreach ($path in $regPaths) {
        if (Test-Path $path) {
            try {
                $key = Get-Item -Path $path -ErrorAction Stop
                Write-Host "`n  Key: $path" -ForegroundColor Magenta

                # List values
                foreach ($valueName in $key.GetValueNames()) {
                    $val = $key.GetValue($valueName)
                    $entry = [PSCustomObject]@{
                        Source    = "Registry"
                        KeyPath   = $path
                        ValueName = $valueName
                        Data      = ConvertTo-SafeString $val
                    }
                    $results += $entry
                    Write-Host ("    {0,-40} = {1}" -f $valueName, ($entry.Data.Substring(0,[Math]::Min(80,$entry.Data.Length))))
                }

                # For HKLM Printers: enumerate sub-keys (each printer)
                if ($path -like "*\Control\Print\Printers") {
                    $subKeys = Get-ChildItem -Path $path -ErrorAction SilentlyContinue
                    foreach ($sub in $subKeys) {
                        Write-Host "    Printer sub-key: $($sub.PSChildName)" -ForegroundColor DarkGreen
                        $entry = [PSCustomObject]@{
                            Source    = "Registry"
                            KeyPath   = $sub.PSPath
                            ValueName = "(SubKey)"
                            Data      = $sub.PSChildName
                        }
                        $results += $entry
                    }
                }
            } catch {
                Write-Verbose "Cannot read registry path $path : $_"
            }
        } else {
            Write-Verbose "Registry path not found: $path"
        }
    }

    return $results
}

# ── 4. Spool File Artifacts ───────────────────────────────────────────────────

function Get-SpoolArtifacts {
    Write-Section "SPOOL FOLDER ARTIFACTS"

    $results = @()
    $spoolPath = "$env:SystemRoot\System32\spool\PRINTERS"

    if (-not (Test-Path $spoolPath)) {
        Write-Warning "Spool path not accessible: $spoolPath"
        return $results
    }

    $files = @(Get-ChildItem -Path $spoolPath -File -ErrorAction SilentlyContinue |
             Where-Object { $_.Extension -in @(".SPL", ".SHD") })

    if ($files.Count -eq 0) {
        Write-Host "  No spool files found (queue is clear)." -ForegroundColor Yellow
    } else {
        Write-Host "  Found $($files.Count) spool file(s):" -ForegroundColor Yellow
        foreach ($f in $files) {
            $entry = [PSCustomObject]@{
                Source        = "SpoolFile"
                FileName      = $f.Name
                Extension     = $f.Extension
                FullPath      = $f.FullName
                Size_Bytes    = $f.Length
                CreationTime  = $f.CreationTime
                LastWriteTime = $f.LastWriteTime
            }
            $results += $entry
            Write-Host ("  [{0}] {1,-20} {2,10} bytes  Created: {3}" -f
                $f.Extension, $f.Name, $f.Length, $f.CreationTime) -ForegroundColor DarkYellow
        }
    }

    return $results
}

# ── 5. Export Results ─────────────────────────────────────────────────────────

function Export-Results {
    param(
        [object[]]$Data,
        [string]$BaseName
    )

    if (-not $Data -or $Data.Count -eq 0) { return }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $baseFile  = Join-Path $ExportPath ("{0}_{1}" -f $BaseName, $timestamp)

    if ($ExportFormat -in @("CSV","Both")) {
        $csv = "$baseFile.csv"
        $Data | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
        Write-Host "  Exported CSV : $csv" -ForegroundColor Green
    }

    if ($ExportFormat -in @("JSON","Both")) {
        $json = "$baseFile.json"
        $Data | ConvertTo-Json -Depth 5 | Out-File -FilePath $json -Encoding UTF8
        Write-Host "  Exported JSON: $json" -ForegroundColor Green
    }
}

# ── Main ──────────────────────────────────────────────────────────────────────

Write-Host "`n╔══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host   "║          PRINT JOB FORENSIC COLLECTOR  —  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')          ║" -ForegroundColor Cyan
Write-Host   "╚══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host   "  Host     : $env:COMPUTERNAME"
Write-Host   "  User     : $env:USERDOMAIN\$env:USERNAME"
Write-Host   "  Export   : $ExportPath  [$ExportFormat]"

# Check elevation
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltinRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "Not running as Administrator — some data sources may be inaccessible."
}

# Collect
$activeJobs   = @(Get-ActivePrintJobs)
$eventJobs    = @(Get-PrintEventLog)
$regArtifacts = @(Get-PrinterRegistry)
$spoolFiles   = if ($IncludeSpoolFiles) { @(Get-SpoolArtifacts) } else { @() }

# Summary
Write-Section "SUMMARY"
Write-Host "  Active queue jobs  : $($activeJobs.Count)"
Write-Host "  Event log records  : $($eventJobs.Count)"
Write-Host "  Registry entries   : $($regArtifacts.Count)"
Write-Host "  Spool file artifacts: $($spoolFiles.Count)"

# Export
if ($ExportFormat -ne "None") {
    Write-Section "EXPORTING RESULTS"
    if (-not (Test-Path $ExportPath)) { New-Item -ItemType Directory -Path $ExportPath | Out-Null }

    Export-Results -Data $activeJobs   -BaseName "PrintForensics_ActiveQueue"
    Export-Results -Data $eventJobs    -BaseName "PrintForensics_EventLog"
    Export-Results -Data $regArtifacts -BaseName "PrintForensics_Registry"
    if ($IncludeSpoolFiles) {
        Export-Results -Data $spoolFiles -BaseName "PrintForensics_SpoolFiles"
    }
}

Write-Host "`n  Done.`n" -ForegroundColor Cyan
