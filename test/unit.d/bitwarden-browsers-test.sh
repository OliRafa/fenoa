#!/bin/bash

# fenoa-bitwarden-browsers connects the Bitwarden extension in the Flatpak browsers to the Bitwarden
# desktop app (a Flatpak too): Brave gets a manifest, two overrides and a socket symlink that
# Bitwarden cannot set up from its sandbox; Firefox the native-messaging directory Bitwarden writes
# into, and the same socket symlink and override. Exercised hermetically with fake Flatpak
# installations, a fake $HOME and a stub `flatpak`.
#
# What was found on hardware, and is pinned here:
#  - The proxy looks for the socket in $XDG_CACHE_HOME/com.bitwarden.desktop first, which inside a
#    browser is the browser's own cache: without the symlink there, Brave's finds nothing.
#  - Firefox's proxy otherwise uses the socket Bitwarden puts in Firefox's directory. The app numbers
#    clients per socket in one shared table, so with Brave connected too their ids collided and the
#    app dropped both connections every few seconds: every browser has to share one socket.
#  - Every path handed to the sandbox is the canonical /var/home/<user> one, not the /home symlink.
#  - The manifest runs desktop_proxy from current/active, so it follows Bitwarden's updates.
# And what review found: Brave's sandbox can rewrite everything under its directory, and the helper
# runs outside it. A Brave that swapped its cache for a symlink to ~/.var/app once had the helper
# delete Bitwarden's data; a burst of Flatpak changes stopped the path unit for the session.

source "$(dirname "$0")/base-test.sh"
require_command jq
require_command timeout

tool="$ROOT/system/desktop/usr/libexec/fenoa-bitwarden-browsers"
service="$ROOT/system/desktop/usr/lib/systemd/user/fenoa-bitwarden-browsers.service"
path_unit="$ROOT/system/desktop/usr/lib/systemd/user/fenoa-bitwarden-browsers.path"
policy="$ROOT/system/desktop/usr/share/polkit-1/actions/com.bitwarden.Bitwarden.policy"
containerfile="$ROOT/images/fenoa/Containerfile"
for f in "$tool" "$service" "$path_unit" "$policy"; do
  [[ -f $f ]] || fail "ships ${f#"$ROOT"/}"
done
pass "the helper, its service and path units, and Bitwarden's polkit action ship"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"
# `flatpak override --user` keeps each app's filesystems in $MOCK_OVERRIDES.<app-id>, one per line,
# and `--show` prints them the way flatpak does: a [Context] group with a ;-terminated list. Each
# --show is logged in $MOCK_SHOWS with its app; with $MOCK_CHANGE set, the first one touches that
# stamp, as an install landing while the helper runs would. As in flatpak, a path has one entry: adding
# it with another mode replaces the old one.
cat >"$mock_bin/flatpak" <<'SH'
#!/bin/bash
[[ $1 == "override" && $2 == "--user" ]] || exit 1
shift 2
if [[ $1 == "--show" ]]; then
  printf 'show %s\n' "$2" >>"$MOCK_SHOWS"
  if [[ -n ${MOCK_CHANGE:-} && ! -e $MOCK_CHANGE.done ]]; then
    : >"$MOCK_CHANGE.done"
    sleep 0.1
    printf 'x' >"$MOCK_CHANGE"
  fi
  if [[ -s $MOCK_OVERRIDES.$2 ]]; then
    printf '[Context]\nfilesystems=%s\n' "$(tr '\n' ';' <"$MOCK_OVERRIDES.$2")"
  fi
  exit 0
fi
printf 'override %s\n' "$*" >>"$MOCK_LOG"
overrides="$MOCK_OVERRIDES.${*: -1}"
for arg in "$@"; do
  if [[ $arg == --filesystem=* ]]; then
    path="${arg#--filesystem=}"
    grep -vxF -e "${path%:ro}" -e "${path%:ro}:ro" "$overrides" >"$overrides.new" 2>/dev/null
    printf '%s\n' "$path" >>"$overrides.new"
    mv "$overrides.new" "$overrides"
  fi
done
SH
chmod +x "$mock_bin/flatpak"

# A real home reached through a symlink stands in for /var/home vs /home.
real_home="$test_tmp/var/home/tester"
mkdir -p "$real_home" "$test_tmp/home"
ln -s "$real_home" "$test_tmp/home/tester"
link_home="$test_tmp/home/tester"
system_flatpak="$test_tmp/var/lib/flatpak"
user_flatpak="$real_home/.local/share/flatpak"

deploy() {
  local installation="$1" app="$2"
  mkdir -p "$installation/app/$app/x86_64/stable/abc123/files"
  ln -sfn x86_64/stable "$installation/app/$app/current"
  ln -sfn abc123 "$installation/app/$app/x86_64/stable/active"
  if [[ $app == "com.bitwarden.desktop" ]]; then
    mkdir -p "$installation/app/$app/x86_64/stable/abc123/files/Bitwarden"
    printf '#!/bin/sh\n' >"$installation/app/$app/x86_64/stable/abc123/files/Bitwarden/desktop_proxy"
    chmod +x "$installation/app/$app/x86_64/stable/abc123/files/Bitwarden/desktop_proxy"
  fi
}

reset() {
  rm -rf "$real_home" "$system_flatpak" "$test_tmp"/overrides.* "$test_tmp/mock.log" "$test_tmp/shows"
  mkdir -p "$real_home"
  : >"$test_tmp/mock.log"
}

run_tool() {
  env PATH="$mock_bin:$PATH" HOME="$link_home" FENOA_FLATPAK_SYSTEM_DIR="$system_flatpak" \
    MOCK_OVERRIDES="$test_tmp/overrides" MOCK_LOG="$test_tmp/mock.log" MOCK_SHOWS="$test_tmp/shows" \
    timeout 20 bash "$tool" >"$test_tmp/out.log" 2>&1
}

brave="$real_home/.var/app/com.brave.Browser"
hosts="$brave/config/BraveSoftware/Brave-Browser/NativeMessagingHosts"
manifest="$hosts/com.8bit.bitwarden.json"
bitwarden_data="$real_home/.var/app/com.bitwarden.desktop"
sockets="$bitwarden_data/cache/com.bitwarden.desktop"
link="$brave/cache/com.bitwarden.desktop"
firefox="$real_home/.var/app/org.mozilla.firefox"
firefox_hosts="$firefox/.mozilla/native-messaging-hosts"
firefox_link="$firefox/cache/com.bitwarden.desktop"
brave_overrides="$test_tmp/overrides.com.brave.Browser"
socket_override="~/.var/app/com.bitwarden.desktop/cache/com.bitwarden.desktop:ro"
firefox_overrides="$test_tmp/overrides.org.mozilla.firefox"
system_proxy="$system_flatpak/app/com.bitwarden.desktop/current/active/files/Bitwarden/desktop_proxy"
user_proxy="$user_flatpak/app/com.bitwarden.desktop/current/active/files/Bitwarden/desktop_proxy"

# --- Bitwarden, Brave and Firefox, all system Flatpaks --------------------------------------------

reset
deploy "$system_flatpak" com.bitwarden.desktop
deploy "$system_flatpak" com.brave.Browser
deploy "$system_flatpak" org.mozilla.firefox
run_tool || fail "the helper succeeds with Bitwarden, Brave and Firefox installed" "$(cat "$test_tmp/out.log")"

[[ -f $manifest ]] || fail "Brave gets a native messaging manifest" "$(cat "$test_tmp/out.log")"
[[ $(jq -r .name "$manifest") == "com.8bit.bitwarden" && $(jq -r .type "$manifest") == "stdio" ]] ||
  fail "the manifest is Bitwarden's stdio host, com.8bit.bitwarden" "$(cat "$manifest")"
[[ $(jq -r .path "$manifest") == "$system_proxy" ]] ||
  fail "the manifest runs desktop_proxy from Bitwarden's current deployment" "$(jq -r .path "$manifest")"
jq -e '.allowed_origins | index("chrome-extension://nngceckbapebfimnlniiiahkandclblb/")' "$manifest" >/dev/null ||
  fail "the manifest allows the Chrome Web Store extension, which Brave installs" "$(cat "$manifest")"
pass "Brave's manifest runs desktop_proxy from current/active and allows the Web Store extension"

[[ -d $sockets ]] || fail "Bitwarden's socket directory exists before the app first starts (Flatpak binds only what exists)"
[[ -L $link && $(readlink "$link") == "$sockets" ]] ||
  fail "Brave's cache links to Bitwarden's socket directory, by its canonical path" "$(ls -l "$link" 2>&1)"
[[ $(readlink "$link") != *"$link_home"* ]] || fail "the symlink must not go through the /home symlink"
pass "Brave's cache links com.bitwarden.desktop to the app's socket directory (canonical path)"

overrides=$(cat "$brave_overrides" 2>/dev/null)
grep -qxF "$system_flatpak/app/com.bitwarden.desktop:ro" <<<"$overrides" ||
  fail "Brave can read Bitwarden's deployment, read-only" "$overrides"
# Connecting needs no write access; read-only, no browser can replace the socket the others use.
grep -qxF "$socket_override" <<<"$overrides" ||
  fail "Brave can reach the app's socket directory, read-only (~ for every user)" "$overrides"
(( $(grep -c . <<<"$overrides") == 2 )) || fail "Brave gets those two overrides and nothing else" "$overrides"
pass "Brave's overrides: Bitwarden's deployment and the socket directory, both read-only"

[[ -d $firefox_hosts ]] || fail "Firefox's native-messaging-hosts directory is created for Bitwarden to fill"
[[ -z $(ls -A "$firefox_hosts") ]] || fail "Firefox's directory is left for Bitwarden to fill"
pass "Firefox gets the native-messaging-hosts directory Bitwarden writes into, left for Bitwarden to fill"

[[ -L $firefox_link && $(readlink "$firefox_link") == "$sockets" ]] ||
  fail "Firefox's cache links to the socket directory Brave's does, so both proxies share one socket" "$(ls -l "$firefox_link" 2>&1)"
[[ $(cat "$firefox_overrides" 2>/dev/null) == "$socket_override" ]] ||
  fail "Firefox can reach the app's socket directory, read-only, and gets no other override" "$(cat "$firefox_overrides" 2>&1)"
pass "Firefox's cache links to the same socket directory as Brave's, with the override to reach it"

# --- idempotent -----------------------------------------------------------------------------------

before=$(stat -c %Y.%i "$manifest")
: >"$test_tmp/mock.log"
rm -f "$test_tmp/shows"
run_tool || fail "a second run succeeds" "$(cat "$test_tmp/out.log")"
[[ ! -s $test_tmp/mock.log ]] || fail "a second run adds no overrides" "$(cat "$test_tmp/mock.log")"
[[ $(stat -c %Y.%i "$manifest") == "$before" ]] || fail "a second run leaves the manifest untouched"
[[ ! -s $test_tmp/out.log ]] || fail "a second run has nothing to say" "$(cat "$test_tmp/out.log")"
# Each run looks at Brave's overrides once.
(( $(grep -c com.brave.Browser "$test_tmp/shows") == 1 )) || fail "with no Flatpak change meanwhile, the helper runs once"
pass "a second run changes nothing"

# --- a Flatpak change while it runs ---------------------------------------------------------------

rm -f "$test_tmp/shows" "$system_flatpak/.changed.done"
: >"$system_flatpak/.changed"
MOCK_CHANGE="$system_flatpak/.changed" run_tool ||
  fail "the helper succeeds when a Flatpak change lands while it runs" "$(cat "$test_tmp/out.log")"
(( $(grep -c com.brave.Browser "$test_tmp/shows") == 2 )) ||
  fail "a change to .changed while it runs makes it run again (the path unit does not watch meanwhile)" "$(cat "$test_tmp/shows")"
pass "a Flatpak change that lands while it runs is caught by running again"

# --- a read-write socket override ----------------------------------------------------------------

printf '%s\n' "${socket_override%:ro}" >"$firefox_overrides"
run_tool || fail "the helper succeeds over a read-write socket override" "$(cat "$test_tmp/out.log")"
[[ $(cat "$firefox_overrides") == "$socket_override" ]] ||
  fail "a read-write socket override (the first setup's) becomes read-only" "$(cat "$firefox_overrides")"
pass "a read-write socket override is made read-only"

# --- a directory where the symlink goes -----------------------------------------------------------

rm "$link"
mkdir -p "$link"
printf 'log\n' >"$link/s.bitwarden.log"
run_tool || fail "the helper succeeds over the directory an earlier proxy made" "$(cat "$test_tmp/out.log")"
[[ -L $link && $(readlink "$link") == "$sockets" ]] ||
  fail "the directory a proxy made before the symlink existed is replaced by the symlink" "$(ls -ld "$link")"
pass "the directory an earlier proxy made in Brave's cache (its log only) is replaced by the symlink"

rm "$link"
mkdir -p "$link"
printf 'mine\n' >"$link/other"
if run_tool; then
  fail "a directory in Brave's cache holding more than the proxy's log fails the unit" "$(cat "$test_tmp/out.log")"
fi
[[ -f $link/other && ! -L $link ]] || fail "a directory holding more than the proxy's log is left as it is"
pass "a directory there holding anything else is left alone, and the unit fails"
rm -rf "$link"

rm "$firefox_link"
mkdir -p "$firefox_link"
run_tool || fail "the helper succeeds over the empty directory Firefox's proxy made" "$(cat "$test_tmp/out.log")"
[[ -L $firefox_link && $(readlink "$firefox_link") == "$sockets" ]] ||
  fail "the empty directory in Firefox's cache is replaced by the symlink" "$(ls -ld "$firefox_link")"
pass "the empty directory Firefox's proxy made in its cache is replaced by the symlink"

# --- the browsers' directories are not trusted ----------------------------------------------------

# Brave can rename its cache and put a symlink to ~/.var/app there: com.bitwarden.desktop under it
# is then Bitwarden's whole data directory.
mkdir -p "$bitwarden_data/config/Bitwarden"
printf '{}' >"$bitwarden_data/config/Bitwarden/data.json"
mv "$brave/cache" "$brave/cache.real"
ln -s "$real_home/.var/app" "$brave/cache"
if run_tool; then
  fail "a symlinked cache in Brave's directory fails the unit" "$(cat "$test_tmp/out.log")"
fi
[[ -f $bitwarden_data/config/Bitwarden/data.json ]] || fail "Bitwarden's data survives a symlinked Brave cache"
[[ -d $bitwarden_data && ! -L $bitwarden_data ]] || fail "Bitwarden's data directory is left as it was"
pass "a symlink for Brave's cache leading to ~/.var/app makes it stop, and Bitwarden's data stays"
rm "$brave/cache"
mv "$brave/cache.real" "$brave/cache"

# Where nothing would stop it (an empty directory), only the guards keep it from writing there.
empty="$test_tmp/empty"
for browser in "$brave" "$firefox"; do
  mkdir -p "$empty"
  mv "$browser/cache" "$browser/cache.real"
  ln -s "$empty" "$browser/cache"
  if run_tool; then
    fail "a cache symlinked to an empty directory fails the unit ($(basename "$browser"))" "$(cat "$test_tmp/out.log")"
  fi
  [[ -z $(ls -A "$empty") ]] || fail "nothing is written through a symlinked cache ($(basename "$browser"))" "$(ls -lA "$empty")"
  rm "$browser/cache"
  mv "$browser/cache.real" "$browser/cache"
  run_tool || fail "the helper recovers once the cache is a directory again" "$(cat "$test_tmp/out.log")"
done
pass "nothing is written through a cache symlinked to an empty directory, in Brave or Firefox"

mv "$firefox/.mozilla" "$firefox/.mozilla.real"
ln -s "$empty" "$firefox/.mozilla"
if run_tool; then
  fail "a symlinked .mozilla fails the unit" "$(cat "$test_tmp/out.log")"
fi
[[ -z $(ls -A "$empty") ]] || fail "nothing is created through a symlinked .mozilla" "$(ls -lA "$empty")"
pass "a symlinked .mozilla in Firefox's directory makes it stop, and nothing is created through it"
rm "$firefox/.mozilla"
mv "$firefox/.mozilla.real" "$firefox/.mozilla"

mv "$firefox/cache" "$firefox/cache.real"
ln -s "$real_home/.var/app" "$firefox/cache"
if run_tool; then
  fail "a symlinked cache in Firefox's directory fails the unit" "$(cat "$test_tmp/out.log")"
fi
[[ -f $bitwarden_data/config/Bitwarden/data.json && -d $bitwarden_data && ! -L $bitwarden_data ]] ||
  fail "Bitwarden's data survives a symlinked Firefox cache"
pass "a symlink for Firefox's cache leading to ~/.var/app makes it stop too, and Bitwarden's data stays"
rm "$firefox/cache"
mv "$firefox/cache.real" "$firefox/cache"

elsewhere="$test_tmp/elsewhere"
mkdir -p "$elsewhere"
mv "$hosts" "$hosts.real"
ln -s "$elsewhere" "$hosts"
if run_tool; then
  fail "a symlinked NativeMessagingHosts fails the unit" "$(cat "$test_tmp/out.log")"
fi
[[ -z $(ls -A "$elsewhere") ]] || fail "nothing is written through a symlinked NativeMessagingHosts" "$(ls -A "$elsewhere")"
pass "a symlinked NativeMessagingHosts makes it stop, and nothing is written through it"
rm "$hosts"
mv "$hosts.real" "$hosts"

rm -f "$manifest"
mkfifo "$manifest"
run_tool || fail "the helper succeeds over a FIFO in the manifest's place" "$(cat "$test_tmp/out.log")"
[[ -f $manifest && ! -p $manifest && $(jq -r .path "$manifest") == "$system_proxy" ]] ||
  fail "a FIFO in the manifest's place is replaced with the manifest, without blocking on it"
pass "a FIFO in the manifest's place is replaced, never read"

# --- someone else's manifest ----------------------------------------------------------------------

other_proxy="$hosts/.bitwarden_desktop_proxy"
printf '#!/bin/sh\n' >"$other_proxy"
chmod +x "$other_proxy"
printf '{"name":"com.8bit.bitwarden","path":"%s","type":"stdio","allowed_origins":[]}\n' "$other_proxy" >"$manifest"
run_tool || fail "the helper succeeds next to a working manifest that is not its own" "$(cat "$test_tmp/out.log")"
[[ $(jq -r .path "$manifest") == "$other_proxy" ]] || fail "a manifest that runs another existing proxy is left alone"
pass "a manifest that runs another proxy that exists (Bitwarden's own, one day) is left alone"

rm "$other_proxy"
run_tool || fail "the helper succeeds over a manifest whose proxy is gone" "$(cat "$test_tmp/out.log")"
[[ $(jq -r .path "$manifest") == "$system_proxy" ]] || fail "a manifest whose proxy no longer exists is replaced"
pass "a manifest whose proxy no longer exists is replaced with ours"

# --- Bitwarden removed ----------------------------------------------------------------------------

rm -rf "$system_flatpak/app/com.bitwarden.desktop"
run_tool || fail "the helper succeeds once Bitwarden is gone" "$(cat "$test_tmp/out.log")"
[[ ! -e $manifest ]] || fail "Brave's manifest goes with Bitwarden"
[[ ! -L $link && ! -L $firefox_link ]] || fail "the socket symlinks go with Bitwarden"
pass "with Bitwarden gone, Brave's manifest and both socket symlinks are removed"

reset
deploy "$system_flatpak" com.brave.Browser
mkdir -p "$hosts"
printf '{"name":"com.8bit.bitwarden","path":"/opt/elsewhere/proxy","type":"stdio"}\n' >"$manifest"
run_tool || fail "the helper succeeds without Bitwarden" "$(cat "$test_tmp/out.log")"
[[ $(jq -r .path "$manifest") == "/opt/elsewhere/proxy" ]] || fail "without Bitwarden, a manifest that is not ours is left alone"
[[ ! -s $brave_overrides ]] || fail "without Bitwarden, Brave gets no overrides" "$(cat "$brave_overrides")"
pass "without Bitwarden, nothing is added and a manifest that is not ours stays"

# --- overrides the user revoked -------------------------------------------------------------------

reset
deploy "$system_flatpak" com.bitwarden.desktop
deploy "$system_flatpak" com.brave.Browser
printf '!%s\n' "$system_flatpak/app/com.bitwarden.desktop" >"$brave_overrides"
run_tool || fail "the helper succeeds with a revoked override" "$(cat "$test_tmp/out.log")"
! grep -qxF "$system_flatpak/app/com.bitwarden.desktop:ro" "$brave_overrides" ||
  fail "access the user revoked (--nofilesystem) is not granted again" "$(cat "$brave_overrides")"
grep -qxF "$socket_override" "$brave_overrides" ||
  fail "the override that was not revoked is still added" "$(cat "$brave_overrides")"
grep -qF 'revoked' "$test_tmp/out.log" || fail "the helper says why it leaves the override out" "$(cat "$test_tmp/out.log")"
pass "an override the user revoked stays revoked"

# --- only some apps, or a user installation -------------------------------------------------------

reset
deploy "$system_flatpak" com.bitwarden.desktop
run_tool || fail "the helper succeeds with Bitwarden alone" "$(cat "$test_tmp/out.log")"
[[ ! -e $brave && ! -e $firefox ]] || fail "without the browsers, nothing is created for them"
pass "without Brave or Firefox installed, nothing is created for them"

reset
deploy "$user_flatpak" com.bitwarden.desktop
deploy "$system_flatpak" com.brave.Browser
run_tool || fail "the helper succeeds with Bitwarden in the user installation" "$(cat "$test_tmp/out.log")"
[[ $(jq -r .path "$manifest") == "$user_proxy" ]] ||
  fail "a user-installed Bitwarden's proxy is the one the manifest runs" "$(jq -r .path "$manifest")"
grep -qxF "$user_flatpak/app/com.bitwarden.desktop:ro" "$brave_overrides" ||
  fail "Brave can read the user installation's Bitwarden" "$(cat "$brave_overrides")"
pass "a Bitwarden in the user installation is found and handed to Brave"

deploy "$system_flatpak" com.bitwarden.desktop
run_tool || fail "the helper succeeds with Bitwarden in both installations" "$(cat "$test_tmp/out.log")"
[[ $(jq -r .path "$manifest") == "$user_proxy" ]] ||
  fail "with Bitwarden in both, the user installation's proxy wins, as it does for flatpak run" "$(jq -r .path "$manifest")"
pass "with Bitwarden in both installations, the user one is used, as flatpak run does"

reset
deploy "$system_flatpak" com.bitwarden.desktop
deploy "$system_flatpak" com.brave.Browser
rm "$system_proxy"
if run_tool; then
  fail "a Bitwarden deployment without desktop_proxy fails the unit (upstream moved it)" "$(cat "$test_tmp/out.log")"
fi
grep -qF 'files/Bitwarden/desktop_proxy' "$test_tmp/out.log" || fail "the failure names the missing proxy" "$(cat "$test_tmp/out.log")"
[[ ! -e $manifest ]] || fail "no manifest points at a proxy that does not exist"
pass "a Bitwarden without desktop_proxy where expected fails the unit and writes nothing"

# --- the units and the build ----------------------------------------------------------------------

grep -qx 'Type=oneshot' "$service" && grep -qx 'ExecStart=/usr/libexec/fenoa-bitwarden-browsers' "$service" ||
  fail "the service is a oneshot running the helper" "$(cat "$service")"
# The path unit cannot start an active unit again, and every run checks everything anew.
! grep -q '^RemainAfterExit=' "$service" || fail "the service does not stay active (the path unit starts it again)"
grep -qx 'WantedBy=default.target' "$service" || fail "the service runs at login"
pass "the service is a oneshot that runs at login and does not stay active"

# The default start limit failed the sixth start within 10s, and the path unit with it.
grep -qx 'StartLimitIntervalSec=0' "$service" || fail "a burst of Flatpak changes cannot hit a start limit"
grep -qE '^TimeoutStartSec=[1-9]' "$service" || fail "a hung run times out instead of blocking the path unit"
for unit in "$service" "$path_unit"; do
  grep -qx 'ConditionUser=!@system' "$unit" || fail "$(basename "$unit") skips system accounts (the greeter's session)"
done
pass "no start limit, a start timeout, and neither unit runs for the greeter's account"

# flatpak touches .changed once a transaction is done; app/<id> appears before its deployment does.
grep -qx 'PathChanged=/var/lib/flatpak/.changed' "$path_unit" ||
  fail "the path unit watches the system installation's .changed stamp" "$(cat "$path_unit")"
grep -qx 'PathChanged=%h/.local/share/flatpak/.changed' "$path_unit" ||
  fail "the path unit watches the user installation's .changed stamp" "$(cat "$path_unit")"
! grep -qE '^Path(Exists|ExistsGlob|DirectoryNotEmpty)=.*/app' "$path_unit" ||
  fail "the path unit does not watch app directories (they appear before the deployment)"
grep -qx 'WantedBy=default.target' "$path_unit" || fail "the path unit is started at login"
pass "the path unit watches both installations' .changed stamps"

grep -qF 'systemctl --global enable fenoa-bitwarden-browsers.service fenoa-bitwarden-browsers.path' "$containerfile" ||
  fail "the image enables the service and the path unit for every user"
grep -qF '/usr/libexec/fenoa-bitwarden-browsers' "$containerfile" || fail "the image makes the helper executable"
pass "the image enables both units for every user and makes the helper executable"

grep -qF '<action id="com.bitwarden.Bitwarden.unlock">' "$policy" || fail "the policy defines com.bitwarden.Bitwarden.unlock"
grep -qx '        <allow_active>auth_self</allow_active>' "$policy" &&
  grep -qx '        <allow_any>no</allow_any>' "$policy" &&
  grep -qx '        <allow_inactive>no</allow_inactive>' "$policy" ||
  fail "unlocking needs the active session's own authentication, and nothing else may" "$(cat "$policy")"
pass "Bitwarden's unlock action asks the active session's user to authenticate, and nobody else"
