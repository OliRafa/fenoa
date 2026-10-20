#!/bin/bash

# fenoa-kbd-backlight and fenoa-hypr-clamshell, exercised with stub brightnessctl / hyprctl / noctalia
# and a fake LED class directory.

source "$(dirname "$0")/base-test.sh"
require_command jq

kbd="$ROOT/system/desktop/usr/bin/fenoa-kbd-backlight"
clam="$ROOT/system/desktop/usr/bin/fenoa-hypr-clamshell"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin" "$test_tmp/leds/kbd_backlight"
log="$test_tmp/calls.log"

# brightnessctl: max/get read MOCK_MAX/MOCK_CUR; set records the value.
cat >"$mock_bin/brightnessctl" <<'SH'
#!/bin/bash
args=("$@")
for a in "${args[@]}"; do
  case $a in
    max) echo "${MOCK_MAX:-255}"; exit 0 ;;
    get) echo "${MOCK_CUR:-0}"; exit 0 ;;
  esac
done
echo "brightnessctl $*" >>"$MOCK_LOG"
SH
cat >"$mock_bin/noctalia" <<'SH'
#!/bin/bash
echo "noctalia $*" >>"$MOCK_LOG"
SH
# hyprctl: `monitors all -j` lists eDP-1 (+ DP-1 when MOCK_EXTERNAL=1); everything else is recorded.
cat >"$mock_bin/hyprctl" <<'SH'
#!/bin/bash
if [[ $1 == "monitors" ]]; then
  name=${MOCK_INTERNAL:-eDP-1}
  if [[ ${MOCK_EXTERNAL:-0} == "1" ]]; then
    jq -cn --arg n "$name" '[{name: $n}, {name: "DP-1"}]'
  else
    jq -cn --arg n "$name" '[{name: $n}]'
  fi
  exit 0
fi
echo "hyprctl $*" >>"$MOCK_LOG"
SH
chmod +x "$mock_bin"/*

mkdir -p "$test_tmp/run"
marker="$test_tmp/run/fenoa-clamshell"
run() { env PATH="$mock_bin:$PATH" MOCK_LOG="$log" FENOA_LEDS_DIR="$test_tmp/leds" XDG_RUNTIME_DIR="$test_tmp/run" "$@"; }

# --- keyboard backlight ----------------------------------------------------------------------------

: >"$log"
run MOCK_MAX=255 MOCK_CUR=100 bash "$kbd" up || fail "kbd up succeeds"
grep -q 'set 125$' "$log" || fail "up steps by 10% of max (100 -> 125)" "$(cat "$log")"
grep -q 'noctalia msg keyboard-backlight-osd 49' "$log" || fail "up shows Noctalia's keyboard OSD" "$(cat "$log")"
pass "up steps 10% and shows the OSD"

: >"$log"; run MOCK_MAX=255 MOCK_CUR=250 bash "$kbd" up
grep -q 'set 255$' "$log" || fail "up clamps at max" "$(cat "$log")"
: >"$log"; run MOCK_MAX=255 MOCK_CUR=10 bash "$kbd" down
grep -q 'set 0$' "$log" || fail "down clamps at 0" "$(cat "$log")"
: >"$log"; run MOCK_MAX=255 MOCK_CUR=250 bash "$kbd" cycle
grep -q 'set 0$' "$log" || fail "cycle wraps to 0 past max" "$(cat "$log")"
: >"$log"; run MOCK_MAX=3 MOCK_CUR=1 bash "$kbd" up
grep -q 'set 2$' "$log" || fail "a 3-level keyboard still steps by 1" "$(cat "$log")"
pass "clamping, cycling and few-level keyboards behave"

rmdir "$test_tmp/leds/kbd_backlight"
if run bash "$kbd" up 2>/dev/null; then fail "no backlight device is an error"; fi
mkdir -p "$test_tmp/leds/kbd_backlight"
if run bash "$kbd" sideways 2>/dev/null; then fail "an unknown direction is rejected"; fi
pass "a missing device and an unknown direction fail"

# --- clamshell -------------------------------------------------------------------------------------

: >"$log"; run MOCK_EXTERNAL=1 bash "$clam" close || fail "close succeeds"
grep -qF 'hyprctl eval hl.monitor({ output = "eDP-1", disabled = true })' "$log" ||
  fail "lid close with an external display disables the internal panel" "$(cat "$log")"
[[ "$(cat "$marker" 2>/dev/null)" == "eDP-1" ]] || fail "lid close leaves the panel name for config reloads"
pass "lid close with an external display disables the internal panel and leaves a reload marker"

: >"$log"; rm -f "$marker"; run MOCK_EXTERNAL=0 bash "$clam" close
[[ ! -s $log ]] || fail "lid close without an external display leaves the panel alone" "$(cat "$log")"
[[ ! -e $marker ]] || fail "no reload marker without an external display"
pass "lid close without an external display leaves the panel to logind"

: >"$log"; printf 'eDP-1\n' >"$marker"; run bash "$clam" open
[[ ! -e $marker ]] || fail "lid open removes the reload marker"
# hl.monitor merges into the panel's existing rule, so only `disabled = false` turns it back on.
grep -qF 'hyprctl eval hl.monitor({ output = "eDP-1", disabled = false })' "$log" ||
  fail "lid open re-enables the panel" "$(cat "$log")"
grep -q '^hyprctl reload' "$log" || fail "lid open reloads so configured monitor rules win"
pass "lid open re-enables the panel and reloads the monitor rules"

: >"$log"; run MOCK_EXTERNAL=1 MOCK_INTERNAL='eDP-1"; os.exit() --' bash "$clam" close
[[ ! -s $log ]] || fail "a connector name that is not plain is never put into Lua" "$(cat "$log")"
pass "an unsafe connector name is refused"

if run bash "$clam" 2>/dev/null; then fail "a missing action is rejected"; fi
pass "a missing action is rejected"
