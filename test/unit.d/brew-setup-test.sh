#!/bin/bash

# fenoa-brew-setup.service hands Homebrew to the primary user and applies the Brewfile on first
# boot. Homebrew ships PREBUILT in the image (ublue's brew image) and ublue's own brew-setup.service
# unpacks it; this helper only re-owns the prefix and runs `brew bundle`. Four failure classes are
# guarded here; the first three were seen on hardware in the image this was ported from:
#
#  1. Picking the wrong account: `getent passwd` fields are name:passwd:uid:..., and printing $2
#     resolved every machine's primary user to the password placeholder "x".
#  2. Downloading Homebrew's installer at boot: `bash -c "$(curl ...)"` exits 0 when curl fails,
#     so a machine with no brew blamed `brew bundle`. There is no download any more.
#  3. Debris from (2): an EMPTY prefix directory makes ublue's brew-setup.service (gated on
#     ConditionPathExists=!/home/linuxbrew/.linuxbrew) skip the unpack forever. The helper clears
#     an empty prefix and ublue's marker so the unpack can run.
#  4. Running before the network: started from multi-user.target, `brew bundle` ran before Wi-Fi
#     was up (the image masks NetworkManager-wait-online) and failed until the next boot. A timer
#     now starts it, and its condition waits for Homebrew's hosts to answer over HTTPS.

source "$(dirname "$0")/base-test.sh"

units="$ROOT/system/platform/usr/lib/systemd/system"
unit="$units/fenoa-brew-setup.service"
timer="$units/fenoa-brew-setup.timer"
helper="$ROOT/system/platform/usr/libexec/fenoa-brew-setup"
containerfile="$ROOT/images/fenoa/Containerfile"
preset="$ROOT/system/platform/usr/lib/systemd/system-preset/50-fenoa.preset"

[[ -f $unit ]] || fail "the brew setup unit ships"
[[ -f $timer ]] || fail "the brew setup timer ships"
[[ -f $helper ]] || fail "the brew setup helper ships"
pass "the brew setup unit, timer and helper ship"

# --- unit wiring ------------------------------------------------------------------------------

# Started at boot, `brew bundle` runs before Wi-Fi is up (NetworkManager-wait-online is masked) and
# fails until the next boot; on a fresh install Wi-Fi is not even configured yet. A timer starts it
# instead, and again while its condition skips it (Homebrew's hosts do not answer yet).
if grep -qE '^\[Install\]|^(WantedBy|RequiredBy|UpheldBy|Alias|Also)=' "$unit"; then
  fail "the brew setup service has no [Install] section (only its timer starts it)" "$(grep -nE '^\[Install\]|By=' "$unit")"
fi
pass "the brew setup service is static: only its timer starts it"

grep -qE '^OnBootSec=' "$timer" || fail "the timer starts the setup after boot (OnBootSec=)"
grep -qE '^OnUnitInactiveSec=' "$timer" || fail "the timer starts a skipped run again (OnUnitInactiveSec=)"
accuracy=$(sed -n 's/^AccuracySec=//p' "$timer")
[[ $accuracy =~ ^([0-9]+)s$ ]] && (( BASH_REMATCH[1] < 60 )) ||
  fail "the timer sets an AccuracySec= under a minute (the default 1min lets each start slip)" "got: ${accuracy:-<unset>}"
target=$(sed -n 's/^Unit=//p' "$timer")
[[ -z $target || $target == "fenoa-brew-setup.service" ]] || fail "the timer starts fenoa-brew-setup.service" "Unit=$target"
grep -qx 'WantedBy=timers.target' "$timer" || fail "the timer is wired into timers.target"
pass "the timer starts the setup after boot and again while it is skipped (AccuracySec=$accuracy)"

# RemainAfterExit is what ends the timer's retries once a run succeeds.
grep -qx 'Type=oneshot' "$unit" || fail "the brew setup service is a oneshot"
grep -qx 'RemainAfterExit=yes' "$unit" ||
  fail "a successful run stays active (RemainAfterExit=yes), which stops the timer for the boot"
pass "a oneshot that stays active once it succeeds"

# A `brew bundle` that keeps failing (a formula that will not build) must back off, not rebuild every
# 2 minutes all boot. RestartMode=direct is load-bearing: without it each failure makes the unit
# inactive for an instant, the timer's OnUnitInactiveSec= fires on top of the pending restart, and
# its start cuts the delay short and resets the backoff (seen on systemd 259).
restart=$(grep -E '^(Restart|RestartMode|RestartSec|RestartSteps|RestartMaxDelaySec)=' "$unit")
expected=$'Restart=on-failure\nRestartMode=direct\nRestartSec=5min\nRestartSteps=5\nRestartMaxDelaySec=2h'
[[ $restart == "$expected" ]] ||
  fail "a failed run restarts with a growing delay, 5min up to 2h, without the timer cutting in" "got:"$'\n'"$restart"
if grep -qE '^(StartLimitIntervalSec|StartLimitBurst)=' "$unit"; then
  fail "no StartLimit*= overrides (restarts minutes apart never reach the default limit)" "$(grep -nE '^StartLimit' "$unit")"
fi
pass "a failed run backs off (Restart=on-failure, RestartMode=direct, 5min growing to 2h over 5 steps)"

# "Already applied" must be a fast successful run, never a skip: a unit skipped by Condition*= is
# inactive, so the timer would start it every 2 minutes for the rest of every boot.
if grep -qE '^(Condition|Assert)[A-Za-z]*=' "$unit"; then
  fail "no Condition*=/Assert*= (the timer would loop on it)" "$(grep -nE '^(Condition|Assert)' "$unit")"
fi
pass "no Condition*= the timer could loop on"

# Ordering, not Requires=: if either has not happened the helper must say so and a later run
# retries, never be silently skipped. It also holds a timer start back while fenoa-firstboot-user
# waits at its tty1 prompt. Wants= queues the unpack again on every try: a no-op once it is done
# (its ConditionPathExists=! guards), and the unpack itself once the helper has cleared debris.
grep -q '^After=brew-setup\.service' "$unit" ||
  fail "unit is ordered after ublue's brew-setup.service (the unpack)"
grep -q '^Wants=brew-setup\.service' "$unit" ||
  fail "unit wants ublue's brew-setup.service, so every try queues the unpack again"
grep -q '^After=fenoa-firstboot-user\.service' "$unit" ||
  fail "unit is ordered after the primary account is created"
pass "unit wants and is ordered after the unpack, and is ordered after the account"
if grep -qE '^(Requires|BindsTo)=brew-setup\.service' "$unit"; then
  fail "a hard dependency would skip the retry path" "$(grep -nE '^(Requires|BindsTo)=' "$unit")"
fi
pass "the dependency on the unpack is soft (no Requires=/BindsTo=)"

# The network path is what kept failing. It must be gone, not merely guarded. Comments are
# excluded: the helper documents the bug it used to have, and naming it is not doing it.
if grep -vE '^[[:space:]]*#' "$helper" | grep -qE 'install\.sh|curl|wget'; then
  fail "the helper no longer downloads anything" \
    "$(grep -vE '^[[:space:]]*#' "$helper" | grep -nE 'install\.sh|curl|wget')"
fi
pass "the helper no longer downloads anything"

# Drift guard: the unit promises "first boot", which holds only if the helper writes the stamp path
# it also reads, and the unit's condition looks for that same path.
helper_stamp=$(sed -n 's/^STAMP="\${FENOA_BREW_STAMP:-\(.*\)}"$/\1/p' "$helper")
[[ -n $helper_stamp ]] || fail "helper has a parseable stamp default"
pass "helper stamps completion at $helper_stamp"

# --- the condition: done, or online ---------------------------------------------------------------

# Run the unit's own ExecCondition script, with the stamp and fenoa-online pointed into the sandbox.
condition=$(sed -n "s/^ExecCondition=\/usr\/bin\/bash -c '\(.*\)'$/\1/p" "$unit")
[[ -n $condition ]] || fail "the unit has a bash ExecCondition" "$(grep -n '^ExecCondition' "$unit")"
[[ $condition == *"$helper_stamp"* ]] ||
  fail "the condition checks the stamp the helper writes ($helper_stamp)" "$condition"
[[ $condition == *"/usr/libexec/fenoa-online formulae.brew.sh ghcr.io"* ]] ||
  fail "the condition waits for Homebrew's API and bottle hosts to answer" "$condition"
pass "the condition checks the helper's stamp, else fenoa-online formulae.brew.sh ghcr.io"

cond_tmp=$(mktemp -d)
trap 'rm -rf "$cond_tmp"' EXIT
cond_stamp="$cond_tmp/brew-setup-done"
cat >"$cond_tmp/fenoa-online" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"${0%/*}/online.log"
exit "${ONLINE_RC:-0}"
SH
chmod +x "$cond_tmp/fenoa-online"
script=${condition//"$helper_stamp"/$cond_stamp}
script=${script//\/usr\/libexec\/fenoa-online/$cond_tmp/fenoa-online}
run_condition() { rm -f "$cond_tmp/online.log"; env ONLINE_RC="${ONLINE_RC:-0}" bash -c "$script"; }

: >"$cond_stamp"
ONLINE_RC=1 run_condition || fail "a stamped machine passes the condition at once, network or not"
[[ ! -e $cond_tmp/online.log ]] || fail "a stamped machine does not wait for the network"
pass "applied already: the condition passes at once (one instant no-op run, then the timer stops)"

rm -f "$cond_stamp"
ONLINE_RC=1 run_condition; rc=$?
(( rc == 1 )) || fail "not applied and offline: the condition skips (1)" "exit $rc"
[[ $(cat "$cond_tmp/online.log" 2>/dev/null) == "formulae.brew.sh ghcr.io" ]] ||
  fail "not applied: the condition asks fenoa-online about Homebrew's hosts" "$(cat "$cond_tmp/online.log" 2>/dev/null)"
ONLINE_RC=0 run_condition || fail "not applied and online: the condition passes"
ONLINE_RC=255 run_condition; rc=$?
(( rc == 255 )) || fail "a broken fenoa-online still fails the unit (255 passes through)" "exit $rc"
pass "not applied yet: the condition is fenoa-online's verdict (skip offline, run online, fail when broken)"
rm -rf "$cond_tmp"

# --- build wiring ---------------------------------------------------------------------------------

enabled=$(containerfile_units enable <"$containerfile")
grep -qx 'fenoa-brew-setup\.timer' <<<"$enabled" || fail "the Containerfile enables fenoa-brew-setup.timer" "$enabled"
grep -qx 'fenoa-brew-setup\.service' <<<"$enabled" &&
  fail "the Containerfile does not enable the brew setup service itself (it would run before the network)"
grep -qx 'enable fenoa-brew-setup.timer' "$preset" || fail "50-fenoa.preset enables the brew setup timer"
grep -qE '^(enable|disable) fenoa-brew-setup\.service$' "$preset" &&
  fail "50-fenoa.preset has no line for the static brew setup service" "$(grep -n 'fenoa-brew-setup' "$preset")"
pass "the Containerfile and 50-fenoa.preset enable the timer, not the static service"

# --- harness ------------------------------------------------------------------------------------

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"

# getent as nss-systemd presents it: real accounts from /etc/passwd, plus DynamicUser= accounts
# that exist only in the name-service layer.
cat >"$mock_bin/getent" <<'SH'
#!/bin/bash
case $1 in
  passwd)
    echo 'root:x:0:0:root:/root:/bin/bash'
    echo 'bin:x:1:1:bin:/bin:/sbin/nologin'
    [[ ${DYNAMIC_USER:-0} == 1 ]] && echo 'speakersafetyd:x:62454:62454:Dynamic User:/:/usr/sbin/nologin'
    [[ ${HUMAN_USER:-0} == 1 ]] && echo 'rafael:x:1000:1000:Rafael:/var/home/rafael:/bin/bash'
    [[ ${SECOND_USER:-0} == 1 ]] && echo 'later:x:1001:1001::/var/home/later:/bin/bash'
    ;;
esac
exit 0
SH

# stat reports whoever OWNS_PREFIX says, so the re-own path can be driven without root.
cat >"$mock_bin/stat" <<'SH'
#!/bin/bash
[[ $1 == -c && $2 == %u ]] && { printf '%s
' "${OWNS_PREFIX:-1000}"; exit 0; }
exit 1
SH

cat >"$mock_bin/chown" <<'SH'
#!/bin/bash
printf 'chown %s
' "$*" >>"$MOCK_LOG"
exit "${CHOWN_RC:-0}"
SH

# su RUNS the command it is handed rather than discarding it, so the command string the helper
# builds — the shellenv eval and the bundle call — is genuinely executed. A mock that only recorded
# its arguments is how the old `bash -c "$(curl …)"` bug survived a passing test suite.
cat >"$mock_bin/su" <<'SH'
#!/bin/bash
printf 'su %s
' "$*" >>"$MOCK_LOG"
cmd=""
while [[ $# -gt 0 ]]; do
  [[ $1 == -c ]] && { cmd="$2"; shift 2; continue; }
  shift
done
[[ -n $cmd ]] || exit 0
bash -c "$cmd"
SH

chmod +x "$mock_bin"/*

brewfile="$test_tmp/Brewfile"
printf 'brew "neovim"\n' >"$brewfile"
stamp="$test_tmp/state/brew-setup-done"
login_defs="$test_tmp/login.defs"
printf 'UID_MIN 1000\nUID_MAX 60000\n' >"$login_defs"
mock_log="$test_tmp/mock.log"
prefix="$test_tmp/linuxbrew"

# unpack fakes what ublue's brew-setup.service leaves behind: a working brew under the prefix.
unpack() {
  mkdir -p "$prefix/bin"
  printf '#!/bin/bash\n[ "$1" = bundle ] && echo "bundle ran"\nexit 0\n' >"$prefix/bin/brew"
  chmod +x "$prefix/bin/brew"
}
reset() { : >"$mock_log"; rm -f "$stamp"; rm -rf "$prefix"; }

run_helper() {
  env PATH="$mock_bin:$PATH" MOCK_LOG="$mock_log" \
    FENOA_BREW_FILE="$brewfile" FENOA_BREW_STAMP="$stamp" \
    FENOA_BREW_PREFIX="$prefix" FENOA_LOGIN_DEFS="$login_defs" \
    "$@" bash "$helper" >"$test_tmp/out.log" 2>&1
}

# --- 1) the account name ------------------------------------------------------------------------

reset; unpack
HUMAN_USER=1 run_helper || fail "a normal run succeeds" "$(cat "$test_tmp/out.log")"
grep -q "applying .* as rafael" "$test_tmp/out.log" ||
  fail "helper resolves the primary user by name" "$(cat "$test_tmp/out.log")"
pass "helper resolves the primary user by name"

grep -qE '^su .*\brafael\b' "$mock_log" ||
  fail "the account name is what reaches su" "$(cat "$mock_log")"
pass "the account name is what reaches su"

# "x" is every passwd row's second field, so it can never be a real account.
if grep -qE "(^| )x( |$)" "$mock_log" || grep -q " as x" "$test_tmp/out.log"; then
  fail "the passwd placeholder never reaches a command" "$(cat "$mock_log")"
fi
pass "the passwd placeholder never reaches a command"

grep -q "bundle ran" "$test_tmp/out.log" ||
  fail "the Brewfile is actually applied" "$(cat "$test_tmp/out.log")"
pass "the Brewfile is actually applied"
[[ -f $stamp ]] || fail "a successful run stamps done" "$(cat "$test_tmp/out.log")"
pass "a successful run stamps done"

# --- 2) which account wins ----------------------------------------------------------------------

reset; unpack
HUMAN_USER=1 SECOND_USER=1 run_helper || fail "run with two users succeeds" "$(cat "$test_tmp/out.log")"
grep -q "applying .* as rafael" "$test_tmp/out.log" ||
  fail "the lowest uid in range is chosen" "$(cat "$test_tmp/out.log")"
pass "the lowest uid in range is chosen"

# A DynamicUser= account is not a human. speakersafetyd (Apple Silicon speaker protection) lands at
# uid 62454, which systemd allocates from 61184-65519 and nss-systemd surfaces in getent.
reset; unpack
DYNAMIC_USER=1 run_helper || fail "run alongside a DynamicUser account succeeds" "$(cat "$test_tmp/out.log")"
grep -q "no primary user yet" "$test_tmp/out.log" ||
  fail "a DynamicUser account is not treated as the primary user" "$(cat "$test_tmp/out.log")"
pass "a DynamicUser account is not treated as the primary user"
[[ ! -f $stamp ]] || fail "a run with no human user leaves no stamp, so it retries next boot"
pass "a run with no human user leaves no stamp"

reset; unpack
run_helper || fail "run with no users succeeds" "$(cat "$test_tmp/out.log")"
[[ ! -s $mock_log ]] || fail "no commands run without a primary user" "$(cat "$mock_log")"
pass "no commands run without a primary user"

# --- 3) ownership -------------------------------------------------------------------------------

# ublue's brew-setup.service chowns the unpacked tree to a hardcoded 1000:1000. That is right on
# nearly every machine but it is an assumption, and a prefix owned by the wrong uid is a brew that
# cannot install anything. Re-own to the account actually detected.
reset; unpack
HUMAN_USER=1 OWNS_PREFIX=1000 run_helper || fail "run with matching ownership succeeds" "$(cat "$test_tmp/out.log")"
grep -q '^chown' "$mock_log" &&
  fail "ownership already correct means no chown" "$(cat "$mock_log")"
pass "ownership already correct means no chown"

reset; unpack
HUMAN_USER=1 OWNS_PREFIX=4242 run_helper || fail "run with wrong ownership succeeds" "$(cat "$test_tmp/out.log")"
grep -qE '^chown .*rafael' "$mock_log" ||
  fail "a mismatched owner is re-owned to the detected user" "$(cat "$mock_log")"
pass "a mismatched owner is re-owned to the detected user"
grep -q "was uid 4242" "$test_tmp/out.log" ||
  fail "the re-own says what it found" "$(cat "$test_tmp/out.log")"
pass "the re-own says what it found"

reset; unpack
HUMAN_USER=1 OWNS_PREFIX=4242 CHOWN_RC=1 run_helper &&
  fail "a failed chown fails the run" "$(cat "$test_tmp/out.log")"
pass "a failed chown fails the run"
[[ ! -f $stamp ]] || fail "a failed chown leaves no stamp"
pass "a failed chown leaves no stamp"

# --- 4) debris from the old runtime install must not block the unpack -----------------------------

marker="$test_tmp/dot-linuxbrew"

run_helper_m() { FENOA_BREW_MARKER="$marker" run_helper "$@"; }

# The hardware case: an empty prefix, exactly what `install -d` left behind. It must be cleared so
# brew-setup.service's ConditionPathExists=! can pass on the next try (the unit wants it).
reset; mkdir -p "$prefix"; : >"$marker"
HUMAN_USER=1 run_helper_m &&
  fail "an empty prefix fails the run" "$(cat "$test_tmp/out.log")"
pass "an empty prefix fails the run"
grep -q "holds no Homebrew — clearing it" "$test_tmp/out.log" ||
  fail "the empty prefix is reported as debris" "$(cat "$test_tmp/out.log")"
pass "the empty prefix is reported as debris"
[[ ! -e $prefix ]] || fail "the empty prefix is removed so the unpack can run on the next try"
pass "the empty prefix is removed"
[[ ! -e $marker ]] || fail "ublue's marker is cleared too — it was claiming a done unpack"
pass "ublue's /etc/.linuxbrew marker is cleared too"

# A REAL install must never be cleared, however this helper is feeling about it. bin/brew in the
# shipped tree is a symlink, so -e (not -f) is what decides.
reset; mkdir -p "$prefix/bin"; ln -s /nonexistent "$prefix/bin/brew"
HUMAN_USER=1 run_helper_m &&
  fail "a prefix with bin/brew fails (brew is not executable) but is not cleared" "$(cat "$test_tmp/out.log")"
# -L, not -e: the link is deliberately dangling here, and -e follows it — the same blind spot the
# helper itself had to be taught about.
[[ -L $prefix/bin/brew ]] || fail "a prefix holding bin/brew must never be cleared"
pass "a prefix holding bin/brew (even a symlink) is never cleared"
grep -q "clearing it" "$test_tmp/out.log" &&
  fail "a prefix holding bin/brew must not be called debris" "$(cat "$test_tmp/out.log")"
pass "a prefix holding bin/brew is not called debris"

reset; mkdir -p "$prefix/Homebrew/Library"
HUMAN_USER=1 run_helper_m && fail "a prefix with Homebrew/ still fails without bin/brew"
[[ -d $prefix/Homebrew ]] || fail "a prefix holding Homebrew/ must never be cleared"
pass "a prefix holding Homebrew/ is never cleared"

# A working install is untouched and proceeds normally.
reset; unpack; : >"$marker"
HUMAN_USER=1 run_helper_m || fail "a working prefix still succeeds" "$(cat "$test_tmp/out.log")"
[[ -x $prefix/bin/brew ]] || fail "a working prefix survives"
[[ -e $marker ]] || fail "a working prefix leaves ublue's marker alone"
pass "a working prefix is untouched, marker included"

# --- 5) the unpack must have happened -------------------------------------------------------------

# Homebrew ships in the image now, so a missing prefix means ublue's brew-setup.service has not run
# or has failed. That must be named, not rediscovered as "brew: command not found" from a login
# shell two commands later — which is exactly how the old download failure presented.
reset
HUMAN_USER=1 run_helper &&
  fail "a missing brew fails the run" "$(cat "$test_tmp/out.log")"
pass "a missing brew fails the run"
grep -q "brew-setup.service has not unpacked" "$test_tmp/out.log" ||
  fail "the failure names the unpack" "$(cat "$test_tmp/out.log")"
pass "the failure names the unpack"
grep -q "brew bundle failed" "$test_tmp/out.log" &&
  fail "a missing brew never reaches brew bundle" "$(cat "$test_tmp/out.log")"
pass "a missing brew never reaches brew bundle"
[[ ! -f $stamp ]] || fail "a missing brew leaves no stamp, so the timer retries it"
pass "a missing brew leaves no stamp"

# --- 6) idempotence -----------------------------------------------------------------------------

reset; unpack; mkdir -p "$(dirname "$stamp")"; : >"$stamp"
HUMAN_USER=1 run_helper || fail "a stamped run succeeds" "$(cat "$test_tmp/out.log")"
[[ ! -s $mock_log ]] || fail "a stamped run does nothing" "$(cat "$mock_log")"
pass "a stamped run does nothing"
