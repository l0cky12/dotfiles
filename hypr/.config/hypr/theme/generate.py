#!/usr/bin/env python3
"""Generate and install the active desktop theme.

    generate.py --list
    generate.py --validate SLUG | --validate-all
    generate.py set SLUG [--no-reload] [--wallpaper] [--prefix DIR]

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
import time
import tomllib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import themelib as tl  # noqa: E402

HERE = Path(__file__).resolve().parent
TEMPLATES = HERE / "templates"
THEMES_DIR = HERE.parent / "themes"
STATE_FILE = THEMES_DIR / "current-theme"
CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
CACHE_HOME = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
WALLPAPER_STATE_FILE = Path(os.environ.get(
    "HYPR_WALLPAPER_STATE_FILE",
    Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
    / "hyprland-desktop/wallpaper/current",
))

# Colour output only when a human is watching.
_TTY = sys.stdout.isatty()
def _c(code: str, text: str) -> str:
    return f"\033[{code}m{text}\033[0m" if _TTY else text
BOLD = lambda s: _c("1", s)          # noqa: E731
GREEN = lambda s: _c("32", s)        # noqa: E731
YELLOW = lambda s: _c("33", s)       # noqa: E731
RED = lambda s: _c("31", s)          # noqa: E731
DIM = lambda s: _c("2", s)           # noqa: E731


OPTIONAL_TARGETS = {
    "neovim-theme.lua": "neovim",
    "btop-theme.tpl": "btop",
    "obsidian-theme.css": "obsidian",
}

OPTIONAL_DEPLOY_DIRS = {
    "neovim": Path("nvim/colors"),
    "btop": Path("btop/themes"),
    "obsidian": Path("obsidian/snippets"),
}


def targets(prefix: Path, theme: tl.Theme) -> list[tl.Artifact]:
    """Describe every template, destination, and validator.

    Destinations are real config paths, not copies: this repo is stowed, so
    ~/.config/<app> already points into it. Optional deployment is decided from
    the live XDG config tree even when `prefix` points at a harmless preview
    tree; ``--validate-all`` still renders every target.
    """
    return [
        tl.Artifact(
            "hyprland-decorations.lua", prefix / "hypr/conf/decorations.lua"
        ),
        tl.Artifact(
            "quickshell-theme.json", prefix / "hypr/themes/.active/theme.json"
        ),
        tl.Artifact("kitty-theme.conf", prefix / "kitty/theme/current-theme.conf"),
        tl.Artifact("zsh-theme.zsh", prefix / "zsh/current-theme.zsh"),
        tl.Artifact("rofi-theme.rasi", prefix / "rofi/color-themes/current.rasi"),
        tl.Artifact(
            "rofi-powermenu-theme.rasi", prefix / "rofi/powermenu/theme.rasi"
        ),
        tl.Artifact("hyprlock-colors.conf", prefix / "hyprlock/colors.conf"),
        tl.Artifact("swaync-style.css", prefix / "swaync/style.css"),
        tl.Artifact("wofi-style.css", prefix / "wofi/style.css"),
        tl.Artifact("noctalia-colors.json", prefix / "noctalia/colors.json"),
        tl.Artifact("greeter-theme.css", prefix / "greeter/greeter.css"),
        tl.Artifact("regreet-greeter.toml", prefix / "greeter/regreet.toml"),
        tl.Artifact(
            "neovim-theme.lua", prefix / f"nvim/colors/{theme.slug}.lua"
        ),
        tl.Artifact(
            "btop-theme.tpl", prefix / f"btop/themes/{theme.slug}.theme",
            validator=".theme",
        ),
        tl.Artifact(
            "obsidian-theme.css",
            prefix / "obsidian/snippets/generated-theme.css",
        ),
    ]


def deployed_targets(
    artifacts: list[tl.Artifact],
    live_prefix: Path,
) -> tuple[list[tl.Artifact], list[str]]:
    """Keep optional adapters whose live Stow-created directory exists.

    Artifact destinations may point at a harmless ``--prefix`` preview tree;
    deployment is always determined from the live config tree instead.
    """
    selected: list[tl.Artifact] = []
    messages: list[str] = []
    for artifact in artifacts:
        app = OPTIONAL_TARGETS.get(artifact.template)
        if app and not (live_prefix / OPTIONAL_DEPLOY_DIRS[app]).is_dir():
            messages.append(f"  {app}: skipped (not deployed)")
            continue
        selected.append(artifact)
    return selected, messages


# The greeter CSS/TOML get an extra check beyond "does it parse": did the
# render actually carry this theme's own colours/flags, rather than some
# copy-pasted placeholder. Keyed by template name (not suffix) because these
# checks are specific to these two files, unlike the generic VALIDATORS map.

GREETER_CSS_ROLES = ("accent", "urgent", "muted", "surface")
GREETER_CSS_MARKERS = (".suggested-action", "infobar.error", "entry")


def _rgb_csv(color: str) -> str:
    r, g, b = tl._rgb(color)
    return f"{r}, {g}, {b}"


def _check_greeter_css(out: Path, theme: tl.Theme) -> None:
    text = out.read_text()
    # A role may show up either as a raw "#rrggbb" (bare colour references
    # like `{{ muted }}`) or as the decimal triplet css_rgba() emits.
    missing_roles = [
        r for r in GREETER_CSS_ROLES
        if theme.colors[r] not in text and _rgb_csv(theme.colors[r]) not in text
    ]
    if missing_roles:
        raise tl.ThemeError(
            f"{out.name}: rendered CSS does not reference colour role(s) "
            f"{', '.join(missing_roles)} for theme '{theme.slug}'"
        )
    missing_markers = [m for m in GREETER_CSS_MARKERS if m not in text]
    if missing_markers:
        raise tl.ThemeError(
            f"{out.name}: rendered CSS is missing required selector(s) "
            f"{', '.join(missing_markers)}"
        )


REGREET_TOML_REQUIRED = (
    ("background", "path"), ("background", "fit"),
    ("GTK", "application_prefer_dark_theme"), ("GTK", "cursor_theme_name"),
    ("GTK", "font_name"), ("GTK", "theme_name"),
)


def _check_regreet_toml(out: Path) -> None:
    data = tomllib.loads(out.read_text())
    for table, key in REGREET_TOML_REQUIRED:
        if key not in (data.get(table) or {}):
            raise tl.ThemeError(f"{out.name}: [{table}] is missing required key '{key}'")


def build(
    theme: tl.Theme,
    stage: Path,
    prefix: Path,
    artifacts: list[tl.Artifact] | None = None,
) -> list[tuple[Path, Path]]:
    """Render every template into `stage` and validate it. Returns the
    (staged, destination) pairs ready for install."""
    staged: list[tuple[Path, Path]] = []
    chosen = artifacts if artifacts is not None else targets(prefix, theme)
    for artifact in chosen:
        name, dest = artifact.template, artifact.dest
        template = TEMPLATES / name
        if not template.is_file():
            raise tl.ThemeError(f"missing template: {template}")
        out = stage / name
        out.write_text(tl.render(template.read_text(), theme, origin=name))
        validator = tl.VALIDATORS.get(artifact.validator or out.suffix)
        if validator:
            validator(out)
        if name == "greeter-theme.css":
            _check_greeter_css(out, theme)
        elif name == "regreet-greeter.toml":
            _check_regreet_toml(out)
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

    # Hyprland re-reads decorations.lua, which it already requires.
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
    the emoji picker, capture menu and calculators all already read."""
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


def link_optional_themes(
    prefix: Path,
    theme: tl.Theme,
    installed_apps: set[str] | None = None,
) -> list[str]:
    """Keep stable aliases without making a completed install fail."""
    messages: list[str] = []
    outputs = (
        ("neovim", prefix / "nvim/colors", ".lua", "generated Neovim colorscheme"),
        ("btop", prefix / "btop/themes", ".theme", "generated btop theme"),
    )
    for app, directory, suffix, marker in outputs:
        if installed_apps is not None and app not in installed_apps:
            continue
        try:
            current = directory / f"{theme.slug}{suffix}"
            if not current.is_file():
                continue
            for candidate in directory.glob(f"*{suffix}"):
                if candidate == current or candidate.name == f"current{suffix}":
                    continue
                try:
                    with candidate.open(encoding="utf-8") as handle:
                        first_line = handle.readline()
                except (OSError, UnicodeDecodeError):
                    continue
                if marker in first_line:
                    candidate.unlink()
            link = directory / f"current{suffix}"
            if link.is_file() and not link.is_symlink():
                try:
                    with link.open(encoding="utf-8") as handle:
                        first_line = handle.readline()
                except (OSError, UnicodeDecodeError):
                    first_line = ""
                if marker not in first_line:
                    messages.append(
                        f"  {app}: warning ({link.name} is a user-owned file; "
                        "alias not updated)"
                    )
                    continue
            tmp = directory / f".current{suffix}.new"
            if tmp.is_symlink() or tmp.exists():
                tmp.unlink()
            tmp.symlink_to(current.name)
            os.replace(tmp, link)
        except OSError as exc:
            messages.append(
                f"  {app}: warning (could not update current theme alias: {exc})"
            )
    return messages


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


def sync_btop_config(_prefix: Path, _theme: tl.Theme) -> str:
    """Advise without reading or modifying user-owned btop configuration."""
    return '  btop: set color_theme = "current" in btop.conf once'


# ── Wallpaper ────────────────────────────────────────────────────────────────
# Deliberately outside the atomic guarantee: this is a runtime action like the
# app reloads, not a generated file. A wallpaper daemon problem must never fail
# a colour switch that has already been installed successfully.

def apply_wallpaper(theme: tl.Theme) -> str:
    """Set the desktop wallpaper for `theme`. Returns a one-line status."""
    path = tl.resolve_wallpaper(theme.wallpaper)
    if path is None:
        # A theme with no asset leaves whatever is on screen alone. Clearing it
        # would be worse than doing nothing -- you would lose your wallpaper by
        # switching to a theme that simply has not been given one yet.
        return f"unchanged (no asset for {theme.slug})"

    if not shutil.which("hyprctl") or not shutil.which("hyprpaper"):
        return "skipped (hyprpaper not installed)"

    # hyprpaper.conf sets ipc = true, so a running daemon takes hyprctl commands.
    # It is started here as well as from autostart so a first switch works
    # without needing to log out.
    if not _pids_of("hyprpaper"):
        try:
            subprocess.Popen(
                ["hyprpaper"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        except OSError as exc:
            return f"failed to start hyprpaper: {exc}"
        # Give the daemon a moment to create its IPC socket before talking to it.
        for _ in range(20):
            time.sleep(0.05)
            if _pids_of("hyprpaper"):
                break

    target = str(path)
    # `preload` and `unload` are best-effort: hyprpaper up to 0.7 required an
    # explicit preload before a wallpaper could be set, while 0.8 (verified here
    # on 0.8.4) removed them from the IPC surface and loads on demand -- it
    # answers both with "invalid hyprpaper request". Only the `wallpaper` call is
    # treated as authoritative, so this works on either version.
    _run(["hyprctl", "hyprpaper", "preload", target], timeout=10)
    # An empty monitor field means every output.
    if not _run(["hyprctl", "hyprpaper", "wallpaper", f",{target}"], timeout=10):
        return f"failed to set {path.name}"
    _run(["hyprctl", "hyprpaper", "unload", "unused"], timeout=10)
    try:
        WALLPAPER_STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
        fd, state_tmp_name = tempfile.mkstemp(
            prefix=".current.", dir=WALLPAPER_STATE_FILE.parent
        )
        state_tmp = Path(state_tmp_name)
        with os.fdopen(fd, "w") as state_handle:
            json.dump({"path": str(path.resolve())}, state_handle)
            state_handle.write("\n")
        os.replace(state_tmp, WALLPAPER_STATE_FILE)
    except OSError:
        try:
            state_tmp.unlink(missing_ok=True)
        except (NameError, OSError):
            pass
        return f"{path.name} (state not saved)"
    return path.name


# ── Greeter system install ───────────────────────────────────────────────────
# The only place `theme set` would touch anything outside $HOME. Opt-in via
# `--install-greeter`: `theme set` is also invoked with no TTY attached (the
# Quickshell picker, SUPER+T, `theme next`/`previous`), where a sudo password
# prompt would just hang. Every other caller is unaffected by this default.

GREETER_ETC_TARGETS = (
    ("greeter/greeter.css", "/etc/greetd/regreet.css"),
    ("greeter/regreet.toml", "/etc/greetd/regreet.toml"),
)


def install_greeter_to_etc(prefix: Path, dry_run: bool) -> None:
    commands = [
        ["sudo", "install", "-m", "644", str(prefix / src), dest]
        for src, dest in GREETER_ETC_TARGETS
    ]
    if dry_run:
        for cmd in commands:
            print(DIM("  " + " ".join(cmd)))
        return
    for cmd in commands:
        if subprocess.run(cmd).returncode != 0:
            print(f"{RED('error')}: failed: {' '.join(cmd)}", file=sys.stderr)
            return
    print(GREEN("  installed greeter.css and regreet.toml into /etc/greetd/"))
    print(DIM("  regreet reads these at greeter startup, not live -- restart "
              "greetd to apply now: sudo systemctl restart greetd"))


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
            selected, target_messages = deployed_targets(
                targets(prefix, theme), CONFIG_HOME
            )
            staged = build(theme, stage, prefix, selected)
        except tl.ThemeError as exc:
            print(f"{RED('error')}: {exc}", file=sys.stderr)
            print("Nothing was installed; previous theme left untouched.",
                  file=sys.stderr)
            return 1

        for w in theme.warnings:
            print(f"{YELLOW('warning')}: {w}", file=sys.stderr)

        mandatory_staged: list[tuple[Path, Path]] = []
        optional_staged: list[tuple[str, tuple[Path, Path]]] = []
        for artifact, staged_pair in zip(selected, staged, strict=True):
            app = OPTIONAL_TARGETS.get(artifact.template)
            if app:
                optional_staged.append((app, staged_pair))
            else:
                mandatory_staged.append(staged_pair)

        tl.install(mandatory_staged)
        link_rofi(prefix, theme.slug)
        sync_noctalia(prefix, theme)
        sync_fastfetch(prefix, theme)

        installed_optional: set[str] = set()
        for app, staged_pair in optional_staged:
            try:
                tl.install([staged_pair])
            except OSError as exc:
                target_messages.append(
                    f"  {app}: warning (could not install generated theme: {exc})"
                )
            else:
                installed_optional.add(app)

        target_messages.extend(
            link_optional_themes(prefix, theme, installed_optional)
        )
        if "btop" in installed_optional:
            target_messages.append(sync_btop_config(prefix, theme))
        if "obsidian" in installed_optional:
            target_messages.append(
                "  obsidian: enable generated-theme.css in Settings > Appearance "
                "> CSS snippets"
            )
    finally:
        shutil.rmtree(stage, ignore_errors=True)

    if dry:
        print(f"{GREEN('rendered')} {theme.name} into {prefix} "
              f"(no state written, nothing reloaded)")
        for message in target_messages:
            print(DIM(message))
        return 0

    write_state(theme)
    print(f"{GREEN('theme')} {BOLD(theme.name)} ({theme.mode})")
    for message in target_messages:
        print(DIM(message))

    if args.no_reload:
        print(DIM("  reload skipped"))
        return 0

    if args.wallpaper:
        print(DIM("  wallpaper: " + apply_wallpaper(theme)))

    kitty_conf = prefix / "kitty/theme/current-theme.conf"
    done, deferred = reload_apps(theme, kitty_conf)
    if done:
        print(DIM("  reloaded: " + ", ".join(done)))
    if deferred:
        print(DIM("  on next launch: " + ", ".join(deferred)))

    if args.install_greeter:
        install_greeter_to_etc(prefix, args.dry_run)

    return 0


# Palette subset the picker needs to draw a preview. Kept explicit so the UI
# contract is visible here rather than implied by whatever the theme happens to
# define, and so QML never has to handle a missing key.
INDEX_COLORS = (
    ("background", "background"), ("backgroundAlt", "background_alt"),
    ("surface", "surface"), ("surfaceAlt", "surface_alt"),
    ("overlay", "overlay"),
    ("foreground", "foreground"), ("foregroundBright", "foreground_bright"),
    ("muted", "muted"),
    ("accent", "accent"), ("accentAlt", "accent_alt"),
    ("border", "border"), ("borderActive", "border_active"),
    ("red", "red"), ("green", "green"), ("yellow", "yellow"),
    ("blue", "blue"), ("magenta", "magenta"), ("cyan", "cyan"),
)


def build_index() -> dict:
    """Everything a visual picker needs, in one JSON document.

    All filesystem probing (wallpaper resolution) happens here so the shell UI
    stays pure QML with no Process per tile. Broken themes are reported rather
    than raised, so one bad file cannot blank the picker.
    """
    themes, errors = tl.load_all_tolerant(THEMES_DIR)
    active = current_slug() or ""
    rows = []
    for slug, theme in themes.items():
        wallpaper = tl.resolve_wallpaper(theme.wallpaper)
        rows.append({
            "slug": slug,
            "name": theme.name,
            "mode": theme.mode,
            "description": theme.description,
            "family": theme.family,
            "wallpaper": str(wallpaper) if wallpaper else "",
            "colors": {
                key: theme.colors[src] for key, src in INDEX_COLORS
            } | {"onAccent": tl.namespace(theme)["fg_on"](theme.colors["accent"])},
            "style": {
                "rounding": int(theme.style["rounding"]),
                "borderWidth": int(theme.style["border_width"]),
                "surfaceOpacity": float(theme.style["surface_opacity"]),
            },
        })
    return {"active": active, "themes": rows, "errors": errors}


def cmd_index(args: argparse.Namespace) -> int:
    index = build_index()
    if args.json:
        json.dump(index, sys.stdout)
        sys.stdout.write("\n")
        return 0

    print(f"{len(index['themes'])} theme(s), active: {index['active'] or 'none'}")
    missing = []
    for row in index["themes"]:
        mark = GREEN("*") if row["slug"] == index["active"] else " "
        wp = row["wallpaper"]
        print(f" {mark} {BOLD(row['slug']):<32} {row['name']:<22} "
              f"{DIM(row['mode']):<10} {'wallpaper' if wp else DIM('no wallpaper')}")
        if not wp:
            missing.append(row["slug"])
    if missing:
        print(f"\n{len(missing)} theme(s) with no wallpaper asset: "
              + ", ".join(missing))
        print(DIM("  drop an image at wallpaper/theme/<name>.jpg to fill one in"))
    for err in index["errors"]:
        print(f" {RED('FAIL')} {err['slug']}: {err['error']}", file=sys.stderr)
    return 1 if index["errors"] else 0


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
    args.install_greeter = False
    args.dry_run = False
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
    wallpaper_flags = p.add_mutually_exclusive_group()
    wallpaper_flags.add_argument(
        "--wallpaper", action="store_true",
        help="also apply the theme's wallpaper (the default preserves it)")
    wallpaper_flags.add_argument(
        "--no-wallpaper", dest="wallpaper", action="store_false",
        help=argparse.SUPPRESS)
    p.set_defaults(wallpaper=False)
    p.add_argument("--prefix", help="render into DIR instead of ~/.config "
                                   "(implies no state write, no reload)")
    p.add_argument(
        "--install-greeter", action="store_true",
        help="also copy rendered greeter.css/regreet.toml into /etc/greetd/ "
             "via sudo (off by default; a no-op with --prefix)")
    p.add_argument(
        "--dry-run", action="store_true",
        help="with --install-greeter, print the sudo install commands "
             "instead of running them")
    p.set_defaults(func=cmd_set)

    p = sub.add_parser("index", help="machine-readable theme list for the picker")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_index)

    sub.add_parser("current").set_defaults(func=cmd_current)
    sub.add_parser("mode").set_defaults(func=cmd_mode)

    p = sub.add_parser("cycle")
    p.add_argument("direction", choices=("next", "previous"))
    p.add_argument(
        "--wallpaper", action="store_true",
        help="also apply the next theme's wallpaper (the default preserves it)")
    p.set_defaults(func=cmd_cycle)

    args = ap.parse_args(argv)
    try:
        return args.func(args)
    except tl.ThemeError as exc:
        print(f"{RED('error')}: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
