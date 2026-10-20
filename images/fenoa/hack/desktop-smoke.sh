#!/bin/bash
# Container smoke test for the Fenoa DESKTOP layer (the published `fenoa` image). Run
# platform-smoke.sh against the same image as well; this file covers only what the desktop stage
# adds.
#
# Beyond package presence it exercises the shipped configuration with the real binaries in the
# image: Noctalia validates the seeded user config, Hyprland verifies the seeded Lua config, the
# greeter lists the session greeter.toml names, and tmpfiles creates the greeter state directory.
#
#   ./images/fenoa/hack/desktop-smoke.sh [IMAGE]     # default fenoa:44
set -euo pipefail
IMAGE="${1:-fenoa:44}"
ENGINE="${ENGINE:-podman}"

echo "== desktop smoke: $IMAGE (via $ENGINE) =="
"$ENGINE" run --rm -i --entrypoint bash "$IMAGE" -s <<'CHECKS'
set -uo pipefail
fail=0
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
no() { printf '  \033[31m✗ %s\033[0m\n' "$1"; fail=1; }

# Never `cmd | grep -q` here (pipefail + SIGPIPE); capture output, then match in the shell.

echo "== packages =="
if rpm -q hyprland >/dev/null 2>&1 || rpm -q hyprland-git >/dev/null 2>&1; then ok "hyprland"; else no "hyprland missing"; fi
[[ -f /usr/share/wayland-sessions/hyprland-uwsm.desktop ]] && ok "hyprland-uwsm.desktop session" || no "uwsm session file missing"
for p in uwsm noctalia noctalia-greeter greetd greetd-selinux accountsservice gnome-keyring xdg-desktop-portal-hyprland \
         xdg-desktop-portal-gtk adw-gtk3-theme foot xdg-terminal-exec nautilus mpv mpv-mpris wl-clipboard \
         udiskie wf-recorder adobe-source-code-pro-fonts cascadia-mono-nf-fonts; do
  rpm -q "$p" >/dev/null 2>&1 && ok "$p" || no "$p missing"
done
for p in sddm quickshell firefox; do
  rpm -q "$p" >/dev/null 2>&1 && no "$p installed (Fenoa ships none)" || ok "$p absent"
done
override="$(cat /etc/dnf/repos.override.d/90-fenoa-terra.repo 2>/dev/null || true)"
case $override in *"includepkgs=noctalia-greeter"*) ok "Terra restricted to noctalia-greeter" ;; *) no "Terra repo is not restricted" ;; esac
origin="$(rpm -q --qf '%{VENDOR}|%{PACKAGER}\n' noctalia-greeter 2>/dev/null || true)"
case $origin in *[Cc]opr*) no "noctalia-greeter came from the COPR, not Terra: $origin" ;; *) ok "noctalia-greeter is not the COPR build" ;; esac

echo "== greeter =="
dm="$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null || true)"
[[ $dm == */greetd.service ]] && ok "greetd is the display manager" || no "display-manager is not greetd (${dm:-unset})"
[[ "$(systemctl get-default 2>/dev/null)" == "graphical.target" ]] && ok "default target = graphical.target" || no "default target is not graphical.target"
greetd_conf="$(cat /etc/greetd/config.toml 2>/dev/null || true)"
case $greetd_conf in *'command = "/usr/libexec/fenoa-greeter-session"'*) ok "greetd runs fenoa-greeter-session" ;; *) no "greetd does not run fenoa-greeter-session" ;; esac
case $greetd_conf in *'user = "greetd"'*) ok "greetd runs the greeter as greetd" ;; *) no "greetd greeter user is not greetd" ;; esac
getent passwd greetd >/dev/null && ok "greetd account exists" || no "greetd account missing"
[[ -x /usr/bin/noctalia-greeter-session ]] && ok "noctalia-greeter-session executable" || no "noctalia-greeter-session missing"
[[ -x /usr/libexec/fenoa-greeter-session ]] && ok "fenoa-greeter-session executable" || no "fenoa-greeter-session missing or not executable"
[[ -x /usr/bin/lua ]] && ok "lua (runs the keyboard resolver for the greeter)" || no "/usr/bin/lua missing"
# The wrapper must hand the greeter a layout from the session's resolver; /usr/bin/env stands in for
# the greeter and prints what it would get.
greeter_env="$(FENOA_GREETER_SESSION=/usr/bin/env /usr/libexec/fenoa-greeter-session 2>&1 || true)"
greeter_layout="$(printf '%s\n' "$greeter_env" | sed -n 's/^XKB_DEFAULT_LAYOUT=//p')"
[[ -n $greeter_layout ]] && ok "the greeter gets the session's layout (XKB_DEFAULT_LAYOUT=$greeter_layout)" \
  || no "fenoa-greeter-session sets no XKB_DEFAULT_LAYOUT: ${greeter_env%%$'\n'*}"
pam="$(cat /etc/pam.d/greetd 2>/dev/null || true)"
case $pam in *pam_gnome_keyring.so*auto_start*) ok "login unlocks the GNOME keyring (pam_gnome_keyring)" ;; *) no "/etc/pam.d/greetd does not unlock the keyring" ;; esac

# Flatpak apps reach that keyring through the Secret portal, which Fenoa routes to gnome-keyring.
[[ -f /usr/share/xdg-desktop-portal/portals/gnome-keyring.portal ]] \
  && ok "gnome-keyring ships a Secret portal" || no "gnome-keyring.portal missing"
portals="$(cat /etc/xdg-desktop-portal/hyprland-portals.conf 2>/dev/null || true)"
case $portals in
  *$'\n'"org.freedesktop.impl.portal.Secret=gnome-keyring"*) ok "the Secret portal is routed to gnome-keyring" ;;
  *) no "/etc/xdg-desktop-portal/hyprland-portals.conf does not route the Secret portal to gnome-keyring" ;;
esac
# The /etc copy replaces the package's file whole; it must still carry the package's default=.
pkg_default="$(sed -n 's/^default=//p' /usr/share/xdg-desktop-portal/hyprland-portals.conf 2>/dev/null || true)"
our_default="$(sed -n 's/^default=//p' /etc/xdg-desktop-portal/hyprland-portals.conf 2>/dev/null || true)"
[[ -n $pkg_default && $our_default == "$pkg_default" ]] \
  && ok "hyprland-portals.conf keeps the package's default=$pkg_default" \
  || no "hyprland-portals.conf default=${our_default:-?} no longer matches the package's ${pkg_default:-?}"

# tmpfiles must create the state dir owned by the greeter account, and link the image's greeter.toml.
systemd-tmpfiles --create /usr/lib/tmpfiles.d/fenoa-greeter.conf >/dev/null 2>&1 || true
state="$(stat -c '%a %U:%G' /var/lib/noctalia-greeter 2>/dev/null || true)"
[[ $state == "750 greetd:greetd" ]] && ok "/var/lib/noctalia-greeter is 0750 greetd:greetd" || no "greeter state dir wrong: ${state:-missing}"
[[ "$(readlink -f /var/lib/noctalia-greeter/greeter.toml)" == "/usr/share/fenoa/greeter/greeter.toml" ]] \
  && ok "greeter.toml links to the image copy" || no "greeter.toml not linked"
# Read the compiled policy rather than matchpathcon, which depends on the host having SELinux on.
fcontext="$(grep -F '/var/lib/noctalia-greeter(' /etc/selinux/targeted/contexts/files/file_contexts 2>/dev/null || true)"
case $fcontext in
  *xdm_var_lib_t*) ok "greeter state is labelled xdm_var_lib_t (the greeter may write it)" ;;
  *) no "no xdm_var_lib_t file context for /var/lib/noctalia-greeter (${fcontext:-none})" ;;
esac
[[ "$(stat -c '%a %U' /var/lib/greetd 2>/dev/null)" == "750 greetd" ]] && ok "/var/lib/greetd (greetd's home) recreated by tmpfiles" || no "/var/lib/greetd missing or wrong"
sessions="$(noctalia-greeter sessions 2>/dev/null || true)"
default_session="$(sed -n 's/^default = "\(.*\)"$/\1/p' /usr/share/fenoa/greeter/greeter.toml)"
case $sessions in *"$default_session"*) ok "greeter finds its default session: $default_session" ;; *) no "greeter sessions do not include '$default_session': $sessions" ;; esac

# The passwordless greeter-sync rule only works if it names the packaged action and helper.
policy="$(cat /usr/share/polkit-1/actions/org.noctalia.greeter.apply-appearance.policy 2>/dev/null || true)"
case $policy in *'org.noctalia.greeter.sync-appearance'*) ok "packaged polkit action org.noctalia.greeter.sync-appearance" ;; *) no "greeter sync polkit action missing" ;; esac
helper="$(readlink -f /usr/bin/noctalia-greeter-apply-appearance 2>/dev/null || true)"
rule="$(cat /usr/share/polkit-1/rules.d/49-fenoa-greeter-sync.rules 2>/dev/null || true)"
case $rule in *"\"$helper\""*) ok "polkit rule names the real helper path ($helper)" ;; *) no "polkit rule does not name $helper" ;; esac

echo "== seeded user config, checked by the real binaries =="
home="$(mktemp -d)"
cp -a /etc/skel/. "$home/"
mkdir -p "$home/.run" && chmod 0700 "$home/.run"
[[ -f $home/.config/hypr/hyprland.lua ]] && ok "skel seeds ~/.config/hypr/hyprland.lua" || no "skel has no hyprland.lua"
[[ -f $home/.config/noctalia/config.toml ]] && ok "skel seeds ~/.config/noctalia/config.toml" || no "skel has no noctalia config"

validate="$(HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_STATE_HOME="$home/.local/state" noctalia config validate 2>&1 || true)"
# A plugin's widget types are known only once Noctalia has fetched the plugin, which it does at
# login, so the offline validator flags plugin widgets ("<author>/<plugin>:<entry>"); any other
# warning is a problem. desktop-config-test.sh checks each of them belongs to an enabled plugin.
problems="$(printf '%s\n' "$validate" | grep -E 'WARN|ERR' | grep -vE 'unrecognized widget type "[^"/]+/[^"/:]+:[^"]+"$' || true)"
if [[ -n $problems ]]; then
  no "noctalia config validate reports problems: $problems"
elif [[ $validate == *"Config is valid"* ]]; then
  ok "noctalia config validate: valid, no warnings beyond the plugin widgets"
else
  no "noctalia config validate: $validate"
fi
exported="$(HOME="$home" XDG_CONFIG_HOME="$home/.config" noctalia config export 2>/dev/null || true)"
case $exported in *'polkit_agent = true'*) ok "the image defaults are included (polkit agent on)" ;; *) no "the include of /usr/share/fenoa/noctalia/fenoa.toml did not apply" ;; esac

# Hyprland refuses to run as root, even just to verify a config; do it as nobody.
chown -R nobody:nobody "$home"
verify="$(runuser -u nobody -- env HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_RUNTIME_DIR="$home/.run" \
  timeout 60 Hyprland --verify-config -c "$home/.config/hypr/hyprland.lua" 2>&1 || true)"
case $verify in
  *"config ok"*) ok "Hyprland --verify-config: config ok" ;;
  *) no "Hyprland rejects the seeded config: $(printf '%s' "$verify" | tail -5)" ;;
esac
rm -rf "$home"

echo "== session plumbing and defaults =="
for c in fenoa-kbd-backlight fenoa-hypr-clamshell; do
  [[ -x /usr/bin/$c ]] && ok "$c" || no "$c missing"
done
# The AI Usage widget runs `ai-usagebar usage --json`; with no vendor logins it still reports (errors).
aub_version="$(ai-usagebar --version 2>&1 || true)"
aub_home="$(mktemp -d)"
aub_usage="$(HOME="$aub_home" timeout 30 ai-usagebar usage --json 2>&1 || true)"
rm -rf "$aub_home"
case $aub_version in
  "ai-usagebar "[0-9]*) ok "ai-usagebar CLI for the AI Usage widget ($aub_version)" ;;
  *) no "ai-usagebar CLI missing or broken: $aub_version" ;;
esac
case $aub_usage in
  *'"schema_version"'*) ok "ai-usagebar usage --json reports without any vendor login" ;;
  *) no "ai-usagebar usage --json: $aub_usage" ;;
esac
# The AirPods widget drives the librepods daemon (a user service in every session) via librepods-ctl.
for b in librepods librepods-ctl; do
  libs="$(ldd "/usr/bin/$b" 2>&1 || true)"
  if [[ ! -x /usr/bin/$b ]]; then
    no "$b missing"
  elif [[ $libs == *"not found"* ]]; then
    no "$b is missing libraries: $(printf '%s\n' "$libs" | grep 'not found' | tr -s ' \t' ' ')"
  else
    ok "$b (every library resolves)"
  fi
done
lp_unit="$(cat /usr/lib/systemd/user/librepods.service 2>/dev/null || true)"
case $lp_unit in
  *$'\n'"ExecStart=/usr/bin/librepods --headless"$'\n'*) ok "librepods.service runs /usr/bin/librepods --headless" ;;
  *) no "librepods.service missing or not pointed at /usr/bin/librepods --headless" ;;
esac
[[ "$(systemctl --global is-enabled librepods.service 2>/dev/null)" == "enabled" ]] \
  && ok "librepods.service is enabled for every user" || no "librepods.service is not enabled globally"
sh -n /usr/share/uwsm/env.d/10-fenoa 2>/dev/null && ok "uwsm env.d/10-fenoa parses" || no "uwsm env.d/10-fenoa missing or invalid"
[[ "$(cat /etc/xdg/hyprland-xdg-terminals.list 2>/dev/null)" == "foot.desktop" ]] && ok "default terminal: foot" || no "hyprland-xdg-terminals.list not foot"
[[ -f /usr/share/applications/foot.desktop ]] && ok "foot.desktop exists" || no "foot.desktop missing"
mime="$(cat /usr/share/applications/hyprland-mimeapps.list 2>/dev/null || true)"
case $mime in *"x-scheme-handler/https=com.brave.Browser.desktop"*) ok "https opens Brave" ;; *) no "https is not mapped to Brave" ;; esac
manifest="$(cat /usr/share/flatpak/preinstall.d/fenoa.preinstall 2>/dev/null || true)"
for app in com.brave.Browser org.gnome.Loupe org.gnome.Evince org.libreoffice.LibreOffice md.obsidian.Obsidian org.localsend.localsend_app com.obsproject.Studio; do
  case $manifest in *"[Flatpak Preinstall $app]"*) ok "Flatpak preinstall: $app" ;; *) no "Flatpak preinstall lacks $app" ;; esac
done
# GTK3 (and Qt) inside the sandbox follow light/dark only with both adw-gtk3 theme extensions.
for theme in org.gtk.Gtk3theme.adw-gtk3 org.gtk.Gtk3theme.adw-gtk3-dark; do
  case $manifest in
    *"[Flatpak Preinstall $theme]"$'\n'"Branch=3.22"$'\n'"IsRuntime=true"*) ok "Flatpak preinstall: $theme//3.22 (runtime)" ;;
    *) no "Flatpak preinstall lacks $theme (Branch=3.22, IsRuntime=true)" ;;
  esac
done
# Webapps: GTK trusts the hicolor cache over the directory, so an icon the cache lacks is invisible.
# The cache stores names NUL-terminated, sometimes right after a printable offset byte, so match the
# name up to its terminator only.
icon_cache="$(LC_ALL=C tr -c '[:print:]' '\n' </usr/share/icons/hicolor/icon-theme.cache 2>/dev/null || true)"
for app in spotify chess proton-mail proton-calendar; do
  [[ -f /usr/share/applications/fenoa-webapp-$app.desktop ]] && ok "webapp: $app" || no "webapp $app missing"
  case $icon_cache$'\n' in
    *"fenoa-webapp-$app"$'\n'*) ok "the hicolor icon cache lists fenoa-webapp-$app" ;;
    *) no "the hicolor icon cache lacks fenoa-webapp-$app (rebuild it after the desktop overlay)" ;;
  esac
done
mono="$(fc-match -f '%{family}' monospace 2>/dev/null || true)"
case $mono in "Source Code Pro"*) ok "monospace resolves to Source Code Pro (system-wide, so the greeter can use it)" ;; *) no "monospace resolves to '${mono:-?}', not Source Code Pro" ;; esac
zone="$(firewall-offline-cmd --get-default-zone 2>/dev/null || true)"
[[ "$(firewall-offline-cmd --zone="$zone" --query-service=localsend 2>/dev/null)" == "yes" ]] \
  && ok "LocalSend's port is open in the $zone zone" || no "localsend service not enabled in the default firewalld zone"

echo "== first boot: the preset pass keeps the login screen =="
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
  [[ -z $changes ]] && ok "systemctl preset-all changes nothing (greetd and graphical.target survive a first boot)" || no "a first boot's preset pass would change the image:"$'\n'"$changes"
else
  no "systemctl preset-all failed: $preset_out"
fi
dm="$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null || true)"
[[ $dm == */greetd.service && "$(systemctl get-default 2>/dev/null)" == "graphical.target" ]] \
  && ok "after the preset pass greetd is still the display manager, booting graphical.target" \
  || no "after the preset pass the display manager is '${dm:-unset}', default $(systemctl get-default 2>/dev/null)"
# Fedora's user presets end in `disable *` too; ours must keep librepods if a global pass ever runs.
if systemctl --global preset librepods.service >/dev/null 2>&1 \
  && [[ "$(systemctl --global is-enabled librepods.service 2>/dev/null)" == "enabled" ]]; then
  ok "a global preset pass keeps librepods.service enabled"
else
  no "a global preset pass disables librepods.service"
fi

echo
if [[ $fail == "0" ]]; then echo "DESKTOP SMOKE: PASS"; else echo "DESKTOP SMOKE: FAIL"; fi
exit "$fail"
CHECKS
