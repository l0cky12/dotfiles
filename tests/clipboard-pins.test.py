#!/usr/bin/env python3
"""Exercise pin matching and wipes against a private, real cliphist database."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[1]
HELPER = REPO / "hypr/.config/hypr/scripts/clipboard-pins.py"
WIPE = REPO / "hypr/.config/hypr/scripts/clipboard-wipe.sh"
LOCK = REPO / "screensaver/.local/bin/screensaver-lock"

with tempfile.TemporaryDirectory(prefix="clipboard-pins-test.") as directory:
    root = Path(directory)
    env = dict(os.environ, HOME=directory, XDG_CACHE_HOME=str(root / "cache"),
               XDG_CONFIG_HOME=str(root / "config"), XDG_STATE_HOME=str(root / "state"))
    env.pop("WAYLAND_DISPLAY", None)
    env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
    (root / "bin").mkdir()
    clear = root / "bin/wl-copy"
    clear.write_text('#!/bin/sh\n[ "$*" = "--clear" ] && exit "${CLEAR_STATUS:-0}"\nexit 2\n')
    clear.chmod(0o755)
    env["PATH"] = str(root / "bin") + ":" + env["PATH"]
    (root / "config/cliphist").mkdir(parents=True)
    (root / "config/cliphist/config").write_text("max-items 200\n")
    scripts = root / ".config/hypr/scripts"
    scripts.mkdir(parents=True)
    (scripts / WIPE.name).symlink_to(WIPE)
    (scripts / HELPER.name).symlink_to(HELPER)
    for name, body in {
        "pkill": "exit 0", "pidwait": "exit 0", "pidof": "exit 1",
        "quickshell": 'printf "%s\\n" "$FIXTURE_PINS"; exit "${IPC_STATUS:-0}"',
        "hyprlock": 'printf "locked\\n"',
    }.items():
        script = root / "bin" / name
        script.write_text("#!/bin/sh\n" + body + "\n")
        script.chmod(0o755)
    env.update(SCREENSAVER_LOCK_CONFIG=str(REPO / "hypr/.config/hypr/hyprlock.conf"),
               SCREENSAVER_LOCK_LAYOUT_DIR=str(REPO / "hyprlock/.config/hyprlock/layouts"),
               SCREENSAVER_LOCK_RUNTIME_DIR=str(root / "runtime"),
               SCREENSAVER_LOCK_LAYOUT_FILE=str(root / "lock-layout"))
    real_cliphist = shutil.which("cliphist")
    assert real_cliphist, "cliphist is required"

    def run(*args, data=None, check=True):
        return subprocess.run(args, input=data, env=env, capture_output=True,
                              check=check, timeout=10)

    def store(data):
        run(real_cliphist, "store", data=data)
        return run(real_cliphist, "list").stdout.decode().split("\t", 1)[0]

    first = b"x" * 110 + b"A"
    second = b"x" * 110 + b"B"
    first_id = store(first)
    second_id = store(second)
    run(str(WIPE), first_id)
    assert run(real_cliphist, "decode", first_id, check=False).stdout == first, \
        "wipe changed the pinned ID, leaving the panel with stale IDs"
    assert run(real_cliphist, "decode", second_id, check=False).returncode != 0

    # Two different complete values have identical truncated previews.
    second_id = store(second)
    preview = run(real_cliphist, "list").stdout.decode().splitlines()[0].split("\t", 1)[1]
    digest = hashlib.sha256(first).hexdigest()
    pins = json.dumps([dict(id=first_id, preview=preview, hash=digest)])
    rows = json.loads(run("python3", str(HELPER), "list", pins).stdout)
    assert len({row["hash"] for row in rows}) == 2, "preview collision hid distinct contents"
    env["FIXTURE_PINS"] = pins
    assert run(str(LOCK)).stdout == b"locked\n"
    assert run(real_cliphist, "list").stdout.decode().split("\t", 1)[0] == first_id
    assert run(real_cliphist, "decode", first_id).stdout == first

    # A stale descriptor follows only the matching complete content's new ID.
    new_id = store(first)
    other_id = store(second)
    run(str(WIPE), "--pins", pins)
    assert run(real_cliphist, "decode", new_id).stdout == first
    assert run(real_cliphist, "decode", other_id, check=False).returncode != 0

    # Multiple pins with the same preview retain their separate contents.
    other_id = store(second)
    third_id = store(b"x" * 110 + b"C")
    both = json.dumps([dict(id=new_id, preview=preview, hash=digest),
                       dict(id=other_id, preview=preview, hash=hashlib.sha256(second).hexdigest())])
    run(str(WIPE), "--pins", both)
    assert run(real_cliphist, "decode", new_id).stdout == first
    assert run(real_cliphist, "decode", other_id).stdout == second
    assert run(real_cliphist, "decode", third_id, check=False).returncode != 0

    # Binary identity is based on bytes, not an image summary or text decoding.
    binary = bytes(range(256)) * 2
    binary_id = store(binary)
    assert run("python3", str(HELPER), "hash", binary_id).stdout.decode().strip() == \
        hashlib.sha256(binary).hexdigest()

    before = run(real_cliphist, "list").stdout
    env["CLEAR_STATUS"] = "1"
    assert run(str(WIPE), check=False).returncode != 0
    assert run(real_cliphist, "list").stdout == before, "failed clipboard clear deleted history"
    env["CLEAR_STATUS"] = "0"

    # Legacy pins use their still-existing numeric ID, never their preview.
    run(str(WIPE), "--pins", json.dumps([dict(id=new_id, preview=preview)]))
    assert run(real_cliphist, "decode", new_id).stdout == first
    before = run(real_cliphist, "list").stdout
    assert run(str(WIPE), "--pins", "not-json", check=False).returncode != 0
    assert run(real_cliphist, "list").stdout == before
    # Unavailable IPC falls back to a full wipe, including pinned content.
    env["IPC_STATUS"] = "1"
    assert run(str(LOCK)).stdout == b"locked\n"
    assert run(real_cliphist, "list").stdout == b""

print("ok: clipboard pins with real isolated cliphist")
