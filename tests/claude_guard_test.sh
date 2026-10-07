#!/bin/sh
# Unit test for private_dot_claude/hooks/chezmoi-guard.sh.
#
# Each case feeds the hook a PreToolUse payload and checks its decision:
# ask, deny, or none (no output: the command proceeds normally).
#
#     sh tests/claude_guard_test.sh

set -u

SRC=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
HOOK="$SRC/private_dot_claude/hooks/chezmoi-guard.sh"
failures=0

# shellcheck disable=SC2016 # $SRC in a case is literal command text
# CASES: expected decision | permission mode | command, already JSON-escaped.
CASES='ask|default|chezmoi apply
ask|acceptEdits|chezmoi apply ~/.zshrc
ask|plan|chezmoi update
deny|auto|chezmoi apply
deny|bypassPermissions|chezmoi apply
deny|dontAsk|chezmoi apply
deny|auto|cd ~ && chezmoi apply ~/.shell/env.sh ~/.zprofile
deny|auto|env X=1 chezmoi --source . apply
deny|auto|chezmoi --source \"$SRC\" --no-tty apply
deny|auto|sh -c \"chezmoi apply\"
deny|auto|chezmoi init --apply https://example.com/dots.git
deny|auto|chezmoi edit -a ~/.zshrc
deny|auto|chezmoi destroy ~/.bashrc
deny|auto|chezmoi purge
none|auto|chezmoi diff
none|auto|chezmoi status
none|auto|chezmoi diff ~/.config/apply
none|auto|chezmoi execute-template < run_onchange_after_enable-karabiner-rules.sh.tmpl
none|auto|chezmoi diff; echo apply
none|auto|chezmoi init --promptString x=y
none|auto|git commit -m \"docs: never apply without asking\"
none|auto|ls applications'

payload() {
	printf '{"tool_name":"Bash","permission_mode": "%s","tool_input":{"command":"%s","description":"Run chezmoi apply on a fake home"}}' "$1" "$2"
}

decision() {
	payload "$1" "$2" | sh "$HOOK" | sed -n 's/.*"permissionDecision":"\([a-z]*\)".*/\1/p'
}

check() {
	got=$(decision "$2" "$3")
	[ "${got:-none}" = "$1" ] && return
	printf 'FAIL [%s] %s: got %s, want %s\n' "$2" "$3" "${got:-none}" "$1"
	failures=$((failures + 1))
}

while IFS='|' read -r want mode command; do
	check "$want" "$mode" "$command"
done <<EOF
$CASES
EOF

[ "$failures" -eq 0 ] && { echo "all guard cases passed"; exit 0; }
echo "$failures failure(s)"
exit 1
