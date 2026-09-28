#!/usr/bin/env python3
"""lmenu-parse.py - JSONC menu tree parser, guard evaluator and row renderer.

The dotted id *is* the tree: ``style.bar.position`` is a child of ``style.bar``.
Entry kind is inferred - ``action`` makes a leaf, ``target`` makes a link, a
``provider`` makes a generated submenu, anything else is a plain submenu.

Guards are bash conditions.  A view evaluates its guards in two batches, one
for its own rows and one for the rows nested below them, each a single bash
process running the guards concurrently and printing ``<id>:<w|c|d>:<0|1>``
per guard.  A guard that fails to run at all is treated as ``0``.

Commands:
    rows <route>            emit "<icon>\\t<label>\\t<suffix>\\t<id>\\t<crumb>\\t<meta>"
                            per row: the route's own rows, then every row
                            nested below it, then "#direct:<n>" counting the
                            former
    feed <route> <file>     stream a view for rofi: a header, then display
                            lines, recording what each row runs in <file>
    dump                    emit the whole reachable tree, generated rows and
                            aliases as JSON, for the Quickshell panel
    resolve <route> <id>    emit "<kind>\\t<payload>"
    title <route>           emit the prompt title for a route
    route <string>          emit the canonical id for an id or alias
    validate                parse both sources and report problems
    --dry-run <route>       human-readable dump of a resolved view
"""

from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

SEP = "#"  # separates a provider id from its generated row key
CHECK = "✓"
CHEVRON = "\u203a"  # marks a row that opens another view
CRUMB_SEP = " / "  # joins the menu names above a nested search row

# Generated lists short and cheap enough to search from a parent menu.  Apps,
# fonts and timezones run to hundreds of rows, so they stay searchable only
# inside their own view.
SEARCHABLE_PROVIDERS = {"themes"}

CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
DEFAULT_MENU = Path(
    os.environ.get("LMENU_MENU") or CONFIG_HOME / "lmenu" / "menu.jsonc"
)
DEFAULT_OVERLAY = Path(
    os.environ.get("LMENU_EXTENSIONS")
    or CONFIG_HOME / "lmenu" / "extensions" / "menu.jsonc"
)

# Fields accepted on an entry.  `iconFont` is accepted and discarded so an
# Omarchy-shaped file parses cleanly under a rofi-only renderer.
KNOWN_FIELDS = {
    "id", "icon", "label", "title", "action", "target", "provider",
    "aliases", "description", "when", "checked", "disabled",
}
DISCARDED_FIELDS = {"iconFont"}


def warn(message: str) -> None:
    print(f"lmenu-parse: {message}", file=sys.stderr)


# --------------------------------------------------------------------------
# JSONC


def strip_jsonc(text: str) -> str:
    """Drop whole-line // comments and trailing commas."""
    lines = []
    for line in text.splitlines():
        if line.lstrip().startswith("//"):
            lines.append("")
        else:
            lines.append(line)
    stripped = "\n".join(lines)
    return re.sub(r",(\s*[}\]])", r"\1", stripped)


def load_jsonc(path: Path) -> list[dict]:
    data = json.loads(strip_jsonc(path.read_text(encoding="utf-8")))
    if isinstance(data, dict):
        data = data.get("entries", [])
    if not isinstance(data, list):
        raise ValueError("menu source must be a list of entries")
    for entry in data:
        if not isinstance(entry, dict):
            raise ValueError("menu entries must be objects")
        if not entry.get("id"):
            raise ValueError("every menu entry needs an id")
        for key in list(entry):
            if key in DISCARDED_FIELDS:
                del entry[key]
            elif key not in KNOWN_FIELDS:
                raise ValueError(f"{entry['id']}: unknown field {key!r}")
    return data


def merge_sources(base: list[dict], overlay: list[dict]) -> list[dict]:
    """Per-key merge: a same-id overlay entry replaces only the fields it
    declares and keeps its original position; a new id appends."""
    merged = [dict(entry) for entry in base]
    index = {entry["id"]: position for position, entry in enumerate(merged)}
    for entry in overlay:
        target = index.get(entry["id"])
        if target is None:
            index[entry["id"]] = len(merged)
            merged.append(dict(entry))
        else:
            merged[target].update(entry)
    return merged


def load_menu(menu_path: Path, overlay_path: Path) -> list[dict]:
    entries = load_jsonc(menu_path)
    if overlay_path.is_file():
        try:
            entries = merge_sources(entries, load_jsonc(overlay_path))
        except (ValueError, json.JSONDecodeError, OSError) as error:
            warn(f"ignoring broken extension file {overlay_path}: {error}")
    return entries


# --------------------------------------------------------------------------
# Tree


class Menu:
    def __init__(self, entries: list[dict]) -> None:
        self.entries = entries
        self.by_id = {entry["id"]: entry for entry in entries}
        self.children: dict[str, list[dict]] = {"": []}
        for entry in entries:
            parent = entry["id"].rpartition(".")[0]
            self.children.setdefault(parent, []).append(entry)
        self.aliases: dict[str, str] = {}
        for entry in entries:
            for alias in entry.get("aliases", []):
                self.aliases[normalise(alias)] = entry["id"]

    def kind(self, entry: dict) -> str:
        if entry.get("action"):
            return "leaf"
        if entry.get("target"):
            return "link"
        if entry.get("provider"):
            return "provider"
        return "submenu"

    def resolve_route(self, route: str) -> str:
        route = (route or "").strip()
        if route in ("", "menu", "go", "root"):
            return ""
        if route in self.by_id:
            return route
        alias = self.aliases.get(normalise(route))
        if alias:
            return alias
        return route  # literal id fallback, matching the reference semantics

    def title(self, route: str) -> str:
        if not route:
            return "Menu"
        entry = self.by_id.get(route)
        if not entry:
            return route
        return entry.get("title") or entry.get("label") or route


def normalise(value: str) -> str:
    return value.strip().lower().replace("_", "-")


# --------------------------------------------------------------------------
# Guards


def evaluate_guards(requests: list[tuple[str, str, str]]) -> dict[tuple[str, str], bool]:
    """requests is a list of (id, kind, expression); kind is w, c or d.

    Every expression runs as its own `bash -c` inside one batched bash process,
    so a syntax error in one guard cannot abort the render.  The guards run
    concurrently: a searchable view evaluates the whole subtree, and several
    status probes take a fifth of a second each.  Each result is one short
    printf, which a pipe writes atomically, so lines never interleave.
    """
    results: dict[tuple[str, str], bool] = {}
    if not requests:
        return results
    script = ["#!/usr/bin/env bash\n"]
    for entry_id, kind, expression in requests:
        script.append(
            "{ if bash -c %s >/dev/null 2>&1 </dev/null; then s=1; else s=0; fi\n"
            "printf '%%s:%%s:%%s\\n' %s %s \"$s\"; } &\n"
            % (shlex.quote(expression), shlex.quote(entry_id), shlex.quote(kind))
        )
    script.append("wait\n")
    try:
        completed = subprocess.run(
            ["bash", "-s"],
            input="".join(script),
            capture_output=True,
            text=True,
            timeout=10,
        )
        output = completed.stdout
    except (OSError, subprocess.SubprocessError) as error:
        warn(f"guard batch failed, treating every guard as false: {error}")
        output = ""
    for line in output.splitlines():
        parts = line.rsplit(":", 2)
        if len(parts) != 3:
            continue
        entry_id, guard_kind, value = parts
        results[(entry_id, guard_kind)] = value == "1"
    for entry_id, kind, _ in requests:
        results.setdefault((entry_id, kind), False)
    return results


# --------------------------------------------------------------------------
# Providers


def provider_rows(name: str) -> list[dict]:
    if name == "apps":
        return apps_provider()
    if name == "fonts":
        return fonts_provider()
    if name == "themes":
        return themes_provider()
    if name == "timezones":
        return timezones_provider()
    warn(f"unknown provider {name!r}")
    return []


def desktop_dirs() -> list[Path]:
    raw = os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
    home = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local/share")
    return [Path(part) / "applications" for part in [home, *raw.split(":")] if part]


def apps_provider() -> list[dict]:
    seen: dict[str, dict] = {}
    for directory in desktop_dirs():
        if not directory.is_dir():
            continue
        for path in sorted(directory.glob("*.desktop")):
            if path.name in seen:
                continue
            entry = parse_desktop(path)
            if entry:
                seen[path.name] = entry
    return sorted(seen.values(), key=lambda row: row["label"].lower())


def parse_desktop(path: Path) -> dict | None:
    fields: dict[str, str] = {}
    in_main = False
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("["):
            in_main = line == "[Desktop Entry]"
            continue
        if not in_main or "=" not in line:
            continue
        key, _, value = line.partition("=")
        fields.setdefault(key.strip(), value.strip())
    if fields.get("Type", "Application") != "Application":
        return None
    if fields.get("NoDisplay", "").lower() == "true":
        return None
    if fields.get("Hidden", "").lower() == "true":
        return None
    name = fields.get("Name")
    if not name:
        return None
    return {
        "key": path.name,
        "icon": "",
        "label": name,
        "search": " ".join(
            part for part in (fields.get("Keywords", ""), fields.get("Comment", "")) if part
        ),
        "action": desktop_launch(path.name, fields.get("Exec", "")),
    }


def desktop_launch(desktop_id: str, exec_line: str) -> str:
    stem = desktop_id[:-len(".desktop")] if desktop_id.endswith(".desktop") else desktop_id
    fallback = re.sub(r"%[a-zA-Z]", "", exec_line).strip()
    if not fallback:
        fallback = "true"
    return f"gtk-launch {shlex.quote(stem)} || {fallback}"


def fonts_provider() -> list[dict]:
    families = run_lines(["fc-list", ":", "family"])
    current = ""
    match = run_lines(["fc-match", "--format=%{family}"])
    if match:
        current = match[0].split(",")[0].strip()
    seen: list[str] = []
    for line in families:
        for family in line.split(","):
            family = family.strip()
            if family and family not in seen:
                seen.append(family)
    rows = []
    for family in sorted(seen, key=str.lower):
        rows.append({
            "key": family,
            "icon": "",
            "label": family,
            "checked_now": family == current,
            "action": "notify-send 'Font' %s" % shlex.quote(
                f"{family} selected. Set it in your terminal or bar config."
            ),
        })
    return rows


def themes_provider() -> list[dict]:
    theme_cli = str(Path.home() / ".local/bin/theme")
    slugs = run_lines([theme_cli, "list"])
    current = run_lines([theme_cli, "current"])
    active = current[0].strip() if current else ""
    rows = []
    for line in slugs:
        # `theme list` prints an aligned "[*] slug  Name  mode" table, where the
        # leading asterisk marks the active theme.
        fields = line.split()
        if fields and fields[0] == "*":
            fields = fields[1:]
        slug = fields[0] if fields else ""
        if not slug:
            continue
        rows.append({
            "key": slug,
            "icon": "",
            "label": slug,
            "checked_now": slug == active,
            "action": f"{shlex.quote(theme_cli)} set {shlex.quote(slug)}",
        })
    return rows


def timezones_provider() -> list[dict]:
    zones = run_lines(["timedatectl", "list-timezones"])
    current = run_lines(["timedatectl", "show", "-p", "Timezone", "--value"])
    active = current[0].strip() if current else ""
    rows = []
    for zone in zones:
        zone = zone.strip()
        if not zone:
            continue
        rows.append({
            "key": zone,
            "icon": "",
            "label": zone,
            "checked_now": zone == active,
            "action": f"sudo timedatectl set-timezone {shlex.quote(zone)}",
        })
    return rows


def run_lines(command: list[str]) -> list[str]:
    try:
        completed = subprocess.run(
            command, capture_output=True, text=True, timeout=10
        )
    except (OSError, subprocess.SubprocessError):
        return []
    if completed.returncode != 0:
        return []
    return completed.stdout.splitlines()


# --------------------------------------------------------------------------
# Views


class Row:
    def __init__(self, icon, label, suffix, row_id, kind, payload, urgent=False,
                 crumb="", meta=""):
        self.icon = icon
        self.label = label
        self.suffix = suffix
        self.id = row_id
        self.kind = kind
        self.payload = payload
        self.urgent = urgent
        # Where a nested search row lives, relative to the view showing it.
        # Empty for the view's own direct rows.
        self.crumb = crumb
        # Invisible search terms rofi matches against as well as the label.
        self.meta = meta

    def tsv(self) -> str:
        return "\t".join((self.icon, self.label, self.suffix, self.id,
                          self.crumb, self.meta))


def search_terms(*parts: str) -> str:
    """Flatten search terms onto one line so they survive the TSV protocol."""
    return " ".join(" ".join(part.split()) for part in parts if part)


def build_view(menu: Menu, route: str) -> list[Row]:
    direct, nested = view_phases(menu, route)
    return direct + list(nested)


def view_phases(menu: Menu, route: str):
    """The route's own rows as a list, and a lazy iterator over the rows
    nested below them.  Nothing below the direct rows is evaluated until the
    iterator is consumed, which is what lets lmenu draw a view before its
    subtree's guards have finished."""
    entry = menu.by_id.get(route)
    if entry is not None and menu.kind(entry) == "provider":
        return provider_view(entry), iter(())
    return static_view(menu, route)


def provider_view(entry: dict, crumb: str = "") -> list[Row]:
    rows = []
    for generated in provider_rows(entry["provider"]):
        suffix = CHECK if generated.get("checked_now") else ""
        rows.append(Row(
            generated.get("icon", ""),
            generated["label"],
            suffix,
            f"{entry['id']}{SEP}{generated['key']}",
            "leaf",
            generated["action"],
            crumb=crumb,
            meta=search_terms(generated.get("search", "")),
        ))
    return rows


def subtree(menu: Menu, route: str) -> list[tuple[dict, list[str]]]:
    """Every entry below route in tree order, each with the labels of the
    entries between route and it."""
    found: list[tuple[dict, list[str]]] = []

    def walk(parent: str, trail: list[str]) -> None:
        for child in menu.children.get(parent, []):
            found.append((child, trail))
            walk(child["id"], trail + [label_of(child)])

    walk(route, [])
    return found


def label_of(entry: dict) -> str:
    return entry.get("label", entry["id"].rpartition(".")[2])


def guard_requests(entries: list[tuple[dict, list[str]]]) -> list[tuple[str, str, str]]:
    requests: list[tuple[str, str, str]] = []
    for child, _ in entries:
        for kind, field in (("w", "when"), ("c", "checked"), ("d", "disabled")):
            if child.get(field):
                requests.append((child["id"], kind, child[field]))
    return requests


def reachable(entries, guards, unreachable: set[str]):
    """Yield (entry, trail, checked, disabled) for every entry browsing could
    reach: a failing "when" hides an entry, and a hidden or dimmed entry takes
    everything below it along.  unreachable carries that across calls, so a
    subtree can be walked in phases."""
    for child, trail in entries:
        parent = child["id"].rpartition(".")[0]
        if parent in unreachable:
            unreachable.add(child["id"])
            continue
        if child.get("when") and not guards.get((child["id"], "w"), False):
            unreachable.add(child["id"])
            continue
        disabled = bool(child.get("disabled")) and guards.get((child["id"], "d"), False)
        checked = bool(child.get("checked")) and guards.get((child["id"], "c"), False)
        if disabled:
            unreachable.add(child["id"])
        yield child, trail, checked, disabled


def static_view(menu: Menu, route: str):
    """The route's own rows, and an iterator over every row nested below it.

    The nested rows are what make a submenu searchable from above: the launcher
    sizes its list to the direct rows, so they only come into view once typing
    filters the direct rows away.  A nested row is dropped when any entry
    between it and the route is hidden or dimmed, exactly as browsing could
    never reach it.

    The two phases evaluate their guards separately, so the direct rows cost
    only their own guards and the whole subtree's are paid while the menu is
    already on screen.
    """
    entries = subtree(menu, route)
    unreachable: set[str] = set()

    def rows_for(phase: list[tuple[dict, list[str]]]) -> list[Row]:
        guards = evaluate_guards(guard_requests(phase))
        rows: list[Row] = []
        for child, trail, checked, disabled in reachable(phase, guards, unreachable):
            kind = menu.kind(child)
            # A tick outranks a chevron: a checked row is reporting state, which
            # matters more than the fact that it also descends.  Nested rows
            # carry their breadcrumb instead of a chevron.
            if checked or disabled:
                suffix = CHECK
            elif kind in ("submenu", "link", "provider") and not trail:
                suffix = CHEVRON
            else:
                suffix = ""
            payload = child.get("action") or child.get("target") or child["id"]
            rows.append(Row(
                child.get("icon", ""),
                label_of(child),
                suffix,
                child["id"],
                kind,
                payload,
                urgent=disabled,
                crumb=CRUMB_SEP.join(trail),
                meta=search_terms(" ".join(child.get("aliases", [])),
                                  child.get("description", "")),
            ))
            if (kind == "provider" and not disabled
                    and child["provider"] in SEARCHABLE_PROVIDERS):
                searchable.append((len(rows), child, trail))
        return rows

    def expand(rows: list[Row]) -> list[Row]:
        """Splice searchable provider rows in after the row that owns them."""
        for position, child, trail in reversed(searchable):
            rows[position:position] = provider_view(
                child, CRUMB_SEP.join(trail + [label_of(child)]))
        searchable.clear()
        return rows

    searchable: list[tuple[int, dict, list[str]]] = []
    direct = rows_for([entry for entry in entries if not entry[1]])
    # A direct provider's generated rows are nested rows, so they wait too.
    direct_providers = list(searchable)
    searchable.clear()

    def nested():
        rows = rows_for([entry for entry in entries if entry[1]])
        for _, child, trail in direct_providers:
            yield from provider_view(child, label_of(child))
        yield from expand(rows)

    return direct, nested()


def has_nested(menu: Menu, route: str) -> bool:
    """Whether a view can show search rows below its own, judged from the tree
    alone so the answer is ready before any guard runs."""
    entry = menu.by_id.get(route)
    if entry is not None and menu.kind(entry) == "provider":
        return False
    for child in menu.children.get(route, []):
        if menu.children.get(child["id"]):
            return True
        if child.get("provider") in SEARCHABLE_PROVIDERS:
            return True
    return False


def display(row: Row, pad: int) -> str:
    """The exact text rofi shows for a row.

    Suffixes (a chevron for rows that descend, a tick for rows reporting state)
    are padded into a column of their own, which only lines up because the
    launcher font is monospace.  A nested row trails the menus it lives under
    instead of joining that column.
    """
    icon = f"{row.icon}  " if row.icon else ""
    if row.crumb:
        return f"{icon}{row.label}   {row.crumb}" + (f"  {row.suffix}" if row.suffix else "")
    if row.suffix:
        return f"{icon}{row.label:<{pad}}  {row.suffix}"
    return f"{icon}{row.label}"


def rofi_line(row: Row, pad: int) -> str:
    """A display line plus rofi row options: hidden search terms, and the
    urgent flag lmenu uses to dim a disabled row."""
    options = []
    if row.meta:
        options.append(f"meta\x1f{row.meta}")
    if row.urgent:
        options.append("urgent\x1ftrue")
    line = display(row, pad)
    if options:
        line += "\0" + "\x1f".join(options)
    return line + "\n"


def feed(menu: Menu, route: str, view_path: str) -> int:
    """Stream one view to lmenu, which hands the stream straight to rofi.

    The first line is a "<title>\\t<direct rows>\\t<has nested rows>" header
    lmenu reads to size the list.  Every row after it is written to view_path
    as a NUL-terminated "<id>\\t<kind>\\t<payload>" record before it is
    printed, so the index rofi returns maps straight back to what to run,
    without evaluating the view a second time.
    """
    direct, nested = view_phases(menu, route)
    pad = max((len(row.label) for row in direct), default=0)
    out = sys.stdout
    try:
        with open(view_path, "w", encoding="utf-8") as view:
            out.write(f"{menu.title(route)}\t{len(direct)}\t"
                      f"{int(has_nested(menu, route))}\n")
            out.flush()

            def emit(row: Row) -> None:
                kind, payload = row.kind, row.payload
                if row.urgent:
                    kind, payload = "disabled", ""
                elif kind == "link":
                    payload = menu.resolve_route(payload)
                view.write(f"{row.id}\t{kind}\t{payload}\0")
                view.flush()
                out.write(rofi_line(row, pad))

            for row in direct:
                emit(row)
            out.flush()
            for row in nested:
                emit(row)
                out.flush()
    except BrokenPipeError:
        # rofi closed before the stream ended: a row was picked early.
        os.dup2(os.open(os.devnull, os.O_WRONLY), out.fileno())
    return 0


def dump(menu: Menu) -> dict:
    """The whole reachable tree as one document, for a resident front end.

    The Quickshell panel holds this in memory, so opening, browsing and
    searching never wait on a process; it re-runs the dump in the background
    to refresh ticks and visibility.  Guards and every provider run
    concurrently, since each is a wait on another process.
    """
    entries = subtree(menu, "")
    providers = [child for child, _ in entries if menu.kind(child) == "provider"]
    with ThreadPoolExecutor(max_workers=len(providers) + 1) as pool:
        guard_job = pool.submit(evaluate_guards, guard_requests(entries))
        provider_jobs = {child["id"]: pool.submit(provider_rows, child["provider"])
                         for child in providers}
        guards = guard_job.result()

        items = []
        generated: dict[str, list[dict]] = {}
        for child, _, checked, disabled in reachable(entries, guards, set()):
            kind = menu.kind(child)
            payload = child.get("action") or child.get("target") or child["id"]
            if kind == "link":
                payload = menu.resolve_route(payload)
            items.append({
                "id": child["id"],
                "parent": child["id"].rpartition(".")[0],
                "icon": child.get("icon", ""),
                "label": label_of(child),
                "title": menu.title(child["id"]),
                "kind": kind,
                "payload": payload,
                "search": search_terms(" ".join(child.get("aliases", [])),
                                       child.get("description", "")),
                "checked": checked,
                "disabled": disabled,
                "searchable": child.get("provider") in SEARCHABLE_PROVIDERS,
            })
            if kind == "provider" and not disabled:
                generated[child["id"]] = [{
                    "id": f"{child['id']}{SEP}{row['key']}",
                    "icon": row.get("icon", ""),
                    "label": row["label"],
                    "payload": row["action"],
                    "search": search_terms(row.get("search", "")),
                    "checked": bool(row.get("checked_now")),
                } for row in provider_jobs[child["id"]].result()]
    return {"entries": items, "providers": generated, "aliases": menu.aliases}


def resolve(menu: Menu, route: str, row_id: str) -> tuple[str, str] | None:
    for row in build_view(menu, route):
        if row.id == row_id:
            if row.urgent:
                return ("disabled", "")
            return (row.kind, row.payload)
    return None


# --------------------------------------------------------------------------
# Entry point


def main(argv: list[str]) -> int:
    menu_path = DEFAULT_MENU
    overlay_path = DEFAULT_OVERLAY
    args = list(argv)

    dry_run = False
    if args and args[0] == "--dry-run":
        dry_run = True
        args.pop(0)
        args.insert(0, "rows")

    if not args:
        print(__doc__, file=sys.stderr)
        return 2

    command, rest = args[0], args[1:]

    try:
        entries = load_menu(menu_path, overlay_path)
    except (ValueError, json.JSONDecodeError, OSError) as error:
        warn(f"cannot read {menu_path}: {error}")
        return 1
    menu = Menu(entries)

    if command == "validate":
        print(f"ok: {len(entries)} entries, {len(menu.children)} branches")
        return 0

    if command == "route":
        print(menu.resolve_route(rest[0] if rest else ""))
        return 0

    if command == "title":
        print(menu.title(menu.resolve_route(rest[0] if rest else "")))
        return 0

    if command == "rows":
        route = menu.resolve_route(rest[0] if rest else "")
        rows = build_view(menu, route)
        if dry_run:
            print(f"# route: {route or '(root)'}  title: {menu.title(route)}")
            for row in rows:
                flag = "disabled" if row.urgent else row.kind
                print(f"{row.tsv()}\t{flag}\t{row.payload}")
            return 0
        for row in rows:
            print(row.tsv())
        print("#direct:" + str(sum(1 for row in rows if not row.crumb)))
        urgent = [str(i) for i, row in enumerate(rows) if row.urgent]
        print("#urgent:" + ",".join(urgent))
        return 0

    if command == "dump":
        json.dump(dump(menu), sys.stdout, ensure_ascii=False)
        sys.stdout.write("\n")
        return 0

    if command == "feed":
        if len(rest) < 2:
            warn("feed needs a route and a view file")
            return 2
        return feed(menu, menu.resolve_route(rest[0]), rest[1])

    if command == "resolve":
        if len(rest) < 2:
            warn("resolve needs a route and a row id")
            return 2
        route = menu.resolve_route(rest[0])
        found = resolve(menu, route, rest[1])
        if not found:
            return 1
        print("\t".join(found))
        return 0

    warn(f"unknown command {command!r}")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
