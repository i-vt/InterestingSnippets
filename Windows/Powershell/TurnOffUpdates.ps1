# Stop the Windows Update Service
Stop-Service -Name wuauserv -Force

# Disable the Windows Update Service
Set-Service -Name wuauserv -StartupType Disabled

# Verify the Service Status
Get-Service -Name wuauserv

# Modify Registry Settings: Create or Navigate to the WindowsUpdate Key
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Force

# Disable Automatic Updates
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate" -Value 1 -Type DWord

# Confirm the Change
Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"

# List Windows Update Scheduled Tasks
$tasks = Get-ScheduledTask | Where-Object { $_.TaskName -like "*WindowsUpdate*" }

# Disable the Tasks
foreach ($task in $tasks) {
    Disable-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath
}

# Verify the Tasks are Disabled
Get-ScheduledTask | Where-Object { $_.TaskName -like "*WindowsUpdate*" } | Select TaskName, State

# Disable Windows Update Medic Service: Take Ownership of the Service Registry Key
$acl = Get-Acl "HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc"
$person = [System.Security.Principal.NTAccount]"Administrators"
$acl.SetOwner($person)
Set-Acl -Path "HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" -AclObject $acl

# Set the Service to Disabled
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" -Name "Start" -Value 4

# Stop the Service
Stop-Service -Name WaaSMedicSvc -Force

# Use Group Policy Settings via PowerShell: Install the PolicyFileEditor Module
Install-Module -Name PolicyFileEditor -Scope CurrentUser

# Import the Module
Import-Module PolicyFileEditor

# Set Policy to Disable Automatic Updates
Set-PolicyFileEntry -Path "$env:windir\System32\GroupPolicy\Machine\Registry.pol" -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" -ValueName "NoAutoUpdate" -Data 1 -Type DWord

# Force Group Policy Update
gpupdate /force

# Re-Enabling Windows Updates: Enable Windows Update Service
Set-Service -Name wuauserv -StartupType Manual
Start-Service -Name wuauserv

# Remove Registry Changes
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate"

# Enable Scheduled Tasks
foreach ($task in $tasks) {
    Enable-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath
}

# Enable Windows Update Medic Service
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" -Name "Start" -Value 3
Start-Service -Name WaaSMedicSvc
