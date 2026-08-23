#!/usr/bin/env python3
"""Generate and install the active desktop theme.

    generate.py --list
    generate.py --validate SLUG | --validate-all
    generate.py --set SLUG [--no-reload] [--prefix DIR]

The switch is atomic in the sense that matters: everything is rendered and
validated in a staging directory first, and nothing is moved into place until
all of it has passed. A broken theme therefore leaves the previous one running.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import themelib as tl  # noqa: E402

HERE = Path(__file__).resolve().parent
TEMPLATES = HERE / "templates"
THEMES_DIR = HERE.parent / "themes"
STATE_FILE = THEMES_DIR / "current-theme"

CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
CACHE_HOME = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))

# Colour output only when a human is watching.
_TTY = sys.stdout.isatty()
def _c(code: str, text: str) -> str:
    return f"\033[{code}m{text}\033[0m" if _TTY else text
BOLD = lambda s: _c("1", s)          # noqa: E731
GREEN = lambda s: _c("32", s)        # noqa: E731
YELLOW = lambda s: _c("33", s)       # noqa: E731
RED = lambda s: _c("31", s)          # noqa: E731
DIM = lambda s: _c("2", s)           # noqa: E731


def targets(prefix: Path) -> list[tuple[str, Path]]:
    """(template, destination) for every generated file.

    Destinations are real config paths, not copies: this repo is stowed, so
    ~/.config/<app> already points into it. `prefix` exists only so the test
    pass can render everything somewhere harmless.
    """
    return [
        ("hyprland-decorations.conf", prefix / "hypr/conf/decorations.conf"),
        ("quickshell-theme.json",     prefix / "hypr/themes/.active/theme.json"),
        ("waybar-colors.css",         prefix / "waybar/colors.css"),
        ("kitty-theme.conf",          prefix / "kitty/theme/current-theme.conf"),
        ("zsh-theme.zsh",             prefix / "zsh/current-theme.zsh"),
        ("rofi-theme.rasi",           prefix / "rofi/color-themes/current.rasi"),
        ("hyprlock-colors.conf",      prefix / "hyprlock/colors.conf"),
        ("swaync-style.css",          prefix / "swaync/style.css"),
        ("wofi-style.css",            prefix / "wofi/style.css"),
        ("noctalia-colors.json",      prefix / "noctalia/colors.json"),
    ]


def build(theme: tl.Theme, stage: Path, prefix: Path) -> list[tuple[Path, Path]]:
    """Render every template into `stage` and validate it. Returns the
    (staged, destination) pairs ready for install."""
    staged: list[tuple[Path, Path]] = []
    for name, dest in targets(prefix):
        template = TEMPLATES / name
        if not template.is_file():
            raise tl.ThemeError(f"missing template: {template}")
        out = stage / name
        out.write_text(tl.render(template.read_text(), theme, origin=name))
        validator = tl.VALIDATORS.get(out.suffix)
        if validator:
            validator(out)
        staged.append((out, dest))
    return staged


# ── Reload ───────────────────────────────────────────────────────────────────
# Every reload is scoped to a named process and tolerated if absent. Nothing
# here uses a broad pattern kill.

def _run(cmd: list[str], timeout: int = 5) -> bool:
    try:
        return subprocess.run(
            cmd, capture_output=True, timeout=timeout
        ).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def _pids_of(name: str) -> list[str]:
    try:
        out = subprocess.run(
            ["pgrep", "-x", name], capture_output=True, text=True, timeout=5
        )
    except (OSError, subprocess.TimeoutExpired):
        return []
    return out.stdout.split() if out.returncode == 0 else []


def reload_apps(theme: tl.Theme, kitty_conf: Path) -> tuple[list[str], list[str]]:
    done: list[str] = []
    deferred: list[str] = []

    # Hyprland re-reads decorations.conf, which it already sources.
    if shutil.which("hyprctl") and _run(["hyprctl", "reload"]):
        done.append("hyprland")

    # Quickshell needs nothing: Theme.qml watches the generated theme.json and
    # repaints itself. Report it so the absence of a command is not mistaken
    # for the shell having been missed.
    if _pids_of("quickshell"):
        done.append("quickshell (live)")

    # Kitty: one socket per instance. The previous generator called `kitty @`
    # bare, which only worked when the calling shell happened to export
    # KITTY_LISTEN_ON; addressing each pid works from anywhere.
    kitty_pids = _pids_of("kitty")
    if kitty_pids and shutil.which("kitty"):
        hits = 0
        for pid in kitty_pids:
            to = f"unix:@kitty-{pid}"
            if _run(["kitty", "@", "--to", to, "set-colors", "--all",
                     "--configured", str(kitty_conf)]):
                hits += 1
                _run(["kitty", "@", "--to", to, "set-background-opacity",
                      str(theme.style["surface_opacity"])])
        if hits:
            done.append(f"kitty ({hits}/{len(kitty_pids)})")

    # Waybar reloads its stylesheet on SIGUSR2. Exact-name match only.
    if _pids_of("waybar") and _run(["pkill", "-USR2", "-x", "waybar"]):
        done.append("waybar")

    if _pids_of("swaync") and shutil.which("swaync-client"):
        if _run(["swaync-client", "--reload-config"]):
            done.append("swaync")

    # These read the theme when next launched. Say so rather than implying they
    # were reloaded.
    deferred += ["rofi", "wofi", "fastfetch", "hyprlock"]
    deferred.append("zsh (new shells; run `exec zsh` here)")
    return done, deferred


# ── Side effects that are not template renders ───────────────────────────────

def link_rofi(prefix: Path, slug: str) -> None:
    """Rofi is pointed at the theme by a symlink, which is what Super+A,
    KeyHints.sh, the capture menu and the calculators all already read."""
    themes = prefix / "rofi/color-themes"
    generated = themes / "current.rasi"
    slug_copy = themes / f"{slug}.rasi"
    shutil.copyfile(generated, slug_copy)
    link = prefix / "rofi/current-theme.rasi"
    tmp = link.parent / ".current-theme.rasi.new"
    if tmp.is_symlink() or tmp.exists():
        tmp.unlink()
    tmp.symlink_to(slug_copy)
    os.replace(tmp, link)


def sync_noctalia(prefix: Path, theme: tl.Theme) -> None:
    """Register the generated colours as a Noctalia user scheme named after the
    theme. The previous generator hardcoded "Windows-7" here for every theme,
    so switching never actually moved Noctalia off that scheme."""
    settings = prefix / "noctalia/settings.json"
    colors = prefix / "noctalia/colors.json"
    if not colors.is_file():
        return
    scheme = theme.slug
    scheme_dir = prefix / "noctalia/colorschemes" / scheme
    scheme_dir.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(colors, scheme_dir / f"{scheme}.json")
    if not settings.is_file():
        return
    try:
        data = json.loads(settings.read_text())
    except json.JSONDecodeError:
        return  # not ours to repair
    cs = data.setdefault("colorSchemes", {})
    cs["predefinedScheme"] = scheme
    cs["useWallpaperColors"] = False
    cs["darkMode"] = theme.is_dark
    tmp = settings.parent / ".settings.json.new"
    tmp.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
    os.replace(tmp, settings)


def sync_fastfetch(prefix: Path, theme: tl.Theme) -> None:
    """fastfetch takes a named colour, not hex, so map the accent to the nearest
    of the eight it understands."""
    cfg = prefix / "fastfetch/config.jsonc"
    if not cfg.is_file():
        return
    names = {
        "red": theme.ansi["red"], "green": theme.ansi["green"],
        "yellow": theme.ansi["yellow"], "blue": theme.ansi["blue"],
        "magenta": theme.ansi["magenta"], "cyan": theme.ansi["cyan"],
        "white": theme.ansi["white"], "black": theme.ansi["bright_black"],
    }
    accent = theme.colors["accent"]
    ar, ag, ab = tl._rgb(accent)
    best = min(
        names,
        key=lambda n: sum(
            (a - b) ** 2 for a, b in zip((ar, ag, ab), tl._rgb(names[n]))
        ),
    )
    text = cfg.read_text()
    new = re.sub(r'"keyColor":\s*"[a-z_]*"', f'"keyColor": "{best}"', text)
    if new != text:
        tmp = cfg.parent / ".config.jsonc.new"
        tmp.write_text(new)
        os.replace(tmp, cfg)


def write_state(theme: tl.Theme) -> None:
    """One authority for the active theme, plus a cache mirror so non-Hyprland
    tooling can ask for the mode without parsing TOML."""
    tmp = STATE_FILE.parent / ".current-theme.new"
    tmp.write_text(theme.slug)
    os.replace(tmp, STATE_FILE)

    cache = CACHE_HOME / "theme"
    cache.mkdir(parents=True, exist_ok=True)
    for name, value in (("current", theme.slug), ("mode", theme.mode)):
        tmp = cache / f".{name}.new"
        tmp.write_text(value + "\n")
        os.replace(tmp, cache / name)


def current_slug() -> str | None:
    if STATE_FILE.is_file():
        return STATE_FILE.read_text().strip() or None
    return None


# ── Commands ─────────────────────────────────────────────────────────────────

def cmd_list(args: argparse.Namespace) -> int:
    themes = tl.load_all(THEMES_DIR)
    active = current_slug()
    if args.porcelain:
        for slug, theme in themes.items():
            print(f"{slug}\t{theme.name}\t{theme.mode}"
                  f"\t{'active' if slug == active else ''}")
        return 0
    for slug, theme in themes.items():
        mark = GREEN("*") if slug == active else " "
        print(f" {mark} {BOLD(slug):<32} {theme.name:<22} {DIM(theme.mode)}")
    return 0


def cmd_validate(args: argparse.Namespace) -> int:
    slugs = sorted(p.name for p in THEMES_DIR.iterdir()
                   if (p / "colors.toml").is_file()) if args.all else [args.slug]
    failures = 0
    warnings = 0
    with tempfile.TemporaryDirectory(prefix="theme-validate.") as tmp:
        stage = Path(tmp) / "stage"
        stage.mkdir()
        prefix = Path(tmp) / "prefix"
        for slug in slugs:
            try:
                theme = tl.load(THEMES_DIR / slug / "colors.toml")
                build(theme, stage, prefix)
            except tl.ThemeError as exc:
                print(f" {RED('FAIL')} {slug}: {exc}")
                failures += 1
                continue
            if theme.warnings:
                print(f" {YELLOW('WARN')} {slug}")
                for w in theme.warnings:
                    print(f"        {w}")
                warnings += len(theme.warnings)
            else:
                print(f" {GREEN('ok')}   {slug}")
    print()
    print(f"{len(slugs)} theme(s): {len(slugs) - failures} valid, "
          f"{failures} failed, {warnings} contrast warning(s)")
    return 1 if failures else 0


def cmd_set(args: argparse.Namespace) -> int:
    slug = args.slug
    toml = THEMES_DIR / slug / "colors.toml"
    if not toml.is_file():
        available = ", ".join(sorted(
            p.name for p in THEMES_DIR.iterdir() if (p / "colors.toml").is_file()
        ))
        print(f"{RED('error')}: no theme '{slug}'.\nAvailable: {available}",
              file=sys.stderr)
        return 2

    prefix = Path(args.prefix).expanduser() if args.prefix else CONFIG_HOME
    dry = bool(args.prefix)

    try:
        theme = tl.load(toml)
    except tl.ThemeError as exc:
        print(f"{RED('error')}: {exc}", file=sys.stderr)
        print("Previous theme left untouched.", file=sys.stderr)
        return 1

    stage_root = Path(os.environ.get("XDG_RUNTIME_DIR", tempfile.gettempdir()))
    stage = Path(tempfile.mkdtemp(prefix="theme-stage.", dir=stage_root))
    try:
        try:
            staged = build(theme, stage, prefix)
        except tl.ThemeError as exc:
            print(f"{RED('error')}: {exc}", file=sys.stderr)
            print("Nothing was installed; previous theme left untouched.",
                  file=sys.stderr)
            return 1

        for w in theme.warnings:
            print(f"{YELLOW('warning')}: {w}", file=sys.stderr)

        tl.install(staged)
        link_rofi(prefix, theme.slug)
        sync_noctalia(prefix, theme)
        sync_fastfetch(prefix, theme)
    finally:
        shutil.rmtree(stage, ignore_errors=True)

    if dry:
        print(f"{GREEN('rendered')} {theme.name} into {prefix} "
              f"(no state written, nothing reloaded)")
        return 0

    write_state(theme)
    print(f"{GREEN('theme')} {BOLD(theme.name)} ({theme.mode})")

    if args.no_reload:
        print(DIM("  reload skipped"))
        return 0

    kitty_conf = prefix / "kitty/theme/current-theme.conf"
    done, deferred = reload_apps(theme, kitty_conf)
    if done:
        print(DIM("  reloaded: " + ", ".join(done)))
    if deferred:
        print(DIM("  on next launch: " + ", ".join(deferred)))
    return 0


def cmd_current(args: argparse.Namespace) -> int:
    slug = current_slug()
    if not slug:
        print("none", file=sys.stderr)
        return 1
    print(slug)
    return 0


def cmd_mode(args: argparse.Namespace) -> int:
    slug = current_slug()
    if not slug:
        print("unknown", file=sys.stderr)
        return 1
    try:
        print(tl.load(THEMES_DIR / slug / "colors.toml").mode)
    except tl.ThemeError:
        print("unknown", file=sys.stderr)
        return 1
    return 0


def cmd_cycle(args: argparse.Namespace) -> int:
    slugs = sorted(p.name for p in THEMES_DIR.iterdir()
                   if (p / "colors.toml").is_file())
    if not slugs:
        print("no themes found", file=sys.stderr)
        return 1
    active = current_slug()
    i = slugs.index(active) if active in slugs else -1
    step = 1 if args.direction == "next" else -1
    args.slug = slugs[(i + step) % len(slugs)]
    args.no_reload = False
    args.prefix = None
    return cmd_set(args)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="theme-generate", description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("list")
    p.add_argument("--porcelain", action="store_true",
                   help="tab-separated, for scripts and menus")
    p.set_defaults(func=cmd_list)

    p = sub.add_parser("validate")
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("slug", nargs="?")
    g.add_argument("--all", action="store_true")
    p.set_defaults(func=cmd_validate)

    p = sub.add_parser("set")
    p.add_argument("slug")
    p.add_argument("--no-reload", action="store_true")
    p.add_argument("--prefix", help="render into DIR instead of ~/.config "
                                   "(implies no state write, no reload)")
    p.set_defaults(func=cmd_set)

    sub.add_parser("current").set_defaults(func=cmd_current)
    sub.add_parser("mode").set_defaults(func=cmd_mode)

    p = sub.add_parser("cycle")
    p.add_argument("direction", choices=("next", "previous"))
    p.set_defaults(func=cmd_cycle)

    args = ap.parse_args(argv)
    try:
        return args.func(args)
    except tl.ThemeError as exc:
        print(f"{RED('error')}: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
