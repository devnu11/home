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
overwriting a file once it has written that file at least one time — on a fresh
machine it will replace a pre-existing `~/.gitconfig` silently.

## Layout

| Source | Target | Notes |
| --- | --- | --- |
| `dot_gitconfig.tmpl` | `~/.gitconfig` | Identity from init prompts; Windows tool paths behind an OS conditional |
| `dot_shell/env.sh` | `~/.shell/env.sh` | PATH, EDITOR, PAGER, GPG_TTY — every shell, including cron |
| `dot_shell/interactive.sh` | `~/.shell/interactive.sh` | History, aliases, `lsd` — interactive shells only |
| `dot_zshenv` | `~/.zshenv` | Read by every zsh; sources `env.sh` |
| `dot_zprofile` | `~/.zprofile` | Login zsh: Homebrew (Apple Silicon/Intel/Linux), then re-sources `env.sh` |
| `dot_zshrc` | `~/.zshrc` | Interactive zsh: `interactive.sh`, then `~/.zshrc.local` |
| `dot_bash_profile` | `~/.bash_profile` | Login bash: `env.sh`, then `.bashrc` |
| `dot_bashrc` | `~/.bashrc` | `env.sh`, then interactive-only config and `~/.bashrc.local` |
| `Documents/PowerShell/Microsoft.PowerShell_profile.ps1` | `$PROFILE` | Windows only |
| `private_dot_claude/CLAUDE.md` | `~/.claude/CLAUDE.md` | `private_` keeps `~/.claude` at mode 0700 |
| `.chezmoiexternal.toml.tmpl` | `~/code/claude-skills` | Clones the Claude skills repo; see below |
| `run_onchange_after_install-handy.{sh,ps1}.tmpl` | — | Installs `handy` onto PATH; see below |
| `run_after_link-claude-skills.{sh,ps1}.tmpl` | — | Links those skills into `~/.claude/skills` |

`.chezmoiignore` keeps `README.md` and `handy/` out of `~`, skips the PowerShell
profile off Windows, skips `.zshrc`/`.zprofile`/`.zshenv` on Windows, and leaves
`~/.claude/skills/synced` alone — that bucket is synced from the Anthropic
account and is machine state, not config.

## Why the shell config is split in two

`~/.zshrc` and `~/.bashrc` are only read by *interactive* shells. Anything put
there is invisible to scripts, `ssh host cmd`, and cron — which matters here,
because `handy jira-report` is meant to run from cron.

So environment lives in `env.sh`, sourced from `~/.zshenv` (every zsh) and from
both bash rc files: `PATH` (prepends `~/bin` and `~/.local/bin`), `EDITOR`/
`VISUAL` (nano, else nvim, vim, vi), `PAGER`/`LESS`, and `GPG_TTY` for signed
commits. Aliases, history and other interactive-only settings live in
`interactive.sh`.

`env.sh` removes a PATH entry before prepending it, so order survives macOS
`/usr/libexec/path_helper` (which reshuffles PATH in `/etc/zprofile`, after
`~/.zshenv` has run) and entries never pile up in nested shells.

### Server watchdog

`interactive.sh` ends with a hook that runs `handy servers start --quiet` in the
background, so each new terminal restarts anything in `~/.config/handy/servers`
that has died (see handy's README, "Servers on hosts you can't run services
on"). It does nothing on machines without handy or that config, never delays the
prompt, skips even starting Python if it ran in the last 10 minutes and the
config hasn't changed since, and logs to `~/.local/state/handy-servers/hook.log`.
`HANDY_SERVERS_DISABLE=1` turns it off.

## Per-machine and corporate overrides

None of these are tracked. Create whichever a machine needs:

| File | Overrides |
| --- | --- |
| `~/.gitconfig.local` | Work email, signing key, proxy, real paths to diff/merge tools. Included last, so it beats anything above it. |
| `~/.bashrc.local`, `~/.zshrc.local` | PATH entries, proxies, work aliases |
| `~/.zprofile.local` | Login-shell setup specific to the machine |
| `local.ps1` beside `$PROFILE` | Same, for PowerShell |
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

## Windows tools

The Windows branch of `dot_gitconfig.tmpl` points at Chocolatey's default
install locations:

```
choco install notepadplusplus beyondcompare
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

## handy

`handy/` is a git submodule of a separate Python CLI. `chezmoi apply` installs
its entry points into `~/.local/bin` (which `common.sh` puts on PATH) so
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

## License

MIT — see [LICENSE](LICENSE).
