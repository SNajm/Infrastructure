#requires -Version 7
<#
.SYNOPSIS
    Shared run log for the Infrastructure scripts. Dot-source it; do not run it.

.DESCRIPTION
    Every script in this folder records, durably, that it ran: which chat and session
    authored it, whether it succeeded, and when.

    WHY THIS EXISTS. These scripts change databases, logins and installed builds. Weeks
    later the only questions that matter are "did that migration actually run, and when",
    and "which session produced this thing". A console that has since been closed answers
    neither. A script that fails silently and leaves no trace is the failure mode the
    universal rule in D:\Claude\General\unhandled-errors-must-be-recorded.md exists to
    prevent, and the Chat ID convention only pays off if the ID survives into the artifacts
    the chat produced.

    The ChatId passed in is the session that AUTHORED the script, taken from its .NOTES
    header. It is not the session that happens to be running it -- a script run in 2027
    still reports the session that wrote it, which is the thing you need in order to find
    the reasoning behind it.

    LOGGING NEVER BREAKS THE CALLER. Every write is wrapped: a locked file or a read-only
    disk degrades to a warning on the console. A script that does real work must not fail
    because its bookkeeping could not be written.

.EXAMPLE
    . (Join-Path $PSScriptRoot 'ScriptRunLog.ps1')
    Initialize-RunLog -ChatId 'C001.261031T2215' -ScriptName 'deploy.ps1'
    ...
    Write-RunLogEntry -Outcome SUCCESS -Detail 'mimir - key created'

.NOTES
    Chat ID  C001.261031T2215
#>

Set-StrictMode -Version Latest

# Where the log lives. logs/ is already in .gitignore -- a run log is machine-local
# history, not source. One file, appended to, never rotated by these scripts: a few
# hundred bytes per run means it stays readable for years.
$script:RunLogPath   = Join-Path (Split-Path $PSScriptRoot -Parent) 'logs\script-runs.log'
$script:RunLogChatId = '(unknown)'
$script:RunLogScript = '(unknown)'
$script:RunLogStart  = $null
$script:RunLogWritten = $false

<#
Call once, at the top of a script, before anything can fail.
#>
function Initialize-RunLog {
    param(
        [Parameter(Mandatory)][string] $ChatId,
        [Parameter(Mandatory)][string] $ScriptName
    )
    $script:RunLogChatId  = $ChatId
    $script:RunLogScript  = $ScriptName
    $script:RunLogStart   = [datetime]::UtcNow
    $script:RunLogWritten = $false
}

<#
Appends one line and returns. Outcome is SUCCESS or FAILED.

Only the FIRST call writes. Fail is called from inside nested helpers, and a script that
fails during its own cleanup would otherwise record two contradictory outcomes for one run.
The first one is the true one.
#>
function Write-RunLogEntry {
    param(
        [Parameter(Mandatory)][ValidateSet('SUCCESS', 'FAILED')][string] $Outcome,
        [string] $Detail = ''
    )

    if ($script:RunLogWritten) { return }
    $script:RunLogWritten = $true

    try {
        $dir = Split-Path $script:RunLogPath -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

        # UTC, sortable. A log read a year later must not depend on which machine's
        # timezone wrote it, and ISO order means sort and chronological order agree.
        $when = [datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')

        $elapsed = if ($script:RunLogStart) {
            '{0:0.0}s' -f ([datetime]::UtcNow - $script:RunLogStart).TotalSeconds
        } else { '-' }

        # Fixed-width columns so the file reads as a table without a parser. ASCII only:
        # a different console code page turns anything else into mojibake (EE10).
        $line = '{0}Z  {1,-30} {2,-20} {3,-7} {4,7}  {5}' -f `
            $when, $script:RunLogScript, $script:RunLogChatId, $Outcome, $elapsed, $Detail

        Add-Content -Path $script:RunLogPath -Value $line -Encoding utf8
    }
    catch {
        # Deliberately non-fatal. See the header: bookkeeping must not sink real work.
        Write-Host "  (could not write the run log: $($_.Exception.Message))" -ForegroundColor DarkYellow
    }
}

<#
Where the log is, for a script that wants to tell the operator where to look.
#>
function Get-RunLogPath { return $script:RunLogPath }
