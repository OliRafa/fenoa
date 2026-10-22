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

# A plugin widget shows only while its plugin is enabled, and AI Usage only draws what the
# ai-usagebar CLI reports, which nothing but the image provides.
[[ "$(toml "$noctalia_defaults" 'all(w["type"].split(":")[0] in t["plugins"]["enabled"]
  for w in t["widget"].values() if "/" in w.get("type", ""))')" == "True" ]] ||
  fail "every plugin widget in the defaults belongs to an enabled plugin"
[[ "$(toml "$noctalia_defaults" 't["widget"]["ai_usage"]["type"]')" == "felipeartur/ai-usagebar:bar" ]] ||
  fail "the ai_usage widget is the AI Usage plugin's bar widget"
[[ "$(toml "$noctalia_defaults" '"ai_usage" in t["bar"]["default"]["end"]')" == "True" ]] ||
  fail "the AI Usage widget is on the bar"
grep -qF 'install -Dm0755 "$tmp/ai-usagebar" /usr/bin/ai-usagebar' "$containerfile" ||
  fail "the Containerfile installs the ai-usagebar CLI the plugin runs"
grep -qE '^ARG AI_USAGEBAR_KEY=[0-9A-F]{40}$' "$containerfile" ||
  fail "the ai-usagebar release is checked against a pinned signing-key fingerprint"
pass "the AI Usage plugin is enabled and on the bar, and the image carries its signed ai-usagebar CLI"

[[ "$(toml "$noctalia_defaults" 't["widget"]["calculator"]["type"]')" == "yuuto/calculator:bar" ]] ||
  fail "the calculator widget is the Calculator plugin's bar widget"
[[ "$(toml "$noctalia_defaults" '"calculator" in t["bar"]["default"]["end"]')" == "True" ]] ||
  fail "the Calculator widget is on the bar"
pass "the Calculator plugin is enabled and on the bar"

[[ "$(toml "$noctalia_defaults" 't["widget"]["pomodoro"]["type"]')" == "thepunkoff/pomodoro:widget" ]] ||
  fail "the pomodoro widget is the Pomodoro Timer plugin's bar widget"
[[ "$(toml "$noctalia_defaults" '"pomodoro" in t["bar"]["default"]["end"]')" == "True" ]] ||
  fail "the Pomodoro Timer widget is on the bar"
sed 's/#.*//' "$ROOT/packages/desktop.packages" | awk 'NF{print $1}' | grep -qx ffmpeg-free ||
  fail "desktop.packages installs ffmpeg-free (ffplay, which the Pomodoro Timer plugin depends on)"
pass "the Pomodoro Timer plugin is enabled and on the bar, and ffplay is installed for its sounds"

[[ "$(toml "$noctalia_defaults" 't["widget"]["airpods"]["type"]')" == "harveywuk/airpods:airpods" ]] ||
  fail "the airpods widget is the AirPods plugin's bar widget"
[[ "$(toml "$noctalia_defaults" '"airpods" in t["bar"]["default"]["end"]')" == "True" ]] ||
  fail "the AirPods widget is on the bar"
grep -qE '^ARG LIBREPODS_COMMIT=[0-9a-f]{40}$' "$containerfile" || fail "librepods is built from a pinned commit"
grep -qF 'COPY --from=librepods /out/usr/bin/librepods /out/usr/bin/librepods-ctl /usr/bin/' "$containerfile" ||
  fail "the image carries the librepods daemon and the librepods-ctl the plugin runs"
grep -qF 'systemctl --global enable librepods.service' "$containerfile" || fail "librepods runs for every user"
for p in qt6-qtconnectivity qt6-qtbase-gui qt6-qtdeclarative; do
  sed 's/#.*//' "$ROOT/packages/desktop.packages" | awk 'NF{print $1}' | grep -qx "$p" ||
    fail "desktop.packages installs $p, whose Qt libraries librepods links"
done
pass "the AirPods plugin is enabled and on the bar, and the image runs its librepods daemon from a pinned commit"

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

# --- presets: a first boot keeps the login screen ----------------------------------------------------

desktop_stage=$(sed -n '/^FROM platform AS desktop$/,$p' "$containerfile")
[[ -n $desktop_stage ]] || fail "the Containerfile has a desktop stage"
check_preset "$D/usr/lib/systemd/system-preset/50-fenoa-desktop.preset" "$desktop_stage"
grep -qx 'enable greetd.service' "$D/usr/lib/systemd/system-preset/50-fenoa-desktop.preset" ||
  fail "50-fenoa-desktop.preset enables greetd"
pass "50-fenoa-desktop.preset covers greetd and graphical.target, read before Fedora's presets"
# User units: the same rule against Fedora's user-preset 99-default-disable.preset, for the units the
# stage enables with `systemctl --global` (which containerfile_units leaves out).
global_units=$(printf '%s\n' "$desktop_stage" | sed -e '/^[[:space:]]*#/d' | sed -e ':a' -e '/\\$/N; s/\\\n//; ta' |
  grep -oE 'systemctl --global (enable|disable) [^;&|]*' | sed 's/--global //' || true)
[[ -n $global_units ]] || fail "the desktop stage enables user units globally (librepods)"
check_preset "$D/usr/lib/systemd/user-preset/50-fenoa-desktop.preset" "$global_units"
pass "user-preset/50-fenoa-desktop.preset covers the user units the desktop stage enables (librepods)"
check_machine_id_last desktop "$desktop_stage"
pass "the desktop stage ships /etc/machine-id as uninitialized again, after its package installs"

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

# --- one binding per key ---------------------------------------------------------------------------

# Two bindings on one chord both fire, and --verify-config accepts that. Run bindings.lua against a
# stub `hl` that prints every chord it binds, modifiers sorted: the monitor and group keys are built
# in loops, which a grep would miss.
lua_bin=$(command -v lua5.4 || command -v lua || true)
if [[ -n $lua_bin ]]; then
  chords=$("$lua_bin" - "$hypr" <<'LUA' 2>&1
local dir = arg[1]
package.path = dir .. "/?.lua;" .. package.path
local stub
stub = setmetatable({}, { __index = function() return stub end, __call = function() return stub end })
hl = setmetatable({
  bind = function(keys)
    local parts = {}
    for part in keys:gmatch("[^+]+") do
      parts[#parts + 1] = (part:gsub("^%s+", ""):gsub("%s+$", ""):upper())
    end
    local key = table.remove(parts)
    table.sort(parts)
    parts[#parts + 1] = key
    print(table.concat(parts, " + "))
  end,
}, { __index = function() return stub end })
dofile(dir .. "/fenoa/bindings.lua")
LUA
  ) || fail "bindings.lua runs against a stub hl" "$chords"
  (( $(wc -l <<<"$chords") > 100 )) || fail "the stub saw every binding (else this check proves nothing)" "$chords"
  dupes=$(sort <<<"$chords" | uniq -d)
  [[ -z $dupes ]] || fail "no two bindings share a chord" "$dupes"
  pass "no two bindings share a chord ($(wc -l <<<"$chords") bindings)"
else
  pass "skipped the one-binding-per-chord check (no lua interpreter on PATH)"
fi

# --- bindings ↔ helpers ----------------------------------------------------------------------------

while read -r helper; do
  [[ -x $D/usr/bin/$helper ]] || fail "a binding runs a shipped, executable helper: $helper"
done < <(grep -hoE '"fenoa-[a-z-]+[ "]' "$hypr"/fenoa/*.lua | tr -d '" ' | sort -u)
pass "every fenoa-* helper the bindings run ships and is executable"

# uwsm-app also takes a desktop ID; the entry has to be in the overlay or come with a preinstalled
# Flatpak, or the key does nothing.
while read -r id; do
  [[ -f $D/usr/share/applications/$id ]] ||
    grep -qF "[Flatpak Preinstall ${id%.desktop}]" "$D/usr/share/flatpak/preinstall.d/fenoa.preinstall" ||
    fail "a binding launches a desktop entry the image ships: $id"
done < <(grep -hoE 'launch\("[A-Za-z0-9._-]+\.desktop"' "$hypr"/fenoa/bindings.lua | sed -E 's/^launch\("//; s/"$//' | sort -u)
pass "every desktop entry the bindings launch ships, in the overlay or as a preinstalled Flatpak"

# launch_or_focus(ID, CLASS) focuses a window of CLASS before launching ID; if CLASS is not the class
# the entry's window gets, every press opens another window.
focus_binds=$(grep -hoE 'launch_or_focus\("[^"]+", "[^"]+"\)' "$hypr"/fenoa/bindings.lua || true)
[[ -n $focus_binds ]] || fail "the bindings use launch_or_focus (else this check proves nothing)"
while IFS='"' read -r _ id _ class _; do
  entry="$D/usr/share/applications/$id"
  [[ -f $entry ]] || fail "a launch_or_focus binding launches a desktop entry the overlay ships: $id"
  grep -qx "StartupWMClass=$class" "$entry" ||
    fail "launch_or_focus looks for the class $id's window gets ($class)" "$(grep '^StartupWMClass=' "$entry")"
done <<<"$focus_binds"
pass "every launch_or_focus binding looks for the class its desktop entry's window gets"

# The Noctalia IPC verbs the bindings use (checked against `noctalia msg --help` from 5.2.1).
known_verbs=" bar-toggle caffeine-toggle mic-mute media nightlight-toggle notification-clear-active notification-dnd-toggle notification-invoke-latest panel-toggle screenshot-fullscreen screenshot-region session settings-toggle volume-down volume-mute volume-up window-switcher brightness-down brightness-up "
while read -r verb; do
  [[ $known_verbs == *" $verb "* ]] || fail "binding uses a known Noctalia IPC verb: $verb"
done < <(grep -hoE 'noctalia\("[a-z-]+' "$hypr"/fenoa/bindings.lua | sed -E 's/noctalia\("//' | sort -u)
pass "every Noctalia IPC verb the bindings use exists"

# A switch binding names the input device; a PC laptop's lid is the ACPI button driver's "Lid Switch".
grep -qF 'switch:on:Lid Switch' "$hypr/fenoa/bindings.lua" && grep -qF 'switch:off:Lid Switch' "$hypr/fenoa/bindings.lua" ||
  fail "the lid bindings name the laptop's \"Lid Switch\""
pass "the lid bindings name the laptop's \"Lid Switch\""

# With lock restore on, a second locker started while the screen is locked replaces the live lock
# screen and can unlock.
grep -qE '^[[:space:]]*allow_session_lock_restore = false,' "$hypr/fenoa/looknfeel.lua" ||
  fail "a second locker cannot replace the live session lock (allow_session_lock_restore = false)"
pass "a second locker cannot replace the live session lock"

# --- Flatpak app set ↔ default apps ----------------------------------------------------------------

manifest="$D/usr/share/flatpak/preinstall.d/fenoa.preinstall"
mime="$D/usr/share/applications/hyprland-mimeapps.list"
# One line per group: NAME BRANCH ISRUNTIME ("-" for a key the group does not set).
preinstall_groups=$(awk '
  function flush() { if (name != "") print name, (branch == "" ? "-" : branch), (runtime == "" ? "-" : runtime) }
  /^\[Flatpak Preinstall / { flush(); name = $3; sub(/\]$/, "", name); branch = ""; runtime = ""; next }
  /^Branch=/ { branch = substr($0, 8) }
  /^IsRuntime=/ { runtime = substr($0, 11) }
  END { flush() }
' "$manifest")
[[ -n $preinstall_groups ]] || fail "the preinstall manifest has groups"
# An app group without Branch=stable installs nothing from Flathub (the default branch is "master").
bad_apps=$(awk '$3 != "true" && !($2 == "stable" && $3 == "false")' <<<"$preinstall_groups")
[[ -z $bad_apps ]] || fail "every app group pins Branch=stable and IsRuntime=false" "$bad_apps"
pass "every app group pins Branch=stable and IsRuntime=false"

# GTK3 inside the sandbox (and Qt, through the runtime's libqgtk3) can only use a GTK theme its
# runtime carries. Noctalia switches between adw-gtk3 and adw-gtk3-dark, and flatpak's auto-download
# never fetches either here (it follows the GTK theme of the user running it, and the preinstall and
# updates run as root, on plain Adwaita), so both extensions are preinstalled, from their 3.22 branch.
for theme in org.gtk.Gtk3theme.adw-gtk3 org.gtk.Gtk3theme.adw-gtk3-dark; do
  grep -qx "$theme 3.22 true" <<<"$preinstall_groups" ||
    fail "the Flatpak set includes the $theme runtime extension (Branch=3.22, IsRuntime=true)" "$(grep -F "$theme" <<<"$preinstall_groups")"
done
bad_runtimes=$(awk '$3 == "true" && $1 !~ /^org\.gtk\.Gtk3theme\./' <<<"$preinstall_groups")
[[ -z $bad_runtimes ]] || fail "the only runtimes in the set are the GTK3 theme extensions" "$bad_runtimes"
pass "the light and dark adw-gtk3 theme extensions are preinstalled (Branch=3.22, IsRuntime=true)"

# The Qt half: Qt apps take their palette from GTK3 only because the session asks for the gtk3
# platform theme, and Flatpak passes that variable into the sandbox.
grep -qx 'export QT_QPA_PLATFORMTHEME=gtk3' "$D/usr/share/uwsm/env.d/10-fenoa" ||
  fail "the uwsm session environment exports QT_QPA_PLATFORMTHEME=gtk3 (Qt Flatpaks follow GTK3's theme)"
builtin_ids=$(toml "$noctalia_defaults" 't["theme"]["templates"]["builtin_ids"]')
[[ $builtin_ids == *gtk3* && $builtin_ids == *gtk4* ]] ||
  fail "Noctalia's gtk3/gtk4 templates are on (they switch the GTK theme and color-scheme)" "builtin_ids: $builtin_ids"
pass "the session exports QT_QPA_PLATFORMTHEME=gtk3, and Noctalia's gtk templates drive the theme"

for app in com.brave.Browser org.gnome.Loupe org.gnome.Evince org.libreoffice.LibreOffice md.obsidian.Obsidian \
           org.localsend.localsend_app com.obsproject.Studio; do
  grep -qF "[Flatpak Preinstall $app]" "$manifest" || fail "the Flatpak set includes $app"
done
pass "the Flatpak set: Brave, Loupe, Evince, LibreOffice, Obsidian, LocalSend, OBS Studio"

while read -r app; do
  case $app in
    com.brave.Browser|org.gnome.Loupe|org.gnome.Evince)
      grep -qF "[Flatpak Preinstall $app]" "$manifest" || fail "the default app $app is in the Flatpak preinstall set"
      ;;
  esac
done < <(sed -n 's/^[^=]*=\(.*\)\.desktop$/\1/p' "$mime" | sort -u)
grep -qF 'x-scheme-handler/https=com.brave.Browser.desktop' "$mime" || fail "Brave is the default browser"
pass "the Flatpak default apps in mimeapps are all preinstalled"

# --- Webapps ---------------------------------------------------------------------------------------

# Each webapp is a launcher for a Brave app window. Brave names that window's Wayland app_id after
# the --app URL (brave-HOST__-Default for a site's root), and Noctalia matches windows to launchers
# by StartupWMClass, so the two have to agree or the window shows Brave's icon instead.
icons="$D/usr/share/icons/hicolor/scalable/apps"
for app in spotify chess proton-mail proton-calendar whatsapp; do
  [[ -f "$D/usr/share/applications/fenoa-webapp-$app.desktop" ]] || fail "the $app webapp ships"
done
for entry in "$D"/usr/share/applications/fenoa-webapp-*.desktop; do
  name=$(basename "$entry")
  if command -v desktop-file-validate >/dev/null 2>&1; then
    out=$(desktop-file-validate "$entry" 2>&1) || fail "$name is a valid desktop entry" "$out"
  fi
  url=$(sed -n 's|^Exec=flatpak run com\.brave\.Browser --app=\(https://[^ ]*\)$|\1|p' "$entry")
  [[ -n $url ]] || fail "$name opens a site in a Brave app window" "$(grep '^Exec=' "$entry")"
  host=${url#https://}
  [[ $host == */ && $host != */*/ ]] || fail "$name opens a site's root (its window class depends on the path)" "$url"
  host=${host%/}
  grep -qx "StartupWMClass=brave-${host}__-Default" "$entry" ||
    fail "$name's StartupWMClass matches Brave's app window class (brave-${host}__-Default)"
  icon=$(sed -n 's/^Icon=//p' "$entry")
  [[ -n $icon && -f "$icons/$icon.svg" ]] || fail "$name's icon ships in hicolor/scalable/apps" "Icon=$icon"
done
grep -qF '[Flatpak Preinstall com.brave.Browser]' "$manifest" || fail "the webapps' browser, Brave, is preinstalled"
overlay_at=$(grep -nx 'COPY system/desktop/ /' "$containerfile" | cut -d: -f1)
cache_at=$(grep -nF 'gtk-update-icon-cache -f /usr/share/icons/hicolor' "$containerfile" | tail -1 | cut -d: -f1)
[[ -n $overlay_at && -n $cache_at ]] && (( cache_at > overlay_at )) ||
  fail "the Containerfile rebuilds the hicolor icon cache after the desktop overlay adds icons"
pass "the webapps (Spotify, Chess.com, Proton Mail, Proton Calendar, WhatsApp) open in Brave app windows with their own icons"

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
  fail "OBS Studio is a Flatpak, not the native RPM"
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
