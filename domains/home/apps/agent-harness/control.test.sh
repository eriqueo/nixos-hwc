#!/usr/bin/env bash
set -euo pipefail

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
STORE="$ROOT/store"
BIN="$ROOT/bin"
mkdir -p "$STORE" "$BIN"

cat > "$ROOT/expected.json" <<'EOF'
{"schemaVersion":1,"staticPolicy":{"revision":"rev1"}}
EOF
cp "$ROOT/expected.json" "$ROOT/system.json"

for file in system-policy claude-instructions codex-hooks codex-skill pi-instructions claude-settings; do
  printf 'pinned\n' > "$STORE/$file"
done

for command in claude codex pi herdr agent-state-validate; do
  cat > "$BIN/$command" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$BIN/$command"
done
cat > "$BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$BIN/systemctl"
cat > "$BIN/t3-dx2-handoff" <<'EOF'
#!/usr/bin/env bash
DELEGATE=/etc/agent-harness/skills/delegate/scripts/delegate.py
EOF
chmod +x "$BIN/t3-dx2-handoff"

run_doctor() {
  PATH="$BIN:$PATH" \
  AGENT_HARNESS_EXPECTED_MANIFEST="$ROOT/expected.json" \
  AGENT_HARNESS_SYSTEM_MANIFEST="$ROOT/system.json" \
  AGENT_HARNESS_STORE_PREFIX="$STORE" \
  AGENT_HARNESS_SYSTEM_POLICY="$STORE/system-policy" \
  AGENT_HARNESS_CLAUDE_INSTRUCTIONS="$STORE/claude-instructions" \
  AGENT_HARNESS_CODEX_HOOKS="$STORE/codex-hooks" \
  AGENT_HARNESS_CODEX_SKILL="$STORE/codex-skill" \
  AGENT_HARNESS_PI_INSTRUCTIONS="$STORE/pi-instructions" \
  AGENT_HARNESS_CLAUDE_SETTINGS="$STORE/claude-settings" \
  AGENT_HARNESS_SOURCE="$ROOT/source" \
  bash "$(dirname "$0")/control.sh" doctor
}

run_doctor >/dev/null

cat > "$ROOT/system.json" <<'EOF'
{"schemaVersion":1,"staticPolicy":{"revision":"rev2"}}
EOF
if run_doctor >/dev/null 2>&1; then
  echo 'control.test: split system/user revision unexpectedly passed' >&2
  exit 1
fi

cp "$ROOT/expected.json" "$ROOT/system.json"
printf '%s\n' "$ROOT/source/hooks/example.sh" > "$STORE/codex-hooks"
if run_doctor >/dev/null 2>&1; then
  echo 'control.test: mutable runtime reference unexpectedly passed' >&2
  exit 1
fi

SOURCE_REPO="$ROOT/publish-source"
SOURCE_REMOTE="$ROOT/publish-source.git"
NIXOS_REPO="$ROOT/publish-nixos"
NIXOS_REMOTE="$ROOT/publish-nixos.git"
git init -q --bare "$SOURCE_REMOTE"
git init -q --bare "$NIXOS_REMOTE"
git init -q -b main "$SOURCE_REPO"
git init -q -b main "$NIXOS_REPO"
git -C "$SOURCE_REPO" config user.name test
git -C "$SOURCE_REPO" config user.email test@example.invalid
git -C "$NIXOS_REPO" config user.name test
git -C "$NIXOS_REPO" config user.email test@example.invalid
mkdir -p "$SOURCE_REPO/bin"
cat > "$SOURCE_REPO/bin/harness-policy-check" <<'EOF'
#!/usr/bin/env bash
[ "$PWD" = "$(git rev-parse --show-toplevel)" ]
exit 0
EOF
chmod +x "$SOURCE_REPO/bin/harness-policy-check"
printf 'static\n' > "$SOURCE_REPO/policy"
git -C "$SOURCE_REPO" add .
git -C "$SOURCE_REPO" commit -q -m static
STATIC_REVISION=$(git -C "$SOURCE_REPO" rev-parse HEAD)
git -C "$SOURCE_REPO" remote add github "$SOURCE_REMOTE"
git -C "$SOURCE_REPO" push -q -u github main

cat > "$NIXOS_REPO/flake.lock" <<EOF
{"nodes":{"agent-harness":{"locked":{"rev":"$STATIC_REVISION"}}}}
EOF
git -C "$NIXOS_REPO" add flake.lock
git -C "$NIXOS_REPO" commit -q -m nixos
git -C "$NIXOS_REPO" remote add origin "$NIXOS_REMOTE"
git -C "$NIXOS_REPO" push -q -u origin main

run_publish_check() {
  AGENT_HARNESS_EXPECTED_MANIFEST="$ROOT/expected.json" \
  AGENT_HARNESS_SOURCE="$SOURCE_REPO" \
  AGENT_HARNESS_NIXOS="$NIXOS_REPO" \
  bash "$(dirname "$0")/control.sh" publish --check
}

run_publish_check >/dev/null
printf 'dirty\n' >> "$SOURCE_REPO/policy"
if run_publish_check >/dev/null 2>&1; then
  echo 'control.test: dirty static source unexpectedly passed publication preflight' >&2
  exit 1
fi

printf 'control.test: PASS\n'
