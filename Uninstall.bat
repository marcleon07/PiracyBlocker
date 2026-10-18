@echo off
:: Turns off automatic updates, unblocks everything and removes PiracyBlocker from Program Files.
:: Asks for administrator permission first.
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0PiracyBlocker.ps1" -Action Uninstall
echo.
pause
