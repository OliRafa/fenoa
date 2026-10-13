#!/bin/bash

# /etc/profile.d/fenoa-shell.sh wires the Brewfile's shell tools into interactive bash. Sourced here
# with stub tools on PATH: everything is set up when the tools exist, nothing when they don't, and
# nothing in non-interactive shells or when the user opts out.

source "$(dirname "$0")/base-test.sh"

setup="$ROOT/system/platform/etc/profile.d/fenoa-shell.sh"
[[ -f $setup ]] || fail "fenoa-shell.sh ships"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin" "$test_tmp/empty"
# PATH holds only the stubs (or nothing): the host may have its own zoxide/eza in /usr/bin.
for tool in starship zoxide fzf; do
  # `<tool> init bash` / `fzf --bash` print shell code; make it define a marker function.
  printf '#!/bin/bash\necho "%s_loaded() { :; }"\n' "$tool" >"$test_tmp/bin/$tool"
done
for tool in eza bat; do
  printf '#!/bin/bash\nexit 0\n' >"$test_tmp/bin/$tool"
done
chmod +x "$test_tmp/bin"/*

probe='source "$1"; declare -F starship_loaded zoxide_loaded fzf_loaded zd; alias ls lt ff cd 2>/dev/null; true'

out=$(env -i HOME="$test_tmp" TERM=xterm PATH="$test_tmp/bin" /bin/bash -ic "$probe" _ "$setup" 2>/dev/null)
for want in starship_loaded zoxide_loaded fzf_loaded zd "alias ls='eza -lh" "alias lt='eza --tree" "alias ff=" "alias cd='zd'"; do
  [[ $out == *"$want"* ]] || fail "interactive bash with the tools installed sets up: $want" "$out"
done
pass "interactive bash: starship, zoxide (cd → zd), fzf, eza and the bat preview are set up"

out=$(env -i HOME="$test_tmp" TERM=xterm PATH="$test_tmp/empty" /bin/bash -ic "$probe" _ "$setup" 2>/dev/null)
[[ $out != *_loaded* && $out != *"alias ls="* && $out != *"alias cd="* ]] ||
  fail "before the tools are installed nothing is aliased or initialised" "$out"
pass "without the tools (before brew bundle finishes) nothing changes"

out=$(env -i HOME="$test_tmp" TERM=xterm PATH="$test_tmp/bin" /bin/bash -c "$probe" _ "$setup" 2>/dev/null)
[[ $out != *_loaded* && $out != *"alias ls="* ]] || fail "non-interactive shells are left alone" "$out"
pass "non-interactive shells are left alone"

# Fedora's /etc/zshrc sources profile.d too; zsh (new accounts' login shell) keeps its stock config.
# Stood in for by a bash without BASH_VERSION, which is all the guard looks at.
out=$(env -i HOME="$test_tmp" TERM=xterm PATH="$test_tmp/bin" /bin/bash -ic "unset BASH_VERSION; $probe" _ "$setup" 2>/dev/null)
[[ $out != *_loaded* && $out != *"alias ls="* && $out != *"alias cd="* ]] || fail "a shell that is not bash (zsh) is left alone" "$out"
pass "a shell that is not bash (zsh sourcing profile.d) is left alone"

out=$(env -i HOME="$test_tmp" TERM=xterm FENOA_SHELL_SETUP=0 PATH="$test_tmp/bin" /bin/bash -ic "$probe" _ "$setup" 2>/dev/null)
[[ $out != *_loaded* && $out != *"alias ls="* ]] || fail "FENOA_SHELL_SETUP=0 opts out" "$out"
pass "FENOA_SHELL_SETUP=0 opts out"

out=$(env -i HOME="$test_tmp" TERM=dumb PATH="$test_tmp/bin" /bin/bash -ic "$probe" _ "$setup" 2>/dev/null)
[[ $out != *starship_loaded* ]] || fail "no starship prompt on a dumb terminal" "$out"
pass "no starship prompt on a dumb terminal"
