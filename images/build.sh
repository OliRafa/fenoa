#!/bin/bash
# Build a Fenoa bootc image. Run on a native aarch64 (Apple Silicon) host or an arm64 CI runner.
#
#   ./images/build.sh platform    # -> fenoa-platform:$FEDORA (the platform stage only; local/CI)
#   ./images/build.sh fenoa       # -> fenoa:$FEDORA (platform + desktop)
#   ./images/build.sh fairydust   # -> fenoa-fairydust:$FEDORA (FROM fenoa; fairydust kernel swap)
#
#   ENGINE=podman FEDORA=44 ./images/build.sh fenoa
#   FDK_IMAGE=ghcr.io/olirafa/omarchy-fairydust-kernel:44 ./images/build.sh fairydust
set -euo pipefail

TARGET="${1:-fenoa}"
FEDORA="${FEDORA:-44}"
ENGINE="${ENGINE:-podman}"
FDK_IMAGE="${FDK_IMAGE:-ghcr.io/olirafa/omarchy-fairydust-kernel:latest}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

case "$TARGET" in
  platform)
    TAG="${TAG:-fenoa-platform:$FEDORA}"
    echo "==> $ENGINE build $TAG (platform stage, Fedora $FEDORA)"
    exec "$ENGINE" build \
      -f "$REPO_ROOT/images/fenoa/Containerfile" \
      --target platform \
      --build-arg FEDORA="$FEDORA" \
      -t "$TAG" "$REPO_ROOT"
    ;;
  fenoa)
    TAG="${TAG:-fenoa:$FEDORA}"
    echo "==> $ENGINE build $TAG (platform + desktop, Fedora $FEDORA)"
    exec "$ENGINE" build \
      -f "$REPO_ROOT/images/fenoa/Containerfile" \
      --build-arg FEDORA="$FEDORA" \
      -t "$TAG" "$REPO_ROOT"
    ;;
  fairydust)
    TAG="${TAG:-fenoa-fairydust:$FEDORA}"
    echo "==> $ENGINE build $TAG (FROM fenoa:$FEDORA, kernel=$FDK_IMAGE)"
    exec "$ENGINE" build \
      -f "$REPO_ROOT/images/fairydust/Containerfile" \
      --build-arg TAG="$FEDORA" \
      --build-arg FDK_IMAGE="$FDK_IMAGE" \
      -t "$TAG" "$REPO_ROOT"
    ;;
  *)
    echo "usage: $0 [platform|fenoa|fairydust]" >&2
    exit 2
    ;;
esac
