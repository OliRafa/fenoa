#!/bin/bash

# Shared helpers for test/unit.d/*-test.sh. Source it; don't run it.
#
#   pass DESC            prints "ok - DESC"
#   fail DESC [DETAIL]   prints DETAIL to stderr, then "not ok - DESC", and exits 1 — the first
#                        failed assertion ends the file (test/unit keeps going with the next file)
#   require_command CMD  fails unless CMD is on PATH
#   containerfile_units VERB < TEXT
#                        the units a Containerfile (stage) passes to `systemctl VERB`, one per line
#   check_machine_id_last STAGE_NAME STAGE_TEXT
#                        fails unless the stage writes /etc/machine-id as "uninitialized" after its
#                        last package install
#   check_preset PRESET STAGE_TEXT [INSTALLED_NAME]
#                        fails unless PRESET covers every unit STAGE_TEXT enables, disables or makes
#                        the default target, and is shaped and named so systemd reads it first
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

containerfile_units() {
  local verb="$1"

  # Comments out, continued lines joined, then the unit names after `systemctl VERB` (so neither
  # `systemctl mask` nor `systemctl --global ...` counts).
  sed -e '/^[[:space:]]*#/d' |
    sed -e ':a' -e '/\\$/N; s/\\\n//; ta' |
    grep -oE "systemctl $verb [^;&|]*" |
    tr ' ' '\n' |
    grep -E '^[A-Za-z0-9@._-]+\.(service|socket|timer|target|path|mount)$' |
    sort -u
}

# A first boot runs a FULL preset pass and Fedora's 99-default-disable.preset disables whatever no
# preset lists, so every unit an image enables (or makes the default target) needs an `enable`
# line, and every unit it disables a `disable` line, in a preset systemd reads before Fedora's.
check_preset() {
  local preset="$1" text="$2" name="${3:-$(basename "$1")}" bad dupes unit

  [[ -f $preset ]] || fail "$name ships"
  bad=$(grep -vE '^[[:space:]]*(#.*)?$' "$preset" | grep -vE '^(enable|disable) [A-Za-z0-9@._-]+$' || true)
  [[ -z $bad ]] || fail "$name holds only 'enable UNIT' / 'disable UNIT' lines" "$bad"
  [[ $name == *.preset && $name < "81-" ]] || fail "$name sorts before Fedora's preset files (81- and up)"
  dupes=$(awk '$1 == "enable" || $1 == "disable" { print $2 }' "$preset" | sort | uniq -d)
  [[ -z $dupes ]] || fail "$name lists each unit once" "$dupes"

  while read -r unit; do
    [[ -z $unit ]] || grep -qx "enable $unit" "$preset" ||
      fail "$name enables $unit, which the Containerfile enables (or makes the default target)"
  done < <(printf '%s\n' "$text" | containerfile_units enable; printf '%s\n' "$text" | containerfile_units set-default)
  while read -r unit; do
    [[ -z $unit ]] || grep -qx "disable $unit" "$preset" ||
      fail "$name disables $unit, which the Containerfile disables"
  done < <(printf '%s\n' "$text" | containerfile_units disable)
}

# systemd detects a first boot (and runs systemd-firstboot and the preset pass) only when
# /etc/machine-id is absent or reads "uninitialized"; an empty file does not count. Anything a
# package install runs could write a real ID, so the write has to come after the stage's last
# package install.
check_machine_id_last() {
  local stage="$1" text="$2" write install

  write=$(printf '%s\n' "$text" | grep -nF -- "printf 'uninitialized\\n' >/etc/machine-id" | tail -1 | cut -d: -f1)
  install=$(printf '%s\n' "$text" | grep -nE 'dnf -y install' | tail -1 | cut -d: -f1)
  [[ -n $write ]] || fail "the $stage stage ships /etc/machine-id as uninitialized"
  (( write > ${install:-0} )) ||
    fail "the $stage stage writes /etc/machine-id after its last package install" "write at $write, dnf install at $install"
}
