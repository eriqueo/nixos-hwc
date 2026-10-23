#!/usr/bin/env bash
# Check files, recipient rules and the selected host's scoped mounts.
set -euo pipefail
REPO="$(git rev-parse --show-toplevel)"
exec python3 - "$REPO" "${1:-$(hostname)}" <<'PYTHON'
import json, pathlib, subprocess, sys
repo, host = pathlib.Path(sys.argv[1]), sys.argv[2]
def evaluate(expression):
    return json.loads(subprocess.run(["nix", "eval", "--impure", "--json", "--expr", expression],
        cwd=repo, check=True, capture_output=True, text=True, timeout=90).stdout)
root = json.dumps(str(repo))
entries = evaluate(f"let g=import ({root}+\"/domains/secrets/parts/lib.nix\") {{}}; in g.walkParts ({root}+\"/domains/secrets/parts\")")
rules = evaluate(f"builtins.attrNames (import ({root}+\"/secrets.nix\"))")
expected = evaluate(f"let g=import ({root}+\"/domains/secrets/parts/lib.nix\") {{}}; es=g.walkParts ({root}+\"/domains/secrets/parts\"); in map (e: e.name) (builtins.filter (e: g.mountAllowed {json.dumps(host)} e.name) es)")
mounts = evaluate(f"builtins.attrNames (builtins.getFlake (\"path:\"+{root})).nixosConfigurations.{host}.config.age.secrets")
for entry in entries:
    assert "domains/secrets/parts/" + entry["rel"] in rules, "missing recipient rule: " + entry["name"]
for rule in rules:
    assert (repo / rule).is_file(), "dangling recipient rule: " + rule
assert len({entry["name"] for entry in entries}) == len(entries), "derived secret name collision"
assert set(mounts) == set(expected) | {"caddy-cert", "caddy-key"}, "host mount set differs from scoped policy"
print(f"secrets parity {host}: {len(entries)} payloads, {len(rules)} rules, {len(mounts)} permitted mounts; passed")
PYTHON
