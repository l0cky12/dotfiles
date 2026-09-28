#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
profile="$repo_root/hypr/.config/hypr/scripts/hypridle-profile"
source_config="$repo_root/hypr/.config/hypr/hypridle.conf"
test_root=$(mktemp -d -t hypridle-profile-test.XXXXXX)
cleanup() {
  if [[ -x $test_root/bin/pkill-fixture ]]; then
    "$test_root/bin/pkill-fixture" >/dev/null 2>&1 || true
  fi
  rm -rf -- "$test_root"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

mkdir -p "$test_root/bin" "$test_root/state" "$test_root/runtime"
cat > "$test_root/bin/pkill-fixture" <<'SH'
#!/usr/bin/env python3
import os, signal, sys
from pathlib import Path
with open(os.environ["HYPRIDLE_PROFILE_CALLS"], "a") as log:
    log.write("pkill " + " ".join(sys.argv[1:]) + "\n")
pidfile = Path(os.environ["FIXTURE_PID"])
try:
    os.kill(int(pidfile.read_text()), signal.SIGTERM)
except (FileNotFoundError, ProcessLookupError):
    sys.exit(1)
SH
cat > "$test_root/bin/pgrep-fixture" <<'SH'
#!/usr/bin/env python3
import os, sys
from pathlib import Path
try:
    os.kill(int(Path(os.environ["FIXTURE_PID"]).read_text()), 0)
except (FileNotFoundError, ProcessLookupError):
    sys.exit(1)
SH
cat > "$test_root/bin/hypridle-fixture" <<'SH'
#!/usr/bin/env python3
import os, re, signal, sys, time
from pathlib import Path
config = Path(sys.argv[2]).read_text()
timeout = re.search(r"timeout = (\d+)", config)[1]
with open(os.environ["HYPRIDLE_PROFILE_CALLS"], "a") as log:
    log.write("start " + timeout + "\n")
if os.environ.get("FAIL_TIMEOUT") == timeout:
    sys.exit(17)
pidfile = Path(os.environ["FIXTURE_PID"])
pidfile.write_text(str(os.getpid()))
def stop(*_):
    pidfile.unlink(missing_ok=True)
    sys.exit(0)
signal.signal(signal.SIGTERM, stop)
while True:
    time.sleep(.05)
SH
cat > "$test_root/bin/hypridle-once" <<'SH'
#!/usr/bin/env bash
printf 'hypridle %s\n' "$*" >> "$HYPRIDLE_PROFILE_CALLS"
SH
chmod +x "$test_root/bin/"*

export HYPRIDLE_PROFILE_STATE_FILE="$test_root/state/idle-profile"
export HYPRIDLE_PROFILE_SOURCE_CONFIG="$source_config"
export HYPRIDLE_PROFILE_RUNTIME_DIR="$test_root/runtime"
export HYPRIDLE_PROFILE_PKILL="$test_root/bin/pkill-fixture"
export HYPRIDLE_PROFILE_PGREP="$test_root/bin/pgrep-fixture"
export HYPRIDLE_PROFILE_SETSID=setsid
export HYPRIDLE_PROFILE_NOTIFY=true
export FIXTURE_PID="$test_root/pid"
export HYPRIDLE_PROFILE_HYPRIDLE="$test_root/bin/hypridle-fixture"
export HYPRIDLE_PROFILE_CALLS="$test_root/calls.log"

[[ $($profile current) == balanced ]] || fail 'missing state did not select the balanced profile'

$profile render quick > "$test_root/quick.conf"
for timeout in 60 180 600 1200; do
  grep -Eq "^[[:space:]]*timeout = $timeout$" "$test_root/quick.conf" \
    || fail "quick profile omitted timeout $timeout"
done
[[ $(grep -c '^[[:space:]]*listener {' "$test_root/quick.conf") == 4 ]] \
  || fail 'quick profile did not keep all four listeners'

$profile render never-suspend > "$test_root/never-suspend.conf"
[[ $(grep -c '^[[:space:]]*listener {' "$test_root/never-suspend.conf") == 3 ]] \
  || fail 'never-suspend profile did not remove the suspend listener'
grep -Fq 'on-timeout = systemctl suspend' "$test_root/never-suspend.conf" \
  && fail 'never-suspend profile retained the suspend action'

if $profile render unknown > /dev/null 2>&1; then
  fail 'an unknown profile rendered successfully'
fi

$profile set relaxed --dry-run > "$test_root/dry-run.out"
[[ ! -e $HYPRIDLE_PROFILE_STATE_FILE ]] || fail 'dry-run wrote profile state'
[[ ! -e $HYPRIDLE_PROFILE_CALLS ]] || fail 'dry-run restarted Hypridle'
grep -Fq 'would select idle profile: relaxed' "$test_root/dry-run.out" \
  || fail 'dry-run did not report the selected profile'

if HYPRIDLE_PROFILE_SETSID="$test_root/bin/missing-setsid" \
    $profile set relaxed > /dev/null 2>&1; then
  fail 'set continued without its restart command'
fi
[[ ! -e $HYPRIDLE_PROFILE_STATE_FILE ]] || fail 'failed preflight wrote profile state'

$profile set quick > "$test_root/set.out"
[[ $(<"$HYPRIDLE_PROFILE_STATE_FILE") == quick ]] || fail 'set did not persist the profile'
grep -Eq "^pkill .*hypridle$" "$HYPRIDLE_PROFILE_CALLS" || fail 'set did not stop old Hypridle'
for _ in {1..50}; do
  [[ -e $FIXTURE_PID ]] && break
  sleep .02
done
grep -Fxq 'start 60'  "$HYPRIDLE_PROFILE_CALLS" || fail 'set did not launch the selected config'

# A replacement that exits at startup must not claim success or change state.
if FAIL_TIMEOUT=300 $profile set relaxed > "$test_root/failed.out" 2>&1; then
  fail 'failed replacement was reported as success'
fi
[[ $(<"$HYPRIDLE_PROFILE_STATE_FILE") == quick ]] || fail 'failed replacement changed the saved profile'
grep -Eq '^[[:space:]]*timeout = 60$' "$test_root/runtime/hypridle.conf" \
  || fail 'failed replacement did not restore the runtime config'
"$HYPRIDLE_PROFILE_PGREP" || fail 'failed replacement left no running daemon'
grep -Fq 'restored' "$test_root/failed.out" || fail 'rollback was not explained'
[[ $(grep -c '^start 60$' "$HYPRIDLE_PROFILE_CALLS") == 2 ]] || fail 'previous profile was not restarted'
grep -Eq '^[[:space:]]*timeout = 60$' "$test_root/runtime/hypridle.conf" \
  || fail 'set did not render the selected runtime config'

: > "$HYPRIDLE_PROFILE_CALLS"
HYPRIDLE_PROFILE_HYPRIDLE="$test_root/bin/hypridle-once" $profile daemon
grep -Fxq "hypridle --config $test_root/runtime/hypridle.conf" "$HYPRIDLE_PROFILE_CALLS" \
  || fail 'daemon did not start Hypridle with the runtime config'

printf 'not-a-profile\n' > "$HYPRIDLE_PROFILE_STATE_FILE"
[[ $($profile current) == balanced ]] || fail 'invalid state did not fail closed to balanced'

grep -Fq "\$HOME/.config/hypr/scripts/hypridle-profile daemon" \
  "$repo_root/hypr/.config/hypr/conf/autostart.lua" \
  || fail 'Lua autostart does not use the profile daemon'
grep -Fq "\$HOME/.config/hypr/scripts/hypridle-profile daemon" \
  "$repo_root/hypr/.config/hypr/conf/autostart.conf" \
  || fail 'legacy autostart does not use the profile daemon'

printf 'ok: Hypridle profile fixtures\n'
