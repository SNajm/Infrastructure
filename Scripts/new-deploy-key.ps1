#requires -Version 7
<#
.SYNOPSIS
    DSEP01.01: create an app's deploy key on this PC (passphrase, locked file, loaded in ssh-agent).

.DESCRIPTION
    Writes D:\repos\.config\<app>\<app>-deploy.key (+ .pub). ssh-keygen asks for the passphrase itself;
    a key without one is refused. Never overwrites an existing key.

    Run it in a normal PowerShell window: Claude Code's "!" prompt cannot answer the passphrase prompt.

.EXAMPLE
    .\Scripts\new-deploy-key.ps1 -App mimir

.NOTES
    Chat ID  C001.261031T2215
#>
param(
    [Parameter(Mandatory)][ValidateSet('exchequer', 'ashborne', 'sovereign', 'ravenhold', 'mimir')][string] $App
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ScriptRunLog.ps1')
Initialize-RunLog -ChatId 'C001.261031T2215' -ScriptName 'new-deploy-key.ps1'

function Fail([string] $Message) {
    Write-RunLogEntry -Outcome FAILED -Detail "$App - $Message"
    Write-Host "X $Message" -ForegroundColor Red
    exit 1
}

# Windows OpenSSH, not Git Bash's: only these talk to the Windows ssh-agent (DSEP00.06.a lesson).
$openssh = Join-Path $env:WINDIR 'System32\OpenSSH'
$keygen  = Join-Path $openssh 'ssh-keygen.exe'
$sshAdd  = Join-Path $openssh 'ssh-add.exe'
if (-not (Test-Path $keygen)) { Fail "Windows OpenSSH not found at $openssh" }

$dir = "D:\repos\.config\$App"
$key = Join-Path $dir "$App-deploy.key"
if (Test-Path $key) { Fail "$key already exists; not overwriting it." }
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }

$comment = "$App-deploy@$($env:COMPUTERNAME) C001.261031T2215"
Write-Host "==> Creating $key ($comment). Choose a passphrase when asked." -ForegroundColor Cyan
& $keygen -t ed25519 -f $key -C $comment
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $key)) { Fail 'ssh-keygen did not create the key.' }

# An empty passphrase opens the key with -P "": that must fail.
& $keygen -y -P '' -f $key 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
    Fail "the key has NO passphrase. Add one now: & '$keygen' -p -f '$key'   (then run ssh-add yourself)"
}

# Only this Windows account may read it, or Windows ssh refuses to use it.
& icacls $key /inheritance:r /grant:r "$(whoami):(R,W)" | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "icacls could not lock $key" }

Write-Host '==> Adding it to ssh-agent (asks for the passphrase once).' -ForegroundColor Cyan
& $sshAdd $key
if ($LASTEXITCODE -ne 0) { Fail 'ssh-add failed: is the "OpenSSH Authentication Agent" service running?' }

$pub = (Get-Content "$key.pub" -Raw).Trim()
$fp  = (& $keygen -lf "$key.pub")
Write-Host ''
Write-Host "Key:  $key" -ForegroundColor Green
Write-Host "      $fp"
Write-Host "Next: .\Scripts\deploy-user.ps1 -App $App -Server GlyphScribe -Mode stage"
Write-RunLogEntry -Outcome SUCCESS -Detail "$App - $fp"
