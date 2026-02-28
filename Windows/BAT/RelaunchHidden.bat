@echo off
if not "%~1"=="h" (
    powershell -WindowStyle Hidden -Command "Start-Process -FilePath '%~f0' -ArgumentList 'h' -WindowStyle Hidden"
    exit /b
)
