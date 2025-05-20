# Deployment via RMM Tools

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
