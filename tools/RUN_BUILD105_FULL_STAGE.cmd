@echo off
setlocal
cd /d "%~dp0"
where powershell.exe >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Windows PowerShell not found.
  pause
  exit /b 2
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0RUN_BUILD105_GUI.ps1"
set "CODE=%ERRORLEVEL%"
echo.
echo [RESULT] ExitCode=%CODE%. Read the RESULTS folder for the ZIP.
pause
exit /b %CODE%
