"""Versioned favorites: CRITICAL user data, retained until removed; home backups.

Bound: 128 entries / 64 KiB; reject at capacity. Mutations are idempotent by path,
locked and atomically replaced, with no retry loop. Lua never writes this store.
"""
import fcntl
import json
import os
from pathlib import Path
import sys
import tempfile

MAX_ENTRIES, MAX_BYTES = 128, 65536


class StoreError(Exception):
    def __init__(self, code, message):
        self.code, self.message = code, message


def validate(data):
    if not isinstance(data, dict) or data.get("version") != 1:
        raise StoreError("format", "Unsupported favorites format. Restore a version 1 file.")
    entries = data.get("favorites")
    if not isinstance(entries, list) or len(entries) > MAX_ENTRIES:
        raise StoreError("limit", "Favorites must contain at most 128 entries.")
    seen = set()
    for entry in entries:
        if not isinstance(entry, dict) or set(entry) != {"name", "path"}:
            raise StoreError("format", "Each favorite must have a name and path.")
        name, path = entry["name"], entry["path"]
        if not isinstance(name, str) or not name.strip() or len(name) > 80 or any(ord(c) < 32 or ord(c) == 127 for c in name):
            raise StoreError("name", "Use a name of 1 to 80 characters without control characters.")
        if not isinstance(path, str) or not Path(path).is_absolute() or any(ord(c) < 32 or ord(c) == 127 for c in path):
            raise StoreError("path", "Use an absolute local directory path without control characters.")
        if path in seen:
            raise StoreError("duplicate", "The favorites file contains a duplicate path.")
        seen.add(path)
    return data


def read(path):
    with path.open("rb") as handle:
        raw = handle.read(MAX_BYTES + 1)
    if len(raw) > MAX_BYTES:
        raise StoreError("limit", "Favorites file exceeds 64 KiB. Reduce it before editing.")
    try:
        return validate(json.loads(raw))
    except (ValueError, UnicodeError) as error:
        raise StoreError("format", "Favorites file is invalid JSON. Restore it before editing.") from error


def load(path, defaults):
    try:
        return read(path)
    except FileNotFoundError:
        return read(defaults)


def change(data, action, path, name):
    entries = data["favorites"]
    index = next((i for i, item in enumerate(entries) if item["path"] == path), None)
    if action == "add":
        if not Path(path).is_dir():
            raise StoreError("directory", "That directory is unavailable. Choose an existing local folder.")
        if index is None:
            entries.append({"name": name.strip(), "path": path})
    elif action == "rename":
        if index is None:
            raise StoreError("missing", "Another window removed this favorite. Reopen favorites.")
        entries[index]["name"] = name.strip()
    elif action == "remove":
        if index is not None:
            entries.pop(index)
    else:
        raise StoreError("action", "Unknown favorites action.")
    return validate(data)


def save(path, data):
    raw = (json.dumps(data, ensure_ascii=False, indent=2) + "\n").encode()
    if len(raw) > MAX_BYTES:
        raise StoreError("limit", "Favorites exceed 64 KiB. Remove an entry before adding another.")
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix=".favorites-", delete=False) as handle:
            temporary = Path(handle.name)
            handle.write(raw)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
        temporary = None
        descriptor = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def run(path, defaults, action, target="", name=""):
    if action == "load":
        return load(path, defaults)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.with_suffix(".lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise StoreError("busy", "Another window is saving favorites. Try this action again.") from error
        data = change(load(path, defaults), action, target, name)
        save(path, data)
        return data


def main(arguments):
    try:
        if len(arguments) not in (3, 4, 5):
            raise StoreError("arguments", "Expected store path, defaults path, action, optional path and name.")
        data = run(Path(arguments[0]), Path(arguments[1]), *arguments[2:])
        response = {"ok": True, "favorites": data["favorites"]}
    except StoreError as error:
        response = {"ok": False, "code": error.code, "error": error.message}
    except OSError as error:
        response = {"ok": False, "code": "io", "error": f"Cannot access favorites: {error}. Inspect {arguments[0]}."}
    print(json.dumps(response, ensure_ascii=False))
    return 0 if response["ok"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
