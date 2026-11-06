# Verify a Document: drop one or more .docx/.pdf files on the shortcut (or click it and pick a file).
# Runs `docverify check` against the local services and opens the report in your browser.
param(
    [switch]$NoPause,
    [switch]$NoOpen,
    [switch]$Yes,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Files
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'SuiteCommon.ps1')

# What a model judged after reading passages. Statements with nothing compared are explained by $ReasonHelp instead.
$StatusHelp = [ordered]@{
    VERIFIED       = 'a model judged that a quoted source passage supports it'
    OVERSTATED     = 'a model judged that the source supports only a weaker or narrower version'
    MISCITED       = 'a model judged that the cited source or pin cite does not say this'
    CONTRADICTED   = 'a model judged that a source says the opposite'
    STALE          = 'a model''s label for an outdated source; no date check backs it'
    UNSUPPORTED    = 'a model did not find it in the passages it was shown'
    UNVERIFIABLE   = 'a model could not decide from the passages it was shown'
    FABRICATED     = 'a model''s label; no citation lookup backs it. Check it by hand'
}
$ReasonHelp = [ordered]@{
    NO_SOURCES          = 'no source was linked'
    NO_ELIGIBLE_SOURCE  = 'sources were linked, but none qualifies as evidence (library documents do not)'
    SOURCES_UNAVAILABLE = 'a source was found but could not be read, or was blocked'
    NO_MATCHING_PASSAGE = 'no passage in the sources shared a word with the statement'
    INVALID_MODEL_REPLY = 'passages were sent, but the model''s reply failed validation'
}

function Select-DocumentFile {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object Windows.Forms.OpenFileDialog
    $dialog.Title = 'Choose a document to verify'
    $dialog.Filter = 'Word or PDF documents (*.docx;*.pdf)|*.docx;*.pdf|Markdown or text (*.md;*.markdown;*.txt)|*.md;*.markdown;*.txt'
    $dialog.Multiselect = $true
    $dialog.InitialDirectory = [Environment]::GetFolderPath('MyDocuments')
    if ($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) { return @($dialog.FileNames) }
    return @()
}

# The Workbench logs a short, payload-free reason when a model call fails (for example "provider: HTTP 401").
function Get-WorkbenchFailureReason($Config, [datetime]$Since) {
    $paths = Get-SuitePaths $Config.install_root
    $lines = @()
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        if ($Config.workbench_mode -eq 'Docker') {
            $sinceText = $Since.ToUniversalTime().AddSeconds(-5).ToString('yyyy-MM-ddTHH:mm:ssZ')
            $lines = & $Config.docker compose -p $Config.compose_project --project-directory $paths.Workbench `
                -f (Join-Path $paths.Workbench 'docker-compose.yml') -f $paths.ComposeOverride logs --no-color --since $sinceText app 2>$null
        } else {
            $log = Join-Path $paths.Logs 'workbench.err.log'
            if (Test-Path -LiteralPath $log) { $lines = Get-Content -LiteralPath $log -Tail 50 }
        }
    } catch {} finally { $ErrorActionPreference = $old }
    $reason = $null
    foreach ($line in @($lines)) {
        $i = ([string]$line).IndexOf('{"event":"request_failed"')
        if ($i -lt 0) { continue }
        try { $j = ([string]$line).Substring($i) | ConvertFrom-Json; if ($j.reason) { $reason = [string]$j.reason } } catch {}
    }
    return $reason
}

function Explain-ProviderReason([string]$Reason) {
    if (-not $Reason) { return @() }
    if ($Reason -match 'provider: HTTP 401|provider failed \(HTTP 401\)') {
        return @('OpenAI rejected the API key (it is wrong, expired or revoked). Create a new key at',
                 'https://platform.openai.com/api-keys and run Setup again to replace it. Nothing was charged.')
    }
    if ($Reason -match 'provider: HTTP 429|provider failed \(HTTP 429\)') {
        return @('OpenAI refused the request because of a usage limit. Usually the account has no credit or billing',
                 'is not set up (https://platform.openai.com/settings/organization/billing), or you sent too many',
                 'requests in a short time. Wait a minute and try again.')
    }
    if ($Reason -match 'provider: HTTP 403|provider failed \(HTTP 403\)') { return @('OpenAI refused access for this key or model (HTTP 403). Check the key''s project permissions.') }
    if ($Reason -match 'provider: HTTP 40[04]|provider failed \(HTTP 40[04]\)') { return @('OpenAI did not accept the request (the configured model may not be available to your account).') }
    if ($Reason -match 'connection failed|request failed before a response|no response within') {
        return @('The Workbench could not reach OpenAI. Check this computer''s internet connection, VPN or firewall',
                 '(api.openai.com must be reachable), then try again.')
    }
    if ($Reason -match 'provider: HTTP 5\d\d|provider failed \(HTTP 5\d\d\)') {
        return @('OpenAI reported a problem on its side. No result was recorded for your document. Try again later;',
                 'see https://status.openai.com/ if it continues.')
    }
    if ($Reason -match 'reply contained no text|model refused|incomplete reply|reply text|not valid JSON') {
        return @('OpenAI answered without a usable reply (empty, refused, cut off or not readable). No result was recorded for your',
                 'document. The call may still be billed. Try again later; if it keeps happening, see the Workbench log.')
    }
    if ($Reason -match 'daily AI allowance') { return @('The suite''s daily AI call limit is used up. It resets at midnight UTC.') }
    return @("The Workbench reported: $Reason")
}

function Explain-Failure($Config, [string]$ErrorLine, [string]$LastStep, [datetime]$Started) {
    $code = if ($ErrorLine -match 'error \(([a-z0-9_]+)\)') { $Matches[1] } else { '' }
    $paid = ($LastStep -match 'model call|OpenAI')
    Write-Host ''
    Write-Bad 'The document could not be verified.'
    switch -Regex ($code) {
        '^service_unavailable$' { Write-Info 'The Research Workbench did not answer. Use "Start Brightline Verification Suite" and try again.'; return }
        '^workbench_token_unreadable$|^upstream_http_401$' { Write-Info 'The suite''s Workbench access token was not accepted. Run Setup again to repair the installation.'; return }
        '^invalid_file$|^file_not_allowed$' { Write-Info ($ErrorLine -replace '^error \([^)]*\):\s*', ''); return }
        '^upstream_http_422$|^upstream_http_415$|^upstream_http_413$' {
            Write-Info 'The Workbench could not read this file. It may be damaged, password-protected, or larger than 25 MB.'; return }
        '^pdf_needs_normalization$|^normalization_incomplete$' {
            Write-Info 'This PDF has no readable text layer (it may be scanned or damaged), and Context Forge could not'
            Write-Info 'extract all of its pages. Try a text-based PDF or the original Word file.'; return }
        '^upstream_http_429$' { Write-Info 'The Workbench is busy or its daily AI limit is used up. Wait a few minutes and try again.'; return }
        '^no_claims$|^workbench_outdated$|^document_runtime_missing$|^upstream_http_409$' { Write-Info ($ErrorLine -replace '^error \([^)]*\):\s*', ''); return }
    }
    if ($paid -or $code -match '^upstream_http_5\d\d$|^submission_uncertain$|incomplete') {
        $stepLabel = if ($paid) { 'The paid AI step failed: ' } else { 'This step failed: ' }
        Write-Info ($stepLabel + ($LastStep -replace '^\s+', ''))
        $reason = Get-WorkbenchFailureReason $Config $Started
        if (-not $reason) { $reason = $ErrorLine }
        $lines = Explain-ProviderReason $reason
        if ($lines.Count) { foreach ($l in $lines) { Write-Info $l } }
        else { Write-Info 'Common causes: the OpenAI API key is wrong or has no credit, or there is no internet connection.' }
        return
    }
    Write-Info ($ErrorLine -replace '^error \([^)]*\):\s*', '')
}

$exit = 0
try {
    $config = Read-SuiteConfig (Get-RootFromBin $PSScriptRoot)
    $Files = @($Files | Where-Object { $_ })
    if (-not $Files.Count) { $Files = Select-DocumentFile }
    if (-not $Files.Count) { Write-Info 'No file chosen.'; $Files = @() }

    if ($Files.Count) {
        Write-Host 'Brightline Verification Suite - Verify a Document' -ForegroundColor White
        $ready = Test-WorkbenchReady $config
        if (-not $ready.Ok -or -not (Test-ContextForgeReady $config) -or -not (Test-GetFilesReady $config)) {
            Write-Info 'Starting the verification services first (this can take a minute)...'
            $null = Start-Suite $config
            $ready = Test-WorkbenchReady $config
        }
        if (-not $ready.Ok) { throw 'The Research Workbench is not running. Use "Start Brightline Verification Suite", then try again.' }
        $model = @($ready.Checks | Where-Object { $_.name -eq 'draft_model' })[0]
        if ($model -and $model.status -ne 'READY') { throw 'No OpenAI API key is configured for the Workbench. Run Setup again and enter your key.' }
    }

    foreach ($file in $Files) {
        Write-Host ''
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { Write-Bad "File not found: $file"; $exit = 1; continue }
        $item = Get-Item -LiteralPath $file
        if ($item.Extension.ToLowerInvariant() -notin @('.docx', '.pdf', '.md', '.markdown', '.txt')) {
            Write-Bad ("{0}: only Word (.docx) and PDF files can be verified (also .md, .markdown and .txt). Old .doc files: open in Word and Save As .docx." -f $item.Name)
            $exit = 1; continue
        }
        Write-Host ("Document: {0} ({1:N0} KB)" -f $item.Name, ($item.Length / 1KB)) -ForegroundColor White
        Write-Info 'The text of this document will be sent to OpenAI through the Research Workbench, and the'
        Write-Info 'model calls are billed to your OpenAI account.'
        if ($config.discover_sources) {
            Write-Info 'The Workbench will also search the web for sources. That adds up to 10 paid model calls, and each'
            Write-Info 'call can run several web searches; the searches inside a call are not capped.'
        }
        if (-not $Yes -and -not (Read-YesNo 'Verify this document now?' $false)) { Write-Info 'Skipped.'; continue }

        $started = Get-Date
        $script:lastStep = ''
        $arguments = @('check', $item.FullName)
        if ($config.discover_sources) { $arguments += '--discover' }
        Write-Info 'Working. Long documents can take 10-30 minutes; keep this window open.'
        $result = Invoke-DocVerify $config $arguments {
            param($line)
            if ($line.StartsWith('Result: ')) { return }  # shown in the summary below
            $friendly = $line -replace '\(model call\)', '(paid OpenAI call)' -replace '\(model and web search calls\)', '(paid OpenAI and web search calls)'
            $script:lastStep = $friendly
            Write-Host ('   ' + (Get-Date).ToString('HH:mm:ss') + '  ' + $friendly)
        }
        # A written report exits 0, or 3 when nothing was compared. Any other code, or no summary, means no report.
        if (($result.Code -ne 0 -and $result.Code -ne 3) -or -not $result.Json) {
            $exit = 1
            $line = if ($result.Errors.Count) { $result.Errors[-1] } else { 'error: docverify stopped unexpectedly' }
            Explain-Failure $config $line $script:lastStep $started
            Write-Info ('Technical detail: ' + $line)
            continue
        }
        $r = $result.Json
        Write-Host ''
        Write-Good ('Finished in {0:N0} minutes.' -f ((Get-Date) - $started).TotalMinutes)
        Write-Host ''
        if ($r.nothing_compared) { Write-Warn2 $r.headline; $exit = 3 } else { Write-Info $r.headline }
        if ($r.coverage_complete -eq $false) {
            Write-Warn2 'Statements may be missing: the model said it did not go through the whole text.'
            if ($r.coverage_notes) { Write-Info ('  ' + $r.coverage_notes) }
        }
        $c = $r.claims
        Write-Host ''
        Write-Info ("{0} statements found: {1} compared with a source, {2} not compared, {3} needing no source." -f $c.total, $c.compared, $c.not_checked, $c.not_applicable)
        if ($c.compared) { Write-Info ("Compared: {0} verified, {1} with a problem to look at." -f $c.verified, $c.with_findings) }
        foreach ($status in $StatusHelp.Keys) {
            $n = [int]$r.counts.$status
            if ($status -eq 'UNVERIFIABLE') { $n -= [int]$c.not_checked }
            if ($n -gt 0) { Write-Info ("  {0,4}  {1,-15} {2}" -f $n, $status, $StatusHelp[$status]) }
        }
        if ($c.not_checked) {
            Write-Info 'Not compared (these say nothing about whether the statement is right):'
            foreach ($reason in $ReasonHelp.Keys) {
                $n = [int]$r.not_checked_by_reason.$reason
                if ($n -gt 0) { Write-Info ("  {0,4}  {1,-20} {2}" -f $n, $reason, $ReasonHelp[$reason]) }
            }
        }
        foreach ($gap in @($r.evidence_gaps.discovery_failures)) {
            if ($gap) { Write-Warn2 ('Source not used: ' + $(if ($gap.candidate_url) { $gap.candidate_url } else { $gap.candidate_title }) + ': ' + $gap.reason) }
        }
        foreach ($gap in @($r.evidence_gaps.excluded_sources)) {
            if ($gap) { Write-Warn2 ('Source left out: ' + $(if ($gap.title) { $gap.title } else { $gap.canonical_url }) + ': ' + $gap.reason) }
        }
        foreach ($w in @($r.document_warnings)) { if ($w) { Write-Warn2 ('Compare the text with your original: ' + $w) } }
        foreach ($l in @($r.limitations)) { if ($l -and $l.code) { Write-Warn2 ('Note: ' + $(if ($l.message) { $l.message } else { $l.code })) } }
        if ($c.compared) { Write-Info 'A result is a model''s reading of the sources, not legal advice. Read the quoted passages in the report.' }
        Write-Info ('Report: ' + $r.report_html)
        if (-not $NoOpen) { Start-Process $r.report_html }
    }
} catch {
    Write-Bad $_.Exception.Message
    $exit = 1
}
if (-not $NoPause) { Write-Host ''; Read-Host '   Press Enter to close this window' | Out-Null }
exit $exit
