#!/usr/bin/env python3
"""Install, remove and launch managed web apps.

    webapp list [--json]
    webapp get <id>
    webapp discover-icon <url> [--id ID]
    webapp install --name NAME --url URL [--icon PATH] [--id ID]
    webapp remove <id>
    webapp launch <id>
    webapp doctor

A web app is a website promoted to a first-class launcher: metadata we own, an
icon we own, and a .desktop file we own. The metadata directory is the ownership
marker -- removal only ever touches apps listed there, so an unrelated .desktop
file can never be deleted by this tool.

Installation is staged: everything is built and validated in a scratch directory
and only moved into place once all of it has passed, so a failure leaves no
half-installed app behind.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import weblib as wl  # noqa: E402

_TTY = sys.stdout.isatty()
def _c(code: str, text: str) -> str:
    return f"\033[{code}m{text}\033[0m" if _TTY else text
BOLD = lambda s: _c("1", s)      # noqa: E731
GREEN = lambda s: _c("32", s)    # noqa: E731
YELLOW = lambda s: _c("33", s)   # noqa: E731
RED = lambda s: _c("31", s)      # noqa: E731
DIM = lambda s: _c("2", s)       # noqa: E731


# ── .desktop generation ──────────────────────────────────────────────────────

def desktop_entry(app: wl.WebApp) -> str:
    """The launcher text.

    Exec carries only the helper and the validated id -- never the URL. That is
    deliberate: it means no part of a website address can reach an Exec line,
    where .desktop quoting rules would otherwise have to be trusted.

    Name is written as given (spaces and punctuation are fine); Rofi's
    drun-display-format shows Name, so this is what you type to find the app.
    """
    lines = [
        "[Desktop Entry]",
        "Type=Application",
        f"Name={app.name}",
        f"Comment={app.host} web app",
        f"Exec={wl.LAUNCH_HELPER} {app.id}",
    ]
    if app.icon:
        lines.append(f"Icon={app.icon}")
    lines += [
        "Terminal=false",
        "StartupNotify=true",
    ]
    # No StartupWMClass. Brave ignores --class for app-mode windows and derives
    # its own (verified: `brave-youtube.com__-Default`), and that derived value
    # embeds the browser profile name -- so anything written here would be a
    # guess that could quietly stop matching. Hyprland and Rofi both ignore the
    # field anyway; the derived class is recorded in the metadata instead, where
    # `webapp list` can show it for writing window rules.
    lines += [
        "Categories=Network;",
        f"{wl.MARKER_KEY}=true",
        f"{wl.MARKER_ID_KEY}={app.id}",
        "",
    ]
    return "\n".join(lines)


def validate_desktop(path: Path) -> None:
    """Gate the install on desktop-file-validate when it is available."""
    if not shutil.which("desktop-file-validate"):
        print(DIM("  desktop-file-validate not installed; skipping validation"),
              file=sys.stderr)
        return
    rc, err = wl.run_quiet(["desktop-file-validate", str(path)], timeout=15)
    if rc != 0:
        raise wl.WebAppError(f"the generated launcher is invalid: {err or 'see desktop-file-validate'}")


def refresh_desktop_database() -> None:
    """Best effort -- Rofi rescans per invocation, so this only helps consumers
    that read the mimeinfo cache."""
    if shutil.which("update-desktop-database"):
        wl.run_quiet(["update-desktop-database", str(wl.DESKTOP_DIR)], timeout=20)


# ── Commands ─────────────────────────────────────────────────────────────────

def cmd_list(args: argparse.Namespace) -> int:
    apps, errors = wl.list_apps()
    if args.json:
        json.dump({
            "apps": [a.to_dict() for a in apps],
            "errors": errors,
        }, sys.stdout)
        sys.stdout.write("\n")
        return 0

    if not apps and not errors:
        print("No web apps installed.")
        return 0
    for app in apps:
        icon = "icon" if app.icon and Path(app.icon).is_file() else DIM("no icon")
        missing = "" if Path(app.desktop_file).is_file() else RED("  [launcher missing]")
        print(f"  {BOLD(app.id):<28} {app.name:<26} {DIM(app.host):<24} {icon}{missing}")
    for err in errors:
        print(f"  {RED('FAIL')} {err['id']}: {err['error']}", file=sys.stderr)
    print(f"\n{len(apps)} web app(s)" + (f", {len(errors)} unreadable" if errors else ""))
    return 1 if errors else 0


def cmd_get(args: argparse.Namespace) -> int:
    app = wl.load_app(args.id)
    json.dump(app.to_dict(), sys.stdout)
    sys.stdout.write("\n")
    return 0


def cmd_discover_icon(args: argparse.Namespace) -> int:
    """Fetch an icon into a scratch location and report where it landed.

    Split out as its own command so the shell UI can show a preview before
    committing to an install, and so the network call is one short-lived process
    rather than something the UI has to hold open.
    """
    url = wl.normalise_url(args.url)
    stem = wl.validate_id(args.id) if args.id else (wl.slugify(wl.url_host(url)) or "icon")
    stage = wl.CACHE_HOME / "webapps"
    found = wl.discover_icon(url, stage, stem)
    # The suggested name comes from the host, not from the icon, so it is
    # reported either way -- a site with no usable icon still deserves a
    # pre-filled name, which is the case the Super+Space install lands in.
    if found is None:
        json.dump({
            "ok": False,
            "reason": "no icon found",
            "suggested_name": wl.name_from_url(url),
        }, sys.stdout)
        sys.stdout.write("\n")
        return 0
    path, source = found
    json.dump({
        "ok": True,
        "path": str(path),
        "source": source,
        "suggested_name": wl.name_from_url(url),
    }, sys.stdout)
    sys.stdout.write("\n")
    return 0


def cmd_install(args: argparse.Namespace) -> int:
    name = wl.validate_name(args.name)
    url = wl.normalise_url(args.url)

    app_id = wl.validate_id(args.id) if args.id else wl.slugify(name)
    if not app_id:
        app_id = wl.slugify(wl.url_host(url))
    if not app_id:
        raise wl.WebAppError("could not derive an id from the name or URL; pass --id")

    taken = wl.existing_ids()
    if app_id in taken:
        try:
            clash = wl.load_app(app_id)
            detail = f" ({clash.name} -> {clash.url})"
        except wl.WebAppError:
            detail = ""
        # Explicit rather than silently suffixing: overwriting someone's app
        # because the name collided would be worse than making them choose.
        suggestion = next(
            f"{app_id}-{n}" for n in range(2, 100) if f"{app_id}-{n}" not in taken
        )
        raise wl.WebAppError(
            f"a web app with id {app_id!r} already exists{detail}. "
            f"Pass --id {suggestion} to install alongside it, "
            f"or remove the existing one first."
        )

    stage = Path(tempfile.mkdtemp(prefix="webapp-stage.", dir=wl.RUNTIME_DIR))
    icon_source = "none"
    try:
        # ── icon: user-provided, then discovered, then generated ──────────────
        staged_icon: Path | None = None
        if args.icon:
            src = Path(args.icon).expanduser()
            if not src.is_file():
                raise wl.WebAppError(f"icon not found: {src}")
            staged_icon = wl.normalise_icon(src, stage / app_id)
            icon_source = "user"
        elif not args.no_icon:
            found = wl.discover_icon(url, stage, app_id)
            if found is not None:
                staged_icon = wl.normalise_icon(found[0], stage / app_id)
                icon_source = "discovered"

        if staged_icon is None and not args.no_icon:
            try:
                staged_icon = wl.generate_icon(stage / app_id, name)
                icon_source = "generated"
            except wl.WebAppError as exc:
                # An icon is a nicety; refusing to install without one would be
                # the wrong trade.
                print(YELLOW(f"warning: {exc}"), file=sys.stderr)

        final_icon = wl.ICONS_DIR / staged_icon.name if staged_icon else None

        app = wl.WebApp(
            id=app_id,
            name=name,
            url=url,
            icon=str(final_icon) if final_icon else "",
            desktop_file=str(wl.DESKTOP_DIR / f"{wl.DESKTOP_PREFIX}{app_id}.desktop"),
            wm_class=wl.derived_wm_class(url, wl.find_browser()),
            icon_source=icon_source,
            created_at=wl.now_stamp(),
        )

        # ── stage metadata + launcher, and validate before anything moves ─────
        staged_meta = stage / f"{app_id}.toml"
        staged_meta.write_text(app.to_toml())

        staged_desktop = stage / f"{wl.DESKTOP_PREFIX}{app_id}.desktop"
        # Point Icon at where the icon *will* live, not the staging copy.
        staged_desktop.write_text(desktop_entry(app))
        validate_desktop(staged_desktop)

        # ── install: icon, then metadata, then the launcher last ──────────────
        # Launcher last so the app never appears in a menu before the metadata
        # that makes it launchable and removable exists.
        if staged_icon and final_icon:
            wl.atomic_copy(staged_icon, final_icon)
        wl.atomic_write(wl.APPS_DIR / f"{app_id}.toml", staged_meta.read_text())
        wl.atomic_write(Path(app.desktop_file), staged_desktop.read_text(), mode=0o644)
    finally:
        shutil.rmtree(stage, ignore_errors=True)

    refresh_desktop_database()

    if args.json:
        json.dump({"ok": True, **app.to_dict()}, sys.stdout)
        sys.stdout.write("\n")
    else:
        print(f"{GREEN('installed')} {BOLD(app.name)} {DIM('(' + app.id + ')')}")
        print(DIM(f"  url      {app.url}"))
        print(DIM(f"  icon     {app.icon or 'none'} ({icon_source})"))
        print(DIM(f"  launcher {app.desktop_file}"))
    return 0


def cmd_remove(args: argparse.Namespace) -> int:
    app = wl.load_app(args.id)

    # Second ownership check, independent of the metadata directory: the launcher
    # must carry our marker with this id. A .desktop file that does not is not
    # ours to delete, however the metadata got edited.
    desktop = Path(app.desktop_file)
    if desktop.is_file():
        text = desktop.read_text(errors="replace")
        if f"{wl.MARKER_ID_KEY}={app.id}" not in text:
            raise wl.WebAppError(
                f"{desktop} is not marked as web app {app.id!r} -- refusing to "
                "delete it. Remove the metadata by hand if this is intentional."
            )

    removed: list[str] = []
    # Every path is re-checked against the managed directories before unlinking,
    # so a hand-edited metadata file cannot aim removal at an arbitrary file.
    for label, raw, roots in (
        ("launcher", app.desktop_file, (wl.DESKTOP_DIR,)),
        ("icon", app.icon, (wl.ICONS_DIR,)),
    ):
        if not raw:
            continue
        try:
            path = wl.assert_managed(Path(raw), *roots)
        except wl.WebAppError as exc:
            print(YELLOW(f"warning: {exc}"), file=sys.stderr)
            continue
        if path.is_file():
            path.unlink()
            removed.append(label)

    meta = wl.APPS_DIR / f"{app.id}.toml"
    if meta.is_file():
        meta.unlink()
        removed.append("metadata")

    refresh_desktop_database()

    if args.json:
        json.dump({"ok": True, "id": app.id, "removed": removed}, sys.stdout)
        sys.stdout.write("\n")
    else:
        print(f"{GREEN('removed')} {BOLD(app.name)} {DIM('(' + ', '.join(removed) + ')')}")
    return 0


def cmd_launch(args: argparse.Namespace) -> int:
    """Open a managed web app in a standalone browser window.

    The URL is re-validated here even though it was validated at install time:
    the metadata file is editable, so it is treated as untrusted input on every
    read. The browser is invoked with an argument list -- no shell, so nothing in
    the URL can be reinterpreted as syntax.
    """
    app = wl.load_app(args.id)
    url = wl.normalise_url(app.url)
    browser = wl.find_browser()

    # App mode is the only flag needed. --class is deliberately not passed:
    # Brave ignores it for app-mode windows on Wayland (verified), so sending it
    # would be dead weight that implies a guarantee it does not provide.
    cmd = [browser, f"--app={url}"]

    if args.print_command:
        json.dump({"command": cmd}, sys.stdout)
        sys.stdout.write("\n")
        return 0

    try:
        subprocess.Popen(
            cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError as exc:
        raise wl.WebAppError(f"could not start {browser}: {exc}") from None
    return 0


def cmd_doctor(args: argparse.Namespace) -> int:
    print(BOLD("web app manager"))
    try:
        browser = wl.find_browser()
        print(f"  browser        {GREEN(browser)}")
    except wl.WebAppError as exc:
        print(f"  browser        {RED(str(exc))}")
    override = os.environ.get("WEBAPP_BROWSER")
    if override:
        print(f"  $WEBAPP_BROWSER {override}")

    for label, tool, needed in (
        ("validator", "desktop-file-validate", "validating launchers"),
        ("imagemagick", "magick", "ICO conversion and fallback icons"),
        ("db update", "update-desktop-database", "menu caches"),
        ("notify", "notify-send", "launch errors"),
    ):
        path = shutil.which(tool)
        state = GREEN(path) if path else YELLOW(f"missing -- {needed} unavailable")
        print(f"  {label:<14} {state}")

    print(f"  launch helper  {wl.LAUNCH_HELPER}"
          + ("" if wl.LAUNCH_HELPER.exists() else RED("  [missing -- run `stow hypr`]")))
    print(f"  metadata       {wl.APPS_DIR}")
    print(f"  icons          {wl.ICONS_DIR}")
    print(f"  launchers      {wl.DESKTOP_DIR}")
    print(f"  accent         {wl.accent_colour()}")

    apps, errors = wl.list_apps()
    print(f"\n  {len(apps)} web app(s) installed")

    # Orphans in both directions: a launcher with no metadata is unremovable by
    # this tool, and metadata with no launcher is invisible in menus.
    problems = 0
    for app in apps:
        if not Path(app.desktop_file).is_file():
            print(f"  {YELLOW('orphan')} {app.id}: metadata but no launcher")
            problems += 1
        if app.icon and not Path(app.icon).is_file():
            print(f"  {YELLOW('orphan')} {app.id}: metadata points at a missing icon")
            problems += 1
    known = {a.id for a in apps}
    if wl.DESKTOP_DIR.is_dir():
        for path in sorted(wl.DESKTOP_DIR.glob(f"{wl.DESKTOP_PREFIX}*.desktop")):
            stem_id = path.stem[len(wl.DESKTOP_PREFIX):]
            if stem_id not in known:
                print(f"  {YELLOW('orphan')} {path.name}: launcher with no metadata")
                problems += 1
    for err in errors:
        print(f"  {RED('unreadable')} {err['id']}: {err['error']}")
        problems += 1
    if problems == 0:
        print(f"  {GREEN('no problems found')}")
    return 1 if problems else 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="webapp", description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("list")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_list)

    p = sub.add_parser("get")
    p.add_argument("id")
    p.set_defaults(func=cmd_get)

    p = sub.add_parser("discover-icon")
    p.add_argument("url")
    p.add_argument("--id")
    p.set_defaults(func=cmd_discover_icon)

    p = sub.add_parser("install")
    p.add_argument("--name", required=True)
    p.add_argument("--url", required=True)
    p.add_argument("--icon", help="use this local image instead of discovering one")
    p.add_argument("--id", help="override the generated id")
    p.add_argument("--no-icon", action="store_true",
                   help="skip icon discovery and the generated fallback")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_install)

    p = sub.add_parser("remove")
    p.add_argument("id")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_remove)

    p = sub.add_parser("launch")
    p.add_argument("id")
    p.add_argument("--print-command", action="store_true",
                   help="print the argv that would be run instead of running it")
    p.set_defaults(func=cmd_launch)

    sub.add_parser("doctor").set_defaults(func=cmd_doctor)

    args = ap.parse_args(argv)
    try:
        return args.func(args)
    except wl.WebAppError as exc:
        print(f"{RED('error')}: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
