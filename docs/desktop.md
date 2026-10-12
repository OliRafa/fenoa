# The desktop

Fenoa's session is Hyprland (Lua config) managed by uwsm, with Noctalia v5 as the shell and noctalia-greeter as the login screen.

## Pieces

| Piece | Provided by | Notes |
|---|---|---|
| Compositor | `hyprland` (lionheartp/Hyprland COPR) | Lua config, 0.55+; started by uwsm from `hyprland-uwsm.desktop` |
| Bar, launcher, control center, dock, desktop widgets | Noctalia | `uwsm-app -s s -- noctalia` from Hyprland's start hook |
| Notifications, OSD | Noctalia | Noctalia owns `org.freedesktop.Notifications` |
| Lock screen, idle | Noctalia | PAM service `login`; locks before suspend via a logind delay inhibitor; lock at 5 min, screen off at 5.5 min |
| Polkit agent | Noctalia | `shell.polkit_agent = true`; Fenoa ships no other agent |
| Clipboard history, screenshots, emoji, calculator | Noctalia | launcher providers `/emo`, `/calc`, `/win`, `/session`, `/wall` |
| Night light | Noctalia | wlr-gamma-control; no hyprsunset |
| Theming | Noctalia templates | `gtk3`, `gtk4` (adw-gtk3), `foot`, `hyprland` |
| Login screen | noctalia-greeter (Terra) on greetd | its own wlroots compositor; state in `/var/lib/noctalia-greeter` |
| Terminal | foot | via `xdg-terminal-exec` (`/etc/xdg/hyprland-xdg-terminals.list`) |
| Files | Nautilus | |
| Browser, images, PDF | Brave, Loupe, Evince (Flatpaks) | defaults in `/usr/share/applications/hyprland-mimeapps.list` |
| Media | mpv + mpv-mpris | Noctalia's media controls see it over MPRIS |

## Key bindings

Defined in `/usr/share/fenoa/hypr/fenoa/bindings.lua`. Override or add bindings in `~/.config/hypr/hyprland.lua` (`hl.unbind("SUPER + Q")` first to repurpose a key).

### Apps and shell

| Keys | Action |
|---|---|
| `Super + Return` | Terminal (foot) |
| `Super + Shift + Return` / `Super + Shift + B` | Brave |
| `Super + Shift + F` | Files |
| `Super + Shift + N` | Neovim in a terminal |
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

The Mac top row sends these without Fn (`hid_apple fnmode=1`).

| Keys | Action |
|---|---|
| Volume keys (`Alt` for 1% steps), mute, mic mute | Noctalia volume with OSD |
| Brightness keys | Panel brightness |
| `Shift + Brightness` | Keyboard backlight (`fenoa-kbd-backlight`; the Mac top row has no backlight keys) |
| Play/pause, next, previous | The active MPRIS player |
| `Print`, `Super + F11`, `Super + Volume down` | Screenshot a region |
| `Shift + Print`, `Super + F12`, `Super + Volume up` | Screenshot a display |
| Lid closed with an external display | Internal panel off (`fenoa-hypr-clamshell`); without one, logind suspends |

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

- **Hyprland:** `~/.config/hypr/hyprland.lua`. It loads the defaults, then your settings, then Noctalia's palette. Check a change with `Hyprland --verify-config`. Monitors: `hl.monitor({ output = "DP-1", mode = "3440x1440@60", position = "auto-right", scale = 1 })`; names from `hyprctl monitors`.
- **Noctalia:** `~/.config/noctalia/config.toml` (includes `/usr/share/fenoa/noctalia/fenoa.toml`); the Settings window saves to `~/.local/state/noctalia/settings.toml`, which wins. Check with `noctalia config validate`.
- **Default apps:** `~/.config/mimeapps.list` overrides `/usr/share/applications/hyprland-mimeapps.list`.
- **Session environment:** `~/.config/uwsm/env` adds to `/usr/share/uwsm/env.d/10-fenoa` (Homebrew on `PATH`, `TERMINAL`, `EDITOR`).

## The greeter

- greetd runs `/usr/bin/noctalia-greeter-session` as the `greetd` account on VT1 (`/etc/greetd/config.toml`). On Fedora the greeter account is `greetd`, not `greeter` as upstream's docs assume.
- `/usr/lib/tmpfiles.d/fenoa-greeter.conf` creates `/var/lib/noctalia-greeter` (0750, `greetd`) and links `greeter.toml` to the image copy in `/usr/share/fenoa/greeter/`, which sets the default session to `Hyprland (uwsm-managed)`. Keep appearance out of `greeter.toml`: its values win over the sync.
- Noctalia's `[shell.greeter_sync] auto_sync` copies wallpaper, palette, font and monitor layout to the greeter whenever they change, through the packaged constrained polkit action. `/usr/share/polkit-1/rules.d/49-fenoa-greeter-sync.rules` lets active local members of `wheel` do that without a password; anyone else gets an administrator prompt from Noctalia's polkit agent.
- Avatars come from AccountsService: set one in Noctalia (Control Center) and the greeter shows it.
- Fonts the greeter uses must be installed system-wide; fonts in `~/.local/share/fonts` are invisible to it.
- `/etc/pam.d/greetd` (from Fedora's greetd) unlocks the GNOME keyring with the login password.
- Logs: `journalctl -u greetd -b | grep noctalia-greeter`.
