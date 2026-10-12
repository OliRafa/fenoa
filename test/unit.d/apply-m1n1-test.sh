#!/bin/bash

# fenoa-apply-m1n1 refreshes m1n1 stage 2 + the devicetree for the running kernel. On an atomic
# install it failed every time, and this file pins the reason.
#
# update-m1n1 is a distro script running `set -e`, and line 70 is:
#     gzip -c "$U_BOOT" >>"${TARGET}.new"
# Every file in an ostree/composefs deployment has mtime 0 (timestamps are normalised at commit).
# GNU gzip calls that "file timestamp out of range for gzip format", warns, and exits 2 — so `set -e`
# kills update-m1n1 before boot.bin is written. Observed on hardware; the machine kept a stale
# devicetree, which breaks hardware the moment a kernel ships a changed one.
#
# It also pins when the refresh runs at all: only on a boot that came through m1n1.

source "$(dirname "$0")/base-test.sh"

helper="$ROOT/system/platform/usr/libexec/fenoa-apply-m1n1"
[[ -f $helper ]] || fail "the apply-m1n1 helper ships"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

blob="$test_tmp/u-boot-nodtb.bin"
head -c 2048 /dev/urandom >"$blob"
touch -d @0 "$blob" || fail "can set an mtime of 0 for the test fixture"

# The premise. If a future gzip stops exiting non-zero here the workaround becomes redundant rather
# than wrong, so report instead of failing — but the assertions below must still hold.
if gzip -c "$blob" >/dev/null 2>&1; then
  pass "gzip no longer rejects a zero mtime on this host (workaround now redundant, still correct)"
else
  pass "gzip rejects a zero mtime — the failure mode this helper works around"
fi

FENOA_APPLY_M1N1_LIB=1 source "$helper"

staged=$(stage_gzip_safe_uboot "$blob") || fail "stage_gzip_safe_uboot succeeds"
[[ -f $staged ]] || fail "stage_gzip_safe_uboot produces a file" "got: ${staged:-<empty>}"
pass "stage_gzip_safe_uboot produces a file"

cmp -s "$blob" "$staged" || fail "the staged copy is byte-identical to the blob"
pass "the staged copy is byte-identical to the blob"

# The point of the whole exercise: gzip must accept the copy.
if gzip -c "$staged" >/dev/null 2>&1; then
  pass "gzip accepts the staged copy (exit 0, no warning)"
else
  fail "gzip accepts the staged copy" "gzip still exits $? — mtime: $(stat -c %Y "$staged" 2>/dev/null)"
fi

(( $(stat -c %Y "$staged" 2>/dev/null || echo 0) > 0 )) || fail "the staged copy has a real mtime"
pass "the staged copy has a real mtime"

rm -rf "$(dirname "$staged")"

# And the copy has to actually reach update-m1n1: it reads a fixed path, so the helper bind-mounts
# the staged file over the original. Without this the staging above would be dead code.
grep -q 'mount --bind' "$helper" || fail "the helper bind-mounts the staged copy over the blob"
grep -q 'unshare --mount' "$helper" || fail "the bind mount is confined to a private namespace"
grep -q 'run_update_m1n1' "$helper" || fail "the refresh path calls update-m1n1 through the wrapper"
pass "the staged copy is bind-mounted over the blob for update-m1n1"

# --- only on a boot that came through m1n1 --------------------------------------------------------

# update-m1n1 ships in every image, so its presence cannot tell an Asahi boot from any other. The
# devicetree property m1n1 sets (the ESP update-m1n1 writes to) can; the unit and the helper's
# manual-run guard must both check it, and the same path.
unit="$ROOT/system/platform/usr/lib/systemd/system/fenoa-apply-m1n1.service"
esp_node=/proc/device-tree/chosen/asahi,efi-system-partition
grep -qx "ConditionPathExists=$esp_node" "$unit" || fail "the unit only runs on a boot that came through m1n1"
helper_node=$(sed -n 's/^esp_node="\${FENOA_ASAHI_ESP_NODE:-\(.*\)}"$/\1/p' "$helper")
[[ $helper_node == "$esp_node" ]] ||
  fail "the helper checks the same node as the unit" "unit=$esp_node helper=${helper_node:-<unparsed>}"
pass "the unit and the helper both require m1n1's devicetree node ($esp_node)"

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"
cat >"$stub_bin/update-m1n1" <<'SH'
#!/bin/bash
echo update-m1n1 >>"$CALLS"
SH
chmod +x "$stub_bin/update-m1n1"

run_apply() { # run_apply <devicetree node path>; UBOOT_BLOB points nowhere, so no mount namespace
  env -u FENOA_APPLY_M1N1_LIB -u FENOA_M1N1_AUTOREBOOT -u FENOA_FWEXTRACT \
    PATH="$stub_bin:$PATH" CALLS="$test_tmp/calls" FENOA_ASAHI_ESP_NODE="$1" \
    FENOA_STATE_DIR="$test_tmp/state" UBOOT_BLOB="$test_tmp/no-such-blob" \
    bash "$helper" >"$test_tmp/out.log" 2>&1
}

rm -rf "$test_tmp/calls" "$test_tmp/state"
run_apply "$test_tmp/no-such-node" || fail "without m1n1's node the helper exits 0" "$(cat "$test_tmp/out.log")"
[[ ! -e $test_tmp/calls ]] || fail "without m1n1's node update-m1n1 is not run" "$(cat "$test_tmp/calls")"
[[ ! -e $test_tmp/state ]] || fail "without m1n1's node no stamp directory is created"
grep -qF 'not booted through m1n1' "$test_tmp/out.log" || fail "the skip says why" "$(cat "$test_tmp/out.log")"
pass "without m1n1's node the helper skips, says why, and never runs update-m1n1"

: >"$test_tmp/asahi,efi-system-partition"
run_apply "$test_tmp/asahi,efi-system-partition" || fail "with m1n1's node the refresh succeeds" "$(cat "$test_tmp/out.log")"
[[ "$(cat "$test_tmp/calls" 2>/dev/null)" == "update-m1n1" ]] || fail "with m1n1's node update-m1n1 runs once"
[[ "$(cat "$test_tmp/state/m1n1-applied" 2>/dev/null)" == "$(uname -r)" ]] ||
  fail "a successful refresh stamps the running kernel"
pass "with m1n1's node update-m1n1 runs and the running kernel is stamped"
