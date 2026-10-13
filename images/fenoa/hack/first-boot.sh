#!/bin/bash
# e2e test of Fenoa's FIRST-BOOT user setup against a built image (container; no boot).
#
# Covers the boot-time half of first boot: fenoa-firstboot-user creating the primary user from a
# preseed (zsh as its login shell, Fedora's stock ~/.zshrc seeded from /etc/skel), the marker
# gating, preseed scrubbing and idempotence, and — on the desktop image — /etc/skel seeding the new
# home with the Hyprland/Noctalia config. Also validates the shipped units with systemd-analyze.
#
# The unit's GATING is covered in A0/A: it gates on its own marker, not ConditionFirstBoot. The image
# ships /etc/machine-id as "uninitialized", so systemd does detect an install's first boot, but it
# commits a real ID during that boot; the retry after an aborted prompt or a failed useradd happens
# on a boot that is no longer a first boot. We populate /etc/machine-id before provisioning, so this
# test runs in exactly that state.
#
# NOT covered here — needs a real booted session (images/boottest/ on a Mac): the tty1 interactive
# prompt and the greeter handoff.
#
#   ./images/fenoa/hack/first-boot.sh [IMAGE]           # default fenoa-platform:44
#   DESKTOP=1 ./images/fenoa/hack/first-boot.sh fenoa:44 # also assert the skel desktop config
set -euo pipefail
IMAGE="${1:-fenoa-platform:44}"
ENGINE="${ENGINE:-podman}"
DESKTOP="${DESKTOP:-0}"

echo "== first-boot e2e: $IMAGE (via $ENGINE, desktop=$DESKTOP) =="
"$ENGINE" run --rm -i -e DESKTOP="$DESKTOP" --entrypoint bash "$IMAGE" -s <<'CHECKS'
set -uo pipefail
fail=0
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
no() { printf '  \033[31m✗ %s\033[0m\n' "$1"; fail=1; }
note() { printf '  \033[2m·\033[0m %s\n' "$1"; }

U=tester

echo "== A0) the unit gates on a marker, not ConditionFirstBoot =="
unit=/usr/lib/systemd/system/fenoa-firstboot-user.service
unit_text="$(cat "$unit" 2>/dev/null || true)"
case $unit_text in
  *$'\n'ConditionFirstBoot*) no "unit gates on ConditionFirstBoot — it skips whenever /etc/machine-id is already set" ;;
  *) ok "unit does not gate on ConditionFirstBoot" ;;
esac
unit_marker="$(sed -n 's/^ConditionPathExists=!//p' "$unit")"
[[ -n $unit_marker ]] && ok "unit gates on marker: $unit_marker" || no "unit has no marker condition"
case $unit_text in
  *$'\n'Before=display-manager.service*) ok "ordered before the display manager" ;;
  *) no "not ordered before the display manager" ;;
esac

echo "== A) fenoa-firstboot-user (preseed) creates the primary user =="
# Run as a later boot would: a POPULATED /etc/machine-id (ConditionFirstBoot=no). Written directly:
# systemd-machine-id-setup leaves the image's "uninitialized" in place.
printf '%s\n' "$(head -c16 /dev/urandom | od -An -tx1 | tr -d ' \n')" >/etc/machine-id
[[ "$(cat /etc/machine-id)" =~ ^[0-9a-f]{32}$ ]] && ok "/etc/machine-id populated (simulating a non-first boot)" || no "could not populate /etc/machine-id"
# And a systemd DynamicUser= account, the way nss-systemd surfaces one: speakersafetyd on Asahi runs
# at uid 62454. A naive uid>=1000 "is there a human user" test counts it, and the helper then skips
# on a machine with no human user at all.
echo 'speakersafetyd:x:62454:62454:Dynamic User:/:/usr/sbin/nologin' >>/etc/passwd
ok "seeded a DynamicUser-range account (uid 62454)"
install -d /etc/fenoa
cat >/etc/fenoa/firstboot-user.conf <<EOF
FENOA_USER=$U
FENOA_USER_FULLNAME="Test User"
FENOA_USER_GROUPS="wheel"
FENOA_USER_PASSWORD=correcthorsebattery
EOF
/usr/libexec/fenoa-firstboot-user
getent passwd "$U" >/dev/null && ok "user '$U' created" || no "user '$U' not created"
groups="$(id -nG "$U" 2>/dev/null || true)"
case " $groups " in *" wheel "*) ok "in 'wheel' (sudo)" ;; *) no "not in wheel ($groups)" ;; esac
pstatus="$(passwd -S "$U" 2>/dev/null | awk '{print $2}')"
[[ $pstatus == "P" ]] && ok "password set" || no "password not set (status: ${pstatus:-unknown})"
home="$(getent passwd "$U" | cut -d: -f6)"
note "home = $home"
[[ -d $home ]] && ok "home dir exists" || no "home dir missing"
login_shell="$(getent passwd "$U" | cut -d: -f7)"
[[ $login_shell == "/usr/bin/zsh" ]] && ok "login shell is /usr/bin/zsh" || no "login shell is '${login_shell:-?}', not /usr/bin/zsh"
[[ -f $home/.zshrc ]] && ok "~/.zshrc seeded from /etc/skel (Fedora's stock config)" || no "~/.zshrc missing — skel not seeded"

if [[ $DESKTOP == "1" ]]; then
  echo "== B) /etc/skel seeded the desktop config into the new home =="
  [[ -f $home/.config/hypr/hyprland.lua ]] && ok "~/.config/hypr/hyprland.lua" || no "~/.config/hypr/hyprland.lua missing — skel not seeded"
  [[ -f $home/.config/noctalia/config.toml ]] && ok "~/.config/noctalia/config.toml" || no "~/.config/noctalia/config.toml missing"
  owner="$(stat -c %U "$home/.config/hypr/hyprland.lua" 2>/dev/null || true)"
  [[ $owner == "$U" ]] && ok "seeded config is owned by $U" || no "seeded config owned by '${owner:-?}', not $U"
fi

echo "== C) done marker, preseed shredded, idempotent re-run =="
# Without the marker the unit's condition never turns false: it would re-run every boot and take
# tty1 from getty each time (Conflicts=getty@tty1.service).
if [[ -n ${unit_marker:-} ]]; then
  [[ -f $unit_marker ]] && ok "done marker written at $unit_marker" || no "done marker $unit_marker not written — unit would re-run every boot"
fi
[[ ! -e /etc/fenoa/firstboot-user.conf ]] && ok "preseed conf shredded after use" || no "preseed conf left behind (holds a secret)"
rerun="$(/usr/libexec/fenoa-firstboot-user 2>&1 || true)"
case $rerun in *"already exists"*) ok "re-run is a no-op (a user already exists)" ;; *) no "re-run did not self-skip: $rerun" ;; esac

echo "== D) systemd-analyze verify on shipped units (report) =="
if command -v systemd-analyze >/dev/null 2>&1; then
  for u in /usr/lib/systemd/system/fenoa-*.service /usr/lib/systemd/system/fenoa-*.timer; do
    [[ -e $u ]] || continue
    if systemd-analyze verify "$u" >/tmp/sv.log 2>&1; then
      ok "verify $(basename "$u")"
    else
      note "verify $(basename "$u"): $(grep -m1 . /tmp/sv.log 2>/dev/null) (non-fatal in a container)"
    fi
  done
else
  note "systemd-analyze absent"
fi

echo
if [[ $fail == "0" ]]; then echo "FIRST-BOOT E2E: PASS"; else echo "FIRST-BOOT E2E: FAIL"; fi
exit "$fail"
CHECKS
