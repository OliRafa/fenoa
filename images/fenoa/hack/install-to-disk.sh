#!/bin/bash
# Real `bootc install to-disk` of an image onto a loopback file, then inspect the result by mounting
# it: systemd-boot on the ESP (no GRUB), a kernel staged under EFI/Linux, the composefs-native
# deployment root (/composefs, /ostree, /state), and a deployment /etc whose machine-id still reads
# "uninitialized", so the installed system detects its first boot. This is the shipping install
# path (docs/platform.md), with --generic-image so it leaves the runner's firmware boot entries alone.
#
# Needs root, loop devices and rootful podman with the image in /var/lib/containers:
#   sudo ./images/fenoa/hack/install-to-disk.sh [IMAGE] [WORKDIR]
set -euo pipefail
IMAGE="${1:-fenoa:44}"
WORKDIR="${2:-/var/tmp/fenoa-install-to-disk}"
ENGINE="${ENGINE:-podman}"

mkdir -p "$WORKDIR"
disk="$WORKDIR/disk.raw"
rm -f "$disk"
truncate -s 20G "$disk"

echo "== bootc install to-disk: $IMAGE =="
"$ENGINE" run --rm --privileged --pid=host \
  --security-opt label=type:unconfined_t \
  -v /var/lib/containers:/var/lib/containers -v /dev:/dev \
  -v "$WORKDIR":/output \
  "$IMAGE" \
  bootc install to-disk \
    --composefs-backend --bootloader systemd --filesystem btrfs \
    --generic-image --via-loopback --wipe /output/disk.raw

# Inspect by loopback mount (no libguestfs: its qemu appliance needs KVM, which a runner may lack).
# p1 = ESP (vfat), p2 = root (btrfs).
loop=$(losetup -Pf --show "$disk")
mnt="$WORKDIR/mnt"
mkdir -p "$mnt/esp" "$mnt/root"
# Runs as root: leave nothing root-owned behind in WORKDIR for an unprivileged caller to trip over.
cleanup() {
  umount "$mnt/esp" 2>/dev/null || true
  umount "$mnt/root" 2>/dev/null || true
  losetup -d "$loop" 2>/dev/null || true
  rmdir "$mnt/esp" "$mnt/root" "$mnt" 2>/dev/null || true
  rm -f "$disk"
}
trap cleanup EXIT

sd=0 grub=0 kern=0 cfs=0 ost=0 st=0 mid=0

mount "${loop}p1" "$mnt/esp"
echo "--- ESP /EFI ---"
find "$mnt/esp/EFI" -maxdepth 3 -print 2>/dev/null || true
[[ -e $mnt/esp/EFI/systemd/systemd-bootx64.efi || -e $mnt/esp/EFI/BOOT/BOOTX64.EFI ]] && sd=1
[[ -n "$(find "$mnt/esp/EFI" -iname 'grub*.efi' -o -iname 'shim*.efi' 2>/dev/null | head -1)" ]] && grub=1
[[ -n "$(find "$mnt/esp/EFI/Linux" -name vmlinuz 2>/dev/null | head -1)" ]] && kern=1
umount "$mnt/esp"

mount "${loop}p2" "$mnt/root"
echo "--- deployment root ---"
ls -a "$mnt/root" 2>/dev/null | head
# composefs-native backend root layout: composefs/ ostree/ state/ (NOT the classic
# /ostree/repo + /ostree/deploy + .bootc-aleph.json-at-root).
[[ -d $mnt/root/composefs ]] && cfs=1
[[ -d $mnt/root/ostree ]] && ost=1
[[ -d $mnt/root/state ]] && st=1
# The install copies the image's /etc into state/deploy/<id>/etc. Its machine-id must still read
# "uninitialized" (or be absent), or systemd would not see the first boot and systemd-firstboot
# would never ask its questions.
for etc in "$mnt/root"/state/deploy/*/etc; do
  [[ -d $etc ]] || continue
  if [[ ! -e $etc/machine-id ]]; then
    echo "installed /etc/machine-id: absent"
    mid=1
  else
    content=$(<"$etc/machine-id")
    echo "installed /etc/machine-id: '$content'"
    [[ $content == "uninitialized" ]] && mid=1
  fi
done
umount "$mnt/root"

fail=0
check() { # check <ok> <pass message> <fail message>
  if (( $1 )); then echo "OK: $2"; else echo "FAIL: $3"; fail=1; fi
}
check "$sd" "systemd-boot on ESP" "systemd-boot missing from ESP"
check "$(( ! grub ))" "no GRUB or shim on ESP" "GRUB or shim present on ESP"
check "$kern" "kernel staged on ESP" "no kernel on ESP"
check "$cfs" "/composefs deployment store present" "no /composefs (composefs deploy incomplete)"
check "$ost" "/ostree present" "no /ostree"
check "$st" "/state present" "no /state"
check "$mid" "installed /etc/machine-id is uninitialized: the first boot will be detected" \
  "installed /etc/machine-id is not uninitialized (or no deployment /etc): systemd-firstboot would not run"

if (( fail == 0 )); then echo "INSTALL-TO-DISK: PASS"; else echo "INSTALL-TO-DISK: FAIL"; fi
exit "$fail"
