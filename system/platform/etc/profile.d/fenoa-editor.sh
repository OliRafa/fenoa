# Prefer Neovim (installed into the Homebrew prefix by fenoa-brew-setup.service, whose PATH hook
# /etc/profile.d/brew.sh sorts before this file) and fall back to vi from vim-minimal.
if command -v nvim >/dev/null 2>&1; then
  export EDITOR=nvim VISUAL=nvim
else
  export EDITOR="${EDITOR:-vi}"
fi
