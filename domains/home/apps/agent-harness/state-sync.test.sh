#!/usr/bin/env bash
set -euo pipefail

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/bin"
cat > "$ROOT/bin/curl" <<EOF
#!/usr/bin/env bash
cat >/dev/null
printf 'alert\n' >> "$ROOT/alerts"
EOF
chmod +x "$ROOT/bin/curl"
export PATH="$ROOT/bin:$PATH"
export AGENT_STATE_NOTIFY_URL=http://notify.invalid/notify
VALIDATOR=$(realpath "$(dirname "$0")/state-validate.sh")
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

cat > "$ROOT/bin/counting-validator" <<EOF
#!/usr/bin/env bash
printf 'validate\n' >> "$ROOT/validations"
exec bash "$VALIDATOR" "\$@"
EOF
chmod +x "$ROOT/bin/counting-validator"

printf '%s\n' 'invalid memory' > "$ROOT/state/projects/demo/memory/invalid.md"
if AGENT_STATE_DIR="$ROOT/state" AGENT_CONFIG_DIRS="$ROOT/config" AGENT_HOST=test \
    AGENT_STATE_VALIDATOR="$ROOT/bin/counting-validator" \
    bash "$(dirname "$0")/state-sync.sh" sync >/dev/null 2>&1; then
  echo 'state-sync.test: invalid memory unexpectedly synchronized' >&2
  exit 1
fi
test "$(wc -l < "$ROOT/alerts")" -eq 1
test "$(wc -l < "$ROOT/validations")" -eq 1
set +e
AGENT_STATE_DIR="$ROOT/state" AGENT_CONFIG_DIRS="$ROOT/config" AGENT_HOST=test \
  AGENT_STATE_VALIDATOR="$ROOT/bin/counting-validator" \
  bash "$(dirname "$0")/state-sync.sh" sync >/dev/null 2>&1
repeat_rc=$?
set -e
if [ "$repeat_rc" -ne 75 ]; then
  echo "state-sync.test: repeated invalid memory returned $repeat_rc instead of 75" >&2
  exit 1
fi
test "$(wc -l < "$ROOT/alerts")" -eq 1
test "$(wc -l < "$ROOT/validations")" -eq 1

printf '%s\n' 'different invalid memory' > "$ROOT/state/projects/demo/memory/invalid.md"
if AGENT_STATE_DIR="$ROOT/state" AGENT_CONFIG_DIRS="$ROOT/config" AGENT_HOST=test \
    AGENT_STATE_VALIDATOR="$ROOT/bin/counting-validator" \
    bash "$(dirname "$0")/state-sync.sh" sync >/dev/null 2>&1; then
  echo 'state-sync.test: changed invalid memory unexpectedly synchronized' >&2
  exit 1
fi
test "$(wc -l < "$ROOT/alerts")" -eq 2
test "$(wc -l < "$ROOT/validations")" -eq 2

rm "$ROOT/state/projects/demo/memory/invalid.md"
AGENT_STATE_DIR="$ROOT/state" AGENT_CONFIG_DIRS="$ROOT/config" AGENT_HOST=test \
  AGENT_STATE_VALIDATOR="$ROOT/bin/counting-validator" \
  bash "$(dirname "$0")/state-sync.sh" sync >/dev/null
test "$(wc -l < "$ROOT/alerts")" -eq 3
test "$(wc -l < "$ROOT/validations")" -eq 3
printf 'state-sync.test: PASS\n'
