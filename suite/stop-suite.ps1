# Stop Brightline Verification Suite: stops only the services this installation started.
param([switch]$NoPause)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'SuiteCommon.ps1')
try {
    $config = Read-SuiteConfig (Get-RootFromBin $PSScriptRoot)
    Write-Host 'Stopping the Brightline Verification Suite...' -ForegroundColor White
    Stop-Suite $config
    Write-Good 'Stopped. Your documents, reports and settings are kept.'
    if ($config.workbench_mode -eq 'Docker') { Write-Info 'Docker Desktop itself keeps running; you can quit it from its tray icon.' }
    $code = 0
} catch {
    Write-Bad $_.Exception.Message
    $code = 1
}
if (-not $NoPause) { Read-Host '   Press Enter to close this window' | Out-Null }
exit $code
