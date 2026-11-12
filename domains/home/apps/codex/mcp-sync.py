#!/usr/bin/env python3
"""mcp-sync.py — give Codex the MCP servers Claude Code gets.

agent-harness generates ~/.mcp.json, the one list of MCP servers. Codex keeps
its servers in config.toml, a per-host file that also holds hook trust, so it
cannot be a store link. This mirrors each server in that list into Codex with
Codex's own `codex mcp add` / `remove`, which edit only their own table.

Names this script wrote are recorded in $CODEX_HOME/hwc-mcp-managed.json, so a
server dropped from the list is removed again. A server added by hand under a
name the list does not use is never touched.

Usage: mcp-sync.py [--check] <mcp.json> <codex-binary>
Exit: 0 Codex has every listed server as listed · 1 it does not, or codex failed
"""
import json
import os
import subprocess
import sys


def wanted(entry):
    """The parts of a ~/.mcp.json entry Codex keeps, in a form both sides share."""
    if entry.get("type") in ("http", "streamable_http") or "url" in entry:
        return {"url": entry["url"]}
    return {"command": entry["command"], "args": list(entry.get("args", [])),
            "env": dict(entry.get("env", {}))}


def present(row):
    t = row.get("transport", {})
    if t.get("type") == "streamable_http":
        return {"url": t.get("url")}
    return {"command": t.get("command"), "args": list(t.get("args") or []), "env": dict(t.get("env") or {})}


def codex(binary, *args):
    return subprocess.run([binary, "mcp", *args], capture_output=True, text=True)


def main(argv):
    check = bool(argv and argv[0] == "--check")
    if check:
        argv = argv[1:]
    source, binary = argv
    if not os.path.exists(source):
        print(f"mcp-sync: {source} does not exist on this host; nothing to mirror")
        return 0
    want = {name: wanted(e) for name, e in json.load(open(source))["mcpServers"].items()}
    home = os.environ.get("CODEX_HOME", os.path.expanduser("~/.codex"))
    state = os.path.join(home, "hwc-mcp-managed.json")
    managed = set(json.load(open(state))) if os.path.exists(state) else set()

    listed = codex(binary, "list", "--json")
    if listed.returncode:
        print(f"mcp-sync: codex mcp list failed: {listed.stderr.strip()}", file=sys.stderr)
        return 1
    have = {row["name"]: present(row) for row in json.loads(listed.stdout or "[]")}
    stale = sorted(n for n in want if have.get(n) != want[n])
    gone = sorted(n for n in managed - set(want) if n in have)
    if check:
        for n in stale:
            print(f"mcp-sync: Codex lacks or differs on {n}", file=sys.stderr)
        for n in gone:
            print(f"mcp-sync: Codex still has removed server {n}", file=sys.stderr)
        print(f"mcp-sync: {len(want) - len(stale)} of {len(want)} servers match")
        return 1 if stale or gone else 0

    failed = []
    for n in stale:
        w = want[n]
        if "url" in w:
            r = codex(binary, "add", n, "--url", w["url"])
        else:
            env = [x for k, v in sorted(w["env"].items()) for x in ("--env", f"{k}={v}")]
            r = codex(binary, "add", n, *env, "--", w["command"], *w["args"])
        if r.returncode:
            failed.append(n)
            print(f"mcp-sync: could not add {n}: {r.stderr.strip()}", file=sys.stderr)
    for n in gone:
        if codex(binary, "remove", n).returncode:
            failed.append(n)
            print(f"mcp-sync: could not remove {n}", file=sys.stderr)
    with open(state + ".tmp", "w") as fh:
        json.dump(sorted(want), fh)
    os.replace(state + ".tmp", state)
    print(f"mcp-sync: {len(want)} servers listed, {len(stale)} written, {len(gone)} removed, {len(failed)} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
