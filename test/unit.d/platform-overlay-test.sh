#!/bin/bash

# Static checks on the platform layer that only fail on real hardware if they regress: the Apple HID
# early-load fix has to reach the initramfs, which only happens if its drop-ins are in the image
# before images/fenoa/Containerfile rebuilds it; the units the Containerfile enables have to exist;
# and nothing from Omarchy may leak back in.

source "$(dirname "$0")/base-test.sh"

overlay="$ROOT/system/platform"
containerfile="$ROOT/images/fenoa/Containerfile"
packages="$ROOT/packages/platform.packages"

# --- Apple HID: modprobe + dracut drop-ins ------------------------------------------------------

grep -qx 'options hid_apple fnmode=1' "$overlay/usr/lib/modprobe.d/fenoa-apple.conf" ||
  fail "hid_apple fnmode=1 is configured"
grep -qE '^force_drivers\+=" hid_apple hid_magicmouse "$' "$overlay/usr/lib/dracut/dracut.conf.d/90-fenoa-apple-hid.conf" ||
  fail "dracut forces hid_apple + hid_magicmouse into the initramfs"
pass "the Apple HID modprobe and dracut drop-ins are present"

# The overlay COPY must come before the initramfs rebuild, or the drop-ins never reach it. Compare
# line numbers within the platform stage.
copy_line=$(grep -n '^COPY system/platform/ /' "$containerfile" | head -1 | cut -d: -f1)
dracut_line=$(grep -n 'dracut --force' "$containerfile" | head -1 | cut -d: -f1)
[[ -n $copy_line && -n $dracut_line ]] || fail "the Containerfile copies the overlay and rebuilds the initramfs"
(( copy_line < dracut_line )) ||
  fail "the platform overlay is copied before the initramfs rebuild" "COPY at $copy_line, dracut at $dracut_line"
pass "the platform overlay is copied before the initramfs rebuild"

# hid-magicmouse is built into both the stock kernel-16k and the fairydust kernel while hid-apple is
# a module. The build-time initramfs check must accept a built-in driver, or it rejects every build.
for f in "$containerfile" "$ROOT/images/fairydust/Containerfile"; do
  [[ -f $f ]] || continue
  grep -q 'modules.builtin' "$f" || fail "${f#"$ROOT"/} accepts built-in HID drivers in its initramfs check"
done
pass "the initramfs checks accept built-in HID drivers"

# --- units the Containerfile enables exist ------------------------------------------------------

while read -r unit; do
  [[ -f $overlay/usr/lib/systemd/system/$unit ]] || fail "enabled unit ships: $unit"
done < <(grep -oE 'fenoa-[a-z0-9-]+\.(service|timer)' "$containerfile" | sort -u)
pass "every fenoa-* unit the Containerfile enables ships in the overlay"

for f in "$overlay"/usr/lib/systemd/system/fenoa-*.service; do
  grep -qE '^ExecStart=' "$f" || fail "$(basename "$f") has an ExecStart"
  exec_path=$(sed -n 's/^ExecStart=\(\/usr\/[^ ]*\).*/\1/p' "$f" | head -1)
  if [[ $exec_path == /usr/libexec/fenoa-* || $exec_path == /usr/bin/fenoa-* ]]; then
    [[ -f $overlay$exec_path ]] || fail "$(basename "$f") runs a helper that ships: $exec_path"
  fi
done
pass "every fenoa-* service has an ExecStart whose helper ships"

# --- presets: a first boot keeps every unit as built --------------------------------------------

platform_stage=$(sed -n '/^FROM .* AS platform$/,/^FROM platform AS desktop$/p' "$containerfile")
[[ -n $platform_stage ]] || fail "the Containerfile has a platform stage"
[[ -n $(printf '%s\n' "$platform_stage" | containerfile_units enable) ]] ||
  fail "the platform stage's systemctl enables can be read (else the coverage check proves nothing)"
check_preset "$overlay/usr/lib/systemd/system-preset/50-fenoa.preset" "$platform_stage"
pass "50-fenoa.preset covers every unit the platform stage enables or disables, read before Fedora's"

# Fedora's 90-default.preset enables sshd; first match wins, so this line keeps it off.
grep -qx 'disable sshd.service' "$overlay/usr/lib/systemd/system-preset/50-fenoa.preset" ||
  fail "50-fenoa.preset disables sshd.service"
pass "50-fenoa.preset disables sshd"

check_machine_id_last platform "$platform_stage"
pass "the platform stage ships /etc/machine-id as uninitialized, after its package installs (first boot is detected)"

boottest="$ROOT/images/boottest/Containerfile"
installed=$(sed -n 's|^COPY images/boottest/fenoa-boottest.preset /usr/lib/systemd/system-preset/\(.*\)$|\1|p' "$boottest")
[[ -n $installed ]] || fail "the boottest image installs its preset"
check_preset "$ROOT/images/boottest/fenoa-boottest.preset" "$(cat "$boottest")" "$installed"
pass "the boottest image's preset ($installed) covers the unit it enables"

grep -qF 'systemctl disable sshd.service' "$containerfile" || fail "the Containerfile disables sshd"
grep -qF -- '--remove-service-from-zone=ssh' "$containerfile" ||
  fail "the Containerfile removes ssh from the default firewalld zone"
pass "the Containerfile disables sshd and closes ssh in the default firewalld zone"

# --- package list hygiene -----------------------------------------------------------------------

dupes=$(sed 's/#.*//' "$packages" | awk 'NF{print $1}' | sort | uniq -d)
[[ -z $dupes ]] || fail "platform.packages has no duplicates" "$dupes"
pass "platform.packages has no duplicates"

if sed 's/#.*//' "$packages" | awk 'NF{print $1}' | grep -qxE 'quickshell|sddm|hyprland.*|noctalia.*|greetd'; then
  fail "the platform layer carries no desktop packages"
fi
pass "the platform layer carries no desktop packages"

# --- no Omarchy, consistent shebangs ------------------------------------------------------------

# The fairydust kernel is consumed from its own repo's image, ghcr.io/olirafa/omarchy-fairydust-kernel;
# that name is the only allowed mention (the smoke tests under hack/ assert Omarchy is absent).
leaks=$(grep -rniE 'omarchy' "$ROOT/system" "$ROOT/images" "$ROOT/packages" 2>/dev/null | grep -v 'omarchy-fairydust-kernel' | grep -v '/hack/' || true)
[[ -z $leaks ]] || fail "no Omarchy references in the image sources" "$leaks"
pass "no Omarchy references in the image sources"

while IFS= read -r script; do
  first=$(head -n1 "$ROOT/$script")
  [[ $first == "#!/bin/bash" ]] || fail "$script uses #!/bin/bash" "got: $first"
done < <("$ROOT/test/shell-files" | grep -vE '^deploy/lib/|/profile.d/|^test/unit.d/base-test.sh$')
pass "every executable shell script uses #!/bin/bash (sourced files are exempt)"

# A script committed without its executable bit fails wherever it is run directly (CI runs the image
# tests as ./images/...). The Containerfiles chmod the overlay helpers anyway; the repo copy must
# match. base-test.sh is only ever sourced.
while IFS= read -r script; do
  [[ -x $ROOT/$script ]] || fail "$script is executable"
done < <("$ROOT/test/shell-files" | grep -vE '^deploy/lib/|/profile.d/|^test/unit.d/base-test.sh$')
pass "every executable shell script has its executable bit"
