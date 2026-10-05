@echo off
setlocal
where pwsh.exe >nul 2>&1
if errorlevel 1 (
  echo ERROR: PowerShell 7+ is required.
  exit /b 1
)
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0rc126_phase2c_metal_prefill_measurement.ps1" %*
exit /b %ERRORLEVEL%
