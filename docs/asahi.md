# Apple Silicon platform notes

What Fenoa does specifically for Fedora Asahi Remix on Apple Silicon, and why. Most of the hardware enablement (kernel, firmware, audio DSP, Touch Bar, m1n1/U-Boot) comes from the `quay.io/fedora-asahi-remix-atomic-desktops/base-atomic` image; this page covers what Fenoa adds or changes on top. The boot chain and the install itself are in [`deploy/README.md`](../deploy/README.md).

## Bootloader: systemd-boot on composefs

The image ships systemd-boot instead of GRUB, installed with `bootc install --composefs-backend --bootloader systemd`. On Asahi the chain is `m1n1 → U-Boot (UEFI) → /EFI/BOOT/BOOTAA64.EFI → kernel`, and the devicetree comes from m1n1, so the bootloader never manages it.

- `rpm-ostree`, `bootupd` and the GRUB EFI binaries are removed where nothing holds them. `asahi-platform-metapackage` keeps `grub2-common`, so its boot-success units are masked; under systemd-boot they fail on every login otherwise.
- The base image's initramfs is built for the ostree backend. A composefs install writes `composefs=<digest>` onto the kernel command line, which nothing in that initramfs reads, so the machine boots the image's kernel against whatever `/usr` is on disk and lands in emergency mode. Step P5 of `images/fenoa/Containerfile` rebuilds the initramfs with bootc's `bootc` dracut module and fails the build without `bootc-root-setup.service`. This only fails on hardware; the install succeeds either way.

## m1n1 and the devicetree on an atomic system

On mutable Asahi, `update-m1n1` rewrites `<ESP>/m1n1/boot.bin` (m1n1 stage 2 + U-Boot + devicetree) on kernel updates. On bootc nothing does, and by default it reads the static devicetree in `/boot` rather than the one in the image. A kernel with a changed devicetree (the 6.19 USB change, or the fairydust DP alt-mode nodes) then boots against a stale one and hardware breaks.

- Build time: `DTBS` in `/etc/sysconfig/update-m1n1` points at `/usr/lib/modules/$(uname -r)/dtb`. `update-m1n1` globs `$DTBS/apple/t*.dtb`, so a kernel must install its DTBs under `dtb/apple/`.
- Run time: `fenoa-apply-m1n1.service` runs `update-m1n1` once per kernel, and only on a boot that came through m1n1: it is conditioned on `/proc/device-tree/chosen/asahi,efi-system-partition`, the devicetree property m1n1 sets and `update-m1n1` finds the ESP by (`update-m1n1` itself ships in every image, so its presence proves nothing). Every file in a composefs deployment has mtime 0 and GNU gzip exits 2 on that, killing `update-m1n1` under `set -e`; the helper bind-mounts a copy of the U-Boot blob with a real mtime over the original inside a private mount namespace.
- Two reboots are inherent: the first lands on the new kernel and refreshes `boot.bin`, the second boots with the new devicetree. Set `FENOA_M1N1_AUTOREBOOT=1` in `/etc/default/fenoa-m1n1` to take the second one automatically. `FENOA_FWEXTRACT=1` also refreshes `vendorfw` via `asahi-fwupdate` (off by default; it rarely changes).

## Keyboard and trackpad

- **Trackpad dead after some boots.** The internal keyboard and trackpad (SPI devices on M1 13" laptops — "Apple SPI Keyboard/Trackpad"; DockChannel MTP devices on M2 and later — "Apple MTP keyboard/multi-touch") first bind to `hid-generic`, then get re-created when `hid_apple` / `hid_magicmouse` load from the root filesystem. That reshuffles `/dev/input/eventN` while logind and the compositor are starting; logind's TakeDevice fails ("Could not take device: No such file or directory"), libinput never retries, and the trackpad stays dead for the session. `/usr/lib/dracut/dracut.conf.d/90-fenoa-apple-hid.conf` loads both drivers from the initramfs so the devices exist before userspace starts. `hid-magicmouse` is built into both the stock and fairydust kernels while `hid-apple` is a module; the build checks accept either. Live recovery without a reboot: `sudo udevadm trigger --action=add /dev/input/eventN`.
- **Keyboard layout.** Hyprland takes its layout from the system: `XKBLAYOUT`/`XKBVARIANT`/`XKBOPTIONS` in `/etc/vconsole.conf` (set with `localectl set-x11-keymap`), otherwise the console `KEYMAP` that `systemd-firstboot` asked for, mapped through systemd's `kbd-model-map`. A non-Latin layout is never first, or Hyprland's letter bindings would stop matching.
- **Function row.** `/usr/lib/modprobe.d/fenoa-apple.conf` sets `hid_apple fnmode=1`: the top row sends brightness/volume/media keys and F1–F12 need Fn, like macOS. It has to be in the initramfs too, since that is where `hid_apple` now loads.
- **Keyboard backlight.** Apple's top row has no keyboard-backlight keys, so the desktop binds Shift+brightness to `fenoa-kbd-backlight`, which steps `*kbd_backlight*` with `brightnessctl`.
- **Touch Bar.** `tiny-dfr` (from the base image) drives the function row on 13" M1/M2 MacBook Pros. Display backlight selection must skip `appletb_backlight`, which is the Touch Bar's.
- **Lid switch.** Apple Silicon reports the lid as the input switch `Apple SMC power/lid events`, not `Lid Switch`, so compositor bindings for the generic name never fire.

## Display

- **Notch.** Fenoa leaves the Asahi default: the area beside the notch is not part of the framebuffer, so nothing can be hidden behind it. `options appledrm show_notch=1` would expose the full panel height, but then the bar has to be exactly as tall as the cutout on each model (14"/16" Pro: 64 physical rows; 13.6"/15" Air: 56) and must keep its centre clear. Revisit if the bar ever learns to size itself to the notch.
- **Direct scanout** is disabled in Hyprland (`render.direct_scanout = 0`) to avoid fullscreen artifacts seen on Asahi.
- **Screen recording.** gpu-screen-recorder fails on the Asahi GPU ("unknown gpu vendor: Mesa"); the image ships `wf-recorder` instead, and OBS Studio is installed as a Flatpak on first boot.

## Audio

The speakers' DSP comes from `asahi-audio` (PipeWire filter chains with the bankstown/triforce LV2 plugins) and `speakersafetyd`, which must be running or the kernel keeps the speakers muted. Both ship in the base image; Fenoa adds no audio tuning of its own and must not run a second DSP (EasyEffects) on the speaker sink.

## DRM (Widevine)

Google serves no arm64 Widevine CDM to the Chromium component updater, so enabling DRM in a browser fetches nothing on aarch64. `fenoa-widevine` runs Fedora Asahi's `widevine-installer` (ChromeOS LaCrOS image → arm64 CDM in `/var/lib/widevine`, persistent on bootc) and copies the CDM into each Chromium-family Flatpak's own profile, because the sandbox cannot see `/var/lib/widevine`. The hint file must use the canonical `/var/home/<user>/...` path the sandbox resolves; a `/home/...` path makes the browser log "Widevine enabled but no library found". Brave additionally needs its `brave.widevine_opted_in` pref. Run `fenoa-widevine` once after the browser's first start, and `fenoa-widevine --wire-only` to re-wire after a browser profile is recreated.

## Power and storage tuning

- zram sized to RAM with zstd, sysctls tuned for swap on zram (swappiness 150, page-cluster 0), zswap disabled so pages are not compressed twice.
- Kyber I/O scheduler on whole disks to keep interactive reads flowing under write floods.
- systemd-oomd acts on memory pressure, and only user apps (`app.slice`) are kill candidates, so the compositor and shell survive.
- Wi-Fi power save off (`brcmfmac` latency spikes and link drops).
- `InhibitDelayMaxSec=15` gives the lock screen time to engage before suspend when closing the lid also reconfigures displays.
- The power key is handed to the compositor (`HandlePowerKey=ignore`), which opens the session menu.

## Not done (and why)

- **USB autosuspend.** `usbcore` is built into the Asahi kernels, so `options usbcore autosuspend=-1` in `modprobe.d` does nothing; it would need the kernel argument `usbcore.autosuspend=-1` via `/usr/lib/bootc/kargs.d/`, at a battery cost. Not shipped.
- **Battery charge limits.** The `macsmc` battery exposes `charge_control_end_threshold`, but nothing sets it; set it by hand (or a udev rule) if you want one.
