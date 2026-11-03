# Open Research Workbench: makes sure the Workbench runs, puts its access token on the clipboard and opens it.
param([switch]$NoPause, [switch]$NoBrowser)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'SuiteCommon.ps1')
try {
    $config = Read-SuiteConfig (Get-RootFromBin $PSScriptRoot)
    $paths = Get-SuitePaths $config.install_root
    if (-not (Test-WorkbenchReady $config).Ok) {
        Write-Info 'The Research Workbench is not running yet; starting it...'
        if (-not (Start-Workbench $config)) { throw 'The Research Workbench could not be started. Try "Start Brightline Verification Suite".' }
    }
    $url = 'http://127.0.0.1:{0}/' -f $config.ports.workbench
    $token = Read-SecretFile $paths.WorkbenchToken
    if ($token) {
        Set-Clipboard -Value $token
        Write-Info 'The Workbench is protected by an access token, which is now on your clipboard.'
        Write-Info 'If the page asks for it, click the box and press Ctrl+V, then confirm. (Once per browser session.)'
    }
    if (-not $NoBrowser) { Start-Process $url }
    Write-Good "Research Workbench: $url"
    $code = 0
} catch {
    Write-Bad $_.Exception.Message
    $code = 1
}
if (-not $NoPause) { Read-Host '   Press Enter to close this window' | Out-Null }
exit $code
