<#
.SYNOPSIS
  Installs the Brightline Document Verification Suite for the current Windows user.

.DESCRIPTION
  Installs the four bundled tools (Research Verification Workbench, Document Verification, Context Forge,
  Get Files) into a per-user folder, connects them to each other, creates Start Menu shortcuts and a
  "Verify a Document" drag-and-drop shortcut on the Desktop, and starts everything.

  Missing prerequisites (Python 3.12, Node.js LTS, Docker Desktop or PostgreSQL) are explained and offered for
  installation through winget; nothing is installed without your "yes". Re-running Setup repairs or updates an
  existing installation and keeps your data, tokens and (unless you choose otherwise) your OpenAI key.

.PARAMETER InstallRoot
  Install folder. Default: %LOCALAPPDATA%\Brightline\DocVerify
.PARAMETER WorkbenchMode
  Docker (default, recommended: Docker Desktop runs the Workbench and its PostgreSQL database) or Native
  (Node.js plus a PostgreSQL server you install yourself).
.PARAMETER DryRun
  Check prerequisites and show exactly what Setup would do, including any winget commands, without
  installing, writing or starting anything.
.PARAMETER SimulateMissing
  With -DryRun only: pretend these prerequisites are missing (Python, Node, Docker, PostgreSQL) to preview
  the installation offers.
.PARAMETER ShortcutFolder
  Where Start Menu shortcuts go. Default: your Start Menu, folder "Brightline Verification Suite".
.PARAMETER DesktopFolder
  Where the "Verify a Document" drag-and-drop shortcut goes. Default: your Desktop.
.PARAMETER Yes
  Acknowledge the cost and confidentiality notices without asking. Never approves installing software.
#>
[CmdletBinding()]
param(
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'Brightline\DocVerify'),
    [ValidateSet('Docker', 'Native')][string]$WorkbenchMode = 'Docker',
    [ValidateRange(1024, 65535)][int]$WorkbenchPort = 3080,
    [ValidateRange(1024, 65535)][int]$DocVerifyPort = 3091,
    [ValidateRange(1024, 65535)][int]$ContextForgePort = 8765,
    [ValidateRange(1024, 65535)][int]$GetFilesPort = 8766,
    [ValidatePattern('^[a-z0-9][a-z0-9_-]{1,40}$')][string]$ComposeProject = 'brightline-docverify',
    [string]$ShortcutFolder = (Join-Path ([Environment]::GetFolderPath('Programs')) 'Brightline Verification Suite'),
    [string]$DesktopFolder = ([Environment]::GetFolderPath('Desktop')),
    [switch]$NoDesktopShortcut,
    [string]$PythonExe,
    [string[]]$ContextForgeInputRoots,
    [string]$DocumentsFolder = ([Environment]::GetFolderPath('MyDocuments')),
    [string]$PostgresHost = '127.0.0.1',
    [ValidateRange(1, 65535)][int]$PostgresPort = 5432,
    [string]$PostgresAdminUser = 'postgres',
    [Security.SecureString]$PostgresAdminPassword,
    [Security.SecureString]$OpenAIKey,
    [switch]$Yes,
    [switch]$DryRun,
    [string[]]$SimulateMissing = @(),
    [switch]$NoStart
)
$ErrorActionPreference = 'Stop'
$bundle = [IO.Path]::GetFullPath($PSScriptRoot)
. ($bundle + '\suite\SuiteCommon.ps1')  # first: also repairs the module path (see SuiteCommon.ps1)

$PowerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
$paths = Get-SuitePaths $InstallRoot
# Accept "-SimulateMissing Python,Node" from both -File (one string) and -Command (an array).
$SimulateMissing = @($SimulateMissing | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
foreach ($item in $SimulateMissing) { if ($item -notin @('Python', 'Node', 'Docker', 'PostgreSQL')) { throw "-SimulateMissing accepts Python, Node, Docker and PostgreSQL (got '$item')." } }
if ($SimulateMissing.Count -and -not $DryRun) { throw '-SimulateMissing can only be used together with -DryRun.' }

function Get-WingetCommand([string]$Id, [switch]$Interactive) {
    $wingetArgs = @('install', '--id', $Id, '--exact', '--source', 'winget')
    if ($Interactive) { $wingetArgs += '--interactive' }
    $wingetArgs += @('--accept-source-agreements', '--accept-package-agreements')
    return $wingetArgs
}

# Explain a missing prerequisite and, after an explicit yes, install it with winget.
# Returns 'installed', 'declined', 'failed' or 'dryrun'.
function Request-Prerequisite([string]$Name, [string]$Id, [string[]]$Why, [string]$ManualUrl, [string[]]$Notes, [switch]$Interactive) {
    Write-Warn2 "$Name is not installed (or too old)."
    foreach ($line in $Why) { Write-Info $line }
    foreach ($line in $Notes) { Write-Info $line }
    $cmd = 'winget ' + ((Get-WingetCommand $Id -Interactive:$Interactive) -join ' ')
    Write-Info "Setup can install it for you with Windows Package Manager:"
    Write-Info "    $cmd"
    Write-Info "Or install it yourself from $ManualUrl and run Setup again."
    if ($DryRun) {
        Write-Info "[dry run] Setup would now ask: Install $Name now? Nothing is installed in a dry run."
        return 'dryrun'
    }
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-Bad 'Windows Package Manager (winget) is not available on this computer. Install "App Installer" from the Microsoft Store, or install the program yourself from the link above.'
        return 'failed'
    }
    if (-not (Read-YesNo "Install $Name now?" $false)) { return 'declined' }
    Write-Info "Installing $Name. Windows may ask for permission (a User Account Control prompt); choose Yes."
    & $winget.Source @(Get-WingetCommand $Id -Interactive:$Interactive)
    $code = $LASTEXITCODE
    Update-SessionPath
    # -1978335189 (0x8A15002B): already installed / no applicable upgrade.
    if ($code -eq 0 -or $code -eq -1978335189) { return 'installed' }
    Write-Bad "winget reported an error ($code) while installing $Name."
    return 'failed'
}

function Test-PostgresReachable([string]$TargetHost, [int]$Port) {
    $client = New-Object Net.Sockets.TcpClient
    try { $a = $client.BeginConnect($TargetHost, $Port, $null, $null); return ($a.AsyncWaitHandle.WaitOne(1500) -and $client.Connected) }
    catch { return $false } finally { $client.Close() }
}

function Invoke-ChildPowerShell([string]$Script, [string[]]$Arguments, [string]$LogName) {
    $log = Join-Path $paths.Logs $LogName
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        & $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File $Script @Arguments *> $log
        return $LASTEXITCODE
    } finally { $ErrorActionPreference = $old }
}

function Invoke-Logged([string]$Exe, [string[]]$Arguments, [string]$LogName, [string]$WorkingDirectory) {
    $log = Join-Path $paths.Logs $LogName
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    if ($WorkingDirectory) { Push-Location -LiteralPath $WorkingDirectory }
    try {
        & $Exe @Arguments *>> $log
        return $LASTEXITCODE
    } finally { if ($WorkingDirectory) { Pop-Location }; $ErrorActionPreference = $old }
}

function New-SuiteShortcut([string]$Folder, [string]$Name, [string]$Script, [string]$Description, [string]$Icon, [switch]$Sta) {
    New-Item -ItemType Directory -Force -Path $Folder | Out-Null
    $lnk = Join-Path $Folder ($Name + '.lnk')
    $shell = New-Object -ComObject WScript.Shell
    $s = $shell.CreateShortcut($lnk)
    $s.TargetPath = $PowerShellExe
    $staArg = if ($Sta) { '-STA ' } else { '' }
    $s.Arguments = '-NoProfile -ExecutionPolicy Bypass ' + $staArg + '-File "' + (Join-Path $paths.Bin $Script) + '"'
    $s.WorkingDirectory = $paths.Root
    $s.Description = $Description
    if ($Icon) { $s.IconLocation = $Icon }
    $s.Save()
    [Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
    return $lnk
}

# =============================================================================================
Write-Host ''
Write-Host 'Brightline Document Verification Suite - Setup (public preview 0.1.0)' -ForegroundColor White
Write-Host '----------------------------------------------------------------------'
Write-Info 'This installs four tools that work together to check the factual and legal statements in your'
Write-Info 'Word and PDF drafts against sources, and sets up a "Verify a Document" shortcut.'
Write-Info "Install folder: $InstallRoot"
if ($DryRun) { Write-Warn2 'DRY RUN: nothing will be installed, written or started.' }

# ---- 1. This computer -----------------------------------------------------------------------
Write-Step 'Step 1 of 7: Checking this computer'
if ([Environment]::OSVersion.Version.Major -lt 10 -or -not [Environment]::Is64BitOperatingSystem) {
    throw 'The suite needs 64-bit Windows 10 or Windows 11.'
}
foreach ($slug in $script:ToolSlugs) {
    if (-not (Test-Path -LiteralPath (Join-Path $bundle "tools\$slug"))) {
        throw "The download is incomplete: the folder tools\$slug is missing. Extract the whole zip file (right-click, Extract All) and run Setup from the extracted folder."
    }
}
Write-Good ('Windows ' + [Environment]::OSVersion.Version.ToString() + ', 64-bit')
$drive = [IO.Path]::GetPathRoot($InstallRoot)
try {
    $free = (New-Object IO.DriveInfo($drive)).AvailableFreeSpace
    if ($free -lt 6GB) { Write-Warn2 ("Only {0:N1} GB free on {1}. Allow about 6 GB (Docker images, Python packages, your documents)." -f ($free / 1GB), $drive) }
    else { Write-Good ("{0:N0} GB free on {1}" -f ($free / 1GB), $drive) }
} catch {}

# ---- 2. Prerequisites -------------------------------------------------------------------------
Write-Step 'Step 2 of 7: Checking required programs'
$missingStop = $false

$python = if ('Python' -in $SimulateMissing) { $null } else { Find-SuitePython $PythonExe }
if (-not $python) {
    $r = Request-Prerequisite 'Python 3.12' 'Python.Python.3.12' @(
        'Python runs Document Verification, Context Forge and Get Files on this computer.') 'https://www.python.org/downloads/windows/' @(
        'Python is free (PSF license).')
    if ($r -eq 'installed') { $python = Find-SuitePython $PythonExe }
    if (-not $python -and -not $DryRun) { $missingStop = $true; Write-Bad 'Python 3.12 is required. Install it, then run Setup again.' }
}
if ($python) {
    Write-Good ("Python {0} ({1})" -f $python.Version, $python.Exe)
    if ($python.Version.Minor -ne 12) { Write-Info 'Note: the tools are tested on Python 3.12; this newer version is expected to work.' }
}

$node = if ('Node' -in $SimulateMissing) { $null } else { Find-SuiteNode }
$nodeNeeded = ($WorkbenchMode -eq 'Native')
if ($node -and $node.Version -lt [version]'22.9.0') {
    Write-Warn2 ("Node.js {0} is too old (22.9 or later is needed)." -f $node.Version); $node = $null
}
if (-not $node) {
    $why = if ($nodeNeeded) { @('Node.js runs the Research Workbench in Native mode.') } else {
        @('Node.js is optional in the recommended Docker mode. It lets AI assistants such as Claude Desktop use',
          'Context Forge and Get Files directly (their "MCP" connectors). Verification works without it.') }
    $r = Request-Prerequisite 'Node.js LTS' 'OpenJS.NodeJS.LTS' $why 'https://nodejs.org/' @('Node.js is free (MIT license).')
    if ($r -eq 'installed') { $node = Find-SuiteNode }
    if (-not $node -and $nodeNeeded -and -not $DryRun) { $missingStop = $true; Write-Bad 'Node.js is required for Native mode.' }
    elseif (-not $node -and -not $DryRun) { Write-Info 'Continuing without Node.js (the AI-assistant connectors will not be installed).' }
}
if ($node) { Write-Good ("Node.js {0}" -f $node.Version) }

$docker = $null
if ($WorkbenchMode -eq 'Docker') {
    $docker = if ('Docker' -in $SimulateMissing) { $null } else { Find-SuiteDocker }
    if (-not $docker) {
        $r = Request-Prerequisite 'Docker Desktop' 'Docker.DockerDesktop' @(
            'Docker Desktop runs the Research Workbench together with its PostgreSQL database and the Word/PDF',
            'report tools in a sealed, ready-made package, so nothing else has to be set up by hand.') 'https://www.docker.com/products/docker-desktop/' @(
            'Licence: Docker Desktop is free for personal use, education, non-commercial open-source projects and',
            'businesses with fewer than 250 employees AND less than USD 10 million in annual revenue. Larger',
            'organisations need a paid Docker subscription. If that applies to you, answer N and run Setup with',
            '-WorkbenchMode Native instead (free: Node.js + PostgreSQL). Terms: https://www.docker.com/legal/docker-subscription-service-agreement/',
            'Docker Desktop also needs Windows virtualization (WSL 2); on first start it may ask to update WSL or to restart.')
        if ($r -eq 'installed') {
            Write-Good 'Docker Desktop was installed.'
            Write-Info 'Next: restart Windows if asked, open Docker Desktop from the Start Menu, accept its terms, wait until'
            Write-Info 'it shows "Engine running", then run Setup again. Setup stops here so nothing is half-installed.'
            exit 0
        }
        if (-not $DryRun) { $missingStop = $true; Write-Bad 'Docker Desktop is required for Docker mode (or use -WorkbenchMode Native).' }
    } else {
        if (-not $docker.Compose -or $docker.Compose -lt [version]'2.24.0') {
            $missingStop = $true
            Write-Bad 'Docker Compose 2.24 or later is needed. Update Docker Desktop (Settings, Software updates) and run Setup again.'
        } else { Write-Good ("Docker {0}, Compose {1}" -f $docker.Exe, $docker.Compose) }
        if (-not $docker.Running) {
            if ($DryRun) { Write-Info '[dry run] Docker Desktop is not running; Setup would start it and wait.' }
            elseif (Start-DockerEngine $docker.Exe) { Write-Good 'Docker engine is running' }
            else { $missingStop = $true; Write-Bad 'Docker Desktop did not start. Open it from the Start Menu, wait for "Engine running", then run Setup again.' }
        } else { Write-Good 'Docker engine is running' }
    }
} else {
    $pgUp = if ('PostgreSQL' -in $SimulateMissing) { $false } else { Test-PostgresReachable $PostgresHost $PostgresPort }
    if (-not $pgUp) {
        $r = Request-Prerequisite 'PostgreSQL 16' 'PostgreSQL.PostgreSQL.16' @(
            "No PostgreSQL server answers at ${PostgresHost}:$PostgresPort. The Research Workbench stores projects and results in it.") 'https://www.postgresql.org/download/windows/' @(
            'PostgreSQL is free (PostgreSQL license). Its installer opens a window: choose a password for the',
            '"postgres" administrator and keep port 5432. Setup asks for that password once and does not store it.') -Interactive
        if ($r -eq 'installed') { $pgUp = Wait-Until { Test-PostgresReachable $PostgresHost $PostgresPort } 60 'PostgreSQL' }
        if (-not $pgUp -and -not $DryRun) { $missingStop = $true; Write-Bad "PostgreSQL is required for Native mode (expected at ${PostgresHost}:$PostgresPort)." }
    } else { Write-Good "PostgreSQL answers at ${PostgresHost}:$PostgresPort" }
}
if ($missingStop) { Write-Host ''; Write-Bad 'Setup cannot continue until the items above are fixed. Nothing was installed.'; exit 1 }

# ---- 3. Ports ---------------------------------------------------------------------------------
Write-Step 'Step 3 of 7: Checking network ports (all local to this computer)'
$existing = Test-Path -LiteralPath $paths.SuiteJson
if ($existing -and -not $DryRun) {
    Write-Info 'An earlier installation was found; stopping it so it can be updated (your data is kept).'
    try { Stop-Suite (Read-SuiteConfig $InstallRoot) } catch { Write-Warn2 'Could not stop the earlier installation cleanly; continuing.' }
    Start-Sleep -Seconds 2
}
$ports = [ordered]@{ 'Research Workbench' = $WorkbenchPort; 'Document Verification' = $DocVerifyPort; 'Context Forge' = $ContextForgePort; 'Get Files' = $GetFilesPort }
if (@($ports.Values | Select-Object -Unique).Count -ne 4) { throw 'The four ports must be different.' }
$busy = @()
foreach ($k in $ports.Keys) {
    if (Test-PortListening $ports[$k]) { $busy += $k; Write-Bad ("Port {0} ({1}) is already used by another program." -f $ports[$k], $k) }
    else { Write-Good ("Port {0} free for {1}" -f $ports[$k], $k) }
}
if ($busy.Count) {
    Write-Info 'Another program (possibly a separate copy of one of these tools) is using that port. Either stop it, or run'
    Write-Info 'Setup with a different port, for example:  .\setup.ps1 -WorkbenchPort 13080 -ContextForgePort 18765'
    if (-not $DryRun) { exit 1 }
}

# ---- Dry run summary --------------------------------------------------------------------------
if ($DryRun) {
    Write-Step 'Dry run: what Setup would do next'
    Write-Info "Copy the four tools to $($paths.App)"
    Write-Info "Context Forge: run its install.ps1 (Python packages from PyPI)$(if (-not $node) { ' without the Node.js connector' })"
    Write-Info "Get Files: run its install.ps1 with data in $($paths.GetFilesData)"
    if ($WorkbenchMode -eq 'Docker') { Write-Info "Research Workbench: docker compose -p $ComposeProject up -d --build (port 127.0.0.1:$WorkbenchPort)" }
    else { Write-Info "Research Workbench: npm ci, create database role/database on ${PostgresHost}:$PostgresPort, run migrations (port 127.0.0.1:$WorkbenchPort)" }
    Write-Info 'Ask once for your OpenAI API key (hidden) and store it only in the Workbench .env file (your account only)'
    Write-Info "Start Menu shortcuts in: $ShortcutFolder"
    if (-not $NoDesktopShortcut) { Write-Info "Drag-and-drop shortcut in: $DesktopFolder" }
    Write-Host ''
    Write-Good 'Dry run finished. Nothing was changed.'
    exit 0
}

# ---- 4. OpenAI key and notices ---------------------------------------------------------------
Write-Step 'Step 4 of 7: OpenAI account (cost and confidentiality)'
$oldEnv = Read-DotEnv $paths.WorkbenchEnv
$apiKey = $null
if ($OpenAIKey) { $apiKey = ConvertFrom-SecureToPlain $OpenAIKey }
elseif ($oldEnv['OPENAI_API_KEY']) {
    if ($Yes -or (Read-YesNo 'An OpenAI API key is already stored for the suite. Keep it?' $true)) { $apiKey = $oldEnv['OPENAI_API_KEY'] }
}
if (-not $apiKey) {
    Write-Info 'The Research Workbench uses OpenAI''s models to find the statements in your document and check them'
    Write-Info 'against sources. Please read this before continuing:'
    Write-Host ''
    Write-Info 'COST: every verification makes paid calls to the OpenAI API, billed to YOUR OpenAI account. The cost'
    Write-Info '  grows with document length and with web searching for sources (see https://openai.com/api/pricing/).'
    Write-Info '  The suite limits the number of calls per day, but that is not a dollar limit: set a monthly budget at'
    Write-Info '  https://platform.openai.com/settings/organization/limits'
    Write-Info 'CONFIDENTIALITY: the text of every document you verify, and passages of its sources, are sent to'
    Write-Info '  OpenAI. Do not verify privileged, confidential, client or export-controlled material unless your'
    Write-Info '  professional obligations, your client''s consent and OpenAI''s terms allow it.'
    Write-Info 'KEY: create an API key at https://platform.openai.com/api-keys (sign in, "Create new secret key").'
    Write-Info '  It starts with "sk-". It is stored only on this computer, in a file only your Windows account can read.'
    Write-Host ''
    if (-not $Yes -and -not (Read-YesNo 'I have read the cost and confidentiality notes. Continue?' $false)) {
        Write-Info 'Setup stopped. Nothing was installed.'; exit 1
    }
    while (-not $apiKey) {
        $secure = Read-Host -Prompt '   Paste your OpenAI API key (it will not be shown) and press Enter' -AsSecureString
        $candidate = (ConvertFrom-SecureToPlain $secure).Trim()
        if (-not $candidate) { Write-Info 'No key entered. You can press Ctrl+C to cancel Setup.'; continue }
        if ($candidate -match '\s' -or $candidate.Length -lt 20) { Write-Bad 'That does not look like an API key (too short or contains spaces). Try again.'; continue }
        if (-not $candidate.StartsWith('sk-')) {
            if (-not (Read-YesNo 'OpenAI keys normally start with "sk-". Use this value anyway?' $false)) { continue }
        }
        $apiKey = $candidate
    }
}
if ($apiKey -match '[\r\n]') { throw 'The API key contains a line break.' }
Write-Good 'OpenAI key received (it will not be displayed).'

$cfRoots = if ($ContextForgeInputRoots) { $ContextForgeInputRoots } else { @($paths.DocVerifyData, $DocumentsFolder) | Where-Object { $_ } }

# ---- 5. Copy and install the tools --------------------------------------------------------------
Write-Step 'Step 5 of 7: Installing the tools (this downloads Python packages; allow 5-15 minutes)'
foreach ($dir in @($paths.Root, $paths.App, $paths.Bin, $paths.Config, $paths.Logs, $paths.Run)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
if (-not (Test-Path -LiteralPath $paths.Marker)) {
    Write-Utf8NoBom $paths.Marker "Brightline Document Verification Suite install root. uninstall.ps1 removes only folders that contain this file.`r`n"
}
foreach ($dir in @($paths.Secrets, $paths.Data)) {
    $isNew = -not (Test-Path -LiteralPath $dir)
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    if ($isNew) { Set-UserOnlyAcl $dir -Folder }
}
foreach ($dir in @($paths.DocVerifyData, $paths.CfOutput)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
if ($WorkbenchMode -eq 'Native') { New-Item -ItemType Directory -Force -Path $paths.WorkbenchData | Out-Null }

foreach ($slug in $script:ToolSlugs) {
    $null = & robocopy.exe (Join-Path $bundle "tools\$slug") (Join-Path $paths.App $slug) /E /XD .git node_modules .venv data output security storage /NFL /NDL /NJH /NJS /NP
    if ($LASTEXITCODE -ge 8) { throw "Copying $slug failed (robocopy code $LASTEXITCODE)." }
}
foreach ($f in Get-ChildItem -LiteralPath (Join-Path $bundle 'suite') -File) { Copy-Item -LiteralPath $f.FullName -Destination $paths.Bin -Force }
Copy-Item -LiteralPath (Join-Path $bundle 'uninstall.ps1') -Destination $paths.Bin -Force
foreach ($doc in @('README.md', 'LICENSE', 'NOTICE', 'DISCLAIMER.md', 'SECURITY.md', 'CHANGELOG.md')) {
    if (Test-Path -LiteralPath (Join-Path $bundle $doc)) { Copy-Item -LiteralPath (Join-Path $bundle $doc) -Destination $paths.Root -Force }
}
# Files from a downloaded zip carry the "downloaded from the Internet" mark; clear it on the copies
# this installation runs, so Windows does not ask about each script again.
Get-ChildItem -LiteralPath $paths.Root -Recurse -File -Include *.ps1, *.cmd, *.py, *.mjs, *.js | Unblock-File -ErrorAction SilentlyContinue
Write-Good "Program files copied to $($paths.App)"

$skipNode = @(); if (-not $node) { $skipNode = @('-SkipNode') }
Write-Info 'Installing Context Forge (text extraction and Windows OCR)...'
$code = Invoke-ChildPowerShell (Join-Path $paths.ContextForge 'install.ps1') (@('-Python', $python.Exe) + $skipNode) 'install-context-forge.log'
if ($code -ne 0) { throw "Context Forge did not install. Details: $(Join-Path $paths.Logs 'install-context-forge.log')" }
Write-Good 'Context Forge installed'

Write-Info 'Installing Get Files (local source library)...'
$code = Invoke-ChildPowerShell (Join-Path $paths.GetFiles 'install.ps1') (@('-DataPath', $paths.GetFilesData, '-PythonExe', $python.Exe) + $skipNode) 'install-get-files.log'
if ($code -ne 0) { throw "Get Files did not install. Details: $(Join-Path $paths.Logs 'install-get-files.log')" }
Write-Good 'Get Files installed'

$gfToken = Read-SecretFile $paths.GfToken
if (-not $gfToken) { throw 'The Get Files service token was not created.' }
if (-not (Test-Path -LiteralPath $paths.CfToken)) { throw 'The Context Forge service token was not created.' }

# Workbench access token (shared secret for the Workbench API, kept in a user-only file).
$wbToken = Read-SecretFile $paths.WorkbenchToken
if (-not $wbToken) {
    $wbToken = New-RandomToken 32
    Write-Utf8NoBom $paths.WorkbenchToken $wbToken
}
Set-UserOnlyAcl $paths.WorkbenchToken

# ---- 6. Research Workbench ----------------------------------------------------------------------
Write-Step 'Step 6 of 7: Setting up the Research Workbench'
$envLines = New-Object Collections.Generic.List[string]
$envLines.Add('# Written by the Brightline Document Verification Suite setup. Secrets: readable by your account only.')
$envLines.Add('ORCHESTRATION_MODE=openai')
$envLines.Add('OPENAI_API_KEY=' + $apiKey)
$envLines.Add('WORKBENCH_TOKEN=' + $wbToken)
$envLines.Add('PORT=' + $WorkbenchPort)
$envLines.Add('WORKBENCH_PORT=' + $WorkbenchPort)
$nodeExe = $null
if ($WorkbenchMode -eq 'Docker') {
    # The database volume keeps the password it was created with, so it is also kept beside your data
    # (survives an uninstall that keeps data, and a reinstall).
    $pgSecret = Join-Path $paths.Data 'workbench-db-password.secret'
    $pgPassword = if ($oldEnv['POSTGRES_PASSWORD']) { $oldEnv['POSTGRES_PASSWORD'] } elseif (Read-SecretFile $pgSecret) { Read-SecretFile $pgSecret } else { New-RandomToken 24 }
    Write-Utf8NoBom $pgSecret $pgPassword
    Set-UserOnlyAcl $pgSecret
    $envLines.Add('POSTGRES_PASSWORD=' + $pgPassword)
    $envLines.Add('SOURCE_CORPUS_URL=http://host.docker.internal:' + $GetFilesPort)
    $envLines.Add('SOURCE_CORPUS_TOKEN=' + $gfToken)
    Write-Utf8NoBom $paths.WorkbenchEnv (($envLines -join "`n") + "`n")
    Set-UserOnlyAcl $paths.WorkbenchEnv
    $image = $ComposeProject + '-workbench:' + $script:SuiteVersion
    Write-Utf8NoBom $paths.ComposeOverride ("# Written by setup.ps1: a project-specific image name so uninstall removes only this suite's image.`nservices:`n  app:`n    image: $image`n")
} else {
    $nodeExe = $node.Exe
    $roleName = 'docverify_workbench'; $dbName = 'docverify_workbench'
    $dbSecret = Join-Path $paths.Data 'workbench-database-url.secret'
    $dbUrl = if ($oldEnv['DATABASE_URL']) { $oldEnv['DATABASE_URL'] } else { Read-SecretFile $dbSecret }
    Write-Info 'Installing the Workbench''s Node.js packages...'
    $code = Invoke-Logged $node.Npm @('ci', '--omit=dev', '--ignore-scripts', '--no-audit', '--no-fund') 'install-workbench.log' $paths.Workbench
    if ($code -ne 0) { throw "npm ci failed for the Workbench. Details: $(Join-Path $paths.Logs 'install-workbench.log')" }
    Write-Info 'Installing the Word/PDF report runtime (Python packages)...'
    $docsVenv = Join-Path $paths.Workbench '.venv-docs'
    if (-not (Test-Path (Join-Path $docsVenv 'Scripts\python.exe'))) {
        $code = Invoke-Logged $python.Exe @('-m', 'venv', $docsVenv) 'install-workbench.log'
        if ($code -ne 0) { throw 'Could not create the report runtime.' }
    }
    $docsPy = Join-Path $docsVenv 'Scripts\python.exe'
    $code = Invoke-Logged $docsPy @('-m', 'pip', 'install', '--disable-pip-version-check', '--only-binary=:all:', '--require-hashes', '-r', (Join-Path $paths.Workbench 'requirements-documents.txt')) 'install-workbench.log'
    if ($code -eq 0) { $code = Invoke-Logged $docsPy @('-m', 'pip', 'install', '--disable-pip-version-check', 'python-docx', 'reportlab') 'install-workbench.log' }
    if ($code -ne 0) { Write-Warn2 'The Word/PDF report runtime could not be installed; CSV reports still work.'; $docsPy = $null }
    if (-not $dbUrl) {
        Write-Info "Creating the Workbench database on ${PostgresHost}:$PostgresPort (needs the PostgreSQL administrator password once; it is not stored)."
        $adminPw = if ($PostgresAdminPassword) { ConvertFrom-SecureToPlain $PostgresAdminPassword } else { ConvertFrom-SecureToPlain (Read-Host -Prompt "   Password of the PostgreSQL user '$PostgresAdminUser'" -AsSecureString) }
        $rolePw = New-RandomToken 24
        $saved = @{ h = $env:PGHOST; p = $env:PGPORT; u = $env:PGUSER; w = $env:PGPASSWORD }
        try {
            $env:PGHOST = $PostgresHost; $env:PGPORT = [string]$PostgresPort; $env:PGUSER = $PostgresAdminUser; $env:PGPASSWORD = $adminPw
            $env:WB_DIR = $paths.Workbench; $env:WB_ROLE = $roleName; $env:WB_DB = $dbName; $env:WB_ROLE_PASSWORD = $rolePw
            $code = Invoke-Logged $node.Exe @((Join-Path $paths.Bin 'pg-provision.mjs'), 'create') 'install-workbench.log'
        } finally {
            $env:PGHOST = $saved.h; $env:PGPORT = $saved.p; $env:PGUSER = $saved.u; $env:PGPASSWORD = $saved.w
            $env:WB_ROLE_PASSWORD = $null; $env:WB_DIR = $null; $env:WB_ROLE = $null; $env:WB_DB = $null; $adminPw = $null
        }
        if ($code -ne 0) { throw "Could not create the Workbench database (wrong administrator password?). Details: $(Join-Path $paths.Logs 'install-workbench.log')" }
        $dbUrl = "postgres://${roleName}:$rolePw@${PostgresHost}:$PostgresPort/$dbName"
    }
    Write-Utf8NoBom $dbSecret $dbUrl
    Set-UserOnlyAcl $dbSecret
    $envLines.Add('DATABASE_URL=' + $dbUrl)
    $envLines.Add('HOST=127.0.0.1')
    $envLines.Add('WORKBENCH_DATA_DIR=' + $paths.WorkbenchData)
    if ($docsPy) { $envLines.Add('ARTIFACT_PYTHON=' + $docsPy) }
    $envLines.Add('SOURCE_CORPUS_URL=http://127.0.0.1:' + $GetFilesPort)
    $envLines.Add('SOURCE_CORPUS_TOKEN_FILE=' + $paths.GfToken)
    Write-Utf8NoBom $paths.WorkbenchEnv (($envLines -join "`n") + "`n")
    Set-UserOnlyAcl $paths.WorkbenchEnv
    Write-Info 'Preparing the database tables...'
    $code = Invoke-Logged $node.Exe @('--env-file=.env', 'scripts/migrate.js') 'install-workbench.log' $paths.Workbench
    if ($code -ne 0) { throw "Database preparation failed. Details: $(Join-Path $paths.Logs 'install-workbench.log')" }
}
$apiKey = $null

# Document Verification configuration: wired to the three services and their token files.
$dvConfig = [ordered]@{
    port         = $DocVerifyPort
    data_dir     = $paths.DocVerifyData
    input_roots  = @($DocumentsFolder | Where-Object { $_ })
    workbench    = [ordered]@{ url = "http://127.0.0.1:$WorkbenchPort"; timeout_seconds = 3000; token_file = $paths.WorkbenchToken }
    discovery    = [ordered]@{ enabled = $true; max_external_queries = 10 }
    get_files    = [ordered]@{ enabled = $true; url = "http://127.0.0.1:$GetFilesPort"; token_file = $paths.GfToken; collection = 'research' }
    context_forge= [ordered]@{ enabled = $true; url = "http://127.0.0.1:$ContextForgePort"; token_file = $paths.CfToken; poll_timeout = 180 }
    drive        = [ordered]@{ enabled = $false }
}
Write-Utf8NoBom $paths.DocVerifyConf ($dvConfig | ConvertTo-Json -Depth 5)

$suite = [ordered]@{
    product                   = 'Brightline Document Verification Suite'
    version                   = $script:SuiteVersion
    install_root              = $paths.Root
    workbench_mode            = $WorkbenchMode
    compose_project           = $ComposeProject
    workbench_image           = $(if ($WorkbenchMode -eq 'Docker') { $ComposeProject + '-workbench:' + $script:SuiteVersion } else { $null })
    docker                    = $(if ($docker) { $docker.Exe } else { $null })
    python                    = $python.Exe
    node                      = $(if ($node) { $node.Exe } else { $null })
    postgres                  = $(if ($WorkbenchMode -eq 'Native') { [ordered]@{ host = $PostgresHost; port = $PostgresPort; database = 'docverify_workbench'; role = 'docverify_workbench' } } else { $null })
    ports                     = [ordered]@{ workbench = $WorkbenchPort; docverify = $DocVerifyPort; context_forge = $ContextForgePort; get_files = $GetFilesPort }
    context_forge_input_roots = @($cfRoots)
    discover_sources          = $true
    shortcuts                 = @()
    installed                 = (Get-Date).ToString('s')
}
Write-Utf8NoBom $paths.SuiteJson ($suite | ConvertTo-Json -Depth 5)
$config = Read-SuiteConfig $InstallRoot

if ($WorkbenchMode -eq 'Docker') {
    Write-Info 'Building and starting the Workbench in Docker. The first time this downloads about 500 MB and'
    Write-Info 'takes 5-10 minutes; later starts take seconds.'
    $code = Invoke-WorkbenchCompose $config @('up', '-d', '--build') -Quiet
    if ($code -ne 0) { throw "Docker could not build or start the Workbench. Details: $(Join-Path $paths.Logs 'docker-compose.log')" }
    Write-Good 'Workbench containers created'
}

# ---- 7. Shortcuts, start and self-check -----------------------------------------------------------
Write-Step 'Step 7 of 7: Shortcuts and first start'
$icons = "$env:SystemRoot\System32\shell32.dll"
$created = @()
$created += New-SuiteShortcut $ShortcutFolder 'Start Brightline Verification Suite' 'start-suite.ps1' 'Start the four verification services' "$icons,137"
$created += New-SuiteShortcut $ShortcutFolder 'Stop Brightline Verification Suite' 'stop-suite.ps1' 'Stop the verification services' "$icons,27"
$created += New-SuiteShortcut $ShortcutFolder 'Open Research Workbench' 'open-workbench.ps1' 'Open the Research Workbench in your browser' "$icons,13"
$created += New-SuiteShortcut $ShortcutFolder 'Verify a Document' 'verify-document.ps1' 'Choose a Word or PDF file to verify' "$icons,1" -Sta
$created += New-SuiteShortcut $ShortcutFolder 'Uninstall Brightline Verification Suite' 'uninstall.ps1' 'Remove the verification suite' "$icons,31"
if (-not $NoDesktopShortcut) {
    $created += New-SuiteShortcut $DesktopFolder 'Verify a Document' 'verify-document.ps1' 'Drop a Word or PDF file here to verify it' "$icons,1" -Sta
}
$suite['shortcuts'] = @($created)
$suite['shortcut_folder'] = $ShortcutFolder
Write-Utf8NoBom $paths.SuiteJson ($suite | ConvertTo-Json -Depth 5)
$config = Read-SuiteConfig $InstallRoot
Write-Good ("Shortcuts created in: {0}" -f $ShortcutFolder)
if (-not $NoDesktopShortcut) { Write-Good ('"Verify a Document" shortcut on: ' + $DesktopFolder) }

if ($NoStart) {
    Write-Host ''; Write-Good 'Setup finished (services not started because of -NoStart).'; exit 0
}
$started = Start-Suite $config
$allOk = $true
foreach ($k in $started.Keys) { if ($started[$k]) { Write-Good "$k is running" } else { $allOk = $false; Write-Bad "$k did not start (see $($paths.Logs))" } }

$doctor = Invoke-DocVerify $config @('doctor')
if ($doctor.Json) {
    foreach ($name in @('workbench', 'context_forge', 'get_files')) {
        $entry = $doctor.Json.$name
        if ($entry -and $entry.ok) { Write-Good "Document Verification can reach $name" } else { $allOk = $false; Write-Bad "Document Verification cannot reach $name" }
    }
}

Write-Host ''
if ($allOk) {
    Write-Host 'Setup finished. Everything is running.' -ForegroundColor Green
} else {
    Write-Host 'Setup finished, but not everything started. Try "Start Brightline Verification Suite" from the Start Menu;' -ForegroundColor Yellow
    Write-Host "if it still fails, see Troubleshooting in the README and the logs in $($paths.Logs)." -ForegroundColor Yellow
}
Write-Info 'How to verify a document:'
if (-not $NoDesktopShortcut) { Write-Info '  - Drag a .docx or .pdf file onto "Verify a Document" on your Desktop, or' }
Write-Info '  - Start Menu > Brightline Verification Suite > Verify a Document, then pick the file.'
Write-Info 'The report opens in your browser when the check is done.'
Write-Info 'After restarting Windows, use "Start Brightline Verification Suite" first.'
