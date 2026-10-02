#!/usr/bin/env python3
"""Read cliphist pins using complete-content hashes, never display previews."""
import hashlib
import json
import re
import subprocess
import sys


def cliphist(*args):
    return subprocess.run(["cliphist", *args], capture_output=True,
                          check=True, timeout=1).stdout


def content_hash(entry_id):
    if not re.fullmatch(r"[0-9]+", entry_id):
        raise ValueError("invalid clipboard ID")
    return hashlib.sha256(cliphist("decode", entry_id)).hexdigest()


def read_pins(value):
    pins = json.loads(value)
    if not isinstance(pins, list):
        raise ValueError("pins must be a list")
    for pin in pins:
        if not isinstance(pin, dict) or not re.fullmatch(r"[0-9]+", str(pin.get("id", ""))):
            raise ValueError("invalid pinned ID")
        if "hash" in pin and not re.fullmatch(r"[a-f0-9]{64}", str(pin["hash"])):
            raise ValueError("invalid pinned hash")
        if "preview" in pin and not isinstance(pin["preview"], str):
            raise ValueError("invalid pinned preview")
    return pins


def list_entries(pins):
    ids = {str(pin["id"]) for pin in pins}
    previews = {pin["preview"] for pin in pins if "preview" in pin}
    rows = []
    for line in cliphist("list").decode("utf-8", errors="replace").split("\n"):
        entry_id, tab, preview = line.partition("\t")
        if not tab or not re.fullmatch(r"[0-9]+", entry_id):
            continue
        row = dict(id=entry_id, preview=preview)
        # Previews only narrow decoding work; equality is checked with a hash.
        if entry_id in ids or preview in previews:
            row["hash"] = content_hash(entry_id)
        rows.append(row)
    return rows


def main():
    mode, value = sys.argv[1:]
    if mode == "hash":
        print(content_hash(value))
        return
    pins = read_pins(value)
    rows = list_entries(pins)
    if mode == "list":
        print(json.dumps(rows))
    elif mode == "resolve":
        hashes = {pin["hash"] for pin in pins if "hash" in pin}
        # Before migration, an existing ID is safe. Never migrate by preview.
        legacy_ids = {str(pin["id"]) for pin in pins if "hash" not in pin}
        matches = [row["id"] for row in rows
                   if row.get("hash") in hashes or row["id"] in legacy_ids]
        print("\n".join(matches))
    else:
        raise ValueError("unknown clipboard pin operation")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f"clipboard pins: {error}", file=sys.stderr)
        sys.exit(1)
