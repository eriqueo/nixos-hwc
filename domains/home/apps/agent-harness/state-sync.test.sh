#!/usr/bin/env bash
set -euo pipefail

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
git init --bare "$ROOT/hub.git" >/dev/null
git clone "$ROOT/hub.git" "$ROOT/state" >/dev/null 2>&1
git -C "$ROOT/state" config user.name test
git -C "$ROOT/state" config user.email test@example.invalid
mkdir -p "$ROOT/state/projects/demo/memory" "$ROOT/config/projects/demo/memory"
printf '# MISTAKES\n' > "$ROOT/state/MISTAKES.md"
printf 'state\n' > "$ROOT/state/projects/demo/memory/MEMORY.md"
git -C "$ROOT/state" add .
git -C "$ROOT/state" commit -m seed >/dev/null
BASE=$(git -C "$ROOT/state" rev-parse HEAD)
printf '{"schemaVersion":1,"memoryContractBase":"%s"}\n' "$BASE" > "$ROOT/state/.harness-schema.json"
git -C "$ROOT/state" add .harness-schema.json
git -C "$ROOT/state" commit -m schema >/dev/null
git -C "$ROOT/state" push -u origin main >/dev/null 2>&1

cat > "$ROOT/config/projects/demo/memory/local.md" <<'EOF'
---
name: local
description: test memory
authority: observation
source: test fixture
metadata:
  type: project
---

local
EOF
AGENT_STATE_DIR="$ROOT/state" AGENT_CONFIG_DIRS="$ROOT/config" AGENT_HOST=test \
  bash "$(dirname "$0")/state-sync.sh" link

test -L "$ROOT/config/projects/demo/memory"
test "$(readlink "$ROOT/config/projects/demo/memory")" = "$ROOT/state/projects/demo/memory"
rg -q '^local$' "$ROOT/state/projects/demo/memory/local.md"

unlink "$ROOT/config/projects/demo/memory"
ln -s "$ROOT/retired/projects/demo/memory" "$ROOT/config/projects/demo/memory"
AGENT_STATE_DIR="$ROOT/state" AGENT_CONFIG_DIRS="$ROOT/config" AGENT_HOST=test \
  bash "$(dirname "$0")/state-sync.sh" link
test "$(readlink "$ROOT/config/projects/demo/memory")" = "$ROOT/state/projects/demo/memory"

AGENT_STATE_DIR="$ROOT/state" AGENT_CONFIG_DIRS="$ROOT/config" AGENT_HOST=test \
  bash "$(dirname "$0")/state-sync.sh" sync
test -z "$(git -C "$ROOT/state" status --porcelain)"

printf '%s\n' 'invalid memory' > "$ROOT/state/projects/demo/memory/invalid.md"
if AGENT_STATE_DIR="$ROOT/state" AGENT_CONFIG_DIRS="$ROOT/config" AGENT_HOST=test \
    bash "$(dirname "$0")/state-sync.sh" sync >/dev/null 2>&1; then
  echo 'state-sync.test: invalid memory unexpectedly synchronized' >&2
  exit 1
fi
rm "$ROOT/state/projects/demo/memory/invalid.md"
printf 'state-sync.test: PASS\n'
