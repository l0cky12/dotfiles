#!/usr/bin/env python3
"""Fixture tests for the locally collected Neovim and Herdr palettes."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile


REPO = Path(__file__).resolve().parent.parent
SCRIPT = REPO / "hypr/.config/hypr/scripts/application-keybinds"


def collect(source: str, environment: dict[str, str]) -> dict:
    result = subprocess.run([str(SCRIPT), source], check=True, text=True,
                            capture_output=True, env=environment)
    return json.loads(result.stdout)


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="application-keybinds-test.") as directory:
        root = Path(directory)
        nvim = root / "nvim.json"
        nvim.write_text(json.dumps([
            {"mode": "n", "lhs": "<leader>ff", "desc": "Find files"},
            {"mode": "i", "lhs": "<C-s>", "rhs": "<Cmd>write<CR>"},
            {"mode": "n", "lhs": "<leader>ff", "desc": "Find files"},
        ]), encoding="utf-8")
        env = dict(os.environ, APPLICATION_KEYBINDS_NVIM_JSON=str(nvim))
        result = collect("neovim", env)
        assert result["title"] == "Neovim keybindings"
        assert [(item["shortcut"], item["description"]) for item in result["rows"]] == [
            ("Insert  <C-s>", "<Cmd>write<CR>"),
            ("Normal  <leader>ff", "Find files"),
        ]

        defaults = root / "defaults.toml"
        defaults.write_text("""[keys]
prefix = "ctrl+b"
next_tab = "prefix+n"
focus_pane_left = "prefix+h"
""", encoding="utf-8")
        config = root / "config.toml"
        config.write_text("""[keys]
next_tab = "ctrl+alt+]"

[[keys.command]]
key = "prefix+g"
description = "open git status"
""", encoding="utf-8")
        env = dict(os.environ, APPLICATION_KEYBINDS_HERDR_DEFAULT_CONFIG=str(defaults),
                   HERDR_CONFIG=str(config))
        result = collect("herdr", env)
        assert result["title"] == "Herdr keybindings"
        assert {(item["shortcut"], item["description"]) for item in result["rows"]} == {
            ("ctrl+b", "prefix"), ("ctrl+alt+]", "next tab"),
            ("prefix+h", "focus pane left"), ("prefix+g", "open git status"),
        }
    print("ok: application keybinding collectors use only local fixture data")


if __name__ == "__main__":
    main()
