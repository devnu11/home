# End-to-end test of `chezmoi apply` on Windows.
#
# Bootstraps this source directory into a throwaway home the way a new machine
# would (init with canned prompt answers, then apply) and checks what landed.
# Nothing touches the real profile: every per-user location chezmoi, git and
# uv use points into a scratch directory for the whole run.
#
# Needs chezmoi and git on PATH and the handy and claude-skills submodules
# checked out. uv is optional: its check is skipped when absent.
#
#     pwsh -File tests/apply_test.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Src = Split-Path -Parent $PSScriptRoot
$Work = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
$FakeHome = Join-Path $Work 'home'
$SkillsSrc = Join-Path $Src 'private_dot_claude\skills'
$OldClone = Join-Path $Work 'old-clone'
$Skills = Join-Path $FakeHome '.claude\skills'
$script:Failures = [Collections.Generic.List[string]]::new()

# --- expectations -------------------------------------------------------

# Environment variable -> path under the scratch home. chezmoi and git read
# USERPROFILE/HOME; uv resolves its own dirs through the Windows known-folder
# API, which ignores those, so its variables pin it too.
$FakeEnv = [ordered]@{
    USERPROFILE           = ''
    HOME                  = ''
    APPDATA               = 'AppData\Roaming'
    LOCALAPPDATA          = 'AppData\Local'
    UV_TOOL_DIR           = '.local\share\uv\tools'
    UV_TOOL_BIN_DIR       = '.local\bin'
    UV_CACHE_DIR          = '.cache\uv'
    UV_PYTHON_INSTALL_DIR = '.local\share\uv\python'
    UV_PYTHON_BIN_DIR     = '.local\bin'
}

$TerminalFragment = 'AppData\Local\Microsoft\Windows Terminal\Fragments\home\cmd.json'

$Managed = '.gitconfig', '.shell\env.sh', '.shell\aliases.sh', '.shell\lamaison.sh', '.shell\bashrc.sh', '.bashrc', '.bash_profile', '.claude\CLAUDE.md',
           '.claude\hooks\chezmoi-guard.sh', '.claude\settings.json',
           'Documents\PowerShell\Microsoft.PowerShell_profile.ps1',
           'Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1',
           '.cmdrc.cmd', '.config\cmd\aliases.doskey', $TerminalFragment

# zsh files are Unix-only; source-dir furniture never lands in ~.
$Unmanaged = '.zshrc', '.zprofile', '.zshenv', 'README.md', 'LICENSE', 'handy', 'tests', '.github'

# Files of the claude-skills submodule that are not skills.
$SkillsUnmanaged = 'README.md', 'LICENSE', 'install.sh', 'tests', '.github', '.team', '.claude'

# doskey macros ~\.cmdrc.cmd must define (name=expansion), from aliases.yaml.
$CmdMacros = 'gs=git status $*', '..=cd .. $*', 'll=dir $*', 'h=doskey /history $B findstr /i $*'

# PowerShell executable -> the profile it loads, relative to the scratch home.
$ProfileShells = [ordered]@{
    pwsh       = 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1'
    powershell = 'Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
}

# What install-packages must pass to choco (from .chezmoidata/packages.yaml).
$ChocoPackages = 'beyondcompare', 'unxutils', 'notepadplusplus', 'uv', 'nodejs-lts', 'fzf', 'ripgrep'

$GitValues = [ordered]@{
    'user.email'    = 'ci@example.com'
    'core.autocrlf' = 'true'
    'diff.tool'     = 'bc5'
}

# --- helpers ------------------------------------------------------------

function Fail([string]$message) {
    Write-Host "    FAIL $message"
    $script:Failures.Add($message)
}

function Section([string]$title) {
    Write-Host "`n== $title"
}

function Assert-Equal($actual, $expected) {
    if ($actual -ne $expected) { Fail "got '$actual', want '$expected'" }
}

function Enter-FakeHome {
    New-Item -ItemType Directory -Path $FakeHome -Force | Out-Null
    foreach ($name in $FakeEnv.Keys) {
        $relative = $FakeEnv[$name]
        $path = if ($relative) { Join-Path $FakeHome $relative } else { $FakeHome }
        [Environment]::SetEnvironmentVariable($name, $path)
    }
    $env:HOME_PACKAGES = 'skip' # keep install-packages off the real machine
}

function Save-Environment {
    $saved = @{}
    foreach ($name in $FakeEnv.Keys) { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }
    return $saved
}

function Restore-Environment([hashtable]$saved) {
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    Remove-Item Env:HOME_PACKAGES -ErrorAction SilentlyContinue
}

# Run chezmoi against this source with stdin empty, so an unanswered prompt
# errors instead of hanging. Returns combined output; records a non-zero exit.
function Invoke-Chezmoi {
    # chezmoi writes progress to stderr; that is not an error.
    $ErrorActionPreference = 'Continue'
    $out = $null | & chezmoi --source $Src --no-tty @args 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { Fail "chezmoi $($args -join ' '): exit $LASTEXITCODE`n$out" }
    Write-Host $out
    return $out
}

function Get-Entry([string]$path) {
    return Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
}

# Attributes and link type of $path, for failure messages.
function Format-Entry([string]$path) {
    $item = Get-Entry $path
    if (-not $item) { return 'nothing' }
    return "$($item.Attributes), LinkType '$($item.LinkType)'"
}

function Assert-Absent([string]$relative) {
    if (Test-Path -LiteralPath (Join-Path $FakeHome $relative)) { Fail "~\$relative should not exist" }
}

function Assert-File([string]$relative) {
    if (-not (Test-Path -LiteralPath (Join-Path $FakeHome $relative) -PathType Leaf)) { Fail "~\$relative missing" }
}

# Skill folders in the submodule: those holding a SKILL.md.
function Get-SourceSkill {
    Get-ChildItem -Path $SkillsSrc -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') }
}

# ~\.claude\skills\$name must be a copied folder, not a link, matching the submodule.
function Assert-SkillCopied([string]$name) {
    $dest = Join-Path $Skills $name
    $item = Get-Entry $dest
    if (-not $item -or $item.LinkType) { Fail "$dest is not a plain folder (found: $(Format-Entry $dest))"; return }
    $want = Get-Content -Raw (Join-Path (Join-Path $SkillsSrc $name) 'SKILL.md')
    Assert-Equal (Get-Content -Raw (Join-Path $dest 'SKILL.md')) $want
}

# --- steps --------------------------------------------------------------

function Test-Bootstrap {
    Section 'init + first apply'
    # --promptString/--promptChoice key on the prompt text, not the variable.
    Invoke-Chezmoi init `
        --promptString 'Full name for git commits=CI Test' `
        --promptString 'Email address for git commits=ci@example.com' `
        --promptString "Your username (shown as 'me' in the prompt)=ci" `
        --promptString "Usual machine, shown grey in the prompt=ci-host" `
        --promptString "Host for a bare ``ssh`` (blank for none)=" `
        --promptString "printf pattern turning a bare ssh number into a host, e.g. box%02d (blank for none)=" `
        --promptString "Directory shown blue in the prompt (blank for none)=" `
        --promptString "Directory shown cyan in the prompt (blank for none)=" `
        --promptChoice 'Is this a personal or work computer=personal' | Out-Null
    Invoke-Chezmoi apply | Out-Null
}

# A work .gitconfig already in place; the first apply must back it up.
$WorkGitconfig = "[user]`n`temail = me@work.example"

function Initialize-ExistingDotfiles {
    Set-Content -Path (Join-Path $FakeHome '.gitconfig') -Value $WorkGitconfig -NoNewline
    Initialize-OldSkillJunction
}

# A skill junctioned into a separate clone, as the old link script left it.
function Initialize-OldSkillJunction {
    $name = (Get-SourceSkill | Select-Object -First 1).Name
    New-Item -ItemType Directory -Path (Join-Path $OldClone $name), $Skills -Force | Out-Null
    Set-Content -Path (Join-Path (Join-Path $OldClone $name) 'SKILL.md') -Value 'old clone' -NoNewline
    New-Item -ItemType Junction -Path (Join-Path $Skills $name) -Target (Join-Path $OldClone $name) | Out-Null
}

# The first run replaced that junction with a copy and never wrote through it.
function Test-OldSkillJunction {
    Section 'old skill junction replaced'
    $name = (Get-SourceSkill | Select-Object -First 1).Name
    Assert-Equal (Get-Content -Raw (Join-Path (Join-Path $OldClone $name) 'SKILL.md')) 'old clone'
    Assert-SkillCopied $name
}

function Test-Backup {
    Section 'backup of existing dotfiles'
    $copy = Get-ChildItem (Join-Path $FakeHome '.dotfiles-backup\*\.gitconfig') -ErrorAction SilentlyContinue
    if (-not $copy) { Fail 'no backup of .gitconfig'; return }
    Assert-Equal (Get-Content -Raw $copy.FullName) $WorkGitconfig
}

function Test-Targets {
    Section 'targets'
    foreach ($f in $Managed) { Assert-File $f }
    foreach ($f in $Unmanaged) { Assert-Absent $f }
}

function Test-Gitconfig {
    Section 'gitconfig'
    $cfg = Join-Path $FakeHome '.gitconfig'
    foreach ($key in $GitValues.Keys) {
        Assert-Equal "$key=$(git config -f $cfg $key)" "$key=$($GitValues[$key])"
    }
}

# Every skill in the submodule is copied; the submodule's furniture is not.
function Test-Skills {
    Section 'claude-skills'
    # Not $skills: PowerShell names are case-insensitive and dynamically scoped,
    # so that would shadow $Skills inside Assert-SkillCopied.
    $found = @(Get-SourceSkill)
    if ($found.Count -eq 0) { Fail 'no skills in the submodule (git submodule update --init)' }
    foreach ($skill in $found) { Assert-SkillCopied $skill.Name }
    foreach ($f in $SkillsUnmanaged) { Assert-Absent ".claude\skills\$f" }
}

function Test-Idempotent {
    Section 'second apply'
    $out = Invoke-Chezmoi apply
    # run_onchange_ scripts must not re-run when nothing they hash changed.
    if ($out -match 'handy: installing') { Fail 'install-handy re-ran on an unchanged source' }
    # run_after_ scripts always count as pending, so compare files only.
    Invoke-Chezmoi verify --exclude scripts | Out-Null
}

# install-packages must render as valid PowerShell that installs every package.
function Test-Packages {
    Section 'packages'
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) { Write-Host '    skip: choco not installed'; return }
    $template = Get-Content -Raw (Join-Path $Src 'run_onchange_after_install-packages.ps1.tmpl')
    $script = Invoke-Chezmoi execute-template $template
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseInput($script, [ref]$null, [ref]$errors) | Out-Null
    if ($errors) { Fail "install-packages does not parse: $errors" }
    foreach ($pkg in $ChocoPackages) { if ($script -notmatch "'$pkg'") { Fail "install-packages does not install $pkg" } }
}

function Test-Handy {
    Section 'handy'
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) { Write-Host '    skip: uv not installed'; return }
    $exe = Join-Path $FakeHome '.local\bin\handy.exe'
    if (-not (Test-Path $exe)) { Fail "handy not installed to $exe"; return }
    & $exe --help | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "handy --help: exit $LASTEXITCODE" }
}

# Load the applied profile in each PowerShell, as a real session would, and run
# tests\profile_probe.ps1 inside it.
function Test-PowerShellProfile {
    Section 'PowerShell profiles'
    foreach ($shell in $ProfileShells.Keys) {
        if (-not (Get-Command $shell -ErrorAction SilentlyContinue)) { Write-Host "    skip: $shell not installed"; continue }
        $profilePath = Join-Path $FakeHome $ProfileShells[$shell]
        $probe = ". '$profilePath'; . '$(Join-Path $PSScriptRoot 'profile_probe.ps1')'"
        & $shell -NoLogo -NoProfile -NonInteractive -Command $probe
        if ($LASTEXITCODE -ne 0) { Fail "${shell}: $LASTEXITCODE profile check(s) failed" }
    }
}

# ~\.cmdrc.cmd must run cleanly under cmd and leave the macros and prompt set.
# (Macros only expand at an interactive prompt, so they are listed, not run.)
function Test-CmdRc {
    Section 'cmd.exe rc file'
    $rc = Join-Path $FakeHome '.cmdrc.cmd'
    $out = cmd /d /c "call `"$rc`" && doskey /macros && set PROMPT" 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { Fail "cmdrc: exit $LASTEXITCODE`n$out" }
    foreach ($macro in $CmdMacros) { if (-not $out.Contains($macro)) { Fail "cmdrc: macro '$macro' missing" } }
    if ($out -notmatch 'PROMPT=.*\$P') { Fail "cmdrc: PROMPT not set`n$out" }
}

# The Terminal fragment must be valid JSON that launches cmd with the rc file.
function Test-TerminalFragment {
    Section 'Windows Terminal fragment'
    $entry = (Get-Content -Raw (Join-Path $FakeHome $TerminalFragment) | ConvertFrom-Json).profiles[0]
    if ($entry.commandline -notmatch '/k .*\.cmdrc\.cmd') { Fail "fragment commandline: $($entry.commandline)" }
}

# --- main ---------------------------------------------------------------

$Steps = 'Initialize-ExistingDotfiles', 'Test-Bootstrap', 'Test-Backup', 'Test-Targets', 'Test-Gitconfig', 'Test-Skills',
         'Test-OldSkillJunction', 'Test-Packages', 'Test-Handy', 'Test-PowerShellProfile', 'Test-CmdRc', 'Test-TerminalFragment',
         'Test-Idempotent', 'Test-Skills'

$saved = Save-Environment
try {
    Enter-FakeHome
    foreach ($step in $Steps) { & $step }
} catch {
    Fail "unexpected error: $_"
} finally {
    Restore-Environment $saved
    # rmdir /s does not follow junctions, so nothing outside $Work is touched.
    cmd /c rmdir /s /q "$Work" 2>$null
}

if ($script:Failures.Count -gt 0) {
    Write-Host "`n$($script:Failures.Count) failure(s)"
    exit 1
}
Write-Host "`nall checks passed"
