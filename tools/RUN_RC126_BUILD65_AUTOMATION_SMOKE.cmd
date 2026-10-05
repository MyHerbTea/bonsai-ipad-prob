@echo off
setlocal
where pwsh.exe >nul 2>&1
if errorlevel 1 (
  echo ERROR: PowerShell 7 ^(pwsh.exe^) is required.
  exit /b 1
)
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0rc126_build65_automation_smoke.ps1" %*
exit /b %ERRORLEVEL%
