#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_root/hypr/.local/bin/network-speedtest"
test_root=$(mktemp -d -t network-speedtest-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

mkdir -p "$test_root/bin" "$test_root/counters"

cat >"$test_root/bin/ip" <<'SH'
#!/usr/bin/env bash
printf '1.1.1.1 via 127.0.0.1 dev lo src 127.0.0.1\n'
SH

cat >"$test_root/bin/curl" <<'SH'
#!/usr/bin/env bash
api_url="" data_mode=false upload_mode=false previous=""
for argument in "$@"; do
  [[ $argument == https://api.fast.com/* ]] && api_url=$argument
  [[ $previous == --data-binary && $argument == @- ]] && data_mode=true
  [[ $previous == --upload-file && $argument == - ]] && upload_mode=true
  previous=$argument
done
if [[ -n $api_url ]]; then
  printf 'api:%s\n' "$api_url" >>"$CURL_CALLS"
  if [[ ${CURL_API_FAIL:-} == 1 ]]; then
    printf 'curl: fixture HTTP 403\n' >&2
    exit 22
  fi
  printf '%s\n' '{"client":{},"targets":[{"url":"https://one.test/speedtest"},{"url":"https://two.test/speedtest"},{"url":"https://three.test/speedtest"}]}'
elif "$data_mode"; then
  printf 'upload-data\n' >>"$CURL_CALLS"
elif "$upload_mode"; then
  printf 'upload-file\n' >>"$CURL_CALLS"
else
  printf 'download\n' >>"$CURL_CALLS"
fi
SH

cat >"$test_root/bin/cat" <<'SH'
#!/usr/bin/env bash
name=${1##*/}
state="$COUNTER_STATE/$name"
count=0
[[ ! -e $state ]] || read -r count <"$state"
printf '%s\n' "$((count + 1))" >"$state"
case "$name:$count" in
  rx_bytes:0) printf '1000000\n' ;;
  rx_bytes:*) printf '63500000\n' ;;
  tx_bytes:0) printf '2000000\n' ;;
  tx_bytes:*) printf '33250000\n' ;;
  *) exit 1 ;;
esac
SH

cat >"$test_root/bin/head" <<'SH'
#!/usr/bin/env bash
exit 0
SH

cat >"$test_root/bin/sleep" <<'SH'
#!/usr/bin/env bash
/usr/bin/sleep 0.1
SH

chmod +x "$test_root/bin/"*

export CURL_CALLS="$test_root/curl.calls"
export COUNTER_STATE="$test_root/counters"

run() {
  CURL_API_FAIL="${CURL_API_FAIL:-}" PATH="$test_root/bin:/usr/bin" "$script" "$@"
}

output=$(run)
grep -Fq 'Interface: lo' <<<"$output" || fail 'active interface was not reported'
grep -Fq 'Download: 100.0 Mbps' <<<"$output" || fail 'download calculation is wrong'
grep -Fq 'Upload: 50.0 Mbps' <<<"$output" || fail 'upload calculation is wrong'
[[ $(grep -c '^download$' "$CURL_CALLS") == 8 ]] ||
  fail 'download did not start eight curl workers'
[[ $(grep -c '^upload-data$' "$CURL_CALLS") == 8 ]] ||
  fail 'upload did not POST /dev/zero with curl data mode'
grep -Fqx 'api:https://api.fast.com/netflix/speedtest/v2?token=YXNkZmFzZGxmbnNkYWZoYXNkZmhrYWxm&urlCount=3' \
  "$CURL_CALLS" || fail 'fast.com API parameters changed'
! grep -Fq 'notify-send' "$script" || fail 'network speed test still sends notifications'

: >"$CURL_CALLS"
rm -f "$COUNTER_STATE"/*
stream=$(run --stream-json)
jq -se 'length == 11
  and (map(select(.phase == "download")) | length == 5)
  and (map(select(.phase == "upload")) | length == 5)
  and .[10].phase == "complete"' <<<"$stream" >/dev/null ||
  fail 'stream mode did not emit live download and upload samples'

if CURL_API_FAIL=1 run >"$test_root/failure.out" 2>"$test_root/failure.err"; then
  fail 'HTTP 403 did not fail'
fi
grep -Fq 'public token' "$test_root/failure.err" ||
  fail 'HTTP 403 did not produce a clear error'

printf 'ok: network speed test fixtures\n'
