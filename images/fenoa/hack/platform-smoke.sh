#!/bin/bash
# Container smoke test for the Fenoa PLATFORM layer.
#
# Runs the built image as a container and asserts the userspace a correct build must produce —
# WITHOUT booting. Boot-time state is covered by images/boottest/, on a PC or in a VM.
#
# Every Fenoa image must pass this: the platform stage and the desktop image built on it.
#
#   ./images/fenoa/hack/platform-smoke.sh [IMAGE]       # default fenoa-platform:44
#   ENGINE=docker ./images/fenoa/hack/platform-smoke.sh
set -euo pipefail
IMAGE="${1:-fenoa-platform:44}"
ENGINE="${ENGINE:-podman}"

echo "== platform smoke: $IMAGE (via $ENGINE) =="
"$ENGINE" run --rm -i --entrypoint bash "$IMAGE" -s <<'CHECKS'
set -uo pipefail
fail=0
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
no() { printf '  \033[31m✗ %s\033[0m\n' "$1"; fail=1; }
# timer_only UNIT: UNIT is static (no [Install]) and not wanted by multi-user.target, so only its
# timer starts it.
timer_only() {
  local state
  state="$(systemctl is-enabled "$1" 2>/dev/null || true)"
  if [[ $state == "static" && ! -e /etc/systemd/system/multi-user.target.wants/$1 && ! -L /etc/systemd/system/multi-user.target.wants/$1 ]]; then
    ok "$1 is static (started by its timer, not at boot)"
  else
    no "$1 is '${state:-unknown}' or wanted by multi-user.target (it would run before the network is up)"
  fi
}

# Never `cmd | grep -q` here: under pipefail grep -q's early exit SIGPIPEs the producer and the
# pipeline reports failure even on a match. Capture output first, then match in the shell.

echo "== Fedora base (x86_64) =="
[[ $(uname -m) == "x86_64" ]] && ok "x86_64" || no "not x86_64: $(uname -m)"
rpm -q kernel >/dev/null 2>&1 && ok "kernel (Fedora's)" || no "kernel missing — wrong base"
for p in linux-firmware microcode_ctl amd-ucode-firmware fwupd mesa-vulkan-drivers libva-intel-media-driver; do
  rpm -q "$p" >/dev/null 2>&1 && ok "$p" || no "$p missing"
done

echo "== kernel + bootloader =="
n=$(find /usr/lib/modules -maxdepth 2 -name vmlinuz 2>/dev/null | wc -l)
[[ $n == "1" ]] && ok "exactly one kernel in /usr/lib/modules" || no "expected 1 kernel in /usr/lib/modules, found $n"
rpm -q systemd-boot-unsigned >/dev/null 2>&1 && ok "systemd-boot-unsigned installed" || no "systemd-boot-unsigned missing"
[[ -f /usr/lib/systemd/boot/efi/systemd-bootx64.efi ]] && ok "systemd-bootx64.efi for bootc to install" || no "systemd-bootx64.efi missing"
# Nothing holds these on x86_64, so P3 removes them; a GRUB left behind would mean bootupd or a
# grub2 package came back with a base or package-list change.
for p in rpm-ostree bootupd grub2-common grub2-efi-x64 grub2-tools shim-x64; do
  rpm -q "$p" >/dev/null 2>&1 && no "$p installed (the image boots systemd-boot)" || ok "$p removed"
done
for u in /usr/lib/systemd/user/grub-boot-success.timer /usr/lib/systemd/system/grub-boot-indeterminate.service; do
  [[ ! -e $u ]] && ok "no $(basename "$u") (it fails every boot under systemd-boot)" || no "$(basename "$u") ships"
done
rpm -q firefox >/dev/null 2>&1 && no "firefox still installed (the browser is a Flatpak)" || ok "native firefox removed"

echo "== initramfs (composefs and ostree root pivots) =="
kver="$(basename "$(dirname "$(find /usr/lib/modules -maxdepth 2 -name vmlinuz 2>/dev/null | head -1)")")"
listing="$(lsinitrd "/usr/lib/modules/$kver/initramfs.img" 2>/dev/null || true)"
case $listing in
  *bootc-root-setup.service*) ok "initramfs carries bootc-root-setup.service (composefs root pivot)" ;;
  *) no "initramfs has no bootc composefs root setup — a composefs install would boot the host's /usr" ;;
esac
case $listing in
  *ostree-prepare-root.service*) ok "initramfs carries ostree-prepare-root.service (a Fedora Atomic switched to Fenoa boots)" ;;
  *) no "initramfs has no ostree-prepare-root — a system switched from Fedora Atomic would not boot" ;;
esac

echo "== first-boot user provisioning =="
[[ -x /usr/libexec/fenoa-firstboot-user ]] && ok "fenoa-firstboot-user helper" || no "fenoa-firstboot-user missing"
[[ -L /etc/systemd/system/multi-user.target.wants/fenoa-firstboot-user.service ]] \
  && ok "fenoa-firstboot-user.service enabled" || no "fenoa-firstboot-user.service not enabled"
if getent passwd | awk -F: '$3>=1000 && $3<60000 {f=1} END{exit !f}'; then
  no "a human user is baked into the image (must be created on first boot)"
else
  ok "no human user baked in"
fi
# New accounts log in to zsh with Fedora's stock config: the package's %post lists it in
# /etc/shells (chsh refuses a shell that is not there) and it ships the skel files useradd copies.
rpm -q zsh >/dev/null 2>&1 && ok "zsh installed (new accounts' login shell)" || no "zsh missing (fenoa-firstboot-user would fall back to bash)"
shells="$(cat /etc/shells 2>/dev/null || true)"
[[ $'\n'$shells$'\n' == *$'\n'/usr/bin/zsh$'\n'* ]] && ok "/usr/bin/zsh is listed in /etc/shells" || no "/usr/bin/zsh is not in /etc/shells"
for f in /etc/skel/.zshrc /etc/skel/.zprofile; do
  [[ -f $f ]] && ok "$f (Fedora's stock zsh config for new homes)" || no "$f missing"
done
# systemd counts a boot as the first only when /etc/machine-id is absent or reads "uninitialized"
# (an empty file does not count); only then does systemd-firstboot run and the preset pass apply.
machine_id="$(cat /etc/machine-id 2>/dev/null || true)"
[[ $machine_id == "uninitialized" ]] && ok "/etc/machine-id reads uninitialized (an install detects its first boot)" \
  || no "/etc/machine-id is '${machine_id:-empty or absent}', not uninitialized (systemd-firstboot would not run)"
# systemd-firstboot silently skips a question whose answer is already configured: the locale,
# keymap or timezone when its file exists, the root password unless root's shadow field is
# "!unprovisioned". The docs promise the first three questions and no root password.
for f in /etc/locale.conf /etc/vconsole.conf /etc/localtime; do
  [[ ! -e $f && ! -L $f ]] && ok "the image ships no $f (systemd-firstboot asks for it)" \
    || no "the image ships $f (systemd-firstboot would skip its question)"
done
root_shadow="$(awk -F: '$1 == "root" { print $2 }' /etc/shadow 2>/dev/null || true)"
[[ -n $root_shadow && $root_shadow != "!unprovisioned" ]] \
  && ok "root's shadow entry is set ('$root_shadow'), so systemd-firstboot asks for no root password" \
  || no "root's shadow field is '${root_shadow:-missing}' (systemd-firstboot would prompt for a root password)"

echo "== Flatpak provisioning =="
command -v flatpak >/dev/null 2>&1 && ok "flatpak" || no "flatpak missing"
help="$(flatpak preinstall --help 2>&1 || true)"
case $help in *preinstall*) ok "flatpak preinstall CLI available" ;; *) no "flatpak has no preinstall subcommand" ;; esac
[[ -s /etc/flatpak/remotes.d/flathub.flatpakrepo ]] && ok "Flathub remote baked (registering it downloads nothing)" || no "flathub.flatpakrepo missing"
[[ "$(readlink -f /etc/systemd/system/flatpak-add-fedora-repos.service)" == "/dev/null" ]] \
  && ok "flatpak-add-fedora-repos masked (Flathub is the only remote)" || no "flatpak-add-fedora-repos not masked"
# The preinstall waits for the network itself: fenoa-online skips it until the remotes answer over
# HTTPS, and its timer starts it again until it has run. Started at boot instead (multi-user.target),
# it would run before Wi-Fi is up, and offline `flatpak preinstall` exits 0 having installed nothing.
# fenoa-brew-setup (below) works the same way.
[[ -x /usr/libexec/fenoa-online ]] && ok "fenoa-online (the provisioning units' network check)" || no "fenoa-online missing or not executable"
# fenoa-online asks each host over HTTPS with curl; without it every provisioning unit fails.
command -v curl >/dev/null 2>&1 && ok "curl (fenoa-online's HTTPS check)" || no "curl missing — fenoa-online cannot check the network"
timer_only fenoa-flatpak-preinstall.service
for t in fenoa-flatpak-preinstall fenoa-flatpak-update; do
  [[ -L /etc/systemd/system/timers.target.wants/$t.timer ]] && ok "$t.timer enabled" || no "$t.timer not enabled"
done
unit="$(cat /usr/lib/systemd/system/fenoa-flatpak-preinstall.service 2>/dev/null || true)"
case $unit in *"ExecCondition=/usr/libexec/fenoa-online dl.flathub.org"*) ok "preinstall waits until Flathub answers" ;; *) no "preinstall has no fenoa-online condition (it would run offline and exit 0)" ;; esac
case $unit in *"--prio=10 flathub"*) ok "Flathub gets priority 10 (it outranks a remote the machine already had)" ;; *) no "Flathub's priority not set (a Fedora remote would win ties)" ;; esac
case $unit in *"dbus-run-session -- /usr/bin/flatpak preinstall"*) ok "preinstall runs under dbus-run-session" ;; *) no "preinstall not wrapped in dbus-run-session (dies without a session bus)" ;; esac
# ...and dbus-run-session must exist: base-atomic has none, and without it the units fail with
# 203/EXEC and retry forever. (The desktop once got it only by accident, via system-config-printer.)
[[ -x /usr/bin/dbus-run-session ]] && ok "dbus-run-session installed" || no "dbus-run-session missing — Flatpak provisioning cannot run"

echo "== Homebrew ships prebuilt (ublue brew image) =="
[[ -s /usr/share/homebrew.tar.zst ]] && ok "homebrew.tar.zst shipped" || no "homebrew.tar.zst missing"
[[ -f /usr/share/fenoa/Brewfile ]] && ok "/usr/share/fenoa/Brewfile" || no "Brewfile missing"
[[ -L /etc/systemd/system/multi-user.target.wants/brew-setup.service ]] && ok "brew-setup.service enabled" || no "brew-setup.service not enabled"
# Like the Flatpak preinstall: started by its timer, and skipped until Homebrew's hosts answer
# unless the Brewfile has already been applied.
timer_only fenoa-brew-setup.service
unit="$(cat /usr/lib/systemd/system/fenoa-brew-setup.service 2>/dev/null || true)"
case $unit in *"/usr/libexec/fenoa-online formulae.brew.sh ghcr.io"*) ok "fenoa-brew-setup waits until Homebrew's hosts answer" ;; *) no "fenoa-brew-setup has no fenoa-online condition (brew bundle would run offline)" ;; esac
case $unit in *"Restart=on-failure"*"RestartMode=direct"*) ok "fenoa-brew-setup backs off a failed brew bundle" ;; *) no "fenoa-brew-setup does not back off failures (it would rebuild every 2 minutes)" ;; esac
for t in fenoa-brew-setup brew-update brew-upgrade; do
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
         /usr/lib/tmpfiles.d/fenoa-zswap.conf /etc/docker/daemon.json; do
  [[ -f $f ]] && ok "$f" || no "$f missing"
done
[[ -x /usr/lib/systemd/system-sleep/fenoa-unmount-fuse ]] && ok "gvfs FUSE unmount sleep hook" || no "sleep hook missing or not executable"
visudo -cf /etc/sudoers.d/fenoa-passwd-tries >/dev/null 2>&1 && ok "sudoers drop-in parses" || no "sudoers drop-in invalid"
[[ "$(stat -c %a /etc/sudoers.d/fenoa-passwd-tries 2>/dev/null)" == "440" ]] && ok "sudoers drop-in is 0440" || no "sudoers drop-in mode is not 0440"

echo "== fingerprint for sudo and polkit, password as the fallback =="
for p in fprintd fprintd-pam; do
  rpm -q "$p" >/dev/null 2>&1 && ok "$p" || no "$p missing"
done
[[ -f /usr/share/dbus-1/system-services/net.reactivated.Fprint.service ]] \
  && ok "fprintd is D-Bus activated" || no "fprintd has no D-Bus activation file (nothing would start it)"
for m in pam_fprintd pam_exec; do
  [[ -f /usr/lib64/security/$m.so ]] && ok "$m.so" || no "$m.so missing"
done
gate="$(awk '/^auth.*pam_exec\.so/ { print $NF }' /usr/lib/pam.d/fenoa-fingerprint 2>/dev/null)"
[[ $gate == "/usr/libexec/fenoa-lid-closed" && -x $gate ]] && ok "fenoa-fingerprint's lid check ships executable" || no "fenoa-fingerprint runs '${gate:-nothing}', not an executable fenoa-lid-closed"
# No ACPI lid in a container: the check must say "open", so the reader is tried.
if [[ -x $gate ]] && ! "$gate"; then ok "the lid check reports open without an ACPI lid"; else no "the lid check reports a shut lid without an ACPI lid"; fi
for f in /etc/pam.d/sudo /usr/lib/pam.d/polkit-1; do
  first="$(grep -m1 -E '^auth[[:space:]]' "$f" 2>/dev/null | tr -s ' \t' ' ')"
  [[ $first == "auth include fenoa-fingerprint" ]] && ok "$f starts its auth stack with fenoa-fingerprint" || no "$f's first auth line is '$first'"
done
[[ ! -e /etc/pam.d/polkit-1 ]] && ok "no /etc/pam.d/polkit-1 hides the image's polkit stack" || no "/etc/pam.d/polkit-1 hides /usr/lib/pam.d/polkit-1"
# The login screen and tty logins stay password-only (system-auth carries no pam_fprintd).
auth_fprintd="$(grep -lE '^[[:space:]]*auth.*pam_fprintd' /etc/pam.d/system-auth /etc/pam.d/password-auth /etc/pam.d/login 2>/dev/null || true)"
[[ -z $auth_fprintd ]] && ok "system-auth, password-auth and login do not ask for a fingerprint" || no "pam_fprintd in: $auth_fprintd"
# The stack as a whole: with no reader (no fprintd in a container) sudo still takes the password, and
# only the right one.
if useradd -m -G wheel fenoa-pam-test 2>/dev/null && echo 'fenoa-pam-test:Fenoa-smoke-1' | chpasswd 2>/dev/null; then
  if runuser -u fenoa-pam-test -- sudo -S -k -p '' true <<<'Fenoa-smoke-1' >/dev/null 2>&1; then
    ok "sudo authenticates with the password through the fingerprint stack"
  else
    no "sudo rejects the right password"
  fi
  if runuser -u fenoa-pam-test -- sudo -S -k -p '' true <<<'wrong-password' >/dev/null 2>&1; then
    no "sudo accepts a wrong password"
  else
    ok "sudo rejects a wrong password"
  fi
  userdel -r fenoa-pam-test 2>/dev/null || true
else
  no "could not create a test user for the sudo check"
fi

echo "== first boot: the preset pass keeps every unit as built =="
# A first boot makes systemd run a FULL `systemctl preset-all`: every unit is set to what the
# presets say, and Fedora's 99-default-disable.preset disables anything they do not list. Do the same
# here (the container is thrown away) and require that it changes no unit-file state, enablement
# link or default target, i.e. the presets keep the image exactly as built.
unit_state() {
  systemctl list-unit-files --no-legend --no-pager 2>/dev/null | awk '{ print $1, $2 }'
  find /etc/systemd/system /etc/systemd/user -type l -printf 'link %P -> %l\n' 2>/dev/null
  echo "default.target: $(systemctl get-default 2>/dev/null)"
}
before="$(unit_state | sort)"
if preset_out="$(systemctl preset-all 2>&1)"; then
  after="$(unit_state | sort)"
  changes="$(diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") || true)"
  [[ -z $changes ]] && ok "systemctl preset-all changes nothing (50-fenoa.preset covers every unit the build enables)" || no "a first boot's preset pass would change the image:"$'\n'"$changes"
else
  no "systemctl preset-all failed: $preset_out"
fi
# homectl's first-boot prompt would ask for a second user (see 50-fenoa.preset).
homed_firstboot="$(systemctl is-enabled systemd-homed-firstboot.service 2>/dev/null || true)"
case $homed_firstboot in
  enabled*) no "systemd-homed-firstboot.service is enabled (a second user prompt on first boot)" ;;
  *) ok "systemd-homed-firstboot.service is not enabled (${homed_firstboot:-not found})" ;;
esac

echo "== no Omarchy =="
leftovers="$(ls -d /usr/share/omarchy /usr/bin/omarchy* /usr/libexec/omarchy* /etc/omarchy* /usr/lib/systemd/system/omarchy* 2>/dev/null || true)"
[[ -z $leftovers ]] && ok "no omarchy files" || no "omarchy files present: $leftovers"

[[ -L /usr/local ]] && ok "/usr/local is a symlink (var-backed on bootc)" || no "/usr/local is not a symlink"

echo
if [[ $fail == "0" ]]; then echo "PLATFORM SMOKE: PASS"; else echo "PLATFORM SMOKE: FAIL"; fi
exit "$fail"
CHECKS
