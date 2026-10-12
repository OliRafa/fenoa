# Testing

Three tiers, from cheapest to most faithful.

## 1. No image: `./test/all`

Runs anywhere (CI: `.github/workflows/tests.yml` on ubuntu, plus shellcheck at error level).

- `bash -n` on every shell script (`test/shell-files` lists them: `*.sh` plus anything with a `#!/bin/bash` shebang)
- `test/unit` — every `test/unit.d/*-test.sh`, hermetic, stubbing commands through `PATH`:
  - `apply-m1n1-test.sh` — the zero-mtime gzip workaround in `fenoa-apply-m1n1`
  - `firstboot-user-test.sh` — unit gating, the DynamicUser UID trap, marker/preseed handling
  - `brew-setup-test.sh` — primary-user detection, empty-prefix debris, no network
  - `flatpak-provisioning-test.sh` — preinstall/update units and their build wiring
  - `widevine-test.sh` — CDM wiring into Flatpak profiles, the canonical-path hint, Brave's opt-in
  - `platform-overlay-test.sh` — Apple HID drop-ins reach the initramfs step, enabled units ship, no Omarchy leftovers, shebangs
  - `desktop-config-test.sh` — config parsing and cross-file agreement (greetd ↔ tmpfiles ↔ greeter, skel ↔ defaults, bindings ↔ helpers, Flatpaks ↔ default apps); runs `Hyprland --verify-config` when Hyprland is installed
  - `desktop-helpers-test.sh` — `fenoa-kbd-backlight` and `fenoa-hypr-clamshell`
- `deploy/tests/*.test.sh` — the ESP backup/restore, capacity, GPT absorb, boot-entry repair and BLS prune libraries

Unit tests source `test/unit.d/base-test.sh` (`pass`, `fail`, `require_command`). A file stops at its first failure; the runner keeps going and reports every failing file.

## 2. Built image: `images/*/hack/`

CI: `.github/workflows/image-e2e.yml` on `ubuntu-24.04-arm`, building with rootful podman because `bootc install` reads `/var/lib/containers`.

| Script | Against | Checks |
|---|---|---|
| `images/fenoa/hack/platform-smoke.sh` | platform stage, `fenoa`, `fenoa-fairydust` (`KERNEL=fairydust`) | Asahi base, one kernel, systemd-boot, masked grub units, initramfs (composefs pivot, Apple HID), m1n1 wiring, first-boot/Flatpak/brew units, services, tuning files, no Omarchy |
| `images/fenoa/hack/desktop-smoke.sh` | `fenoa`, `fenoa-fairydust` | packages, greetd as display manager, greeter account/PAM/state dir, the greeter finds its default session, polkit rule ↔ packaged action, `noctalia config validate` and `Hyprland --verify-config` on the seeded config, default apps |
| `images/fenoa/hack/first-boot.sh` | platform stage; `fenoa` with `DESKTOP=1` | preseeded user creation under a populated machine-id and a DynamicUser account, marker, scrubbing, idempotence, skel seeding, `systemd-analyze verify` |
| `images/fenoa/hack/install-to-disk.sh` | `fenoa` | real `bootc install to-disk --composefs-backend --bootloader systemd`, inspected by loop mount |
| `deploy/tests/esp-bootc-integration.sh` | `fenoa` | real `bootc install to-filesystem` over a fake Asahi ESP; the preboot layer survives |
| `images/fairydust/hack/smoke.sh` | `fenoa-fairydust` | kernel swap, DP alt-mode and GPU drivers, PE vmlinuz, DTBs under `dtb/apple/`, rebuilt initramfs |

`publish.yml` runs the smoke tests again before it pushes anything.

## 3. Hardware: `images/boottest/`

The Asahi kernels only boot on Apple Silicon, so boot-time behaviour is checked on a Mac:

```sh
podman build -t fenoa:44-boottest --build-arg BASE=fenoa:44 -f images/boottest/Containerfile .
# deploy it (bootc switch to a pushed tag, or deploy/fenoa-install), reboot twice, then:
journalctl -u fenoa-boottest
```

`boot-smoke.sh` checks the running kernel and GPU render node, systemd-boot on the located ESP with no GRUB, the m1n1 stamp, services (greetd, NetworkManager, speakersafetyd…), zram, failed units, the greeter process and state directory, SELinux denials for greetd/noctalia-greeter, `hid_apple fnmode`, the trackpad, and first-boot provisioning.

Hardware-only by nature: the tty1 first-boot prompt, the greeter handoff into Hyprland, the m1n1 two-reboot flow, DP alt-mode, and anything SELinux only denies at runtime.
