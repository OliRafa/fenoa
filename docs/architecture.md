# Architecture

How the Fenoa image is put together, and where each kind of file lives.

## Images and stages

```
quay.io/fedora-asahi-remix-atomic-desktops/base-atomic:44   Asahi kernel-16k, firmware, m1n1/U-Boot, dracut, audio DSP
  └─ images/fenoa/Containerfile  (stage: platform)          bootc plumbing for Apple Silicon — never published
       └─ images/fenoa/Containerfile  (stage: desktop)      Hyprland + Noctalia + greeter  →  ghcr.io/olirafa/fenoa
            └─ images/fairydust/Containerfile               fairydust kernel swap          →  ghcr.io/olirafa/fenoa-fairydust
ghcr.io/ublue-os/brew           → prebuilt Homebrew tree copied in by the platform stage
ghcr.io/olirafa/omarchy-fairydust-kernel → /usr/lib/modules/<kver> copied in by the fairydust image
```

The split follows one rule: the **platform** stage holds everything a non-graphical Fedora Asahi bootc install needs (boot, firmware, drivers, system services, provisioning); the **desktop** stage holds everything that exists for the Hyprland/Noctalia session. `./images/build.sh platform` builds the platform stage on its own, and CI smoke-tests it before building the desktop on top.

### platform (`images/fenoa/Containerfile`, steps P1–P10)

| Step | What | Why |
|---|---|---|
| P1 | `packages/platform.packages` | system services, Asahi extras (tiny-dfr, widevine-installer, Honeykrisp), Docker, base CLI |
| P2 | remove Firefox | the browser is a Flatpak |
| P3 | systemd-boot; drop rpm-ostree/bootupd/GRUB; mask grub boot-success units | composefs + systemd-boot install; see [asahi.md](asahi.md) |
| P4 | `COPY system/platform/ /` | units, helpers, tuning drop-ins, Apple HID modprobe/dracut config |
| P5 | rebuild the initramfs with the `bootc` dracut module | composefs pivot; Apple HID drivers loaded early |
| P6 | `DTBS` → image devicetree; enable `fenoa-apply-m1n1` | m1n1/devicetree refresh on atomic |
| P7 | enable `fenoa-firstboot-user`, `systemd-firstboot` | the image ships no user |
| P8 | ublue brew tree + Brewfile; baked Flathub remote; enable provisioning units | `/var` is seeded only on first boot |
| P9 | enable system services; mask NetworkManager-wait-online | |
| P10 | clean residue; `bootc container lint` | |

### desktop (steps D1–D6)

| Step | What |
|---|---|
| D1 | lionheartp/Hyprland COPR (priority 10, never replaces GTK/Pango/Cairo) and Terra restricted to `noctalia-greeter`, both via `/etc/dnf/repos.override.d` |
| D2 | `hyprland` + `hyprland-uwsm`, falling back to the `-git` builds when stable is unresolvable |
| D3 | `packages/desktop.packages` |
| D4 | `COPY system/desktop/ /`; assert the greeter account, binaries and session name |
| D5 | enable greetd (it aliases `display-manager.service`); default to `graphical.target` |
| D6 | clean residue; `bootc container lint` |

### fairydust (`images/fairydust/Containerfile`, F1–F3)

Copies the fairydust kernel tree in, removes every other kernel, runs `depmod`, and rebuilds the initramfs exactly like P5. See [fairydust.md](fairydust.md).

## Where files go

| Path | Owner | Notes |
|---|---|---|
| `/usr/lib/systemd/**`, `/usr/lib/sysctl.d`, `/usr/lib/udev/rules.d`, `/usr/lib/modprobe.d`, `/usr/lib/dracut/dracut.conf.d`, `/usr/lib/tmpfiles.d`, `/usr/lib/NetworkManager/conf.d`, `/usr/share/polkit-1/rules.d` | image | vendor drop-in paths: updates flow through `bootc upgrade` and an admin can still override in `/etc` |
| `/etc/sudoers.d`, `/etc/security/faillock.conf`, `/etc/docker/daemon.json`, `/etc/cups/cups-browsed.conf`, `/etc/greetd/config.toml`, `/etc/xdg/*` | image, merged | only where the consumer reads nothing else; `/etc` is three-way merged on upgrade, so a local edit sticks |
| `/usr/share/fenoa/hypr`, `/usr/share/fenoa/noctalia`, `/usr/share/fenoa/greeter` | image | desktop defaults, pulled in by the user's config |
| `/etc/skel/.config/{hypr,noctalia}` | image → user | thin files seeded into a new home that load the `/usr/share/fenoa` defaults |
| `/var/lib/fenoa` | runtime | first-boot markers and the m1n1 stamp |
| `/var/lib/noctalia-greeter` | runtime (tmpfiles) | greeter state; `greeter.toml` is a link back into `/usr/share/fenoa/greeter` |
| `/var/lib/flatpak`, `/home/linuxbrew` | runtime | Flatpak apps and the Homebrew prefix, provisioned on first boot and updated on their own timers |

`/var` is created from the image only on the first boot of a deployment and never updated by `bootc upgrade`, so nothing in the image may rely on content baked into `/var`; directories come from `tmpfiles.d`, state from first-boot units.

## Desktop configuration layering

```
~/.config/hypr/hyprland.lua            (user; seeded from /etc/skel)
  dofile /usr/share/fenoa/hypr/bootstrap.lua     module path + reload-safe requires
  require "fenoa"                                 /usr/share/fenoa/hypr/fenoa/*.lua
  ... user overrides ...
  require "noctalia" (guarded)                    ~/.config/hypr/noctalia.lua, rendered by Noctalia

~/.config/noctalia/config.toml         (user; seeded from /etc/skel)
  [include] /usr/share/fenoa/noctalia/fenoa.toml
  ... user overrides ...
~/.local/state/noctalia/settings.toml  (Noctalia's Settings window; wins over both)
```

Hyprland keeps one Lua state across `hyprctl reload`, so the bootstrap drops the `fenoa.*` and `noctalia` modules from `package.loaded` before they are required again; otherwise a reload would re-run none of the defaults.

## Boot and session flow

```
m1n1 → U-Boot → systemd-boot → kernel + initramfs (bootc composefs pivot, hid_apple loaded)
  → systemd-firstboot, fenoa-firstboot-user (first boot only, tty1)
  → greetd → noctalia-greeter-session (bundled wlroots compositor) → PAM (/etc/pam.d/greetd, keyring unlock)
  → uwsm start hyprland.desktop → Hyprland → uwsm-app noctalia
background: fenoa-apply-m1n1, fenoa-flatpak-preinstall, brew-setup → fenoa-brew-setup
```
