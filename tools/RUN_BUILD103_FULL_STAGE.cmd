@echo off
setlocal
cd /d "%~dp0"
set "SCRIPT=%~dp0rc126_build103_full_stage_certification.py"
if not exist "%SCRIPT%" (
  echo [ERROR] Missing full-stage test script. Extract entire runner ZIP first.
  pause
  exit /b 2
)
where py >nul 2>nul
if not errorlevel 1 (
  py -3 "%SCRIPT%" --output "%~dp0RESULTS"
) else (
  python "%SCRIPT%" --output "%~dp0RESULTS"
)
set "CODE=%ERRORLEVEL%"
echo.
echo All test evidence is in RESULTS. ExitCode=%CODE%
pause
exit /b %CODE%
