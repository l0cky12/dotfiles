#!/usr/bin/env python3
"""Fixture tests for Lua reconciliation, caching, and palette records."""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


REPO = Path(__file__).resolve().parent.parent
COLLECTOR = REPO / "hypr/.config/hypr/scripts/keybinds-collector"
REPLAY = REPO / "hypr/.config/hypr/scripts/keybinds-replay.lua"
KEYBINDS_STATE = REPO / "quickshell/.config/quickshell/KeybindsState.qml"


def invoke(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run([str(COLLECTOR), *args], check=True, text=True,
                          capture_output=True)


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value), encoding="utf-8")


def main() -> None:
    qml = KEYBINDS_STATE.read_text(encoding="utf-8")
    lua_activation = re.search(
        r'else if \(r\.dispatcher === "lua"\) \{\s*'
        r'actionProc\.command = \["hyprctl", "([^"]+)", r\.arg\]', qml)
    assert lua_activation and lua_activation.group(1) == "eval", \
        "reconciled lua rows must activate through hyprctl eval"
    print("ok: reconciled Lua rows activate through hyprctl eval")

    with tempfile.TemporaryDirectory(prefix="keybinds-collector-test.") as directory:
        root = Path(directory)
        config = root / "hypr"
        (config / "conf").mkdir(parents=True)
        (config / "conf/variables.lua").write_text(
            'return { terminal = "fixture-terminal" }\n', encoding="utf-8")
        (config / "conf/keybindings.lua").write_text(
            """local cfg = require("conf/variables")
local function bind(keys, description, dispatcher)
  hl.bind(keys, dispatcher, { description = description })
end
bind("SUPER + Return", "terminal", hl.dsp.exec_cmd(cfg.terminal))
bind("SUPER + A", "duplicate label", hl.dsp.exec_cmd("first-action"))
bind("SUPER + B", "duplicate label", hl.dsp.exec_cmd("second-action"))
bind("SUPER + code:67", "function key help", hl.dsp.exec_cmd("show-help"))
bind("SUPER + N", "night light", function()
  hl.dispatch(hl.dsp.exec_cmd("night-light toggle"))
end)
bind("SUPER + Q", "close window", hl.dsp.window.close())
""", encoding="utf-8")
        binds_path = root / "binds.json"
        binds = [
            {"modmask": 64, "key": "Return", "keycode": 0,
             "description": "terminal", "dispatcher": "__lua", "arg": "101", "mouse": False},
            {"modmask": 64, "key": "A", "keycode": 0,
             "description": "duplicate label", "dispatcher": "__lua", "arg": "102", "mouse": False},
            {"modmask": 64, "key": "B", "keycode": 0,
             "description": "duplicate label", "dispatcher": "__lua", "arg": "103", "mouse": False},
            {"modmask": 64, "key": "SUPER + code:67", "keycode": 67,
             "description": "function key help", "dispatcher": "__lua", "arg": "104", "mouse": False},
            {"modmask": 64, "key": "N", "keycode": 0,
             "description": "night light", "dispatcher": "__lua", "arg": "105", "mouse": False},
            {"modmask": 64, "key": "Q", "keycode": 0,
             "description": "close window", "dispatcher": "__lua", "arg": "106", "mouse": False},
        ]
        write_json(binds_path, binds)
        keymap = root / "keymap.txt"
        keymap.write_text("fixture-us\n", encoding="utf-8")
        cache = root / "cache"

        # This is the regression: the previous __lua|description identity has
        # one value, while reconciled dispatcher|arg identities remain two.
        old_identities = {f"{row['dispatcher']}|{row['description']}" for row in binds[1:3]}
        assert len(old_identities) == 1, "fixture no longer demonstrates the old merge failure"

        run_args = ("--binds-json", str(binds_path), "--keymap-summary", str(keymap),
                    "--keybindings", str(config / "conf/keybindings.lua"),
                    "--cache-home", str(cache), "--debug")
        first = invoke(*run_args)
        records = json.loads(first.stdout)
        assert "cache rebuild:" in first.stderr
        dynamic = records[:len(binds)]
        assert [(row["dispatcher"], row["arg"]) for row in dynamic] == [
            ("exec", "fixture-terminal"), ("exec", "first-action"),
            ("exec", "second-action"), ("exec", "show-help"),
            ("exec", "night-light toggle"), ("killactive", "")]
        new_identities = {f"{row['dispatcher']}|{row['arg']}" for row in dynamic[1:3]}
        assert len(new_identities) == 2, "reconciliation still fuses different actions"
        assert dynamic[3]["key"] == "code:67" and dynamic[3]["key_label"] == "F1"
        assert {(row["description"], row["dispatcher"]) for row in records[-2:]} == {
            ("copy URL from web app", "sendshortcut"),
            ("download video from web app", "sendshortcut")}

        second = invoke(*run_args)
        assert "cache hit:" in second.stderr and "cache rebuild:" not in second.stderr
        first_cache = next(cache.glob("keybindings-*.records"))

        binds.append({"modmask": 0, "key": "F12", "keycode": 0,
                      "description": "fixture added bind", "dispatcher": "exec",
                      "arg": "added", "mouse": False})
        write_json(binds_path, binds)
        changed = invoke(*run_args)
        assert "cache rebuild:" in changed.stderr
        caches = list(cache.glob("keybindings-*.records"))
        assert len(caches) == 2 and any(path != first_cache for path in caches), \
            "cache hash did not change with binds input"
        changed_cache = next(path for path in caches if path != first_cache)

        newest = max(caches, key=lambda path: path.stat().st_mtime_ns)
        newest.write_text("not json\n", encoding="utf-8")
        repaired = invoke(*run_args)
        assert "cache rebuild:" in repaired.stderr
        assert isinstance(json.loads(newest.read_text(encoding="utf-8")), list)

        dry_run = invoke("--binds-json", str(binds_path), "--keymap-summary", str(keymap),
                         "--keybindings", str(config / "conf/keybindings.lua"),
                         "--dry-run", "--limit", "30")
        assert "fixture-terminal" in dry_run.stdout
        print("ok: old description-only identity reproduces merge (expected failure mode)")
        print("ok: reconciled action identity keeps different actions separate")
        print("ok: Lua function bind recovered real exec dispatcher and argument")
        print("ok: close-window replay retains the killactive denylist identity")
        print(f"ok: cache miss rebuilt {first_cache.name}")
        print(f"ok: cache hit reused {first_cache.name} without replay rebuild")
        print(f"ok: binds change moved hash to {changed_cache.name}")
        print("ok: corrupt cache triggered live fixture rebuild")
        print("ok: static bindings and keycode fallback")
        print("--- first 30 prioritized fixture rows ---")
        print(dry_run.stdout, end="")

        # Exercise the repository's real Lua file as the fixture replay source,
        # then feed an equivalent synthetic hyprctl JSON snapshot back through
        # the complete collector for a useful 30-row ordering artifact.
        runner = next((name for name in ("lua", "lua5.4", "lua5.3")
                       if shutil.which(name)), None)
        actual_config = REPO / "hypr/.config/hypr"
        command = ([runner, str(REPLAY), str(actual_config / "conf/keybindings.lua"),
                    str(actual_config)] if runner else
                   [shutil.which("nvim"), "--headless", "-u", "NONE", "-l", str(REPLAY),
                    str(actual_config / "conf/keybindings.lua"), str(actual_config)])
        environment = os.environ.copy()
        environment["NVIM_LOG_FILE"] = os.devnull
        replayed = json.loads(subprocess.run(command, check=True, text=True,
                                             capture_output=True,
                                             env=environment).stdout)
        repository_binds = []
        for index, row in enumerate(replayed, 1000):
            if not row["description"]:
                continue
            key = row["key"]
            keycode = int(key.removeprefix("code:")) if key.startswith("code:") else 0
            repository_binds.append({
                "modmask": row["modmask"], "key": "" if keycode else key,
                "keycode": keycode, "description": row["description"],
                "dispatcher": "__lua", "arg": str(index), "mouse": False,
            })
        repository_binds_path = root / "repository-binds.json"
        write_json(repository_binds_path, repository_binds)
        repository_rows = invoke(
            "--binds-json", str(repository_binds_path),
            "--keymap-summary", str(keymap),
            "--keybindings", str(actual_config / "conf/keybindings.lua"),
            "--dry-run", "--limit", "30")
        assert len(repository_rows.stdout.splitlines()) == 30
        print("--- first 30 prioritized repository-fixture rows ---")
        print(repository_rows.stdout, end="")

    if shutil.which("qmllint"):
        subprocess.run(["qmllint", str(REPO / "quickshell/.config/quickshell/KeybindsState.qml"),
                        str(REPO / "quickshell/.config/quickshell/KeybindsPanel.qml")], check=True)
        print("ok: qmllint KeybindsState.qml KeybindsPanel.qml")
    else:
        print("skip: qmllint is not installed")

    if shutil.which("quickshell"):
        subprocess.run(["quickshell", "-p", str(
            REPO / "quickshell/.config/quickshell/KeybindsSmoke.qml")], check=True,
            timeout=30)
        print("ok: Quickshell palette build/search smoke")
    else:
        print("skip: quickshell is not installed")


if __name__ == "__main__":
    if not (shutil.which("lua") or shutil.which("lua5.4") or shutil.which("lua5.3")
            or shutil.which("nvim")):
        raise SystemExit("skip: no Lua interpreter or Neovim Lua runner installed")
    main()
