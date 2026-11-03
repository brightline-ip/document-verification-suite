# Start Brightline Verification Suite: starts the four local services (and Docker Desktop if needed).
param([switch]$NoPause)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'SuiteCommon.ps1')
try {
    $config = Read-SuiteConfig (Get-RootFromBin $PSScriptRoot)
    Write-Host 'Starting the Brightline Verification Suite...' -ForegroundColor White
    $results = Start-Suite $config
    $ok = $true
    foreach ($k in $results.Keys) { if ($results[$k]) { Write-Good "$k is running" } else { $ok = $false; Write-Bad "$k did not start" } }
    Write-Host ''
    if ($ok) {
        Write-Host 'Ready. Drop a Word or PDF file on "Verify a Document" to check it.' -ForegroundColor Green
    } else {
        Write-Host ('Something did not start. See Troubleshooting in the README; logs are in ' + (Join-Path $config.install_root 'logs')) -ForegroundColor Yellow
    }
    $code = if ($ok) { 0 } else { 1 }
} catch {
    Write-Bad $_.Exception.Message
    $code = 1
}
if (-not $NoPause) { Read-Host '   Press Enter to close this window' | Out-Null }
exit $code
