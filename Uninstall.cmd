@echo off
setlocal
rem Brightline Document Verification Suite - double-click to uninstall.
rem Windows PowerShell must not inherit PowerShell 7's module path.
set "PSModulePath="
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" -NoPause %*
echo.
pause
