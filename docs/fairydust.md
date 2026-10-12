# The fairydust variant

`ghcr.io/olirafa/fenoa-fairydust` is `fenoa` with the stock Asahi `kernel-16k` swapped for the experimental **fairydust** kernel: AsahiLinux/linux's `fairydust` branch, which adds USB-C DisplayPort alt-mode output on Apple Silicon MacBooks. It is the only kernel line with DP alt-mode; stable `linux-asahi` has none.

## Where the kernel comes from

The kernel is not compiled here. It is built in [OliRafa/omarchy-fairydust-kernel](https://github.com/OliRafa/omarchy-fairydust-kernel) and published as `ghcr.io/olirafa/omarchy-fairydust-kernel:{latest,44}`, a `FROM scratch` context image holding only:

- `/usr/lib/modules/<kver>/` — `vmlinuz` (the EFI-ZBOOT PE image systemd-boot needs), `config`, `System.map`, stripped modules, and Apple DTBs under `dtb/apple/`
- `/usr/lib/modules/fairydust.kver` — the version string

Its config is seeded from Fedora's `kernel-16k` config (16K pages) plus the fairydust deltas; the image label `dev.omarchy.fairydust.revision` records the branch commit. The kernel repo rebuilds only when the branch moves. Pin a specific build with `FDK_IMAGE=ghcr.io/olirafa/omarchy-fairydust-kernel:<tag> ./images/build.sh fairydust`.

## What the swap does

`images/fairydust/Containerfile`:

1. Copies the kernel tree in, removes the `kernel-16k*` RPMs and every other kernel tree, runs `depmod`, and fails unless exactly one kernel remains.
2. Rebuilds the initramfs exactly like the platform stage's step P5 — bootc's composefs pivot plus the Apple HID drivers. Without it the boot entry would carry the stock kernel's initramfs, which this image deleted.
3. Lints.

The m1n1 wiring needs no change: `DTBS=/usr/lib/modules/$(uname -r)/dtb` follows whatever kernel is running.

## Things that bite

- **DTB layout.** `update-m1n1` globs `$DTBS/apple/t*.dtb`. A kernel image with flat `dtb/*.dtb` makes it find nothing; `fenoa-apply-m1n1` then fails and the fairydust devicetree (the part that switches DP alt-mode on) never applies, while everything else boots fine on the old one. `images/fairydust/hack/smoke.sh` asserts `dtb/apple/`.
- **Two reboots.** The first boot onto the fairydust kernel refreshes `boot.bin`; DP alt-mode only works from the second.
- **GPU driver.** A kernel built without `drm_asahi` (`asahi.ko`) renders the whole desktop on llvmpipe: laggy cursor, dropped frames. Some Asahi branches mark the driver `BROKEN`, which silently drops it from `olddefconfig`. The smoke test asserts the module is present, and the boot test asserts a GPU render node exists.
- **Hotplug.** On the 7.1 fairydust kernels, a cold boot with the monitor attached works while re-plugging can fail, notably through active USB-C→DP adapters (VIA Labs converters) that negotiate USB3+DP mode. A passive USB-C (DP Alt Mode) → DisplayPort cable avoids the affected path.

## Verifying

DP alt-mode itself can only be checked on hardware: deploy the image (or its boot-test overlay), reboot twice, connect a display. `journalctl -k | grep -i dptx` shows the link coming up; `hyprctl monitors` should list the external output.
