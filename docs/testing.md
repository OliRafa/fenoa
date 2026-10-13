# Testing

Three tiers, from cheapest to most faithful.

## 1. No image: `./test/all`

Runs anywhere (CI: `.github/workflows/tests.yml` on ubuntu, plus shellcheck at error level).

- `bash -n` on every shell script (`test/shell-files` lists them: `*.sh` plus anything with a `#!/bin/bash` shebang)
- `test/unit` — every `test/unit.d/*-test.sh`, hermetic, stubbing commands through `PATH`:
  - `apply-m1n1-test.sh` — the zero-mtime gzip workaround in `fenoa-apply-m1n1`, and that it only runs on a boot that came through m1n1
  - `firstboot-user-test.sh` — unit gating, the DynamicUser UID trap, marker/preseed handling, zsh as the login shell (bash when zsh is missing), the XKB layout filled in for a KEYMAP-only `vconsole.conf` that systemd-firstboot did not convert and `kbd-model-map` cannot map (and the US-layout warning otherwise)
  - `brew-setup-test.sh` — the timer and its static service, the condition (the helper's stamp, else `fenoa-online` for Homebrew's hosts) run against a stub, the restart backoff for real failures, wanting and ordering after the unpack and ordering after the account, build and preset wiring; primary-user detection, empty-prefix debris, no download
  - `flatpak-provisioning-test.sh` — the preinstall timer and its static service (`fenoa-online` condition, no `Restart=`, no condition the timer could loop on, not ordered before the system helper), the update units (a bounded network wait before the metered check), and their build and preset wiring
  - `online-test.sh` — `fenoa-online` asks `https://HOST/` with neither `--fail` nor `--insecure`; its exit status (0 answered, 1 no answer, a certificate that does not validate or a timeout, 255 misuse, including an octal-looking or overlong `--wait`, or a check that cannot run); `--wait` retrying until an answer or its bound; and the hosts the units pass it
  - `widevine-test.sh` — CDM wiring into Flatpak profiles, the canonical-path hint, Brave's opt-in
  - `platform-overlay-test.sh` — Apple HID drop-ins reach the initramfs step, enabled units ship, `50-fenoa.preset` (and the boottest image's preset) covers every unit the Containerfile enables or disables and is read before Fedora's presets, sshd stays off, no Omarchy leftovers, shebangs
  - `desktop-config-test.sh` — config parsing and cross-file agreement (greetd ↔ tmpfiles ↔ greeter, skel ↔ defaults, bindings ↔ helpers, Flatpaks ↔ default apps, the Secret portal ↔ gnome-keyring, the desktop stage's units ↔ `50-fenoa-desktop.preset`), no second locker replacing a live lock; runs `Hyprland --verify-config` when Hyprland is installed
  - `desktop-helpers-test.sh` — `fenoa-kbd-backlight` and `fenoa-hypr-clamshell`
  - `keyboard-layout-test.sh` — `fenoa/keyboard.lua` derives the layout from `localectl`'s XKB settings or the console keymap (via `kbd-model-map`), Latin layout first; `input.lua` and `fenoa-greeter-session` hand exactly that to Hyprland and the greeter, and the greeter still starts when the resolver cannot run
  - `shell-setup-test.sh` — `/etc/profile.d/fenoa-shell.sh` wires starship, zoxide, fzf and eza into interactive bash only when installed, and leaves other shells (zsh) alone
- `deploy/tests/*.test.sh` — the ESP backup/restore, capacity, GPT absorb, boot-entry repair and BLS prune libraries

Unit tests source `test/unit.d/base-test.sh` (`pass`, `fail`, `require_command`, and `containerfile_units`/`check_preset` for the preset coverage checks). A file stops at its first failure; the runner keeps going and reports every failing file.

## 2. Built image: `images/*/hack/`

CI: `.github/workflows/image-e2e.yml` on `ubuntu-24.04-arm`, building with rootful podman because `bootc install` reads `/var/lib/containers`.

| Script | Against | Checks |
|---|---|---|
| `images/fenoa/hack/platform-smoke.sh` | platform stage, `fenoa`, `fenoa-fairydust` (`KERNEL=fairydust`) | Asahi base, one kernel, systemd-boot, masked grub units, initramfs (composefs pivot, Apple HID), m1n1 wiring, first-boot/Flatpak/brew units (the Flatpak preinstall and Brewfile setup static and started by their enabled timers, `fenoa-online` executable, curl present), zsh (installed, in `/etc/shells`, its stock skel files), `/etc/machine-id` reads `uninitialized`, services, sshd off (also after a preset pass) and closed in firewalld, tuning files, a full `systemctl preset-all` (what a first boot runs) changes nothing, no Omarchy |
| `images/fenoa/hack/desktop-smoke.sh` | `fenoa`, `fenoa-fairydust` | packages, greetd as display manager, greeter account/PAM/state dir, the greeter wrapper exports a keyboard layout, the Secret portal routed to gnome-keyring, the greeter finds its default session, polkit rule ↔ packaged action, `noctalia config validate` and `Hyprland --verify-config` on the seeded config, default apps, greetd and `graphical.target` survive a full `systemctl preset-all` |
| `images/fenoa/hack/first-boot.sh` | platform stage; `fenoa` with `DESKTOP=1` | preseeded user creation under a populated machine-id and a DynamicUser account, zsh login shell and seeded `~/.zshrc`, marker, scrubbing, idempotence, skel seeding, `systemd-analyze verify` |
| `images/fenoa/hack/install-to-disk.sh` | `fenoa` | real `bootc install to-disk --composefs-backend --bootloader systemd`, inspected by loop mount; the installed `/etc/machine-id` still reads `uninitialized`, so the first boot will be detected |
| `deploy/tests/esp-bootc-integration.sh` | `fenoa` | real `bootc install to-filesystem` over a fake Asahi ESP; the preboot layer survives |
| `images/fairydust/hack/smoke.sh` | `fenoa-fairydust` | kernel swap, DP alt-mode and GPU drivers, PE vmlinuz, DTBs under `dtb/apple/`, rebuilt initramfs |

`publish.yml` only runs after this workflow has passed for a push to `main` (or its weekly run), builds that exact commit, and repeats the smoke tests on its own build before it pushes anything.

## 3. Hardware: `images/boottest/`

The Asahi kernels only boot on Apple Silicon, so boot-time behaviour is checked on a Mac:

```sh
podman build -t fenoa:44-boottest --build-arg BASE=fenoa:44 -f images/boottest/Containerfile .
# deploy it (bootc switch to a pushed tag, or deploy/fenoa-install), reboot twice, then:
journalctl -u fenoa-boottest
```

`boot-smoke.sh` checks the running kernel and GPU render node, systemd-boot on the located ESP with no GRUB, the m1n1 stamp, services (greetd, NetworkManager, speakersafetyd…), zram, failed units, the greeter process and state directory, SELinux denials for greetd/noctalia-greeter, `hid_apple fnmode`, the trackpad, and first-boot provisioning (including a machine ID committed in place of `uninitialized`, and the provisioning timers enabled).

Hardware-only by nature: the tty1 first-boot prompts (systemd-firstboot's locale, keymap and timezone, then fenoa-firstboot-user's account), the greeter handoff into Hyprland, the m1n1 two-reboot flow, DP alt-mode, and anything SELinux only denies at runtime.
