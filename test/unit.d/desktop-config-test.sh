#!/bin/bash

# Static checks on the desktop layer's configuration, runnable without an image: the configs parse,
# the pieces that must agree with each other do (greetd ↔ tmpfiles ↔ greeter, skel ↔ /usr/share
# defaults, bindings ↔ shipped helpers, Flatpak manifest ↔ default apps), and — when Hyprland is
# installed, as on a Fenoa or omarchy-atomic machine — Hyprland itself verifies the Lua config.
# images/fenoa/hack/desktop-smoke.sh repeats the binary-backed checks inside the built image.

source "$(dirname "$0")/base-test.sh"
require_command python3

D="$ROOT/system/desktop"
hypr="$D/usr/share/fenoa/hypr"
skel_hypr="$D/etc/skel/.config/hypr/hyprland.lua"
skel_noctalia="$D/etc/skel/.config/noctalia/config.toml"
noctalia_defaults="$D/usr/share/fenoa/noctalia/fenoa.toml"
greetd="$D/etc/greetd/config.toml"
greeter="$D/usr/share/fenoa/greeter/greeter.toml"
tmpfiles="$D/usr/lib/tmpfiles.d/fenoa-greeter.conf"
containerfile="$ROOT/images/fenoa/Containerfile"

toml() { # toml FILE EXPR — evaluate a Python expression over the parsed TOML as `t`
  python3 - "$1" "$2" <<'PY'
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    t = tomllib.load(f)
print(eval(sys.argv[2]))
PY
}

# --- TOML parses -----------------------------------------------------------------------------------

for f in "$skel_noctalia" "$noctalia_defaults" "$greetd" "$greeter"; do
  toml "$f" 'len(t)' >/dev/null 2>"$ROOT/.toml.err" || fail "${f#"$ROOT"/} is valid TOML" "$(cat "$ROOT/.toml.err")"
done
rm -f "$ROOT/.toml.err"
pass "the Noctalia, greetd and greeter configs are valid TOML"

# --- Noctalia: skel includes the image defaults ----------------------------------------------------

include=$(toml "$skel_noctalia" 't["include"]["files"][0]')
[[ $include == "/usr/share/fenoa/noctalia/fenoa.toml" && -f $D$include ]] ||
  fail "the seeded Noctalia config includes the shipped defaults" "include: $include"
pass "the seeded Noctalia config includes /usr/share/fenoa/noctalia/fenoa.toml"

[[ "$(toml "$noctalia_defaults" 't["shell"]["polkit_agent"]')" == "True" ]] ||
  fail "Noctalia is the polkit agent (Fenoa ships no other)"
[[ "$(toml "$noctalia_defaults" 't["shell"]["launch_apps_custom_command"]')" == 'uwsm-app -- $CMD' ]] ||
  fail "apps launch through uwsm-app (app.slice, oomd-eligible)"
[[ "$(toml "$noctalia_defaults" 't["shell"]["greeter_sync"]["auto_sync"]')" == "True" ]] ||
  fail "the greeter follows the user's appearance (auto sync)"
pass "Noctalia defaults: polkit agent, uwsm-launched apps, greeter auto sync"

# --- greetd ↔ tmpfiles ↔ greeter ------------------------------------------------------------------

greeter_user=$(toml "$greetd" 't["default_session"]["user"]')
[[ $greeter_user == "greetd" ]] || fail "greetd runs the greeter as Fedora's greetd account" "got: $greeter_user"
[[ "$(toml "$greetd" 't["default_session"]["command"]')" == "/usr/libexec/fenoa-greeter-session" ]] ||
  fail "greetd launches the greeter through fenoa-greeter-session (the session's keyboard layout)"
wrapper="$D/usr/libexec/fenoa-greeter-session"
[[ -x $wrapper ]] || fail "fenoa-greeter-session ships and is executable"
grep -qF 'greeter="${FENOA_GREETER_SESSION:-/usr/bin/noctalia-greeter-session}"' "$wrapper" ||
  fail "fenoa-greeter-session execs noctalia-greeter-session (not the bare greeter binary)"
grep -qF 'lua="${FENOA_LUA:-/usr/bin/lua}"' "$wrapper" || fail "fenoa-greeter-session runs /usr/bin/lua"
resolver=$(sed -n 's/.*FENOA_KEYBOARD_LUA="\${FENOA_KEYBOARD_LUA:-\([^}]*\)}".*/\1/p' "$wrapper")
[[ $resolver == /usr/share/fenoa/hypr/fenoa/keyboard.lua && -f $D$resolver ]] ||
  fail "fenoa-greeter-session runs the resolver Hyprland uses" "got: ${resolver:-<unparsed>}"
grep -qF 'require("fenoa.keyboard")' "$hypr/fenoa/input.lua" || fail "Hyprland takes its layout from the same resolver"
grep -qE 'chmod 0755 .*/usr/libexec/fenoa-greeter-session' "$containerfile" ||
  fail "the Containerfile makes fenoa-greeter-session executable"
pass "greetd starts the greeter as greetd through fenoa-greeter-session, which shares Hyprland's layout resolver"

grep -qE "^d /var/lib/noctalia-greeter 0750 $greeter_user $greeter_user -$" "$tmpfiles" ||
  fail "the greeter state dir is 0750 and owned by the account greetd uses (else a blank greeter)" "$(cat "$tmpfiles")"
grep -qE '^L\+ /var/lib/noctalia-greeter/greeter.toml - - - - /usr/share/fenoa/greeter/greeter.toml$' "$tmpfiles" ||
  fail "greeter.toml is linked from the image"
grep -qE "^d /var/lib/greetd 0750 $greeter_user $greeter_user -$" "$tmpfiles" ||
  fail "greetd's home is recreated by tmpfiles (a bootc switch carries no /var/lib/greetd)"
cil="$D/usr/share/fenoa/selinux/fenoa-greeter.cil"
grep -qF '(filecon "/var/lib/noctalia-greeter(/.*)?" any (system_u object_r xdm_var_lib_t' "$cil" ||
  fail "the greeter state dir gets greetd's SELinux type (xdm_var_lib_t)"
grep -qF "semodule -i /usr/share/fenoa/selinux/fenoa-greeter.cil" "$containerfile" ||
  fail "the Containerfile installs the SELinux module"
pass "tmpfiles creates the greeter state dir and greetd's home, links greeter.toml; the state dir is xdm_var_lib_t"

session=$(toml "$greeter" 't["session"]["default"]')
[[ $session == "Hyprland (uwsm-managed)" ]] || fail "the greeter defaults to the uwsm Hyprland session" "got: $session"
grep -qF "Name=$session" "$containerfile" || fail "the Containerfile asserts the session name greeter.toml uses"
pass "the greeter's default session is '$session', asserted at build time"

rule="$D/usr/share/polkit-1/rules.d/49-fenoa-greeter-sync.rules"
grep -qF '"org.noctalia.greeter.sync-appearance"' "$rule" || fail "the sync rule targets the constrained action only"
grep -qF '"/usr/bin/noctalia-greeter-apply-appearance"' "$rule" || fail "the sync rule pins the helper path"
grep -qF 'subject.isInGroup("wheel")' "$rule" || fail "passwordless sync is limited to wheel"
grep -qF 'subject.active' "$rule" && grep -qF 'subject.local' "$rule" || fail "passwordless sync needs an active local session"
if grep -qF 'org.noctalia.greeter.apply-appearance"' "$rule"; then
  fail "the rule must never cover the legacy, path-only apply-appearance action"
fi
pass "the greeter-sync polkit rule is the narrow constrained-action rule"

# --- portals ---------------------------------------------------------------------------------------

# gnome-keyring's portal only volunteers under GNOME (UseIn=gnome), so the Hyprland session names it
# for the Secret interface. The /etc file replaces the package's whole hyprland-portals.conf, so it
# must keep the package's default backends too.
portals="$D/etc/xdg-desktop-portal/hyprland-portals.conf"
[[ -f $portals ]] || fail "the Hyprland portal routing ships in /etc/xdg-desktop-portal"
grep -qx '\[preferred\]' "$portals" || fail "hyprland-portals.conf has a [preferred] section"
grep -qx 'default=hyprland;gtk' "$portals" || fail "hyprland-portals.conf keeps the package's default=hyprland;gtk"
grep -qx 'org.freedesktop.impl.portal.Secret=gnome-keyring' "$portals" ||
  fail "the Secret portal is routed to gnome-keyring"
for p in gnome-keyring xdg-desktop-portal-hyprland xdg-desktop-portal-gtk; do
  sed 's/#.*//' "$ROOT/packages/desktop.packages" | awk 'NF{print $1}' | grep -qx "$p" ||
    fail "desktop.packages installs $p, which hyprland-portals.conf names"
done
pass "the Secret portal goes to gnome-keyring; the other portals stay hyprland, then gtk"

# --- Hyprland Lua -----------------------------------------------------------------------------------

grep -qF 'dofile("/usr/share/fenoa/hypr/bootstrap.lua")' "$skel_hypr" || fail "the seeded hyprland.lua loads the bootstrap"
[[ -f $hypr/bootstrap.lua && -f $hypr/fenoa/init.lua ]] || fail "the bootstrap and defaults ship"
# Noctalia's hyprland template appends an UNGUARDED require("noctalia") unless it finds that text;
# the seeded config carries it (in a comment) next to the guarded form.
grep -qF 'require("noctalia")' "$skel_hypr" || fail "the seeded config carries the require(\"noctalia\") marker"
grep -qF 'pcall(require, "noctalia")' "$skel_hypr" || fail "the palette is applied through a guarded require"
pass "the seeded hyprland.lua loads the defaults and guards Noctalia's palette module"

while read -r module; do
  [[ -f $hypr/${module//.//}.lua ]] || fail "required module ships: $module"
done < <(grep -hoE 'require\("fenoa\.[a-z_.]+"\)' "$hypr"/fenoa/*.lua | sed -E 's/require\("(.*)"\)/\1/' | sort -u)
pass "every fenoa.* module the defaults require ships"

luac_bin=$(command -v luac5.4 || command -v luac || true)
if [[ -n $luac_bin ]]; then
  for f in "$skel_hypr" "$hypr"/bootstrap.lua "$hypr"/fenoa/*.lua; do
    "$luac_bin" -p "$f" 2>"$ROOT/.lua.err" || fail "${f#"$ROOT"/} is valid Lua" "$(cat "$ROOT/.lua.err")"
  done
  rm -f "$ROOT/.lua.err"
  pass "the Hyprland config is valid Lua ($luac_bin)"
else
  pass "skipped Lua syntax check (no luac on PATH)"
fi

# Hyprland's own verifier rejects unknown keys, rule fields, match properties and dispatchers.
if command -v Hyprland >/dev/null 2>&1; then
  tmp=$(mktemp -d)
  mkdir -p "$tmp/hypr" "$tmp/run"
  chmod 0700 "$tmp/run"
  sed "s|/usr/share/fenoa/hypr|$tmp/defaults|g" "$skel_hypr" >"$tmp/hypr/hyprland.lua"
  cp -a "$hypr" "$tmp/defaults"
  sed -i "s|/usr/share/fenoa/hypr|$tmp/defaults|g" "$tmp/defaults/bootstrap.lua"
  out=$(HOME="$tmp" XDG_CONFIG_HOME="$tmp" XDG_RUNTIME_DIR="$tmp/run" timeout 60 Hyprland --verify-config -c "$tmp/hypr/hyprland.lua" 2>&1 || true)
  rm -rf "$tmp"
  [[ $out == *"config ok"* ]] || fail "Hyprland --verify-config accepts the shipped config" "$(printf '%s\n' "$out" | tail -8)"
  pass "Hyprland --verify-config: config ok ($(Hyprland --version 2>/dev/null | head -1))"
else
  pass "skipped Hyprland --verify-config (Hyprland not installed; desktop-smoke.sh runs it in the image)"
fi

# --- bindings ↔ helpers ----------------------------------------------------------------------------

while read -r helper; do
  [[ -x $D/usr/bin/$helper ]] || fail "a binding runs a shipped, executable helper: $helper"
done < <(grep -hoE '"fenoa-[a-z-]+' "$hypr"/fenoa/*.lua | tr -d '"' | sort -u)
pass "every fenoa-* helper the bindings run ships and is executable"

# The Noctalia IPC verbs the bindings use (checked against `noctalia msg --help` from 5.2.1).
known_verbs=" bar-toggle caffeine-toggle mic-mute media nightlight-toggle notification-clear-active notification-dnd-toggle notification-invoke-latest panel-toggle screenshot-fullscreen screenshot-region session settings-toggle volume-down volume-mute volume-up window-switcher brightness-down brightness-up "
while read -r verb; do
  [[ $known_verbs == *" $verb "* ]] || fail "binding uses a known Noctalia IPC verb: $verb"
done < <(grep -hoE 'noctalia\("[a-z-]+' "$hypr"/fenoa/bindings.lua | sed -E 's/noctalia\("//' | sort -u)
pass "every Noctalia IPC verb the bindings use exists"

grep -qF 'switch:on:Apple SMC power/lid events' "$hypr/fenoa/bindings.lua" ||
  fail "the lid binding uses the Apple Silicon switch name"
pass "the lid binding uses the Apple Silicon switch name"

# With lock restore on, a second locker started while the screen is locked replaces the live lock
# screen and can unlock.
grep -qE '^[[:space:]]*allow_session_lock_restore = false,' "$hypr/fenoa/looknfeel.lua" ||
  fail "a second locker cannot replace the live session lock (allow_session_lock_restore = false)"
pass "a second locker cannot replace the live session lock"

# --- Flatpak app set ↔ default apps ----------------------------------------------------------------

manifest="$D/usr/share/flatpak/preinstall.d/fenoa.preinstall"
mime="$D/usr/share/applications/hyprland-mimeapps.list"
groups=$(grep -cE '^\[Flatpak Preinstall ' "$manifest")
branches=$(grep -cE '^Branch=stable$' "$manifest")
(( groups > 0 && groups == branches )) || fail "every preinstall group pins Branch=stable ($groups groups, $branches stable)"
pass "every preinstall group pins Branch=stable"

for app in com.brave.Browser org.gnome.Loupe org.gnome.Evince org.libreoffice.LibreOffice md.obsidian.Obsidian \
           org.localsend.localsend_app com.obsproject.Studio; do
  grep -qF "[Flatpak Preinstall $app]" "$manifest" || fail "the Flatpak set includes $app"
done
pass "the Flatpak set: Brave, Loupe, Evince, LibreOffice, Obsidian, LocalSend, OBS Studio (Fedora's build)"

while read -r app; do
  case $app in
    com.brave.Browser|org.gnome.Loupe|org.gnome.Evince)
      grep -qF "[Flatpak Preinstall $app]" "$manifest" || fail "the default app $app is in the Flatpak preinstall set"
      ;;
  esac
done < <(sed -n 's/^[^=]*=\(.*\)\.desktop$/\1/p' "$mime" | sort -u)
grep -qF 'x-scheme-handler/https=com.brave.Browser.desktop' "$mime" || fail "Brave is the default browser"
pass "the Flatpak default apps in mimeapps are all preinstalled"

# --- packages --------------------------------------------------------------------------------------

packages="$ROOT/packages/desktop.packages"
dupes=$(sed 's/#.*//' "$packages" | awk 'NF{print $1}' | sort | uniq -d)
[[ -z $dupes ]] || fail "desktop.packages has no duplicates" "$dupes"
for p in noctalia noctalia-greeter greetd lua uwsm adw-gtk3-theme foot udiskie wf-recorder adobe-source-code-pro-fonts cascadia-mono-nf-fonts; do
  sed 's/#.*//' "$packages" | awk 'NF{print $1}' | grep -qx "$p" || fail "desktop.packages installs $p"
done
if sed 's/#.*//' "$packages" | awk 'NF{print $1}' | grep -qxE 'sddm|quickshell'; then
  fail "desktop.packages carries no SDDM or Quickshell"
fi
if sed 's/#.*//' "$packages" | awk 'NF{print $1}' | grep -qx 'obs-studio'; then
  fail "OBS Studio is Fedora's Flatpak, not the native RPM"
fi
pass "desktop.packages installs the shell, greeter and session, and nothing from Omarchy's stack"

# The COPR carries -git builds of noctalia/noctalia-greeter; they must never win over Fedora/Terra.
grep -qF "excludepkgs=gtk4* gtk3* pango* cairo* noctalia* quickshell*" "$containerfile" ||
  fail "the Hyprland COPR is excluded from GTK, Noctalia, the greeter and Quickshell"
pass "the Hyprland COPR cannot replace GTK, Noctalia, the greeter or Quickshell"

# LocalSend can only discover and receive with its port open in the default zone.
svc="$D/usr/lib/firewalld/services/localsend.xml"
grep -qF '<port protocol="tcp" port="53317"/>' "$svc" && grep -qF '<port protocol="udp" port="53317"/>' "$svc" ||
  fail "the localsend firewalld service opens TCP and UDP 53317"
grep -qF -- '--add-service=localsend' "$containerfile" || fail "the Containerfile enables the localsend service"
pass "LocalSend's port 53317 (TCP+UDP) is opened in the default firewalld zone"

grep -qF 'udiskie --automount' "$hypr/fenoa/autostart.lua" || fail "udiskie is started with the session"
pass "udiskie automounts removable drives from session start"

# The default font: Source Code Pro as "monospace", used by foot, the shell and (via sync) the greeter.
grep -qF '<string>Source Code Pro</string>' "$D/etc/fonts/conf.d/50-fenoa-monospace.conf" ||
  fail "fontconfig makes Source Code Pro the monospace font"
grep -qF 'mode="prepend_first" binding="strong"' "$D/etc/fonts/conf.d/50-fenoa-monospace.conf" ||
  fail "the monospace preference wins over other packages' preferences"
[[ "$(toml "$noctalia_defaults" 't["shell"]["font_family"]')" == "monospace" ]] || fail "the Noctalia shell uses the monospace font"
grep -qx 'font=monospace:size=11' "$D/etc/skel/.config/foot/foot.ini" || fail "foot uses monospace at size 11"
pass "Source Code Pro is the default monospace for foot, the shell and the greeter"

# uwsm sources env.d with sh.
sh -n "$D/usr/share/uwsm/env.d/10-fenoa" || fail "uwsm env.d/10-fenoa is valid sh"
pass "uwsm env.d/10-fenoa is valid sh"
