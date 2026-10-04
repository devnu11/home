# home

Cross-platform dotfiles, managed with [chezmoi](https://chezmoi.io).

Targets macOS (zsh), Linux/WSL (bash), Windows Git Bash, and Windows PowerShell.
Everything machine- or employer-specific stays out of this repo, in local
override files that chezmoi never touches.

## Bootstrap a new machine

Install chezmoi (`brew install chezmoi`, `choco install chezmoi`, or see
[the install docs](https://chezmoi.io/install/)), then:

```sh
chezmoi init --source=~/code/home https://github.com/devnu11/home.git
chezmoi diff      # review before touching the home directory
chezmoi apply
```

`init` prompts once for name, email, and whether the machine is `personal` or
`work`, and writes the answers plus the source path to
`~/.config/chezmoi/chezmoi.toml`. That file is per-machine and is **not** in
this repo.

Run `chezmoi diff` before the first `apply`. chezmoi only warns about
overwriting a file once it has written that file at least one time, so on a
fresh machine it replaces a pre-existing `~/.gitconfig` without asking. Two
things soften that:

- The first apply copies every pre-existing dotfile listed in
  [`.chezmoidata/existing.yaml`](.chezmoidata/existing.yaml) to
  `~/.dotfiles-backup/<time>/` before writing anything.
- A listed target that is a **symlink** (a team-shared `~/.bashrc`, say) is
  never touched. `~/.bash_profile` then loads `~/.shell/bashrc.sh` itself, so
  login shells (ssh, most terminals on macOS) still get the full setup.
  Non-login interactive shells read only the shared `~/.bashrc` and get none
  of it.

## Layout

| Source | Target | Notes |
| --- | --- | --- |
| `dot_gitconfig.tmpl` | `~/.gitconfig` | Identity from init prompts; Windows tool paths behind an OS conditional |
| `dot_shell/env.sh` | `~/.shell/env.sh` | PATH, EDITOR, PAGER, GPG_TTY — every shell, including cron |
| `dot_shell/interactive.sh` | `~/.shell/interactive.sh` | History, aliases, `lsd` — interactive shells only |
| `dot_zshenv` | `~/.zshenv` | Read by every zsh; sources `env.sh` |
| `dot_zprofile` | `~/.zprofile` | Login zsh: re-sources `env.sh` after macOS `path_helper` |
| `dot_zshrc` | `~/.zshrc` | Interactive zsh: `interactive.sh`, then `~/.zshrc.local` |
| `dot_bash_profile` | `~/.bash_profile` | Login bash: `env.sh`, then `.bashrc` (and `.shell/bashrc.sh` if `.bashrc` is shared) |
| `dot_bashrc` | `~/.bashrc` | Sources `.shell/bashrc.sh` |
| `dot_shell/bashrc.sh` | `~/.shell/bashrc.sh` | `env.sh`, then interactive-only config and `~/.bashrc.local` |
| `Documents/PowerShell/Microsoft.PowerShell_profile.ps1.tmpl` | `$PROFILE` | Windows only; aliases, helpers and prompt, see below |
| `Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1` | 5.1's `$PROFILE` | Loads the one above, so Windows PowerShell matches |
| `dot_cmdrc.cmd.tmpl`, `private_dot_config/cmd/` | `~/.cmdrc.cmd`, `~/.config/cmd/` | Windows only; cmd.exe aliases and prompt |
| `AppData/Local/Microsoft/Windows Terminal/Fragments/home/cmd.json` | Terminal fragment | Adds the "Command Prompt (home)" profile |
| `.chezmoidata/aliases.yaml` | — | Aliases shared by bash, zsh, PowerShell and cmd.exe |
| `private_dot_claude/CLAUDE.md` | `~/.claude/CLAUDE.md` | `private_` keeps `~/.claude` at mode 0700 |
| `private_dot_claude/hooks/chezmoi-guard.sh` | `~/.claude/hooks/chezmoi-guard.sh` | Claude Code hook: sessions must ask before `chezmoi apply` and friends; see below |
| `private_dot_claude/modify_settings.json` | `~/.claude/settings.json` | Merges that hook in; Claude Code's own settings are kept |
| `.chezmoiexternal.toml.tmpl` | `~/code/claude-skills` | Clones the Claude skills repo; see below |
| `run_onchange_after_install-handy.{sh,ps1}.tmpl` | — | Installs `handy` onto PATH; see below |
| `run_after_link-claude-skills.{sh,ps1}.tmpl` | — | Links those skills into `~/.claude/skills` |
| `private_dot_config/karabiner/assets/complex_modifications/*.json` | `~/.config/karabiner/…` | macOS only; Karabiner-Elements rules, see below |
| `run_onchange_after_enable-karabiner-rules.sh.tmpl` | — | Turns those rules on in Karabiner's selected profile |

`.chezmoiignore` keeps `README.md` and `handy/` out of `~`, skips the PowerShell
profile off Windows, skips `.zshrc`/`.zprofile`/`.zshenv` on Windows, and leaves
`~/.claude/skills/synced` alone — that bucket is synced from the Anthropic
account and is machine state, not config.

## Why the shell config is split in two

`~/.zshrc` and `~/.bashrc` are only read by *interactive* shells. Anything put
there is invisible to scripts, `ssh host cmd`, and cron — which matters here,
because `handy jira-report` is meant to run from cron.

So environment lives in `env.sh`, sourced from `~/.zshenv` (every zsh) and from
both bash rc files: `PATH` (prepends `~/bin` and `~/.local/bin`, appends
Homebrew), `EDITOR`/
`VISUAL` (nano, else nvim, vim, vi), `PAGER`/`LESS`, and `GPG_TTY` for signed
commits. Aliases, history and other interactive-only settings live in
`interactive.sh`.

`env.sh` removes a PATH entry before adding it, so order survives macOS
`/usr/libexec/path_helper` (which reshuffles PATH in `/etc/zprofile`, after
`~/.zshenv` has run) and entries never pile up in nested shells.

Homebrew goes *after* the system directories, not before them as
`brew shellenv` would put it. The system directories are root-owned and
Homebrew's are user-writable, so a rogue formula or cask could otherwise ship
its own `sudo` or `ssh` and harvest credentials. The cost: where both exist,
the system copy wins (`python3`, `openssl`, `pip3`); reach brew's with
`$HOMEBREW_PREFIX/bin/<tool>`. On Intel Macs Homebrew lives in `/usr/local`,
which macOS's own `/etc/paths` already puts ahead of `/usr/bin`.

### Server watchdog

`interactive.sh` ends with a hook that runs `handy servers start --quiet` in the
background, so each new terminal restarts anything in `~/.config/handy/servers`
that has died (see handy's README, "Servers on hosts you can't run services
on"). It does nothing on machines without handy or that config, never delays the
prompt, skips even starting Python if it ran in the last 10 minutes and the
config hasn't changed since, and logs to `~/.local/state/handy-servers/hook.log`.
`HANDY_SERVERS_DISABLE=1` turns it off.

## Same aliases in every shell

Abbreviations that make sense everywhere (the git ones, `..`, `ll`, `h`, `p`,
...) live once in [`.chezmoidata/aliases.yaml`](.chezmoidata/aliases.yaml).
Add one there and the next apply puts it in bash and zsh (`~/.shell/aliases.sh`),
PowerShell (a function per alias) and cmd.exe (a doskey macro). An entry can
give a different command per shell, or leave a shell out.

- **PowerShell** (7, and 5.1 through a stub) also gets env.sh's PATH, editor
  and pager settings, bash-style history, the `path`, `up`, `mkdirg`/`mcd`,
  `pd`, `extract`, `ftext`, `lsd` and `ssh` helpers, and the same
  `status [user@host:dir]` prompt. Your aliases replace PowerShell's built-in
  ones of the same name (`gc`, `gl`, `gp`, `gcm`, `h`); `rm`, `cp`, `mv`, `ls`
  and `ps` stay PowerShell's, since their Unix versions only add Unix flags.
- **cmd.exe** has no rc file, so a Windows Terminal profile, "Command Prompt
  (home)", runs `cmd /k ~/.cmdrc.cmd`. It is not registered as AutoRun, so
  scripts, build tools and `cmd /c` never load it. Its prompt can't show the
  last exit status or colour by directory.

Unix-only aliases and functions (the `ls`/`find`/`chmod`/`tar` families and so
on) stay in `interactive.sh`.

## Per-machine and corporate overrides

None of these are tracked. Create whichever a machine needs:

| File | Overrides |
| --- | --- |
| `~/.gitconfig.local` | Work email, signing key, proxy, real paths to diff/merge tools. Included last, so it beats anything above it. |
| `~/.bashrc.local`, `~/.zshrc.local` | PATH entries, proxies, work aliases |
| `~/.zprofile.local` | Login-shell setup specific to the machine |
| `local.ps1` beside `$PROFILE` | Same, for PowerShell |
| `~/.cmdrc.local.cmd` | Same, for cmd.exe |
| `~/.claude/CLAUDE.local.md` | Claude instructions that only apply on this machine |

A work laptop typically needs only `~/.gitconfig.local`:

```ini
[user]
	email = dave.evans@example.com
[http]
	proxy = http://proxy.corp.example.com:8080
```

Anything that varies per machine but is *not* secret can instead become a
template variable in `.chezmoi.toml.tmpl` and a `{{ .var }}` in the file.

## Claude Code can't write to `~` unasked

Three layers stop any Claude session, on any machine, from running a chezmoi
command that writes to the home directory without asking:

1. `~/.claude/CLAUDE.md` says so, and requires a full, unfiltered
   `chezmoi diff` and `chezmoi status` before asking.
2. `~/.claude/hooks/chezmoi-guard.sh`, a PreToolUse hook, catches `apply`,
   `update`, `destroy`, `purge` and `init`/`edit --apply`, including wrapped
   forms (`cd ~ && …`, `env … chezmoi`, `sh -c "…"`). In default, acceptEdits
   and plan modes it asks you. Claude Code ignores "ask" in auto and
   bypassPermissions modes, so there it denies, and you run the command
   yourself.
3. `modify_settings.json` registers the hook in `~/.claude/settings.json` by
   merging, since Claude Code rewrites that file. Only the guard's entry is
   replaced; the first apply re-sorts the file's keys.

The hook only sees commands Claude runs directly; layer 1 forbids hiding one
in a script file. `sh tests/claude_guard_test.sh` tests the matcher.

## Packages

`chezmoi apply` installs the packages listed in
[`.chezmoidata/packages.yaml`](.chezmoidata/packages.yaml) with the OS's package
manager: Chocolatey on Windows, Homebrew on macOS, apt on Debian/Ubuntu. Add a
name to a list and the next apply installs it. A missing package manager is a
warning, not an error, and the script reruns once it appears. Removing a name
does not uninstall anything.

Chocolatey needs an elevated shell; from a normal one the install fails and the
next apply retries. `HOME_PACKAGES=skip` turns the step off (the tests use it).

## Karabiner-Elements (macOS)

The `karabiner-elements` cask comes from the package list. Rules live in
`private_dot_config/karabiner/assets/complex_modifications/`, and
`run_onchange_after_enable-karabiner-rules.sh.tmpl` turns each one on in
Karabiner's selected profile. Karabiner rewrites `karabiner.json` from its own
UI, so the script patches that file with `jq` (shipped with macOS) rather than
chezmoi owning it. A rule replaces any rule with the same description, and
rules added in the UI are kept.

To add a rule, drop its JSON in that directory and add its filename to the
`$rules` list at the top of the script.

Shipped rules:

- `windows-app-cmd-tab.json`: in Windows App (Microsoft Remote Desktop),
  Cmd+Tab sends Alt+Tab, and Cmd+Shift+Tab sends Alt+Shift+Tab, so window
  switching happens on the remote machine.

On first install, macOS still needs you to approve Karabiner's system
extension and grant Input Monitoring by hand, in System Settings.

## Windows tools

The Windows branch of `dot_gitconfig.tmpl` points at Chocolatey's default
install locations. Beyond Compare comes from the package list above; Notepad++
does not (yet):

```
choco install notepadplusplus
```

It uses full paths rather than Chocolatey's PATH shims on purpose: shims for GUI
applications return immediately instead of blocking, which breaks git's editor,
difftool and mergetool. For the same reason it uses `BComp.exe`, the variant
that waits, rather than `BCompare.exe`. A machine that installed these somewhere
else overrides the paths in `~/.gitconfig.local`.

## Separate repos

Two things are deliberately their own repos rather than content here, so that
someone who wants only one of them can take just that:

| Repo | What |
| --- | --- |
| [devnu11/handy](https://github.com/devnu11/handy) | Python CLI tools, a git submodule at `handy/` |
| [devnu11/claude-skills](https://github.com/devnu11/claude-skills) | Claude Code skills, a chezmoi external at `~/code/claude-skills` |

The skills repo is an external rather than a submodule on purpose. chezmoi
reinterprets filenames in its source directory — `dot_`, `private_`, `run_`
prefixes — so a submodule there would mangle any repo not written for chezmoi.
An external is cloned verbatim, and needs no `git submodule update --init` at
bootstrap.

### Claude skills

Claude Code reads personal skills from `~/.claude/skills/<name>/`, but that
directory already holds `synced/`, the bucket Anthropic syncs from the account —
and `git clone` refuses a non-empty destination. So the repo is cloned to
`~/code/claude-skills` and `run_after_link-claude-skills` symlinks each skill
into place (directory junctions on Windows, which need no admin rights).

Linking is done by the skills repo's own `install.sh`, so the repo works
standalone and the two paths can't drift. It only touches symlinks pointing
back into that repo, leaving `synced/` and any hand-made skill directory alone,
and it prunes links to skills that have been deleted.

`chezmoi diff` can't show what that will do: it only sees the wrapper, and
`install.sh` lives in `~/code/claude-skills`, outside this repo. Before an
apply, preview the links and any pending pull of the external:

```sh
CLAUDE_SKILLS_DIR=~/.claude/skills ~/code/claude-skills/install.sh --dry-run
git -C ~/code/claude-skills fetch && git -C ~/code/claude-skills log --oneline HEAD..@{u}
```

## handy

`handy/` is a git submodule of a separate Python CLI. `chezmoi apply` installs
its entry points into `~/.local/bin` (which `env.sh` puts on PATH) so
`handy` is runnable from anywhere:

```sh
uv tool install --force --editable ~/code/home/handy
```

The `run_onchange_after_install-handy` scripts do this automatically, and re-run
only when `handy/pyproject.toml` changes. They skip with a message if `uv` isn't
installed or the submodule isn't checked out, so they never fail an `apply`.
Delete them if you'd rather install by hand.

## Day-to-day

```sh
chezmoi edit ~/.gitconfig    # edit the source, not the copy in ~
chezmoi diff                 # what would change
chezmoi apply                # apply it
chezmoi apply --interactive  # confirm each file
chezmoi re-add ~/.bashrc     # pull a change made in ~ back into the source
chezmoi cd                   # drop into the source repo to commit and push
```

Editing a managed file directly in `~` works until the next `chezmoi apply`.
After chezmoi has written a file once, a later `apply` over a hand-edit prompts
before overwriting (and aborts rather than guessing if there's no terminal);
`--force` skips that prompt. Managed files carry a "Managed by chezmoi" header
as a reminder.

## What is deliberately not managed

`~/.claude/settings.json` — Claude Code rewrites it whenever you switch model or
approve a permission, so tracking it means constant drift and a real risk of
`apply` reverting a change Claude Code just made. If you later want new machines
seeded with it without that risk, add it as `create_private_dot_claude/…`:
chezmoi's `create_` prefix writes the file only when it is absent and never
touches it again.

## Tests

`tests/` holds end-to-end checks that bootstrap this repo into a scratch home
and inspect the result. Neither touches your real home directory.

```sh
sh tests/apply_test.sh                 # Linux / macOS
pwsh -File tests/apply_test.ps1        # Windows
```

Both run `chezmoi init` with canned answers, then `apply`, and check the files
that land, the gitconfig values, the claude-skills links (symlinks on Unix,
junctions on Windows), that `handy` is runnable when `uv` is installed, and that
a second `apply` changes nothing. The Unix test also starts bash and zsh as
plain, login and interactive shells and checks `~/.local/bin` heads PATH. The
Windows test additionally drives the junction script through adding, removing
and relinking a skill, loads the profile in both PowerShell 7 and Windows
PowerShell 5.1 and runs `tests/profile_probe.ps1` inside, runs `~/.cmdrc.cmd`
under cmd.exe and checks its macros and prompt, and validates the Terminal
fragment.

They need chezmoi, git, the `handy` submodule, and network access to clone
claude-skills. CI runs them on Ubuntu, macOS and Windows for every push and pull
request.

## License

MIT — see [LICENSE](LICENSE).
