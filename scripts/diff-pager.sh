#!/bin/sh
# chezmoi's diff.pager (see .chezmoi.toml.tmpl): drops the diff of each script
# in HIDDEN, then pages the rest. `chezmoi diff --no-pager` skips this filter.
#
# chezmoi lists every run_ script in every diff, as a new file, even when it
# would do nothing. Hide a script here only when a diff hook reports what it
# would do; each entry is "<script>:<hook that reports it>", and
# tests/apply_test.sh fails when the hook is not wired up. Every other script
# stays in the diff.

HIDDEN="link-claude-skills.sh:preview-claude-skills.sh"

get_hidden_names() {
	for entry in $HIDDEN; do printf ' %s' "${entry%%:*}"; done
	echo ' '
}

drop_hidden() {
	awk -v hidden="$(get_hidden_names)" '{
		line = $0
		gsub(/\033\[[0-9;]*m/, "", line)  # colour codes hide the header
		if (line ~ /^diff --git /) {
			split(line, field, " ")
			skip = index(hidden, " " substr(field[3], 3) " ") > 0
		}
	}
	!skip'
}

page() {
	if [ -t 1 ]; then
		# PAGER may carry its own arguments, e.g. "less -R".
		# shellcheck disable=SC2086
		exec ${PAGER:-less -R}
	fi
	exec cat
}

main() {
	drop_hidden | page
}

main
