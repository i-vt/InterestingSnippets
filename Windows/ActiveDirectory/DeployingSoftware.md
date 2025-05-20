# Software Deployment via GPO & RMM: `updatepolicy.exe` / `updatepolicy.dll`

## Overview

This guide demonstrates how to deploy `updatepolicy.exe` or `updatepolicy.dll` using:

- **Active Directory Group Policy (GPO)**
- **Remote Monitoring & Management (RMM) tools** (e.g., NinjaRMM, Kaseya, etc.)

---

## 📦 Part 1: Deployment via Active Directory Group Policy

### 1. Deploy `.EXE` using GPO Startup Script

**Step-by-step:**

1. Place `updatepolicy.exe` in a network-accessible share:

```text
\\DC01\Software\updatepolicy.exe
```

2. Create a batch script `deploy_updatepolicy.bat`:

```bat
@echo off
\\DC01\Software\updatepolicy.exe /silent
```

3. Open **Group Policy Management**, create/edit a GPO:

```
Computer Configuration → Policies → Windows Settings → Scripts (Startup) → Startup
```

4. Add `deploy_updatepolicy.bat` to the Startup script section.

5. Link the GPO to your target OU.

6. Optional: On a client, force GPO update:

```cmd
gpupdate /force
```

---

### 2. Deploy `.DLL` Using `rundll32` or PowerShell Loader

#### A. If the DLL exports a valid function:

```bat
rundll32.exe \\DC01\Software\updatepolicy.dll,EntryPoint
```

> Replace `EntryPoint` with the actual exported function name.

#### B. Using PowerShell Reflective Loader:

```powershell
powershell -ExecutionPolicy Bypass -WindowStyle Hidden -Command "IEX (New-Object Net.WebClient).DownloadString('http://DC01/updatepolicy_loader.ps1')"
```

---

## Part 2: Deployment via RMM Tools

### 1. Executable Deployment via Script Task

```bat
@echo off
curl -o C:\Windows\Temp\updatepolicy.exe http://<your-internal-server>/updatepolicy.exe
C:\Windows\Temp\updatepolicy.exe /silent
```

> Upload and run this via your RMM platform's scripting interface.

---

### 2. DLL Deployment via `rundll32` or PowerShell

#### A. Using `rundll32`:

```bat
curl -o C:\Windows\Temp\updatepolicy.dll http://<your-internal-server>/updatepolicy.dll
rundll32 C:\Windows\Temp\updatepolicy.dll,EntryPoint
```

#### B. Using PowerShell Reflective DLL Loader:

```powershell
Invoke-WebRequest -Uri http://<your-server>/updatepolicy_loader.ps1 -OutFile C:\Windows\Temp\loader.ps1
powershell -ExecutionPolicy Bypass -File C:\Windows\Temp\loader.ps1
```
