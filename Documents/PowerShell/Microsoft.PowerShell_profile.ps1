# Managed by chezmoi. Edit the source: `chezmoi edit $PROFILE`
# Windows only — see .chezmoiignore.

# --- PATH ---------------------------------------------------------------
# Where `uv tool install` puts entry points, so `handy` is invocable.
$localBin = Join-Path $HOME '.local\bin'
if ((Test-Path $localBin) -and ($env:PATH -notlike "*$localBin*")) {
    $env:PATH = "$localBin;$env:PATH"
}

Set-Alias -Name g -Value git

function ll { Get-ChildItem @args }
function la { Get-ChildItem -Force @args }

# List subdirectories by total size, largest first.
function lsd {
    Get-ChildItem -Directory | ForEach-Object {
        $bytes = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue |
                  Measure-Object -Property Length -Sum).Sum
        [pscustomobject]@{
            Size = '{0,8:N1} MB' -f ($bytes / 1MB)
            Name = $_.Name
        }
    } | Sort-Object { [double]($_.Size -replace '[^\d.]') } -Descending
}

# Machine-local additions. Not tracked in the dotfiles repo.
$localProfile = Join-Path (Split-Path $PROFILE) 'local.ps1'
if (Test-Path $localProfile) { . $localProfile }
