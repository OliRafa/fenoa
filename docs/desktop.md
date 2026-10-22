# The desktop

Fenoa's session is Hyprland (Lua config) managed by uwsm, with Noctalia v5 as the shell and noctalia-greeter as the login screen.

## Pieces

| Piece | Provided by | Notes |
|---|---|---|
| Compositor | `hyprland` (lionheartp/Hyprland COPR) | Lua config, 0.55+; started by uwsm from `hyprland-uwsm.desktop` |
| Bar, launcher, control center, dock, desktop widgets | Noctalia | `uwsm-app -s s -- noctalia` from Hyprland's start hook |
| Notifications, OSD | Noctalia | Noctalia owns `org.freedesktop.Notifications` |
| Lock screen, idle | Noctalia | PAM service `login` for the password, and an enrolled finger through fprintd at the same time (see [Fingerprint reader](platform.md#fingerprint-reader)); locks before suspend via a logind delay inhibitor; lock at 5 min, screen off at 5.5 min; a second locker cannot replace the live lock (see [If the lock screen crashes](#if-the-lock-screen-crashes)) |
| Polkit agent | Noctalia | `shell.polkit_agent = true`; Fenoa ships no other agent. With a finger enrolled, a prompt asks for it first and for the password once the reader gives up |
| Keyring | gnome-keyring | unlocked with the login password (`/etc/pam.d/greetd`); Flatpak apps reach it through the Secret portal, which `/etc/xdg-desktop-portal/hyprland-portals.conf` routes to gnome-keyring because its portal only offers itself under GNOME (the other portals stay `hyprland`, then `gtk`) |
| AI plan usage | Noctalia's AI Usage plugin (`felipeartur/ai-usagebar`), with the `ai-usagebar` CLI (`akitaonrails/ai-usagebar`) in the image | first on the bar's right-hand side; click for the panel, right-click to refresh. Noctalia fetches and updates the plugin from its community source at login; the CLI (upstream's signed release) updates with the image. Claude and Codex usage come from their own CLIs' logins (run `claude` or `codex login` once), Copilot from `gh auth login`; API keys and opt-in vendors go in `~/.config/ai-usagebar/config.toml`. A bar already arranged in Settings keeps its layout: add the widget there |
| Bar calculator | Noctalia's Calculator plugin (`yuuto/calculator`) | next to AI Usage; click for the keypad and expression panel, right-click to clear; the bar shows the last result. `noctalia msg panel-toggle yuuto/calculator:panel` opens it from a binding. Fetched and updated like AI Usage; a bar already arranged in Settings needs the widget added there |
| Pomodoro timer | Noctalia's Pomodoro Timer plugin (`thepunkoff/pomodoro`) | next to the calculator; click for the panel, durations in Settings → Plugins. Its alarm and ticking sounds play through Noctalia's shell sounds, or through `ffplay` (`ffmpeg-free`) with "Bypass Noctalia Sound Globals". Fetched and updated like AI Usage; a bar already arranged in Settings needs the widget added there |
| AirPods | Noctalia's AirPods plugin (`harveywuk/airpods`), driving the librepods daemon in the image | beside Bluetooth, hidden until AirPods connect (pair them as usual first); click for battery, listening mode, adaptive noise, Conversation Awareness and ear detection, right-click to cycle the listening mode. The daemon is the patched librepods fork the plugin needs (GPL-3.0, `harveywuk/librepods`), built from a pinned commit (`LIBREPODS_COMMIT` in the Containerfile; read the diff before bumping it) and run headless as the sandboxed user service `librepods.service` in every graphical session (`systemctl --user mask --now librepods.service` turns it off for you; a per-user `disable` cannot override the image's global enable). Its tray GUI is not shipped. A bar already arranged in Settings needs the widget added there |
| Clipboard history, screenshots, emoji, calculator | Noctalia | launcher providers `/emo`, `/calc`, `/win`, `/session`, `/wall` |
| Night light | Noctalia | wlr-gamma-control; no hyprsunset |
| Theming | Noctalia templates | `gtk3`, `gtk4` (adw-gtk3), `foot`, `hyprland`. On each light/dark switch the gtk template sets `color-scheme` and the GTK theme (`adw-gtk3`/`adw-gtk3-dark`), which the settings portal hands to Flatpak apps |
| Flatpak light/dark | the settings portal, plus the `org.gtk.Gtk3theme.adw-gtk3` and `adw-gtk3-dark` extensions (preinstalled) | GTK4/libadwaita, Firefox, Chromium and Electron follow `color-scheme`; GTK3 apps, and Qt apps through the runtime's GTK3 platform theme (`QT_QPA_PLATFORMTHEME=gtk3` in the session), load the dark or light theme extension. Both are preinstalled because nothing else would install them: flatpak only auto-downloads the GTK theme of the user running it, and the preinstall and daily update run as root, on plain Adwaita. Noctalia's palette colours stay on the host |
| Login screen | noctalia-greeter (Terra) on greetd | its own wlroots compositor; state in `/var/lib/noctalia-greeter` |
| Terminal | foot | via `xdg-terminal-exec` (`/etc/xdg/hyprland-xdg-terminals.list`); `~/.config/foot/foot.ini` sets `monospace:size=11` |
| Files | Nautilus | |
| Removable drives | udiskie | automounts USB drives and SD cards from session start |
| Browser, images, PDF | Brave, Loupe, Evince (Flatpaks) | defaults in `/usr/share/applications/hyprland-mimeapps.list` |
| Webapps | Brave app windows | Spotify, Chess.com, Proton Mail and Proton Calendar in the launcher (`/usr/share/applications/fenoa-webapp-*.desktop`, icons from homarr-labs/dashboard-icons in hicolor). Each opens the site's root in its own window (`--app`) on Brave's default profile, so it shares Brave's logins. `StartupWMClass` is the class Brave gives that window (`brave-<host>__-Default`), which Noctalia uses to show the webapp's icon. The image rebuilds the hicolor icon cache after adding the icons, because GTK otherwise keeps the stale one |
| Office, notes, file sharing | LibreOffice, Obsidian, LocalSend (Flatpaks) | LocalSend's port 53317 (TCP+UDP) is open in firewalld |
| Screen recording / streaming | OBS Studio (Flatpak), wf-recorder | `wf-recorder -f out.mp4` records from a terminal |
| Media | mpv + mpv-mpris | Noctalia's media controls see it over MPRIS |
| Font | Source Code Pro | the system `monospace` (`/etc/fonts/conf.d/50-fenoa-monospace.conf`), used by foot, Noctalia and the greeter; Cascadia Mono NF supplies Nerd Font icons as a fallback |
| Login shell | zsh (accounts created by `fenoa-firstboot-user`) | Fedora's stock config only (`~/.zshrc` and `~/.zprofile` from `/etc/skel`); the shell tools below are set up in bash, not zsh. `chsh -s /bin/bash` makes bash the login shell |
| Shell tools | starship, zoxide, fzf, eza, bat, ripgrep, fd, lazygit, btop (Homebrew) | wired into interactive bash (only) by `/etc/profile.d/fenoa-shell.sh` once installed: starship prompt, `cd` falls back to zoxide, fzf on Ctrl+R/Ctrl+T/Alt+C, `ls`/`lt` via eza, `ff` fuzzy file preview; opt out with `FENOA_SHELL_SETUP=0` |

## Key bindings

Defined in `/usr/share/fenoa/hypr/fenoa/bindings.lua`. Override or add bindings in `~/.config/hypr/hyprland.lua` (`hl.unbind("SUPER + Q")` first to repurpose a key).

### Apps and shell

| Keys | Action |
|---|---|
| `Super + Return` | Terminal (foot) |
| `Super + Shift + Return` / `Super + Shift + B` | Brave |
| `Super + Shift + F` | Files |
| `Super + Shift + N` | Neovim in a terminal |
| `Super + Shift + M` / `E` / `C` | Spotify / Proton Mail / Proton Calendar (webapps) |
| `Super + Space` | Launcher |
| `Super + Alt + Space` | Control center |
| `Super + Ctrl + Space` | Wallpaper picker |
| `Super + Shift + Space` | Toggle the bar |
| `Super + Ctrl + E` | Emoji picker |
| `Super + Ctrl + V` | Clipboard history |
| `Super + Ctrl + S` | Noctalia settings |
| `Super + Escape`, power key | Session menu (lock, log out, suspend, reboot, shut down) |
| `Super + Ctrl + L` | Lock |
| `Alt + Tab` | Window switcher |
| `Super + ,` | Dismiss notifications |
| `Super + Alt + ,` | Open the latest notification |
| `Super + Ctrl + ,` | Toggle do-not-disturb |
| `Super + Ctrl + I` | Keep awake (idle inhibitor) |
| `Super + Ctrl + N` | Night light |

### Media and hardware

| Keys | Action |
|---|---|
| Volume keys (`Alt` for 1% steps), mute, mic mute | Noctalia volume with OSD |
| Brightness keys | Panel brightness |
| Keyboard-backlight keys | Keyboard backlight (`fenoa-kbd-backlight`); laptops that step it in firmware (ThinkPads' `Fn + Space`) need no binding |
| Play/pause, next, previous | The active MPRIS player |
| `Print`, `Super + F11` | Screenshot a region |
| `Shift + Print`, `Super + F12` | Screenshot a display |
| Lid closed with an external display | Internal panel off (`fenoa-hypr-clamshell`, kept off across config reloads); without one, logind suspends |

### Windows and workspaces

| Keys | Action |
|---|---|
| `Super + W` / `Super + Q` | Close window |
| `Super + T` | Toggle floating |
| `Super + F` / `Super + Alt + F` | Fullscreen / maximize |
| `Super + J` | Toggle split |
| `Super + P` | Pseudo-tile |
| `Super + Arrows` | Focus |
| `Super + Shift + Arrows` | Swap windows |
| `Super + -` / `Super + =` (`Shift` for vertical) | Resize |
| `Super + drag` / `Super + right-drag` | Move / resize with the mouse |
| `Super + G`, `Super + Alt + G` | Group / ungroup; `Super + Alt + Tab` cycles the group |
| `Super + 1…0` | Workspace 1–10 |
| `Super + Shift + 1…0` | Move window to workspace (`Alt` too: stay put) |
| `Super + Tab` / `Super + Shift + Tab` / `Super + Ctrl + Tab` | Next / previous / last workspace |
| Three-finger horizontal swipe | Switch workspace |
| `Super + S` / `Super + Alt + S` | Scratchpad / send window to it |
| `Super + Shift + Alt + Left/Right` | Move workspace to another monitor |
| `Ctrl + Alt + Tab` | Focus the next monitor |

## Configuration

- **Hyprland:** `~/.config/hypr/hyprland.lua`. It loads the defaults, then your settings, then Noctalia's palette. Check a change with `Hyprland --verify-config`. Monitors default to Hyprland's automatic scale; set yours per output, e.g. `hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 1.25 })` (names from `hyprctl monitors`). XWayland apps are scaled by Hyprland (right size, slightly soft at fractional scales); for pixel-sharp XWayland at an integer scale set `xwayland.force_zero_scaling = true` and export `GDK_SCALE` in `~/.config/uwsm/env`.
- **Keyboard:** Hyprland and the login screen follow the system layout (`localectl set-x11-keymap <layout> [model] [variant] [options]`, then log out and in again); override Hyprland's with `hl.config({ input = { kb_layout = "..." } })`.
- **Noctalia:** `~/.config/noctalia/config.toml` (includes `/usr/share/fenoa/noctalia/fenoa.toml`); the Settings window saves to `~/.local/state/noctalia/settings.toml`, which wins. Check with `noctalia config validate`.
- **Default apps:** `~/.config/mimeapps.list` overrides `/usr/share/applications/hyprland-mimeapps.list`.
- **Session environment:** `/usr/share/uwsm/env.d/10-fenoa` sets the Wayland backends, cursor size, Qt/GTK theming, `TERMINAL`, `EDITOR` and Homebrew's `PATH` for the whole session (uwsm exports it to systemd and D-Bus activation too); add your own in `~/.config/uwsm/env`.

## If the lock screen crashes

Hyprland does not let a second locker replace a live session lock (`misc.allow_session_lock_restore = false` in `/usr/share/fenoa/hypr/fenoa/looknfeel.lua`): while the screen is locked, a client that starts its own lock cannot take over from Noctalia's lock screen and unlock. It does not protect against programs already running as you, which can turn the option back on with `hyprctl` exactly as step 2 below does. The flip side is that if Noctalia dies while the screen is locked, the session stays locked with nothing to type the password into. This is the procedure to recover it without logging out:

1. Switch to a text console with `Ctrl + Alt + F2` (add `Fn` on a laptop whose top row sends media keys first) and log in as yourself.
2. Let a new client take the lock over, for now: `hyprctl --instance 0 eval 'hl.config({ misc = { allow_session_lock_restore = true } })'` (`--instance 0` picks the first running Hyprland).
3. Start Noctalia again: `hyprctl --instance 0 eval 'hl.exec_cmd("uwsm-app -s s -- noctalia")'`
4. Ask it to lock, which replaces the dead lock: `loginctl lock-sessions` (with Noctalia running, logind's lock request goes through Noctalia's lock screen).
5. Go back with `Ctrl + Alt + F1` (again with `Fn` if needed) and unlock. The setting reverts at the next config reload or login.

## The greeter

- greetd runs `/usr/libexec/fenoa-greeter-session` as the `greetd` account on VT1 (`/etc/greetd/config.toml`). It hands the greeter the session's keyboard layout as `XKB_DEFAULT_LAYOUT`/`VARIANT`/`OPTIONS`, computed by the resolver Hyprland uses (`fenoa/keyboard.lua`), then execs `noctalia-greeter-session`; if the resolver cannot run, the greeter falls back to `/etc/vconsole.conf`. On Fedora the greeter account is `greetd`, not `greeter` as upstream's docs assume.
- `/usr/lib/tmpfiles.d/fenoa-greeter.conf` creates `/var/lib/noctalia-greeter` (0750, `greetd`; SELinux type `xdm_var_lib_t` from `/usr/share/fenoa/selinux/fenoa-greeter.cil`, so the greeter may write its remembered session and scheme) and greetd's own home `/var/lib/greetd`, and links `greeter.toml` to the image copy in `/usr/share/fenoa/greeter/`, which sets the default session to `Hyprland (uwsm-managed)`. Keep appearance out of `greeter.toml`: its values win over the sync.
- Noctalia's `[shell.greeter_sync] auto_sync` copies wallpaper, palette, font and monitor layout to the greeter whenever they change, through the packaged constrained polkit action (it runs exactly `noctalia-greeter-apply-appearance --sync <staging dir>` as root). `/usr/share/polkit-1/rules.d/49-fenoa-greeter-sync.rules` lets active local members of `wheel` do that without a password; anyone else gets an administrator prompt from Noctalia's polkit agent.
- That rule is a convenience upstream leaves off by default: it means any process in your session can feed images to the greeter without asking. To require your password for every sync instead, mask it with an empty file of the same name: `sudo touch /etc/polkit-1/rules.d/49-fenoa-greeter-sync.rules` (polkit uses the `/etc` copy when both exist).
- Avatars come from AccountsService: set one in Noctalia (Control Center) and the greeter shows it.
- Fonts the greeter uses must be installed system-wide; fonts in `~/.local/share/fonts` are invisible to it.
- `/etc/pam.d/greetd` (from Fedora's greetd) unlocks the GNOME keyring with the login password. It takes the password only, never a fingerprint: the keyring needs the password, and the greeter has no fingerprint prompt.
- Logs: `journalctl -u greetd -b | grep noctalia-greeter`.
