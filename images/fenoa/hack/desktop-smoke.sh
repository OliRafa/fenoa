#!/bin/bash
# Container smoke test for the Fenoa DESKTOP layer (the published `fenoa` image and the fairydust
# variant). Run platform-smoke.sh against the same image as well; this file covers only what the
# desktop stage adds.
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
         obs-studio udiskie adobe-source-code-pro-fonts cascadia-mono-nf-fonts; do
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
case $greetd_conf in *'command = "/usr/bin/noctalia-greeter-session"'*) ok "greetd runs noctalia-greeter-session" ;; *) no "greetd does not run noctalia-greeter-session" ;; esac
case $greetd_conf in *'user = "greetd"'*) ok "greetd runs the greeter as greetd" ;; *) no "greetd greeter user is not greetd" ;; esac
getent passwd greetd >/dev/null && ok "greetd account exists" || no "greetd account missing"
[[ -x /usr/bin/noctalia-greeter-session ]] && ok "noctalia-greeter-session executable" || no "noctalia-greeter-session missing"
pam="$(cat /etc/pam.d/greetd 2>/dev/null || true)"
case $pam in *pam_gnome_keyring.so*auto_start*) ok "login unlocks the GNOME keyring (pam_gnome_keyring)" ;; *) no "/etc/pam.d/greetd does not unlock the keyring" ;; esac

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
case $validate in
  *"warning"*|*"WARN"*|*"ERR"*) no "noctalia config validate reports problems: $validate" ;;
  *"Config is valid"*) ok "noctalia config validate: valid, no warnings" ;;
  *) no "noctalia config validate: $validate" ;;
esac
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
sh -n /usr/share/uwsm/env.d/10-fenoa 2>/dev/null && ok "uwsm env.d/10-fenoa parses" || no "uwsm env.d/10-fenoa missing or invalid"
[[ "$(cat /etc/xdg/hyprland-xdg-terminals.list 2>/dev/null)" == "foot.desktop" ]] && ok "default terminal: foot" || no "hyprland-xdg-terminals.list not foot"
[[ -f /usr/share/applications/foot.desktop ]] && ok "foot.desktop exists" || no "foot.desktop missing"
mime="$(cat /usr/share/applications/hyprland-mimeapps.list 2>/dev/null || true)"
case $mime in *"x-scheme-handler/https=com.brave.Browser.desktop"*) ok "https opens Brave" ;; *) no "https is not mapped to Brave" ;; esac
manifest="$(cat /usr/share/flatpak/preinstall.d/fenoa.preinstall 2>/dev/null || true)"
for app in com.brave.Browser org.gnome.Loupe org.gnome.Evince org.libreoffice.LibreOffice md.obsidian.Obsidian org.localsend.localsend_app; do
  case $manifest in *"[Flatpak Preinstall $app]"*) ok "Flatpak preinstall: $app" ;; *) no "Flatpak preinstall lacks $app" ;; esac
done
mono="$(fc-match -f '%{family}' monospace 2>/dev/null || true)"
case $mono in "Source Code Pro"*) ok "monospace resolves to Source Code Pro (system-wide, so the greeter can use it)" ;; *) no "monospace resolves to '${mono:-?}', not Source Code Pro" ;; esac
zone="$(firewall-offline-cmd --get-default-zone 2>/dev/null || true)"
[[ "$(firewall-offline-cmd --zone="$zone" --query-service=localsend 2>/dev/null)" == "yes" ]] \
  && ok "LocalSend's port is open in the $zone zone" || no "localsend service not enabled in the default firewalld zone"

echo
if [[ $fail == "0" ]]; then echo "DESKTOP SMOKE: PASS"; else echo "DESKTOP SMOKE: FAIL"; fi
exit "$fail"
CHECKS
