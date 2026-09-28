"""Web app manager -- validation, identity, icons and managed paths.

A "web app" here is a website promoted to a first-class launcher: some metadata
we own, an icon we own, and a .desktop file we own. This module is the part that
decides what is valid and where things live; manager.py drives it.

Ownership rule, which everything else depends on: an app belongs to this manager
if and only if it has a metadata file in APPS_DIR. Removal never infers ownership
from a filename or from what a .desktop file happens to Exec.

Everything a website gives us -- HTML, icon bytes, redirect targets -- is
untrusted. Nothing from a URL ever reaches a shell.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import unicodedata
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urljoin, urlsplit, urlunsplit

# ── Paths ────────────────────────────────────────────────────────────────────
# Managed state lives under XDG_DATA_HOME rather than in the dotfiles tree:
# ~/.config/hypr is a stow symlink into the git repo, and runtime user data
# written there would show up as repo changes. Engine code is versioned; the apps
# you create are yours.

CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
DATA_HOME = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
CACHE_HOME = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
RUNTIME_DIR = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp"))

ROOT = DATA_HOME / "webapps"
APPS_DIR = ROOT / "apps"          # <id>.toml -- the ownership marker
ICONS_DIR = ROOT / "icons"        # <id>.<ext>
DESKTOP_DIR = DATA_HOME / "applications"

DESKTOP_PREFIX = "webapp-"
MARKER_KEY = "X-Hypr-WebApp"
MARKER_ID_KEY = "X-Hypr-WebApp-ID"
SCHEMA_VERSION = 1

# The launch helper the generated .desktop files point at. Resolved through the
# stow symlink so the entry keeps working if the repo moves.
LAUNCH_HELPER = Path.home() / ".local/bin/webapp-launch"

# The browser order is: $WEBAPP_BROWSER, then the XDG default browser when it is
# Chromium-family, then the first of these on PATH. Only Chromium derivatives
# qualify because --app= is a Chromium switch; Firefox has no equivalent
# single-site mode, so a Firefox default falls through to this list.
BROWSER_CANDIDATES = (
    "brave",
    "chromium",
    "chromium-browser",
    "google-chrome",
    "google-chrome-stable",
    "helium-browser",
)

# Executable names, as a desktop entry's Exec runs them, that accept --app=.
CHROMIUM_EXECUTABLES = frozenset(BROWSER_CANDIDATES) | {
    "brave-browser",
    "helium",
    "microsoft-edge",
    "microsoft-edge-stable",
    "vivaldi",
    "vivaldi-stable",
}

# The handlers that name the default browser, most telling first.
BROWSER_MIME_TYPES = ("x-scheme-handler/https", "x-scheme-handler/http")

ALLOWED_SCHEMES = ("http", "https")

# Chromium-family browsers build their own WM class for an app-mode window and
# ignore --class on Wayland. Verified on Brave 151: `--app=https://youtube.com/`
# produces `brave-youtube.com__-Default`, and `--app=https://example.com/app?x=1`
# produces `brave-example.com__app-Default` -- host, then "__", then the path
# with slashes folded to underscores, then the profile name. The query string is
# dropped.
#
# The leading product is Brave's own name, but other derivatives keep Chromium's
# `chrome`: verified on Helium, whose app windows are `chrome-<host>__-Default`
# while its normal windows are `helium`.
#
# This is recorded rather than imposed: it is what Hyprland will actually see, so
# it is what a per-app window rule has to match. It also means every web app has
# a class distinct from plain `brave-browser`, which is why the existing
# `^(brave-browser)$ -> workspace 2` rule does not capture web apps.
BROWSER_PROFILE = "Default"


def derived_wm_class(url: str, browser: str = "brave") -> str:
    """The window class the browser will give this app's window.

    Derived, not assigned -- see BROWSER_PROFILE. Only meaningful for
    Chromium-family browsers using the default profile.
    """
    parts = urlsplit(url)
    product = "brave" if Path(browser).name.lower().startswith("brave") else "chrome"
    tail = parts.path.strip("/").replace("/", "_")
    return f"{product}-{parts.hostname or ''}__{tail}-{BROWSER_PROFILE}"

# A URL scheme per RFC 3986: letter, then letters/digits/+/-/.
_SCHEME_RE = re.compile(r"^([a-zA-Z][a-zA-Z0-9+.\-]*):")

MAX_NAME_LEN = 96
MAX_ID_LEN = 48


class WebAppError(Exception):
    """Something is wrong with a web app or the request. Carries a message meant
    for the user, not a traceback."""


# ── Identity ─────────────────────────────────────────────────────────────────

_SLUG_STRIP = re.compile(r"[^a-z0-9]+")


def slugify(text: str) -> str:
    """A filesystem- and shell-safe id from a display name.

    "Google Calendar" -> "google-calendar". Accents are folded rather than
    dropped so "Café" becomes "cafe" instead of "caf". The result can only ever
    contain [a-z0-9-] with no leading or trailing dash, which is what makes it
    safe to interpolate into a filename -- there is no way to smuggle a path
    separator, a dot-dot, or a shell metacharacter through it.
    """
    folded = unicodedata.normalize("NFKD", text)
    ascii_only = folded.encode("ascii", "ignore").decode("ascii")
    slug = _SLUG_STRIP.sub("-", ascii_only.lower()).strip("-")
    return slug[:MAX_ID_LEN].strip("-")


def validate_id(app_id: str) -> str:
    """Reject anything that is not already a well-formed id.

    Applied to ids arriving from outside (a CLI argument, a metadata file), so a
    hand-edited `id = "../../../etc/cron.d/x"` cannot steer a write or an unlink.
    """
    if not app_id:
        raise WebAppError("empty web app id")
    if app_id != slugify(app_id):
        raise WebAppError(
            f"invalid web app id {app_id!r}: expected lowercase letters, digits "
            "and dashes only"
        )
    return app_id


def validate_name(name: str) -> str:
    """A display name may contain punctuation and spaces; it may not be blank,
    absurdly long, or carry control characters that would corrupt a .desktop
    file or a notification."""
    cleaned = name.strip()
    if not cleaned:
        raise WebAppError("enter a name for the web app")
    if any(ord(ch) < 0x20 or ord(ch) == 0x7F for ch in cleaned):
        raise WebAppError("the name contains control characters")
    if len(cleaned) > MAX_NAME_LEN:
        raise WebAppError(f"the name is too long (max {MAX_NAME_LEN} characters)")
    return cleaned


# ── URLs ─────────────────────────────────────────────────────────────────────

def normalise_url(raw: str) -> str:
    """Validate and canonicalise a website URL.

    Accepts a bare host ("youtube.com") and promotes it to https. Anything whose
    scheme is not http/https is rejected by name -- that is what keeps
    javascript:, data: and file: out. Path, query, fragment and port are left
    exactly as given, because they are frequently load-bearing for a web app
    ("/app?mode=compact"); only an empty path is filled in as "/".
    """
    text = (raw or "").strip()
    if not text:
        raise WebAppError("enter a website URL")
    if any(ch.isspace() for ch in text):
        raise WebAppError("the URL contains whitespace")
    if any(ord(ch) < 0x20 or ord(ch) == 0x7F for ch in text):
        raise WebAppError("the URL contains control characters")

    # Distinguish a real scheme from a bare "host:port". Both look like
    # "word:something", so a plain search for ":" would read "localhost:8080" as
    # a scheme, and a plain search for "://" would let "javascript:alert(1)"
    # through to be silently prefixed with https.
    scheme_match = _SCHEME_RE.match(text)
    if scheme_match:
        candidate = scheme_match.group(1).lower()
        rest = text[scheme_match.end():]
        if candidate in ALLOWED_SCHEMES:
            pass                                   # normal absolute URL
        elif rest.startswith("//") or not rest.split("/", 1)[0].isdigit():
            # Authority-style or non-numeric remainder: a genuine scheme, and one
            # we do not allow. Named explicitly so the rejection is legible.
            raise WebAppError(
                f"unsupported URL scheme {candidate + ':'!r} -- only http and "
                "https are allowed"
            )
        else:
            text = "https://" + text               # host:port, e.g. localhost:8080
    else:
        text = "https://" + text                   # bare host

    parts = urlsplit(text)
    if parts.scheme not in ALLOWED_SCHEMES:
        raise WebAppError(
            f"unsupported URL scheme {parts.scheme + ':'!r} -- only http and "
            "https are allowed"
        )
    if not parts.hostname:
        raise WebAppError(f"{raw!r} has no hostname")
    if "." not in parts.hostname and parts.hostname != "localhost":
        raise WebAppError(f"{parts.hostname!r} does not look like a hostname")

    # Rebuild the authority with a lowercased host, leaving userinfo, port, path,
    # query and fragment untouched. urlsplit already lowercases .hostname, so the
    # host has to be substituted into the authority rather than replaced in it.
    userinfo, _, hostport = parts.netloc.rpartition("@")
    host = parts.hostname.lower()
    if hostport.startswith("["):                    # IPv6 literal
        host = "[" + host + "]"
    netloc = host + (f":{parts.port}" if parts.port else "")
    if userinfo:
        netloc = f"{userinfo}@{netloc}"

    path = parts.path or "/"
    return urlunsplit((parts.scheme, netloc, path, parts.query, parts.fragment))


def url_host(url: str) -> str:
    return urlsplit(url).hostname or ""


def name_from_url(url: str) -> str:
    """A reasonable display name from a host, for pre-filling the form.

    "https://calendar.google.com/" -> "Calendar Google". Deliberately crude: it
    only ever pre-fills an empty field and the user can overwrite it.
    """
    host = url_host(url)
    if not host:
        return ""
    parts = [p for p in host.split(".") if p not in ("www", "com", "org", "net",
                                                     "io", "app", "dev", "co")]
    if not parts:
        parts = host.split(".")[:1]
    return " ".join(p.capitalize() for p in parts)


# ── Browser ──────────────────────────────────────────────────────────────────

def _xdg_dirs(home: Path, var: str, default: str) -> list[Path]:
    return [home] + [Path(d) for d in os.environ.get(var, default).split(":") if d]


def _read_group(path: Path, group: str) -> dict[str, str]:
    """One [group] of a desktop-style key file; {} when missing or unreadable.

    Hand-parsed rather than through configparser: this runs on every launch,
    and the files involved are a few lines of key=value.
    """
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        return {}
    values: dict[str, str] = {}
    current = None
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1]
        elif current == group and "=" in line:
            key, _, value = line.partition("=")
            values.setdefault(key.strip(), value.strip())
    return values


def default_browser() -> tuple[str, Path] | None:
    """(desktop id, desktop file) of the XDG default browser, or None.

    Read straight from the mimeapps.list files in the order the XDG MIME
    Applications spec gives -- per directory, a $desktop-mimeapps.list before
    the plain one -- instead of asking xdg-settings, which costs ~100 ms a call.
    A listed entry that is not installed is skipped, as the spec says.
    """
    desktops = [d.lower() for d in os.environ.get("XDG_CURRENT_DESKTOP", "").split(":") if d]
    names = [f"{d}-mimeapps.list" for d in desktops] + ["mimeapps.list"]
    app_dirs = [d / "applications"
                for d in _xdg_dirs(DATA_HOME, "XDG_DATA_DIRS", "/usr/local/share:/usr/share")]
    list_dirs = _xdg_dirs(CONFIG_HOME, "XDG_CONFIG_DIRS", "/etc/xdg") + app_dirs
    defaults = [_read_group(d / n, "Default Applications") for d in list_dirs for n in names]

    for mime in BROWSER_MIME_TYPES:
        for group in defaults:
            for desktop_id in group.get(mime, "").split(";"):
                desktop_id = desktop_id.strip()
                if not desktop_id or "/" in desktop_id:
                    continue
                for directory in app_dirs:
                    if (directory / desktop_id).is_file():
                        return desktop_id, directory / desktop_id
    return None


def _exec_program(desktop_file: Path) -> str | None:
    """The program a desktop entry's main Exec runs, resolved on PATH."""
    import shlex

    try:
        words = shlex.split(_read_group(desktop_file, "Desktop Entry").get("Exec", ""))
    except ValueError:
        return None
    # `env VAR=value program …` is a common wrapper; the program is what counts.
    if words and Path(words[0]).name == "env":
        words = words[1:]
        while words and ("=" in words[0] or words[0].startswith("-")):
            words = words[1:]
    return shutil.which(words[0]) if words else None


def browser_choice() -> tuple[str, str]:
    """(browser path, why it was picked) for launching web apps.

    $WEBAPP_BROWSER overrides everything so this is switchable without editing
    code. Raises rather than guessing, because a wrong browser here produces a
    confusing failure at launch time.
    """
    override = os.environ.get("WEBAPP_BROWSER", "").strip()
    if override:
        resolved = shutil.which(override)
        if not resolved:
            raise WebAppError(f"$WEBAPP_BROWSER is set to {override!r}, which is not on PATH")
        return resolved, "$WEBAPP_BROWSER"

    default = default_browser()
    if default is None:
        reason = "no default browser is set"
    else:
        desktop_id, desktop_file = default
        program = _exec_program(desktop_file)
        if program is None:
            reason = f"default browser {desktop_id} runs nothing on PATH"
        elif Path(program).name in CHROMIUM_EXECUTABLES:
            return program, f"default browser ({desktop_id})"
        else:
            reason = f"default browser {desktop_id} has no app mode"

    for candidate in BROWSER_CANDIDATES:
        resolved = shutil.which(candidate)
        if resolved:
            return resolved, f"fallback: {reason}"
    raise WebAppError(
        f"no Chromium-family browser found ({reason}). Web apps need one of: "
        + ", ".join(BROWSER_CANDIDATES)
    )


def find_browser() -> str:
    """The Chromium-family browser to launch web apps with."""
    return browser_choice()[0]


# ── Model ────────────────────────────────────────────────────────────────────

@dataclass
class WebApp:
    id: str
    name: str
    url: str
    icon: str
    desktop_file: str
    wm_class: str
    icon_source: str
    created_at: str
    version: int = SCHEMA_VERSION

    @property
    def host(self) -> str:
        return url_host(self.url)

    def to_dict(self) -> dict:
        return {
            "version": self.version,
            "id": self.id,
            "name": self.name,
            "url": self.url,
            "icon": self.icon,
            "desktop_file": self.desktop_file,
            "wm_class": self.wm_class,
            "icon_source": self.icon_source,
            "created_at": self.created_at,
            "host": self.host,
        }

    def to_toml(self) -> str:
        def q(value: str) -> str:
            # TOML basic string: only backslash and quote need escaping, and
            # control characters are already rejected by the validators.
            return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'
        return (
            f"version = {self.version}\n"
            f"id = {q(self.id)}\n"
            f"name = {q(self.name)}\n"
            f"url = {q(self.url)}\n"
            f"icon = {q(self.icon)}\n"
            f"desktop_file = {q(self.desktop_file)}\n"
            f"wm_class = {q(self.wm_class)}\n"
            f"icon_source = {q(self.icon_source)}\n"
            f"created_at = {q(self.created_at)}\n"
        )


def now_stamp() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def load_app(app_id: str) -> WebApp:
    """Read one app's metadata. Treats the file as untrusted: the id inside must
    match the filename, and paths must stay inside the managed directories."""
    import tomllib

    app_id = validate_id(app_id)
    path = APPS_DIR / f"{app_id}.toml"
    if not path.is_file():
        raise WebAppError(f"no web app with id {app_id!r}")
    try:
        with path.open("rb") as fh:
            data = tomllib.load(fh)
    except tomllib.TOMLDecodeError as exc:
        raise WebAppError(f"{path.name} is not valid TOML: {exc}") from None

    stored_id = str(data.get("id", ""))
    if stored_id != app_id:
        raise WebAppError(
            f"{path.name} declares id {stored_id!r} but is filed as {app_id!r}"
        )
    for key in ("name", "url", "desktop_file"):
        if not data.get(key):
            raise WebAppError(f"{path.name} is missing {key!r}")

    return WebApp(
        id=app_id,
        name=str(data["name"]),
        url=str(data["url"]),
        icon=str(data.get("icon", "")),
        desktop_file=str(data["desktop_file"]),
        wm_class=str(data.get("wm_class", "")),
        icon_source=str(data.get("icon_source", "unknown")),
        created_at=str(data.get("created_at", "")),
        version=int(data.get("version", SCHEMA_VERSION)),
    )


def list_apps() -> tuple[list[WebApp], list[dict[str, str]]]:
    """Every managed app, plus any metadata file that would not load.

    Errors are collected rather than raised so one corrupt file cannot hide the
    rest of the list -- the UI shows what it can and reports the remainder.
    """
    apps: list[WebApp] = []
    errors: list[dict[str, str]] = []
    if not APPS_DIR.is_dir():
        return apps, errors
    for path in sorted(APPS_DIR.glob("*.toml")):
        try:
            apps.append(load_app(path.stem))
        except WebAppError as exc:
            errors.append({"id": path.stem, "error": str(exc)})
        except Exception as exc:
            errors.append({"id": path.stem, "error": f"{type(exc).__name__}: {exc}"})
    apps.sort(key=lambda a: a.name.lower())
    return apps, errors


def existing_ids() -> set[str]:
    if not APPS_DIR.is_dir():
        return set()
    return {p.stem for p in APPS_DIR.glob("*.toml")}


# ── Managed-path guards ──────────────────────────────────────────────────────

def assert_managed(path: Path, *allowed: Path) -> Path:
    """Refuse to touch anything outside the directories this tool owns.

    The last line of defence for removal: metadata is a plain text file the user
    could edit, so a path read out of it is re-checked before any unlink rather
    than trusted because it came from "our" file.
    """
    resolved = path.expanduser().resolve()
    for root in allowed:
        try:
            resolved.relative_to(root.resolve())
            return resolved
        except ValueError:
            continue
    raise WebAppError(
        f"refusing to touch {resolved} -- outside the managed directories "
        + ", ".join(str(r) for r in allowed)
    )


# ── Atomic writes ────────────────────────────────────────────────────────────

def atomic_write(dest: Path, content: str, mode: int | None = None) -> None:
    """Write via a temp file in the destination's own directory, then replace, so
    no reader ever sees a partial file. Same idiom as the theme generator."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.parent / f".{dest.name}.new"
    tmp.write_text(content)
    if mode is not None:
        tmp.chmod(mode)
    os.replace(tmp, dest)


def atomic_copy(src: Path, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.parent / f".{dest.name}.new"
    shutil.copyfile(src, tmp)
    os.replace(tmp, dest)


def run_quiet(cmd: list[str], timeout: int = 10) -> tuple[int, str]:
    """Run a command with no shell. Returns (rc, stderr)."""
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return proc.returncode, (proc.stderr or "").strip()
    except FileNotFoundError:
        return 127, f"{cmd[0]}: not found"
    except subprocess.TimeoutExpired:
        return 124, f"{cmd[0]}: timed out"


def notify(title: str, message: str, critical: bool = False) -> None:
    """Desktop notification, following the repo convention (notify-send when
    present, stderr otherwise; bypass DND for results the user asked for)."""
    if shutil.which("notify-send"):
        cmd = ["notify-send", "-a", "Web Apps"]
        if critical:
            cmd += ["-u", "critical", "-h", "boolean:swaync-bypass-dnd:true"]
        cmd += [title, message]
        run_quiet(cmd, timeout=5)
    else:
        import sys
        print(f"{title}: {message}", file=sys.stderr)


# ── Theme accent, for generated icons ────────────────────────────────────────

def accent_colour(default: str = "#7aa2f7") -> str:
    """The active desktop theme's accent, so a generated fallback icon matches
    the rest of the desktop. Falls back silently -- an icon is not worth failing
    an install over."""
    path = CONFIG_HOME / "hypr/themes/.active/theme.json"
    try:
        data = json.loads(path.read_text())
        value = data.get("colors", {}).get("accent")
        if isinstance(value, str) and re.fullmatch(r"#[0-9a-fA-F]{6}", value):
            return value
    except Exception:
        pass
    return default


# ── Icon discovery ───────────────────────────────────────────────────────────
# Everything below talks to arbitrary websites. The rules, all enforced here
# rather than trusted:
#
#   * http/https only, and the opener is built with only those two handlers, so a
#     redirect to file:// cannot be followed even if a site tries.
#   * bounded time, bounded redirects, bounded bytes -- read in chunks so a
#     "Content-Length: 5" lying about a 5GB body cannot exhaust memory.
#   * the file type is decided by sniffing magic bytes, never by Content-Type or
#     by the URL's extension.
#   * the remote filename is discarded entirely; we write <id>.<ext>.
#   * nothing downloaded is executed, and no downloaded string reaches a shell.
#
# Private and loopback addresses are deliberately NOT blocked: a self-hosted
# service on the LAN is a perfectly good web app, and this is a personal desktop
# tool rather than a server-side fetcher. The protections that matter here are
# the scheme restriction and keeping URL data away from any shell.

# urllib.request and html.parser are imported inside the functions below, not at
# the top. Together they cost ~100 ms at startup, and only icon discovery needs
# them -- `launch`, which runs on every menu click, never touches the network.

FETCH_TIMEOUT = 6
MAX_REDIRECTS = 3
MAX_BYTES = 5 * 1024 * 1024
MAX_HTML_BYTES = 512 * 1024
USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) webapp-manager/1"

# (extension, predicate on the first bytes)
_SIGNATURES: tuple[tuple[str, "callable"], ...] = (
    ("png", lambda b: b.startswith(b"\x89PNG\r\n\x1a\n")),
    ("jpg", lambda b: b.startswith(b"\xff\xd8\xff")),
    ("gif", lambda b: b.startswith(b"GIF87a") or b.startswith(b"GIF89a")),
    ("webp", lambda b: b.startswith(b"RIFF") and b[8:12] == b"WEBP"),
    ("ico", lambda b: b.startswith(b"\x00\x00\x01\x00") or b.startswith(b"\x00\x00\x02\x00")),
    ("svg", lambda b: b.lstrip()[:5].lower() in (b"<?xml", b"<svg")
            or b"<svg" in b[:512].lower()),
)


def _opener() -> urllib.request.OpenerDirector:
    """An opener that can only speak HTTP(S). Omitting FileHandler/FTPHandler is
    what makes a redirect to file:// impossible rather than merely unlikely."""
    import urllib.request

    class BoundedRedirect(urllib.request.HTTPRedirectHandler):
        max_redirections = MAX_REDIRECTS

        def redirect_request(self, req, fp, code, msg, headers, newurl):
            if urlsplit(newurl).scheme not in ALLOWED_SCHEMES:
                return None
            return super().redirect_request(req, fp, code, msg, headers, newurl)

    return urllib.request.build_opener(
        urllib.request.HTTPHandler,
        urllib.request.HTTPSHandler,
        BoundedRedirect,
    )


def _fetch(url: str, limit: int) -> bytes:
    """Fetch at most `limit` bytes. Raises WebAppError with a short reason."""
    import urllib.error
    import urllib.request

    if urlsplit(url).scheme not in ALLOWED_SCHEMES:
        raise WebAppError(f"refusing to fetch non-HTTP URL {url!r}")
    req = urllib.request.Request(url, headers={
        "User-Agent": USER_AGENT,
        "Accept": "*/*",
    })
    try:
        with _opener().open(req, timeout=FETCH_TIMEOUT) as resp:
            chunks: list[bytes] = []
            total = 0
            while True:
                chunk = resp.read(64 * 1024)
                if not chunk:
                    break
                total += len(chunk)
                if total > limit:
                    # Truncate rather than fail: a partial HTML head is still
                    # useful, and an over-large icon is simply not wanted.
                    chunks.append(chunk)
                    break
                chunks.append(chunk)
            return b"".join(chunks)[:limit]
    except urllib.error.HTTPError as exc:
        raise WebAppError(f"HTTP {exc.code} fetching {url}") from None
    except urllib.error.URLError as exc:
        raise WebAppError(f"could not reach {urlsplit(url).hostname}: {exc.reason}") from None
    except TimeoutError:
        raise WebAppError(f"timed out fetching {urlsplit(url).hostname}") from None
    except Exception as exc:
        raise WebAppError(f"could not fetch {url}: {type(exc).__name__}") from None


def _icon_link_candidates(html: str) -> list[tuple[int, str]]:
    """(score, href) for every icon a page head declares."""
    from html.parser import HTMLParser

    class _IconLinkParser(HTMLParser):
        """Collects declared icons from a page head.

        A real parser rather than a regex: attribute order, quoting style and
        self-closing syntax all vary, and a regex over hostile HTML is how you end up
        following something that was never a link tag.
        """

        def __init__(self) -> None:
            super().__init__(convert_charrefs=True)
            self.candidates: list[tuple[int, str]] = []  # (score, href)
            self._in_head = True

        def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
            if tag == "body":
                self._in_head = False
                return
            a = {k.lower(): (v or "") for k, v in attrs}

            if tag == "link":
                rels = a.get("rel", "").lower().split()
                if not any(r in ("icon", "shortcut", "apple-touch-icon",
                                 "apple-touch-icon-precomposed", "mask-icon")
                           for r in rels):
                    return
                href = a.get("href", "").strip()
                if not href:
                    return
                # Prefer big, and prefer apple-touch-icon: it is required to be a
                # square PNG with no transparency, which is exactly what a launcher
                # icon wants. A declared "sizes" wins when it is larger.
                score = 0
                if "apple-touch-icon" in rels or "apple-touch-icon-precomposed" in rels:
                    score = 180
                sizes = a.get("sizes", "").lower()
                m = re.search(r"(\d+)\s*x\s*(\d+)", sizes)
                if m:
                    score = max(score, min(int(m.group(1)), 1024))
                elif href.lower().endswith(".svg"):
                    # Deliberately ranked below any declared size. An SVG favicon is
                    # frequently a bare monochrome glyph -- ChatGPT's even switches
                    # fill via prefers-color-scheme, which renderers outside a
                    # browser ignore, producing a black-on-transparent icon that
                    # vanishes on a dark panel. A sized raster is the better launcher
                    # icon whenever the site offers one.
                    score = max(score, 64)
                elif score == 0:
                    score = 32                # an undeclared favicon is usually small
                self.candidates.append((score, href))

            elif tag == "meta":
                prop = (a.get("property") or a.get("name") or "").lower()
                if prop in ("og:image", "twitter:image"):
                    content = a.get("content", "").strip()
                    if content:
                        # Social images are big but usually banners, not icons, so
                        # they rank below any declared icon.
                        self.candidates.append((16, content))

    parser = _IconLinkParser()
    parser.feed(html)
    return parser.candidates


def discover_icon(url: str, dest_dir: Path, stem: str) -> tuple[Path, str] | None:
    """Find and download the best available icon for `url`.

    Returns (path, source_url) or None when nothing usable was found. Never
    raises for an ordinary "site has no icon" -- that is a normal outcome the
    caller handles with a generated fallback.
    """
    dest_dir.mkdir(parents=True, exist_ok=True)
    candidates: list[tuple[int, str]] = []

    try:
        html = _fetch(url, MAX_HTML_BYTES)
        for score, href in _icon_link_candidates(html.decode("utf-8", "replace")):
            try:
                absolute = urljoin(url, href)
            except Exception:
                continue
            if urlsplit(absolute).scheme in ALLOWED_SCHEMES:
                candidates.append((score, absolute))
    except WebAppError:
        # The page did not load; /favicon.ico may still exist.
        pass

    parts = urlsplit(url)
    candidates.append((8, urlunsplit((parts.scheme, parts.netloc, "/favicon.ico", "", ""))))

    # Highest score first, de-duplicated, and only a handful attempted so a page
    # declaring fifty icons cannot turn into fifty requests.
    seen: set[str] = set()
    ordered: list[str] = []
    for _, href in sorted(candidates, key=lambda c: -c[0]):
        if href not in seen:
            seen.add(href)
            ordered.append(href)

    for href in ordered[:5]:
        try:
            blob = _fetch(href, MAX_BYTES)
        except WebAppError:
            continue
        if len(blob) < 32:
            continue
        ext = sniff_image(blob)
        if ext is None:
            continue
        # The remote filename is never reused; we name the file ourselves.
        out = dest_dir / f"{stem}.{ext}"
        out.write_bytes(blob)
        return out, href

    return None


def sniff_image(blob: bytes) -> str | None:
    """The real file type from magic bytes. Content-Type and file extensions are
    both attacker-controlled, so neither is consulted."""
    head = blob[:1024]
    for ext, matches in _SIGNATURES:
        try:
            if matches(head):
                return ext
        except Exception:
            continue
    return None


def normalise_icon(src: Path, dest_stem: Path) -> Path:
    """Put an icon into its final managed form: always a PNG.

    Converting rather than storing whatever the site served is a deliberate
    call about *this* machine. gdk-pixbuf here ships only its built-in loaders --
    there is no librsvg or webp loader installed -- so Rofi can render PNG,
    JPEG, GIF and ICO but not SVG or WebP. Qt (the shell) can render all of
    them. Normalising to PNG is the one format every consumer handles, so the
    icon looks the same in the launcher, the shell and any file manager.

    A PNG is passed through untouched; re-encoding a good PNG only loses quality.
    """
    blob = src.read_bytes()
    ext = sniff_image(blob)
    if ext is None:
        raise WebAppError(
            f"{src.name} is not a recognised image (PNG, JPEG, GIF, WebP, ICO or SVG)"
        )

    out = dest_stem.with_suffix(".png")

    if ext == "png":
        if src.resolve() != out.resolve():
            atomic_copy(src, out)
        return out

    if not shutil.which("magick"):
        # No converter: keep the original format rather than lose the icon, and
        # accept that Rofi may not render an SVG or WebP.
        fallback = dest_stem.with_suffix("." + ext)
        if src.resolve() != fallback.resolve():
            atomic_copy(src, fallback)
        return fallback

    # -thumbnail caps the size without upscaling; a transparent background is
    # preserved so a rounded app icon does not gain black corners. For a
    # multi-resolution ICO this picks the largest frame rather than the 16px one.
    rc, err = run_quiet([
        "magick", str(src), "-background", "none",
        "-thumbnail", "256x256>", "-depth", "8", str(out),
    ], timeout=30)
    if rc == 0 and out.is_file() and sniff_image(out.read_bytes()) == "png":
        return out

    fallback = dest_stem.with_suffix("." + ext)
    if src.resolve() != fallback.resolve():
        atomic_copy(src, fallback)
    return fallback


def generate_icon(dest_stem: Path, letter: str, accent: str | None = None) -> Path:
    """A letter tile in the desktop's accent colour, for when no icon exists.

    Requires ImageMagick. Failure is reported but never fatal: an app with no
    icon is still a working app, and Rofi falls back to a generic entry.
    """
    if not shutil.which("magick"):
        raise WebAppError("ImageMagick (magick) is needed to generate a fallback icon")
    colour = accent or accent_colour()
    initial = (letter.strip()[:1] or "?").upper()
    out = dest_stem.with_suffix(".png")

    # Dark text on the accent when the accent is light, and vice versa, so the
    # letter is legible whatever the active theme is.
    r, g, b = (int(colour[i:i + 2], 16) for i in (1, 3, 5))
    luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
    fg = "#101010" if luma > 140 else "#f5f5f5"

    rc, err = run_quiet([
        "magick", "-size", "256x256", f"xc:{colour}",
        "-gravity", "center",
        "-fill", fg, "-pointsize", "150",
        "-annotate", "+0-8", initial,
        # 8 bits is all a flat two-colour tile needs; the default 16 doubles the
        # file for no visible gain.
        "-depth", "8",
        str(out),
    ], timeout=20)
    if rc != 0 or not out.is_file():
        raise WebAppError(f"could not generate a fallback icon: {err or 'magick failed'}")
    return out
