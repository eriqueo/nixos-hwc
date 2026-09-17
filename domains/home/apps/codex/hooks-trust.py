#!/usr/bin/env python3
"""hooks-trust.py — record Codex trust for the hooks in the shared hooks.json.

Codex refuses to run a hook until its definition hash is recorded under
hooks.state in config.toml ("1 hook needs review before it can run"). Trust
state is per host, while ~/.codex/hooks.json is linked from ~/.claude-config,
so every host must record the hashes after the file changes. This asks the
Codex app-server for the hooks it sees (hooks/list), and writes trust through
the same server (config/value/write) only for hooks whose source is the user
hooks.json. Project and plugin hooks are never touched.

Lives beside index.nix, not inline, so it can run by hand against a scratch
CODEX_HOME. Usage: hooks-trust.py <codex-binary>...  (first that answers wins)
Exit: 0 every user hook trusted · 1 a hook is still untrusted or no binary answered
"""
import json
import os
import select
import subprocess
import sys
import time

TIMEOUT = 30


def rpc_session(binary):
    proc = subprocess.Popen(
        [binary, "app-server"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        cwd=os.path.expanduser("~"),
    )
    stdin, stdout = proc.stdin, proc.stdout
    assert stdin is not None and stdout is not None

    def send(msg):
        stdin.write(json.dumps(msg) + "\n")
        stdin.flush()

    def recv(msg_id):
        deadline = time.time() + TIMEOUT
        while time.time() < deadline:
            ready, _, _ = select.select([stdout], [], [], 1)
            if not ready:
                continue
            line = stdout.readline()
            if not line:
                return None
            try:
                msg = json.loads(line)
            except ValueError:
                continue
            if msg.get("id") == msg_id:
                return msg
        return None

    return proc, send, recv


def main(binaries):
    home = os.environ.get("CODEX_HOME", os.path.expanduser("~/.codex"))
    link = os.path.join(home, "hooks.json")
    # hooks.json is a symlink into ~/.claude-config; accept either spelling of its source.
    sources = tuple({link + ":", os.path.realpath(link) + ":"})
    for binary in binaries:
        if not (os.path.isfile(binary) and os.access(binary, os.X_OK)):
            continue
        proc, send, recv = rpc_session(binary)
        try:
            send({"id": 1, "method": "initialize",
                  "params": {"clientInfo": {"name": "hwc-hooks-trust", "version": "1"}}})
            if recv(1) is None:
                continue
            send({"method": "initialized"})
            send({"id": 2, "method": "hooks/list", "params": {"cwds": [os.path.expanduser("~")]}})
            listed = recv(2)
            if not listed or "result" not in listed:
                print(f"hooks-trust: {binary} did not answer hooks/list", file=sys.stderr)
                continue
            hooks = [h for entry in listed["result"].get("data", [])
                     for h in entry.get("hooks", [])
                     if h.get("key", "").startswith(sources)]
            if not hooks:
                print(f"hooks-trust: {binary} lists no hooks from {link}", file=sys.stderr)
                return 1
            untrusted = [h for h in hooks if h.get("trustStatus") in ("untrusted", "modified")]
            next_id = 3
            for hook in untrusted:
                send({"id": next_id, "method": "config/value/write", "params": {
                    "keyPath": f'hooks.state."{hook["key"]}"',
                    "value": {"trusted_hash": hook["currentHash"], "enabled": True},
                    "mergeStrategy": "upsert",
                }})
                reply = recv(next_id)
                next_id += 1
                if not reply or "result" not in reply:
                    print(f"hooks-trust: failed to trust {hook['key']}: {reply}", file=sys.stderr)
            send({"id": next_id, "method": "hooks/list", "params": {"cwds": [os.path.expanduser("~")]}})
            after = recv(next_id)
            still = [h["key"] for entry in (after or {}).get("result", {}).get("data", [])
                     for h in entry.get("hooks", [])
                     if h.get("key", "").startswith(sources)
                     and h.get("trustStatus") not in ("trusted", "managed")]
            print(f"hooks-trust: {len(hooks)} user hooks, {len(untrusted)} newly trusted, "
                  f"{len(still)} untrusted ({binary})")
            for key in still:
                print(f"hooks-trust: still untrusted: {key}", file=sys.stderr)
            return 0 if (after and not still) else 1
        finally:
            proc.kill()
            proc.wait()
    print("hooks-trust: no Codex binary answered", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
