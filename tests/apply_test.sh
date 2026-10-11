#!/bin/sh
# End-to-end test of `chezmoi apply` on Linux and macOS.
#
# Bootstraps this source directory into a throwaway HOME the way a new machine
# would (init with canned prompt answers, then apply), checks what landed, and
# checks that a second apply changes nothing. Nothing touches the real home:
# HOME points at a scratch directory for every command, so chezmoi's config and
# state, and anything `uv tool install` writes, land there.
#
# Needs chezmoi and git on PATH and the handy and claude-skills submodules
# checked out. zsh and uv are optional: their checks are skipped when absent.
#
#     sh tests/apply_test.sh

# Messages say ~/ literally on purpose (SC2088); shell probes are single-quoted
# so the child shell expands them (SC2016).
# shellcheck disable=SC2088,SC2016

set -u

SRC=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d) || exit 1 # an empty WORK would make FAKE_HOME a real path
FAKE_HOME="$WORK/home"
FAILURES="$WORK/failures"
trap 'rm -rf "$WORK"' EXIT
# dash skips the EXIT trap on a signal; exiting from the handler runs it.
trap 'exit 130' INT TERM
mkdir -p "$FAKE_HOME"

# --- helpers ------------------------------------------------------------

fail() {
	printf '    FAIL %s\n' "$*" | tee -a "$FAILURES" >&2
}

section() {
	printf '\n== %s\n' "$*"
}

# Run a command with HOME (and nothing else) pointing at the scratch home.
in_home() {
	# uv's own overrides beat HOME, so drop them too or a local run would
	# overwrite the developer's real handy install. HOME_PACKAGES=skip keeps
	# install-packages off the real machine.
	env -u XDG_CONFIG_HOME -u XDG_DATA_HOME -u XDG_STATE_HOME -u XDG_CACHE_HOME \
		-u XDG_BIN_HOME -u UV_TOOL_DIR -u UV_TOOL_BIN_DIR \
		-u UV_PYTHON_INSTALL_DIR -u UV_PYTHON_BIN_DIR \
		-u BASH_ENV -u ENV HOME="$FAKE_HOME" HOME_PACKAGES=skip "$@"
}

chez() {
	# stdin closed so a prompt the test failed to answer errors, not hangs.
	in_home chezmoi --source "$SRC" --no-tty "$@" </dev/null
}

assert_file() {
	[ -f "$FAKE_HOME/$1" ] || fail "~/$1 missing"
}

assert_absent() {
	[ ! -e "$FAKE_HOME/$1" ] || fail "~/$1 should not exist"
}

assert_eq() {
	[ "$1" = "$2" ] || fail "got '$1', want '$2'"
}

# Succeed if $1 is on PATH; otherwise say the check is skipped.
have() {
	command -v "$1" >/dev/null 2>&1 && return
	echo "    skip: $1 not installed"
	return 1
}

# --- expectations -------------------------------------------------------

MANAGED='.gitconfig .shell/env.sh .shell/interactive.sh .shell/aliases.sh .shell/lamaison.sh .shell/bashrc.sh .bashrc .bash_profile
.zshenv .zprofile .zshrc .claude/CLAUDE.md .claude/hooks/chezmoi-guard.sh .claude/settings.json'

# Source-dir furniture and Windows-only files stay out of ~.
UNMANAGED='my.bashrc README.md LICENSE handy tests .github Documents .cmdrc.cmd .config/cmd AppData'

# The claude-skills submodule, and the files of it that are not skills.
SKILLS_SRC="$SRC/private_dot_claude/skills"
SKILLS_UNMANAGED='README.md LICENSE install.sh tests .github .team .claude'

# key=value pairs the Unix gitconfig must hold.
GIT_VALUES='user.name=CI Test
user.email=ci@example.com
core.autocrlf=input'

# Claude Code's own settings, which modify_settings.json must keep.
SEED_SETTINGS='{"model": "opus", "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "say done"}]}]}}'

# --- steps --------------------------------------------------------------

# ~/.claude/settings.json as Claude Code would have left it before chezmoi.
seed_claude_settings() {
	mkdir -p "$FAKE_HOME/.claude"
	printf '%s\n' "$SEED_SETTINGS" >"$FAKE_HOME/.claude/settings.json"
}

bootstrap() {
	section "init + first apply"
	chez_init \
		--promptChoice 'Is this a personal or work computer=personal' \
		--promptString 'Email address for git commits=ci@example.com'
	chez apply || fail "first apply: exit $?"
}

# `chezmoi init` with the prompts every profile shares answered; $@ adds more.
chez_init() {
	# --promptString/--promptChoice key on the prompt text, not the variable.
	chez init \
		--promptString 'Full name for git commits=CI Test' \
		--promptString "Your username (shown as 'me' in the prompt)=ci" \
		--promptString "Usual machine, shown grey in the prompt=ci-host" \
		--promptString "Host for a bare \`ssh\` (blank for none)=" \
		--promptString "printf pattern turning a bare ssh number into a host, e.g. box%02d (blank for none)=" \
		--promptString "Directory shown blue in the prompt (blank for none)=" \
		--promptString "Directory shown cyan in the prompt (blank for none)=" \
		"$@" || fail "init: exit $?"
}

check_targets() {
	section "targets"
	for f in $MANAGED; do assert_file "$f"; done
	for f in $UNMANAGED; do assert_absent "$f"; done
	for dir in .claude .config; do assert_private_dir "$dir"; done
}

# ~/$1 must be mode 0700: nobody else may list or traverse it.
assert_private_dir() {
	[ -d "$FAKE_HOME/$1" ] || return 0
	case "$(ls -ld "$FAKE_HOME/$1")" in
		drwx------*) ;;
		*) fail "~/$1 is not mode 0700" ;;
	esac
}

check_gitconfig() {
	section "gitconfig"
	echo "$GIT_VALUES" | while IFS='=' read -r key want; do
		assert_eq "$key=$(git config -f "$FAKE_HOME/.gitconfig" "$key")" "$key=$want"
	done
	[ -z "$(git config -f "$FAKE_HOME/.gitconfig" diff.tool)" ] || fail "Windows diff.tool leaked into Unix gitconfig"
}

# Skills from the submodule: each folder holding a SKILL.md lands in
# ~/.claude/skills as a real folder; the submodule's own furniture does not.
check_skills() {
	section "claude-skills"
	set -- "$SKILLS_SRC"/*/SKILL.md
	[ -f "$1" ] || { fail "no skills in the submodule (git submodule update --init)"; return; }
	for manifest; do check_skill "${manifest%/SKILL.md}"; done
	for f in $SKILLS_UNMANAGED; do assert_absent ".claude/skills/$f"; done
	check_no_dropped_empty_files
}

# chezmoi never creates an empty file, so one inside a copied folder would go
# missing without a word. Each must sit in a folder .chezmoiignore leaves out.
check_no_dropped_empty_files() {
	git -C "$SKILLS_SRC" ls-files | while read -r f; do
		[ -s "$SKILLS_SRC/$f" ] || [ ! -d "$FAKE_HOME/.claude/skills/${f%/*}" ] ||
			fail "empty skills file $f is skipped; ignore its folder or give it content"
	done
}

# Skill folder $1 of the submodule must be copied, not linked, into ~.
check_skill() {
	dest="$FAKE_HOME/.claude/skills/${1##*/}"
	[ ! -L "$dest" ] || { fail "$dest is a symlink"; return; }
	cmp -s "$1/SKILL.md" "$dest/SKILL.md" || fail "$dest/SKILL.md differs from the submodule"
}

# An edited skill file shows up in `chezmoi diff`, line by line.
check_skills_in_diff() {
	section "claude-skills in chezmoi diff"
	set -- "$SKILLS_SRC"/*/SKILL.md
	name=${1%/SKILL.md} name=${name##*/}
	echo 'local edit' >>"$FAKE_HOME/.claude/skills/$name/SKILL.md"
	chez diff --no-pager | grep -q '^-local edit' ||
		fail "diff does not show the edit to $name/SKILL.md"
	cp "$1" "$FAKE_HOME/.claude/skills/$name/SKILL.md"
}

# install-packages must render as valid sh that installs this OS's packages.
check_packages() {
	section "packages"
	# chez closes stdin, so the template goes in as an argument.
	script=$(chez execute-template "$(cat "$SRC/run_onchange_after_install-packages.sh.tmpl")") ||
		{ fail "render: exit $?"; return; }
	printf '%s' "$script" | grep -q HOME_PACKAGES || fail "install-packages rendered empty"
	printf '%s\n' "$script" | sh -n || fail "install-packages is not valid sh"
	for pkg in $(expected_packages); do
		printf '%s' "$script" | grep -q "\"$pkg\"" || fail "install-packages does not install $pkg"
	done
}

# Packages from .chezmoidata/packages.yaml this OS's script must name.
# Empty where the package manager is missing: the script then only warns.
expected_packages() {
	case "$(uname -s)" in
		Darwin) command -v brew >/dev/null 2>&1 && echo uv node fzf ripgrep beyond-compare karabiner-elements ;;
		Linux) command -v apt-get >/dev/null 2>&1 && echo fzf ripgrep ;;
	esac
}

KARABINER_RULE='Cmd+Tab sends Alt+Tab when Windows App is frontmost'

# On macOS the shipped rule is enabled in karabiner.json exactly once;
# elsewhere nothing of Karabiner's lands.
# The guard hook is registered exactly once and the seeded settings survive.
check_claude_settings() {
	section "claude settings"
	settings="$FAKE_HOME/.claude/settings.json"
	assert_eq "guard entries: $(grep -c 'chezmoi-guard.sh' "$settings")" "guard entries: 1"
	grep -q '"model": "opus"' "$settings" || fail "settings.json lost the seeded model"
	grep -q '"say done"' "$settings" || fail "settings.json lost the seeded Stop hook"
}

check_karabiner() {
	section "karabiner"
	if [ "$(uname -s)" != Darwin ]; then
		assert_absent .config/karabiner
		return
	fi
	have jq || return 0
	assert_eq "rule enabled $(karabiner_rule_count) time(s)" "rule enabled 1 time(s)"
}

karabiner_rule_count() {
	jq --arg d "$KARABINER_RULE" \
		'[.profiles[].complex_modifications.rules[]? | select(.description == $d)] | length' \
		"$FAKE_HOME/.config/karabiner/karabiner.json"
}

check_handy() {
	section "handy"
	have uv || return 0
	in_home "$FAKE_HOME/.local/bin/handy" --help >/dev/null || fail "handy not runnable from ~/.local/bin"
}

# Every login and interactive shell must start cleanly and put ~/.local/bin
# first on PATH. (Plain non-interactive bash reads no rc file.)
check_shell() {
	section "$1 startup"
	have "$1" || return 0
	mkdir -p "$FAKE_HOME/.local/bin"
	for mode in -c -lc -ic; do
		[ "$1 $mode" = "bash -c" ] && continue
		assert_eq "$1 $mode: $(path_head "$1" "$mode")" "$1 $mode: $FAKE_HOME/.local/bin"
	done
}

# Homebrew must come after /usr/bin so it can never shadow sudo and friends.
check_brew_after_system() {
	section "homebrew after system dirs"
	[ -d /opt/homebrew/bin ] || { echo "    skip: no /opt/homebrew"; return 0; }
	have zsh || return 0
	order=$(in_home PATH=/usr/bin:/bin zsh -lc 'print -l $path' </dev/null |
		grep -nx -e /usr/bin -e /opt/homebrew/bin | cut -d: -f2 | paste -sd' ' -)
	assert_eq "$order" "/usr/bin /opt/homebrew/bin"
}

# First PATH entry seen by shell $1 started with flags $2.
path_head() {
	path=$(in_home PATH=/usr/bin:/bin "$1" "$2" 'printf %s "$PATH"' 2>"$WORK/stderr" </dev/null) ||
		fail "$1 $2: exit $?: $(cat "$WORK/stderr")"
	echo "${path%%:*}"
}

check_idempotent() {
	section "second apply"
	chez apply >"$WORK/apply2" 2>&1 || fail "second apply: exit $?: $(cat "$WORK/apply2")"
	cat "$WORK/apply2"
	check_no_script_acted "$WORK/apply2"
	# run_after_ scripts always count as pending, so compare files only.
	chez verify --exclude scripts || fail "verify: files differ after a second apply"
	pending=$(chez diff --exclude scripts) || fail "diff: exit $?"
	[ -z "$pending" ] || fail "diff not empty after a second apply"
}

# Apply output $1 must show no script doing work: run_onchange_ scripts
# re-run only when what they hash changes, and links are already in place.
check_no_script_acted() {
	! grep -q 'handy: installing' "$1" || fail "install-handy re-ran on an unchanged source"
	! grep -q 'karabiner: enabled' "$1" || fail "enable-karabiner-rules re-ran on unchanged rules"
}

# A machine with dotfiles already: a team-shared ~/.bashrc symlink, a work
# ~/.gitconfig, a ~/.profile that login bash must still read, and a skill
# symlinked into another clone, as the old install.sh linking left them. Run in
# a second scratch home so the checks above still see a clean machine.
check_existing_home() {
	section "existing dotfiles"
	FAKE_HOME="$WORK/existing"
	seed_existing_home
	bootstrap
	check_shared_bashrc
	check_backup .gitconfig "$WORK_GITCONFIG"
	check_old_skill_link
	assert_eq "~/.profile: $(in_home bash -lc 'echo "${WORK_PROFILE:-unread}"' </dev/null)" "~/.profile: read"
	assert_eq "bash -lc: $(path_head bash -lc)" "bash -lc: $FAKE_HOME/.local/bin"
}

WORK_GITCONFIG='[user]
	email = me@work.example'

seed_existing_home() {
	mkdir -p "$FAKE_HOME" "$WORK/shared"
	echo '# team-wide bashrc' >"$WORK/shared/bashrc"
	ln -s "$WORK/shared/bashrc" "$FAKE_HOME/.bashrc"
	printf '%s\n' "$WORK_GITCONFIG" >"$FAKE_HOME/.gitconfig"
	echo 'WORK_PROFILE=read' >"$FAKE_HOME/.profile"
	seed_old_skill_link
}

# ~/.claude/skills/<skill> as a symlink into a separate clone.
seed_old_skill_link() {
	set -- "$SKILLS_SRC"/*/SKILL.md
	OLD_SKILL=${1%/SKILL.md} OLD_SKILL=${OLD_SKILL##*/}
	mkdir -p "$WORK/old-clone/$OLD_SKILL" "$FAKE_HOME/.claude/skills"
	echo 'old clone' >"$WORK/old-clone/$OLD_SKILL/SKILL.md"
	ln -s "$WORK/old-clone/$OLD_SKILL" "$FAKE_HOME/.claude/skills/$OLD_SKILL"
}

# Apply replaced that symlink with a copy and never wrote through it.
check_old_skill_link() {
	assert_eq "old clone: $(cat "$WORK/old-clone/$OLD_SKILL/SKILL.md")" "old clone: old clone"
	check_skill "$SKILLS_SRC/$OLD_SKILL"
}

check_shared_bashrc() {
	[ -L "$FAKE_HOME/.bashrc" ] || fail "shared ~/.bashrc symlink was replaced"
	assert_eq "$(cat "$WORK/shared/bashrc")" "# team-wide bashrc"
}

# ~/.dotfiles-backup/<time>/$1 must hold content $2.
check_backup() {
	set -- "$FAKE_HOME"/.dotfiles-backup/*/"$1" "$2"
	[ -f "$1" ] || { fail "no backup of ${1##*/}"; return; }
	assert_eq "$(cat "$1")" "$2"
}

# A work computer: the team's ~/.bashrc stays, ours lands in ~/my.bashrc
# (which the team file sources), and the email defaults to the work one.
check_work_home() {
	section "work computer"
	FAKE_HOME="$WORK/work"
	mkdir -p "$FAKE_HOME"
	printf '%s\n' "$TEAM_BASHRC" >"$FAKE_HOME/.bashrc"
	chez_init --promptChoice 'Is this a personal or work computer=work' --promptDefaults
	chez apply || fail "work apply: exit $?"
	assert_eq "$(cat "$FAKE_HOME/.bashrc")" "$TEAM_BASHRC"
	assert_file my.bashrc
	assert_eq "$(git config -f "$FAKE_HOME/.gitconfig" user.email)" "d.evans@samsung.com"
	assert_eq "bash -ic: $(path_head bash -ic)" "bash -ic: $FAKE_HOME/.local/bin"
}

TEAM_BASHRC='[ -f "$HOME/my.bashrc" ] && . "$HOME/my.bashrc"'

# --- main ---------------------------------------------------------------

seed_claude_settings
bootstrap
check_targets
check_claude_settings
check_gitconfig
check_skills
check_packages
check_karabiner
check_handy
check_shell bash
check_shell zsh
check_brew_after_system
check_idempotent
check_claude_settings
check_skills_in_diff
check_karabiner
check_existing_home
check_work_home

if [ -s "$FAILURES" ]; then
	printf '\n%d failure(s)\n' "$(grep -c '^    FAIL' "$FAILURES")"
	exit 1
fi
printf '\nall checks passed\n'
