#!/usr/bin/env python3
"""Fixture tests for Lua reconciliation, caching, and palette records."""

from __future__ import annotations

import json
from pathlib import Path
import re
import runpy
import shutil
import subprocess
import tempfile


REPO = Path(__file__).resolve().parent.parent
COLLECTOR = REPO / "hypr/.config/hypr/scripts/keybinds-collector"
KEYBINDS_STATE = REPO / "quickshell/.config/quickshell/KeybindsState.qml"
KEYBINDING_CONF = REPO / "hypr/.config/hypr/conf/keybinding.conf"


def conf_descriptions(conf: str) -> list[str]:
    dispatchers = (
        "exec|fullscreen|killactive|layoutmsg|movecurrentworkspacetomonitor|"
        "movefocus|movetoworkspace|movetoworkspacesilent|movewindow|"
        "resizeactive|swapwindow|togglefloating|workspace"
    )
    descriptions = []
    for line in conf.splitlines():
        match = re.search(rf",\s*(?:{dispatchers})\s*,", line)
        if not match:
            continue
        fields = line[:match.start()].partition("=")[2].split(",", 2)
        if len(fields) != 3:
            continue
        description = fields[2].strip()
        if description == "Delete, close all windows":
            description = "close all windows"
        descriptions.append(description)
    return descriptions


def invoke(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run([str(COLLECTOR), *args], check=True, text=True,
                          capture_output=True)


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value), encoding="utf-8")


def main() -> None:
    qml = KEYBINDS_STATE.read_text(encoding="utf-8")
    conf = KEYBINDING_CONF.read_text(encoding="utf-8")
    collector_globals = runpy.run_path(str(COLLECTOR), run_name="keybinds_collector_test")
    priority = collector_globals["PRIORITY"]
    rank = collector_globals["rank"]

    qml_priority = [pattern.replace(r"\/", "/") for pattern in re.findall(
        r"\{ rank: \d+, re: /((?:\\.|[^/])*)/i \}", qml)]
    assert tuple(qml_priority) == priority, \
        "QML and collector priority ladders differ in content or order"
    descriptions = conf_descriptions(conf)
    unmatched = sorted({description for description in descriptions
                        if rank(description) == 999})
    assert not unmatched, f"repository descriptions missing priority rules: {unmatched}"
    required_families = (
        r"^focus ", r"^move window ", r"^swap window ",
        r"^move workspace to .* monitor$", r"resize|expand window|shrink window",
        r"^workspace [0-9]+$", r"^move to workspace",
        r"^move silently to workspace", r"^(next|previous|former) workspace$",
        r"reminder", r"Windows VM|Gaming VM", r"^Zoom (in|out)$|^Reset zoom$",
    )
    for family in required_families:
        matches = [description for description in descriptions
                   if re.search(family, description, re.IGNORECASE)]
        assert matches, f"repository fixture has no descriptions for family: {family}"
        assert all(rank(description) != 999 for description in matches), family
    print(f"ok: identical priority ladders rank all {len(set(descriptions))} "
          "repository descriptions")

    keywords = re.findall(r"^\s*(bind[a-z]*)\s*=", conf, re.MULTILINE)
    valid_flags = set("lrcgoenmtisdpuw")
    invalid_keywords = sorted({keyword for keyword in keywords
                               if not set(keyword.removeprefix("bind")) <= valid_flags})
    assert not invalid_keywords, f"invalid Hyprland bind keywords: {invalid_keywords}"
    described_repeat_lines = [line for line in conf.splitlines()
                              if re.match(r"^\s*bind(?=[a-z]*d)(?=[a-z]*[el])[a-z]*\s*=", line)]
    assert all(re.search(r",\s*[^,]+,\s*(?:exec|resizeactive)\s*,", line)
               for line in described_repeat_lines), \
        "described repeat/locked binds must retain description and dispatcher columns"
    print(f"ok: all {len(keywords)} bind keywords use documented flags and retain descriptions")

    lua_activation = re.search(
        r'else if \(r\.dispatcher === "lua"\) \{\s*'
        r'actionProc\.command = \["hyprctl", "([^"]+)", r\.arg\]', qml)
    assert lua_activation and lua_activation.group(1) == "eval", \
        "reconciled lua rows must activate through hyprctl eval"
    print("ok: reconciled Lua rows activate through hyprctl eval")

    # `hyprctl binds` reports a `code:N` bind with key "" AND keycode 0, so the
    # workspace block (number_row_keys in conf/keybindings.lua) reaches the
    # collector with nothing to match on and nothing to display. The keyless
    # fallback has to recover the action and the key, or the palette shows the
    # whole workspace family blank.
    reconcile = collector_globals["reconcile"]
    add_key_labels = collector_globals["add_key_labels"]
    keyless = [
        {"modmask": 64, "key": "", "keycode": 0, "description": "workspace 1",
         "dispatcher": "__lua", "arg": "228", "mouse": False},
        {"modmask": 65, "key": "", "keycode": 0, "description": "move to workspace 1",
         "dispatcher": "__lua", "arg": "122", "mouse": False},
        {"modmask": 68, "key": "", "keycode": 0,
         "description": "move silently to workspace 1",
         "dispatcher": "__lua", "arg": "124", "mouse": False},
    ]
    replayed_keyless = [
        {"modmask": 64, "description": "workspace 1", "key": "code:10",
         "dispatcher": "lua", "arg": "hl.dsp.focus({ workspace = 1 })"},
        {"modmask": 65, "description": "move to workspace 1", "key": "code:10",
         "dispatcher": "exec", "arg": "move-follow-true"},
        {"modmask": 68, "description": "move silently to workspace 1", "key": "code:10",
         "dispatcher": "exec", "arg": "move-follow-false"},
    ]
    rows = reconcile(keyless, replayed_keyless)
    add_key_labels(rows)
    by_description = {row.get("description"): row for row in rows}
    for description, dispatcher in (("workspace 1", "lua"),
                                    ("move to workspace 1", "exec"),
                                    ("move silently to workspace 1", "exec")):
        row = by_description[description]
        assert row["dispatcher"] == dispatcher, (description, row)
        assert row.get("key_label") == "1", (description, row)
    # One replayed row answers for one bind, and reconcile must not leave marks
    # on its arguments: a repeated call has to behave the same way.
    repeated = reconcile(keyless, replayed_keyless)
    assert not [row for row in repeated if row.get("dispatcher") == "__lua"], repeated
    duplicated = reconcile(keyless + [dict(keyless[0])], replayed_keyless)
    assert len([row for row in duplicated
                if row.get("dispatcher") == "__lua"]) == 1, duplicated
    print("ok: keycode-only workspace binds recover both action and key")

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

        # Feed the real keybinding.conf descriptions through the complete
        # collector for a useful ordering artifact.
        actual_config = REPO / "hypr/.config/hypr"
        repository_binds = []
        for index, description in enumerate(descriptions, 1000):
            repository_binds.append({
                "modmask": 64, "key": f"code:{index}", "keycode": index,
                "description": description, "dispatcher": "exec",
                "arg": f"fixture-{index}", "mouse": False,
            })
        repository_binds_path = root / "repository-binds.json"
        write_json(repository_binds_path, repository_binds)
        repository_rows = invoke(
            "--binds-json", str(repository_binds_path),
            "--keymap-summary", str(keymap),
            "--keybindings", str(actual_config / "conf/keybindings.lua"),
            "--dry-run", "--limit", "40")
        assert len(repository_rows.stdout.splitlines()) == 40
        print("--- first 40 prioritized repository-fixture rows ---")
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
