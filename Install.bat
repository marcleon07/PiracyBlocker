@echo off
:: Installs PiracyBlocker to Program Files and turns on automatic updates at startup and daily.
:: Asks for administrator permission first.
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0PiracyBlocker.ps1" -Action Install
echo.
pause
