@echo off
setlocal
where pwsh.exe >nul 2>&1
if errorlevel 1 (
  echo ERROR: PowerShell 7+ is required. Run the .ps1 directly from an existing PowerShell 7 session if pwsh.exe is not on PATH.
  exit /b 1
)
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0rc126_phase2b_heap_pressure_relief_abab.ps1" %*
exit /b %ERRORLEVEL%
