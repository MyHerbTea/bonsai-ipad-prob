@echo off
setlocal
where pwsh.exe >nul 2>&1
if errorlevel 1 (
  echo ERROR: PowerShell 7 ^(pwsh.exe^) is required.
  exit /b 1
)
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0rc126_phase2a_memory_governor_abab.ps1" %*
exit /b %ERRORLEVEL%
