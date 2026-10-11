#!/bin/sh
# Pins ~/code/claude-skills to a commit by writing its SHA to
# .chezmoidata/claude-skills.yaml, then prints the command that commits the pin.
# Does not apply anything: the next `chezmoi apply` checks the pin out.
#
#     sh scripts/pin-claude-skills.sh [<commit>]    # default: origin/main
#
# Fetches origin first. Refuses a commit that is on no origin branch, since
# other machines could not fetch it.

SRC=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
REPO="${CLAUDE_SKILLS_REPO:-$HOME/code/claude-skills}"
PIN_FILE="$SRC/.chezmoidata/claude-skills.yaml"

die() {
	echo "pin-claude-skills: $*" >&2
	exit 1
}

resolve_commit() {
	git -C "$REPO" fetch --quiet origin || die "could not fetch origin in $REPO"
	git -C "$REPO" rev-parse --verify --quiet "$1^{commit}" || die "no commit $1 in $REPO"
}

require_pushed() {
	[ -n "$(git -C "$REPO" branch --remotes --contains "$1")" ] ||
		die "$1 is on no origin branch; push it first"
}

write_pin() {
	tmp="$PIN_FILE.tmp"
	sed "s/^\( *commit:\).*/\1 $1/" "$PIN_FILE" >"$tmp" || die "could not write $tmp"
	command mv -f "$tmp" "$PIN_FILE"
}

main() {
	sha=$(resolve_commit "${1:-origin/main}") || exit 1
	require_pushed "$sha"
	write_pin "$sha"
	short=$(printf %.7s "$sha")
	echo "pinned claude-skills to $short ($(git -C "$REPO" log --format=%s -1 "$sha"))"
	echo "commit the pin with:"
	echo "  git -C $SRC commit -m \"chore(skills): pin claude-skills to $short\" -- .chezmoidata/claude-skills.yaml"
}

main "$@"
