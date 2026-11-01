#requires -Version 7
<#
.SYNOPSIS
    DSEP01.02: set up or switch an app's deploy user on a web server, as glyphops.

.DESCRIPTION
    Copies server/add-deploy-user.sh (and for 'stage' the app's public key) to /tmp on the server as
    glyphops, then runs it with sudo in an interactive session. On the server it shows the plan and asks
    for 'yes'; sudo asks for glyphops's password.

      stage   create <app>deploy with its key, group and sudo rule. Old deploys keep working.
      take    the switch: /opt/<app> passes from glyphadmin to <app>deploy.
      return  rollback of 'take'.

    Run it in a normal PowerShell window (passwords are typed at the prompts).

.EXAMPLE
    .\Scripts\deploy-user.ps1 -App mimir -Server GlyphScribe -Mode stage

.NOTES
    Chat ID  C001.261031T2215
#>
param(
    [Parameter(Mandatory)][ValidateSet('exchequer', 'ashborne', 'sovereign', 'ravenhold', 'mimir')][string] $App,
    [Parameter(Mandatory)][ValidateSet('GlyphScribe', 'GlyphWarden')][string] $Server,
    [Parameter(Mandatory)][ValidateSet('stage', 'take', 'return')][string] $Mode
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ScriptRunLog.ps1')
Initialize-RunLog -ChatId 'C001.261031T2215' -ScriptName 'deploy-user.ps1'

function Fail([string] $Message) {
    Write-RunLogEntry -Outcome FAILED -Detail "$App $Mode on $Server - $Message"
    Write-Host "X $Message" -ForegroundColor Red
    exit 1
}

$hosts  = @{ GlyphScribe = 'glyphscribe.crucible'; GlyphWarden = '10.10.15.30' }
$remote = "glyphops@$($hosts[$Server])"
$opsKey = Join-Path $HOME '.ssh\id_ed25519_glyphops'
$ssh    = Join-Path $env:WINDIR 'System32\OpenSSH\ssh.exe'
$scp    = Join-Path $env:WINDIR 'System32\OpenSSH\scp.exe'
$common = @('-i', $opsKey, '-o', 'IdentitiesOnly=yes', '-o', 'ConnectTimeout=10')

$repo   = Split-Path $PSScriptRoot -Parent
$script = Join-Path $repo 'server\add-deploy-user.sh'
$pub    = "D:\repos\.config\$App\$App-deploy.key.pub"
if (-not (Test-Path $opsKey)) { Fail "operator key not found: $opsKey (DSEP00.06.a)" }
if ($Mode -eq 'stage' -and -not (Test-Path $pub)) { Fail "deploy key not found: $pub (run new-deploy-key.ps1 -App $App first)" }

# LF copies in a temp folder: a CR reaching bash breaks the script.
$tmp = Join-Path ([IO.Path]::GetTempPath()) "dsep-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $files = @()
    $s = Join-Path $tmp 'add-deploy-user.sh'
    [IO.File]::WriteAllText($s, ((Get-Content $script -Raw) -replace "`r", ''))
    $files += $s
    if ($Mode -eq 'stage') {
        $p = Join-Path $tmp "$App-deploy.pub"
        [IO.File]::WriteAllText($p, ((Get-Content $pub -Raw) -replace "`r", ''))
        $files += $p
    }

    Write-Host "==> Copying to $remote`:/tmp ..." -ForegroundColor Cyan
    & $scp -q @common -o BatchMode=yes @files "${remote}:/tmp/"
    if ($LASTEXITCODE -ne 0) { Fail "could not copy to $remote (is the glyphops key in ssh-agent?)" }

    Write-Host "==> Running '$Mode' for $App on $Server. sudo asks for glyphops's password." -ForegroundColor Cyan
    & $ssh -t @common $remote "sudo bash /tmp/add-deploy-user.sh $App $Mode; rc=`$?; rm -f /tmp/add-deploy-user.sh /tmp/$App-deploy.pub; exit `$rc"
    if ($LASTEXITCODE -ne 0) { Fail "add-deploy-user.sh $App $Mode exited $LASTEXITCODE on $Server (see above)" }
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

Write-RunLogEntry -Outcome SUCCESS -Detail "$App $Mode on $Server"
if ($Mode -eq 'stage') { Write-Host "Next: .\Scripts\check-separation.ps1 -App $App -Server $Server" }
