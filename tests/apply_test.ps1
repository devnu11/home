# End-to-end test of `chezmoi apply` on Windows.
#
# Bootstraps this source directory into a throwaway home the way a new machine
# would (init with canned prompt answers, then apply), checks what landed, then
# drives the claude-skills junction script through add, remove, relink and
# skip. Nothing touches the real profile: every per-user location chezmoi, git
# and uv use points into a scratch directory for the whole run.
#
# Needs chezmoi and git on PATH, the handy submodule checked out, and network
# access (the claude-skills external is cloned from GitHub). uv is optional:
# its check is skipped when absent.
#
#     pwsh -File tests/apply_test.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Src = Split-Path -Parent $PSScriptRoot
$Work = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
$FakeHome = Join-Path $Work 'home'
$Clone = Join-Path $FakeHome 'code\claude-skills'
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

$Managed = '.gitconfig', '.shell\env.sh', '.shell\lamaison.sh', '.shell\bashrc.sh', '.bashrc', '.bash_profile', '.claude\CLAUDE.md',
           'Documents\PowerShell\Microsoft.PowerShell_profile.ps1'

# zsh files are Unix-only; source-dir furniture never lands in ~.
$Unmanaged = '.zshrc', '.zprofile', '.zshenv', 'README.md', 'LICENSE', 'handy', 'tests', '.github'

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

# Fail unless the apply output $out matches $pattern.
function Assert-Reported([string]$out, [string]$pattern) {
    if ($out -notmatch $pattern) { Fail "output lacks /$pattern/" }
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

function Get-JunctionTarget([string]$path) {
    $item = Get-Entry $path
    if (-not $item -or $item.LinkType -ne 'Junction') { return $null }
    return [IO.Path]::GetFullPath(@($item.Target)[0]).TrimEnd('\')
}

function Assert-Junction([string]$name) {
    $link = Join-Path $Skills $name
    $got = Get-JunctionTarget $link
    if (-not $got) { Fail "$link is not a junction (found: $(Format-Entry $link))"; return }
    Assert-Equal $got ([IO.Path]::GetFullPath((Join-Path $Clone $name)))
}

function Assert-Absent([string]$relative) {
    if (Test-Path -LiteralPath (Join-Path $FakeHome $relative)) { Fail "~\$relative should not exist" }
}

function Assert-File([string]$relative) {
    if (-not (Test-Path -LiteralPath (Join-Path $FakeHome $relative) -PathType Leaf)) { Fail "~\$relative missing" }
}

# Skill directories in the claude-skills clone: those holding a SKILL.md.
function Get-RepoSkill {
    Get-ChildItem -Path $Clone -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') }
}

function New-Skill([string]$root, [string]$name) {
    $dir = Join-Path $root $name
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Set-Content -Path (Join-Path $dir 'SKILL.md') -Value "---`nname: $name`n---"
}

# A hand-made directory at ~\.claude\skills\$name, holding one file.
function New-Blocker([string]$name) {
    $blocker = Join-Path $Skills $name
    New-Item -ItemType Directory -Path $blocker | Out-Null
    Set-Content -Path (Join-Path $blocker 'mine.txt') -Value 'hand-made'
    return $blocker
}

# Repoint the junction for $name at a decoy skill; returns the decoy's path.
function Set-JunctionElsewhere([string]$name) {
    New-Skill $Work 'elsewhere'
    $link = Join-Path $Skills $name
    [IO.Directory]::Delete($link, $false)
    New-Item -ItemType Junction -Path $link -Target (Join-Path $Work 'elsewhere') | Out-Null
    return Join-Path $Work 'elsewhere'
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
        --promptChoice 'Machine profile=personal' | Out-Null
    Invoke-Chezmoi apply | Out-Null
}

# A work .gitconfig already in place; the first apply must back it up.
$WorkGitconfig = "[user]`n`temail = me@work.example"

function Initialize-ExistingDotfiles {
    Set-Content -Path (Join-Path $FakeHome '.gitconfig') -Value $WorkGitconfig -NoNewline
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

# The commit .chezmoidata/claude-skills.yaml pins.
function Get-SkillsPin {
    $line = Select-String -Path (Join-Path $Src '.chezmoidata\claude-skills.yaml') -Pattern '^\s*commit:\s*(\S+)'
    return $line.Matches[0].Groups[1].Value
}

function Test-SkillJunctions {
    Section 'claude-skills junctions'
    if (-not (Test-Path $Clone)) { Fail 'external not cloned to ~\code\claude-skills'; return }
    Assert-Equal "pin: $(git -C $Clone rev-parse HEAD)" "pin: $(Get-SkillsPin)"
    # Not $skills: PowerShell names are case-insensitive and dynamically scoped,
    # so that would shadow $Skills inside Assert-Junction.
    $found = @(Get-RepoSkill)
    if ($found.Count -eq 0) { Fail 'no skills found in the claude-skills clone' }
    foreach ($skill in $found) { Assert-Junction $skill.Name }
}

function Test-Idempotent {
    Section 'second apply'
    $out = Invoke-Chezmoi apply
    # run_onchange_ scripts must not re-run when nothing they hash changed.
    if ($out -match 'handy: installing') { Fail 'install-handy re-ran on an unchanged source' }
    if ($out -match '(?m)^(link|relink|prune) ') { Fail 'junction script changed something on a re-run' }
    # run_after_ scripts always count as pending, so compare files only.
    Invoke-Chezmoi verify --exclude scripts | Out-Null
}

function Test-AddSkill {
    Section 'add a skill'
    New-Skill $Clone 'zz-ci-added'
    Invoke-Chezmoi apply | Out-Null
    Assert-Junction 'zz-ci-added'
}

function Test-PruneSkill {
    Section 'remove that skill'
    Remove-Item -Recurse -Force (Join-Path $Clone 'zz-ci-added')
    Assert-Reported (Invoke-Chezmoi apply) 'prune\s+zz-ci-added'
    Assert-Absent '.claude\skills\zz-ci-added'
}

function Test-Relink {
    Section 'relink a junction pointing elsewhere'
    $name = (Get-RepoSkill | Select-Object -First 1).Name
    $elsewhere = Set-JunctionElsewhere $name
    Assert-Reported (Invoke-Chezmoi apply) "relink\s+$name"
    Assert-Junction $name
    if (-not (Test-Path (Join-Path $elsewhere 'SKILL.md'))) { Fail 'relink damaged the old target' }
}

function Test-SkipRealDirectory {
    Section 'leave a real directory in the way alone'
    New-Skill $Clone 'zz-ci-blocked'
    $blocker = New-Blocker 'zz-ci-blocked'
    Assert-Reported (Invoke-Chezmoi apply) 'SKIP\s+zz-ci-blocked'
    if ((Get-Entry $blocker).LinkType) { Fail 'real directory was replaced by a link' }
    if (-not (Test-Path (Join-Path $blocker 'mine.txt'))) { Fail 'real directory contents lost' }
    Remove-Item -Recurse -Force (Join-Path $Clone 'zz-ci-blocked'), $blocker
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

function Test-PowerShellProfile {
    Section 'PowerShell profile'
    $profilePath = Join-Path $FakeHome 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1'
    $probe = ". '$profilePath'; " +
             "foreach (`$c in 'g', 'gs', 'gc', 'mkcd', 'up', 'path') { if (-not (Get-Command `$c -ErrorAction SilentlyContinue)) { exit 1 } }; " +
             "if (-not (prompt)) { exit 2 }; " +
             "if ((Get-Command gc).CommandType -ne 'Function') { exit 3 }"
    & pwsh -NoProfile -NonInteractive -Command $probe
    if ($LASTEXITCODE -ne 0) { Fail "profile failed to load: exit $LASTEXITCODE" }
}

# --- main ---------------------------------------------------------------

$Steps = 'Initialize-ExistingDotfiles', 'Test-Bootstrap', 'Test-Backup', 'Test-Targets', 'Test-Gitconfig', 'Test-SkillJunctions',
         'Test-Packages', 'Test-Handy', 'Test-PowerShellProfile', 'Test-Idempotent', 'Test-SkillJunctions',
         'Test-AddSkill', 'Test-PruneSkill', 'Test-Relink', 'Test-SkipRealDirectory'

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
