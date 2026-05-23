#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Enables automatic login on Windows 10.
.DESCRIPTION
    - Detects local user accounts; if only one exists, selects it automatically.
    - Detects if Windows Hello PIN is configured and disables the
      "Require Windows Hello sign-in" requirement so password-based auto-login works.
    - Sets the Winlogon registry keys for auto-login.
    Must be run as Administrator.
.NOTES
    WARNING: Your password is stored in plain text in the registry.
    Only use this on a physically secure machine.

HINT:

If all else fails with resetting the PW, just make a new acc: 
net user NewAdmin SomePassword /add
net localgroup Administrators NewAdmin /add
#>

# -- Detect local user accounts --
$AllUsers = Get-LocalUser | Where-Object { $_.Enabled -eq $true }

if ($AllUsers.Count -eq 0) {
    Write-Host '[ERROR] No enabled local user accounts found.' -ForegroundColor Red
    pause; exit 1
}
elseif ($AllUsers.Count -eq 1) {
    $Username = $AllUsers.Name
    Write-Host "Only one local user detected: '$Username' -- using that account.`n" -ForegroundColor Cyan
}
else {
    Write-Host 'Multiple enabled local users found:' -ForegroundColor Yellow
    $i = 1
    foreach ($u in $AllUsers) {
        Write-Host "  [$i] $($u.Name)"
        $i++
    }
    $choice = Read-Host "`nSelect a user (1-$($AllUsers.Count))"
    if ($choice -lt 1 -or $choice -gt $AllUsers.Count) {
        Write-Host '[ERROR] Invalid selection.' -ForegroundColor Red
        pause; exit 1
    }
    $Username = $AllUsers[$choice - 1].Name
}

# -- Detect and handle Windows Hello PIN --
$UserSID = (Get-LocalUser -Name $Username).SID.Value
$NgcPath = "$env:SystemRoot\ServiceProfiles\LocalService\AppData\Local\Microsoft\Ngc"
$PinConfigured = $false

if (Test-Path $NgcPath) {
    $NgcItems = Get-ChildItem -Path $NgcPath -Directory -ErrorAction SilentlyContinue
    if ($NgcItems.Count -gt 0) {
        $PinConfigured = $true
    }
}

if ($PinConfigured) {
    Write-Host '[INFO] Windows Hello PIN appears to be configured.' -ForegroundColor Yellow
    Write-Host '       Auto-login requires password, not PIN.' -ForegroundColor Yellow
    Write-Host '       Disabling "Require Windows Hello sign-in for Microsoft accounts"...' -ForegroundColor Yellow
    Write-Host ''

    $HelloPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device'
    if (Test-Path $HelloPath) {
        Set-ItemProperty -Path $HelloPath -Name 'DevicePasswordLessBuildVersion' -Value 0 -Force
        Write-Host '[OK] Windows Hello sign-in requirement disabled.' -ForegroundColor Green
    }
}

# -- Prompt for password --
$SecurePass = Read-Host "Enter the PASSWORD for '$Username'" -AsSecureString
$PlainPass  = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
)

if ([string]::IsNullOrWhiteSpace($PlainPass)) {
    Write-Host '[ERROR] Password cannot be empty.' -ForegroundColor Red
    pause; exit 1
}

# -- Set auto-login registry keys --
$RegPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'

try {
    Set-ItemProperty -Path $RegPath -Name 'AutoAdminLogon'    -Value '1'        -Force
    Set-ItemProperty -Path $RegPath -Name 'DefaultUserName'   -Value $Username  -Force
    Set-ItemProperty -Path $RegPath -Name 'DefaultPassword'   -Value $PlainPass -Force
    Set-ItemProperty -Path $RegPath -Name 'DefaultDomainName' -Value $env:COMPUTERNAME -Force

    Remove-ItemProperty -Path $RegPath -Name 'AutoLogonCount' -ErrorAction SilentlyContinue

    Write-Host ''
    Write-Host '[OK] Auto-login enabled for this PC.' -ForegroundColor Green
    Write-Host '     Restart your PC to take effect.' -ForegroundColor Cyan
    Write-Host ''
}
catch {
    Write-Host "[ERROR] Failed to set registry values: $_" -ForegroundColor Red
}
finally {
    $PlainPass = $null
    [GC]::Collect()
}

pause
