#!/bin/sh
# Prints what the next `chezmoi apply` will do to the Claude skills, which
# `chezmoi diff` cannot show: the links are made by install.sh in the
# claude-skills clone, not by files in this repo. Runs after every
# `chezmoi diff` (a hook in .chezmoi.toml.tmpl) and prints nothing when there
# is nothing to change.
#
# Runs install.sh from the clone as it is checked out now, as apply does.

SRC=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
REPO="$HOME/code/claude-skills"
PIN=$(sed -n 's/^ *commit: *//p' "$SRC/.chezmoidata/claude-skills.yaml")

# When the clone is not at the pin, says so and lists the pinned commits it
# lacks. Apply checks the pin out only when the pin itself has changed.
pending_commits() {
	head=$(git -C "$REPO" rev-parse --short HEAD)
	[ "$(git -C "$REPO" rev-parse HEAD)" != "$PIN" ] || return 0
	echo "claude-skills: checkout is $head, pin is $(printf %.7s "$PIN"); links below are for the checkout"
	git -C "$REPO" log --oneline "HEAD..$PIN" 2>/dev/null ||
		echo "  (pin not fetched yet; apply fetches it if the pin changed)"
}

# Links install.sh would add, change or remove; its "ok" lines are dropped.
pending_links() {
	CLAUDE_SKILLS_DIR="$HOME/.claude/skills" "$REPO/install.sh" --dry-run |
		grep -Ev '^(ok |$)|skill\(s\) in '
}

[ -x "$REPO/install.sh" ] || exit 0
pending_commits
pending_links
exit 0
