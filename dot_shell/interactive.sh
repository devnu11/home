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
