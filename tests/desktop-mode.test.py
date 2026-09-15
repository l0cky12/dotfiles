#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "modes/.local/share/desktop-mode"
WRAPPER = ROOT / "modes/.local/bin/desktop-mode"
sys.path.insert(0, str(LIB))

from desktop_mode import (Config, Controller, ModeError, StateStore, default_state,  # noqa: E402
                          load_config, parse_duration, timing_report)


class DesktopModeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = Path(tempfile.mkdtemp(prefix="desktop-mode-test."))
        self.addCleanup(shutil.rmtree, self.temp, True)
        self.config_path = self.temp / "config.toml"
        self.config_path.write_text(
            'warm_temperature = 1000\nnormal_temperature = 6500\n'
            'maximum_duration_seconds = 3600\nduration_presets = ["15m", "30m", "1h"]\n'
            'reconcile_seconds = 0.2\nnotification_command = ["notify-fixture"]\n'
            'screensaver_command = ["screen-fixture"]\n', encoding="utf-8")
        self.config = load_config(self.config_path)
        self.store = StateStore(self.temp / "runtime")

    def test_config_and_duration_validation(self) -> None:
        self.assertEqual(self.config.warm_temperature, 1000)
        self.assertEqual(parse_duration("15m", 3600), 900)
        with self.assertRaisesRegex(ModeError, "integer followed"):
            parse_duration("forever")
        with self.assertRaisesRegex(ModeError, "exceeds"):
            parse_duration("2h", 3600)
        invalid = self.temp / "bad.toml"
        invalid.write_text("unknown = true\n", encoding="utf-8")
        with self.assertRaisesRegex(ModeError, "unknown configuration"):
            load_config(invalid)

    def test_atomic_state_permissions_and_validation(self) -> None:
        state = self.store.update(lambda value: value["modes"]["stay-awake"].update(desired=True))
        self.assertTrue(state["modes"]["stay-awake"]["desired"])
        self.assertEqual(self.store.path.stat().st_mode & 0o777, 0o600)
        self.store.path.write_text("not json", encoding="utf-8")
        self.assertEqual(self.store.read(), default_state())

    def test_concurrent_state_updates_are_serialized(self) -> None:
        threads = [threading.Thread(target=lambda: self.store.update(lambda _value: None))
                   for _ in range(20)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        self.assertEqual(self.store.read()["generation"], 20)

    def test_stay_awake_is_idempotent_and_timed(self) -> None:
        controller = Controller(self.config, self.store)
        first = controller.set("stay-awake", True, "15m")
        second = controller.set("stay-awake", True, "15m")
        self.assertTrue(first["observed"])
        self.assertTrue(second["observed"])
        self.assertGreater(second["expires_at"], time.time())
        controller.set("stay-awake", False)
        self.assertFalse(controller.status_one("stay-awake")["observed"])

    def test_expiry_disables_transient_mode(self) -> None:
        controller = Controller(self.config, self.store)
        self.store.update(lambda value: value["modes"]["stay-awake"].update(
            desired=True, expires_at=time.time() - 1))
        controller.expire()
        self.assertFalse(controller.status_one("stay-awake")["observed"])

    def test_backend_commands_are_argv_and_observed(self) -> None:
        calls = []
        def runner(argv, **_kwargs):
            calls.append(argv)
            if argv[-2:] == ["status", "--json"]:
                return subprocess.CompletedProcess(argv, 0, json.dumps({"available": True, "dnd": True}), "")
            if argv[-2:] == ["auto", "status"]:
                return subprocess.CompletedProcess(argv, 0, "automatic=enabled\n", "")
            return subprocess.CompletedProcess(argv, 0, "", "")
        controller = Controller(self.config, self.store, runner)
        self.assertTrue(controller.status_one("do-not-disturb")["observed"])
        self.assertTrue(controller.status_one("screensaver-auto")["observed"])
        controller.set("do-not-disturb", False)
        self.assertIn(["notify-fixture", "dnd-off"], calls)

    def test_failed_backend_records_desired_and_error(self) -> None:
        def runner(argv, **_kwargs):
            return subprocess.CompletedProcess(argv, 2, "", "fixture failure")
        controller = Controller(self.config, self.store, runner)
        with self.assertRaisesRegex(ModeError, "fixture failure"):
            controller.set("do-not-disturb", True)
        item = self.store.read()["modes"]["do-not-disturb"]
        self.assertTrue(item["desired"])
        self.assertEqual(item["error"], "fixture failure")

    def test_stopped_hyprsunset_is_off_not_an_error(self) -> None:
        def runner(argv, **_kwargs):
            return subprocess.CompletedProcess(argv, 1, "", "")  # pgrep: no match
        controller = Controller(self.config, self.store, runner)
        with mock.patch("desktop_mode.shutil.which", return_value="/usr/bin/fixture"):
            item = controller.status_one("night-light")
        self.assertTrue(item["available"])
        self.assertFalse(item["observed"])
        self.assertIsNone(item["error"])

    def test_probed_mode_error_clears_when_backend_recovers(self) -> None:
        def runner(argv, **_kwargs):
            if argv[-2:] == ["status", "--json"]:
                return subprocess.CompletedProcess(argv, 0, json.dumps({"available": True, "dnd": False}), "")
            return subprocess.CompletedProcess(argv, 0, "", "")
        controller = Controller(self.config, self.store, runner)
        self.store.update(lambda value: value["modes"]["do-not-disturb"].update(
            error="notification service unavailable"))
        self.assertIsNone(controller.status_one("do-not-disturb")["error"])
        controller.reconcile()
        self.assertIsNone(self.store.read()["modes"]["do-not-disturb"]["error"])

    def test_reconcile_restores_desired_backend_state(self) -> None:
        calls = []
        def runner(argv, **_kwargs):
            calls.append(argv)
            if argv[-2:] == ["status", "--json"]:
                return subprocess.CompletedProcess(argv, 0, json.dumps({"available": True, "dnd": False}), "")
            return subprocess.CompletedProcess(argv, 0, "", "")
        controller = Controller(self.config, self.store, runner)
        self.store.update(lambda value: value["modes"]["do-not-disturb"].update(desired=True))
        with mock.patch("desktop_mode.shutil.which", return_value=None):
            controller.reconcile()
        self.assertIn(["notify-fixture", "dnd-on"], calls)

    def test_lock_condition_honors_active_and_expired_timer(self) -> None:
        env = os.environ.copy()
        env.update({"DESKTOP_MODE_CONFIG": str(self.config_path),
                    "DESKTOP_MODE_RUNTIME_DIR": str(self.store.root)})
        self.store.update(lambda value: value["modes"]["stay-awake"].update(
            desired=True, expires_at=time.time() + 60))
        active = subprocess.run([str(WRAPPER), "condition", "lock"], env=env)
        self.assertEqual(active.returncode, 1)
        self.store.update(lambda value: value["modes"]["stay-awake"].update(
            desired=True, expires_at=time.time() - 1))
        expired = subprocess.run([str(WRAPPER), "condition", "lock"], env=env)
        self.assertEqual(expired.returncode, 0)

    def test_daemon_signal_cleanup(self) -> None:
        env = os.environ.copy()
        runtime = self.temp / "daemon-runtime"
        env.update({"DESKTOP_MODE_CONFIG": str(self.config_path),
                    "DESKTOP_MODE_RUNTIME_DIR": str(runtime)})
        process = subprocess.Popen([str(WRAPPER), "daemon"], env=env,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        pidfile = runtime / "daemon.pid"
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline and not pidfile.exists():
            time.sleep(0.02)
        self.assertTrue(pidfile.exists())
        process.terminate()
        stdout, stderr = process.communicate(timeout=4)
        self.assertEqual(process.returncode, 0, stderr)
        self.assertFalse(pidfile.exists())

    def test_lock_condition_fails_closed_when_config_is_missing(self) -> None:
        env = os.environ.copy()
        env.update({"DESKTOP_MODE_CONFIG": str(self.temp / "missing.toml"),
                    "DESKTOP_MODE_RUNTIME_DIR": str(self.temp / "condition")})
        result = subprocess.run([str(WRAPPER), "condition", "lock"], env=env,
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("lock allowed", result.stderr)

    def test_cli_manual_and_automatic_are_separate(self) -> None:
        fixture = self.temp / "screen-fixture"
        log = self.temp / "calls"
        fixture.write_text("#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$MODE_LOG\"\n"
                           "[ \"$*\" = 'auto status' ] && printf 'automatic=enabled\\n'\n"
                           "exit 0\n", encoding="utf-8")
        fixture.chmod(0o755)
        config = self.config_path.read_text(encoding="utf-8").replace(
            '["screen-fixture"]', f'["{fixture}"]')
        self.config_path.write_text(config, encoding="utf-8")
        env = os.environ.copy()
        env.update({"DESKTOP_MODE_CONFIG": str(self.config_path),
                    "DESKTOP_MODE_RUNTIME_DIR": str(self.temp / "cli-runtime"),
                    "MODE_LOG": str(log)})
        manual = subprocess.run([str(WRAPPER), "action", "screensaver"], env=env)
        automatic = subprocess.run([str(WRAPPER), "disable", "screensaver-auto"], env=env,
                                   text=True, capture_output=True)
        self.assertEqual(manual.returncode, 0)
        self.assertEqual(automatic.returncode, 0, automatic.stderr)
        self.assertEqual(log.read_text(encoding="utf-8").splitlines(),
                         ["start", "auto disable", "auto status"])

    def test_hypridle_screensaver_and_lock_timing_report(self) -> None:
        idle = self.temp / "hypridle.conf"
        idle.write_text(
            "listener {\n timeout = 180\n on-timeout = ascii-screensaver\n}\n"
            "listener {\n timeout = 300\n on-timeout = loginctl lock-session\n}\n",
            encoding="utf-8")
        with mock.patch.dict(os.environ, {"DESKTOP_MODE_HYPRIDLE_CONFIG": str(idle)}):
            report = timing_report()
        self.assertEqual(report["screensaver_idle_seconds"], 180)
        self.assertEqual(report["lock_seconds"], 300)
        self.assertEqual(report["warnings"], [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
