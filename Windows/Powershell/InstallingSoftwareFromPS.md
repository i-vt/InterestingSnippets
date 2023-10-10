# Installing Software From PowerShell

### Steps:
1. Download the installer
2. Ensure you are running PowerShell as administrator
3. ``Start-Process -FilePath "C:\path\to\python-installer.exe" -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1" -Wait``

### Command breakdown:
- /quiet: Install Python silently.
- InstallAllUsers=1: Install Python for all users.
- PrependPath=1: Add Python to the system PATH.
