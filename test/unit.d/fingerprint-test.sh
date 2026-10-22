#!/bin/bash

# Fingerprint authentication for sudo and polkit: /usr/lib/pam.d/fenoa-fingerprint, which both stacks
# include in front of their password, tries pam_fprintd unless fenoa-lid-closed says the lid is shut.
# What has to hold, since it only shows on real hardware: the lid check reads the ACPI lid and calls
# anything it cannot read open (the reader is tried, the password still follows); the stack skips
# exactly pam_fprintd on a shut lid and lets a match end the caller's stack (include, never
# substack); the build wires it into sudo and polkit-1 only, so the login screen and tty logins stay
# password-only.

source "$(dirname "$0")/base-test.sh"

overlay="$ROOT/system/platform"
helper="$overlay/usr/libexec/fenoa-lid-closed"
stack="$overlay/usr/lib/pam.d/fenoa-fingerprint"
containerfile="$ROOT/images/fenoa/Containerfile"

[[ -x $helper ]] || fail "fenoa-lid-closed ships, executable"
[[ -f $stack ]] || fail "fenoa-fingerprint ships"
pass "fenoa-lid-closed and the fenoa-fingerprint PAM stack ship"

# --- the lid check ------------------------------------------------------------------------------

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

# lid_status LID_DIR: fenoa-lid-closed's exit status against a fake /proc/acpi/button/lid.
lid_status() {
  local status=0
  FENOA_ACPI_LID="$1" "$helper" >/dev/null 2>&1 || status=$?
  echo "$status"
}

# The kernel's own format: "state:      open".
mkdir -p "$test_tmp/open/LID0" "$test_tmp/closed/LID0" "$test_tmp/two/LID0" "$test_tmp/two/LID1" "$test_tmp/empty"
printf 'state:      open\n' >"$test_tmp/open/LID0/state"
printf 'state:      closed\n' >"$test_tmp/closed/LID0/state"
printf 'state:      open\n' >"$test_tmp/two/LID0/state"
printf 'state:      closed\n' >"$test_tmp/two/LID1/state"

[[ $(lid_status "$test_tmp/open") == "1" ]] || fail "an open lid exits 1"
pass "an open lid exits 1 (the reader is tried)"
[[ $(lid_status "$test_tmp/closed") == "0" ]] || fail "a shut lid exits 0"
pass "a shut lid exits 0 (the reader is skipped)"
[[ $(lid_status "$test_tmp/two") == "0" ]] || fail "a shut lid among several exits 0"
pass "a shut lid among several exits 0"
[[ $(lid_status "$test_tmp/empty") == "1" ]] || fail "a machine without an ACPI lid exits 1"
[[ $(lid_status "$test_tmp/missing") == "1" ]] || fail "a missing lid directory exits 1"
pass "a machine without an ACPI lid (a desktop) exits 1"

# --- the PAM stack ------------------------------------------------------------------------------

rules=$(sed -e 's/#.*//' "$stack" | awk 'NF')
env_rule=$(sed -n 1p <<<"$rules")
gate_rule=$(sed -n 2p <<<"$rules")
fprintd_rule=$(sed -n 3p <<<"$rules")
(( $(wc -l <<<"$rules") == 3 )) || fail "fenoa-fingerprint holds exactly pam_env, the lid check and pam_fprintd" "$rules"

# A match ends pam_setcred's pass too, before system-auth's pam_env.
read -r -a env <<<"$env_rule"
[[ ${env[0]} == "auth" && ${env[1]} == "required" && ${env[2]} == "pam_env.so" ]] ||
  fail "pam_env comes first, required, as in system-auth" "$env_rule"
pass "pam_env comes first, so a match still sets the environment"

read -r -a gate <<<"$gate_rule"
[[ ${gate[0]} == "auth" && ${gate[1]} == "[success=1" && ${gate[2]} == "default=ignore]" ]] ||
  fail "the lid check skips exactly the next rule on success and is ignored otherwise" "$gate_rule"
[[ ${gate[3]} == "pam_exec.so" && ${gate[4]} == "quiet" && ${gate[5]} == "quiet_log" ]] ||
  fail "the lid check runs through pam_exec, quiet and quiet_log (no exit status on every open-lid prompt)" "$gate_rule"
[[ ${gate[6]} == "/usr/libexec/fenoa-lid-closed" && -x $overlay${gate[6]} ]] ||
  fail "the lid check runs the shipped fenoa-lid-closed" "$gate_rule"
pass "the lid check runs fenoa-lid-closed through pam_exec, silently, and can only skip the next rule"

read -r -a fprintd <<<"$fprintd_rule"
[[ ${fprintd[0]} == "auth" && ${fprintd[1]} == "sufficient" && ${fprintd[2]} == "pam_fprintd.so" ]] ||
  fail "pam_fprintd follows the lid check directly, sufficient" "$fprintd_rule"
pass "pam_fprintd follows the lid check directly, sufficient (a match ends the stack, a miss falls through)"

# --- wiring: sudo and polkit-1 only, by include --------------------------------------------------

p4b=$(sed -n '/^# P4b)/,/^# P5)/p' "$containerfile")
[[ -n $p4b ]] || fail "the Containerfile has a P4b step before P5"
grep -qF 'for f in /etc/pam.d/sudo /usr/lib/pam.d/polkit-1; do' <<<"$p4b" ||
  fail "P4b wires sudo and polkit-1"
grep -qF 's//auth       include      fenoa-fingerprint\n&/' <<<"$p4b" ||
  fail "P4b inserts an include of fenoa-fingerprint in front of the first auth line"
grep -qF '"auth include fenoa-fingerprint"' <<<"$p4b" ||
  fail "P4b checks that the include is each file's first auth line"
pass "P4b includes fenoa-fingerprint at the top of sudo's and polkit-1's auth stacks, and checks it"

if grep -rqE 'substack[[:space:]]+fenoa-fingerprint' "$containerfile" "$ROOT/system"; then
  fail "fenoa-fingerprint is never a substack (a match would not end the caller's stack)"
fi
if grep -qE '^[^#]*authselect[^#]*with-fingerprint' "$containerfile"; then
  fail "the build does not enable authselect's with-fingerprint (it reaches the login screen)"
fi
others=$(find "$ROOT/system" -path '*/pam.d/*' -type f ! -path "$stack" -exec grep -lE 'fenoa-fingerprint|pam_fprintd' {} + || true)
[[ -z $others ]] || fail "no other PAM stack in the overlays asks for a fingerprint" "$others"
pass "the login screen and tty logins stay password-only (no substack, no with-fingerprint, no other stack)"

copy_line=$(grep -n '^COPY system/platform/ /' "$containerfile" | head -1 | cut -d: -f1)
p4b_line=$(grep -n '^# P4b)' "$containerfile" | cut -d: -f1)
(( copy_line < p4b_line )) || fail "P4b runs after the overlay ships fenoa-fingerprint"
pass "P4b runs after the platform overlay is copied"

# --- packages -----------------------------------------------------------------------------------

platform_packages=$(sed 's/#.*//' "$ROOT/packages/platform.packages" | awk 'NF{print $1}')
for p in fprintd fprintd-pam; do
  grep -qx "$p" <<<"$platform_packages" || fail "platform.packages installs $p"
done
pass "the platform layer installs fprintd and its PAM module"
