#!/usr/bin/env python3
"""Snapshot checks for the theme generator's staged output."""

from __future__ import annotations

import hashlib
import io
import json
import os
import sys
import tempfile
import unittest
import unittest.mock
from contextlib import redirect_stdout
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
THEME_DIR = ROOT / "hypr/.config/hypr/theme"
THEMES = ROOT / "hypr/.config/hypr/themes"

# Import through the stowed package path, exactly like the desktop scripts do.
sys.path.insert(0, str(THEME_DIR))

import generate  # noqa: E402
import themelib as tl  # noqa: E402


KEY_OUTPUTS = (
    "swaync-style.css",
    "wofi-style.css",
    "quickshell-theme.json",
    "kitty-theme.conf",
    "rofi-theme.rasi",
)
FIXTURE_ENV = "THEME_TEST_FIXTURE_DIR"
SNAPSHOT_ENV = "THEME_TEST_SNAPSHOT_JSON"


def loaded_themes() -> dict[str, tl.Theme]:
    """Stable theme order keeps snapshots and test failures reproducible."""
    return dict(sorted(tl.load_all(THEMES).items()))


def render_all(theme: tl.Theme, root: Path) -> list[Path]:
    stage = root / "stage"
    prefix = root / "prefix"
    stage.mkdir(parents=True)
    prefix.mkdir(parents=True)
    staged = generate.build(theme, stage, prefix)
    outputs = [output for output, destination in staged]
    return outputs


def summary(theme: tl.Theme, outputs: list[Path]) -> dict[str, object]:
    """The stable subset worth snapshotting: identity and rendered bytes."""
    files = {
        output.name: hashlib.sha256(output.read_bytes()).hexdigest()
        for output in outputs
    }
    return {
        "accent": theme.colors["accent"],
        "mode": theme.mode,
        "warning_count": len(theme.warnings),
        "files": files,
    }


class ThemeGeneratorTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.themes = loaded_themes()

    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="theme-generator-test.")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

        # Defend against a template or validator deriving a live XDG path.
        env = {
            "XDG_CONFIG_HOME": str(self.root / "config"),
            "XDG_CACHE_HOME": str(self.root / "cache"),
            "XDG_RUNTIME_DIR": str(self.root / "runtime"),
        }
        Path(env["XDG_RUNTIME_DIR"]).mkdir(parents=True)
        patcher = unittest.mock.patch.dict(os.environ, env)
        patcher.start()
        self.addCleanup(patcher.stop)
        wallpaper_patcher = unittest.mock.patch.object(
            tl, "wallpaper_roots", return_value=[]
        )
        wallpaper_patcher.start()
        self.addCleanup(wallpaper_patcher.stop)
        original_config_home = generate.CONFIG_HOME
        original_cache_home = generate.CACHE_HOME
        original_wallpaper_state_file = generate.WALLPAPER_STATE_FILE

        def restore_generator_paths() -> None:
            generate.CONFIG_HOME = original_config_home
            generate.CACHE_HOME = original_cache_home
            generate.WALLPAPER_STATE_FILE = original_wallpaper_state_file

        self.addCleanup(restore_generator_paths)
        generate.CONFIG_HOME = Path(env["XDG_CONFIG_HOME"])
        generate.CACHE_HOME = Path(env["XDG_CACHE_HOME"])
        generate.WALLPAPER_STATE_FILE = self.root / "state/wallpaper"

    def test_renders_every_theme_into_temporary_stage(self) -> None:
        self.assertGreater(len(self.themes), 0, "theme discovery found nothing")

        for slug, theme in self.themes.items():
            with self.subTest(theme=slug):
                outputs = render_all(theme, self.root / slug)
                self.assertEqual(
                    len(outputs), len(generate.targets(self.root, theme))
                )

                accent = theme.colors["accent"]
                self.assertTrue(accent.startswith("#"))
                for name in KEY_OUTPUTS:
                    output = self.root / slug / "stage" / name
                    self.assertTrue(output.is_file(), f"{name} was not rendered")
                    rendered = output.read_text()
                    self.assertTrue(rendered, f"{name} is empty")
                    self.assertNotIn("{{", rendered, f"{name} has unresolved markers")

                for css_name in ("swaync-style.css", "wofi-style.css"):
                    css = (self.root / slug / "stage" / css_name).read_text()
                    if css_name == "wofi-style.css":
                        red, green, blue = tl._rgb(accent)
                        self.assertIn(f"rgba({red}, {green}, {blue}", css)
                    else:
                        self.assertIn(accent[1:], css)

                quickshell = json.loads(
                    (self.root / slug / "stage" / "quickshell-theme.json").read_text()
                )
                self.assertEqual(quickshell["colors"]["accent"], accent)
                for name in ("kitty-theme.conf", "rofi-theme.rasi"):
                    self.assertIn(accent, (self.root / slug / "stage" / name).read_text())

    def test_prefix_preview_renders_targets_deployed_in_live_config(self) -> None:
        theme = self.themes["tokyo-night"]
        prefix = self.root / "prefix"
        for directory in ("nvim/colors", "btop/themes", "obsidian/snippets"):
            (generate.CONFIG_HOME / directory).mkdir(parents=True)

        stdout = io.StringIO()
        with redirect_stdout(stdout):
            result = generate.main([
                "set", theme.slug, "--prefix", str(prefix), "--no-reload",
            ])

        self.assertEqual(result, 0, stdout.getvalue())
        neovim = (prefix / f"nvim/colors/{theme.slug}.lua").read_text()
        self.assertIn(f'vim.g.colors_name = "{theme.slug}"', neovim)
        self.assertIn(
            f'vim.g.terminal_color_12 = "{theme.ansi["bright_blue"]}"', neovim
        )
        self.assertIn(
            f'Normal = {{ fg = "{theme.colors["foreground"]}", '
            f'bg = "{theme.colors["background"]}" }}',
            neovim,
        )

        btop = (prefix / f"btop/themes/{theme.slug}.theme").read_text()
        self.assertIn(f'theme[main_bg]="{theme.colors["background"]}"', btop)
        self.assertIn(f'theme[hi_fg]="{theme.colors["accent"]}"', btop)

        obsidian = (prefix / "obsidian/snippets/generated-theme.css").read_text()
        self.assertIn(
            f"--background-primary: {theme.colors['background']};", obsidian
        )
        self.assertIn(f"--interactive-accent: {theme.colors['accent']};", obsidian)
        self.assertIn(f"--text-muted: {theme.colors['muted']};", obsidian)
        self.assertIn("set color_theme", stdout.getvalue())
        self.assertIn("enable generated-theme.css", stdout.getvalue())

    def test_optional_app_targets_skip_cleanly_when_absent(self) -> None:
        theme = self.themes["tokyo-night"]
        prefix = self.root / "prefix"
        prefix.mkdir()
        stdout = io.StringIO()

        with redirect_stdout(stdout):
            result = generate.main([
                "set", theme.slug, "--prefix", str(prefix), "--no-reload",
            ])

        self.assertEqual(result, 0, stdout.getvalue())
        for app in ("neovim", "btop", "obsidian"):
            self.assertIn(f"{app}: skipped (not deployed)", stdout.getvalue())
        self.assertFalse((prefix / "nvim").exists())
        self.assertFalse((prefix / "btop").exists())
        self.assertFalse((prefix / "obsidian").exists())

    def test_non_utf8_btop_config_is_user_owned_and_untouched(self) -> None:
        theme = self.themes["tokyo-night"]
        prefix = self.root / "prefix"
        config = prefix / "btop/btop.conf"
        config.parent.mkdir(parents=True)
        invalid_utf8 = b'color_theme = "Default"\n# \xff\n'
        config.write_bytes(invalid_utf8)

        message = generate.sync_btop_config(prefix, theme)

        self.assertEqual(config.read_bytes(), invalid_utf8)
        self.assertIn('color_theme = "current"', message)

    def test_optional_link_failure_keeps_installed_theme_and_state_aligned(self) -> None:
        theme = self.themes["tokyo-night"]
        prefix = generate.CONFIG_HOME
        (prefix / "nvim/colors").mkdir(parents=True)
        state = self.root / "state/current-theme"
        state.parent.mkdir(parents=True)
        state.write_text("catppuccin")
        stdout = io.StringIO()
        original_symlink_to = Path.symlink_to

        def fail_nvim_link(path: Path, *args: object, **kwargs: object) -> None:
            if path == prefix / "nvim/colors/.current.lua.new":
                raise PermissionError("fixture link failure")
            original_symlink_to(path, *args, **kwargs)

        with (
            unittest.mock.patch.object(generate, "STATE_FILE", state),
            unittest.mock.patch.object(
                Path, "symlink_to", autospec=True, side_effect=fail_nvim_link
            ),
            redirect_stdout(stdout),
        ):
            result = generate.main(["set", theme.slug, "--no-reload"])

        self.assertEqual(result, 0, stdout.getvalue())
        self.assertEqual(state.read_text().strip(), theme.slug)
        self.assertTrue((prefix / f"nvim/colors/{theme.slug}.lua").is_file())
        self.assertIn("could not update current theme alias", stdout.getvalue())

    def test_optional_theme_aliases_replace_and_prune_generated_slugs(self) -> None:
        prefix = self.root / "prefix"
        for directory in ("nvim/colors", "btop/themes"):
            (generate.CONFIG_HOME / directory).mkdir(parents=True)
        for directory in (prefix / "nvim/colors", prefix / "btop/themes"):
            directory.mkdir(parents=True)
        custom = prefix / "nvim/colors/custom.lua"
        custom.write_text("-- User colorscheme; theme generator must preserve it.\n")
        first = self.themes["tokyo-night"]
        second = self.themes["catppuccin"]

        for theme in (first, second):
            stdout = io.StringIO()
            with redirect_stdout(stdout):
                result = generate.main([
                    "set", theme.slug, "--prefix", str(prefix), "--no-reload",
                ])
            self.assertEqual(result, 0, stdout.getvalue())

        self.assertFalse((prefix / f"nvim/colors/{first.slug}.lua").exists())
        self.assertFalse((prefix / f"btop/themes/{first.slug}.theme").exists())
        self.assertEqual(
            (prefix / "nvim/colors/current.lua").readlink(),
            Path(f"{second.slug}.lua"),
        )
        self.assertEqual(
            (prefix / "btop/themes/current.theme").readlink(),
            Path(f"{second.slug}.theme"),
        )
        self.assertTrue((prefix / f"nvim/colors/{second.slug}.lua").is_file())
        self.assertTrue((prefix / f"btop/themes/{second.slug}.theme").is_file())
        self.assertTrue(custom.is_file())

    def test_current_slug_is_reserved_for_generated_aliases(self) -> None:
        source = THEMES / "tokyo-night/colors.toml"
        theme_dir = self.root / "current"
        theme_dir.mkdir()
        (theme_dir / "colors.toml").write_text(
            source.read_text().replace(
                'slug = "tokyo-night"', 'slug = "current"', 1
            )
        )

        with self.assertRaisesRegex(tl.ThemeError, "reserved"):
            tl.load(theme_dir / "colors.toml")

    def test_contrast_warnings_match_palette_metadata(self) -> None:
        for slug, theme in self.themes.items():
            with self.subTest(theme=slug):
                self.assertEqual(tl.check_contrast(theme), theme.warnings)

    def test_low_contrast_theme_reports_instead_of_raising(self) -> None:
        colors = {key: "#000000" for key in tl.REQUIRED_COLORS}
        colors.update(background="#000000", foreground="#111111", surface="#000000")
        ansi = {name: "#111111" for name in tl.REQUIRED_ANSI}
        theme = tl.Theme(
            slug="synthetic-low-contrast",
            name="Synthetic Low Contrast",
            mode="dark",
            description="Fixture for contrast warnings",
            family="synthetic",
            wallpaper=None,
            colors=colors,
            ansi=ansi,
            style=dict(tl.STYLE_DEFAULTS),
        )
        for status, fallback in tl.STATUS_DEFAULTS.items():
            theme.colors[status] = colors[fallback]

        warnings = tl.check_contrast(theme)
        self.assertTrue(warnings)
        self.assertEqual(theme.warnings, [])
        self.assertIn("1.11:1", warnings[0])

        render_all(theme, self.root / "synthetic-low-contrast")

    def test_snapshot_comparison(self) -> None:
        fixture_dir = os.environ.get(FIXTURE_ENV)
        snapshot_path = os.environ.get(SNAPSHOT_ENV)
        committed_snapshot = ROOT / "tests/fixtures/theme-generator-snapshots.json"
        if not fixture_dir:
            if snapshot_path:
                snapshot = Path(snapshot_path)
            elif committed_snapshot.exists():
                snapshot = committed_snapshot
            else:
                self.skipTest("snapshot comparison disabled; baseline absent")

        rendered = {}
        for slug, theme in self.themes.items():
            outputs = render_all(theme, self.root / slug)
            rendered[slug] = summary(theme, outputs)

        if fixture_dir:
            fixture = Path(fixture_dir) / "theme-generator-snapshots.json"
            fixture.parent.mkdir(parents=True, exist_ok=True)
            fixture.write_text(json.dumps(rendered, indent=2, sort_keys=True) + "\n")
            return

        with open(snapshot, encoding="utf-8") as handle:
            expected = json.load(handle)
        self.maxDiff = None
        for slug in sorted(set(rendered) | set(expected)):
            self.assertIn(slug, expected, f"unexpected generated theme: {slug}")
            self.assertIn(slug, rendered, f"snapshot theme not generated: {slug}")
            self.assertEqual(
                rendered[slug], expected[slug], f"snapshot mismatch for {slug}"
            )


if __name__ == "__main__":
    unittest.main()
