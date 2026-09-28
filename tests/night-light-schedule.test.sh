#!/usr/bin/env bash
# Night-light schedule: sun times, fixed and sunset schedules, the manual
# override, suspend catch-up, settings validation, and the Quickshell panel.
# Everything runs against a fixture night-light command and a pinned clock, so
# no Hyprland session is touched.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
schedule="$repo_root/hypr/.config/hypr/scripts/night-light-schedule.py"
qs_root="$repo_root/quickshell/.config/quickshell"
test_root=$(mktemp -d -t night-light-schedule-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# --- wiring -------------------------------------------------------------------

grep -Fq 'exec(mod .. " + SHIFT + N", "night light schedule", "quickshell ipc call nightlight toggle")' \
  "$repo_root/hypr/.config/hypr/conf/keybindings.lua" || fail 'Super+Shift+N does not open the schedule panel'
# shellcheck disable=SC2016 # Literal Hyprland variable.
grep -Fq 'bindd = $mainMod SHIFT, N, night light schedule, exec, quickshell ipc call nightlight toggle' \
  "$repo_root/hypr/.config/hypr/conf/keybinding.conf" || fail 'legacy keybinding.conf lacks Super+Shift+N'
grep -Fq 'target: "nightlight"' "$qs_root/Bar.qml" || fail 'the bar has no nightlight IPC target'
grep -Fq 'NightLightPanel {' "$qs_root/Bar.qml" || fail 'the bar does not mount the schedule panel'
grep -Fq 'systemctl --user start night-light-schedule.timer' \
  "$repo_root/hypr/.config/hypr/conf/autostart.lua" || fail 'autostart does not start the schedule timer'
grep -Fq 'ExecStart=%h/.config/hypr/scripts/night-light-schedule.py apply' \
  "$repo_root/systemd/.config/systemd/user/night-light-schedule.service" || fail 'the service does not run apply'
grep -Fq 'OnCalendar=minutely' "$repo_root/systemd/.config/systemd/user/night-light-schedule.timer" ||
  fail 'the timer does not run every minute'
python3 - "$repo_root/menu/.config/lmenu/menu.jsonc" <<'PY' || fail 'lmenu rows are wrong'
import json, re, sys
text = re.sub(r'^\s*//.*$', '', open(sys.argv[1]).read(), flags=re.M)
rows = {row["id"]: row for row in json.loads(text)}
row = rows["trigger.toggle.nightlight-schedule"]
assert row["action"] == "quickshell ipc call nightlight toggle", row
# The shader night light does not need hyprsunset, so neither row is hidden
# behind it.
assert "when" not in rows["trigger.toggle.nightlight"], rows["trigger.toggle.nightlight"]
PY

# --- fixtures -----------------------------------------------------------------

mkdir -p "$test_root/bin"
cat >"$test_root/bin/night-light" <<'SH'
#!/usr/bin/env bash
[[ -z ${FIXTURE_FAIL:-} || $1 == status ]] || exit 1
case $1 in
  status) [[ -f $FIXTURE_LIT ]] && echo 'night-light: on (screen shader)' || echo 'night-light: off' ;;
  on) touch "$FIXTURE_LIT"; echo on >>"$FIXTURE_CALLS" ;;
  off) rm -f "$FIXTURE_LIT"; echo off >>"$FIXTURE_CALLS" ;;
  *) exit 2 ;;
esac
SH
chmod +x "$test_root/bin/night-light"

export TZ=America/Chicago
export NIGHT_LIGHT_COMMAND="$test_root/bin/night-light"
export NIGHT_LIGHT_WEATHER_FILE="$test_root/weather.json"
export FIXTURE_LIT="$test_root/lit"
export FIXTURE_CALLS="$test_root/calls"
printf '{"latitude": 41.8781, "longitude": -87.6298, "timezone": "America/Chicago"}\n' \
  >"$NIGHT_LIGHT_WEATHER_FILE"

reset() {
  export NIGHT_LIGHT_SCHEDULE_DIR="$test_root/state-$1"
  rm -rf -- "$NIGHT_LIGHT_SCHEDULE_DIR" "$FIXTURE_LIT"
  : >"$FIXTURE_CALLS"
}

at() {
  local moment=$1
  shift
  NIGHT_LIGHT_SCHEDULE_NOW=$moment "$schedule" "$@"
}

expect() {
  local got=$1 want=$2 what=$3
  [[ "$got" == "$want" ]] || fail "$what: expected '$want', got '$got'"
}

lit() { [[ -f $FIXTURE_LIT ]] && echo on || echo off; }

# --- sun times against published values (±2 minutes) -------------------------

python3 - "$schedule" <<'PY' || fail 'sun times drifted from published values'
import importlib.util, os, sys, time
from datetime import date
spec = importlib.util.spec_from_file_location("schedule", sys.argv[1])
cases = [
    # tz, place, lat, lon, day, sunrise, sunset (timeanddate.com)
    ("America/Chicago", "Chicago", 41.8781, -87.6298, date(2026, 6, 21), "05:15", "20:29"),
    ("America/Chicago", "Chicago", 41.8781, -87.6298, date(2026, 12, 21), "07:15", "16:22"),
    ("Europe/London", "London", 51.5074, -0.1278, date(2026, 12, 21), "08:04", "15:53"),
    ("Australia/Sydney", "Sydney", -33.8688, 151.2093, date(2026, 6, 21), "07:00", "16:54"),
]
for tz, place, lat, lon, day, rise, sets in cases:
    os.environ["TZ"] = tz
    time.tzset()
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    sunrise, sunset, kind = module.sun_times(day, lat, lon)
    for got, want, name in ((sunrise, rise, "sunrise"), (sunset, sets, "sunset")):
        h, m = map(int, want.split(":"))
        delta = abs(got.hour * 60 + got.minute - (h * 60 + m))
        assert delta <= 2, f"{place} {day} {name}: {got:%H:%M} vs {want}"
assert module.sun_times(date(2026, 6, 21), 78.2, 15.6)[2] == "polar-day"
assert module.sun_times(date(2026, 12, 21), 78.2, 15.6)[2] == "polar-night"
PY

# --- sunset mode ----------------------------------------------------------------
# Chicago, 2026-09-27: sunrise 06:42, sunset 18:40. 2026-09-28: 06:44 / 18:38.

reset sunset
expect "$(at 2026-09-27T19:00 set mode=sunset)" 'switched on' 'choosing sunset after dark'
expect "$(lit)" on 'sunset mode takes effect immediately'
expect "$(at 2026-09-27T19:01 apply)" 'no change due' 'a quiet minute'

# A manual switch holds until the next scheduled change...
"$NIGHT_LIGHT_COMMAND" off
expect "$(at 2026-09-27T19:02 apply)" 'no change due' 'manual off during the night'
expect "$(lit)" off 'manual off holds'
# ...and the next change (sunrise) is already the state the user picked.
expect "$(at 2026-09-28T07:00 apply)" 'already off' 'sunrise after manual off'
expect "$(at 2026-09-28T18:37 apply)" 'no change due' 'just before sunset'
expect "$(at 2026-09-28T18:39 apply)" 'switched on' 'sunset'
expect "$(lit)" on 'light on after sunset'

# Suspended across sunrise: the first run after waking catches up.
expect "$(at 2026-09-29T09:30 apply)" 'switched off' 'catch-up after suspend'

# A clock that moved backwards does not replay switches.
expect "$(at 2026-09-29T05:00 apply)" 'no change due' 'clock moved backwards'

# Offsets move the switch times.
reset offsets
at 2026-09-27T12:00 set mode=sunset sunset_offset=-30 sunrise_offset=15 >/dev/null
expect "$(at 2026-09-27T18:05 apply)" 'no change due' 'before offset sunset'
expect "$(at 2026-09-27T18:11 apply)" 'switched on' '30 minutes before sunset'
expect "$(at 2026-09-28T06:50 apply)" 'no change due' 'before offset sunrise'
expect "$(at 2026-09-28T07:01 apply)" 'switched off' '15 minutes after sunrise'

status_json=$(at 2026-09-27T12:00 status --json)
python3 - "$status_json" <<'PY' || fail 'status JSON is wrong'
import json, sys
s = json.loads(sys.argv[1])
assert s["mode"] == "sunset" and s["sunset_offset"] == -30 and s["sunrise_offset"] == 15, s
assert s["location"]["source"] == "weather default", s["location"]
assert s["today"]["sunset"].startswith("2026-09-27T18:4"), s["today"]
assert s["next"] == {"at": s["next"]["at"], "light": True} and s["next"]["at"].startswith("2026-09-27T18:1"), s["next"]
assert s["error"] is None
PY

# --- fixed mode, including a window across midnight --------------------------

reset fixed
expect "$(at 2026-09-27T20:00 set mode=fixed on=21:30 off=06:15)" 'already off' 'fixed mode before the window'
expect "$(at 2026-09-27T21:29 apply)" 'no change due' 'fixed before on time'
expect "$(at 2026-09-27T21:31 apply)" 'switched on' 'fixed on time'
expect "$(at 2026-09-28T02:00 apply)" 'no change due' 'fixed after midnight'
expect "$(at 2026-09-28T06:16 apply)" 'switched off' 'fixed off time'
# Changing a time re-evaluates straight away.
expect "$(at 2026-09-28T10:00 set on=09:00 off=17:00)" 'switched on' 'moved window now includes the present'

# --- off mode never switches ----------------------------------------------------

reset off
at 2026-09-27T12:00 set mode=off >/dev/null
expect "$(at 2026-09-27T23:00 apply)" 'schedule off' 'off mode'
[[ ! -s $FIXTURE_CALLS ]] || fail 'off mode switched the light'

# --- validation, location and dry runs ------------------------------------------

reset validation
for bad in mode=never on=25:00 off=7 sunset_offset=500 sunrise_offset=soon colour=red; do
  if at 2026-09-27T12:00 set "$bad" 2>/dev/null; then
    fail "set accepted $bad"
  fi
done
if at 2026-09-27T12:00 set-location 95 10 2>/dev/null; then
  fail 'set-location accepted latitude 95'
fi
[[ ! -e $NIGHT_LIGHT_SCHEDULE_DIR/schedule.json ]] || fail 'a rejected setting was written'

reset location
at 2026-09-27T12:00 set mode=sunset >/dev/null
at 2026-09-27T12:00 set-location 51.5074 -0.1278 London >/dev/null
python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); assert s["location"]=={"latitude":51.5074,"longitude":-0.1278,"place":"London"} and s["mode"]=="sunset", s' \
  "$NIGHT_LIGHT_SCHEDULE_DIR/schedule.json" || fail 'set-location did not save the location'

printf '{"loc": "40.7128,-74.0060", "city": "New York", "region": "New York", "timezone": "America/New_York"}\n' \
  >"$test_root/ipinfo.json"
NIGHT_LIGHT_LOCATION_FIXTURE="$test_root/ipinfo.json" at 2026-09-27T12:00 detect-location >/dev/null
python3 -c 'import json,sys; l=json.load(open(sys.argv[1]))["location"]; assert l=={"latitude":40.7128,"longitude":-74.006,"place":"New York, New York","timezone":"America/New_York"}, l' \
  "$NIGHT_LIGHT_SCHEDULE_DIR/schedule.json" || fail 'detect-location did not save the detected location'

reset dry-run
before_calls=$(<"$FIXTURE_CALLS")
dry_output=$(at 2026-09-27T19:00 set mode=sunset --dry-run)
[[ "$dry_output" == *'+ write '*'"mode": "sunset"'* && "$dry_output" == *"+ $NIGHT_LIGHT_COMMAND on"* ]] ||
  fail "dry-run did not describe its actions: $dry_output"
[[ ! -e $NIGHT_LIGHT_SCHEDULE_DIR ]] || fail 'dry-run wrote state'
[[ "$(<"$FIXTURE_CALLS")" == "$before_calls" && ! -e $FIXTURE_LIT ]] || fail 'dry-run switched the light'

# --- review regressions: midnight offsets, concurrent updates and failures -----

reset review
python3 - "$schedule" <<'PYTEST' || fail 'schedule review regressions'
import importlib.util, os, time
from datetime import date, timedelta
from unittest.mock import patch
spec = importlib.util.spec_from_file_location("schedule", __import__("sys").argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
os.environ["TZ"] = "Europe/Oslo"
time.tzset()
settings = dict(m.DEFAULTS, mode="sunset", sunrise_offset=-180,
                location={"latitude": 69.65, "longitude": 18.96})
when, light = next(e for e in m.events_for_day(date(2026, 5, 5), settings) if not e[1])
assert when.date() == date(2026, 5, 4)
assert m.desired_state(when + timedelta(seconds=1), settings) is False

# Simulate another caller changing the time during the network lookup.
assert m.main(["set", "on=21:00"]) == 0
def detection():
    assert m.main(["set", "on=22:00"]) == 0
    return {"latitude": 40.7, "longitude": -74.0}
with patch.object(m, "detect_location", side_effect=detection):
    assert m.main(["detect-location"]) == 0
assert m.load_settings()["on"] == "22:00"

# Failure must preserve the last check, return failure, and retry the event.
os.environ["NIGHT_LIGHT_SCHEDULE_NOW"] = "2026-09-27T20:00"
assert m.main(["set", "mode=fixed", "on=21:00", "off=07:00"]) == 0
before = m.last_check_path().read_text()
os.environ["NIGHT_LIGHT_SCHEDULE_NOW"] = "2026-09-27T21:01"
with patch.dict(os.environ, {"FIXTURE_FAIL": "1"}):
    assert m.main(["apply"]) == 1
assert m.last_check_path().read_text() == before
assert m.main(["apply"]) == 0
assert m.light_is_on()
PYTEST

# --- Quickshell panel -----------------------------------------------------------

if command -v quickshell >/dev/null 2>&1; then
  cat >"$test_root/bin/schedule-fixture" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FIXTURE_CALLS"
if [[ $1 == status ]]; then
  printf '%s\n' '{"mode":"sunset","on":"21:00","off":"07:00","sunset_offset":0,"sunrise_offset":0,"location":{"latitude":41.8781,"longitude":-87.6298,"source":"saved"},"today":{"sunrise":"2026-09-27T06:42-05:00","sunset":"2026-09-27T18:40-05:00","kind":"normal"},"light":true,"scheduled":true,"next":{"at":"2026-09-28T06:43-05:00","light":false},"error":null}'
fi
SH
  chmod +x "$test_root/bin/schedule-fixture"
  : >"$FIXTURE_CALLS"
  smoke_log="$test_root/smoke.log"
  NIGHT_LIGHT_SCHEDULE_BIN="$test_root/bin/schedule-fixture" QT_QPA_PLATFORM=offscreen \
    timeout 30 quickshell -p "$qs_root/NightLightSmoke.qml" >"$smoke_log" 2>&1 || true
  if grep -Fq 'FAIL' "$smoke_log"; then
    grep -F 'FAIL' "$smoke_log" >&2
    fail 'NightLightSmoke.qml reported a failing assertion'
  fi
  grep -Fq 'ok: NightLightState logic' "$smoke_log" ||
    { sed -n '1,80p' "$smoke_log" >&2; fail 'NightLightSmoke.qml did not parse and run'; }
  if ! grep -Fxq 'set off=00:03' "$FIXTURE_CALLS" || ! grep -Fxq 'set on=23:57' "$FIXTURE_CALLS"; then
    fail "the panel did not send its time changes: $(<"$FIXTURE_CALLS")"
  fi
  # PanelWindow needs a Wayland backend; the fixture never shows the panel.
  if [[ -n ${WAYLAND_DISPLAY:-} ]]; then
    panel_log="$test_root/panel.log"
    NIGHT_LIGHT_SCHEDULE_BIN="$test_root/bin/schedule-fixture" \
      timeout 30 quickshell -p "$qs_root/NightLightPanelSmoke.qml" >"$panel_log" 2>&1 || true
    grep -Fq 'ok: night-light panel compiles' "$panel_log" ||
      { sed -n '1,80p' "$panel_log" >&2; fail 'NightLightPanel.qml does not compile'; }
  else
    printf 'skip: no Wayland display; NightLightPanel.qml was not compiled\n'
  fi
else
  printf 'skip: quickshell is not installed; ran the backend checks only\n'
fi

printf 'ok: night-light schedule fixtures\n'
