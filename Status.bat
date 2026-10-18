@echo off
:: Shows whether PiracyBlocker is on and how many sites are blocked.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0PiracyBlocker.ps1" -Action Status
echo.
pause
