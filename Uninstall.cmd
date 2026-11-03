@echo off
rem Brightline Document Verification Suite - double-click to uninstall.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" -NoPause %*
echo.
pause
