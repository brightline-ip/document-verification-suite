@echo off
rem Brightline Document Verification Suite - double-click to install or repair.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" %*
echo.
pause
