#!/bin/bash

# images/publish-index.sh points fenoa:TAG and :latest at a multi-arch index of the two streams'
# per-arch images (main: TAG-amd64, asahi: TAG-arm64). Every machine pulls fenoa:TAG, so an index
# that drops an architecture stops that architecture's upgrades: an arch with no tag of its own must
# keep what fenoa:TAG served it before, and a registry error must publish nothing.
#
# skopeo and podman are stubbed through PATH; the stub registry is a directory holding each ref's
# raw manifest (REF.raw), and for a single image its architecture (REF.arch) and digest (REF.digest).
# A ref without a .raw file is a missing tag; REF.error makes skopeo fail on it with that message.

source "$(dirname "$0")/base-test.sh"
require_command jq

script="$ROOT/images/publish-index.sh"
[[ -x $script ]] || fail "images/publish-index.sh is executable"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"
export MOCK_REG="$test_tmp/reg" MOCK_LOG="$test_tmp/mock.log"

cat >"$mock_bin/skopeo" <<'SH'
#!/bin/bash
ref=${*: -1}
ref=${ref#docker://}
key="$MOCK_REG/${ref//\//_}"
if [[ -f $key.error ]]; then cat "$key.error" >&2; exit 1; fi
if [[ ! -f $key.raw ]]; then echo "reading manifest $ref: manifest unknown" >&2; exit 1; fi
case "$*" in
  *--raw*) cat "$key.raw" ;;
  *Architecture*) cat "$key.arch" ;;
  *Digest*) cat "$key.digest" ;;
  *) exit 2 ;;
esac
SH
cat >"$mock_bin/podman" <<'SH'
#!/bin/bash
printf 'podman %s\n' "$*" >>"$MOCK_LOG"
args=("$@")
for i in "${!args[@]}"; do
  [[ ${args[i]} == "--digestfile" ]] && echo "sha256:index" >"${args[i+1]}"
done
exit 0
SH
chmod +x "$mock_bin/skopeo" "$mock_bin/podman"

repo=ghcr.io/o/fenoa
key() { printf '%s/%s' "$MOCK_REG" "${1//\//_}"; }
image() {  # image REF ARCH DIGEST: a single-arch image at REF
  printf '{"schemaVersion":2,"config":{}}\n' >"$(key "$1").raw"
  printf '%s\n' "$2" >"$(key "$1").arch"
  printf '%s\n' "$3" >"$(key "$1").digest"
}
index() {  # index REF ARCH=DIGEST...: an index at REF
  local entries=() pair
  for pair in "${@:2}"; do
    entries+=("{\"digest\":\"${pair#*=}\",\"platform\":{\"os\":\"linux\",\"architecture\":\"${pair%%=*}\"}}")
  done
  printf '{"schemaVersion":2,"manifests":[%s]}\n' "$(IFS=,; echo "${entries[*]}")" >"$(key "$1").raw"
}
reset() { rm -rf "$MOCK_REG" "$MOCK_LOG" "$test_tmp/digest"; mkdir -p "$MOCK_REG"; : >"$MOCK_LOG"; }
run() { PATH="$mock_bin:$PATH" "$script" "$repo" 44 "$test_tmp/digest" >"$test_tmp/out" 2>&1; }
added() { grep -oE 'manifest add [^ ]+ [^ ]+' "$MOCK_LOG" | awk '{print $4}' | sort | tr '\n' ' '; }

# 1) The transition: fenoa:44 is still the single-arch Apple Silicon image and main publishes the
#    first amd64 image. The index keeps the arm64 image by digest and adds the new amd64 tag.
reset
image "$repo:44" arm64 sha256:mac
image "$repo:44-amd64" amd64 sha256:pc
run || fail "the first amd64 publish succeeds" "$(cat "$test_tmp/out")"
[[ $(added) == "docker://$repo:44-amd64 docker://$repo@sha256:mac " ]] ||
  fail "the first amd64 publish keeps the single-arch arm64 image" "$(added)"
grep -qE "^podman manifest push --all --digestfile $test_tmp/digest fenoa-index-[0-9]+ docker://$repo:44$" "$MOCK_LOG" ||
  fail "the index is pushed to :44 with its digest recorded" "$(cat "$MOCK_LOG")"
grep -qE "^podman manifest push --all fenoa-index-[0-9]+ docker://$repo:latest$" "$MOCK_LOG" ||
  fail "the index is pushed to :latest too" "$(cat "$MOCK_LOG")"
[[ $(<"$test_tmp/digest") == "sha256:index" ]] || fail "the digest file holds the index digest"
pass "the first publish of one stream keeps the other stream's single-arch image"

# 2) Both streams have published: their own tags, whatever fenoa:44 held before.
reset
index "$repo:44" amd64=sha256:oldpc arm64=sha256:oldmac
image "$repo:44-amd64" amd64 sha256:pc
image "$repo:44-arm64" arm64 sha256:mac
run || fail "a publish with both arch tags succeeds" "$(cat "$test_tmp/out")"
[[ $(added) == "docker://$repo:44-amd64 docker://$repo:44-arm64 " ]] ||
  fail "both arch tags are listed" "$(added)"
pass "with both arch tags present, the index lists exactly them"

# 3) fenoa:44 is already an index, and only one stream has its tag (say a tag was deleted): the
#    other architecture comes from the current index, by digest.
reset
index "$repo:44" amd64=sha256:oldpc arm64=sha256:oldmac
image "$repo:44-arm64" arm64 sha256:mac
run || fail "a publish with one arch tag over an index succeeds" "$(cat "$test_tmp/out")"
[[ $(added) == "docker://$repo:44-arm64 docker://$repo@sha256:oldpc " ]] ||
  fail "the amd64 image is kept from the current index" "$(added)"
pass "an architecture without its tag keeps its image from the current index"

# 4) A single-arch fenoa:44 of the other architecture is not carried into a slot it does not fit.
reset
image "$repo:44" amd64 sha256:pc
image "$repo:44-amd64" amd64 sha256:pc2
run || fail "a publish over a single-arch image of the same arch succeeds" "$(cat "$test_tmp/out")"
[[ $(added) == "docker://$repo:44-amd64 " ]] || fail "only the amd64 tag is listed" "$(added)"
pass "a single-arch fenoa:44 is kept only for its own architecture"

# 5) Nothing to list: fail, push nothing.
reset
if run; then fail "an empty registry is an error"; fi
grep -q 'manifest push' "$MOCK_LOG" && fail "nothing is pushed when there is no image" "$(cat "$MOCK_LOG")"
pass "with no image at all it fails and pushes nothing"

# 6) A registry error is not a missing tag: abort before touching the index, or the index would go
#    out without that architecture.
reset
image "$repo:44" arm64 sha256:mac
image "$repo:44-amd64" amd64 sha256:pc
echo "reading manifest: 503 Service Unavailable" >"$(key "$repo:44-arm64").error"
if run; then fail "a registry error aborts the publish" "$(cat "$test_tmp/out")"; fi
grep -q 'manifest push' "$MOCK_LOG" && fail "nothing is pushed after a registry error" "$(cat "$MOCK_LOG")"
grep -q '503' "$test_tmp/out" || fail "the registry error is reported" "$(cat "$test_tmp/out")"
pass "a registry error (anything but manifest unknown) aborts without pushing"

# Usage.
if PATH="$mock_bin:$PATH" "$script" "$repo" >/dev/null 2>&1; then fail "a missing TAG is a usage error"; fi
pass "it needs a repo and a tag"
