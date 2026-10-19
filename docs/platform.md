# x86_64 platform notes

What Fenoa does specifically for x86_64 PCs, and why. The hardware enablement (kernel, linux-firmware, CPU microcode, Mesa, fwupd) comes from Fedora's `quay.io/fedora-ostree-desktops/base-atomic` image; this page covers what Fenoa adds or changes on top. Fenoa for Apple Silicon is built from the [`asahi` branch](https://github.com/OliRafa/fenoa/tree/asahi); both publish to the same multi-arch `ghcr.io/olirafa/fenoa:44`.

## Hardware

- **UEFI only.** systemd-boot is an EFI bootloader; a machine booting in legacy BIOS (CSM) mode cannot boot Fenoa.
- **Secure Boot off.** The image ships `systemd-boot-unsigned`, which no firmware key trusts, so the firmware refuses it while Secure Boot is on. Turn Secure Boot off in the firmware setup before installing. (A `bootc switch` from Fedora Atomic keeps that system's signed shim and GRUB, see below, and boots with Secure Boot on.)
- **Graphics: AMD and Intel.** Mesa's radeonsi/iris and the RADV/ANV Vulkan drivers; VA-API video decoding through Mesa (AMD) and `libva-intel-media-driver` (Intel). Fedora's Mesa leaves out H.264 and HEVC, so host apps such as mpv decode those in software; Flatpak apps such as the browser bring their own codecs. NVIDIA's proprietary driver is not in the image.
- **Firmware updates** come from LVFS through `fwupd` (`fwupdmgr refresh && fwupdmgr update`).

## Installing

Fenoa installs with bootc. Either way, the machine then follows `ghcr.io/olirafa/fenoa:44`, and `bootc upgrade` and `bootc rollback` work as usual.

### A fresh install (`bootc install to-disk`)

This erases the whole target disk. Boot any Linux live image that has podman (Fedora Workstation Live does), find the disk with `lsblk`, and run:

```sh
sudo podman run --rm --privileged --pid=host \
  --security-opt label=type:unconfined_t \
  -v /dev:/dev -v /var/lib/containers:/var/lib/containers \
  ghcr.io/olirafa/fenoa:44 \
  bootc install to-disk --composefs-backend --bootloader systemd --filesystem btrfs /dev/nvme0n1
```

A live session usually keeps `/var/lib/containers` in RAM and the image takes several GB there, so use a machine with plenty of memory or point podman's storage at another disk. The install writes systemd-boot to the ESP, including the fallback path `/EFI/BOOT/BOOTX64.EFI` that the firmware boots when no boot entry names another loader. CI runs the same install onto a disk image (`images/fenoa/hack/install-to-disk.sh`), with `--generic-image` so it leaves the runner's firmware variables alone; the firmware boot entry a real install adds is not tested there. Reboot into the installed system and the [first boot](../README.md#first-boot) takes over.

### From Fedora Atomic (`bootc switch`)

On Silverblue, Kinoite or another Fedora Atomic desktop:

```sh
sudo bootc switch ghcr.io/olirafa/fenoa:44
sudo reboot
```

The switch keeps that system's boot setup: its signed shim and GRUB on the ESP and the ostree backend, so Secure Boot can stay on. Fenoa's initramfs carries the ostree root pivot for this (step P5 of `images/fenoa/Containerfile`). The image ships no GRUB or bootupd of its own, so the GRUB on the ESP stays the one Fedora installed and is no longer updated. The users and the machine ID carry over too, so the first-boot prompts do not appear, and `rpm-ostree` is gone: `bootc` manages updates. This path is not covered by CI; if the new deployment does not come up, pick the previous one in the GRUB menu (or `sudo bootc rollback` from it).

A machine already on a composefs + systemd-boot bootc image switches the same way and keeps that layout.

## Bootloader: systemd-boot on composefs

The image ships systemd-boot instead of GRUB, installed with `bootc install --composefs-backend --bootloader systemd`. The chain is `UEFI firmware → systemd-boot → kernel + initramfs`.

- `rpm-ostree`, `bootupd`, GRUB and shim are removed (step P3). Fedora marks GRUB and shim as protected packages, so the removal clears dnf's protected list for that one command; nothing else needs them. Their boot-success units go with `grub2-common`; under systemd-boot they would fail on every login.
- The base image's initramfs is built for the ostree backend. A composefs install writes `composefs=<digest>` onto the kernel command line, which nothing in that initramfs reads, so the machine boots the image's kernel against whatever `/usr` is on disk and lands in emergency mode. Step P5 rebuilds the initramfs with bootc's `bootc` dracut module and ostree's `ostree` module (dracut includes neither unless asked), and fails the build without `bootc-root-setup.service` or `ostree-prepare-root.service`. Each runs only for its own kernel command line. This only fails on a real boot; the install succeeds either way.

## Keyboard layout

The login screen and Hyprland take their layout from the system through one resolver, `/usr/share/fenoa/hypr/fenoa/keyboard.lua`: `XKBLAYOUT`/`XKBVARIANT`/`XKBOPTIONS` in `/etc/vconsole.conf` (written by `localectl set-x11-keymap`, and by `systemd-firstboot` or `localectl set-keymap` when they can convert the console keymap), otherwise the console `KEYMAP` mapped through `kbd-model-map`. A non-Latin layout is never first, or Hyprland's letter bindings would stop matching, and X-only `terminate:*` options are dropped. greetd starts the greeter through `/usr/libexec/fenoa-greeter-session`, which runs that resolver with `lua` and hands the result over as `XKB_DEFAULT_*`; on its own noctalia-greeter would read `vconsole.conf` as written, so with a `ru` keymap it would start in Cyrillic (`ru,us`) while the session starts in `us,ru`. `systemd-firstboot` does not convert every console keymap it offers (on Fedora 44 `ua`, `bg-cp1251`, `kyrgyz` and `de_CH-latin1` come out with no XKB settings). So if `/etc/vconsole.conf` carries a console `KEYMAP` with no XKB settings that `kbd-model-map` cannot map either, `fenoa-firstboot-user` appends the XKB settings for the keymaps above and, for any other, warns at the password prompt that the login screen and desktop will use the US layout.

## Power and storage tuning

- zram sized to RAM with zstd, sysctls tuned for swap on zram (swappiness 150, page-cluster 0), zswap disabled so pages are not compressed twice.
- Kyber I/O scheduler on whole disks to keep interactive reads flowing under write floods.
- systemd-oomd acts on memory pressure, and only user apps (`app.slice`) are kill candidates, so the compositor and shell survive.
- `InhibitDelayMaxSec=15` gives the lock screen time to engage before suspend when closing the lid also reconfigures displays.
- The power key is handed to the compositor (`HandlePowerKey=ignore`), which opens the session menu.

## Not done (and why)

- **NVIDIA's proprietary driver.** It needs kernel modules built for each kernel (and signed, for Secure Boot); a separate image variant is the likely shape. Mesa's nouveau/NVK is in the image but untested.
- **Secure Boot for fresh installs.** systemd-boot and the kernel would have to be signed with keys the firmware trusts: a Fenoa key enrolled through shim's MOK, or the user's own keys in the firmware. A `bootc switch` from Fedora Atomic keeps Fedora's signed chain instead.
- **Legacy BIOS.** systemd-boot is EFI-only.
