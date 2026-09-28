#!/usr/bin/env python3
"""Schedule the night-light shader by clock time or by local sunset/sunrise.

    night-light-schedule.py status [--json]
    night-light-schedule.py apply [--force] [--dry-run]
    night-light-schedule.py set KEY=VALUE... [--dry-run]
    night-light-schedule.py set-location LAT LON [PLACE] [--dry-run]
    night-light-schedule.py detect-location [--dry-run]

Settings live in $XDG_STATE_HOME/night-light/schedule.json, outside the repo,
because the Quickshell panel rewrites them on every click. The same file holds
the location the weather widget reads.

`apply` is edge-triggered: it only switches the light when a scheduled on/off
time has passed since the previous run. A manual Super+Ctrl+N therefore holds
until the next scheduled change instead of being undone a minute later. The
systemd timer runs it every minute, and a missed run (suspend, reboot) is
caught up on the next one. `--force` sets the scheduled state now; `set` and
`set-location` use it so a new schedule takes effect immediately.

Sunrise and sunset come from the sunrise equation (NOAA/Meeus approximation,
within a minute or two), so no network or extra package is needed after the
location is known. Only `detect-location` touches the network.
"""

from __future__ import annotations

import json
import fcntl
import math
import os
import re
import subprocess
import sys
import tempfile
import urllib.request
from datetime import date, datetime, time, timedelta
from contextlib import contextmanager
from pathlib import Path
from typing import Any

MODES = ("off", "fixed", "sunset")
DEFAULTS: dict[str, Any] = {
    "mode": "off",
    "on": "21:00",
    "off": "07:00",
    "sunset_offset": 0,
    "sunrise_offset": 0,
}
# Offsets beyond three hours stop meaning "around sunset".
MAX_OFFSET = 180
# Enough to cover a long suspend without walking years of days.
MAX_CATCHUP_DAYS = 7
LOCATION_URL = "https://ipinfo.io/json"


class ScheduleError(Exception):
    pass


def state_dir() -> Path:
    base = os.environ.get("XDG_STATE_HOME") or os.path.join(os.environ["HOME"], ".local/state")
    return Path(os.environ.get("NIGHT_LIGHT_SCHEDULE_DIR", os.path.join(base, "night-light")))


def settings_path() -> Path:
    return state_dir() / "schedule.json"


def last_check_path() -> Path:
    return state_dir() / "last-check"


def weather_fallback_path() -> Path:
    config = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.environ["HOME"], ".config")
    return Path(os.environ.get("NIGHT_LIGHT_WEATHER_FILE",
                               os.path.join(config, "quickshell/weather.json")))


def night_light_command() -> str:
    return os.environ.get("NIGHT_LIGHT_COMMAND",
                          str(Path(__file__).resolve().with_name("night-light.sh")))


def now() -> datetime:
    # Tests pin the clock; the value is local time with an explicit offset.
    fixed = os.environ.get("NIGHT_LIGHT_SCHEDULE_NOW")
    if fixed:
        return datetime.fromisoformat(fixed).astimezone()
    return datetime.now().astimezone()


# --- settings -----------------------------------------------------------------


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text())
    except (OSError, ValueError):
        return {}
    return value if isinstance(value, dict) else {}


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=path.name + ".")
    with os.fdopen(fd, "w") as handle:
        json.dump(value, handle, indent=2)
        handle.write("\n")
    os.replace(temporary, path)


@contextmanager
def settings_lock(read_only: bool):
    if read_only:
        yield
        return
    state_dir().mkdir(parents=True, exist_ok=True)
    with (state_dir() / "lock").open("a") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        yield


def parse_clock(value: str) -> time:
    match = re.fullmatch(r"([01]?\d|2[0-3]):([0-5]\d)", str(value).strip())
    if not match:
        raise ScheduleError(f"invalid time {value!r}; use HH:MM")
    return time(int(match.group(1)), int(match.group(2)))


def parse_offset(value: Any) -> int:
    try:
        minutes = int(value)
    except (TypeError, ValueError):
        raise ScheduleError(f"invalid offset {value!r}; use whole minutes") from None
    if abs(minutes) > MAX_OFFSET:
        raise ScheduleError(f"offset {minutes} is outside ±{MAX_OFFSET} minutes")
    return minutes


def valid_location(value: Any) -> dict[str, Any] | None:
    if not isinstance(value, dict):
        return None
    try:
        latitude = float(value["latitude"])
        longitude = float(value["longitude"])
    except (KeyError, TypeError, ValueError):
        return None
    if not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
        return None
    location: dict[str, Any] = {"latitude": latitude, "longitude": longitude}
    for key in ("place", "timezone"):
        if isinstance(value.get(key), str) and value[key]:
            location[key] = value[key]
    return location


def load_settings() -> dict[str, Any]:
    stored = read_json(settings_path())
    settings = dict(DEFAULTS)
    if stored.get("mode") in MODES:
        settings["mode"] = stored["mode"]
    for key in ("on", "off"):
        try:
            settings[key] = parse_clock(stored[key]).strftime("%H:%M")
        except (KeyError, ScheduleError):
            pass
    for key in ("sunset_offset", "sunrise_offset"):
        try:
            settings[key] = parse_offset(stored[key])
        except (KeyError, ScheduleError):
            pass
    settings["location"] = valid_location(stored.get("location"))
    return settings


def stored_settings(settings: dict[str, Any]) -> dict[str, Any]:
    value = {key: settings[key] for key in DEFAULTS}
    if settings.get("location"):
        value["location"] = settings["location"]
    return value


def effective_location(settings: dict[str, Any]) -> dict[str, Any] | None:
    if settings.get("location"):
        return dict(settings["location"], source="saved")
    fallback = valid_location(read_json(weather_fallback_path()))
    if fallback:
        return dict(fallback, source="weather default")
    return None


# --- sun ----------------------------------------------------------------------


def sun_times(day: date, latitude: float, longitude: float) -> tuple[datetime | None, datetime | None, str]:
    """Return local (sunrise, sunset, kind) for `day`.

    kind is "normal", "polar-day" (sun never sets) or "polar-night".
    """
    radians = math.radians
    # Julian day number of `day` at 12:00 UTC, relative to J2000.
    n = day.toordinal() - date(2000, 1, 1).toordinal()
    mean_noon = n - longitude / 360.0
    anomaly = (357.5291 + 0.98560028 * mean_noon) % 360
    centre = (1.9148 * math.sin(radians(anomaly))
              + 0.0200 * math.sin(radians(2 * anomaly))
              + 0.0003 * math.sin(radians(3 * anomaly)))
    ecliptic = (anomaly + centre + 180 + 102.9372) % 360
    transit = (2451545.0 + mean_noon + 0.0053 * math.sin(radians(anomaly))
               - 0.0069 * math.sin(radians(2 * ecliptic)))
    declination = math.asin(math.sin(radians(ecliptic)) * math.sin(radians(23.4397)))
    cos_hour = ((math.sin(radians(-0.833)) - math.sin(radians(latitude)) * math.sin(declination))
                / (math.cos(radians(latitude)) * math.cos(declination)))
    if cos_hour < -1:
        return None, None, "polar-day"
    if cos_hour > 1:
        return None, None, "polar-night"
    half_day = math.degrees(math.acos(cos_hour)) / 360.0

    def local(julian: float) -> datetime:
        return datetime.fromtimestamp((julian - 2440587.5) * 86400).astimezone()

    return local(transit - half_day), local(transit + half_day), "normal"


# --- schedule -----------------------------------------------------------------


def events_for_day(day: date, settings: dict[str, Any]) -> list[tuple[datetime, bool]]:
    """Scheduled (time, light_on) switches on local `day`, unordered."""
    mode = settings["mode"]
    if mode == "fixed":
        on_clock, off_clock = parse_clock(settings["on"]), parse_clock(settings["off"])
        if on_clock == off_clock:
            return []
        return [(datetime.combine(day, on_clock).astimezone(), True),
                (datetime.combine(day, off_clock).astimezone(), False)]
    if mode == "sunset":
        location = effective_location(settings)
        if not location:
            return []
        sunrise, sunset, _ = sun_times(day, location["latitude"], location["longitude"])
        if sunrise is None or sunset is None:
            return []
        return [(sunset + timedelta(minutes=settings["sunset_offset"]), True),
                (sunrise + timedelta(minutes=settings["sunrise_offset"]), False)]
    return []


def desired_state(moment: datetime, settings: dict[str, Any]) -> bool | None:
    """What the schedule wants at `moment`: the most recent switch wins."""
    if settings["mode"] == "sunset":
        location = effective_location(settings)
        if location:
            _, _, kind = sun_times(moment.date(), location["latitude"], location["longitude"])
            if kind != "normal":
                return kind == "polar-night"
    latest: tuple[datetime, bool] | None = None
    for offset in range(-2, 2):
        for when, light in events_for_day(moment.date() + timedelta(days=offset), settings):
            if when <= moment and (latest is None or when > latest[0]):
                latest = (when, light)
    return latest[1] if latest else None


def events_between(start: datetime, end: datetime, settings: dict[str, Any]) -> list[tuple[datetime, bool]]:
    first = max(start.date(), end.date() - timedelta(days=MAX_CATCHUP_DAYS)) - timedelta(days=1)
    found = []
    day = first
    while day <= end.date() + timedelta(days=1):
        found.extend(event for event in events_for_day(day, settings) if start < event[0] <= end)
        day += timedelta(days=1)
    return sorted(found)


def next_event(moment: datetime, settings: dict[str, Any]) -> tuple[datetime, bool] | None:
    upcoming = events_between(moment, moment + timedelta(days=2), settings)
    return upcoming[0] if upcoming else None


# --- light --------------------------------------------------------------------


def light_is_on() -> bool:
    result = subprocess.run([night_light_command(), "status"], text=True,
                            capture_output=True, check=False)
    return result.stdout.startswith("night-light: on")


def set_light(on: bool, dry_run: bool) -> None:
    argv = [night_light_command(), "on" if on else "off"]
    if dry_run:
        print("+ " + " ".join(argv))
        return
    # The shader state is written before Hyprland is reloaded, so a failed
    # reload (no compositor yet) still takes effect at the next Hyprland start.
    result = subprocess.run(argv, text=True, capture_output=True, check=False)
    if result.returncode:
        raise ScheduleError(f"{' '.join(argv)} failed: {result.stderr.strip()}")


def read_last_check() -> datetime | None:
    try:
        return datetime.fromisoformat(last_check_path().read_text().strip()).astimezone()
    except (OSError, ValueError):
        return None


def write_last_check(moment: datetime, dry_run: bool) -> None:
    if dry_run:
        return
    path = last_check_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(moment.isoformat() + "\n")


def apply(settings: dict[str, Any], force: bool, dry_run: bool) -> str:
    """Switch the light if the schedule says so. Returns what happened."""
    moment = now()
    previous = read_last_check()
    def completed(message: str) -> str:
        write_last_check(moment, dry_run)
        return message

    if settings["mode"] == "off":
        return completed("schedule off")
    if force:
        due = True
    elif previous is None or previous > moment:
        # First run, or the clock went backwards: start watching from now
        # rather than guessing which switches were missed.
        due = False
    else:
        due = bool(events_between(previous, moment, settings))
    if not due:
        return completed("no change due")
    wanted = desired_state(moment, settings)
    if wanted is None:
        return completed("no scheduled state")
    if light_is_on() == wanted:
        return completed("already " + ("on" if wanted else "off"))
    set_light(wanted, dry_run)
    return completed("switched " + ("on" if wanted else "off"))


# --- commands -----------------------------------------------------------------


def status(settings: dict[str, Any]) -> dict[str, Any]:
    moment = now()
    location = effective_location(settings)
    today: dict[str, Any] = {"sunrise": None, "sunset": None, "kind": None}
    if location:
        sunrise, sunset, kind = sun_times(moment.date(), location["latitude"], location["longitude"])
        today = {"sunrise": sunrise.isoformat(timespec="minutes") if sunrise else None,
                 "sunset": sunset.isoformat(timespec="minutes") if sunset else None,
                 "kind": kind}
    upcoming = next_event(moment, settings)
    error = None
    if settings["mode"] == "sunset" and not location:
        error = "Set a location to schedule by sunset"
    return {
        "mode": settings["mode"],
        "on": settings["on"],
        "off": settings["off"],
        "sunset_offset": settings["sunset_offset"],
        "sunrise_offset": settings["sunrise_offset"],
        "location": location,
        "today": today,
        "light": light_is_on(),
        "scheduled": desired_state(moment, settings),
        "next": ({"at": upcoming[0].isoformat(timespec="minutes"),
                  "light": upcoming[1]} if upcoming else None),
        "error": error,
    }


def command_set(settings: dict[str, Any], pairs: list[str]) -> dict[str, Any]:
    if not pairs:
        raise ScheduleError("set needs KEY=VALUE arguments")
    updated = dict(settings)
    for pair in pairs:
        key, sep, value = pair.partition("=")
        if not sep:
            raise ScheduleError(f"expected KEY=VALUE, got {pair!r}")
        if key == "mode":
            if value not in MODES:
                raise ScheduleError(f"mode must be one of {', '.join(MODES)}")
            updated["mode"] = value
        elif key in ("on", "off"):
            updated[key] = parse_clock(value).strftime("%H:%M")
        elif key in ("sunset_offset", "sunrise_offset"):
            updated[key] = parse_offset(value)
        else:
            raise ScheduleError(f"unknown setting {key!r}")
    return updated


def parse_location(latitude: str, longitude: str, place: str | None) -> dict[str, Any]:
    location = valid_location({"latitude": latitude, "longitude": longitude, "place": place or ""})
    if not location:
        raise ScheduleError("latitude must be -90..90 and longitude -180..180")
    return location


def detect_location() -> dict[str, Any]:
    fixture = os.environ.get("NIGHT_LIGHT_LOCATION_FIXTURE")
    try:
        if fixture:
            data = json.loads(Path(fixture).read_text())
        else:
            request = urllib.request.Request(LOCATION_URL, headers={"Accept": "application/json"})
            with urllib.request.urlopen(request, timeout=10) as response:
                data = json.loads(response.read().decode())
        latitude, longitude = str(data["loc"]).split(",", 1)
    except (OSError, ValueError, KeyError) as error:
        raise ScheduleError(f"could not detect location: {error}") from None
    place = ", ".join(part for part in (data.get("city"), data.get("region")) if part)
    location = parse_location(latitude, longitude, place)
    if isinstance(data.get("timezone"), str) and data["timezone"]:
        location["timezone"] = data["timezone"]
    return location


def usage() -> str:
    return (__doc__ or "").strip().split("\n\n")[0]


def main(argv: list[str]) -> int:
    dry_run = "--dry-run" in argv
    force = "--force" in argv
    as_json = "--json" in argv
    args = [arg for arg in argv if arg not in ("--dry-run", "--force", "--json")]
    if not args or args[0] in ("-h", "--help"):
        print(usage())
        return 0 if args else 2
    command, rest = args[0], args[1:]
    try:
        # Network lookup must finish before taking the lock and loading the
        # latest settings, so it cannot overwrite edits made during the lookup.
        detected = detect_location() if command == "detect-location" else None
        with settings_lock(dry_run or command == "status"):
            settings = load_settings()
            if command == "status":
                value = status(settings)
                if as_json:
                    print(json.dumps(value))
                else:
                    print(f"mode: {value['mode']}")
                    print(f"light: {'on' if value['light'] else 'off'}")
                    if value["next"]:
                        print(f"next: {'on' if value['next']['light'] else 'off'} at {value['next']['at']}")
                return 0
            if command == "apply":
                print(apply(settings, force, dry_run))
                return 0
            if command in ("set", "set-location", "detect-location"):
                if command == "set":
                    updated = command_set(settings, rest)
                elif command == "set-location":
                    if len(rest) not in (2, 3):
                        raise ScheduleError("usage: set-location LAT LON [PLACE]")
                    updated = dict(settings, location=parse_location(*rest[:2], rest[2] if len(rest) == 3 else None))
                else:
                    updated = dict(settings, location=detected)
                if dry_run:
                    print("+ write " + str(settings_path()) + ": " + json.dumps(stored_settings(updated)))
                else:
                    write_json(settings_path(), stored_settings(updated))
                print(apply(updated, force=True, dry_run=dry_run))
                return 0
    except ScheduleError as error:
        print(f"night-light-schedule: {error}", file=sys.stderr)
        return 1
    print(usage(), file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
