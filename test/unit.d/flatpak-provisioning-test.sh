#!/bin/bash

# Fenoa installs its Flatpak app set on first boot via Fedora/flatpak's UPSTREAM `flatpak preinstall`:
# manifests in /usr/share/flatpak/preinstall.d plus the CLI, which owns the install logic,
# idempotency and user opt-out. Fedora packages the CLI but no boot unit, so
# fenoa-flatpak-preinstall.service is the thin wrapper that runs it (the Bluefin/Aurora mechanism).
# This file pins the platform half: the units and the build wiring. The app set itself is the
# desktop layer's (test/unit.d/desktop-config-test.sh).
#
# Three first-boot failures shaped the units, all invisible to CI (the image e2e job never boots):
#  - the image masks NetworkManager-wait-online, so network-online.target is reached before DNS; a
#    remote fetched over the network at boot fails every time. The remote is registered from a LOCAL
#    baked file.
#  - offline, `flatpak preinstall` skips every ref it cannot reach and EXITS 0, so a unit started
#    at boot with Restart=on-failure "succeeded" without installing anything, and never retried.
#    A timer now starts it, and fenoa-online skips it until the remotes answer over HTTPS (a name
#    that merely resolves, as behind a captive portal, is not enough).
#  - `flatpak preinstall` needs a D-Bus SESSION bus, which a system service lacks: without
#    dbus-run-session it dies with "Cannot autolaunch D-Bus without X11 $DISPLAY".

source "$(dirname "$0")/base-test.sh"

units="$ROOT/system/platform/usr/lib/systemd/system"
unit="$units/fenoa-flatpak-preinstall.service"
timer="$units/fenoa-flatpak-preinstall.timer"
update_service="$units/fenoa-flatpak-update.service"
update_timer="$units/fenoa-flatpak-update.timer"
containerfile="$ROOT/images/fenoa/Containerfile"
preset="$ROOT/system/platform/usr/lib/systemd/system-preset/50-fenoa.preset"
online_check='ExecCondition=/usr/libexec/fenoa-online dl.flathub.org'
update_online_check='ExecCondition=/usr/libexec/fenoa-online --wait=300 dl.flathub.org'

for f in "$unit" "$timer" "$update_service" "$update_timer" "$containerfile" "$preset"; do
  [[ -f $f ]] || fail "ships ${f#"$ROOT"/}"
done
pass "the preinstall service/timer, update service/timer, Containerfile and preset exist"

# --- preinstall: started by its timer, once the remotes answer -----------------------------------

# A boot target would start it before Wi-Fi is up, and offline it exits 0 having installed nothing.
if grep -qE '^\[Install\]|^(WantedBy|RequiredBy|UpheldBy|Alias|Also)=' "$unit"; then
  fail "the preinstall service has no [Install] section (only its timer starts it)" "$(grep -nE '^\[Install\]|By=' "$unit")"
fi
pass "the preinstall service is static: only its timer starts it"

grep -qxF "$online_check" "$unit" ||
  fail "the preinstall is skipped until Flathub answers (fenoa-online, no --wait)" "$(grep -n '^Exec' "$unit")"
pass "the preinstall is skipped until dl.flathub.org answers"

# RemainAfterExit is what ends the timer's retries once a run succeeds; a failure is retried by the
# timer, so Restart= would only add a second, faster retry loop.
grep -qx 'Type=oneshot' "$unit" || fail "the preinstall service is a oneshot"
grep -qx 'RemainAfterExit=yes' "$unit" ||
  fail "a successful run stays active (RemainAfterExit=yes), which stops the timer for the boot"
if grep -qE '^(Restart|RestartSec|StartLimitIntervalSec|StartLimitBurst)=' "$unit"; then
  fail "no Restart=/StartLimit*= (the timer does the retrying)" "$(grep -nE '^(Restart|StartLimit)' "$unit")"
fi
pass "a oneshot that stays active once it succeeds, with no Restart= of its own"

# A unit skipped by a Condition*= is neither active nor failed, so an OnUnitInactiveSec= timer
# starts it again every interval, forever. "Not yet" has to be ExecCondition= or a failure.
if grep -qE '^(Condition|Assert)[A-Za-z]*=' "$unit"; then
  fail "no Condition*=/Assert*= (the timer would loop on it)" "$(grep -nE '^(Condition|Assert)' "$unit")"
fi
pass "no Condition*= the timer could loop on"

# Ordered before the system helper, a user's `flatpak install` during a long preinstall would wait
# for the whole oneshot and fail on the D-Bus timeout; flatpak reads the remotes.d file by itself.
if grep -qE '^Before=.*flatpak-system-helper' "$unit"; then
  fail "the preinstall is not ordered before flatpak-system-helper.service" "$(grep -n '^Before=' "$unit")"
fi
pass "the preinstall does not hold back flatpak-system-helper.service"

grep -qE '^OnBootSec=' "$timer" || fail "the timer starts the preinstall after boot (OnBootSec=)"
grep -qE '^OnUnitInactiveSec=' "$timer" ||
  fail "the timer starts a skipped or failed run again (OnUnitInactiveSec=)"
accuracy=$(sed -n 's/^AccuracySec=//p' "$timer")
[[ $accuracy =~ ^([0-9]+)s$ ]] && (( BASH_REMATCH[1] < 60 )) ||
  fail "the timer sets an AccuracySec= under a minute (the default 1min lets each start slip)" "got: ${accuracy:-<unset>}"
target=$(sed -n 's/^Unit=//p' "$timer")
[[ -z $target || $target == "fenoa-flatpak-preinstall.service" ]] || fail "the timer starts fenoa-flatpak-preinstall.service" "Unit=$target"
grep -qx 'WantedBy=timers.target' "$timer" || fail "the timer is wired into timers.target"
pass "the timer starts the preinstall after boot and again while it is skipped or failing (AccuracySec=$accuracy)"

grep -qE '^ExecStartPre=/usr/bin/flatpak remote-add .*--system .*flathub /etc/flatpak/remotes.d/flathub\.flatpakrepo$' "$unit" ||
  fail "Flathub is added from the baked local file, without a session bus" "$(grep -n Exec "$unit")"
grep -qE '^ExecStartPre=.*remote-add .*flathub https?:' "$unit" &&
  fail "Flathub must not be fetched over the network at boot" "$(grep -n Exec "$unit")"
pass "Flathub is registered from the baked local file before preinstall runs"

# Flathub is the only remote added; every app in the set is on it. preinstall takes each app from the
# first remote by priority and breaks ties alphabetically, and a Fedora Atomic switched to Fenoa
# already has a "fedora" remote at the default priority 1, so Flathub has to be set above that.
if grep -qE '^ExecStartPre=.*remote-add .*(fedora|registry\.fedoraproject\.org)' "$unit"; then
  fail "no Fedora remote is added (Flathub carries the whole app set)" "$(grep -n Exec "$unit")"
fi
flathub_prio=$(sed -n 's/^ExecStartPre=.*remote-modify --system --prio=\([0-9]*\) flathub$/\1/p' "$unit")
[[ -n $flathub_prio ]] || fail "Flathub's priority is set" "$(grep -n prio "$unit")"
(( flathub_prio > 1 )) || fail "Flathub outranks a remote at the default priority 1 (got $flathub_prio)"
pass "Flathub is the only remote added, at priority $flathub_prio, above any existing Fedora remote"

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

# The daily catch-up run fires at boot or on resume, before Wi-Fi is back, and nothing retries it:
# wait (bounded) for the remotes, then skip rather than fail. The metered check has to come after
# the wait, or it judges "no connection yet" instead of the connection that comes up.
grep -qxF "$update_online_check" "$update_service" ||
  fail "the update service waits up to 5 minutes for the remotes (fenoa-online --wait=300)" "$(grep -n '^Exec' "$update_service")"
first_condition=$(grep -m1 '^ExecCondition=' "$update_service")
[[ $first_condition == "$update_online_check" ]] ||
  fail "the network wait comes before the metered check" "$(grep -n '^ExecCondition=' "$update_service")"
# A oneshot has no start timeout unless one is set; if one ever is, it must outlast the wait.
timeout=$(sed -n 's/^TimeoutStartSec=//p' "$update_service")
if [[ -n $timeout && $timeout != "infinity" ]]; then
  [[ $timeout =~ ^([0-9]+)min$ ]] && (( BASH_REMATCH[1] >= 6 )) ||
    fail "the start timeout leaves room for the 5-minute wait" "TimeoutStartSec=$timeout"
fi
pass "the update service waits up to 5 minutes for the remotes, then checks for a metered link"

grep -qE '^OnCalendar=' "$update_timer" || fail "the timer has a schedule"
grep -qE '^Persistent=true' "$update_timer" || fail "the timer catches up after downtime (Persistent)"
grep -qE '^WantedBy=timers\.target' "$update_timer" || fail "the timer is wired into timers.target"
pass "the timer is scheduled, persistent, and wired into timers.target"

# --- build wiring -------------------------------------------------------------------------------

grep -qE 'remotes\.d/flathub\.flatpakrepo' "$containerfile" ||
  fail "the Containerfile bakes flathub.flatpakrepo into /etc/flatpak/remotes.d"
grep -qE 'systemctl mask flatpak-add-fedora-repos\.service' "$containerfile" ||
  fail "the Containerfile masks flatpak-add-fedora-repos.service so Flathub is authoritative"
enabled=$(containerfile_units enable <"$containerfile")
grep -qx 'fenoa-flatpak-preinstall\.timer' <<<"$enabled" ||
  fail "the Containerfile enables fenoa-flatpak-preinstall.timer" "$enabled"
grep -qx 'fenoa-flatpak-preinstall\.service' <<<"$enabled" &&
  fail "the Containerfile does not enable the preinstall service itself (it would run before the network)"
grep -qx 'fenoa-flatpak-update\.timer' <<<"$enabled" ||
  fail "the Containerfile enables fenoa-flatpak-update.timer" "$enabled"
grep -qE 'systemctl mask NetworkManager-wait-online\.service' "$containerfile" ||
  fail "the Containerfile masks NetworkManager-wait-online (why the units check with fenoa-online)"
pass "the Containerfile bakes the remote, masks Fedora's, and enables the timers"

grep -qx 'enable fenoa-flatpak-preinstall.timer' "$preset" || fail "50-fenoa.preset enables the preinstall timer"
grep -qE '^(enable|disable) fenoa-flatpak-preinstall\.service$' "$preset" &&
  fail "50-fenoa.preset has no line for the static preinstall service" "$(grep -n 'fenoa-flatpak-preinstall' "$preset")"
pass "50-fenoa.preset lists the preinstall timer, not the static service"
