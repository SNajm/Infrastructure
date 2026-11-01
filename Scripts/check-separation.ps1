#requires -Version 7
<#
.SYNOPSIS
    DSEP01.03: log in as <app>deploy and prove it can touch only its own app.

.DESCRIPTION
    Pipes server/check-deploy-separation.sh to the server over ssh as <app>deploy, with the app's
    deploy key (from ssh-agent). Prints PASS/FAIL per check; exits 1 on any FAIL. Changes nothing on
    the server except a test file in the app's own folder, removed straight away.

.EXAMPLE
    .\Scripts\check-separation.ps1 -App mimir -Server GlyphScribe

.NOTES
    Chat ID  C001.261031T2215
#>
param(
    [Parameter(Mandatory)][ValidateSet('exchequer', 'ashborne', 'sovereign', 'ravenhold', 'mimir')][string] $App,
    [Parameter(Mandatory)][ValidateSet('GlyphScribe', 'GlyphWarden')][string] $Server
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ScriptRunLog.ps1')
Initialize-RunLog -ChatId 'C001.261031T2215' -ScriptName 'check-separation.ps1'

function Fail([string] $Message) {
    Write-RunLogEntry -Outcome FAILED -Detail "$App on $Server - $Message"
    Write-Host "X $Message" -ForegroundColor Red
    exit 1
}

$hosts = @{ GlyphScribe = 'glyphscribe.crucible'; GlyphWarden = '10.10.15.30' }
$key   = "D:\repos\.config\$App\$App-deploy.key"
$ssh   = Join-Path $env:WINDIR 'System32\OpenSSH\ssh.exe'
$check = Join-Path (Split-Path $PSScriptRoot -Parent) 'server\check-deploy-separation.sh'
if (-not (Test-Path $key)) { Fail "deploy key not found: $key" }

$body = (Get-Content $check -Raw) -replace "`r", ''
$out  = $body | & $ssh -i $key -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 "${App}deploy@$($hosts[$Server])" "tr -d '\r' | bash -s $App" 2>&1
# tr on the server: PowerShell appends a CRLF after piped text, and a lone "\r" line reached bash as
# a command (exit 127) after every check had passed (first run, mimir on GlyphScribe, 2026-11-01).
$rc   = $LASTEXITCODE
$out | ForEach-Object {
    $line = "$_"
    $color = if ($line.StartsWith('PASS')) { 'Green' } elseif ($line.StartsWith('FAIL')) { 'Red' } else { 'Gray' }
    Write-Host $line -ForegroundColor $color
}
if ($rc -ne 0) { Fail "separation check failed or could not log in (exit $rc)" }
Write-RunLogEntry -Outcome SUCCESS -Detail "$App on $Server - all checks passed"
