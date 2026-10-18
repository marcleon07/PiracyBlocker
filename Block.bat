@echo off
:: Blocks all sites listed in the blocklist*.txt files. Asks for administrator permission first.
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0PiracyBlocker.ps1" -Action Block
echo.
pause
