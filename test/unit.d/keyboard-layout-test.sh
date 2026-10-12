#!/bin/bash

# fenoa/input.lua derives Hyprland's keyboard layout from the system setting: XKBLAYOUT & co. in
# /etc/vconsole.conf (localectl set-x11-keymap), else the console KEYMAP that systemd-firstboot
# writes, mapped through systemd's kbd-model-map. Run with a stub `hl` and fixture files.

source "$(dirname "$0")/base-test.sh"

lua_bin=$(command -v lua5.4 || command -v lua || true)
if [[ -z $lua_bin ]]; then
  pass "skipped (no lua interpreter on PATH)"
  exit 0
fi

input="$ROOT/system/desktop/usr/share/fenoa/hypr/fenoa/input.lua"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

# A slice of the real table's format: console-keymap layout model variant options.
cat >"$test_tmp/kbd-model-map" <<'MAP'
# consolelayout		xlayout	xmodel		xvariant	xoptions
us			us	pc105+inet	-		terminate:ctrl_alt_bksp
br-abnt2		br	abnt2		-		terminate:ctrl_alt_bksp
de-latin1-nodeadkeys	de	pc105		nodeadkeys	terminate:ctrl_alt_bksp
ru			ru,us	pc105		-		terminate:ctrl_alt_bksp,grp:shifts_toggle,grp_led:scroll
MAP

# The harness: a stub `hl` that captures the input config, then run input.lua.
cat >"$test_tmp/harness.lua" <<'LUA'
local captured
hl = {
  config = function(t) if t.input then captured = t.input end end,
  gesture = function() end,
  window_rule = function() end,
}
dofile(arg[1])
io.write(captured.kb_layout, "|", captured.kb_variant, "|", captured.kb_options)
LUA

layout_for() { # layout_for <vconsole.conf contents> → "layout|variant|options"
  printf '%s\n' "$1" >"$test_tmp/vconsole.conf"
  FENOA_VCONSOLE_CONF="$test_tmp/vconsole.conf" FENOA_KBD_MODEL_MAP="$test_tmp/kbd-model-map" \
    timeout 10 "$lua_bin" "$test_tmp/harness.lua" "$input" </dev/null
}

check() { # check <description> <vconsole contents> <expected>
  local got
  got=$(layout_for "$2") || fail "$1: input.lua runs" "$got"
  [[ $got == "$3" ]] || fail "$1" "expected '$3', got '$got'"
  pass "$1"
}

check "nothing configured → us" "" "us||"
check "localectl's XKB settings win" $'KEYMAP=us\nXKBLAYOUT=br\nXKBVARIANT=thinkpad\nXKBOPTIONS=compose:ralt' "br|thinkpad|compose:ralt"
check "firstboot's console KEYMAP maps through kbd-model-map" "KEYMAP=br-abnt2" "br||"
check "a mapped variant comes through" 'KEYMAP="de-latin1-nodeadkeys"' "de|nodeadkeys|"
check "an unknown console keymap falls back to us" "KEYMAP=xx-unknown" "us||"
check "systemd's ru,us mapping is reordered to us,ru, keeping its own toggle" "KEYMAP=ru" "us,ru|,|grp:shifts_toggle,grp_led:scroll"
check "a lone non-Latin layout gets us first, reached with both Alts" "XKBLAYOUT=gr" "us,gr|,|grp:alts_toggle"
check "variants stay aligned with their layouts" $'XKBLAYOUT=ua,de\nXKBVARIANT=winkeys,nodeadkeys' "de,ua|nodeadkeys,winkeys|grp:alts_toggle"
check "X-only terminate options are dropped" $'XKBLAYOUT=fr\nXKBOPTIONS=terminate:ctrl_alt_bksp,caps:escape' "fr||caps:escape"
