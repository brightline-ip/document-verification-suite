# Shared helpers for the Brightline Document Verification Suite (setup, launchers, uninstall).
# Windows PowerShell 5.1 compatible. Dot-source this file; it defines functions only.

$script:SuiteVersion = '0.1.0'
$script:SuiteMarker = '.brightline-docverify-suite'
$script:ToolSlugs = @('research-workbench', 'document-verification', 'context-forge', 'get-files')

# ---------------------------------------------------------------------------------------------
# Plain-language console output
# ---------------------------------------------------------------------------------------------
function Write-Step([string]$Text) { Write-Host ''; Write-Host ('== ' + $Text) -ForegroundColor Cyan }
function Write-Info([string]$Text) { Write-Host ('   ' + $Text) }
function Write-Good([string]$Text) { Write-Host ('   OK  ' + $Text) -ForegroundColor Green }
function Write-Warn2([string]$Text) { Write-Host ('   !   ' + $Text) -ForegroundColor Yellow }
function Write-Bad([string]$Text) { Write-Host ('   X   ' + $Text) -ForegroundColor Red }

function Read-YesNo([string]$Question, [bool]$Default = $false) {
    $suffix = if ($Default) { ' [Y/n] ' } else { ' [y/N] ' }
    while ($true) {
        $answer = Read-Host -Prompt ('   ' + $Question + $suffix)
        if ($null -eq $answer) { return $Default }
        $answer = $answer.Trim().ToLowerInvariant()
        if ($answer -eq '') { return $Default }
        if ($answer -in @('y', 'yes')) { return $true }
        if ($answer -in @('n', 'no')) { return $false }
        Write-Info 'Please type Y for yes or N for no.'
    }
}

function ConvertFrom-SecureToPlain([Security.SecureString]$Secure) {
    if ($null -eq $Secure) { return '' }
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

# ---------------------------------------------------------------------------------------------
# Files, secrets and access lists
# ---------------------------------------------------------------------------------------------
function Write-Utf8NoBom([string]$Path, [string]$Text) {
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding $false))
}

function Get-CurrentAccount { return [Security.Principal.WindowsIdentity]::GetCurrent().Name }

# Restrict a file or folder to the current Windows account only (no inheritance, no other users).
function Set-UserOnlyAcl([string]$Path, [switch]$Folder) {
    $account = Get-CurrentAccount
    $grant = if ($Folder) { "${account}:(OI)(CI)F" } else { "${account}:F" }
    $null = & icacls.exe $Path /inheritance:r /grant:r $grant 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Could not restrict access to $Path to your Windows account." }
}

function New-RandomToken([int]$Bytes = 32) {
    $buffer = New-Object byte[] $Bytes
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($buffer) } finally { $rng.Dispose() }
    # URL-safe base64 without padding (43 characters for 32 bytes).
    return ([Convert]::ToBase64String($buffer)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Read-SecretFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return ([IO.File]::ReadAllText($Path)).Trim([char]0xFEFF, ' ', "`r", "`n", "`t")
}

# Read KEY=VALUE pairs from a .env file (no expansion; comments and blank lines ignored).
function Read-DotEnv([string]$Path) {
    $values = @{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $values }
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        $t = $line.Trim([char]0xFEFF).Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        $i = $t.IndexOf('=')
        if ($i -lt 1) { continue }
        $values[$t.Substring(0, $i).Trim()] = $t.Substring($i + 1)
    }
    return $values
}

# ---------------------------------------------------------------------------------------------
# Suite configuration
# ---------------------------------------------------------------------------------------------
function Get-SuitePaths([string]$Root) {
    $Root = [IO.Path]::GetFullPath($Root)
    $app = Join-Path $Root 'app'
    $data = Join-Path $Root 'data'
    return [ordered]@{
        Root           = $Root
        App            = $app
        Bin            = Join-Path $Root 'bin'
        Config         = Join-Path $Root 'config'
        Secrets        = Join-Path $Root 'secrets'
        Data           = $data
        Logs           = Join-Path $Root 'logs'
        Run            = Join-Path $Root 'run'
        Marker         = Join-Path $Root $script:SuiteMarker
        SuiteJson      = Join-Path $Root 'config\suite.json'
        Workbench      = Join-Path $app 'research-workbench'
        WorkbenchEnv   = Join-Path $app 'research-workbench\.env'
        DocVerify      = Join-Path $app 'document-verification'
        ContextForge   = Join-Path $app 'context-forge'
        GetFiles       = Join-Path $app 'get-files'
        DocVerifyConf  = Join-Path $Root 'config\docverify.json'
        ComposeOverride= Join-Path $Root 'config\workbench.compose.yml'
        WorkbenchToken = Join-Path $Root 'secrets\workbench-token.txt'
        CfToken        = Join-Path $app 'context-forge\security\service-token.txt'
        DocVerifyData  = Join-Path $data 'docverify'
        GetFilesData   = Join-Path $data 'get-files'
        GfToken        = Join-Path $data 'get-files\service-token.txt'
        CfOutput       = Join-Path $data 'context-forge-output'
        WorkbenchData  = Join-Path $data 'workbench'
        Reports        = Join-Path $data 'docverify\projects'
    }
}

function Read-SuiteConfig([string]$Root) {
    $paths = Get-SuitePaths $Root
    if (-not (Test-Path -LiteralPath $paths.SuiteJson -PathType Leaf)) {
        throw "The verification suite is not installed in $Root (config\suite.json is missing). Run Setup again."
    }
    $config = [IO.File]::ReadAllText($paths.SuiteJson) | ConvertFrom-Json
    return $config
}

# The install root a launcher in <root>\bin belongs to.
function Get-RootFromBin([string]$BinDir) { return [IO.Path]::GetFullPath((Join-Path $BinDir '..')) }

# ---------------------------------------------------------------------------------------------
# HTTP on loopback (no proxy, no exceptions for HTTP status codes)
# ---------------------------------------------------------------------------------------------
function Invoke-Local {
    param([string]$Url, [string]$Method = 'GET', [string]$Token, [string]$Body, [int]$TimeoutSec = 10,
          [string]$ContentType = 'application/json')
    $result = [ordered]@{ Status = 0; Body = ''; Error = $null }
    try {
        $request = [Net.HttpWebRequest]::Create($Url)
        $request.Method = $Method
        $request.Proxy = $null
        $request.Timeout = $TimeoutSec * 1000
        $request.ReadWriteTimeout = $TimeoutSec * 1000
        $request.AllowAutoRedirect = $false
        if ($Token) { $request.Headers.Add('Authorization', 'Bearer ' + $Token) }
        if ($null -ne $Body -and $Body -ne '') {
            $bytes = [Text.Encoding]::UTF8.GetBytes($Body)
            $request.ContentType = $ContentType
            $request.ContentLength = $bytes.Length
            $stream = $request.GetRequestStream(); $stream.Write($bytes, 0, $bytes.Length); $stream.Close()
        } elseif ($Method -eq 'POST') { $request.ContentLength = 0 }
        try { $response = $request.GetResponse() }
        catch [Net.WebException] {
            if ($_.Exception.Response) { $response = $_.Exception.Response } else { throw }
        }
        $result.Status = [int]$response.StatusCode
        $reader = New-Object IO.StreamReader($response.GetResponseStream())
        $result.Body = $reader.ReadToEnd(); $reader.Close(); $response.Close()
    } catch {
        $result.Error = $_.Exception.Message
    }
    return $result
}

function Test-PortListening([int]$Port) {
    $client = New-Object Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        if ($async.AsyncWaitHandle.WaitOne(700) -and $client.Connected) { return $true }
        return $false
    } catch { return $false } finally { $client.Close() }
}

function Wait-Until([scriptblock]$Condition, [int]$Seconds, [string]$What) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        if (& $Condition) { return $true }
        Start-Sleep -Milliseconds 1000
    }
    return $false
}

# ---------------------------------------------------------------------------------------------
# Prerequisite detection
# ---------------------------------------------------------------------------------------------
function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
}

# Returns @{ Exe; Version } for a Python 3.12+ interpreter, preferring 3.12 (the version the tools test on).
function Find-SuitePython([string]$Requested) {
    # No quote characters: Windows PowerShell 5.1 drops embedded double quotes when calling native programs.
    $probe = 'import sys;print(sys.executable);print(sys.version_info[0],sys.version_info[1],sys.version_info[2],sep=chr(46))'
    $candidates = New-Object Collections.Generic.List[object]
    if ($Requested) { $candidates.Add(@($Requested)) }
    else {
        foreach ($v in @('3.12', '3.13', '3.14')) { $candidates.Add(@('py', "-$v")) }
        $candidates.Add(@('python'))
        foreach ($v in @('312', '313', '314')) {
            foreach ($base in @("$env:LOCALAPPDATA\Programs\Python\Python$v", "$env:ProgramFiles\Python$v", "C:\Python$v")) {
                $candidates.Add(@((Join-Path $base 'python.exe')))
            }
        }
    }
    foreach ($c in $candidates) {
        $exe = $c[0]; $extra = @($c | Select-Object -Skip 1)
        if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) { continue }
        try {
            $out = & $exe @extra -c $probe 2>$null
            if ($LASTEXITCODE -ne 0 -or -not $out) { continue }
            $lines = @($out)
            if ($lines.Count -lt 2) { continue }
            $ver = [version]$lines[1]
            if ($ver.Major -eq 3 -and $ver.Minor -ge 12 -and $lines[0] -notmatch '\\WindowsApps\\') {
                return @{ Exe = $lines[0].Trim(); Version = $ver }
            }
        } catch { continue }
    }
    return $null
}

function Find-SuiteNode {
    $node = (Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
    $exe = if ($node) { $node.Source } elseif (Test-Path "$env:ProgramFiles\nodejs\node.exe") { "$env:ProgramFiles\nodejs\node.exe" } else { $null }
    if (-not $exe) { return $null }
    try {
        $v = & $exe -p 'process.versions.node' 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        $npm = Join-Path (Split-Path -Parent $exe) 'npm.cmd'
        return @{ Exe = $exe; Version = [version]($v.Trim()); Npm = $(if (Test-Path $npm) { $npm } else { $null }) }
    } catch { return $null }
}

function Find-SuiteDocker {
    $cmd = (Get-Command docker -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
    $exe = if ($cmd) { $cmd.Source } elseif (Test-Path "$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe") { "$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe" } else { $null }
    if (-not $exe) { return $null }
    $result = @{ Exe = $exe; Compose = $null; Running = $false; Desktop = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe" }
    try {
        $c = & $exe compose version --short 2>$null
        if ($LASTEXITCODE -eq 0 -and $c) { $result.Compose = [version](($c | Select-Object -First 1).Trim().TrimStart('v') -replace '[^0-9.].*$', '') }
    } catch {}
    $result.Running = Test-DockerRunning $exe
    return $result
}

function Test-DockerRunning([string]$DockerExe) {
    try {
        $null = & $DockerExe info --format '{{.ServerVersion}}' 2>$null
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
}

# Starts Docker Desktop if it is installed but not running, then waits for the engine.
function Start-DockerEngine([string]$DockerExe, [int]$Seconds = 240) {
    if (Test-DockerRunning $DockerExe) { return $true }
    # docker.exe lives in <Docker Desktop>\resources\bin (per-machine or per-user installation).
    $desktop = @((Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $DockerExe))) 'Docker Desktop.exe'),
                 "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
                 "$env:LOCALAPPDATA\Programs\DockerDesktop\Docker Desktop.exe") | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($desktop) {
        Write-Info 'Starting Docker Desktop (this can take a minute or two)...'
        Start-Process -FilePath $desktop | Out-Null
    }
    return (Wait-Until { Test-DockerRunning $DockerExe } $Seconds 'Docker')
}

# ---------------------------------------------------------------------------------------------
# Process bookkeeping: we only ever stop processes this suite started (checked by command line).
# ---------------------------------------------------------------------------------------------
function Get-ProcessCommandLine([int]$ProcessId) {
    $p = Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction SilentlyContinue
    if ($p) { return @{ CommandLine = [string]$p.CommandLine; Path = [string]$p.ExecutablePath } }
    return $null
}

function Save-Pid([string]$RunDir, [string]$Name, [int]$ProcessId) {
    Write-Utf8NoBom (Join-Path $RunDir "$Name.pid") ([string]$ProcessId)
}

function Stop-SuiteProcess([string]$RunDir, [string]$Name, [string]$MustContain) {
    $file = Join-Path $RunDir "$Name.pid"
    if (-not (Test-Path -LiteralPath $file)) { return $false }
    $id = 0
    [void][int]::TryParse(([IO.File]::ReadAllText($file)).Trim(), [ref]$id)
    $stopped = $false
    if ($id -gt 0) {
        $info = Get-ProcessCommandLine $id
        if ($info -and $info.CommandLine -and $info.CommandLine.IndexOf($MustContain, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            # /T also ends the child interpreter that a Windows virtual-environment python.exe starts.
            $null = & taskkill.exe /PID $id /T /F 2>&1
            $stopped = $true
        }
    }
    Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    return $stopped
}

function Get-RunningSuitePid([string]$RunDir, [string]$Name, [string]$MustContain) {
    $file = Join-Path $RunDir "$Name.pid"
    if (-not (Test-Path -LiteralPath $file)) { return 0 }
    $id = 0
    [void][int]::TryParse(([IO.File]::ReadAllText($file)).Trim(), [ref]$id)
    if ($id -le 0) { return 0 }
    $info = Get-ProcessCommandLine $id
    if ($info -and $info.CommandLine -and $info.CommandLine.IndexOf($MustContain, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $id }
    return 0
}

function Quote-Arg([string]$Value) {
    if ($Value.Contains('"')) { throw 'Paths containing double quotes are not supported.' }
    return '"' + $Value + '"'
}

# Start a background process with no window and no console shared with the caller, so closing the window
# that started it (or Windows Terminal) does not stop it and no terminal window pops up. cmd.exe writes its
# output to the suite's log folder. The recorded process is cmd.exe; stopping it ends the whole tree.
function Start-Hidden([string]$Exe, [string[]]$Arguments, [string]$WorkingDirectory, [string]$LogDir, [string]$Name) {
    $command = (@($Exe) + $Arguments | ForEach-Object { Quote-Arg $_ }) -join ' '
    $out = Quote-Arg (Join-Path $LogDir "$Name.out.log"); $err = Quote-Arg (Join-Path $LogDir "$Name.err.log")
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $env:SystemRoot 'System32\cmd.exe'
    $psi.Arguments = '/d /s /c "' + $command + ' 1>>' + $out + ' 2>>' + $err + '"'
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    return [Diagnostics.Process]::Start($psi)
}
# ---------------------------------------------------------------------------------------------
# Docker Compose for the Workbench
# ---------------------------------------------------------------------------------------------
function Invoke-WorkbenchCompose($Config, [string[]]$ComposeArgs, [switch]$Quiet) {
    $paths = Get-SuitePaths $Config.install_root
    $all = @('compose', '-p', $Config.compose_project, '--project-directory', $paths.Workbench,
             '-f', (Join-Path $paths.Workbench 'docker-compose.yml'), '-f', $paths.ComposeOverride) + $ComposeArgs
    $log = Join-Path $paths.Logs 'docker-compose.log'
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        if ($Quiet) {
            & $Config.docker @all *>> $log
        } else {
            & $Config.docker @all 2>&1 | ForEach-Object { $line = [string]$_; Add-Content -LiteralPath $log -Value $line; $line } | Out-Host
        }
        return $LASTEXITCODE
    } finally { $ErrorActionPreference = $old }
}

# ---------------------------------------------------------------------------------------------
# Health checks
# ---------------------------------------------------------------------------------------------
function Test-WorkbenchReady($Config) {
    $paths = Get-SuitePaths $Config.install_root
    $token = Read-SecretFile $paths.WorkbenchToken
    $r = Invoke-Local -Url ("http://127.0.0.1:{0}/api/readiness" -f $Config.ports.workbench) -Token $token -TimeoutSec 15
    if ($r.Status -ne 200) { return @{ Ok = $false; Status = $r.Status; Detail = $r.Error } }
    try { $j = $r.Body | ConvertFrom-Json } catch { return @{ Ok = $false; Status = $r.Status; Detail = 'not a Workbench' } }
    $db = @($j.checks | Where-Object { $_.name -eq 'database' })[0]
    return @{ Ok = ($db -and $db.status -eq 'READY'); Status = $j.status; Detail = $j; Checks = $j.checks }
}

function Test-ContextForgeReady($Config) {
    $paths = Get-SuitePaths $Config.install_root
    $r = Invoke-Local -Url ("http://127.0.0.1:{0}/api/status" -f $Config.ports.context_forge) -Token (Read-SecretFile $paths.CfToken) -TimeoutSec 5
    if ($r.Status -ne 200) { return $false }
    try { return (($r.Body | ConvertFrom-Json).service -eq 'Context Forge') } catch { return $false }
}

function Test-GetFilesReady($Config) {
    # Authenticated /health returns process details only to holders of this installation's token,
    # so a different Get Files on the same port is never mistaken for ours.
    $paths = Get-SuitePaths $Config.install_root
    $r = Invoke-Local -Url ("http://127.0.0.1:{0}/health" -f $Config.ports.get_files) -Token (Read-SecretFile $paths.GfToken) -TimeoutSec 5
    if ($r.Status -ne 200) { return $false }
    try { $j = $r.Body | ConvertFrom-Json; return ($j.service -eq 'Get Files' -and $j.ok -and $j.worker_alive -and $null -ne $j.process_id) } catch { return $false }
}

function Test-DocVerifyReady($Config) {
    $r = Invoke-Local -Url ("http://127.0.0.1:{0}/health" -f $Config.ports.docverify) -TimeoutSec 5
    if ($r.Status -ne 200) { return $false }
    try { return (($r.Body | ConvertFrom-Json).service -eq 'docverify') } catch { return $false }
}

# ---------------------------------------------------------------------------------------------
# Starting and stopping the four services
# ---------------------------------------------------------------------------------------------
function Start-ContextForge($Config) {
    $paths = Get-SuitePaths $Config.install_root
    if (Test-ContextForgeReady $Config) { return $true }
    if (Test-PortListening $Config.ports.context_forge) { Write-Bad ("Port {0} is used by another program, so Context Forge cannot start." -f $Config.ports.context_forge); return $false }
    $py = Join-Path $paths.ContextForge '.venv\Scripts\python.exe'
    $saved = @{ roots = $env:CONTEXT_FORGE_INPUT_ROOTS; out = $env:CONTEXT_FORGE_OUTPUT_DIR; tf = $env:CONTEXT_FORGE_TOKEN_FILE; t = $env:CONTEXT_FORGE_TOKEN }
    try {
        $env:CONTEXT_FORGE_INPUT_ROOTS = (@($Config.context_forge_input_roots) -join ';')
        $env:CONTEXT_FORGE_OUTPUT_DIR = $paths.CfOutput
        $env:CONTEXT_FORGE_TOKEN_FILE = $paths.CfToken
        $env:CONTEXT_FORGE_TOKEN = $null
        $p = Start-Hidden $py @('-m', 'context_forge.server', '--host', '127.0.0.1', '--port', [string]$Config.ports.context_forge) $paths.ContextForge $paths.Logs 'context-forge'
    } finally {
        $env:CONTEXT_FORGE_INPUT_ROOTS = $saved.roots; $env:CONTEXT_FORGE_OUTPUT_DIR = $saved.out
        $env:CONTEXT_FORGE_TOKEN_FILE = $saved.tf; $env:CONTEXT_FORGE_TOKEN = $saved.t
    }
    Save-Pid $paths.Run 'context-forge' $p.Id
    return (Wait-Until { Test-ContextForgeReady $Config } 60 'Context Forge')
}

function Start-GetFiles($Config) {
    $paths = Get-SuitePaths $Config.install_root
    if (Test-GetFilesReady $Config) { return $true }
    if (Test-PortListening $Config.ports.get_files) { Write-Bad ("Port {0} is used by another program, so Get Files cannot start." -f $Config.ports.get_files); return $false }
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $saved = $env:GET_FILES_ALLOW_DOCKER_HOST
    try {
        if ($Config.workbench_mode -eq 'Docker') { $env:GET_FILES_ALLOW_DOCKER_HOST = '1' }
        # Get Files' own launcher starts the service in the background and returns once it is healthy. Its output
        # goes to a file: the background service inherits the launcher's handles, so reading them through a pipe
        # would wait for the service to exit.
        $p = Start-Hidden $ps @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $paths.GetFiles 'start.ps1'), '-Background',
                               '-Port', [string]$Config.ports.get_files, '-DataPath', $paths.GetFilesData) $paths.GetFiles $paths.Logs 'get-files-start'
        if (-not $p.WaitForExit(90000)) { Write-Warn2 'The Get Files launcher is taking unusually long.' }
    } finally { $env:GET_FILES_ALLOW_DOCKER_HOST = $saved }
    return (Wait-Until { Test-GetFilesReady $Config } 30 'Get Files')
}

function Stop-GetFiles($Config) {
    $paths = Get-SuitePaths $Config.install_root
    $state = Join-Path $paths.GetFilesData 'service-state.json'
    if (-not (Test-Path -LiteralPath $state)) { return $false }
    $stopped = $false
    try {
        $s = [IO.File]::ReadAllText($state) | ConvertFrom-Json
        foreach ($id in @($s.pid, $s.launcher_pid) | Select-Object -Unique) {
            if (-not $id) { continue }
            $info = Get-ProcessCommandLine ([int]$id)
            if ($info -and $info.CommandLine -match '-m"?\s+"?corpus' -and $info.CommandLine.IndexOf($paths.GetFilesData, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                Stop-Process -Id ([int]$id) -Force -ErrorAction SilentlyContinue; $stopped = $true
            }
        }
    } catch {}
    return $stopped
}

function Start-DocVerifyService($Config) {
    $paths = Get-SuitePaths $Config.install_root
    if (Test-DocVerifyReady $Config) { return $true }
    if (Test-PortListening $Config.ports.docverify) { Write-Bad ("Port {0} is used by another program, so the Document Verification service cannot start." -f $Config.ports.docverify); return $false }
    $p = Start-Hidden $Config.python @('-m', 'docbridge', '--config', $paths.DocVerifyConf, 'serve') $paths.DocVerify $paths.Logs 'docverify'
    Save-Pid $paths.Run 'docverify' $p.Id
    return (Wait-Until { Test-DocVerifyReady $Config } 30 'Document Verification')
}

function Start-Workbench($Config) {
    $paths = Get-SuitePaths $Config.install_root
    if ((Test-WorkbenchReady $Config).Ok) { return $true }
    if ($Config.workbench_mode -eq 'Docker') {
        if (-not (Start-DockerEngine $Config.docker)) {
            Write-Bad 'Docker Desktop is not running and did not start. Open Docker Desktop from the Start Menu, wait until it says "Engine running", then try again.'
            return $false
        }
        $code = Invoke-WorkbenchCompose $Config @('up', '-d') -Quiet
        if ($code -ne 0) { Write-Bad ('Docker could not start the Research Workbench. Details: ' + (Join-Path $paths.Logs 'docker-compose.log')); return $false }
    } else {
        if (Test-PortListening $Config.ports.workbench) { Write-Bad ("Port {0} is used by another program, so the Research Workbench cannot start." -f $Config.ports.workbench); return $false }
        # Absolute paths, so stop/uninstall can recognise this installation's process by its command line.
        $p = Start-Hidden $Config.node @(('--env-file-if-exists=' + $paths.WorkbenchEnv), (Join-Path $paths.Workbench 'src\server.js')) $paths.Workbench $paths.Logs 'workbench'
        Save-Pid $paths.Run 'workbench' $p.Id
    }
    return (Wait-Until { (Test-WorkbenchReady $Config).Ok } 180 'Workbench')
}

function Stop-Workbench($Config) {
    $paths = Get-SuitePaths $Config.install_root
    if ($Config.workbench_mode -eq 'Docker') {
        if (-not (Test-DockerRunning $Config.docker)) { return $true }
        return ((Invoke-WorkbenchCompose $Config @('stop') -Quiet) -eq 0)
    }
    return (Stop-SuiteProcess $paths.Run 'workbench' $paths.Workbench)
}

function Start-Suite($Config) {
    $results = [ordered]@{}
    Write-Info 'Starting Get Files (source library)...'
    $results['Get Files'] = Start-GetFiles $Config
    Write-Info 'Starting Context Forge (PDF and scanned-page text extraction)...'
    $results['Context Forge'] = Start-ContextForge $Config
    Write-Info 'Starting the Research Workbench (claim checking)...'
    $results['Research Workbench'] = Start-Workbench $Config
    Write-Info 'Starting the Document Verification service...'
    $results['Document Verification'] = Start-DocVerifyService $Config
    return $results
}

function Stop-Suite($Config) {
    $paths = Get-SuitePaths $Config.install_root
    [void](Stop-SuiteProcess $paths.Run 'docverify' $paths.DocVerifyConf)
    [void](Stop-SuiteProcess $paths.Run 'context-forge' $paths.ContextForge)
    [void](Stop-GetFiles $Config)
    [void](Stop-Workbench $Config)
}

# ---------------------------------------------------------------------------------------------
# Running the docverify command line
# ---------------------------------------------------------------------------------------------
# Runs `python -m docbridge --config <conf> <args>`; returns @{ Code; Json; Errors }.
# Progress lines (stderr) are passed to $OnProgress as they arrive.
function Invoke-DocVerify($Config, [string[]]$Arguments, [scriptblock]$OnProgress) {
    $paths = Get-SuitePaths $Config.install_root
    $stdout = New-Object Collections.Generic.List[string]
    $errors = New-Object Collections.Generic.List[string]
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $savedIo = $env:PYTHONIOENCODING; $env:PYTHONIOENCODING = 'utf-8'
    Push-Location -LiteralPath $paths.DocVerify
    try {
        & $Config.python -m docbridge --config $paths.DocVerifyConf @Arguments 2>&1 | ForEach-Object {
            if ($_ -is [Management.Automation.ErrorRecord]) {
                $line = [string]$_.Exception.Message
                if ($line.StartsWith('error')) { $errors.Add($line) }
                elseif ($OnProgress) { & $OnProgress $line }
            } else { $stdout.Add([string]$_) }
        }
        $code = $LASTEXITCODE
    } finally {
        Pop-Location; $ErrorActionPreference = $old; $env:PYTHONIOENCODING = $savedIo
    }
    $json = $null
    if ($stdout.Count) { try { $json = ($stdout -join "`n") | ConvertFrom-Json } catch {} }
    return @{ Code = $code; Json = $json; Errors = @($errors); Raw = ($stdout -join "`n") }
}
