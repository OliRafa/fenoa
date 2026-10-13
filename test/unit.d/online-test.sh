#!/bin/bash

# fenoa-online is the ExecCondition= the provisioning units use to wait for the network, since the
# image masks NetworkManager-wait-online and network-online.target is no barrier. Its exit status
# is the whole interface: 0 runs the unit, 1 skips it (its timer tries again), 255 fails it. A check
# that wrongly exits 0 brings back the original bug (provisioning "succeeding" offline); one that
# exits 1 when it is broken skips the unit forever without a trace.
#
# It asks for an HTTPS answer, not just a DNS answer: with a host pointed at 127.0.0.1, or behind a
# captive portal, the name resolves and `flatpak preinstall` still installs nothing and exits 0.
# curl is stubbed through PATH, which holds nothing else, so the host's network is never touched.

source "$(dirname "$0")/base-test.sh"

helper="$ROOT/system/platform/usr/libexec/fenoa-online"
[[ -f $helper ]] || fail "fenoa-online ships"
[[ -x $helper ]] || fail "fenoa-online is executable"
pass "fenoa-online ships, executable"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"
mock_log="$test_tmp/mock.log"

# curl answers (exit 0, whatever the HTTP status) for the hosts in ANSWERS; for hosts in TLS_FAILS it
# fails certificate validation (60, what a captive portal gets), for hosts in HANGS it times out (28),
# and anything else does not resolve (6). ANSWER_AFTER=N makes ANSWERS hosts fail their first N-1
# requests, counted in CALLS. Real curl prints its error on stderr under --show-error.
cat >"$mock_bin/curl" <<'SH'
#!/bin/bash
printf 'curl %s\n' "$*" >>"$MOCK_LOG"
url=${*: -1}
host=${url#https://}
host=${host%/}
# Builtins only: PATH holds nothing but the stubs.
calls=0
[[ -f $CALLS ]] && read -r calls <"$CALLS"
calls=$(( calls + 1 ))
echo "$calls" >"$CALLS"
if [[ " ${ANSWERS:-} " == *" $host "* ]] && (( calls >= ${ANSWER_AFTER:-1} )); then
  exit 0
elif [[ " ${TLS_FAILS:-} " == *" $host "* ]]; then
  echo "curl: (60) SSL certificate problem: self-signed certificate" >&2
  exit 60
elif [[ " ${HANGS:-} " == *" $host "* ]]; then
  echo "curl: (28) Connection timed out after 10002 milliseconds" >&2
  exit 28
fi
echo "curl: (6) Could not resolve host: $host" >&2
exit 6
SH
chmod +x "$mock_bin/curl"

# curl that cannot do the check at all (no CA bundle).
broken_bin="$test_tmp/broken"
mkdir -p "$broken_bin"
printf '#!/bin/bash\necho "curl: (77) error setting certificate file" >&2\nexit 77\n' >"$broken_bin/curl"
chmod +x "$broken_bin/curl"
# And no curl at all: PATH holds only sleep.
nocurl_bin="$test_tmp/nocurl"
mkdir -p "$nocurl_bin"
ln -s "$(command -v sleep)" "$nocurl_bin/sleep"
ln -s "$(command -v sleep)" "$mock_bin/sleep"
ln -s "$(command -v sleep)" "$broken_bin/sleep"

# Bounded by timeout(1): a regression that loops forever (as an octal --wait once did) fails the
# test instead of hanging it.
run() {
  : >"$mock_log"
  rm -f "$test_tmp/calls"
  timeout 30 env -i PATH="${MOCK_PATH:-$mock_bin}" MOCK_LOG="$mock_log" CALLS="$test_tmp/calls" \
    ANSWERS="${ANSWERS:-}" TLS_FAILS="${TLS_FAILS:-}" HANGS="${HANGS:-}" ANSWER_AFTER="${ANSWER_AFTER:-1}" \
    FENOA_ONLINE_INTERVAL="${FENOA_ONLINE_INTERVAL:-0}" \
    ${FENOA_ONLINE_TIMEOUT:+FENOA_ONLINE_TIMEOUT="$FENOA_ONLINE_TIMEOUT"} \
    /bin/bash "$helper" "$@" >"$test_tmp/out.log" 2>&1
}

# --- every host answers -----------------------------------------------------------------------

ANSWERS="dl.flathub.org registry.fedoraproject.org" run dl.flathub.org registry.fedoraproject.org
rc=$?
(( rc == 0 )) || fail "exits 0 when every host answers" "exit $rc: $(cat "$test_tmp/out.log")"
pass "exits 0 when every host answers over HTTPS"

for host in dl.flathub.org registry.fedoraproject.org; do
  grep -qx "curl --silent --show-error --head --max-time 10 --output /dev/null https://$host/" "$mock_log" ||
    fail "asks https://$host/ with a 10s bound" "$(cat "$mock_log")"
done
pass "each host is asked for https://HOST/ (HEAD), bounded by a 10s timeout"

# Any HTTP status is an answer (ghcr.io answers an error status), and the certificate has to validate.
if grep -qE -- ' (--fail|-f|--fail-with-body|--insecure|-k)( |$)' "$mock_log"; then
  fail "neither --fail (any status counts) nor --insecure (the certificate must validate)" "$(cat "$mock_log")"
fi
pass "no --fail (any HTTP status counts) and no --insecure (the certificate must validate)"

ANSWERS="example.org" FENOA_ONLINE_TIMEOUT=3 run example.org
grep -qF -- "--max-time 3 " "$mock_log" || fail "FENOA_ONLINE_TIMEOUT sets the bound" "$(cat "$mock_log")"
pass "FENOA_ONLINE_TIMEOUT sets the per-request bound"

# --- not online yet: skip (1), and say why ------------------------------------------------------

run dl.flathub.org registry.fedoraproject.org
rc=$?
(( rc == 1 )) || fail "exits 1 when nothing answers (offline)" "exit $rc: $(cat "$test_tmp/out.log")"
grep -qF "dl.flathub.org does not answer over HTTPS yet (curl: (6) Could not resolve host" "$test_tmp/out.log" ||
  fail "the skip names the host and curl's reason" "$(cat "$test_tmp/out.log")"
pass "offline: exits 1 (ExecCondition skips the unit), naming the host and curl's reason"

# Every host has to answer, not just the first: the unit talks to all of them.
ANSWERS="dl.flathub.org" run dl.flathub.org registry.fedoraproject.org
rc=$?
(( rc == 1 )) || fail "exits 1 when a later host does not answer" "exit $rc: $(cat "$test_tmp/out.log")"
grep -qF "registry.fedoraproject.org does not answer" "$test_tmp/out.log" ||
  fail "the skip names the later host" "$(cat "$test_tmp/out.log")"
pass "exits 1 when any one host does not answer"

# The reviewer's case: the name resolves, but what answers is not the real server (a captive
# portal, a host pinned to 127.0.0.1). TLS validation is what tells them apart.
TLS_FAILS="dl.flathub.org" run dl.flathub.org
rc=$?
(( rc == 1 )) || fail "a certificate that does not validate (captive portal) exits 1" "exit $rc: $(cat "$test_tmp/out.log")"
pass "a certificate that does not validate (a captive portal) counts as not online"

HANGS="dl.flathub.org" run dl.flathub.org
rc=$?
(( rc == 1 )) || fail "a timed-out request exits 1" "exit $rc: $(cat "$test_tmp/out.log")"
grep -qF "Connection timed out" "$test_tmp/out.log" || fail "the skip says the request timed out" "$(cat "$test_tmp/out.log")"
pass "a timed-out request counts as not online, and says so"

# --- --wait: retry for a bounded time -----------------------------------------------------------

# Answers on the third request: with --wait it keeps asking and passes.
ANSWERS="dl.flathub.org" ANSWER_AFTER=3 run --wait=60 dl.flathub.org
rc=$?
(( rc == 0 )) || fail "--wait keeps asking until the host answers" "exit $rc: $(cat "$test_tmp/out.log")"
(( $(grep -c '^curl ' "$mock_log") == 3 )) || fail "--wait asked three times" "$(cat "$mock_log")"
pass "--wait retries until the host answers (third request)"

# Without --wait the same host is asked once and skipped.
ANSWERS="dl.flathub.org" ANSWER_AFTER=3 run dl.flathub.org
rc=$?
(( rc == 1 )) || fail "without --wait a failed check skips at once" "exit $rc"
(( $(grep -c '^curl ' "$mock_log") == 1 )) || fail "without --wait there is one request" "$(cat "$mock_log")"
pass "without --wait there is exactly one attempt"

# A host that never answers: give up once the next retry would start past the deadline. With a 1s
# interval and --wait=2 that is after about 2 seconds and 2-3 requests, then exit 1.
start=$SECONDS
FENOA_ONLINE_INTERVAL=1 run --wait=2 dl.flathub.org
rc=$?
took=$(( SECONDS - start ))
(( rc == 1 )) || fail "--wait gives up with exit 1" "exit $rc: $(cat "$test_tmp/out.log")"
(( took <= 5 )) || fail "--wait gives up close to its bound" "took ${took}s"
requests=$(grep -c '^curl ' "$mock_log")
(( requests >= 2 && requests <= 4 )) || fail "--wait=2 at a 1s interval retries a few times" "$requests requests"
grep -qF -- "(--wait=2), skipping" "$test_tmp/out.log" || fail "giving up is logged" "$(cat "$test_tmp/out.log")"
pass "--wait gives up after its bound with exit 1 ($requests requests in ${took}s)"

# A broken check fails at once, --wait or not.
MOCK_PATH="$broken_bin" run --wait=60 dl.flathub.org
rc=$?
(( rc == 255 )) || fail "a curl that cannot check (no CA bundle) exits 255, even with --wait" "exit $rc: $(cat "$test_tmp/out.log")"
pass "a check that cannot run (no CA bundle) exits 255 at once, even with --wait"

# --- broken or misused: fail (255), never a silent skip -----------------------------------------

MOCK_PATH="$nocurl_bin" run dl.flathub.org
rc=$?
(( rc == 255 )) || fail "no curl exits 255" "exit $rc: $(cat "$test_tmp/out.log")"
grep -qF "cannot check dl.flathub.org" "$test_tmp/out.log" || fail "the failure names the host" "$(cat "$test_tmp/out.log")"
pass "no curl at all: exits 255"

# A --wait bash would read as octal ("08" is an arithmetic error that kept the retry loop going
# forever, "0300" silently became 192s) or that is absurdly long counts as misuse too.
for args in "" "--wait=60" "''" "--wait=soon dl.flathub.org" "--wait=08 dl.flathub.org" "--wait=0300 dl.flathub.org" \
            "--wait=-1 dl.flathub.org" "--wait=1000000 dl.flathub.org" "--wait=99999999999999999999 dl.flathub.org" \
            "--bogus dl.flathub.org" "https://dl.flathub.org/" "dl.flathub.org/repo"; do
  eval "run $args"
  rc=$?
  (( rc == 255 )) || fail "misuse exits 255: fenoa-online $args" "exit $rc: $(cat "$test_tmp/out.log")"
  [[ ! -s $mock_log ]] || fail "misuse makes no request: fenoa-online $args" "$(cat "$mock_log")"
done
grep -q "usage:" "$test_tmp/out.log" || fail "misuse prints the usage" "$(cat "$test_tmp/out.log")"
pass "misuse (no host, an empty host, a URL, a bad, octal-looking or overlong --wait, an unknown option) exits 255 and asks nothing"

# The overrides reach the same arithmetic, so they are held to the same shape.
FENOA_ONLINE_INTERVAL=08 run --wait=5 dl.flathub.org
rc=$?
(( rc == 255 )) || fail "an octal-looking FENOA_ONLINE_INTERVAL is misuse" "exit $rc: $(cat "$test_tmp/out.log")"
FENOA_ONLINE_TIMEOUT=0 run dl.flathub.org
rc=$?
(( rc == 255 )) || fail "a zero FENOA_ONLINE_TIMEOUT is misuse" "exit $rc: $(cat "$test_tmp/out.log")"
pass "FENOA_ONLINE_INTERVAL and FENOA_ONLINE_TIMEOUT must be plain decimal (and the timeout above 0)"

# And --wait=0 is the same as no --wait: one attempt.
run --wait=0 dl.flathub.org
rc=$?
(( rc == 1 )) && (( $(grep -c '^curl ' "$mock_log") == 1 )) || fail "--wait=0 makes one attempt and skips" "exit $rc: $(cat "$mock_log")"
pass "--wait=0 makes exactly one attempt"

# --- callers --------------------------------------------------------------------------------------

# A unit that passes no host fails on every start; one that passes something shaped wrong fails too.
units="$ROOT/system/platform/usr/lib/systemd/system"
callers=$(grep -l '^ExecCondition=.*/usr/libexec/fenoa-online' "$units"/* 2>/dev/null || true)
[[ -n $callers ]] || fail "some unit gates on fenoa-online"
for unit in $callers; do
  while read -r call; do
    args=${call#*/usr/libexec/fenoa-online}
    args=${args%%[\'\"]*}
    read -ra words <<<"$args"
    hosts=0
    for word in "${words[@]}"; do
      if [[ $word == --wait=* ]]; then
        [[ $word =~ ^--wait=(0|[1-9][0-9]{0,5})$ ]] || fail "$(basename "$unit") passes --wait plain decimal seconds" "$call"
      else
        [[ $word =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ && $word == *.* ]] ||
          fail "$(basename "$unit") passes fenoa-online host names, not '$word'" "$call"
        hosts=$(( hosts + 1 ))
      fi
    done
    (( hosts > 0 )) || fail "$(basename "$unit") passes fenoa-online at least one host" "$call"
  done < <(grep -E '^ExecCondition=.*/usr/libexec/fenoa-online' "$unit")
done
pass "every unit that calls fenoa-online passes it bare host names (and a numeric --wait)"
