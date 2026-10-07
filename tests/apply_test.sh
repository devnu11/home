#!/bin/sh
# End-to-end test of `chezmoi apply` on Linux and macOS.
#
# Bootstraps this source directory into a throwaway HOME the way a new machine
# would (init with canned prompt answers, then apply), checks what landed, and
# checks that a second apply changes nothing. Nothing touches the real home:
# HOME points at a scratch directory for every command, so chezmoi's config and
# state, the claude-skills clone, and anything `uv tool install` writes all
# land there.
#
# Needs chezmoi and git on PATH, the handy submodule checked out, and network
# access (the claude-skills external is cloned from GitHub). zsh and uv are
# optional: their checks are skipped when absent.
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

MANAGED='.gitconfig .shell/env.sh .shell/interactive.sh .shell/lamaison.sh .bashrc .bash_profile
.zshenv .zprofile .zshrc .claude/CLAUDE.md'

# Source-dir furniture and Windows-only files stay out of ~.
UNMANAGED='README.md LICENSE handy tests .github Documents'

# key=value pairs the Unix gitconfig must hold.
GIT_VALUES='user.name=CI Test
user.email=ci@example.com
core.autocrlf=input'

# --- steps --------------------------------------------------------------

bootstrap() {
	section "init + first apply"
	# --promptString/--promptChoice key on the prompt text, not the variable.
	chez init \
		--promptString 'Full name for git commits=CI Test' \
		--promptString 'Email address for git commits=ci@example.com' \
		--promptString "Your username (shown as 'me' in the prompt)=ci" \
		--promptString "Usual machine, shown grey in the prompt=ci-host" \
		--promptString "Host for a bare \`ssh\` (blank for none)=" \
		--promptString "printf pattern turning a bare ssh number into a host, e.g. box%02d (blank for none)=" \
		--promptString "Directory shown blue in the prompt (blank for none)=" \
		--promptString "Directory shown cyan in the prompt (blank for none)=" \
		--promptChoice 'Machine profile=personal' || fail "init: exit $?"
	chez apply || fail "first apply: exit $?"
}

check_targets() {
	section "targets"
	for f in $MANAGED; do assert_file "$f"; done
	for f in $UNMANAGED; do assert_absent "$f"; done
	case "$(ls -ld "$FAKE_HOME/.claude")" in
		drwx------*) ;;
		*) fail "~/.claude is not mode 0700" ;;
	esac
}

check_gitconfig() {
	section "gitconfig"
	echo "$GIT_VALUES" | while IFS='=' read -r key want; do
		assert_eq "$key=$(git config -f "$FAKE_HOME/.gitconfig" "$key")" "$key=$want"
	done
	[ -z "$(git config -f "$FAKE_HOME/.gitconfig" diff.tool)" ] || fail "Windows diff.tool leaked into Unix gitconfig"
}

check_skill_links() {
	section "claude-skills links"
	clone="$FAKE_HOME/code/claude-skills"
	[ -x "$clone/install.sh" ] || { fail "external not cloned to ~/code/claude-skills"; return; }
	set -- "$clone"/*/SKILL.md
	[ -f "$1" ] || fail "no skills found in the claude-skills clone"
	for manifest; do
		[ -f "$manifest" ] && check_skill_link "${manifest%/SKILL.md}"
	done
}

# ~/.claude/skills/<name> must be a symlink to the skill directory $1.
check_skill_link() {
	link="$FAKE_HOME/.claude/skills/$(basename "$1")"
	[ -L "$link" ] || { fail "$link is not a symlink"; return; }
	assert_eq "$(readlink "$link")" "$1"
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
		Darwin) command -v brew >/dev/null 2>&1 && echo beyond-compare karabiner-elements ;;
	esac
}

KARABINER_RULE='Cmd+Tab sends Alt+Tab when Windows App is frontmost'

# On macOS the shipped rule is enabled in karabiner.json exactly once;
# elsewhere nothing of Karabiner's lands.
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
	! grep -Eq '^(link|relink|prune) ' "$1" || fail "link script changed something on a re-run"
}

# --- main ---------------------------------------------------------------

bootstrap
check_targets
check_gitconfig
check_skill_links
check_packages
check_karabiner
check_handy
check_shell bash
check_shell zsh
check_brew_after_system
check_idempotent
check_skill_links
check_karabiner

if [ -s "$FAILURES" ]; then
	printf '\n%d failure(s)\n' "$(grep -c '^    FAIL' "$FAILURES")"
	exit 1
fi
printf '\nall checks passed\n'
