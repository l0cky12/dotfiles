#!/usr/bin/env python3
"""Small, user-local controller for temporary Hyprland desktop modes."""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import tomllib
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Callable

VERSION = "1.0.0"
MODES = ("night-light", "do-not-disturb", "stay-awake", "screensaver-auto")
TRANSIENT = frozenset(MODES[:3])
DURATION_RE = re.compile(r"^([1-9][0-9]*)([smh])$")
LISTENER_RE = re.compile(r"listener\s*\{(.*?)\}", re.DOTALL)


def _local_bin(name: str) -> str:
    """Absolute path to a sibling Stow package's entry point.

    The Hyprland session PATH does not contain ~/.local/bin -- it is exported
    from .zshrc, which the compositor never sources -- so a bare name will not
    resolve for the daemon started from conf/autostart.lua. Fall back to the
    bare name so a system-wide install still works, and so an explicit
    config.toml override is always honoured verbatim.
    """
    candidate = Path.home() / ".local/bin" / name
    return str(candidate) if candidate.exists() else name


class ModeError(RuntimeError):
    pass


@dataclass(frozen=True)
class Config:
    warm_temperature: int = 1000
    normal_temperature: int = 6500
    maximum_duration_seconds: int = 86400
    duration_presets: tuple[str, ...] = ("15m", "30m", "1h")
    reconcile_seconds: float = 2.0
    notification_command: tuple[str, ...] = field(
        default_factory=lambda: (_local_bin("notificationctl"),))
    screensaver_command: tuple[str, ...] = field(
        default_factory=lambda: (_local_bin("ascii-screensaver"),))


def config_path() -> Path:
    return Path(os.environ.get(
        "DESKTOP_MODE_CONFIG",
        Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "desktop-mode/config.toml",
    ))


def runtime_dir() -> Path:
    base = os.environ.get("DESKTOP_MODE_RUNTIME_DIR")
    if base:
        root = Path(base)
    else:
        runtime = os.environ.get("XDG_RUNTIME_DIR")
        if not runtime:
            raise ModeError("XDG_RUNTIME_DIR is unavailable; refusing insecure persistent mode state")
        root = Path(runtime) / "hyprland-desktop/modes"
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    root.chmod(0o700)
    return root


def _argv(value: Any, label: str) -> tuple[str, ...]:
    if not isinstance(value, list) or not value or not all(isinstance(item, str) and item for item in value):
        raise ModeError(f"{label} must be a non-empty array of strings")
    if any("\x00" in item for item in value):
        raise ModeError(f"{label} contains an invalid NUL byte")
    return tuple(value)


def parse_duration(value: str, maximum: int = 86400) -> int:
    match = DURATION_RE.fullmatch(value)
    if not match:
        raise ModeError("duration must be an integer followed by s, m, or h")
    scale = {"s": 1, "m": 60, "h": 3600}[match.group(2)]
    seconds = int(match.group(1)) * scale
    if seconds > maximum:
        raise ModeError(f"duration exceeds configured maximum of {maximum} seconds")
    return seconds


def load_config(path: Path | None = None) -> Config:
    path = path or config_path()
    try:
        with path.open("rb") as stream:
            raw = tomllib.load(stream)
    except FileNotFoundError as error:
        raise ModeError(f"configuration not found: {path}") from error
    except tomllib.TOMLDecodeError as error:
        raise ModeError(f"invalid TOML in {path}: {error}") from error
    known = {field for field in Config.__dataclass_fields__}
    unknown = sorted(set(raw) - known)
    if unknown:
        raise ModeError(f"unknown configuration key(s): {', '.join(unknown)}")
    warm = raw.get("warm_temperature", 1000)
    normal = raw.get("normal_temperature", 6500)
    maximum = raw.get("maximum_duration_seconds", 86400)
    interval = raw.get("reconcile_seconds", 2.0)
    if any(isinstance(value, bool) or not isinstance(value, int) for value in (warm, normal, maximum)):
        raise ModeError("temperatures and maximum_duration_seconds must be integers")
    if not 1000 <= warm <= 20000 or not 1000 <= normal <= 20000 or warm >= normal:
        raise ModeError("temperatures must be 1000..20000K with warm lower than normal")
    if not 1 <= maximum <= 604800:
        raise ModeError("maximum_duration_seconds must be 1..604800")
    if isinstance(interval, bool) or not isinstance(interval, (int, float)) or not 0.2 <= interval <= 60:
        raise ModeError("reconcile_seconds must be 0.2..60")
    presets = raw.get("duration_presets", ["15m", "30m", "1h"])
    if not isinstance(presets, list) or not presets or not all(isinstance(item, str) for item in presets):
        raise ModeError("duration_presets must be a non-empty array of strings")
    for item in presets:
        parse_duration(item, maximum)
    return Config(
        warm_temperature=warm,
        normal_temperature=normal,
        maximum_duration_seconds=maximum,
        duration_presets=tuple(presets),
        reconcile_seconds=float(interval),
        notification_command=_argv(raw.get("notification_command", [_local_bin("notificationctl")]), "notification_command"),
        screensaver_command=_argv(raw.get("screensaver_command", [_local_bin("ascii-screensaver")]), "screensaver_command"),
    )


def timing_report() -> dict[str, Any]:
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    idle_path = Path(os.environ.get(
        "DESKTOP_MODE_HYPRIDLE_CONFIG", config_home / "hypr/hypridle.conf"))
    report: dict[str, Any] = {
        "screensaver_idle_seconds": None,
        "lock_handoff_seconds": None, "hypridle_config": str(idle_path),
        "lock_seconds": None, "warnings": [],
    }
    try:
        text = idle_path.read_text(encoding="utf-8")
        for block in LISTENER_RE.findall(text):
            match = re.search(r"timeout\s*=\s*([0-9]+)", block)
            if not match:
                continue
            if "ascii-screensaver" in block:
                report["screensaver_idle_seconds"] = int(match.group(1))
            if re.search(r"on-timeout\s*=.*loginctl\s+lock-session", block):
                report["lock_seconds"] = int(match.group(1))
        if report["screensaver_idle_seconds"] is None:
            report["warnings"].append("idle screensaver listener was not found")
        if report["lock_seconds"] is None:
            report["warnings"].append("idle lock listener was not found")
    except (OSError, UnicodeError) as error:
        report["warnings"].append(f"idle timing unavailable: {error}")
    return report


def default_state() -> dict[str, Any]:
    return {
        "version": 1,
        "generation": 0,
        "modes": {
            name: {"desired": False, "expires_at": None, "error": None}
            for name in TRANSIENT
        },
    }


def _validate_state(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict) or value.get("version") != 1 or not isinstance(value.get("modes"), dict):
        return default_state()
    clean = default_state()
    generation = value.get("generation", 0)
    clean["generation"] = generation if isinstance(generation, int) and generation >= 0 else 0
    for name in TRANSIENT:
        item = value["modes"].get(name, {})
        if not isinstance(item, dict):
            continue
        clean["modes"][name]["desired"] = item.get("desired") is True
        expires = item.get("expires_at")
        clean["modes"][name]["expires_at"] = float(expires) if isinstance(expires, (int, float)) else None
        error = item.get("error")
        clean["modes"][name]["error"] = str(error)[:500] if error else None
    return clean


class StateStore:
    def __init__(self, root: Path | None = None):
        self.root = root or runtime_dir()
        self.root.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.root.chmod(0o700)
        self.path = self.root / "state.json"
        self.lock_path = self.root / "state.lock"

    def read(self) -> dict[str, Any]:
        try:
            return _validate_state(json.loads(self.path.read_text(encoding="utf-8")))
        except (OSError, UnicodeError, json.JSONDecodeError):
            return default_state()

    def update(self, callback: Callable[[dict[str, Any]], None]) -> dict[str, Any]:
        with self.lock_path.open("a+", encoding="ascii") as lock:
            os.chmod(self.lock_path, 0o600)
            fcntl.flock(lock, fcntl.LOCK_EX)
            state = self.read()
            callback(state)
            state["generation"] += 1
            fd, name = tempfile.mkstemp(prefix=".state.", dir=self.root)
            temporary = Path(name)
            try:
                with os.fdopen(fd, "w", encoding="utf-8") as stream:
                    json.dump(state, stream, sort_keys=True)
                    stream.write("\n")
                    stream.flush()
                    os.fsync(stream.fileno())
                os.chmod(temporary, 0o600)
                os.replace(temporary, self.path)
                directory = os.open(self.root, os.O_RDONLY | os.O_DIRECTORY)
                try:
                    os.fsync(directory)
                finally:
                    os.close(directory)
            finally:
                temporary.unlink(missing_ok=True)
            return state


Runner = Callable[..., subprocess.CompletedProcess[str]]


class Controller:
    def __init__(self, config: Config, store: StateStore | None = None, runner: Runner = subprocess.run):
        self.config = config
        self.store = store or StateStore()
        self.run = runner

    def _command(self, argv: list[str], timeout: float = 5) -> subprocess.CompletedProcess[str]:
        try:
            return self.run(argv, text=True, capture_output=True, timeout=timeout, check=False)
        except (OSError, subprocess.TimeoutExpired) as error:
            return subprocess.CompletedProcess(argv, 127, "", str(error))

    def _night_status(self) -> tuple[bool, bool, str | None]:
        if not shutil.which("hyprctl") or not shutil.which("hyprsunset"):
            return False, False, "hyprctl or hyprsunset is unavailable"
        running = self._command(["pgrep", "-x", "hyprsunset"])
        if running.returncode:
            # Enabling starts hyprsunset, so an absent daemon is simply "off".
            return True, False, None
        result = self._command(["hyprctl", "hyprsunset", "temperature"])
        digits = "".join(char for char in result.stdout if char.isdigit())
        if result.returncode or not digits:
            return True, False, result.stderr.strip() or "hyprsunset temperature is unavailable"
        threshold = (self.config.warm_temperature + self.config.normal_temperature) // 2
        return True, int(digits) <= threshold, None

    def _dnd_status(self) -> tuple[bool, bool, str | None]:
        result = self._command([*self.config.notification_command, "status", "--json"])
        try:
            data = json.loads(result.stdout)
        except json.JSONDecodeError:
            data = {}
        available = result.returncode == 0 and data.get("available") is True
        return available, data.get("dnd") is True, None if available else (result.stderr.strip() or "notification service unavailable")

    def _screen_status(self) -> tuple[bool, bool, str | None]:
        result = self._command([*self.config.screensaver_command, "auto", "status"])
        available = result.returncode == 0
        return available, "automatic=enabled" in result.stdout, None if available else (result.stderr.strip() or "screensaver unavailable")

    def status_one(self, name: str, state: dict[str, Any] | None = None) -> dict[str, Any]:
        if name not in MODES:
            raise ModeError(f"unknown mode: {name}")
        state = state or self.store.read()
        if name == "night-light":
            available, observed, error = self._night_status()
        elif name == "do-not-disturb":
            available, observed, error = self._dnd_status()
        elif name == "screensaver-auto":
            available, observed, error = self._screen_status()
        else:
            item = state["modes"][name]
            available, observed, error = True, bool(item["desired"]), item["error"]
        item = state["modes"].get(name, {})
        desired = observed if name == "screensaver-auto" else bool(item.get("desired", observed))
        return {"name": name, "desired": desired, "observed": observed, "available": available,
                "expires_at": item.get("expires_at"), "error": error}

    def status(self) -> dict[str, Any]:
        state = self.store.read()
        return {"version": 1, "generation": state["generation"], "daemon": daemon_running(self.store.root),
                "settings": {"warm_temperature": self.config.warm_temperature,
                             "normal_temperature": self.config.normal_temperature,
                             "duration_presets": list(self.config.duration_presets)},
                "modes": [self.status_one(name, state) for name in MODES]}

    def _set_backend(self, name: str, enabled: bool) -> None:
        if name == "night-light":
            if not shutil.which("hyprctl") or not shutil.which("hyprsunset"):
                raise ModeError("night light unavailable: hyprctl or hyprsunset is missing")
            if enabled and self._command(["pgrep", "-x", "hyprsunset"]).returncode:
                started = self._command(["setsid", "-f", "hyprsunset"])
                if started.returncode:
                    raise ModeError(started.stderr.strip() or "hyprsunset could not be started")
                for _ in range(20):
                    if self._command(["pgrep", "-x", "hyprsunset"]).returncode == 0:
                        break
                    time.sleep(0.1)
            command = ["hyprctl", "hyprsunset", "temperature",
                       str(self.config.warm_temperature if enabled else self.config.normal_temperature)]
        elif name == "do-not-disturb":
            command = [*self.config.notification_command, "dnd-on" if enabled else "dnd-off"]
        elif name == "screensaver-auto":
            command = [*self.config.screensaver_command, "auto", "enable" if enabled else "disable"]
        else:
            return
        result = self._command(command)
        if result.returncode:
            raise ModeError(result.stderr.strip() or result.stdout.strip() or f"{name} backend failed")

    def set(self, name: str, enabled: bool, duration: str | None = None) -> dict[str, Any]:
        if name not in MODES:
            raise ModeError(f"unknown mode: {name}")
        if duration and (not enabled or name not in TRANSIENT):
            raise ModeError("timed activation is supported only when enabling a transient mode")
        expiry = time.time() + parse_duration(duration, self.config.maximum_duration_seconds) if duration else None
        error: str | None = None
        try:
            self._set_backend(name, enabled)
        except ModeError as caught:
            error = str(caught)
        if name in TRANSIENT:
            def mutate(state: dict[str, Any]) -> None:
                state["modes"][name] = {"desired": enabled, "expires_at": expiry, "error": error}
            self.store.update(mutate)
        signal_daemon(self.store.root)
        if error:
            raise ModeError(error)
        return self.status_one(name)

    def toggle(self, name: str, duration: str | None = None) -> dict[str, Any]:
        return self.set(name, not self.status_one(name)["observed"], duration)

    def expire(self) -> None:
        now = time.time()
        state = self.store.read()
        for name in TRANSIENT:
            item = state["modes"][name]
            if item["desired"] and item["expires_at"] is not None and item["expires_at"] <= now:
                try:
                    self.set(name, False)
                except ModeError:
                    pass

    def reconcile(self) -> None:
        """Restore owned transient backends after a daemon/service restart."""
        state = self.store.read()
        for name in ("night-light", "do-not-disturb"):
            item = state["modes"][name]
            current = self.status_one(name, state)
            error = current["error"]
            if current["available"] and current["observed"] != item["desired"]:
                try:
                    self._set_backend(name, bool(item["desired"]))
                    error = None
                except ModeError as caught:
                    error = str(caught)
            if item.get("error") != error:
                self.store.update(lambda value, n=name, e=error: value["modes"][n].update(error=e))


def pid_path(root: Path) -> Path:
    return root / "daemon.pid"


def daemon_running(root: Path) -> bool:
    try:
        pid = int(pid_path(root).read_text(encoding="ascii"))
        cmdline = Path(f"/proc/{pid}/cmdline").read_bytes()
        return b"desktop_mode" in cmdline or b"desktop-mode" in cmdline
    except (OSError, ValueError):
        return False


def signal_daemon(root: Path) -> bool:
    if not daemon_running(root):
        return False
    try:
        pid = int(pid_path(root).read_text(encoding="ascii"))
        os.kill(pid, signal.SIGHUP)
        return True
    except (OSError, ValueError):
        return False


def daemon(controller: Controller) -> int:
    root = controller.store.root
    lock = (root / "daemon.lock").open("w", encoding="ascii")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("desktop-mode: daemon already running", file=sys.stderr)
        return 0
    pid_path(root).write_text(f"{os.getpid()}\n", encoding="ascii")
    stopped = False
    wake = False
    def stop(_sig: int, _frame: object) -> None:
        nonlocal stopped
        stopped = True
    def reload(_sig: int, _frame: object) -> None:
        nonlocal wake
        wake = True
    old = {sig: signal.signal(sig, stop) for sig in (signal.SIGINT, signal.SIGTERM)}
    old[signal.SIGHUP] = signal.signal(signal.SIGHUP, reload)
    try:
        while not stopped:
            controller.expire()
            controller.reconcile()
            wake = False
            deadline = time.monotonic() + controller.config.reconcile_seconds
            while not stopped and not wake and time.monotonic() < deadline:
                time.sleep(min(0.1, max(0, deadline - time.monotonic())))
        return 0
    finally:
        pid_path(root).unlink(missing_ok=True)
        lock.close()
        for sig, handler in old.items():
            signal.signal(sig, handler)


def human(item: dict[str, Any]) -> str:
    state = "on" if item["observed"] else "off"
    availability = "available" if item["available"] else "unavailable"
    expiry = f" expires={int(item['expires_at'])}" if item.get("expires_at") else ""
    error = f" error={item['error']}" if item.get("error") else ""
    return f"{item['name']}: {state} ({availability}){expiry}{error}"


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(prog="desktop-mode", description="Control temporary desktop modes")
    root.add_argument("--config", type=Path)
    root.add_argument("--version", action="version", version=VERSION)
    commands = root.add_subparsers(dest="command", required=True)
    for command in ("list", "status"):
        child = commands.add_parser(command)
        child.add_argument("mode", nargs="?", choices=MODES)
        child.add_argument("--json", action="store_true")
    for command in ("enable", "toggle"):
        child = commands.add_parser(command)
        child.add_argument("mode", choices=MODES)
        child.add_argument("--for", dest="duration")
        child.add_argument("--json", action="store_true")
    child = commands.add_parser("disable")
    child.add_argument("mode", choices=MODES)
    child.add_argument("--json", action="store_true")
    reset = commands.add_parser("reset")
    group = reset.add_mutually_exclusive_group(required=True)
    group.add_argument("mode", nargs="?", choices=MODES)
    group.add_argument("--all", action="store_true")
    action = commands.add_parser("action")
    action.add_argument("name", choices=("screensaver",))
    commands.add_parser("menu")
    condition = commands.add_parser("condition")
    condition.add_argument("kind", choices=("screensaver", "lock"))
    commands.add_parser("daemon")
    commands.add_parser("watch").add_argument("--json", action="store_true")
    doctor = commands.add_parser("doctor")
    doctor.add_argument("--json", action="store_true")
    return root


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        config = load_config(args.config)
        controller = Controller(config)
        if args.command in ("list", "status"):
            value = controller.status_one(args.mode) if args.mode else controller.status()
            if args.json:
                print(json.dumps(value, sort_keys=True))
            elif args.mode:
                print(human(value))
            else:
                for item in value["modes"]:
                    print(human(item))
            return 0
        if args.command in ("enable", "disable", "toggle"):
            if args.command == "toggle":
                value = controller.toggle(args.mode, args.duration)
            else:
                value = controller.set(args.mode, args.command == "enable", getattr(args, "duration", None))
            print(json.dumps(value, sort_keys=True) if args.json else human(value))
            return 0
        if args.command == "reset":
            names = MODES if args.all else (args.mode,)
            failed = []
            for name in names:
                try:
                    controller.set(name, name == "screensaver-auto")
                except ModeError as error:
                    failed.append(f"{name}: {error}")
            if failed:
                raise ModeError("; ".join(failed))
            print("reset")
            return 0
        if args.command == "condition":
            stay = controller.store.read()["modes"]["stay-awake"]
            stay_awake = stay["desired"] and (
                stay["expires_at"] is None or stay["expires_at"] > time.time())
            if stay_awake:
                return 1
            if args.kind == "screensaver" and not controller.status_one("screensaver-auto")["observed"]:
                return 1
            return 0
        if args.command == "action":
            result = controller._command([*config.screensaver_command, "start"], timeout=86400)
            if result.returncode:
                raise ModeError(result.stderr.strip() or "screensaver failed")
            return 0
        if args.command == "menu":
            executable = shutil.which("quickshell") or shutil.which("qs")
            if not executable:
                raise ModeError("Quickshell is unavailable")
            return subprocess.call([executable, "ipc", "call", "modes", "toggle"])
        if args.command == "daemon":
            return daemon(controller)
        if args.command == "watch":
            previous = None
            while True:
                value = controller.status()
                encoded = json.dumps(value, sort_keys=True)
                if encoded != previous:
                    print(encoded, flush=True)
                    previous = encoded
                time.sleep(config.reconcile_seconds)
        if args.command == "doctor":
            value = {"config": str(args.config or config_path()), "runtime_dir": str(controller.store.root),
                     "daemon": daemon_running(controller.store.root), "configuration": asdict(config),
                     "timing": timing_report(), "status": controller.status()}
            if args.json:
                print(json.dumps(value, indent=2, default=list))
            else:
                print(f"config=ok\nruntime_dir={value['runtime_dir']}\n"
                      f"daemon={'running' if value['daemon'] else 'stopped'}")
                timing = value["timing"]
                print(f"screensaver_idle_seconds={timing['screensaver_idle_seconds']}\n"
                      f"lock_handoff_seconds={timing['lock_handoff_seconds']}\n"
                      f"lock_seconds={timing['lock_seconds']}")
                for warning in timing["warnings"]:
                    print(f"warning={warning}")
                for item in value["status"]["modes"]:
                    print(human(item))
            return 0
        return 2
    except (ModeError, OSError, ValueError) as error:
        # A broken optional mode configuration must never weaken the security
        # boundary. Hypridle interprets zero as permission to lock.
        if getattr(args, "command", None) == "condition" and getattr(args, "kind", None) == "lock":
            print(f"desktop-mode: lock allowed despite condition error: {error}", file=sys.stderr)
            return 0
        print(f"desktop-mode: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
