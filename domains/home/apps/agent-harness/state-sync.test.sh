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
git -C "$ROOT/state" push -u origin main >/dev/null 2>&1

printf 'local\n' > "$ROOT/config/projects/demo/memory/local.md"
AGENT_STATE_DIR="$ROOT/state" AGENT_CONFIG_DIRS="$ROOT/config" AGENT_HOST=test \
  bash "$(dirname "$0")/state-sync.sh" link

test -L "$ROOT/config/projects/demo/memory"
test "$(readlink "$ROOT/config/projects/demo/memory")" = "$ROOT/state/projects/demo/memory"
test "$(cat "$ROOT/state/projects/demo/memory/local.md")" = local

unlink "$ROOT/config/projects/demo/memory"
ln -s "$ROOT/retired/projects/demo/memory" "$ROOT/config/projects/demo/memory"
AGENT_STATE_DIR="$ROOT/state" AGENT_CONFIG_DIRS="$ROOT/config" AGENT_HOST=test \
  bash "$(dirname "$0")/state-sync.sh" link
test "$(readlink "$ROOT/config/projects/demo/memory")" = "$ROOT/state/projects/demo/memory"

AGENT_STATE_DIR="$ROOT/state" AGENT_CONFIG_DIRS="$ROOT/config" AGENT_HOST=test \
  bash "$(dirname "$0")/state-sync.sh" sync
git -C "$ROOT/state" status --porcelain | test ! -s /dev/stdin
printf 'state-sync.test: PASS\n'
