#!/usr/bin/env python3
"""Fixture checks for the active Hyprlock layout/theme contract."""

from __future__ import annotations

import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
THEME_DIR = ROOT / "hypr/.config/hypr/theme"
sys.path.insert(0, str(THEME_DIR))

import themelib as tl  # noqa: E402

LAYOUT = ROOT / "hyprlock/.config/hyprlock/layouts/hyprlock.conf"
TEMPLATE = THEME_DIR / "templates/hyprlock-colors.conf"
THEMES = ROOT / "hypr/.config/hypr/themes"


def variable_definitions(text: str) -> set[str]:
    return set(re.findall(r"^\s*(\$[A-Za-z0-9_]+)\s*=", text, re.MULTILINE))


def main() -> int:
    layout = LAYOUT.read_text()
    tl.validate_conf(LAYOUT)

    assert "AlfaSlabOne" not in layout
    assert "/wallpapers/1.jpg" not in layout
    assert "hypr-wallpaper-picker current" in layout

    required = set(re.findall(r"\$lock_[A-Za-z0-9_]+", layout))
    assert required, "active layout does not consume generated lock variables"

    template = TEMPLATE.read_text()
    menu = (ROOT / "menu/.config/lmenu/menu.jsonc").read_text()
    offered = set(re.findall(r"screensaver-lock layout set ([a-z0-9]+)", menu))
    wrapper = (ROOT / "hypr/.config/hypr/hyprlock.conf").read_text()
    builtins = {"$USER", "$HOME", "$TIME", "$FAIL", "$ATTEMPTS"}
    for name in offered:
        path = LAYOUT.with_name("hyprlock.conf" if name == "default" else f"{name}.conf")
        content = "\n".join(line for line in path.read_text().splitlines()
                            if not line.lstrip().startswith("#"))
        references = set(re.findall(r"\$[A-Za-z_][A-Za-z_0-9]*", content))
        definitions = variable_definitions(template + "\n" + wrapper + "\n" + content)
        assert not (references - definitions - builtins), (
            f"{name}: undefined variables: {sorted(references - definitions - builtins)}"
        )
    themes = tl.load_all(THEMES)
    assert themes, "no themes found"

    with tempfile.TemporaryDirectory(prefix="hyprlock-theme-test.") as tmp:
        out = Path(tmp) / "colors.conf"
        for slug, theme in themes.items():
            rendered = tl.render(template, theme, origin=TEMPLATE.name)
            out.write_text(rendered)
            tl.validate_conf(out)
            missing = required - variable_definitions(rendered)
            assert not missing, f"{slug}: missing lock variables: {sorted(missing)}"

            for surface in ("surface", "background_alt"):
                ratio = tl.contrast_ratio(
                    theme.colors["foreground_bright"], theme.colors[surface]
                )
                assert ratio >= 4.5, (
                    f"{slug}: lock text contrast on {surface} is {ratio:.2f}:1"
                )

            match = re.search(
                r"^\$lock_blur_passes\s*=\s*(\d+)\s*$", rendered, re.MULTILINE
            )
            assert match, f"{slug}: lock blur passes were not rendered"
            expected = int(theme.style["blur_passes"]) if theme.style["blur"] else 0
            assert int(match.group(1)) == expected, f"{slug}: blur toggle not honored"

    print(f"ok: hyprlock theme contract ({len(themes)} themes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
