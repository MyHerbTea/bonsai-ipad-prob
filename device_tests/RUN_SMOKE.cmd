@echo off
setlocal
cd /d "%~dp0"
if not exist "config.local.json" (
  echo [ERROR] Missing config.local.json. Read README.md.
  pause
  exit /b 2
)
where py >nul 2>nul
if %ERRORLEVEL% EQU 0 (
  py -3 certify.py --suite smoke
) else (
  python certify.py --suite smoke
)
set RC=%ERRORLEVEL%
echo.
echo Certification finished. Inspect results folder. ExitCode=%RC%
pause
exit /b %RC%
