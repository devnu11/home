# List the directories by size of their contents
alias lsd="sudo du -ks $(ls -d */) | sort -nr | cut -f2 | xargs -d '\n' du -sh 2> /dev/null"

alias ls="ls -al --color"
alias cls="clear"
alias ll="ls -l"
alias lf="ls -F"
alias lr="ls -R"
alias h="history"

alias g="git"