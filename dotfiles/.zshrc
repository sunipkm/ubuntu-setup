if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi
export ZPLUG_HOME=$HOME/.zplug
source $ZPLUG_HOME/init.zsh
# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"
# export EDITOR="nvim"
export PATH="$HOME/.tmux/plugins/tmuxifier/bin:$PATH"
export PATH=$HOME/.local/bin:/usr/local/bin:$PATH

plugins=(
  git
  fzf-tab
  zsh-autosuggestions
  zsh-syntax-highlighting
  npm
  zsh-interactive-cd
  z
  yarn
  ufw
  systemadmin
  pass
  minikube
  kubectl
  jsontools
  docker
  copybuffer
  copypath
  command-not-found
  transfer
)

ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=4'

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time oh-my-zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="powerlevel10k/powerlevel10k"
source $ZSH/oh-my-zsh.sh

# Setup fzf
# source <(fzf --zsh)
source $HOME/.fzf_zsh

bindkey '^R' fzf-history-widget

# Quick cd using fzf
fcd() {
  cd "$(find -type d | fzf --preview 'tree -C {} | head -200' --preview-window 'up:60%')"
}

# Find and edit using fzf
fe() {
  nvim "$(find -type f | fzf --preview 'cat {}' --preview-window 'up:60%')"
}

frg() {
	RG_PREFIX="rga --files-with-matches"
	local file
	file="$(
		FZF_DEFAULT_COMMAND="$RG_PREFIX '$1'" \
			fzf --sort --preview="[[ ! -z {} ]] && rga --pretty --context 5 {q} {}" \
				--phony -q "$1" \
				--bind "change:reload:$RG_PREFIX {q}" \
				--preview-window="70%:wrap"
	)" &&
	echo "opening $file" &&
	xdg-open "$file"
}

pe() {
  local file
  file=$(find ~/.password-store -type f -name '*.gpg' | sed "s|^$HOME/.password-store/||;s|\.gpg$||" | fzf)
  if [ -n "$file" ]; then
    pass edit "$file"
  fi
}

# Find and remove files with fzf
frm() {
  # Use `find` to list files and directories, and pipe them to `fzf` for selection
  selected=$(find . -type f -o -type d 2>/dev/null | fzf -m)
  
  # Check if any selection was made
  if [[ -n "$selected" ]]; then
    # Echo the files or directories that will be deleted
    echo "Deleting the following files or directories:"
    echo "$selected"
    
    # Use `xargs` to safely pass selected files/directories to `rm -rf`
    echo "$selected" | xargs -d '\n' rm -rf
  else
    echo "No files or directories selected."
  fi
}

ssh_fzf() {
    local host=$(grep "Host " ~/.ssh/config | cut -d " " -f 2 | fzf)
    if [[ -n $host ]]; then
        ssh "$host"
    else
        echo "No host selected"
    fi
}

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='nvim'
# else
#   export EDITOR='mvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# ssh
# export SSH_KEY_PATH="~/.ssh/rsa_id"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.

# autosuggestions
#source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh

#HOMEBREW_IMPORT

function duls { paste <( du -hs -- "$@" | cut -f1 ) <( ls -ld -- "$@" ) }
fpath=($fpath "$HOME/.zfunctions")

function ssh-set-date { ssh "$@" sudo date -s @$(date -u +"%s") }

export GPG_TTY=$(tty)
export EDITOR=nano

# Programs
alias cat="bat"
alias cl="clear"
alias ls="eza -l --icons"
alias la="eza -TL 2 --icons"
alias lg="lazygit"
alias py="python"
alias td="termdown"

# Tmux commands
alias kat="tmux kill-server"
alias t="TERM=screen-256color-bce tmux"
alias tat="tmux attach -t"
alias tsf="tmux source-file ~/.tmux.conf"
alias tk="tmux kill-session -a"

# Directories
alias download="cd ~/Downloads"
alias dopython="cd ~/Codes/python"
alias dorust="cd ~/Codes/rust"
alias dopicture="cd ~/Codes/picture"

# config files
alias ezsh="$EDITOR ~/.zshrc"
alias envim="cd ~/.config/nvim && nvim"
alias ehyp="cd ~/.config/hypr && nvim"
# alias qutebrowser="cd ~/.config/qutebrowser"

# The following lines were added by compinstall

zstyle ':completion:*' completer _expand _complete _ignored
zstyle ':completion:*' matcher-list 'm:{[:lower:][:upper:]}={[:upper:][:lower:]}'
zstyle :compinstall filename '$HOME/.zshrc'

autoload -Uz compinit
compinit
# End of lines added by compinstall
# Lines configured by zsh-newuser-install
HISTFILE=~/.histfile
HISTSIZE=1000
SAVEHIST=100000
# End of lines configured by zsh-newuser-install

bindkey -v
bindkey -M viins 'kj' vi-cmd-mode
# this will cd and ls at the same time.
function cd {
    builtin cd "$@" && ls -F
}

export GPG_TTY=$(tty)

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

export HOMEBREW_EDITOR=nano

source "$HOME/.cargo/env"

autoload bashcompinit
bashcompinit

alias vim=nvim

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

eval "$(starship init zsh)"
eval "$(tmuxifier init -)"
eval "$(zoxide init zsh)"

# export GOPATH=$(go env GOPATH)
# export GOBIN=$GOPATH/bin
# export PATH=$PATH:$GOBIN

source ~/.miniconda3/bin/activate

#LD_LIBRARY_PATH

# eval "$(thefuck --alias)"

# if [ -z "$TMUX" ]; then
#     tmux attach || exec tmux new-session;
# fi
