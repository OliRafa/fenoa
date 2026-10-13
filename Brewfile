# Fenoa — CLI / developer tools delivered via Homebrew (Linuxbrew)
#
# Installed into the user-writable brew prefix (/home/linuxbrew/.linuxbrew) on first boot, once the
# network is up, by fenoa-brew-setup.service, NOT baked into the immutable image. The base image
# ships Homebrew itself prebuilt (ublue's brew image) and puts its shellenv on PATH via
# /etc/profile.d/brew.sh, and brew-update.timer / brew-upgrade.timer keep everything here current
# after first boot.
#
# Rule of thumb: tools with their own release cadence (editors, language toolchains, dev CLIs)
# live here; anything the desktop or a system service needs at boot lives in the image.

# --- Editor (EDITOR=nvim via /etc/profile.d/fenoa-editor.sh) ---
brew "neovim"
brew "tree-sitter"
brew "luarocks"
brew "lua"

# --- Language toolchains (brew is the versioned-toolchain sweet spot) ---
brew "rust"                 # cargo + rustc
brew "llvm"                 # provides clang
brew "ruby"
brew "libyaml"
brew "openjdk"
brew "dotnet"
brew "poetry"
brew "libpq"
brew "mariadb-connector-c"

# --- Dev CLIs ---
brew "gh"

# --- Shell tools (wired into interactive bash by /etc/profile.d/fenoa-shell.sh) ---
brew "starship"            # prompt
brew "zoxide"              # `z dir` jumps to frecent directories; `cd` falls back to it
brew "fzf"                 # fuzzy finder: Ctrl+R history, Ctrl+T files, Alt+C directories
brew "eza"                 # ls with git status and icons (`ls`, `lt` aliases)
brew "bat"                 # cat with syntax highlighting and paging
brew "ripgrep"             # rg: fast recursive grep
brew "fd"                  # fd: fast, friendly find
brew "lazygit"             # terminal UI for git

# --- General CLI utilities ---
brew "tmux"
brew "btop"                # process / resource monitor
brew "yt-dlp"
brew "tealdeer"            # tldr client
brew "dua-cli"
brew "whois"
brew "inxi"
