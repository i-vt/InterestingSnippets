@echo off
setlocal

set DOWNLOAD_URL=https://example.com/yourfile.exe
set DEST_PATH=C:\MyService\yourfile.exe
set SERVICE_NAME=MyService

echo Downloading service binary...
powershell -Command "Invoke-WebRequest -Uri '%DOWNLOAD_URL%' -OutFile '%DEST_PATH%'"

echo Installing service...
sc create %SERVICE_NAME% binPath= "%DEST_PATH%" start= auto

echo Starting service...
sc start %SERVICE_NAME%

echo Done.

endlocal
pause
