#!/bin/bash

# fenoa/keyboard.lua resolves the keyboard layout from the system setting: XKBLAYOUT & co. in
# /etc/vconsole.conf (localectl set-x11-keymap, or systemd-firstboot when the console keymap
# converts), else the console KEYMAP mapped through systemd's kbd-model-map, with a Latin layout
# first. Hyprland (fenoa/input.lua) and the greeter (fenoa-greeter-session) must both get exactly
# what it returns, or the login screen and the session disagree on the layout the password is typed
# in. Run against fixture files with the Lua interpreter on PATH.

source "$(dirname "$0")/base-test.sh"

lua_bin=$(command -v lua5.4 || command -v lua || true)
if [[ -z $lua_bin ]]; then
  pass "skipped (no lua interpreter on PATH)"
  exit 0
fi

hypr="$ROOT/system/desktop/usr/share/fenoa/hypr"
keyboard="$hypr/fenoa/keyboard.lua"
input="$hypr/fenoa/input.lua"
wrapper="$ROOT/system/desktop/usr/libexec/fenoa-greeter-session"
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

export FENOA_VCONSOLE_CONF="$test_tmp/vconsole.conf" FENOA_KBD_MODEL_MAP="$test_tmp/kbd-model-map"

# --- keyboard.lua resolve() ------------------------------------------------------------------------

# No `hl` global here: the greeter runs keyboard.lua outside Hyprland, so any hl.* call in it would
# fail every check below.
cat >"$test_tmp/resolve.lua" <<'LUA'
local keyboard = dofile(arg[1]).resolve()
io.write(keyboard.layout, "|", keyboard.variant, "|", keyboard.options)
LUA

resolve() { # resolve <vconsole.conf contents> → "layout|variant|options"
  printf '%s\n' "$1" >"$FENOA_VCONSOLE_CONF"
  timeout 10 "$lua_bin" "$test_tmp/resolve.lua" "$keyboard" </dev/null
}

check() { # check <description> <vconsole contents> <expected>
  local got
  got=$(resolve "$2") || fail "$1: keyboard.lua runs" "$got"
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

# --- input.lua hands resolve()'s answer to Hyprland unchanged ----------------------------------------

cat >"$test_tmp/input-harness.lua" <<'LUA'
local captured
hl = {
  config = function(t) if t.input then captured = t.input end end,
  gesture = function() end,
  window_rule = function() end,
}
package.loaded["fenoa.keyboard"] = {
  resolve = function() return { layout = "de,ru", variant = "nodeadkeys,", options = "grp:alts_toggle" } end,
}
dofile(arg[1])
io.write(captured.kb_layout, "|", captured.kb_variant, "|", captured.kb_options)
LUA
got=$(timeout 10 "$lua_bin" "$test_tmp/input-harness.lua" "$input" </dev/null) || fail "input.lua runs" "$got"
[[ $got == "de,ru|nodeadkeys,|grp:alts_toggle" ]] ||
  fail "input.lua passes resolve()'s layout, variant and options to hl.config unchanged" "got '$got'"
pass "input.lua passes resolve()'s layout, variant and options to hl.config unchanged"

# --- fenoa-greeter-session exports resolve()'s answer to the greeter --------------------------------

cat >"$test_tmp/greeter" <<'SH'
#!/bin/bash
printf 'args=%s\n' "$*"
for v in XKB_DEFAULT_LAYOUT XKB_DEFAULT_VARIANT XKB_DEFAULT_OPTIONS; do
  if [[ -v $v ]]; then printf '%s=%s\n' "$v" "${!v}"; else printf '%s unset\n' "$v"; fi
done
SH
chmod +x "$test_tmp/greeter"

greet() { # greet <FENOA_LUA> <FENOA_KEYBOARD_LUA> → what the stub greeter saw
  env -u XKB_DEFAULT_LAYOUT -u XKB_DEFAULT_VARIANT -u XKB_DEFAULT_OPTIONS \
    FENOA_LUA="$1" FENOA_KEYBOARD_LUA="$2" FENOA_GREETER_SESSION="$test_tmp/greeter" \
    "$wrapper" --one "two words" 2>"$test_tmp/greet.err"
}

for contents in "KEYMAP=ru" "" $'XKBLAYOUT=ua,de\nXKBVARIANT=winkeys,nodeadkeys'; do
  expected=$(resolve "$contents")
  IFS='|' read -r layout variant options <<<"$expected"
  got=$(greet "$lua_bin" "$keyboard") || fail "the wrapper execs the greeter" "$(cat "$test_tmp/greet.err")"
  want=$(printf 'args=--one two words\nXKB_DEFAULT_LAYOUT=%s\nXKB_DEFAULT_VARIANT=%s\nXKB_DEFAULT_OPTIONS=%s' "$layout" "$variant" "$options")
  [[ $got == "$want" ]] ||
    fail "the greeter gets exactly resolve()'s answer for '${contents//$'\n'/ }'" "expected:"$'\n'"$want"$'\n'"got:"$'\n'"$got"
done
printf 'KEYMAP=ru\n' >"$FENOA_VCONSOLE_CONF"
got=$(greet "$lua_bin" "$keyboard")
[[ $got == *$'\n'"XKB_DEFAULT_LAYOUT=us,ru"$'\n'* ]] || fail "a ru console keymap starts the greeter in us,ru" "got:"$'\n'"$got"
pass "the greeter gets exactly resolve()'s answer, empty values included, and its arguments (KEYMAP=ru → us,ru)"

unset_all=$'args=--one two words\nXKB_DEFAULT_LAYOUT unset\nXKB_DEFAULT_VARIANT unset\nXKB_DEFAULT_OPTIONS unset'
got=$(greet "$test_tmp/no-such-lua" "$keyboard") || fail "without an interpreter the greeter still starts"
[[ $got == "$unset_all" ]] ||
  fail "without an interpreter the greeter starts with no XKB_DEFAULT_* (it reads vconsole.conf)" "got:"$'\n'"$got"
printf 'error("broken")\n' >"$test_tmp/broken.lua"
got=$(greet "$lua_bin" "$test_tmp/broken.lua") || fail "with a failing resolver the greeter still starts"
[[ $got == "$unset_all" ]] ||
  fail "with a failing resolver the greeter starts with no XKB_DEFAULT_*" "got:"$'\n'"$got"
grep -qF 'could not resolve the keyboard layout' "$test_tmp/greet.err" || fail "the fallback is logged" "$(cat "$test_tmp/greet.err")"
pass "a missing interpreter or failing resolver never blocks the greeter; it starts without XKB_DEFAULT_*"
