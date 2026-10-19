#!/bin/bash
# Build a Fenoa bootc image for x86_64. Run on an x86_64 host or CI runner: the build always targets
# linux/amd64, so elsewhere it runs under emulation (slow, and rpm fails under qemu-user on 16K-page
# hosts such as Apple Silicon). Apple Silicon's image is built from the asahi branch.
#
#   ./images/build.sh platform    # -> fenoa-platform:$FEDORA (the platform stage only; local/CI)
#   ./images/build.sh fenoa       # -> fenoa:$FEDORA (platform + desktop)
#
#   ENGINE=podman FEDORA=44 ./images/build.sh fenoa
set -euo pipefail

TARGET="${1:-fenoa}"
FEDORA="${FEDORA:-44}"
ENGINE="${ENGINE:-podman}"
PLATFORM=linux/amd64
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

case "$TARGET" in
  platform)
    TAG="${TAG:-fenoa-platform:$FEDORA}"
    echo "==> $ENGINE build $TAG (platform stage, Fedora $FEDORA, $PLATFORM)"
    exec "$ENGINE" build \
      -f "$REPO_ROOT/images/fenoa/Containerfile" \
      --platform "$PLATFORM" \
      --target platform \
      --build-arg FEDORA="$FEDORA" \
      -t "$TAG" "$REPO_ROOT"
    ;;
  fenoa)
    TAG="${TAG:-fenoa:$FEDORA}"
    echo "==> $ENGINE build $TAG (platform + desktop, Fedora $FEDORA, $PLATFORM)"
    exec "$ENGINE" build \
      -f "$REPO_ROOT/images/fenoa/Containerfile" \
      --platform "$PLATFORM" \
      --build-arg FEDORA="$FEDORA" \
      -t "$TAG" "$REPO_ROOT"
    ;;
  *)
    echo "usage: $0 [platform|fenoa]" >&2
    exit 2
    ;;
esac
