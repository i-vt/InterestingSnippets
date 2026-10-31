#Requires -Version 3.0
<#
.SYNOPSIS
    Rates how strongly this Windows machine appears to be a virtual machine.

.DESCRIPTION
    Gathers read-only virtualization evidence from WMI/CIM (hardware vendor
    strings, BIOS serial/version, SMBIOS asset tag, baseboard, CPU model,
    disk models, NIC OUIs, PCI vendor IDs, guest-agent services, the CPUID
    hypervisor bit, and Hyper-V host-vs-guest service differences) and
    converts it into a 1-10 rating with one of five verdicts:

        Rating  Verdict
        1-2     not a VM
        3-4     probably not a VM
        5       unsure but mixed signals
        6-7     likely a VM
        8-10    100% VM

    Raw evidence is scored around zero (positive points = VM signals,
    negative points = physical-machine signals); +5 is then added to shift
    "no evidence either way" to the neutral 5. Every matched signal is
    listed with the points it added or subtracted, so the verdict is
    auditable and the weights are easy to tweak.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-VmRating.ps1

.NOTES
    Read-only; no admin is required, although a few signals (SMBIOS asset
    tag, some services) are only visible when elevated.

    Design notes for tricky cases:
      - A bare-metal Hyper-V host scores as PHYSICAL: it has the 'vmms'
        host service (-3), a real OEM manufacturer (-2), and Hyper-V
        integration services (+1) only cancel each other out.
      - WSL2 / Virtualization-Based Security / Credential Guard set the
        CPUID hypervisor bit on PHYSICAL machines, so that bit alone is
        treated as neutral (0) and explained in the evidence list.
      - VMware Workstation / VirtualBox host-only adapters and the WSL2 /
        Hyper-V vSwitch pseudo-NICs are excluded from MAC matching, so a
        physical machine with virtualization software installed does not
        get false-positive MAC points.
      - There are deliberately no timing/RDTSC tricks: they are noisy and
        slow. Deterministic hardware identity strings only.
#>
[CmdletBinding()]
param()

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

# ----------------------------- signal patterns ------------------------------
$vmVendorPattern = 'VMware|innotek|VirtualBox|QEMU|KVM|Xen|Parallels|Bochs|OpenStack|oVirt|RHEV|Amazon EC2|Google'
$vmModelPattern  = 'Virtual Machine|Virtual Platform|VirtualBox|HVM domU|KVM|Google Compute Engine|Standard PC \(QEMU|Bochs'
$vmBiosPattern   = 'VMware|innotek|VirtualBox|QEMU|Xen|Amazon|EC2|Hyper-V|Google'
$vmDiskPattern   = 'VMware|VBOX|Virtual|QEMU|Amazon|Google|Msft'
$vmCpuPattern    = 'QEMU|vCPU|Virtual CPU'
$oemPattern      = 'Dell|HP|Hewlett|Lenovo|ASUS|ASUSTeK|Gigabyte|Micro-Star|MSI|ASRock|Apple|Samsung|Acer|Toshiba|Fujitsu|Supermicro|Intel|NEC|LG|Sony|Panasonic|Getac|Shuttle|Biostar|Clevo|Tongfang'

# Known virtualization NIC OUIs: VMware, Hyper-V/Azure, VirtualBox, Xen,
# Parallels, QEMU/KVM, Virtual PC.
$vmMacPattern = '^(005069|000C29|001C14|005056|00155D|080027|00163E|001C42|525400|0003FF)'

# Host-only / pseudo NICs that must NOT count as guest NICs: VMware Workstation
# (VMnet), VirtualBox host-only, and WSL2/Hyper-V vSwitch adapters all live on
# physical machines and would otherwise trigger false-positive MAC points.
$hostOnlyNic = 'VMnet|Host-Only|vEthernet|Default Switch|Hyper-V Virtual|Loopback|Kernel|Pseudo|Miniport|Bluetooth|Npcap|TAP-Windows|VPN'

$guestAgentServices = '^(VMTools|VBoxService|VBoxTray|qemu-ga|XenSvc|WindowsAzureGuestAgent|GCEAgent)$'

$vmPciVendorPattern = 'VEN_15AD|VEN_80EE|VEN_1AF4|VEN_5853'   # VMware, VirtualBox, VirtIO (KVM), Xen
$vmbusPattern       = 'VMBUS'                                  # Hyper-V synthetic bus

# ------------------------------- data harvest --------------------------------
$cs        = Get-CimInstance Win32_ComputerSystem
$bios      = Get-CimInstance Win32_BIOS
$enclosure = Get-CimInstance Win32_SystemEnclosure
$baseboard = Get-CimInstance Win32_BaseBoard
$cpus      = @(Get-CimInstance Win32_Processor)
$disks     = @(Get-CimInstance Win32_DiskDrive)
$nics      = @(Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled })
$pnp       = @(Get-CimInstance Win32_PnPEntity)
$services  = @(Get-CimInstance Win32_Service | ForEach-Object { $_.Name })

# ----------------------------- evidence: system ------------------------------
if ($cs) {
    if ($cs.Manufacturer -match $vmVendorPattern) {
        Add-Signal 4 "ComputerSystem manufacturer '$($cs.Manufacturer)' is a known virtual-platform vendor"
    }
    if ($cs.Model -match $vmModelPattern) {
        Add-Signal 4 "ComputerSystem model '$($cs.Model)' is a known virtual-machine model"
    }
    if ($cs.Manufacturer -match $oemPattern) {
        Add-Signal -2 "ComputerSystem manufacturer '$($cs.Manufacturer)' is a known physical OEM"
    }
    if ($cs.HypervisorPresent -eq $true) {
        Add-Signal 0 "CPUID hypervisor bit is set - a hypervisor is running (VM, Hyper-V host, or VBS/Credential Guard/WSL2: neutral by itself)"
    }
    elseif ($cs.HypervisorPresent -eq $false) {
        Add-Signal -3 "CPUID hypervisor bit is NOT set - no hypervisor is running (strong bare-metal signal)"
    }
}

# -------------------------------- evidence: BIOS -----------------------------
if ($bios) {
    if ($bios.SerialNumber -match $vmBiosPattern) {
        Add-Signal 3 "BIOS serial number '$($bios.SerialNumber)' looks virtualised"
    }
    if ($bios.SMBIOSBIOSVersion -match $vmBiosPattern) {
        Add-Signal 3 "BIOS version '$($bios.SMBIOSBIOSVersion)' looks virtualised"
    }
}

# ------------------------- evidence: enclosure / baseboard -------------------
if ($enclosure -and $enclosure.SMBIOSAssetTag -match 'VMware-|VirtualBox|Xen|Amazon EC2|Google') {
    Add-Signal 2 "SMBIOS asset tag '$($enclosure.SMBIOSAssetTag)' is written by a hypervisor"
}
if ($baseboard -and ($baseboard.Manufacturer -match $vmVendorPattern -or $baseboard.Product -match $vmModelPattern)) {
    Add-Signal 2 "BaseBoard '$($baseboard.Manufacturer) / $($baseboard.Product)' is virtual"
}

# -------------------------------- evidence: CPU ------------------------------
foreach ($c in $cpus) {
    if ($c.Name -match $vmCpuPattern) {
        Add-Signal 3 "CPU identifies itself as '$($c.Name)'"
        break
    }
}

# -------------------------------- evidence: disks ----------------------------
foreach ($d in $disks) {
    if ($d.Model -match $vmDiskPattern) {
        Add-Signal 2 "Disk '$($d.Model)' is a virtual disk"
        break
    }
}

# -------------------------------- evidence: NICs -----------------------------
foreach ($n in $nics) {
    if ($n.Description -match $hostOnlyNic) { continue }
    $mac = ($n.MACAddress -replace '[^0-9A-Fa-f]', '').ToUpper()
    if ($mac.Length -ge 6 -and $mac -match $vmMacPattern) {
        Add-Signal 2 "MAC address $mac (on '$($n.Description)') has a known virtual-machine OUI"
        break
    }
}

# ------------------------------ evidence: PCI devices ------------------------
$vmPnp = 0
$vmbusPnp = 0
foreach ($dev in $pnp) {
    if ($dev.PNPDeviceID -match $vmPciVendorPattern) { $vmPnp++ }
    elseif ($dev.PNPDeviceID -match $vmbusPattern)   { $vmbusPnp++ }
}
if ($vmPnp -gt 0) {
    Add-Signal 2 "$vmPnp PCI device(s) from a virtual chipset vendor (VMware / VirtualBox / VirtIO / Xen)"
}
elseif ($vmbusPnp -gt 0) {
    Add-Signal 1 "VMBus device present - Hyper-V synthetic hardware (guest VM, or a Hyper-V host)"
}

# -------------------------------- evidence: services -------------------------
$guestSvcHit = @($services | Where-Object { $_ -match $guestAgentServices })
if ($guestSvcHit.Count -gt 0) {
    Add-Signal 3 "Guest-agent service '$($guestSvcHit[0])' is installed (VMware Tools / VirtualBox / QEMU / cloud agent)"
}
if ($services -contains 'vmms') {
    Add-Signal -3 "Service 'vmms' (Hyper-V Virtual Machine Management) is present - this is a Hyper-V HOST, i.e. bare metal"
}
elseif (@($services | Where-Object { $_ -match '^vmic' }).Count -gt 0) {
    Add-Signal 1 "Hyper-V guest integration services (vmic*) are installed - guest VM or Hyper-V host"
}

# ---------------------------------- scoring ----------------------------------
$rawScore = $script:score
$rating   = [Math]::Max(1, [Math]::Min(10, $rawScore + 5))   # shift so that "no evidence" = 5 = unsure

$verdict = switch ($rating) {
    { $_ -le 2 } { 'not a VM'; break }
    { $_ -le 4 } { 'probably not a VM'; break }
    { $_ -eq 5 } { 'unsure but mixed signals'; break }
    { $_ -le 7 } { 'likely a VM'; break }
    default      { '100% VM' }
}

$color = if ($rating -le 4) { 'Green' } elseif ($rating -le 7) { 'Yellow' } else { 'Red' }

# ---------------------------------- output -----------------------------------
Write-Host ''
Write-Host '=============================================================='
Write-Host ("  Virtualization rating : {0}/10" -f $rating) -ForegroundColor $color
Write-Host ("  Verdict               : {0}"  -f $verdict) -ForegroundColor $color
Write-Host '=============================================================='
Write-Host ("  Raw evidence score: {0}  (positive = VM signals, negative = physical signals)" -f $rawScore)
Write-Host '--------------------------------------------------------------'
if ($script:reasons.Count -gt 0) {
    foreach ($r in $script:reasons) { Write-Host "   $r" }
}
else {
    Write-Host '   (no signals collected - unable to determine anything)'
}
Write-Host '--------------------------------------------------------------'
Write-Host '  Bands: 1-2 = not a VM | 3-4 = probably not a VM | 5 = unsure but mixed signals'
Write-Host '         6-7 = likely a VM | 8-10 = 100% VM'
Write-Host '=============================================================='
Write-Host ''
Write-Host $verdict -ForegroundColor $color
