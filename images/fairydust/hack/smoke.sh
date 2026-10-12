#!/bin/bash
# Container smoke test for the fenoa-fairydust image: what the kernel swap must produce, WITHOUT
# booting (DP alt-mode itself is a hardware check). The rest of the image is covered by running
# platform-smoke.sh (KERNEL=fairydust) and desktop-smoke.sh against the same image.
#
#   ./images/fairydust/hack/smoke.sh [IMAGE]     # default fenoa-fairydust:44
set -euo pipefail
IMAGE="${1:-fenoa-fairydust:44}"
ENGINE="${ENGINE:-podman}"

echo "== fairydust smoke: $IMAGE (via $ENGINE) =="
"$ENGINE" run --rm -i --entrypoint bash "$IMAGE" -s <<'CHECKS'
set -uo pipefail
fail=0
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
no() { printf '  \033[31m✗ %s\033[0m\n' "$1"; fail=1; }

echo "== kernel swapped to fairydust =="
if rpm -q kernel-16k >/dev/null 2>&1; then
  no "kernel-16k RPM still present — the stock kernel was not removed"
else
  ok "stock kernel-16k RPM removed"
fi
n=$(find /usr/lib/modules -maxdepth 2 -name vmlinuz 2>/dev/null | wc -l)
[[ $n == "1" ]] && ok "exactly one kernel in /usr/lib/modules" || no "expected 1 kernel, found $n"
kver="$(basename "$(dirname "$(find /usr/lib/modules -maxdepth 2 -name vmlinuz 2>/dev/null | head -1)")")"
# fairydust builds with a plain `<ver>+` localversion (e.g. 7.1.13+), never an fcNN Fedora release.
case $kver in
  *.fc*) no "kernel $kver looks like a Fedora build, not the fairydust swap" ;;
  "") no "no kernel version resolved" ;;
  *) ok "fairydust kernel present: $kver" ;;
esac

echo "== fairydust payload (DisplayPort alt-mode) =="
# appledrm = DRM_APPLE, phy-apple-dptx = the USB-C DisplayPort-TX PHY that is fairydust's point,
# drm_asahi = the GPU driver (a kernel built without it renders everything on llvmpipe).
for m in appledrm phy-apple-dptx asahi; do
  found="$(find "/usr/lib/modules/$kver" -name "$m.ko*" 2>/dev/null | head -1)"
  builtin="$(grep -E "/$m\.ko" "/usr/lib/modules/$kver/modules.builtin" 2>/dev/null || true)"
  if [[ -n $found || -n $builtin ]]; then ok "driver $m present"; else no "driver $m missing"; fi
done
# The EFI-ZBOOT image systemd-boot needs on this chain starts with the PE "MZ" magic.
magic="$(head -c 2 "/usr/lib/modules/$kver/vmlinuz" 2>/dev/null || true)"
[[ $magic == "MZ" ]] && ok "vmlinuz is a PE/EFI image (systemd-boot loadable)" || no "vmlinuz is not a PE/EFI image"

echo "== Apple devicetrees under dtb/apple (update-m1n1's path) =="
# update-m1n1 globs $DTBS/apple/*.dtb; a flat dtb/ makes it find nothing and the fairydust
# devicetree never goes live, while everything else still boots on the old one.
dtbn=$(find "/usr/lib/modules/$kver/dtb/apple" -maxdepth 1 -name '*.dtb' 2>/dev/null | wc -l)
(( dtbn > 0 )) && ok "$dtbn Apple DTBs under modules/$kver/dtb/apple" || no "no DTBs under dtb/apple/"

echo "== initramfs rebuilt against the fairydust kernel =="
listing="$(lsinitrd "/usr/lib/modules/$kver/initramfs.img" 2>/dev/null || true)"
case $listing in
  *bootc-root-setup.service*) ok "initramfs carries bootc-root-setup.service" ;;
  *) no "initramfs has no bootc composefs root setup" ;;
esac

echo
if [[ $fail == "0" ]]; then echo "FAIRYDUST SMOKE: PASS"; else echo "FAIRYDUST SMOKE: FAIL"; fi
exit "$fail"
CHECKS
