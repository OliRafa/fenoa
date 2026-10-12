#!/bin/bash

# The image ships no human user: fenoa-firstboot-user.service creates the primary account on the
# first boot of a deployment. When it does not run, the greeter comes up with no account to offer and the
# machine is unreachable through the GUI — so the gating on that unit is load-bearing, and this
# file locks it down.
#
# The failure it was written for: the unit gated on ConditionFirstBoot=yes. systemd counts a boot as
# the first only when /etc/machine-id is absent or reads "uninitialized", and the image then shipped
# an empty one, which does not count: on real hardware the unit never ran, getty kept tty1, and the
# greeter had no user. The image now ships "uninitialized", but the marker gate stays, because
# systemd commits a real ID during the first boot and only the marker lets an aborted prompt or a
# failed useradd retry on the next one.

source "$(dirname "$0")/base-test.sh"

unit="$ROOT/system/platform/usr/lib/systemd/system/fenoa-firstboot-user.service"
helper="$ROOT/system/platform/usr/libexec/fenoa-firstboot-user"

[[ -f $unit ]] || fail "the first-boot user unit ships"
[[ -f $helper ]] || fail "the first-boot user helper ships"

# --- unit gating ------------------------------------------------------------------------------

if grep -q '^ConditionFirstBoot' "$unit"; then
  fail "unit does not gate on ConditionFirstBoot" "$(grep -n '^ConditionFirstBoot' "$unit")"
fi
pass "unit does not gate on ConditionFirstBoot"

unit_marker=$(sed -n 's/^ConditionPathExists=!//p' "$unit")
[[ -n $unit_marker ]] || fail "unit gates on a negative ConditionPathExists marker"
pass "unit gates on a marker path"

# Drift guard. If the two paths ever disagree the bug comes back wearing a different hat: a marker
# the helper never writes makes the unit fight getty for tty1 every boot, and one written somewhere
# the unit does not look makes it provision once and never again.
helper_marker=$(sed -n 's/^marker="\${FENOA_FIRSTBOOT_MARKER:-\(.*\)}"$/\1/p' "$helper")
[[ $helper_marker == "$unit_marker" ]] ||
  fail "unit marker matches the helper default" "unit=$unit_marker helper=${helper_marker:-<unparsed>}"
pass "unit marker matches the helper default ($unit_marker)"

grep -q '^Before=display-manager\.service' "$unit" ||
  fail "unit is ordered before the display manager (else the greeter comes up with no account)"
pass "unit is ordered before the display manager"

grep -q '^WantedBy=multi-user\.target' "$unit" || fail "unit is wired into multi-user.target"
pass "unit is wired into multi-user.target"

grep -q '^TTYPath=/dev/tty1' "$unit" || fail "interactive prompt is bound to tty1"
grep -q '^StandardInput=tty-force' "$unit" || fail "interactive prompt can read from tty1"
pass "interactive prompt is bound to tty1"

# --- helper behaviour -------------------------------------------------------------------------

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"

# HUMAN_USER=1 adds a real uid-1000 account; DYNAMIC_USER=1 adds a systemd DynamicUser= account
# the way nss-systemd surfaces it (never in /etc/passwd, always in getent).
cat >"$mock_bin/getent" <<'SH'
#!/bin/bash
case $1 in
  passwd)
    echo 'root:x:0:0:root:/root:/bin/bash'
    echo 'bin:x:1:1:bin:/bin:/sbin/nologin'
    [[ ${DYNAMIC_USER:-0} == 1 ]] && echo 'speakersafetyd:x:62454:62454:Dynamic User:/:/usr/sbin/nologin'
    [[ ${HUMAN_USER:-0} == 1 ]] && echo 'someone:x:1000:1000::/var/home/someone:/bin/bash'
    ;;
  group) [[ $2 == wheel ]] ;;
esac
exit 0
SH

cat >"$mock_bin/useradd" <<'SH'
#!/bin/bash
printf 'useradd %s\n' "$*" >>"$MOCK_LOG"
exit "${USERADD_RC:-0}"
SH

for cmd in usermod chpasswd passwd; do
  cat >"$mock_bin/$cmd" <<SH
#!/bin/bash
printf '$cmd %s\n' "\$*" >>"\$MOCK_LOG"
exit 0
SH
done

cat >"$mock_bin/shred" <<'SH'
#!/bin/bash
rm -f "${@: -1}"
SH

chmod +x "$mock_bin"/*

conf="$test_tmp/firstboot-user.conf"
marker="$test_tmp/state/firstboot-user.done"
mock_log="$test_tmp/mock.log"
vconsole="$test_tmp/vconsole.conf"   # absent unless a test writes it; never the host's
# A slice of systemd's kbd-model-map: de and ru convert, ua and the other test keymaps do not.
kbd_model_map="$test_tmp/kbd-model-map"
cat >"$kbd_model_map" <<'MAP'
# consolelayout		xlayout	xmodel		xvariant	xoptions
us			us	pc105+inet	-		terminate:ctrl_alt_bksp
de			de	pc105		-		terminate:ctrl_alt_bksp
ru			ru,us	pc105		-		terminate:ctrl_alt_bksp,grp:shifts_toggle,grp_led:scroll
MAP

write_preseed() {
  cat >"$conf" <<'PRESEED'
FENOA_USER=tester
FENOA_USER_FULLNAME="Test User"
FENOA_USER_GROUPS="wheel"
FENOA_USER_PASSWORD=correcthorsebattery
PRESEED
}

run_helper() {
  env PATH="$mock_bin:$PATH" MOCK_LOG="$mock_log" \
    FENOA_FIRSTBOOT_CONF="$conf" FENOA_FIRSTBOOT_MARKER="$marker" \
    FENOA_VCONSOLE_CONF="$vconsole" FENOA_KBD_MODEL_MAP="$kbd_model_map" \
    "$@" bash "$helper" >"$test_tmp/out.log" 2>&1
}

# 1) No human user + preseed: provisions and marks done.
: >"$mock_log"; rm -f "$marker"; write_preseed
run_helper || fail "preseed run succeeds" "$(cat "$test_tmp/out.log")"
grep -q '^useradd .*tester' "$mock_log" || fail "preseed run creates the account" "$(cat "$mock_log")"
pass "preseed run creates the account"
[[ -f $marker ]] || fail "preseed run writes the done marker"
pass "preseed run writes the done marker"
[[ ! -e $conf ]] || fail "preseed holding a password is scrubbed after use"
pass "preseed is scrubbed after use"

# 2) A human user already exists: no-op, but still marks done so the unit stops taking tty1.
: >"$mock_log"; rm -f "$marker"
HUMAN_USER=1 run_helper || fail "run with an existing user succeeds" "$(cat "$test_tmp/out.log")"
grep -q '^useradd' "$mock_log" && fail "run with an existing user creates nothing" "$(cat "$mock_log")"
pass "run with an existing user creates nothing"
[[ -f $marker ]] || fail "run with an existing user still marks done"
pass "run with an existing user still marks done"

# 3) A systemd DynamicUser= account must not read as a human user. speakersafetyd (Asahi speaker
#    protection) runs with DynamicUser= and lands at uid 62454; systemd allocates that range
#    (61184-65519) and nss-systemd shows it in getent. A uid>=1000 && uid<65534 test counts it as a
#    human account, so the helper skipped on a machine with NO human user and the greeter greeted with
#    nothing to log in as. login.defs UID_MAX (60000 on Fedora) is the bound that excludes it.
: >"$mock_log"; rm -f "$marker"; write_preseed
DYNAMIC_USER=1 run_helper || fail "run alongside a DynamicUser account succeeds" "$(cat "$test_tmp/out.log")"
grep -q '^useradd .*tester' "$mock_log" ||
  fail "a DynamicUser account does not count as a human user" "helper skipped; log: $(cat "$test_tmp/out.log")"
pass "a DynamicUser account does not count as a human user"

# ...but a real account in the login.defs range still counts, alongside the dynamic one.
: >"$mock_log"; rm -f "$marker"; write_preseed
DYNAMIC_USER=1 HUMAN_USER=1 run_helper || fail "run with both account kinds succeeds"
grep -q '^useradd' "$mock_log" && fail "a real human user is still detected" "$(cat "$mock_log")"
pass "a real human user is still detected"

# 4) Provisioning FAILS: must NOT mark done, so the next boot retries instead of latching off with
#    no account — the shape of the original bug, reached by a different route.
: >"$mock_log"; rm -f "$marker"; write_preseed
if USERADD_RC=1 run_helper; then
  fail "a failed useradd fails the unit" "$(cat "$test_tmp/out.log")"
fi
pass "a failed useradd fails the unit"
[[ ! -e $marker ]] || fail "a failed run leaves no done marker (so the next boot retries)"
pass "a failed run leaves no done marker"

# 5) Console keymap → XKB layout. For a keymap systemd-firstboot does not convert, vconsole.conf
#    carries a console KEYMAP with no XKB settings; unless kbd-model-map maps it (fenoa/keyboard.lua
#    falls back to that table), the login screen and Hyprland use us while the password is typed in
#    the console keymap. The helper fills in the keymaps it knows, warns about the rest, and never
#    lets this stand in the way of creating the account.
run_keymap() { # run_keymap <vconsole.conf contents, with \n escapes>
  : >"$mock_log"; rm -f "$marker"; write_preseed
  printf '%b' "$1" >"$vconsole"
  run_helper || fail "a run with a console keymap succeeds" "$(cat "$test_tmp/out.log")"
  grep -q '^useradd .*tester' "$mock_log" || fail "the account is still created" "$(cat "$test_tmp/out.log")"
}

run_keymap 'KEYMAP=ua\n'
[[ "$(cat "$vconsole")" == $'KEYMAP=ua\nXKBLAYOUT=ua,us\nXKBMODEL=pc105\nXKBOPTIONS=terminate:ctrl_alt_bksp,grp:shifts_toggle,grp_led:scroll' ]] ||
  fail "an unconverted ua keymap gets ua,us appended" "$(cat "$vconsole")"
pass "an unconverted keymap (ua) gets its XKB layout, model and options appended"

run_keymap 'KEYMAP=bg-cp1251\n'
[[ "$(cat "$vconsole")" == $'KEYMAP=bg-cp1251\nXKBLAYOUT=bg,us\nXKBMODEL=pc105\nXKBVARIANT=phonetic,\nXKBOPTIONS=terminate:ctrl_alt_bksp,grp:shifts_toggle,grp_led:scroll' ]] ||
  fail "bg-cp1251 gets the phonetic variant too" "$(cat "$vconsole")"
pass "a variant is written only when the keymap has one (bg-cp1251 → phonetic)"

run_keymap 'KEYMAP="de_CH-latin1"'
[[ "$(cat "$vconsole")" == $'KEYMAP="de_CH-latin1"\nXKBLAYOUT=ch\nXKBMODEL=pc105\nXKBOPTIONS=terminate:ctrl_alt_bksp' ]] ||
  fail "a quoted keymap on a last line without a newline is read and appended to cleanly" "$(cat "$vconsole")"
pass "a quoted keymap on an unterminated last line is handled"

run_keymap 'KEYMAP=ru\nXKBLAYOUT=ru,us\nXKBMODEL=pc105\nXKBOPTIONS=terminate:ctrl_alt_bksp,grp:shifts_toggle,grp_led:scroll\n'
printf 'KEYMAP=ru\nXKBLAYOUT=ru,us\nXKBMODEL=pc105\nXKBOPTIONS=terminate:ctrl_alt_bksp,grp:shifts_toggle,grp_led:scroll\n' >"$test_tmp/expected"
cmp -s "$vconsole" "$test_tmp/expected" || fail "a keymap systemd already converted is left byte-identical" "$(cat "$vconsole")"
pass "a keymap that already has an XKB layout is left byte-identical"

run_keymap 'KEYMAP=de\n'
printf 'KEYMAP=de\n' >"$test_tmp/expected"
cmp -s "$vconsole" "$test_tmp/expected" || fail "a KEYMAP kbd-model-map converts is left alone" "$(cat "$vconsole")"
if grep -qF 'XKB' "$test_tmp/out.log"; then
  fail "a KEYMAP kbd-model-map converts draws no warning (keyboard.lua maps it)" "$(cat "$test_tmp/out.log")"
fi
pass "a KEYMAP-only file that kbd-model-map converts (de) is left alone, with no warning"

run_keymap 'KEYMAP=xx-unknown\n'
printf 'KEYMAP=xx-unknown\n' >"$test_tmp/expected"
cmp -s "$vconsole" "$test_tmp/expected" || fail "an unknown keymap is left alone" "$(cat "$vconsole")"
grep -qF "console keymap 'xx-unknown' has no XKB equivalent" "$test_tmp/out.log" ||
  fail "an unknown keymap is logged" "$(cat "$test_tmp/out.log")"
pass "an unknown keymap is left alone and logged"

: >"$mock_log"; rm -f "$marker" "$vconsole"; write_preseed
run_helper || fail "a run without vconsole.conf succeeds" "$(cat "$test_tmp/out.log")"
[[ ! -e $vconsole ]] || fail "no vconsole.conf is created when there is none"
pass "without vconsole.conf nothing is created"

: >"$mock_log"; rm -f "$marker"; printf 'KEYMAP=ua\n' >"$vconsole"
HUMAN_USER=1 run_helper || fail "a run with an existing user succeeds"
[[ "$(cat "$vconsole")" == "KEYMAP=ua" ]] || fail "with a human user already there, vconsole.conf is not touched" "$(cat "$vconsole")"
pass "with a human user already there, vconsole.conf is not touched"

# Interactive: the password prompt warns when the session will fall back to us. (read -p prompts
# are not printed without a terminal, so only the note and the outcome are checked.)
: >"$mock_log"; rm -f "$marker" "$conf"; printf 'KEYMAP=xx-unknown\n' >"$vconsole"
run_helper <<<$'tester\n\nhunter22\nhunter22' || fail "an interactive run succeeds" "$(cat "$test_tmp/out.log")"
grep -q '^useradd .*tester' "$mock_log" || fail "the interactive run creates the account" "$(cat "$mock_log")"
grep -qF "Note: the console keymap 'xx-unknown' has no XKB equivalent" "$test_tmp/out.log" &&
  grep -qF 'sudo localectl set-x11-keymap' "$test_tmp/out.log" ||
  fail "the interactive prompt warns that the session will use the US layout" "$(cat "$test_tmp/out.log")"
pass "the interactive prompt warns before the password when the session will use the US layout"

: >"$mock_log"; rm -f "$marker" "$conf"; printf 'KEYMAP=ua\n' >"$vconsole"
run_helper <<<$'tester\n\nhunter22\nhunter22' || fail "an interactive run with a known keymap succeeds"
if grep -qF 'has no XKB equivalent' "$test_tmp/out.log"; then
  fail "no warning when the keymap got its XKB layout" "$(cat "$test_tmp/out.log")"
fi
pass "no warning when the keymap got its XKB layout"

: >"$mock_log"; rm -f "$marker" "$conf"; printf 'KEYMAP=de\n' >"$vconsole"
run_helper <<<$'tester\n\nhunter22\nhunter22' || fail "an interactive run with a converted keymap succeeds"
if grep -qF 'Note:' "$test_tmp/out.log"; then
  fail "no warning for a keymap kbd-model-map converts" "$(cat "$test_tmp/out.log")"
fi
pass "no warning for a keymap kbd-model-map converts (de)"

# A vconsole.conf that cannot be written still never blocks the account, and the note says why the
# layout falls back to us. (root writes through a read-only mode, so only checked unprivileged.)
if (( EUID != 0 )); then
  : >"$mock_log"; rm -f "$marker" "$conf"; printf 'KEYMAP=ua\n' >"$vconsole"; chmod 0444 "$vconsole"
  run_helper <<<$'tester\n\nhunter22\nhunter22' || fail "an interactive run with a read-only vconsole.conf succeeds"
  chmod 0644 "$vconsole"
  grep -q '^useradd .*tester' "$mock_log" || fail "a read-only vconsole.conf does not block the account"
  grep -qF "Note: the XKB layout for the console keymap 'ua' could not be saved" "$test_tmp/out.log" ||
    fail "a failed write is reported as such, not as a missing XKB equivalent" "$(cat "$test_tmp/out.log")"
  pass "a vconsole.conf that cannot be written is reported, and the account is still created"
else
  pass "skipped the read-only vconsole.conf case (root ignores the file mode)"
fi
