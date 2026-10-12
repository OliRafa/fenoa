# Fenoa

Fenoa (Fedora Noctalia Atomic) is a bootc image for Apple Silicon Macs: Fedora Asahi Remix atomic + systemd-boot + composefs, with a Hyprland + Noctalia desktop and noctalia-greeter on greetd. An optional variant swaps in the fairydust kernel for USB-C DisplayPort alt-mode.

## Layout

- `images/fenoa/Containerfile` - two stages: `platform` (Fedora Asahi + bootc plumbing, no desktop) and the final desktop stage
- `images/fairydust/Containerfile` - `FROM fenoa`; swaps the stock `kernel-16k` for the fairydust kernel and rebuilds the initramfs
- `images/boottest/` - on-hardware boot smoke overlay (never published)
- `images/*/hack/` - container smoke tests and the install-to-disk check CI runs against built images
- `packages/platform.packages`, `packages/desktop.packages` - the dnf package sets, one per stage
- `system/platform/`, `system/desktop/` - file overlays copied to `/` by the matching stage
- `deploy/` - `fenoa-install` (take over a running Fedora Asahi system) and `fenoa-grow-esp`, with their library and tests
- `test/` - `test/all` runs everything that needs no image build; unit tests live in `test/unit.d/*-test.sh`
- `docs/` - how the system is shaped and why; read the relevant page before changing an area

## Where things go

- Platform vs desktop: anything a non-graphical Fedora Asahi bootc install needs (boot, firmware, drivers, system services, provisioning) belongs to the platform stage; anything that exists for the Hyprland/Noctalia session belongs to the desktop stage.
- Prefer vendor drop-in paths under `/usr/lib` (`systemd/*.conf.d`, `sysctl.d`, `udev/rules.d`, `modprobe.d`, `tmpfiles.d`, `NetworkManager/conf.d`, `polkit-1` rules under `/usr/share`) so image updates flow through without `/etc` three-way-merge conflicts. Use `/etc` only for files whose consumer reads nothing else (sudoers, docker, greetd).
- A unit a Containerfile enables or disables (or makes the default target) also needs a matching `enable`/`disable` line in that stage's preset file (`system/platform/usr/lib/systemd/system-preset/50-fenoa.preset`, `system/desktop/.../50-fenoa-desktop.preset`): a first boot runs a full preset pass and Fedora's `99-default-disable.preset` turns off everything unlisted.
- Anything the initramfs needs (`modprobe.d`, `dracut.conf.d`) must be in the image before the initramfs rebuild step. `images/fairydust/Containerfile` rebuilds it again for its kernel.
- `/var` is seeded only on first boot and never updated by `bootc upgrade`. Never bake state into `/var`; ship a `tmpfiles.d` entry or a first-boot unit instead.
- Desktop defaults live in `/usr/share/fenoa/` and are pulled in from the user's config (`~/.config/hypr/hyprland.lua` loads them, `~/.config/noctalia/config.toml` includes them), so updating the image updates the defaults without rewriting user files. `/etc/skel` only seeds those thin user files.
- New system packages go in the matching `packages/*.packages` list with Fedora names. Check they resolve on Fedora 44 aarch64 before committing.

## Style

- In markdown documents, write full lines; break only at structural boundaries like headings and list items
- Two spaces for indentation, no tabs
- Shebangs are `#!/bin/bash`; files that are only sourced (profile.d, `deploy/lib`) need none
- Use bash 5 conditionals: `[[ ]]` for string/file tests and `(( ))` for numeric tests
- In `[[ ]]`, don't quote variables, but do quote string literals when comparing values (e.g. `[[ $mode == "dark" ]]`)
- Prefer `(( count < 50 ))` over `[[ $count -lt 50 ]]`
- Prefer a full `if`/`else` for simple two-path control flow
- Quote paths with spaces instead of escaping them
- Smoke tests never pipe into `grep -q` under `pipefail` (the early exit SIGPIPEs the producer and reports failure on a match); capture output first and match in the shell
- Comments explain why, especially for anything that only fails on real hardware

## Tests

Run from the repo root before calling work done:

```bash
./test/all
```

That covers shell syntax, `test/unit.d`, and the `deploy/` library tests. The image tests need a built image and run in `.github/workflows/image-e2e.yml` on an arm64 runner; locally (aarch64, ~20 GB free):

```bash
./images/build.sh fenoa
./images/fenoa/hack/platform-smoke.sh fenoa:44
./images/fenoa/hack/desktop-smoke.sh fenoa:44
DESKTOP=1 ./images/fenoa/hack/first-boot.sh fenoa:44
```

The desktop config can be checked without an image: `test/unit.d/desktop-config-test.sh` runs `Hyprland --verify-config` against the shipped Lua when Hyprland is installed.

Hardware-only behaviour (boot, m1n1 refresh, greeter, DP alt-mode) is verified with `images/boottest/` on a real Mac.

## Multi-agent loop

For substantive changes (boot chain, initramfs, first-boot, greeter/PAM, security), use a SWE → QA → Review loop with the main session as orchestrator:

- SWE implements; one writer at a time on a branch
- QA runs `./test/all` (and the image tests when the image changes) and reports `VERDICT: PASS` or `VERDICT: FAIL` with output; QA never fixes
- Reviewer reviews the diff; severity `bug` blocks, `suggestion`/`nit` are optional
- Max three SWE↔QA rounds, then surface the remaining issues to the user

## Git

- Commits are atomic: one coherent change per commit
- Commit messages are succinct and describe the change
