"""Semantic desktop theme system — palette loading, validation and rendering.

One `themes/<slug>/colors.toml` per theme is the single source of truth. This
module turns it into the per-application files each app already reads:

    colors.toml -> validate -> render templates -> stage -> atomic install

Nothing here reloads anything; `generate.py` owns that. Nothing here writes
outside the staging directory until `install()` is called, so a validation
failure can never leave the desktop half-switched.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

# ── Schema ───────────────────────────────────────────────────────────────────
# Roles an adapter is allowed to rely on. Every theme must define all of these;
# there is no silent default for a colour, because a missing colour means the
# theme author has not decided what that role looks like (see §48).

REQUIRED_COLORS = (
    "background", "background_alt", "surface", "surface_alt", "overlay",
    "foreground", "foreground_bright", "muted", "disabled",
    "accent", "accent_alt",
    "red", "green", "yellow", "blue", "magenta", "cyan",
    "selection", "border", "border_active", "urgent", "shadow",
)

# Status roles. These *do* default, because "warning is the yellow one" is true
# often enough that spelling it out in 23 files would be noise. A theme whose
# identity needs a different warning colour just sets it.
STATUS_DEFAULTS = {
    "success": "green",
    "warning": "yellow",
    "critical": "red",
    "info": "cyan",
}

ANSI_BASE = ("black", "red", "green", "yellow", "blue", "magenta", "cyan", "white")
REQUIRED_ANSI = ANSI_BASE + tuple("bright_" + n for n in ANSI_BASE)

# Structural tokens. Gaps are deliberately *not* per-theme personality: window
# management must not reflow when the palette changes (§15), so they default the
# same everywhere and a theme has to go out of its way to differ.
STYLE_DEFAULTS = {
    "rounding": 10,
    "border_width": 2,
    "surface_opacity": 0.92,
    "scrim_opacity": 0.50,
    "shadow_opacity": 0.40,
    "blur": True,
    "blur_size": 8,
    "blur_passes": 2,
    "gaps_in": 6,
    "gaps_out": 12,
    "active_opacity": 1.0,
    "inactive_opacity": 0.95,
    "shadow_range": 18,
    "shadow_render_power": 3,
    "border_angle": "45deg",
    # Blur look. Hardcoded in the old generator; surfaced here so it is tunable
    # without being something every theme has to think about.
    "blur_noise": 0.01,
    "blur_contrast": 0.95,
    "blur_brightness": 0.82,
    "blur_vibrancy": 0.18,
}

HEX_RE = re.compile(r"^#[0-9a-fA-F]{6}$")
MODES = ("dark", "light")


class ThemeError(Exception):
    """A theme is unusable. Carries a message meant for the user, not a trace."""


# ── Colour maths ─────────────────────────────────────────────────────────────

def _rgb(color: str) -> tuple[int, int, int]:
    c = color.lstrip("#")
    return int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16)


def _relative_luminance(color: str) -> float:
    def channel(v: int) -> float:
        s = v / 255.0
        return s / 12.92 if s <= 0.03928 else ((s + 0.055) / 1.055) ** 2.4
    r, g, b = _rgb(color)
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def contrast_ratio(fg: str, bg: str) -> float:
    """WCAG 2.1 contrast ratio. 4.5 is the AA threshold for body text."""
    a, b = _relative_luminance(fg), _relative_luminance(bg)
    lo, hi = sorted((a, b))
    return (hi + 0.05) / (lo + 0.05)


# The 6x6x6 cube plus greyscale ramp of the xterm-256 palette, used to degrade
# truecolor hex to an index for terminals that cannot do better.
def _x256_palette() -> list[tuple[int, int, int]]:
    levels = (0, 95, 135, 175, 215, 255)
    pal: list[tuple[int, int, int]] = [(0, 0, 0)] * 16  # 0-15 are terminal-defined
    for r in levels:
        for g in levels:
            for b in levels:
                pal.append((r, g, b))
    for i in range(24):
        v = 8 + i * 10
        pal.append((v, v, v))
    return pal


_X256 = _x256_palette()


def x256(color: str) -> int:
    """Nearest xterm-256 index (searching 16-255; 0-15 are theme-dependent)."""
    r, g, b = _rgb(color)
    best, best_d = 16, None
    for i in range(16, 256):
        pr, pg, pb = _X256[i]
        d = (pr - r) ** 2 + (pg - g) ** 2 + (pb - b) ** 2
        if best_d is None or d < best_d:
            best, best_d = i, d
    return best


# ── Template helpers ─────────────────────────────────────────────────────────
# These are the vocabulary available inside `{{ }}` in a template. Keeping alpha
# derivation in the templates (rather than pre-flattening every colour x every
# opacity into the namespace) is what keeps the namespace small and readable.

def _clamp01(v: float) -> float:
    return max(0.0, min(1.0, float(v)))


def hex_no_hash(color: str) -> str:
    return color.lstrip("#").lower()


def hexa(color: str, alpha: float = 1.0) -> str:
    """#RRGGBBAA — Qt, and anything else that takes 8-digit hex."""
    return f"{color.lower()}{round(_clamp01(alpha) * 255):02x}"


def hypr_rgba(color: str, alpha: float = 1.0) -> str:
    """Hyprland's rgba(aabbccff) form."""
    return f"rgba({hex_no_hash(color)}{round(_clamp01(alpha) * 255):02x})"


def rgba(color: str, alpha: float = 1.0) -> str:
    """Rofi's rgba(r, g, b, NN%) form."""
    r, g, b = _rgb(color)
    return f"rgba({r}, {g}, {b}, {round(_clamp01(alpha) * 100)}%)"


def css_rgba(color: str, alpha: float = 1.0) -> str:
    """GTK/CSS rgba(r, g, b, 0.NN) form."""
    r, g, b = _rgb(color)
    return f"rgba({r}, {g}, {b}, {round(_clamp01(alpha), 3)})"


def mix(a: str, b: str, t: float = 0.5) -> str:
    """Linear blend, t=0 -> a, t=1 -> b. Used to derive tints that must stay
    readable in both modes rather than assuming white or black."""
    t = _clamp01(t)
    ra, ga, ba = _rgb(a)
    rb, gb, bb = _rgb(b)
    return "#%02x%02x%02x" % (
        round(ra + (rb - ra) * t),
        round(ga + (gb - ga) * t),
        round(ba + (bb - ba) * t),
    )


# ── Theme model ──────────────────────────────────────────────────────────────

@dataclass
class Theme:
    slug: str
    name: str
    mode: str
    description: str
    family: str
    wallpaper: str | None
    colors: dict[str, str]
    ansi: dict[str, str]
    style: dict[str, object]
    warnings: list[str] = field(default_factory=list)

    @property
    def is_dark(self) -> bool:
        return self.mode == "dark"


def load(path: Path) -> Theme:
    """Parse and validate one colors.toml. Raises ThemeError with a message that
    names the file and the specific problem."""
    where = path.parent.name
    try:
        with path.open("rb") as fh:
            raw = tomllib.load(fh)
    except FileNotFoundError:
        raise ThemeError(f"{where}: no colors.toml at {path}")
    except tomllib.TOMLDecodeError as exc:
        raise ThemeError(f"{where}: colors.toml is not valid TOML: {exc}")

    meta = raw.get("theme")
    if not isinstance(meta, dict):
        raise ThemeError(f"{where}: missing [theme] table")

    for key in ("name", "slug", "mode"):
        if not meta.get(key):
            raise ThemeError(f"{where}: [theme] is missing required key '{key}'")

    slug = meta["slug"]
    if slug != where:
        raise ThemeError(
            f"{where}: [theme].slug is '{slug}' but the directory is '{where}' — "
            "they must match so the state file resolves to one place"
        )
    if meta["mode"] not in MODES:
        raise ThemeError(
            f"{where}: [theme].mode is '{meta['mode']}', expected one of {MODES}"
        )

    colors = _load_colors(raw, where)
    ansi = _load_ansi(raw, where)

    style = dict(STYLE_DEFAULTS)
    for key, value in (raw.get("style") or {}).items():
        if key not in STYLE_DEFAULTS:
            raise ThemeError(
                f"{where}: unknown [style] key '{key}'. Known keys: "
                + ", ".join(sorted(STYLE_DEFAULTS))
            )
        style[key] = value

    theme = Theme(
        slug=slug,
        name=meta["name"],
        mode=meta["mode"],
        description=meta.get("description", ""),
        family=meta.get("family", slug),
        wallpaper=meta.get("wallpaper"),
        colors=colors,
        ansi=ansi,
        style=style,
    )
    theme.warnings = check_contrast(theme)
    return theme


def _load_colors(raw: dict, where: str) -> dict[str, str]:
    colors = raw.get("colors")
    if not isinstance(colors, dict):
        raise ThemeError(f"{where}: missing [colors] table")

    known = set(REQUIRED_COLORS) | set(STATUS_DEFAULTS)
    missing = [k for k in REQUIRED_COLORS if k not in colors]
    if missing:
        raise ThemeError(f"{where}: [colors] is missing: {', '.join(missing)}")
    unknown = sorted(set(colors) - known)
    if unknown:
        raise ThemeError(
            f"{where}: unknown [colors] key(s): {', '.join(unknown)}. "
            "Add the role to REQUIRED_COLORS if it is meant to be part of the schema."
        )
    for key, value in colors.items():
        if not isinstance(value, str) or not HEX_RE.match(value):
            raise ThemeError(
                f"{where}: [colors].{key} = {value!r} is not a '#RRGGBB' hex colour"
            )

    resolved = {k: v.lower() for k, v in colors.items()}
    for status, fallback in STATUS_DEFAULTS.items():
        resolved.setdefault(status, resolved[fallback])
    return resolved


def _load_ansi(raw: dict, where: str) -> dict[str, str]:
    ansi = raw.get("ansi")
    if not isinstance(ansi, dict):
        raise ThemeError(f"{where}: missing [ansi] table")
    missing = [k for k in REQUIRED_ANSI if k not in ansi]
    if missing:
        raise ThemeError(
            f"{where}: [ansi] is missing {len(missing)} of 16 colours: "
            + ", ".join(missing)
        )
    unknown = sorted(set(ansi) - set(REQUIRED_ANSI))
    if unknown:
        raise ThemeError(f"{where}: unknown [ansi] key(s): {', '.join(unknown)}")
    for key, value in ansi.items():
        if not isinstance(value, str) or not HEX_RE.match(value):
            raise ThemeError(
                f"{where}: [ansi].{key} = {value!r} is not a '#RRGGBB' hex colour"
            )
    return {k: v.lower() for k, v in ansi.items()}


def load_all(themes_dir: Path) -> dict[str, Theme]:
    """Every theme in the tree, keyed by slug. Raises on the first bad one."""
    out: dict[str, Theme] = {}
    for entry in sorted(themes_dir.iterdir()):
        toml = entry / "colors.toml"
        if entry.is_dir() and toml.is_file():
            theme = load(toml)
            out[theme.slug] = theme
    return out


# ── Contrast ─────────────────────────────────────────────────────────────────
# Reported, never auto-corrected: silently substituting a colour would make the
# theme lie about itself (§48). The author gets told which pair to fix.

CONTRAST_CHECKS = (
    ("foreground", "background", 4.5, "body text"),
    ("foreground_bright", "background", 4.5, "emphasised text"),
    ("muted", "background", 3.0, "muted text / inactive workspaces"),
    ("muted", "surface", 3.0, "muted text on cards"),
    ("foreground", "surface", 4.5, "text on cards"),
)

# ANSI `black` (color0) is *meant* to sit next to the background in every
# terminal theme, so it is deliberately not checked. `bright_black` (color8) is,
# because that is what diff tools and shells use for comments and de-emphasis --
# if it is invisible, real information is lost.
ANSI_CONTRAST_CHECKS = ("blue", "magenta", "red", "green", "yellow", "cyan")
ANSI_DIM_CHECKS = ("bright_black",)


def check_contrast(theme: Theme) -> list[str]:
    warnings: list[str] = []
    for fg, bg, threshold, label in CONTRAST_CHECKS:
        ratio = contrast_ratio(theme.colors[fg], theme.colors[bg])
        if ratio < threshold:
            warnings.append(
                f"{theme.slug}: {label} — {fg} on {bg} is {ratio:.2f}:1 "
                f"(want >= {threshold})"
            )
    bg = theme.colors["background"]
    for name in ANSI_CONTRAST_CHECKS:
        ratio = contrast_ratio(theme.ansi[name], bg)
        if ratio < 2.5:
            warnings.append(
                f"{theme.slug}: terminal ansi.{name} is {ratio:.2f}:1 against "
                "the background — it will be hard to read"
            )
    for name in ANSI_DIM_CHECKS:
        ratio = contrast_ratio(theme.ansi[name], bg)
        if ratio < 1.9:
            warnings.append(
                f"{theme.slug}: terminal ansi.{name} is {ratio:.2f}:1 — comments "
                "and dimmed output will be effectively invisible"
            )
    return warnings


# ── Rendering ────────────────────────────────────────────────────────────────

_EXPR_RE = re.compile(r"\{\{(.+?)\}\}", re.DOTALL)


class _Ansi(dict):
    """Attribute access for `{{ ansi.bright_blue }}` in templates."""

    def __getattr__(self, name: str) -> str:
        try:
            return self[name]
        except KeyError:
            raise AttributeError(name) from None


def namespace(theme: Theme) -> dict[str, object]:
    """What a template may refer to. Explicit, so a typo in a template is an
    error rather than a silent empty string."""
    ns: dict[str, object] = {}
    ns.update(theme.colors)
    ns.update(theme.style)
    ns["ansi"] = _Ansi(theme.ansi)
    ns["theme_name"] = theme.name
    ns["theme_slug"] = theme.slug
    ns["theme_mode"] = theme.mode
    ns["theme_description"] = theme.description
    ns["theme_family"] = theme.family
    ns["theme_wallpaper"] = theme.wallpaper or ""
    ns["is_dark"] = theme.is_dark

    # Derived structural tokens. Computed here rather than as template
    # conditionals so every adapter agrees on what "this theme is squarer"
    # means. `radius_pill` keeps the existing fully-rounded bar/launcher look
    # for the soft themes and squares up the hard-geometry ones (Lumon,
    # Retro 82, Hackerman) instead of forcing one shape on all 23.
    rounding = int(theme.style["rounding"])
    ns["radius_pill"] = 999 if rounding >= 10 else max(0, round(rounding * 1.4))
    ns["radius_panel"] = max(0, round(rounding * 1.4))
    ns["radius_row"] = max(0, round(rounding * 0.9))
    ns["radius_input"] = max(0, round(rounding * 1.1))

    # Helpers
    ns.update(
        rgba=rgba, css_rgba=css_rgba, hexa=hexa, hypr_rgba=hypr_rgba,
        mix=mix, hex_no_hash=hex_no_hash, x256=x256,
        contrast_ratio=contrast_ratio,
        json_str=lambda v: json.dumps(v),
        round=round, max=max, min=min, int=int, float=float, abs=abs,
        on=lambda flag, yes="true", no="false": yes if flag else no,
        # `fg_on(c)` picks whichever of the theme's extremes reads on `c`.
        # Templates use it instead of assuming white-on-accent, which is what
        # breaks light themes.
        fg_on=lambda c: (
            theme.colors["background_alt"]
            if contrast_ratio(theme.colors["background_alt"], c)
            >= contrast_ratio(theme.colors["foreground_bright"], c)
            else theme.colors["foreground_bright"]
        ),
    )
    return ns


def render(template: str, theme: Theme, origin: str = "<template>") -> str:
    ns = namespace(theme)

    def sub(match: re.Match[str]) -> str:
        expr = match.group(1).strip()
        try:
            value = eval(expr, {"__builtins__": {}}, ns)  # noqa: S307 - fixed namespace
        except Exception as exc:
            raise ThemeError(
                f"{origin}: cannot evaluate '{{{{ {expr} }}}}' for theme "
                f"'{theme.slug}': {type(exc).__name__}: {exc}"
            ) from None
        if value is None:
            raise ThemeError(f"{origin}: '{{{{ {expr} }}}}' evaluated to None")
        return str(value)

    out = _EXPR_RE.sub(sub, template)
    if "{{" in out or "}}" in out:
        raise ThemeError(f"{origin}: unresolved template markers remain after render")
    return out


# ── Artifact validation ──────────────────────────────────────────────────────
# Each check knows only about the file it is handed, so it works the same on a
# staged file as on an installed one.

def _balanced_braces(text: str, origin: str, hash_comments: bool = False) -> None:
    """Cheap structural sanity check for the formats with no real validator.

    `hash_comments` is off by default because in CSS a leading `#` is an id
    selector, not a comment -- stripping it would eat `#workspaces { ... }` and
    report the file as unbalanced.
    """
    depth = 0
    in_block_comment = False
    for lineno, line in enumerate(text.splitlines(), 1):
        code = line
        if in_block_comment:
            if "*/" in code:
                code = code.split("*/", 1)[1]
                in_block_comment = False
            else:
                continue
        while "/*" in code:
            head, rest = code.split("/*", 1)
            if "*/" in rest:
                code = head + rest.split("*/", 1)[1]
            else:
                code = head
                in_block_comment = True
                break
        code = code.split("//")[0]
        if hash_comments:
            code = code.split("#")[0]
        depth += code.count("{") - code.count("}")
        if depth < 0:
            raise ThemeError(f"{origin}: unbalanced '}}' at line {lineno}")
    if depth != 0:
        raise ThemeError(f"{origin}: {depth} unclosed '{{' block(s)")


def validate_json(path: Path) -> None:
    try:
        json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        raise ThemeError(f"{path.name}: generated JSON is invalid: {exc}") from None


def validate_css(path: Path) -> None:
    _balanced_braces(path.read_text(), path.name)


def validate_conf(path: Path) -> None:
    _balanced_braces(path.read_text(), path.name, hash_comments=True)


def validate_kitty(path: Path) -> None:
    """Kitty's palette is the whole point of the terminal adapter, so check that
    all 16 slots are present and every colour directive is well formed."""
    text = path.read_text()
    seen = set()
    for lineno, line in enumerate(text.splitlines(), 1):
        line = line.split("#")[0].strip() if not line.lstrip().startswith("#") else ""
        if not line:
            continue
        parts = line.split()
        key = parts[0]
        if re.fullmatch(r"color\d+", key):
            seen.add(key)
        if key.endswith("color") or key in {
            "background", "foreground", "cursor", "selection_background",
            "selection_foreground",
        } or re.fullmatch(r"color\d+", key):
            if len(parts) < 2 or not HEX_RE.match(parts[1]):
                raise ThemeError(
                    f"{path.name}:{lineno}: '{key}' is not followed by a #RRGGBB value"
                )
    missing = [f"color{i}" for i in range(16) if f"color{i}" not in seen]
    if missing:
        raise ThemeError(
            f"{path.name}: terminal palette is incomplete, missing {', '.join(missing)}"
        )


def validate_rasi(path: Path) -> None:
    """Rofi is the one app that ships a real theme parser; use it."""
    if not shutil.which("rofi"):
        _balanced_braces(path.read_text(), path.name)
        return  # structural check is the best available fallback
    proc = subprocess.run(
        ["rofi", "-no-config", "-theme", str(path), "-dump-theme"],
        capture_output=True, text=True, timeout=15,
    )
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout).strip().splitlines()
        raise ThemeError(
            f"{path.name}: rofi rejected the generated theme: "
            + (detail[0] if detail else f"exit {proc.returncode}")
        )


def validate_zsh(path: Path) -> None:
    if not shutil.which("zsh"):
        return
    proc = subprocess.run(
        ["zsh", "-n", str(path)], capture_output=True, text=True, timeout=15
    )
    if proc.returncode != 0:
        raise ThemeError(
            f"{path.name}: generated zsh has a syntax error: {proc.stderr.strip()}"
        )


VALIDATORS = {
    ".json": validate_json,
    ".css": validate_css,
    ".conf": validate_conf,
    ".rasi": validate_rasi,
    ".zsh": validate_zsh,
}


# ── Install ──────────────────────────────────────────────────────────────────

@dataclass
class Artifact:
    """One rendered file on its way to one destination."""
    template: str          # filename under templates/
    dest: Path             # final location
    validator: str | None = None   # override the extension-based choice


def install(staged: list[tuple[Path, Path]]) -> None:
    """Move every staged file to its destination.

    Each move is `os.replace` against a temp file in the destination's own
    directory, so no reader ever sees a partial file. This runs only after all
    rendering and validation has succeeded, which is what makes a failed switch
    a no-op rather than a half-switched desktop.
    """
    for src, dest in staged:
        dest.parent.mkdir(parents=True, exist_ok=True)
        tmp = dest.parent / f".{dest.name}.new"
        shutil.copyfile(src, tmp)
        shutil.copymode(src, tmp)
        os.replace(tmp, dest)
