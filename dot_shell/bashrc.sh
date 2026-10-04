# Interactive bash setup. Managed by chezmoi.
# Sourced from ~/.bashrc, or from ~/.bash_profile when ~/.bashrc is a shared
# symlink that chezmoi leaves alone (see .chezmoiignore).

# bash has no ~/.zshenv equivalent, so env.sh is sourced here too (it is
# idempotent). BASH_ENV points here as well, which covers non-interactive
# bash scripts and cron.
[ -f "$HOME/.shell/env.sh" ] && . "$HOME/.shell/env.sh"

# Everything below is interactive-only.
case "$-" in
	*i*) ;;
	*) return ;;
esac

__HOME_BASHRC=1
[ -f "$HOME/.shell/interactive.sh" ] && . "$HOME/.shell/interactive.sh"

# Machine-local additions (corporate proxies, PATH entries, work aliases).
# Not tracked in the dotfiles repo.
if [ -f "$HOME/.bashrc.local" ]; then . "$HOME/.bashrc.local"; fi
