#!/bin/bash
# Container smoke test for the Fenoa PLATFORM layer.
#
# Runs the built image as a container and asserts the userspace a correct build must produce —
# WITHOUT booting. (The Fedora Asahi kernel only boots on real Apple Silicon, so a generic VM boot
# test isn't possible; boot-time state is covered by images/boottest/, run on hardware.)
#
# Every Fenoa image must pass this: the platform stage, the desktop image built on it, and the
# fairydust variant (which swaps the kernel, so it skips the stock-kernel assertion).
#
#   ./images/fenoa/hack/platform-smoke.sh [IMAGE]       # default fenoa-platform:44
#   KERNEL=fairydust ./images/fenoa/hack/platform-smoke.sh fenoa-fairydust:44
#   ENGINE=docker ./images/fenoa/hack/platform-smoke.sh
set -euo pipefail
IMAGE="${1:-fenoa-platform:44}"
ENGINE="${ENGINE:-podman}"
KERNEL="${KERNEL:-stock}"

echo "== platform smoke: $IMAGE (via $ENGINE, kernel=$KERNEL) =="
"$ENGINE" run --rm -i -e KERNEL="$KERNEL" --entrypoint bash "$IMAGE" -s <<'CHECKS'
set -uo pipefail
fail=0
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
no() { printf '  \033[31m✗ %s\033[0m\n' "$1"; fail=1; }

# Never `cmd | grep -q` here: under pipefail grep -q's early exit SIGPIPEs the producer and the
# pipeline reports failure even on a match. Capture output first, then match in the shell.

echo "== Fedora Asahi base (Apple Silicon) =="
[[ $(uname -m) == "aarch64" ]] && ok "aarch64" || no "not aarch64: $(uname -m)"
rpm -q asahi-platform-metapackage >/dev/null 2>&1 && ok "asahi-platform-metapackage" || no "asahi platform packages missing"
if [[ $KERNEL == "stock" ]]; then
  rpm -q kernel-16k >/dev/null 2>&1 && ok "kernel-16k (Asahi kernel)" || no "kernel-16k missing — wrong base"
fi
for p in asahi-audio speakersafetyd tiny-dfr widevine-installer update-m1n1; do
  rpm -q "$p" >/dev/null 2>&1 && ok "$p" || no "$p missing"
done

echo "== kernel + bootloader =="
n=$(find /usr/lib/modules -maxdepth 2 -name vmlinuz 2>/dev/null | wc -l)
[[ $n == "1" ]] && ok "exactly one kernel in /usr/lib/modules" || no "expected 1 kernel in /usr/lib/modules, found $n"
rpm -q systemd-boot-unsigned >/dev/null 2>&1 && ok "systemd-boot-unsigned installed" || no "systemd-boot-unsigned missing"
# Non-fatal: anything held by asahi-platform-metapackage stays but is inert under
# --bootloader systemd (the "no grub on the ESP" guarantee is the install-to-disk CI assertion).
for p in rpm-ostree bootupd grub2-efi-aa64; do
  rpm -q "$p" >/dev/null 2>&1 && echo "  - $p present (held by a dep; inert under systemd-boot)" || ok "$p removed"
done
for u in /etc/systemd/user/grub-boot-success.timer /etc/systemd/user/grub-boot-success.service \
         /etc/systemd/system/grub-boot-indeterminate.service; do
  [[ "$(readlink -f "$u")" == "/dev/null" ]] && ok "masked $(basename "$u")" || no "$(basename "$u") not masked (fails every boot under systemd-boot)"
done
rpm -q firefox >/dev/null 2>&1 && no "firefox still installed (the browser is a Flatpak)" || ok "native firefox removed"

echo "== initramfs (composefs pivot + Apple HID early load) =="
kver="$(basename "$(dirname "$(find /usr/lib/modules -maxdepth 2 -name vmlinuz 2>/dev/null | head -1)")")"
listing="$(lsinitrd "/usr/lib/modules/$kver/initramfs.img" 2>/dev/null || true)"
case $listing in
  *bootc-root-setup.service*) ok "initramfs carries bootc-root-setup.service (composefs root pivot)" ;;
  *) no "initramfs has no bootc composefs root setup — a composefs install would boot the host's /usr" ;;
esac
builtin="$(cat "/usr/lib/modules/$kver/modules.builtin" 2>/dev/null || true)"
for m in hid-apple hid-magicmouse; do
  case $builtin in
    *"/$m.ko"*) ok "$m built into the kernel" ;;
    *)
      case $listing in
        *"/$m.ko"*) ok "$m in the initramfs (trackpad boot-race fix)" ;;
        *) no "$m neither built in nor in the initramfs — the trackpad can come up dead" ;;
      esac
      ;;
  esac
done
[[ -f /usr/lib/dracut/dracut.conf.d/90-fenoa-apple-hid.conf ]] && ok "dracut Apple HID drop-in" || no "dracut Apple HID drop-in missing"
modprobe_conf="$(cat /usr/lib/modprobe.d/fenoa-apple.conf 2>/dev/null || true)"
case $modprobe_conf in
  *"options hid_apple fnmode=1"*) ok "hid_apple fnmode=1 (media keys first)" ;;
  *) no "hid_apple fnmode not configured" ;;
esac

echo "== Asahi m1n1 + devicetree on atomic =="
dtbs="$(grep '^DTBS=' /etc/sysconfig/update-m1n1 2>/dev/null || true)"
case $dtbs in
  *'/usr/lib/modules/$(uname -r)/dtb'*) ok "update-m1n1 DTBS points at the image devicetree" ;;
  *) no "update-m1n1 DTBS not repointed: ${dtbs:-unset}" ;;
esac
command -v update-m1n1 >/dev/null 2>&1 && ok "update-m1n1 present" || no "update-m1n1 missing"
[[ -x /usr/libexec/fenoa-apply-m1n1 ]] && ok "fenoa-apply-m1n1 helper" || no "fenoa-apply-m1n1 missing"
[[ -L /etc/systemd/system/multi-user.target.wants/fenoa-apply-m1n1.service ]] \
  && ok "fenoa-apply-m1n1.service enabled" || no "fenoa-apply-m1n1.service not enabled"

echo "== first-boot user provisioning =="
[[ -x /usr/libexec/fenoa-firstboot-user ]] && ok "fenoa-firstboot-user helper" || no "fenoa-firstboot-user missing"
[[ -L /etc/systemd/system/multi-user.target.wants/fenoa-firstboot-user.service ]] \
  && ok "fenoa-firstboot-user.service enabled" || no "fenoa-firstboot-user.service not enabled"
if getent passwd | awk -F: '$3>=1000 && $3<60000 {f=1} END{exit !f}'; then
  no "a human user is baked into the image (must be created on first boot)"
else
  ok "no human user baked in"
fi

echo "== Flatpak provisioning =="
command -v flatpak >/dev/null 2>&1 && ok "flatpak" || no "flatpak missing"
help="$(flatpak preinstall --help 2>&1 || true)"
case $help in *preinstall*) ok "flatpak preinstall CLI available" ;; *) no "flatpak has no preinstall subcommand" ;; esac
[[ -s /etc/flatpak/remotes.d/flathub.flatpakrepo ]] && ok "Flathub remote baked (DNS-free first boot)" || no "flathub.flatpakrepo missing"
[[ "$(readlink -f /etc/systemd/system/flatpak-add-fedora-repos.service)" == "/dev/null" ]] \
  && ok "flatpak-add-fedora-repos masked (Flathub is the only remote)" || no "flatpak-add-fedora-repos not masked"
for u in fenoa-flatpak-preinstall.service fenoa-brew-setup.service; do
  [[ -L /etc/systemd/system/multi-user.target.wants/$u ]] && ok "$u enabled" || no "$u not enabled"
done
[[ -L /etc/systemd/system/timers.target.wants/fenoa-flatpak-update.timer ]] \
  && ok "fenoa-flatpak-update.timer enabled" || no "fenoa-flatpak-update.timer not enabled"
unit="$(cat /usr/lib/systemd/system/fenoa-flatpak-preinstall.service 2>/dev/null || true)"
case $unit in *Restart=on-failure*) ok "preinstall retries on failure" ;; *) no "preinstall unit has no Restart=on-failure" ;; esac
case $unit in *"--prio=10 flathub"*"--prio=1 fedora"*) ok "Flathub outranks Fedora's registry (OBS-only fallback)" ;; *) no "remote priorities not set (Fedora would win ties)" ;; esac
case $unit in *"dbus-run-session -- /usr/bin/flatpak preinstall"*) ok "preinstall runs under dbus-run-session" ;; *) no "preinstall not wrapped in dbus-run-session (dies without a session bus)" ;; esac
# ...and dbus-run-session must exist: base-atomic has none, and without it the units fail with
# 203/EXEC and retry forever. (The desktop once got it only by accident, via system-config-printer.)
[[ -x /usr/bin/dbus-run-session ]] && ok "dbus-run-session installed" || no "dbus-run-session missing — Flatpak provisioning cannot run"

echo "== Homebrew ships prebuilt (ublue brew image) =="
[[ -s /usr/share/homebrew.tar.zst ]] && ok "homebrew.tar.zst shipped" || no "homebrew.tar.zst missing"
[[ -f /usr/share/fenoa/Brewfile ]] && ok "/usr/share/fenoa/Brewfile" || no "Brewfile missing"
[[ -L /etc/systemd/system/multi-user.target.wants/brew-setup.service ]] && ok "brew-setup.service enabled" || no "brew-setup.service not enabled"
for t in brew-update brew-upgrade; do
  [[ -L /etc/systemd/system/timers.target.wants/$t.timer ]] && ok "$t.timer enabled" || no "$t.timer not enabled"
done
helper="$(grep -vE '^[[:space:]]*#' /usr/libexec/fenoa-brew-setup 2>/dev/null || true)"
case $helper in
  *install.sh*|*curl*|*wget*) no "fenoa-brew-setup downloads an installer" ;;
  *) ok "fenoa-brew-setup does not download an installer" ;;
esac
brewsh="$(cat /etc/profile.d/brew.sh 2>/dev/null || true)"
case $brewsh in *'PATH}:'*HOMEBREW_PREFIX*) ok "brew is appended to PATH, not prepended" ;; *) no "brew.sh missing or prepends brew" ;; esac

echo "== system services =="
for u in NetworkManager bluetooth firewalld systemd-resolved avahi-daemon power-profiles-daemon cups cups-browsed systemd-oomd; do
  systemctl is-enabled "$u.service" >/dev/null 2>&1 && ok "$u enabled" || no "$u not enabled"
done
systemctl is-enabled docker.socket >/dev/null 2>&1 && ok "docker.socket enabled" || no "docker.socket not enabled"
[[ "$(readlink -f /etc/systemd/system/NetworkManager-wait-online.service)" == "/dev/null" ]] \
  && ok "NetworkManager-wait-online masked" || no "NetworkManager-wait-online not masked"

# SSH is opt-in: sshd off, and the default zone does not let it in.
grep -qx 'disable sshd.service' /usr/lib/systemd/system-preset/50-fenoa.preset 2>/dev/null \
  && ok "50-fenoa.preset disables sshd" || no "no preset disables sshd (Fedora's 90-default enables it)"
if [[ -f /usr/lib/systemd/system/sshd.service ]]; then
  sshd_state="$(systemctl is-enabled sshd.service 2>/dev/null || true)"
  [[ $sshd_state == "disabled" ]] && ok "sshd disabled (SSH is opt-in)" || no "sshd is '${sshd_state:-unknown}', not disabled"
  # What a first-boot preset pass would do; the container is thrown away afterwards.
  if preset_out="$(systemctl preset sshd.service 2>&1)"; then
    sshd_state="$(systemctl is-enabled sshd.service 2>/dev/null || true)"
    [[ $sshd_state == "disabled" ]] && ok "applying the presets keeps sshd disabled" || no "the presets re-enable sshd ($sshd_state)"
  else
    no "systemctl preset sshd.service failed: $preset_out"
  fi
else
  ok "sshd is not installed"
fi
zone="$(firewall-offline-cmd --get-default-zone 2>/dev/null || true)"
ssh_allowed="$(firewall-offline-cmd --zone="$zone" --query-service=ssh 2>/dev/null || true)"
[[ $ssh_allowed == "no" ]] && ok "the $zone zone does not allow ssh" || no "the $zone zone allows ssh (${ssh_allowed:-query failed})"

echo "== system tuning =="
for f in /usr/lib/sysctl.d/99-fenoa-sysctl.conf /usr/lib/sysctl.d/90-fenoa-file-watchers.conf \
         /usr/lib/udev/rules.d/60-fenoa-io-scheduler.rules /usr/lib/systemd/zram-generator.conf.d/90-fenoa.conf \
         /usr/lib/systemd/logind.conf.d/10-fenoa-power-button.conf /usr/lib/systemd/logind.conf.d/20-fenoa-inhibit-delay.conf \
         /usr/lib/systemd/oomd.conf.d/10-fenoa.conf /usr/lib/systemd/user/app.slice.d/10-fenoa-oomd.conf \
         /usr/lib/NetworkManager/conf.d/50-fenoa-wifi-powersave.conf /usr/lib/tmpfiles.d/fenoa-zswap.conf \
         /etc/docker/daemon.json; do
  [[ -f $f ]] && ok "$f" || no "$f missing"
done
[[ -x /usr/lib/systemd/system-sleep/fenoa-unmount-fuse ]] && ok "gvfs FUSE unmount sleep hook" || no "sleep hook missing or not executable"
visudo -cf /etc/sudoers.d/fenoa-passwd-tries >/dev/null 2>&1 && ok "sudoers drop-in parses" || no "sudoers drop-in invalid"
[[ "$(stat -c %a /etc/sudoers.d/fenoa-passwd-tries 2>/dev/null)" == "440" ]] && ok "sudoers drop-in is 0440" || no "sudoers drop-in mode is not 0440"
[[ -x /usr/bin/fenoa-widevine ]] && ok "fenoa-widevine on PATH" || no "fenoa-widevine missing"

echo "== no Omarchy =="
leftovers="$(ls -d /usr/share/omarchy /usr/bin/omarchy* /usr/libexec/omarchy* /etc/omarchy* /usr/lib/systemd/system/omarchy* 2>/dev/null || true)"
[[ -z $leftovers ]] && ok "no omarchy files" || no "omarchy files present: $leftovers"

[[ -L /usr/local ]] && ok "/usr/local is a symlink (var-backed on bootc)" || no "/usr/local is not a symlink"

echo
if [[ $fail == "0" ]]; then echo "PLATFORM SMOKE: PASS"; else echo "PLATFORM SMOKE: FAIL"; fi
exit "$fail"
CHECKS
