# Fenoa

**Fe**dora **No**ctalia **A**tomic — a bootc image for Apple Silicon Macs.

Fenoa layers a Hyprland + Noctalia desktop onto Fedora Asahi Remix's atomic base, booted through systemd-boot on bootc's composefs backend, with an optional variant that swaps in the fairydust kernel for USB-C DisplayPort alt-mode.

This commit introduces the **platform layer**: everything Apple Silicon needs to run Fedora Asahi as a bootc OS, with no desktop yet.

- systemd-boot instead of GRUB, and an initramfs rebuilt so composefs installs actually pivot to the deployed `/usr`
- m1n1 + devicetree refresh after image updates (`fenoa-apply-m1n1.service`)
- first-boot primary user creation (`fenoa-firstboot-user.service`)
- Flatpak (`flatpak preinstall`) and Homebrew (ublue's prebuilt brew) provisioning
- Apple HID fixes baked into the initramfs (trackpad boot race, `hid_apple fnmode=1`)
- system tuning: zram, sysctl, kyber I/O scheduler, systemd-oomd, logind, Wi-Fi power save
- Widevine CDM provisioning for Flatpak browsers on aarch64 (`fenoa-widevine`)
- `deploy/fenoa-install` to take over a running Fedora Asahi system, growing the ESP as needed

See [`docs/asahi.md`](docs/asahi.md) for the platform decisions and [`deploy/README.md`](deploy/README.md) for installing.

## Build

On an aarch64 host:

```sh
./images/build.sh platform
./images/fenoa/hack/platform-smoke.sh fenoa-platform:44
```

## Tests

```sh
./test/all
```
