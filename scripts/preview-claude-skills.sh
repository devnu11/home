#!/bin/sh
# Prints what the next `chezmoi apply` will do to the Claude skills, which
# `chezmoi diff` cannot show: the links are made by install.sh in the
# claude-skills clone, not by files in this repo. Runs after every
# `chezmoi diff` (a hook in .chezmoi.toml.tmpl) and prints nothing when the
# clone is at the pin and no link would change.
#
# Runs install.sh from the clone as it is checked out now, as apply does.

SRC=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
REPO="$HOME/code/claude-skills"
PIN_FILE="$SRC/.chezmoidata/claude-skills.yaml"

get_pin() {
	sed -n 's/^ *commit: *//p' "$PIN_FILE"
}

# Links install.sh would add, change or remove; its "ok" lines are dropped.
get_link_changes() {
	CLAUDE_SKILLS_DIR="$HOME/.claude/skills" "$REPO/install.sh" --dry-run |
		grep -Ev '^(ok |$)|skill\(s\) in '
}

describe_checkout() {
	pin=$1
	branch=$(git -C "$REPO" branch --show-current)
	echo "claude-skills (~/code/claude-skills)"
	echo "  checkout: $(git -C "$REPO" rev-parse --short HEAD) (${branch:-detached})"
	echo "  pin:      $(printf %.7s "$pin")"
	[ "$(git -C "$REPO" rev-parse HEAD)" = "$pin" ] || describe_distance "$pin"
}

describe_distance() {
	if ! missing=$(git -C "$REPO" rev-list --count "HEAD..$1" 2>/dev/null); then
		echo "  the pin is not fetched yet; apply fetches it if the pin changed"
	elif [ "$missing" -eq 0 ]; then
		echo "  the checkout already contains the pin"
	else
		echo "  the checkout lacks $missing pinned commit(s):"
		git -C "$REPO" log --oneline "HEAD..$1" | sed 's/^/    /'
	fi
	echo "  apply moves the checkout to the pin only when the pin changed since the"
	echo "  last apply; the diff above then lists checkout-claude-skills.sh"
}

describe_links() {
	if [ -z "$1" ]; then
		echo "  skill links: no changes (as checked out now)"
		return
	fi
	echo "  skill links apply would change (as checked out now):"
	printf '%s\n' "$1" | sed 's/^/    /'
}

describe_pin_commands() {
	latest=$(git -C "$REPO" rev-parse --short origin/main 2>/dev/null) || return 0
	echo "  to pin origin/main ($latest) or another commit:"
	echo "    sh $SRC/scripts/pin-claude-skills.sh [<commit>]"
	echo "  then commit the pin:"
	echo "    git -C $SRC commit -m \"chore(skills): pin claude-skills to $latest\" -- .chezmoidata/claude-skills.yaml"
}

main() {
	[ -x "$REPO/install.sh" ] || exit 0
	pin=$(get_pin)
	links=$(get_link_changes)
	[ "$(git -C "$REPO" rev-parse HEAD)" != "$pin" ] || [ -n "$links" ] || exit 0
	describe_checkout "$pin"
	describe_links "$links"
	describe_pin_commands
}

main
