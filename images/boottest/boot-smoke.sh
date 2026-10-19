#!/bin/bash
# Boot smoke test for Fenoa, run at boot by fenoa-boottest.service (images/boottest/). Asserts what
# a container inspection cannot: that the image booted Fedora's kernel through systemd-boot, brought
# its services and the greeter up, and that SELinux let the greeter work. Exits non-zero on any
# failure. Runs on a PC or in a UEFI VM (OVMF), with Secure Boot off.
set -uo pipefail

fail=0
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
no() { printf '  \033[31m✗ %s\033[0m\n' "$1"; fail=1; }
note() { printf '  · %s\n' "$1"; }

echo "== kernel =="
kver="$(uname -r)"
echo "  kernel: $kver"
case $kver in
  *.fc*.x86_64) ok "Fedora x86_64 kernel running" ;;
  *) no "unexpected kernel: $kver" ;;
esac
render="$(ls /dev/dri/renderD* 2>/dev/null | head -1 || true)"
[[ -n $render ]] && ok "GPU render node present ($render)" || no "no GPU render node — the desktop would render on llvmpipe"

echo "== bootloader: systemd-boot (not GRUB) =="
# bootctl only looks for the ESP at /efi, /boot and /boot/efi, and a composefs install may mount it
# nowhere. Find it by its GPT partition type and mount it read-only if needed, so the "no grub"
# check below is not vacuous.
esp="$(bootctl --print-esp-path 2>/dev/null || true)" esp_tmp=""
if [[ -z $esp ]]; then
  esp_dev="$(lsblk -nrpo PATH,PARTTYPE 2>/dev/null | awk 'tolower($2) == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" { print $1; exit }')"
  if [[ -n $esp_dev ]]; then
    esp="$(findmnt -no TARGET "$esp_dev" 2>/dev/null | head -1 || true)"
    if [[ -z $esp ]]; then
      esp_tmp="$(mktemp -d)"
      if mount -o ro "$esp_dev" "$esp_tmp" 2>/dev/null; then esp="$esp_tmp"; else rmdir "$esp_tmp"; esp_tmp=""; fi
    fi
  fi
fi
[[ -n $esp ]] && ok "ESP located at $esp" || no "ESP not found"
status="$(bootctl status 2>/dev/null || true)"
case $status in *systemd-boot*) ok "systemd-boot is the active bootloader" ;; *) no "systemd-boot not active" ;; esac
secure_boot="$(printf '%s\n' "$status" | sed -n 's/^ *Secure Boot: *//p' | head -1)"
note "Secure Boot: ${secure_boot:-unknown} (systemd-boot is unsigned; it boots only with Secure Boot off)"
if [[ -n $esp ]]; then
  grub="$(find "$esp" \( -iname 'grub*.efi' -o -iname 'shim*.efi' \) -print -quit 2>/dev/null || true)"
  [[ -z $grub ]] && ok "no GRUB or shim on the ESP" || no "GRUB or shim on the ESP: $grub"
fi
if [[ -n $esp_tmp ]]; then
  umount "$esp_tmp" 2>/dev/null || true
  rmdir "$esp_tmp" 2>/dev/null || true
fi

echo "== services =="
for u in greetd NetworkManager systemd-resolved power-profiles-daemon upower firewalld; do
  systemctl is-active --quiet "$u.service" && ok "$u active" || no "$u not active"
done
systemctl is-active --quiet bluetooth.service && ok "bluetooth active" || note "bluetooth inactive (ok without an adapter)"
swaps="$(cat /proc/swaps 2>/dev/null || true)"
case $swaps in *zram0*) ok "zram swap active" ;; *) no "no zram swap" ;; esac
failed="$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | tr '\n' ' ')"
[[ -z ${failed// /} ]] && ok "no failed system units" || no "failed units: $failed"

echo "== greeter =="
greeter="$(pgrep -u greetd -a noctalia-greeter 2>/dev/null || true)"
[[ -n $greeter ]] && ok "noctalia-greeter running as greetd" || note "noctalia-greeter not running (a session may already be logged in)"
state="$(stat -c '%a %U' /var/lib/noctalia-greeter 2>/dev/null || true)"
[[ $state == "750 greetd" ]] && ok "/var/lib/noctalia-greeter is 0750 greetd" || no "greeter state dir wrong: ${state:-missing}"
denials="$(journalctl -b -k -g 'avc:  denied' --no-pager -q 2>/dev/null | grep -E 'greetd|noctalia|xdm' || true)"
[[ -z $denials ]] && ok "no SELinux denials for greetd/noctalia-greeter" || no "SELinux denials: $(printf '%s' "$denials" | head -3)"

echo "== first-boot provisioning =="
# The image ships /etc/machine-id as "uninitialized". On the first boot PID 1 bind-mounts a
# temporary ID over it, so reading the file shows an ID either way; it is committed only once that
# mount is gone and systemd-machine-id-commit did not fail. If it never commits, every boot is a
# first boot, and its full preset pass undoes local unit changes (a `systemctl enable --now sshd`).
machine_id="$(cat /etc/machine-id 2>/dev/null || true)"
id_overmount="$(findmnt -n /etc/machine-id 2>/dev/null || true)"
id_commit="$(systemctl is-failed systemd-machine-id-commit.service 2>/dev/null || true)"
if [[ $machine_id =~ ^[0-9a-f]{32}$ && -z $id_overmount && $id_commit != "failed" ]]; then
  ok "machine ID committed after the first boot"
else
  no "machine ID not committed (id '${machine_id:-empty}', overmount '${id_overmount:-none}', commit unit '${id_commit:-?}')"
fi
[[ -f /var/lib/fenoa/firstboot-user.done ]] && ok "primary user provisioned" || no "fenoa-firstboot-user has not completed"
# The Flatpak preinstall and the Brewfile setup are started by their timers (30s after boot, then
# every 2 minutes until the hosts they need answer), so 20s after multi-user.target they are often
# not done yet.
for t in fenoa-flatpak-preinstall fenoa-brew-setup; do
  systemctl is-enabled --quiet "$t.timer" && ok "$t.timer enabled" || no "$t.timer not enabled — $t would never run"
done
systemctl is-active --quiet fenoa-flatpak-preinstall.service && ok "Flatpak app set installed" \
  || note "fenoa-flatpak-preinstall not done yet (its timer tries every 2 min until the remotes answer)"
[[ -f /var/lib/fenoa/brew-setup-done ]] && ok "Brewfile applied" \
  || note "fenoa-brew-setup not done yet (tried every 2 min until Homebrew answers; a failed bundle backs off)"

echo "== immutability =="
[[ -L /usr/local ]] && ok "/usr/local is a symlink" || no "/usr/local is not a symlink"
enforce="$(getenforce 2>/dev/null || echo unknown)"
[[ $enforce != "Disabled" ]] && ok "SELinux: $enforce" || no "SELinux disabled"

echo
if [[ $fail == "0" ]]; then echo "BOOT SMOKE: PASS"; else echo "BOOT SMOKE: FAIL"; fi
exit "$fail"
