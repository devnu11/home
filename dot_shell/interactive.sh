# Interactive-shell configuration: history, aliases, helpers.
# Sourced from ~/.zshrc and ~/.bashrc. Managed by chezmoi.
# Anything that scripts and cron also need belongs in env.sh instead.

# --- History ------------------------------------------------------------
HISTSIZE=50000
if [ -n "$BASH_VERSION" ]; then
	HISTFILESIZE=50000
	HISTCONTROL=ignoreboth      # skip duplicates and lines starting with a space
	HISTTIMEFORMAT='%F %T '
	shopt -s histappend         # append rather than clobber on exit
	shopt -s checkwinsize
elif [ -n "$ZSH_VERSION" ]; then
	SAVEHIST=50000
	HISTFILE="$HOME/.zsh_history"
	setopt APPEND_HISTORY INC_APPEND_HISTORY EXTENDED_HISTORY
	setopt HIST_IGNORE_DUPS HIST_IGNORE_SPACE HIST_REDUCE_BLANKS
fi

# --- ls -----------------------------------------------------------------
# GNU coreutils spells colour --color=auto; older BSD ls only knows -G.
# (Current macOS ls understands --color and honours it more reliably than -G.)
if ls --color=auto >/dev/null 2>&1; then
	alias ls='ls --color=auto'
else
	export CLICOLOR=1
	alias ls='ls -G'
fi

alias ll='ls -l'
alias la='ls -al'
alias lf='ls -F'
alias lr='ls -R'

alias h='history'
alias g='git'

# List subdirectories by total size, largest first.
# `sort -h` is in both GNU and BSD sort; the original used GNU-only `xargs -d`.
lsd() {
	du -sh -- */ 2>/dev/null | sort -hr
}

# --- handy servers ------------------------------------------------------
# Restart anything listed in ~/.config/handy/servers that has died. Runs in
# the background so the prompt never waits, and is a no-op without handy or
# a config. `handy servers start` itself rate-limits each host to one check
# per 10 minutes and coordinates concurrent logins; the stamp check here just
# avoids starting Python at all when the hook ran recently and the config
# hasn't changed since. HANDY_SERVERS_DISABLE=1 turns it off.
_handy_servers_hook() {
	[ -z "${HANDY_SERVERS_DISABLE:-}" ] || return 0
	command -v handy >/dev/null 2>&1 || return 0
	_hs_config="${XDG_CONFIG_HOME:-$HOME/.config}/handy/servers"
	[ -f "$_hs_config" ] || return 0
	_hs_state="${XDG_STATE_HOME:-$HOME/.local/state}/handy-servers"
	_hs_stamp="$_hs_state/last-hook"
	if [ -n "$(find "$_hs_stamp" -mmin -10 2>/dev/null)" ] && ! [ "$_hs_config" -nt "$_hs_stamp" ]; then
		return 0
	fi
	mkdir -p "$_hs_state" || return 0
	: >"$_hs_stamp"
	_hs_log="$_hs_state/hook.log"
	if [ -f "$_hs_log" ] && [ "$(($(wc -c <"$_hs_log")))" -gt 1048576 ]; then
		tail -n 500 "$_hs_log" >"$_hs_log.tmp" && mv "$_hs_log.tmp" "$_hs_log"
	fi
	(nohup handy servers start --quiet >>"$_hs_log" 2>&1 &)
}
_handy_servers_hook
unset -f _handy_servers_hook
unset _hs_config _hs_state _hs_stamp _hs_log
