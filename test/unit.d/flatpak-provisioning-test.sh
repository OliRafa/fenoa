#!/bin/bash

# Fenoa installs its Flatpak app set on first boot via Fedora/flatpak's UPSTREAM `flatpak preinstall`:
# manifests in /usr/share/flatpak/preinstall.d plus the CLI, which owns the install logic,
# idempotency and user opt-out. Fedora packages the CLI but no boot unit, so
# fenoa-flatpak-preinstall.service is the thin wrapper that runs it (the Bluefin/Aurora mechanism).
# This file pins the platform half: the units and the build wiring. The app set itself is the
# desktop layer's (test/unit.d/desktop-config-test.sh).
#
# Two first-boot failures shaped the unit, both invisible to CI (the image e2e job never boots):
#  - the image masks NetworkManager-wait-online, so network-online.target is reached before DNS; a
#    remote fetched over the network at boot fails every time. The remote is registered from a LOCAL
#    baked file and the wrapper retries out of the boot path.
#  - `flatpak preinstall` needs a D-Bus SESSION bus, which a system service lacks: without
#    dbus-run-session it dies with "Cannot autolaunch D-Bus without X11 $DISPLAY".

source "$(dirname "$0")/base-test.sh"

units="$ROOT/system/platform/usr/lib/systemd/system"
unit="$units/fenoa-flatpak-preinstall.service"
update_service="$units/fenoa-flatpak-update.service"
update_timer="$units/fenoa-flatpak-update.timer"
containerfile="$ROOT/images/fenoa/Containerfile"

for f in "$unit" "$update_service" "$update_timer" "$containerfile"; do
  [[ -f $f ]] || fail "ships ${f#"$ROOT"/}"
done
pass "the preinstall unit, update service/timer and Containerfile exist"

# --- preinstall unit ----------------------------------------------------------------------------

grep -q '^WantedBy=multi-user\.target' "$unit" || fail "unit is wired into multi-user.target"
pass "unit is wired into multi-user.target"

grep -q '^Restart=on-failure' "$unit" || fail "unit retries on failure"
grep -q '^RestartSec=' "$unit" || fail "unit spaces its retries out (RestartSec)"
pass "unit retries a failed pull rather than giving up until reboot"

# systemd ignores StartLimitIntervalSec in [Service]; it must be in [Unit] to disable the limiter.
awk '/^\[/{sec=$0} /^StartLimitIntervalSec=0/{print sec}' "$unit" | grep -q '^\[Unit\]' ||
  fail "StartLimitIntervalSec=0 is in [Unit] so the retry limiter is actually disabled" \
    "$(grep -n 'StartLimitIntervalSec' "$unit")"
pass "the retry limiter is disabled in [Unit]"

grep -qE '^ExecStartPre=/usr/bin/flatpak remote-add .*--system .*/etc/flatpak/remotes.d/flathub\.flatpakrepo' "$unit" ||
  fail "the remote is added from the baked local file, without a session bus" "$(grep -n Exec "$unit")"
grep -qE '^ExecStartPre=.*remote-add .*http' "$unit" &&
  fail "the remote must not be fetched over the network at boot" "$(grep -n Exec "$unit")"
pass "the remote is registered from the baked local file before preinstall runs"

grep -qE '^ExecStart=/usr/bin/dbus-run-session -- /usr/bin/flatpak preinstall .*-y' "$unit" ||
  fail "preinstall runs under dbus-run-session (needs a D-Bus session bus)" "$(grep -n Exec "$unit")"
pass "the install is delegated to upstream 'flatpak preinstall', under a D-Bus session bus"

# No stamp of our own: preinstall runs every boot so additions apply and user removals stick.
if grep -vE '^[[:space:]]*#' "$unit" | grep -qiE 'stamp|-done'; then
  fail "the wrapper does not gate on a stamp" "$(grep -vE '^[[:space:]]*#' "$unit" | grep -niE 'stamp|-done')"
fi
pass "the wrapper carries no stamp; idempotency is upstream's job"

# --- update timer -------------------------------------------------------------------------------

grep -qE '^ExecStart=/usr/bin/dbus-run-session -- /usr/bin/flatpak update --system' "$update_service" ||
  fail "the update service updates the SYSTEM installation under dbus-run-session" "$(grep -n Exec "$update_service")"
grep -qE '^ExecCondition=.*Metered' "$update_service" || fail "the update service skips metered connections"
pass "the update service updates the system installation and spares metered links"

grep -qE '^OnCalendar=' "$update_timer" || fail "the timer has a schedule"
grep -qE '^Persistent=true' "$update_timer" || fail "the timer catches up after downtime (Persistent)"
grep -qE '^WantedBy=timers\.target' "$update_timer" || fail "the timer is wired into timers.target"
pass "the timer is scheduled, persistent, and wired into timers.target"

# --- build wiring -------------------------------------------------------------------------------

grep -qE 'remotes\.d/flathub\.flatpakrepo' "$containerfile" ||
  fail "the Containerfile bakes flathub.flatpakrepo into /etc/flatpak/remotes.d"
grep -qE 'systemctl mask flatpak-add-fedora-repos\.service' "$containerfile" ||
  fail "the Containerfile masks flatpak-add-fedora-repos.service so Flathub is authoritative"
grep -qE 'systemctl enable .*fenoa-flatpak-preinstall\.service' "$containerfile" ||
  fail "the Containerfile enables fenoa-flatpak-preinstall.service"
grep -qE 'systemctl enable .*fenoa-flatpak-update\.timer' "$containerfile" ||
  fail "the Containerfile enables fenoa-flatpak-update.timer"
grep -qE 'systemctl mask NetworkManager-wait-online\.service' "$containerfile" ||
  fail "the Containerfile masks NetworkManager-wait-online (the retry design assumes it)"
pass "the Containerfile bakes the remote, masks Fedora's, and enables the units"
