# Testing

Three tiers, from cheapest to most faithful.

## 1. No image: `./test/all`

Runs anywhere (CI: `.github/workflows/tests.yml` on ubuntu, plus shellcheck at error level).

- `bash -n` on every shell script (`test/shell-files` lists them: `*.sh` plus anything with a `#!/bin/bash` shebang)
- `test/unit` — every `test/unit.d/*-test.sh`, hermetic, stubbing commands through `PATH`:
  - `firstboot-user-test.sh` — unit gating, the DynamicUser UID trap, marker/preseed handling, zsh as the login shell (bash when zsh is missing), the XKB layout filled in for a KEYMAP-only `vconsole.conf` that systemd-firstboot did not convert and `kbd-model-map` cannot map (and the US-layout warning otherwise)
  - `brew-setup-test.sh` — the timer and its static service, the condition (the helper's stamp, else `fenoa-online` for Homebrew's hosts) run against a stub, the restart backoff for real failures, wanting and ordering after the unpack and ordering after the account, build and preset wiring; primary-user detection, empty-prefix debris, no download
  - `flatpak-provisioning-test.sh` — the preinstall timer and its static service (`fenoa-online` condition, no `Restart=`, no condition the timer could loop on, not ordered before the system helper), the update units (a bounded network wait before the metered check), and their build and preset wiring
  - `online-test.sh` — `fenoa-online` asks `https://HOST/` with neither `--fail` nor `--insecure`; its exit status (0 answered, 1 no answer, a certificate that does not validate or a timeout, 255 misuse, including an octal-looking or overlong `--wait`, or a check that cannot run); `--wait` retrying until an answer or its bound; and the hosts the units pass it
  - `platform-overlay-test.sh` — the initramfs rebuild adds and checks both root pivots (composefs, ostree) after the overlay is copied, the units the platform stage enables ship, `50-fenoa.preset` (and the boottest image's preset) covers every unit the Containerfile enables or disables and is read before Fedora's presets, sshd stays off, no Omarchy leftovers, shebangs
  - `desktop-config-test.sh` — config parsing and cross-file agreement (greetd ↔ tmpfiles ↔ greeter, skel ↔ defaults, bindings ↔ helpers, Flatpaks ↔ default apps, the Flatpak app groups pinned to `stable` and the light and dark adw-gtk3 theme extensions at 3.22, `QT_QPA_PLATFORMTHEME=gtk3` for Qt Flatpaks, the Secret portal ↔ gnome-keyring, the desktop stage's units ↔ `50-fenoa-desktop.preset`, its `--global` user units ↔ `user-preset/50-fenoa-desktop.preset` (and its `fenoa-*` user units ship), Noctalia plugin widgets ↔ enabled plugins ↔ what the image ships for them), no second locker replacing a live lock; runs `Hyprland --verify-config` when Hyprland is installed
  - `desktop-helpers-test.sh` — `fenoa-kbd-backlight` and `fenoa-hypr-clamshell`
  - `bitwarden-browsers-test.sh` — `fenoa-bitwarden-browsers` against fake Flatpak installations and a stub `flatpak`: Brave's manifest runs `desktop_proxy` from Bitwarden's `current/active`, its two overrides, the socket symlink in its cache (canonical paths), Firefox's `native-messaging-hosts` directory and the same socket symlink and override, so both browsers share one socket, read-only (a read-write override is downgraded); idempotent, a Flatpak change during a run runs it again; a symlink out of a browser's directory (to Bitwarden's data or to an empty directory) or a FIFO manifest is never followed, and a directory it did not make is never removed; a manifest running another existing proxy and an override the user revoked are left alone; cleanup once Bitwarden is gone; the user installation first; the units (no start limit, a start timeout, not for system accounts, both `.changed` stamps) and the polkit action
  - `keyboard-layout-test.sh` — `fenoa/keyboard.lua` derives the layout from `localectl`'s XKB settings or the console keymap (via `kbd-model-map`), Latin layout first; `input.lua` and `fenoa-greeter-session` hand exactly that to Hyprland and the greeter, and the greeter still starts when the resolver cannot run
  - `publish-index-test.sh` — `images/publish-index.sh` lists each stream's arch tag in the multi-arch `fenoa:44` index, keeps an architecture that has no tag yet from the current `fenoa:44` (an index, or the single-arch image it was), and pushes nothing when there is no image or the registry errors
  - `shell-setup-test.sh` — `/etc/profile.d/fenoa-shell.sh` wires starship, zoxide, fzf and eza into interactive bash only when installed, and leaves other shells (zsh) alone

Unit tests source `test/unit.d/base-test.sh` (`pass`, `fail`, `require_command`, and `containerfile_units`/`check_preset` for the preset coverage checks). A file stops at its first failure; the runner keeps going and reports every failing file.

## 2. Built image: `images/*/hack/`

CI: `.github/workflows/image-e2e.yml` on `ubuntu-24.04` (x86_64), building with rootful podman because `bootc install` reads `/var/lib/containers`.

| Script | Against | Checks |
|---|---|---|
| `images/fenoa/hack/platform-smoke.sh` | platform stage, `fenoa` | x86_64 Fedora base (firmware, microcode, fwupd, the Vulkan and Intel VA-API drivers), one kernel, systemd-boot, no GRUB, shim, bootupd or rpm-ostree, initramfs (composefs and ostree pivots), first-boot/Flatpak/brew units (the Flatpak preinstall and Brewfile setup static and started by their enabled timers, `fenoa-online` executable, curl present), zsh (installed, in `/etc/shells`, its stock skel files), `/etc/machine-id` reads `uninitialized`, services, Tailscale's build of `tailscale`, sshd off (also after a preset pass) and closed in firewalld, tuning files, the fingerprint wiring (fprintd and its PAM module, the lid check, `fenoa-fingerprint` first in sudo's and polkit-1's auth stacks, no `pam_fprintd` in `system-auth`, `password-auth` or `login`, and sudo still taking the right password and only that with no reader), a full `systemctl preset-all` (what a first boot runs) changes nothing, no Omarchy |
| `images/fenoa/hack/desktop-smoke.sh` | `fenoa` | packages, greetd as display manager, greeter account/PAM/state dir, the greeter wrapper exports a keyboard layout, the Secret portal routed to gnome-keyring, the greeter finds its default session, polkit rule ↔ packaged action, `noctalia config validate` (only plugin widgets, unknown until Noctalia fetches them, may warn) and `Hyprland --verify-config` on the seeded config, the `ai-usagebar` CLI and the librepods binaries and user unit for the bar plugins, Bitwarden's polkit action and the `fenoa-bitwarden-browsers` helper and user units (enabled for every user), default apps, the Flatpak app set and the adw-gtk3 theme extensions in the preinstall manifest, greetd and `graphical.target` survive a full `systemctl preset-all`, and librepods a global preset |
| `images/fenoa/hack/first-boot.sh` | platform stage; `fenoa` with `DESKTOP=1` | preseeded user creation under a populated machine-id and a DynamicUser account, zsh login shell and seeded `~/.zshrc`, marker, scrubbing, idempotence, skel seeding, `systemd-analyze verify` |
| `images/fenoa/hack/install-to-disk.sh` | `fenoa` | real `bootc install to-disk --composefs-backend --bootloader systemd`, inspected by loop mount: systemd-boot on the ESP, no GRUB or shim there; the installed `/etc/machine-id` still reads `uninitialized`, so the first boot will be detected |

On a stream branch (a push, its weekly run or a manual run; never a pull request) this workflow ends by pushing the image every step above tested as the immutable `fenoa:44-<sha>` and calling `publish.yml` with its digest, which tags that digest `fenoa:44-amd64`, signs it and rebuilds the `fenoa:44` index. Nothing is built twice, and what machines pull is byte for byte what passed these tests.

## 3. A real boot: `images/boottest/`

Boot-time behaviour is checked on a booted install, on a PC or in a UEFI VM (OVMF) with Secure Boot off:

```sh
podman build -t fenoa:44-boottest --build-arg BASE=fenoa:44 -f images/boottest/Containerfile .
# install it (bootc install to-disk, or bootc switch to a pushed tag), boot it, then:
journalctl -u fenoa-boottest
```

`boot-smoke.sh` checks the running kernel and GPU render node, systemd-boot on the ESP of the disk the system runs from with no GRUB or shim there (and notes the Secure Boot state; on a Fedora Atomic switched to Fenoa, which keeps its GRUB, only that it booted through the ostree backend), services (greetd, NetworkManager, firewalld…), zram, failed units, the greeter process and state directory, SELinux denials for greetd/noctalia-greeter, and first-boot provisioning (including a machine ID committed in place of `uninitialized`, and the provisioning timers enabled).

Only a real boot shows: the tty1 first-boot prompts (systemd-firstboot's locale, keymap and timezone, then fenoa-firstboot-user's account), the greeter handoff into Hyprland, a `bootc switch` from Fedora Atomic, and anything SELinux only denies at runtime.
