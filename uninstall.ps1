<#
.SYNOPSIS
  Removes the Brightline Document Verification Suite: what Setup created, nothing else.

.DESCRIPTION
  Stops the suite's services, removes its shortcuts, its Docker containers and image (Docker mode) and its
  install folder. Your verification projects, reports, source library and the Workbench database are kept
  unless you choose to delete them (you are asked; or pass -RemoveData / -KeepData).
  Python, Node.js, Docker Desktop and PostgreSQL are never uninstalled.

.PARAMETER InstallRoot
  The install folder (default: the installation this script belongs to, else %LOCALAPPDATA%\Brightline\DocVerify).
.PARAMETER RemoveData
  Also permanently delete your data (projects, reports, source library, Workbench database volumes).
.PARAMETER KeepData
  Keep your data without asking.
.PARAMETER Yes
  Do not ask for confirmation (requires -RemoveData or -KeepData).
#>
[CmdletBinding()]
param(
    [string]$InstallRoot,
    [switch]$RemoveData,
    [switch]$KeepData,
    [switch]$Yes,
    [switch]$NoPause
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot $(if (Test-Path (Join-Path $PSScriptRoot 'SuiteCommon.ps1')) { 'SuiteCommon.ps1' } else { 'suite\SuiteCommon.ps1' }))

function Remove-Tree([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    # Unlink junctions and symbolic links first, without following them, so a linked folder's target
    # (for example data moved to another drive) is never emptied.
    $links = @(Get-ChildItem -LiteralPath $Path -Recurse -Force -Attributes ReparsePoint -ErrorAction SilentlyContinue |
        Sort-Object { $_.FullName.Length } -Descending)
    foreach ($link in $links) {
        if ($link.PSIsContainer) { [IO.Directory]::Delete($link.FullName, $false) } else { [IO.File]::Delete($link.FullName) }
    }
    try { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop } catch {}
    if (Test-Path -LiteralPath $Path) {
        # Long paths (for example deep node_modules folders): empty the folder with robocopy, then remove it.
        $empty = Join-Path ([IO.Path]::GetTempPath()) ('bl-empty-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $empty | Out-Null
        $null = & robocopy.exe $empty $Path /MIR /XJ /NFL /NDL /NJH /NJS /NP
        Remove-Item -LiteralPath $empty -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $Path) { throw "Could not remove $Path. Close any program using files there and run Uninstall again." }
}

$exit = 0
try {
    if ($RemoveData -and $KeepData) { throw 'Use either -RemoveData or -KeepData, not both.' }
    if ($Yes -and -not ($RemoveData -or $KeepData)) { throw '-Yes needs -RemoveData or -KeepData, so your data is never deleted without an explicit choice.' }
    if (-not $InstallRoot) {
        $parent = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
        if ((Split-Path -Leaf $PSScriptRoot) -eq 'bin' -and (Test-Path -LiteralPath (Join-Path $parent $script:SuiteMarker))) { $InstallRoot = $parent }
        else { $InstallRoot = Join-Path $env:LOCALAPPDATA 'Brightline\DocVerify' }
    }
    $InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
    $paths = Get-SuitePaths $InstallRoot
    if (-not (Test-Path -LiteralPath $paths.Marker -PathType Leaf)) {
        throw "No Brightline Verification Suite installation was found in $InstallRoot (the marker file is missing). Nothing was changed."
    }
    if ($InstallRoot.TrimEnd('\') -eq ([IO.Path]::GetPathRoot($InstallRoot)).TrimEnd('\') -or $InstallRoot -ieq $env:USERPROFILE -or $InstallRoot -ieq $env:LOCALAPPDATA) {
        throw "Refusing to remove $InstallRoot."
    }
    $config = $null
    try { $config = Read-SuiteConfig $InstallRoot } catch { Write-Warn2 'The suite configuration is missing; removing files only.' }

    Write-Host 'Uninstall the Brightline Document Verification Suite' -ForegroundColor White
    Write-Info "Install folder: $InstallRoot"
    Write-Info 'This removes the program files, shortcuts and (Docker mode) the Workbench containers and image.'
    Write-Info 'Python, Node.js, Docker Desktop and PostgreSQL stay installed.'
    if (-not ($RemoveData -or $KeepData)) {
        Write-Host ''
        Write-Info "Your data: verification projects and reports ($($paths.DocVerifyData)), the Get Files source"
        Write-Info 'library, and the Research Workbench database with its stored sources.'
        $RemoveData = Read-YesNo 'Also PERMANENTLY DELETE all of this data? (No keeps it for a later reinstall)' $false
    }
    if (-not $Yes) {
        $what = if ($RemoveData) { 'Uninstall and DELETE your data now?' } else { 'Uninstall now (your data is kept)?' }
        if (-not (Read-YesNo $what $false)) { Write-Info 'Cancelled. Nothing was changed.'; if (-not $NoPause) { Read-Host '   Press Enter to close' | Out-Null }; exit 0 }
    }
    Set-Location -LiteralPath ([IO.Path]::GetTempPath())

    if ($config) {
        Write-Step 'Stopping the services'
        try { Stop-Suite $config; Write-Good 'Services stopped' } catch { Write-Warn2 ('Could not stop every service: ' + $_.Exception.Message) }

        if ($config.workbench_mode -eq 'Docker' -and $config.docker) {
            Write-Step 'Removing the Workbench containers'
            if (Start-DockerEngine $config.docker 120) {
                $downArgs = @('down', '--remove-orphans')
                if ($RemoveData) { $downArgs += '--volumes' }
                $code = Invoke-WorkbenchCompose $config $downArgs -Quiet
                if ($code -eq 0) { Write-Good ("Containers removed{0}" -f $(if ($RemoveData) { ' together with the database and stored sources' } else { '' })) }
                else { $exit = 1; Write-Warn2 "docker compose down failed (code $code); see $($paths.Logs)\docker-compose.log" }
                if ($config.workbench_image) {
                    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
                    $null = & $config.docker image rm $config.workbench_image 2>&1
                    $ErrorActionPreference = $old
                    if ($LASTEXITCODE -eq 0) { Write-Good "Image $($config.workbench_image) removed" }
                }
                if (-not $RemoveData) {
                    Write-Info ("Kept Docker volumes {0}_pgdata and {0}_workbench-data (your Workbench data)." -f $config.compose_project)
                    Write-Info ("To delete them later: docker volume rm {0}_pgdata {0}_workbench-data" -f $config.compose_project)
                }
            } else {
                $exit = 1
                Write-Warn2 'Docker Desktop is not running, so the Workbench containers could not be removed. Start Docker Desktop and run:'
                Write-Info ("docker compose -p {0} down{1}" -f $config.compose_project, $(if ($RemoveData) { ' --volumes' } else { '' }))
            }
        }
        if ($config.workbench_mode -eq 'Native' -and $RemoveData -and $config.postgres) {
            Write-Step 'Removing the Workbench database'
            $pg = $config.postgres
            $pw = if ($Yes) { '' } else { ConvertFrom-SecureToPlain (Read-Host -Prompt '   PostgreSQL administrator password to delete the database (Enter to skip)' -AsSecureString) }
            $done = $false
            if ($pw -and $config.node -and (Test-Path -LiteralPath (Join-Path $paths.Bin 'pg-provision.mjs'))) {
                $saved = @{ h = $env:PGHOST; p = $env:PGPORT; u = $env:PGUSER; w = $env:PGPASSWORD }
                try {
                    $env:PGHOST = $pg.host; $env:PGPORT = [string]$pg.port; $env:PGUSER = 'postgres'; $env:PGPASSWORD = $pw
                    $env:WB_DIR = $paths.Workbench; $env:WB_ROLE = $pg.role; $env:WB_DB = $pg.database
                    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
                    $null = & $config.node (Join-Path $paths.Bin 'pg-provision.mjs') drop 2>&1
                    $done = ($LASTEXITCODE -eq 0); $ErrorActionPreference = $old
                } finally { $env:PGHOST = $saved.h; $env:PGPORT = $saved.p; $env:PGUSER = $saved.u; $env:PGPASSWORD = $saved.w; $env:WB_DIR = $null; $env:WB_ROLE = $null; $env:WB_DB = $null; $pw = $null }
            }
            if ($done) { Write-Good 'Database and role removed' }
            else { Write-Info ("To delete it yourself (psql as postgres): DROP DATABASE {0}; DROP ROLE {1};" -f $pg.database, $pg.role) }
        }

        Write-Step 'Removing shortcuts'
        foreach ($lnk in @($config.shortcuts)) {
            if ($lnk -and $lnk.EndsWith('.lnk') -and (Test-Path -LiteralPath $lnk)) { Remove-Item -LiteralPath $lnk -Force; Write-Good ('Removed ' + (Split-Path -Leaf $lnk)) }
        }
        if ($config.shortcut_folder -and (Test-Path -LiteralPath $config.shortcut_folder) -and -not (Get-ChildItem -LiteralPath $config.shortcut_folder -Force | Select-Object -First 1)) {
            Remove-Item -LiteralPath $config.shortcut_folder -Force
        }
    }

    Write-Step 'Removing files'
    if ($RemoveData) {
        Remove-Tree $InstallRoot
        Write-Good "Removed $InstallRoot"
    } else {
        foreach ($child in Get-ChildItem -LiteralPath $InstallRoot -Force) {
            if ($child.Name -in @('data', $script:SuiteMarker)) { continue }
            Remove-Tree $child.FullName
        }
        Write-Good "Removed the program files; your data is still in $($paths.Data)"
    }
    Write-Host ''
    Write-Host 'Uninstall finished.' -ForegroundColor Green
    Write-Info 'If you no longer need it, revoke the OpenAI API key at https://platform.openai.com/api-keys.'
    Write-Info 'Python, Node.js, Docker Desktop and PostgreSQL can be removed in Windows Settings > Apps if you do not need them.'
} catch {
    Write-Bad $_.Exception.Message
    $exit = 1
}
if (-not $NoPause) { Read-Host '   Press Enter to close this window' | Out-Null }
exit $exit
