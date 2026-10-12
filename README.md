# Fenoa

**Fe**dora **No**ctalia **A**tomic — an image-based desktop for Apple Silicon Macs.

Fenoa is a [bootc](https://bootc-dev.github.io/bootc/) image built on [Fedora Asahi Remix](https://asahilinux.org/fedora/)'s atomic base: a [Hyprland](https://hypr.land) desktop with the [Noctalia](https://noctalia.dev) shell and [noctalia-greeter](https://github.com/noctalia-dev/noctalia-greeter) login screen, booted through systemd-boot on bootc's composefs backend. The whole OS is one signed container image; updates are atomic and roll back with `bootc rollback`.

| Image | What it is |
|---|---|
| `ghcr.io/olirafa/fenoa:44` | Hyprland + Noctalia on the stock Asahi `kernel-16k` |
| `ghcr.io/olirafa/fenoa-fairydust:44` | The same with the experimental [fairydust](docs/fairydust.md) kernel, for USB-C DisplayPort alt-mode |

Both are rebuilt weekly and on every change, smoke-tested, and cosign-signed.

## What you get

- **Desktop:** Hyprland (Lua config) with Noctalia for the bar, launcher, control center, notifications, OSD, lock screen, idle handling, polkit prompts, clipboard history, screenshots, night light and wallpaper. Noctalia's palette (a built-in scheme, or one generated from your wallpaper) also colours native GTK apps (Nautilus, settings dialogs), foot and Hyprland's borders; Flatpak apps keep their own styling.
- **Login:** noctalia-greeter on greetd, styled like the shell (Noctalia syncs your wallpaper and palette to it). Your login password unlocks the GNOME keyring.
- **Apps:** foot, Nautilus, mpv, wf-recorder, udiskie (USB automount), Docker and Homebrew in the image; Brave, Loupe, Evince, LibreOffice, Obsidian, LocalSend (Flathub) and OBS Studio (Fedora's Flatpak — Flathub has no aarch64 build) installed on first boot; shell and developer tools (starship, zoxide, fzf, eza, bat, ripgrep, fd, lazygit, btop, Neovim, tmux, gh, language toolchains) from the [Brewfile](Brewfile). Source Code Pro is the default monospace font.
- **Apple Silicon:** systemd-boot on composefs, m1n1/devicetree refresh after updates, the trackpad boot-race fix and macOS-style function keys in the initramfs, keyboard backlight on Shift+brightness, the Apple lid switch, Widevine DRM for Brave on aarch64. See [docs/asahi.md](docs/asahi.md).

## Install

On a Mac running **Fedora Asahi Remix 44** (install it alongside macOS first):

```sh
sudo dnf install -y git podman          # Fedora Asahi Remix Minimal ships neither
git clone https://github.com/OliRafa/fenoa && cd fenoa
sudo deploy/fenoa-install ghcr.io/olirafa/fenoa:44     # or ghcr.io/olirafa/fenoa-fairydust:44
sudo reboot
```

The installer grows the Asahi ESP if needed, preserves the m1n1/firmware preboot layer, and installs Fenoa with the composefs backend and systemd-boot. Details and recovery: [deploy/README.md](deploy/README.md).

Already on a composefs + systemd-boot bootc image (such as omarchy-atomic)? Switch in place:

```sh
sudo bootc switch ghcr.io/olirafa/fenoa:44
sudo reboot
```

### First boot

1. `systemd-firstboot` asks for locale, keymap, timezone and the root password (set a hostname later with `hostnamectl hostname <name>`). The login screen and Hyprland follow the keymap you pick.
2. `fenoa-firstboot-user` asks for your username, full name and password on tty1 (or reads a preseed from `/etc/fenoa/firstboot-user.conf`).
3. The greeter comes up; log in to the **Hyprland (uwsm-managed)** session. Noctalia's setup wizard takes it from there.
4. In the background the Flatpak apps and the Brewfile install once the network is up. A reboot or two later, `fenoa-apply-m1n1` has refreshed m1n1 and the devicetree for the installed kernel.

Then, for DRM video in Brave: open Brave once, and run `fenoa-widevine`.

## Use

- `Super + Space` opens the launcher, `Super + Return` a terminal, `Super + Escape` the session menu. The full list is in [docs/desktop.md](docs/desktop.md).
- Your config is `~/.config/hypr/hyprland.lua` and `~/.config/noctalia/config.toml`; both load Fenoa's defaults from `/usr/share/fenoa` first, so image updates keep improving the defaults without touching your changes.
- SSH is off: `sshd` is disabled and the firewall does not let it in. To log in remotely, run `sudo systemctl enable --now sshd` and `sudo firewall-cmd --permanent --add-service=ssh && sudo firewall-cmd --reload`.
- Upgrading from an earlier Fenoa image switches SSH off as well; if you relied on it, run those two commands again after the upgrade.

## Update

```sh
sudo bootc upgrade && sudo reboot
```

Apple Silicon needs one more reboot when the kernel changes: the first boot onto a new kernel refreshes m1n1 and the devicetree, the next one uses them (`FENOA_M1N1_AUTOREBOOT=1` in `/etc/default/fenoa-m1n1` takes it automatically). Flatpaks update daily and Homebrew updates itself, independently of the image. `sudo bootc rollback` returns to the previous image.

## Build and test

On an aarch64 host with podman and ~20 GB free:

```sh
./images/build.sh fenoa          # platform stage + desktop → fenoa:44
./images/build.sh fairydust      # FROM fenoa:44 → fenoa-fairydust:44
./test/all                       # no image needed: syntax, unit tests, deploy library tests
```

The image smoke tests and a real `bootc install to-disk` run in CI on an arm64 runner. See [docs/testing.md](docs/testing.md).

## Documentation

- [docs/architecture.md](docs/architecture.md) — how the image is put together
- [docs/desktop.md](docs/desktop.md) — the session, key bindings, configuration and the greeter
- [docs/asahi.md](docs/asahi.md) — Apple Silicon platform decisions
- [docs/fairydust.md](docs/fairydust.md) — the fairydust kernel variant
- [docs/testing.md](docs/testing.md) — what is tested where
- [deploy/README.md](deploy/README.md) — installing, the ESP, signing, first boot, m1n1

## Credits

Fenoa's platform layer — the bootc plumbing for Asahi, the first-boot and provisioning helpers, the deploy tooling and much of the system tuning — comes from omarchy-atomic, a Fedora Asahi atomic fork of [Omarchy](https://omarchy.org). Thanks to the [Asahi Linux](https://asahilinux.org) project, the [Fedora Asahi Remix atomic desktops](https://github.com/fedora-asahi-remix-atomic-desktops) project, [Universal Blue](https://universal-blue.org) for the prebuilt Homebrew image, and the [Noctalia](https://noctalia.dev) team.
