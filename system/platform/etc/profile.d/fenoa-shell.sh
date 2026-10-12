# Interactive bash setup for the shell tools in the Brewfile (installed into Homebrew on first boot by
# fenoa-brew-setup): the starship prompt, zoxide jumps, fzf key bindings and eza listings. Each piece
# waits until its tool is installed. Fedora's /etc/bashrc sources
# profile.d for interactive shells, and brew.sh (which puts Homebrew on PATH) sorts before this file.
# Opt out per user with `export FENOA_SHELL_SETUP=0` in ~/.bashrc before /etc/bashrc is sourced.

[ -n "${BASH_VERSION:-}" ] || return 0
case $- in *i*) ;; *) return 0 ;; esac
[ "${FENOA_SHELL_SETUP:-1}" = 0 ] && return 0

if [[ ${TERM:-} != "dumb" ]] && command -v starship >/dev/null 2>&1; then
  eval "$(starship init bash)"
fi

if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init bash)"

  # `cd dir` behaves as usual; `cd partial-name` jumps to the best zoxide match instead of failing.
  zd() {
    if (( $# == 0 )); then
      builtin cd ~ || return
    elif [[ -d $1 ]]; then
      builtin cd "$1" || return
    else
      if ! z "$@"; then
        echo "Error: Directory not found"
        return 1
      fi
      printf "\U000F17A9 "
      pwd
    fi
  }
  alias cd="zd"
fi

if command -v fzf >/dev/null 2>&1; then
  # Ctrl+R history search, Ctrl+T insert a file path, Alt+C cd into a directory, `**<Tab>` completion.
  eval "$(fzf --bash)"
  if command -v bat >/dev/null 2>&1; then
    alias ff="fzf --preview 'bat --style=numbers --color=always {}'"
  fi
fi

if command -v eza >/dev/null 2>&1; then
  alias ls='eza -lh --group-directories-first --icons=auto'
  alias lsa='ls -a'
  alias lt='eza --tree --level=2 --long --icons --git'
  alias lta='lt -a'
fi
