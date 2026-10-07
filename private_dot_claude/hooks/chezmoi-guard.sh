#!/bin/sh
# Managed by chezmoi. Edit the source: `chezmoi edit ~/.claude/hooks/chezmoi-guard.sh`
#
# Claude Code PreToolUse hook: stop a session from running chezmoi commands that
# write to the home directory unless the user approves. Registered in
# ~/.claude/settings.json by modify_settings.json.
#
# Input: the hook's JSON on stdin. Output: a permission decision, or nothing.
# Claude Code ignores "ask" in auto and bypassPermissions modes, so those get
# "deny" instead; the user then runs the command themselves.
#
# The raw JSON is matched instead of parsing it (no jq on Windows Git Bash).
# The description field is dropped first, and gaps may not cross an unescaped
# quote, so text outside the command can't complete a match.

# A chezmoi invocation, then (within the same simple command) a subcommand that
# writes to the destination directory.
GAP='([^;&|"]|\\")*'
WRITES="chezmoi${GAP}[[:space:]](apply|update|destroy|purge)([[:space:]]|\\\\?\"|\$)"
APPLY_FLAG="chezmoi${GAP}[[:space:]](init|edit)${GAP}[[:space:]](--apply|-a)([[:space:]]|\\\\?\"|\$)"
# shellcheck disable=SC2016 # backticks are literal Markdown
REASON='chezmoi would write to the home directory. Show the user the full, unfiltered `chezmoi diff` and `chezmoi status` for the targets, then ask them to approve or to run it themselves (see ~/.claude/CLAUDE.md).'

writes_home() {
	printf '%s' "$1" | grep -Eq -e "$WRITES" -e "$APPLY_FLAG"
}

# ask where Claude Code honours it; deny everywhere else, unknown modes included.
decision_for() {
	case "$1" in
		*'"permission_mode":"default"'* | *'"permission_mode":"acceptEdits"'* | *'"permission_mode":"plan"'*) echo ask ;;
		*) echo deny ;;
	esac
}

input=$(cat | tr -d '\n' | sed -E \
	-e 's/"permission_mode"[[:space:]]*:[[:space:]]*/"permission_mode":/' \
	-e 's/"description"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"//')
writes_home "$input" || exit 0
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' \
	"$(decision_for "$input")" "$REASON"
