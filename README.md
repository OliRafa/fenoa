# Fenoa

**Fe**dora **No**ctalia **A**tomic — an image-based desktop for x86_64 PCs.

Fenoa is a [bootc](https://bootc-dev.github.io/bootc/) image built on Fedora's atomic base: a [Hyprland](https://hypr.land) desktop with the [Noctalia](https://noctalia.dev) shell and [noctalia-greeter](https://github.com/noctalia-dev/noctalia-greeter) login screen, booted through systemd-boot on bootc's composefs backend. The whole OS is one signed container image; updates are atomic and roll back with `bootc rollback`.

| Image | What it is |
|---|---|
| `ghcr.io/olirafa/fenoa:44` | Hyprland + Noctalia. A multi-arch name: on a PC it resolves to `fenoa:44-amd64`, built from this branch; on an Apple Silicon Mac to `fenoa:44-arm64`, built from the [`asahi` branch](https://github.com/OliRafa/fenoa/tree/asahi) |

It is rebuilt weekly and on every change, smoke-tested, and cosign-signed (keyless, through GitHub's OIDC):

```sh
cosign verify ghcr.io/olirafa/fenoa:44 \
  --certificate-identity-regexp 'https://github.com/OliRafa/fenoa/.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## What you get

- **Desktop:** Hyprland (Lua config) with Noctalia for the bar, launcher, control center, notifications, OSD, lock screen, idle handling, polkit prompts, clipboard history, screenshots, night light and wallpaper. Noctalia's palette (a built-in scheme, or one generated from your wallpaper) also colours native GTK apps (Nautilus, settings dialogs), foot and Hyprland's borders. Flatpak apps don't get the palette, but they do follow the light/dark switch: GTK3, GTK4/libadwaita and Qt apps on Flathub runtimes, and Firefox, Chromium and Electron apps whose own theme setting is "system" or "device".
- **Login:** noctalia-greeter on greetd, styled like the shell (Noctalia syncs your wallpaper and palette to it). Your login password unlocks the GNOME keyring.
- **Apps:** foot, Nautilus, mpv, wf-recorder, udiskie (USB automount), Docker, Tailscale and Homebrew in the image; Brave, Bitwarden, Loupe, Evince, LibreOffice, Obsidian, LocalSend and OBS Studio (Flathub) installed on first boot; shell and developer tools (starship, zoxide, fzf, eza, bat, ripgrep, fd, lazygit, btop, Neovim, tmux, gh, language toolchains) from the [Brewfile](Brewfile). Source Code Pro is the default monospace font.
- **PC hardware:** UEFI machines with AMD or Intel graphics, booted through systemd-boot on composefs (Secure Boot off), with Fedora's firmware, microcode and fwupd. A fingerprint reader libfprint supports unlocks the lock screen and answers sudo and polkit prompts once you enroll a finger (`fprintd-enroll`). See [docs/platform.md](docs/platform.md).

## Install

Turn Secure Boot off in the firmware setup, boot any Linux live image with podman (Fedora Workstation Live has it), and install onto a disk, which this erases:

```sh
sudo podman run --rm --privileged --pid=host \
  --security-opt label=type:unconfined_t \
  -v /dev:/dev -v /var/lib/containers:/var/lib/containers \
  ghcr.io/olirafa/fenoa:44 \
  bootc install to-disk --composefs-backend --bootloader systemd --filesystem btrfs /dev/nvme0n1
sudo reboot
```

Already on Fedora Atomic (Silverblue, Kinoite...) or another bootc image? Switch in place; this keeps that system's bootloader (and Secure Boot), its users and its machine ID:

```sh
sudo bootc switch ghcr.io/olirafa/fenoa:44
sudo reboot
```

Details, hardware support and caveats: [docs/platform.md](docs/platform.md).

### First boot

This is the first boot of a fresh install (`bootc install`). A `bootc switch` from an existing system keeps its machine ID and its user, so neither prompt below appears.

1. `systemd-firstboot` asks on tty1 for the locale, the keymap and the timezone. It asks for no hostname (set one later with `hostnamectl hostname <name>`) and no root password: root stays locked, and the user you create next gets `sudo`. The login screen and Hyprland follow the keymap you pick.
2. `fenoa-firstboot-user` asks for your username, full name and password on tty1 (or reads a preseed from `/etc/fenoa/firstboot-user.conf`). The account's login shell is zsh, with Fedora's stock configuration (the `~/.zshrc` and `~/.zprofile` the zsh package puts in `/etc/skel`).
3. The greeter comes up; log in to the **Hyprland (uwsm-managed)** session. Noctalia's setup wizard takes it from there.
4. In the background the Flatpak apps and the Brewfile install once the network is up: until Flathub and Homebrew's servers answer over HTTPS, each is tried again every couple of minutes, so connecting to Wi-Fi from the desktop is enough. A Flatpak install that fails is tried again a couple of minutes later too; only if a remote answers but its index then cannot be fetched does `flatpak preinstall` report "Nothing to do." and succeed, and the app set waits for the next boot. A Brewfile that fails to apply is tried again after a growing delay (5 minutes, up to 2 hours).

Fenoa's shell setup for the Brewfile's tools (the starship prompt, zoxide, fzf and eza) is wired into bash only, by `/etc/profile.d/fenoa-shell.sh`; zsh gets none of it. Accounts that already existed keep their login shell, including one carried over by a `bootc switch`: `chsh -s /usr/bin/zsh` switches to zsh, `chsh -s /bin/bash` back.

## Use

- `Super + Space` opens the launcher, `Super + Return` a terminal, `Super + Escape` the session menu. The full list is in [docs/desktop.md](docs/desktop.md).
- Your config is `~/.config/hypr/hyprland.lua` and `~/.config/noctalia/config.toml`; both load Fenoa's defaults from `/usr/share/fenoa` first, so image updates keep improving the defaults without touching your changes.
- SSH is off: `sshd` is disabled and the firewall does not let it in. To log in remotely, run `sudo systemctl enable --now sshd` and `sudo firewall-cmd --permanent --add-service=ssh && sudo firewall-cmd --reload`.
- Upgrading from an earlier Fenoa image switches SSH off as well; if you relied on it, run those two commands again after the upgrade.
- Tailscale's daemon runs from boot; log in once with `sudo tailscale up --operator=$USER` (see [docs/platform.md](docs/platform.md#tailscale)).

## Update

```sh
sudo bootc upgrade && sudo reboot
```

Flatpaks update daily and Homebrew updates itself, independently of the image. `sudo bootc rollback` returns to the previous image.

## Build and test

On an x86_64 host with podman and ~20 GB free:

```sh
./images/build.sh fenoa          # platform stage + desktop → fenoa:44
./test/all                       # no image needed: syntax and unit tests
```

The image smoke tests and a real `bootc install to-disk` run in CI on an x86_64 runner. See [docs/testing.md](docs/testing.md).

## Documentation

- [docs/architecture.md](docs/architecture.md) — how the image is put together
- [docs/desktop.md](docs/desktop.md) — the session, key bindings, configuration and the greeter
- [docs/platform.md](docs/platform.md) — installing, hardware support and the x86_64 platform decisions
- [docs/testing.md](docs/testing.md) — what is tested where

## Credits

Fenoa's platform layer — the bootc plumbing, the first-boot and provisioning helpers and much of the system tuning — comes from omarchy-atomic, a Fedora Asahi atomic fork of [Omarchy](https://omarchy.org), by way of Fenoa for Apple Silicon. Thanks to the [Fedora Atomic Desktops](https://fedoraproject.org/atomic-desktops/) and [Asahi Linux](https://asahilinux.org) projects, [Universal Blue](https://universal-blue.org) for the prebuilt Homebrew image, and the [Noctalia](https://noctalia.dev) team.
