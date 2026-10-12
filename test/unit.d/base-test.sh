#!/bin/bash

# Shared helpers for test/unit.d/*-test.sh. Source it; don't run it.
#
#   pass DESC            prints "ok - DESC"
#   fail DESC [DETAIL]   prints DETAIL to stderr, then "not ok - DESC", and exits 1 — the first
#                        failed assertion ends the file (test/unit keeps going with the next file)
#   require_command CMD  fails unless CMD is on PATH
#
# Stub commands by writing executables into a temp dir and putting it first on PATH.

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  echo "source test/unit.d/base-test.sh from a unit test; do not run it directly" >&2
  exit 1
fi

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
export ROOT

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  local description="$1"
  local detail="${2:-}"

  [[ -n $detail ]] && printf '%s\n' "$detail" >&2
  printf 'not ok - %s\n' "$description" >&2
  exit 1
}

require_command() {
  local command="$1"

  command -v "$command" >/dev/null || fail "required command is available: $command"
}
