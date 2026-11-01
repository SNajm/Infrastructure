#requires -Version 7
<#
.SYNOPSIS
    Guards for the Infrastructure scripts. Run: pwsh -NoProfile -File Tests\run-tests.ps1

.DESCRIPTION
    Plain PowerShell (the machine's Pester is 3.4). Checks:
      - every Scripts\*.ps1 that does work parses, initialises the run log with its own file name and
        the Chat ID in its .NOTES header, and records both SUCCESS and FAILED;
      - no script takes a credential as a parameter;
      - every server\*.sh passes bash -n, has LF endings, and its CHAT_ID (if any) matches the repo's.

.NOTES
    Chat ID  C001.261031T2215
#>
Set-StrictMode -Version Latest
$repo = Split-Path $PSScriptRoot -Parent
$failures = [System.Collections.Generic.List[string]]::new()
$checks = 0
function Check([bool] $ok, [string] $what) {
    $script:checks++
    if (-not $ok) { $script:failures.Add($what) }
}

foreach ($f in Get-ChildItem (Join-Path $repo 'Scripts') -Filter *.ps1) {
    $text = Get-Content $f.FullName -Raw
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
    Check ($errors.Count -eq 0) "$($f.Name): parse errors: $($errors -join '; ')"
    if ($f.Name -eq 'ScriptRunLog.ps1') { continue }

    $notesId = [regex]::Match($text, '(?m)^\s*Chat ID\s+(C\d{3}\.\d{6}T\d{4})').Groups[1].Value
    Check ($notesId -ne '') "$($f.Name): no 'Chat ID' in its .NOTES header"
    Check ($text -match "Initialize-RunLog\s+-ChatId\s+'$([regex]::Escape($notesId))'\s+-ScriptName\s+'$([regex]::Escape($f.Name))'") `
        "$($f.Name): Initialize-RunLog must name itself and its own Chat ID ($notesId)"
    Check ($text -match 'Write-RunLogEntry\s+-Outcome\s+SUCCESS') "$($f.Name): never logs SUCCESS"
    Check ($text -match 'Write-RunLogEntry\s+-Outcome\s+FAILED') "$($f.Name): never logs FAILED"
    Check ($text -notmatch '(?i)\[(string|securestring)\]\s*\$\w*(password|passphrase|secret|token)') `
        "$($f.Name): takes a credential as a parameter (prompt for it instead)"
}

$bash = (Get-Command bash -ErrorAction SilentlyContinue)?.Source
foreach ($f in Get-ChildItem (Join-Path $repo 'server'), (Join-Path $repo 'Scripts') -Filter *.sh) {
    $bytes = [IO.File]::ReadAllBytes($f.FullName)
    Check (-not ($bytes -contains 13)) "$($f.Name): has CR line endings (bash on the server breaks)"
    if ($bash) {
        & $bash -n $f.FullName 2>&1 | Out-Null
        Check ($LASTEXITCODE -eq 0) "$($f.Name): bash -n syntax error"
    }
    $text = Get-Content $f.FullName -Raw
    $m = [regex]::Match($text, 'CHAT_ID=(\S+)')
    if ($m.Success) { Check ($m.Groups[1].Value -eq 'C001.261031T2215') "$($f.Name): CHAT_ID does not match its header" }
}

if ($failures.Count) {
    $failures | ForEach-Object { Write-Host "FAIL  $_" -ForegroundColor Red }
    Write-Host "$($checks - $failures.Count)/$checks passed" -ForegroundColor Red
    exit 1
}
Write-Host "$checks/$checks passed" -ForegroundColor Green
