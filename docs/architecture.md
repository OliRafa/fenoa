# Architecture

How the Fenoa image is put together, and where each kind of file lives.

## Images and stages

```
quay.io/fedora-ostree-desktops/base-atomic:44   kernel, linux-firmware, microcode, Mesa, fwupd, dracut (x86_64)
  └─ images/fenoa/Containerfile  (stage: platform)          bootc plumbing for x86_64 PCs — never published
       └─ images/fenoa/Containerfile  (stage: desktop)      Hyprland + Noctalia + greeter  →  ghcr.io/olirafa/fenoa:44-amd64 (in the fenoa:44 index)
ghcr.io/ublue-os/brew           → prebuilt Homebrew tree copied in by the platform stage
images/fenoa/Containerfile (stage: librepods) → the AirPods plugin's daemon, built from a pinned commit of
                                  github.com/harveywuk/librepods and copied in by the desktop stage
github.com/akitaonrails/ai-usagebar releases → the AI Usage plugin's CLI, signature-checked, copied in by the desktop stage
```

`fenoa:44` is a multi-arch index: this branch publishes `fenoa:44-amd64`, the `asahi` branch (Fedora Asahi Remix, Apple Silicon) publishes `fenoa:44-arm64`, and each stream's publish points `fenoa:44` and `latest` at the newest image of both (`images/publish-index.sh`).

The split follows one rule: the **platform** stage holds everything a non-graphical Fedora bootc install needs (boot, firmware, drivers, system services, provisioning); the **desktop** stage holds everything that exists for the Hyprland/Noctalia session. `./images/build.sh platform` builds the platform stage on its own, and CI smoke-tests it before building the desktop on top.

### platform (`images/fenoa/Containerfile`, steps P1–P9)

| Step | What | Why |
|---|---|---|
| P1 | `packages/platform.packages` | system services, systemd-boot, the Vulkan and Intel VA-API drivers (already in the base, listed so they stay), Docker, base CLI, zsh (new accounts' login shell) |
| P2 | remove Firefox | the browser is a Flatpak |
| P3 | systemd-boot; remove rpm-ostree, bootupd, GRUB and shim (and with them GRUB's boot-success units); fail if any survive | composefs + systemd-boot install; see [platform.md](platform.md) |
| P4 | `COPY system/platform/ /` | units, helpers, tuning drop-ins |
| P5 | rebuild the initramfs with the `bootc` and `ostree` dracut modules | composefs pivot for an install, ostree pivot for a Fedora Atomic switched to Fenoa |
| P6 | enable `fenoa-firstboot-user` (`systemd-firstboot` is static and needs no enabling) | the image ships no user |
| P7 | ublue brew tree + Brewfile; baked Flathub remote; enable the provisioning units (the Flatpak preinstall and the Brewfile setup through their timers) | `/var` is seeded only on first boot; see [Provisioning and the network](#provisioning-and-the-network) |
| P8 | enable system services; mask NetworkManager-wait-online; disable sshd and drop `ssh` from the default firewalld zone | nothing in the boot waits for the network (the units that need it check for themselves); SSH is opt-in, and `50-fenoa.preset` keeps a preset pass from re-enabling sshd |
| P9 | `/etc/machine-id` = `uninitialized`; clean residue; `bootc container lint` | systemd detects each install's first boot (an empty file does not count), so systemd-firstboot runs |

### desktop (steps D1–D6)

| Step | What |
|---|---|
| D1 | lionheartp/Hyprland COPR (priority 10; its GTK/Pango/Cairo and Noctalia/greeter/Quickshell builds excluded) and Terra restricted to `noctalia-greeter`, both via `/etc/dnf/repos.override.d` |
| D2 | `hyprland` + `hyprland-uwsm`, falling back to the `-git` builds when stable is unresolvable |
| D3 | `packages/desktop.packages` |
| D3b | the `ai-usagebar` CLI for the AI Usage plugin: upstream's latest release, which must be signed by the pinned key (`AI_USAGEBAR_KEY`) |
| D3c | `librepods` and `librepods-ctl` from the librepods stage for the AirPods plugin; its user unit pointed at `/usr/bin` and enabled for every user (`systemctl --global`, kept by `user-preset/50-fenoa-desktop.preset`); fail if either binary is missing a library |
| D4 | `COPY system/desktop/ /`; assert the greeter account, binaries and session name; install the SELinux file context for the greeter's state directory |
| D5 | enable greetd (it aliases `display-manager.service`); default to `graphical.target` |
| D6 | `/etc/machine-id` = `uninitialized` again, in case anything D3 installed wrote an ID; clean residue; `bootc container lint` |

## Where files go

| Path | Owner | Notes |
|---|---|---|
| `/usr/lib/systemd/**` (including `system-preset`), `/usr/lib/sysctl.d`, `/usr/lib/udev/rules.d`, `/usr/lib/modprobe.d`, `/usr/lib/dracut/dracut.conf.d`, `/usr/lib/tmpfiles.d`, `/usr/lib/NetworkManager/conf.d`, `/usr/share/polkit-1/rules.d` | image | vendor drop-in paths: updates flow through `bootc upgrade` and an admin can still override in `/etc` |
| `/etc/sudoers.d`, `/etc/docker/daemon.json`, `/etc/cups/cups-browsed.conf`, `/etc/greetd/config.toml`, `/etc/xdg-desktop-portal/hyprland-portals.conf`, `/etc/xdg/*` | image, merged | only where the consumer reads nothing else; `/etc` is three-way merged on upgrade, so a local edit sticks |
| `/usr/share/fenoa/hypr`, `/usr/share/fenoa/noctalia`, `/usr/share/fenoa/greeter` | image | desktop defaults, pulled in by the user's config |
| `/etc/skel/.config/{hypr,noctalia}` | image → user | thin files seeded into a new home that load the `/usr/share/fenoa` defaults |
| `/var/lib/fenoa` | runtime | first-boot markers |
| `/var/lib/noctalia-greeter` | runtime (tmpfiles) | greeter state; `greeter.toml` is a link back into `/usr/share/fenoa/greeter` |
| `/var/lib/flatpak`, `/home/linuxbrew` | runtime | Flatpak apps and the Homebrew prefix, provisioned on first boot and updated on their own timers |

Every unit a Containerfile enables or disables (or makes the default target) also has a line in that stage's preset file, `/usr/lib/systemd/system-preset/50-fenoa.preset` or `50-fenoa-desktop.preset`. The image ships `/etc/machine-id` as `uninitialized`, so every install has a first boot, and a first boot makes systemd run a full preset pass, which sets every unit to what the presets say and, through Fedora's `99-default-disable.preset`, disables anything they do not list; without those lines it would switch off greetd and the first-boot units. The smoke tests run `systemctl preset-all` in the image and require that nothing changes.

`/var` is created from the image only on the first boot of a deployment and never updated by `bootc upgrade`, so nothing in the image may rely on content baked into `/var`; directories come from `tmpfiles.d`, state from first-boot units.

## Desktop configuration layering

```
~/.config/hypr/hyprland.lua            (user; seeded from /etc/skel)
  dofile /usr/share/fenoa/hypr/bootstrap.lua     puts the defaults on the module path
  require "fenoa"                                 /usr/share/fenoa/hypr/fenoa/*.lua
  ... user overrides ...
  require "noctalia" (guarded)                    ~/.config/hypr/noctalia.lua, rendered by Noctalia

~/.config/noctalia/config.toml         (user; seeded from /etc/skel)
  [include] /usr/share/fenoa/noctalia/fenoa.toml
  ... user overrides ...
~/.local/state/noctalia/settings.toml  (Noctalia's Settings window; wins over both)
```

Each `hyprctl reload` runs the config in a fresh Lua state, so `require` loads the defaults (and Noctalia's palette module) again and their settings, bindings and rules are re-applied; the bootstrap only has to put `/usr/share/fenoa/hypr` on `package.path`.

## Boot and session flow

```
UEFI firmware → systemd-boot → kernel + initramfs (bootc composefs pivot)
  → first boot only (/etc/machine-id ships "uninitialized"): full preset pass, then on tty1
      systemd-firstboot (locale, keymap, timezone) and fenoa-firstboot-user (the account, zsh as its shell)
  → greetd → fenoa-greeter-session (XKB_DEFAULT_* from fenoa/keyboard.lua) → noctalia-greeter-session
      (bundled wlroots compositor) → PAM (/etc/pam.d/greetd, keyring unlock)
  → uwsm start hyprland.desktop → Hyprland → uwsm-app noctalia
background: brew-setup (unpacks Homebrew)
timers, once the network is up: fenoa-flatpak-preinstall, fenoa-brew-setup (30s after boot, then every 2 min until the hosts each needs answer)
```

## Provisioning and the network

The image masks `NetworkManager-wait-online`, so nothing in the boot waits for the network and `network-online.target` is reached before Wi-Fi has associated; on a fresh install Wi-Fi is not even configured until the user sets it up in the session. A unit that needs the network therefore cannot be started at boot and ordered after `network-online.target`: it runs offline. For `flatpak preinstall` that is silent, because offline it skips every ref it cannot reach, prints "Nothing to do." and exits 0.

The units that need the network wait for it themselves:

- `ExecCondition=/usr/libexec/fenoa-online [--wait=SECONDS] HOST...` asks each host the unit is about to talk to for `https://HOST/` with curl (each request bounded by a timeout). Any HTTP status counts as an answer, but the certificate has to validate: a name that merely resolves is not enough, because a captive portal, or a host pinned to the wrong address, resolves too and `flatpak preinstall` still exits 0 having installed nothing. While a host does not answer it exits 1 and systemd skips the unit: inactive, not failed. `--wait` keeps asking every few seconds for a bounded time before giving up. Misuse, or a check that cannot run (no curl, no CA bundle), exits 255, which systemd counts as a failure rather than a skip, so a broken condition is reported instead of skipping forever. What that failure looks like depends on the unit: the Flatpak units show in `systemctl --failed`; `fenoa-brew-setup` restarts on it like on any other failure (see below), so it never shows there and only its journal tells.
- A timer starts the unit `OnBootSec=30s` and again `OnUnitInactiveSec=2min` after each run that ended inactive (skipped) or failed.
- The service is `Type=oneshot` with `RemainAfterExit=yes` and no `[Install]` section: a run that exits 0 stays active, so the timer has nothing left to start until the next boot. With `--noninteractive`, an install or download error makes `flatpak preinstall` exit 1, so the unit fails and the timer tries again 2 minutes later. One case waits for the next boot: a remote passes the HTTPS check but its index then cannot be fetched, and `flatpak preinstall` skips its refs, prints "Nothing to do." and exits 0.
- The service has no `Condition*=` at all: a unit skipped by a plain condition is inactive too, so the timer would start it every 2 minutes for the rest of the boot.
- Where a real failure is expensive to repeat (`brew bundle` may build formulae from source), the service backs off on its own: `Restart=on-failure` from 5 minutes up to 2 hours (`RestartSteps=`, `RestartMaxDelaySec=`), with `RestartMode=direct`. Without that mode each failure leaves the unit inactive for an instant, the timer's `OnUnitInactiveSec=` fires on top of the pending restart, and its start cuts the delay short and resets the backoff (seen on systemd 259). A skip by `ExecCondition=` never triggers a restart; a 255 from `fenoa-online` is a failure, so it does.

| Unit | Started by | Waits for |
|---|---|---|
| `fenoa-flatpak-preinstall.service` | `fenoa-flatpak-preinstall.timer`, every boot (later additions to the app set apply; apps the user removed stay removed) | `dl.flathub.org` |
| `fenoa-flatpak-update.service` | `fenoa-flatpak-update.timer`, daily | the same hosts, with `--wait=300`: the catch-up run fires at boot or right at resume, before Wi-Fi has reconnected, and nothing retries it, so it waits up to 5 minutes for the network (then checks for a metered link) and only then skips until the next day |
| `fenoa-brew-setup.service` | `fenoa-brew-setup.timer`, every boot; wants and is ordered after `brew-setup.service` (the unpack: re-queued on every try, a no-op once done) and is ordered after `fenoa-firstboot-user.service` (the account) | `formulae.brew.sh`, `ghcr.io`, until the Brewfile has been applied: once `/var/lib/fenoa/brew-setup-done` exists the condition passes at once and the run is an instant no-op. A `brew bundle` that fails is retried with a growing delay instead of every 2 minutes (see above) |
