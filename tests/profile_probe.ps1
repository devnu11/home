# Checks the applied PowerShell profile from inside a shell that has loaded it.
# Run by apply_test.ps1 in PowerShell 7 and Windows PowerShell 5.1, dot-sourced
# right after the profile at global scope, as a real session would load it:
#
#     pwsh -NoProfile -Command ". '<profile>'; . 'tests/profile_probe.ps1'"
#
# Prints each failure and exits with the number of failures.
# Windows PowerShell 5.1 syntax only.

$ProbeFailures = @()

function Check([string]$what, [scriptblock]$test) {
    try { $ok = & $test } catch { $ok = $false; $what = "$what ($_)" }
    if (-not $ok) { $script:ProbeFailures += $what }
}

function New-ProbeDir {
    Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
}

Check 'gs is a function' { (Get-Command gs).CommandType -eq 'Function' }
Check 'gc beats the built-in Get-Content alias' { (Get-Command gc).CommandType -eq 'Function' }
Check 'h beats the built-in Get-History alias' { (Get-Command h).CommandType -eq 'Function' }
Check '.. is a function' { (Get-Command ..).CommandType -eq 'Function' }
Check 'which finds git' { (which git) -like '*git*' }
Check 'lt sorts oldest first' { $items = @(lt $env:SystemRoot); $items[0].LastWriteTime -le $items[-1].LastWriteTime }
Check 'lk sorts smallest first' { $items = @(lk $env:SystemRoot -File); $items[0].Length -le $items[-1].Length }
Check 'rm is still the built-in' { (Get-Command rm).CommandType -eq 'Alias' }

Check '.. goes up one directory' {
    $dir = New-ProbeDir
    New-Item -ItemType Directory -Path $dir | Out-Null
    Set-Location $dir; ..
    (Get-Location).ProviderPath -eq (Split-Path $dir)
}

Check 'mkdirg creates nested directories and enters them' {
    $dir = Join-Path (New-ProbeDir) 'a\b'
    mkdirg $dir
    (Get-Location).ProviderPath -eq $dir
}

Check 'up 2 goes up two directories' {
    $here = (Get-Location).ProviderPath
    up 2
    (Get-Location).ProviderPath -eq (Split-Path (Split-Path $here))
}

Check 'pd runs a command in a directory and comes back' {
    $here = (Get-Location).ProviderPath
    $there = (pd $env:SystemRoot Get-Location).ProviderPath
    $there -eq $env:SystemRoot -and (Get-Location).ProviderPath -eq $here
}

Check 'path lists one entry per line' { @(path).Count -gt 1 -and -not (@(path) -match ';') }

Check 'a bare ssh number becomes a host' {
    $script:LamaisonSshHostExpression = 'box%02d'
    (Format-SshHost '7') -eq 'box07'
}

Check 'the prompt renders status and [user@host:dir]' {
    $text = prompt
    $text -match '000' -and $text -match '\[' -and $text -match '\] $'
}

Check 'the prompt shows a failed exit code' {
    cmd /c exit 3
    $text = prompt
    $text -match '003'
}

foreach ($failure in $ProbeFailures) { Write-Host "    FAIL $failure" }
exit $ProbeFailures.Count
