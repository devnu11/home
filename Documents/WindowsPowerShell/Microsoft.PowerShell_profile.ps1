# Managed by chezmoi. Edit the source: `chezmoi edit $PROFILE`
# Windows PowerShell 5.1 reads its profile from here; load the PowerShell 7
# one so both shells get the same aliases, functions and prompt.
. (Join-Path $PSScriptRoot '..\PowerShell\Microsoft.PowerShell_profile.ps1')
