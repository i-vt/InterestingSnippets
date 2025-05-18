@echo off
setlocal

set "DOMAIN=zimbabwe"
set "USER=username"
set "GROUP=Administrators"
set "FULLUSER=%DOMAIN%\%USER%"

REM Check if the user is already in the group
net localgroup %GROUP% | find /I "%FULLUSER%" >nul
if %ERRORLEVEL%==0 (
    echo %FULLUSER% is already a member of %GROUP%.
) else (
    net localgroup %GROUP% "%FULLUSER%" /add
    if %ERRORLEVEL%==0 (
        echo Successfully added %FULLUSER% to %GROUP%.
    ) else (
        echo Failed to add %FULLUSER% to %GROUP%.
    )
)

gpupdate.exe /force
