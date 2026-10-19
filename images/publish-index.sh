#!/bin/bash
# Point REPO:TAG and REPO:latest at a multi-arch index of the per-arch images the two Fenoa streams
# publish: main pushes REPO:TAG-amd64 (x86_64), the asahi branch REPO:TAG-arm64 (Apple Silicon).
# bootc on either machine pulls REPO:TAG and gets its own architecture's image.
#
# Each stream runs this after pushing its image (.github/workflows/publish.yml), so the index always
# lists the newest image of both. An architecture with no TAG-ARCH tag yet keeps the image REPO:TAG
# served it before: from the index, or from the single-arch image REPO:TAG was before the streams
# split. So the first publish of one stream never takes the other architecture away, and neither
# does a registry error: anything but "manifest unknown" aborts before the index is touched.
#
#   images/publish-index.sh ghcr.io/olirafa/fenoa 44 [DIGESTFILE]
#
# DIGESTFILE receives the index's digest, for signing. Needs skopeo, jq and podman, logged in to the
# registry.
set -euo pipefail

if (( $# < 2 )); then
  echo "usage: $0 REPO TAG [DIGESTFILE]" >&2
  exit 2
fi
repo=$1 tag=$2 digestfile=${3:-}
arches=(amd64 arm64)

errfile=$(mktemp)
list="fenoa-index-$$"
trap 'rm -f "$errfile"; podman manifest rm "$list" >/dev/null 2>&1 || true' EXIT

# raw_manifest REF: REF's raw manifest, or nothing when the registry has no such tag.
raw_manifest() {
  local out
  if out=$(skopeo inspect --raw "docker://$1" 2>"$errfile"); then
    printf '%s\n' "$out"
  elif [[ $(<"$errfile") != *"manifest unknown"* ]]; then
    echo "skopeo inspect $1: $(<"$errfile")" >&2
    return 1
  fi
}

# What REPO:TAG serves now: an index, a single image, or nothing yet.
current=$(raw_manifest "$repo:$tag")
current_arch="" current_digest=""
if [[ -n $current && $(jq -r 'has("manifests")' <<<"$current") == "false" ]]; then
  current_arch=$(skopeo inspect --format '{{.Architecture}}' "docker://$repo:$tag")
  current_digest=$(skopeo inspect --format '{{.Digest}}' "docker://$repo:$tag")
fi

refs=()
for arch in "${arches[@]}"; do
  own=$(raw_manifest "$repo:$tag-$arch")
  if [[ -n $own ]]; then
    refs+=("docker://$repo:$tag-$arch")
    echo "$arch: $repo:$tag-$arch"
  elif [[ -n $current_arch ]]; then
    if [[ $current_arch == "$arch" ]]; then
      refs+=("docker://$repo@$current_digest")
      echo "$arch: kept from the single-arch $repo:$tag ($current_digest)"
    fi
  elif [[ -n $current ]]; then
    digest=$(jq -r --arg a "$arch" \
      'first(.manifests[] | select(.platform.os == "linux" and .platform.architecture == $a) | .digest) // empty' <<<"$current")
    if [[ -n $digest ]]; then
      refs+=("docker://$repo@$digest")
      echo "$arch: kept from the current $repo:$tag index ($digest)"
    fi
  fi
done

if (( ${#refs[@]} == 0 )); then
  echo "no image to list: neither $repo:$tag-amd64 nor $repo:$tag-arm64 exists" >&2
  exit 1
fi

podman manifest rm "$list" >/dev/null 2>&1 || true
podman manifest create "$list" >/dev/null
for ref in "${refs[@]}"; do
  podman manifest add "$list" "$ref" >/dev/null
done
podman manifest push --all ${digestfile:+--digestfile "$digestfile"} "$list" "docker://$repo:$tag"
podman manifest push --all "$list" "docker://$repo:latest"
echo "$repo:$tag and $repo:latest list ${#refs[@]} image(s)"
