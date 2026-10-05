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

for file in system-policy claude-instructions codex-hooks pi-instructions claude-settings pi-hook-bridge; do
  printf 'pinned\n' > "$STORE/$file"
done

# One skill set, linked from two roots; Codex's root holds only .system.
SKILLS="$STORE/agent-skills"
HOME_T="$ROOT/home"
mkdir -p "$SKILLS/premortem" "$HOME_T/.claude" "$HOME_T/.agents" "$HOME_T/.codex/skills/.system" "$HOME_T/.pi/agent"
printf -- '---\nname: premortem\n---\n' > "$SKILLS/premortem/SKILL.md"
ln -s "$SKILLS" "$HOME_T/.claude/skills"
ln -s "$SKILLS" "$HOME_T/.agents/skills"
printf '{"skills":["%s/.claude/skills"]}\n' "$HOME_T" > "$HOME_T/.pi/agent/settings.json"

for command in claude codex pi herdr agent-state-validate codex-hooks-trust; do
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
  AGENT_HARNESS_PI_INSTRUCTIONS="$STORE/pi-instructions" \
  AGENT_HARNESS_PI_SETTINGS="$HOME_T/.pi/agent/settings.json" \
  AGENT_HARNESS_PI_HOOK_BRIDGE="$STORE/pi-hook-bridge" \
  AGENT_HARNESS_PI_BRIDGE_FAILURES="$ROOT/pi-bridge-failures.log" \
  AGENT_HARNESS_CLAUDE_SETTINGS="$STORE/claude-settings" \
  AGENT_HARNESS_SKILL_SET="$SKILLS" \
  AGENT_HARNESS_SKILL_ROOTS="$HOME_T/.claude/skills:$HOME_T/.agents/skills" \
  AGENT_HARNESS_CODEX_SKILLS="$HOME_T/.codex/skills" \
  AGENT_HARNESS_SOURCE="$ROOT/source" \
  AGENT_HARNESS_FLEET_HOSTS=hwc-server:hwc-laptop:hwc-work \
  bash "$(dirname "$0")/control.sh" "${1:-doctor}"
}

run_doctor >/dev/null

# Skill identity is independent of the caller's collation locale. Seed names
# whose order differs under C and English collation.
printf 'one\n' > "$SKILLS/Z-file"
printf 'two\n' > "$SKILLS/a_file"
fingerprint_c=$(LC_ALL=C run_doctor | awk '/^skill fingerprint:/ {print $3}')
fingerprint_en=$(LC_ALL=en_US.UTF-8 run_doctor | awk '/^skill fingerprint:/ {print $3}')
[ "$fingerprint_c" = "$fingerprint_en" ] || {
  echo 'control.test: skill fingerprint depends on locale' >&2
  exit 1
}

# Drift: a hand-installed Codex skill, a root that is not the set, and a Pi
# path outside it must each fail the doctor.
mkdir "$HOME_T/.codex/skills/hand-copy"
if run_doctor >/dev/null 2>&1; then
  echo 'control.test: hand-installed Codex skill unexpectedly passed' >&2
  exit 1
fi
rmdir "$HOME_T/.codex/skills/hand-copy"
rm "$HOME_T/.agents/skills"; mkdir "$HOME_T/.agents/skills"
if run_doctor >/dev/null 2>&1; then
  echo 'control.test: skill root outside the set unexpectedly passed' >&2
  exit 1
fi
rmdir "$HOME_T/.agents/skills"; ln -s "$SKILLS" "$HOME_T/.agents/skills"
printf '{"skills":["%s/.claude/skills","/tmp"]}\n' "$HOME_T" > "$HOME_T/.pi/agent/settings.json"
if run_doctor >/dev/null 2>&1; then
  echo 'control.test: extra Pi skill path unexpectedly passed' >&2
  exit 1
fi
printf '{"skills":["%s/.claude/skills"]}\n' "$HOME_T" > "$HOME_T/.pi/agent/settings.json"
run_doctor >/dev/null

# A Pi bridge failure in the last hour fails the doctor; an older one does not.
printf '2000-01-01T00:00:00.000Z\tPreToolUse\told\n' > "$ROOT/pi-bridge-failures.log"
run_doctor >/dev/null
printf '%s\tPreToolUse\tspawn ENOENT\n' "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" >> "$ROOT/pi-bridge-failures.log"
if run_doctor >/dev/null 2>&1; then
  echo 'control.test: recent Pi bridge failure unexpectedly passed' >&2
  exit 1
fi
rm "$ROOT/pi-bridge-failures.log"

# drift records a case only after its alert; with no notify URL it stays
# unrecorded, so the alert retries on the next run.
mkdir "$HOME_T/.codex/skills/hand-copy"
if XDG_STATE_HOME="$ROOT/xdg" run_doctor drift >/dev/null 2>&1; then
  echo 'control.test: drift unexpectedly passed with a hand install' >&2
  exit 1
fi
[ ! -e "$ROOT/xdg/agent-harness/drift" ] || {
  echo 'control.test: drift recorded a case whose alert was not sent' >&2
  exit 1
}
rmdir "$HOME_T/.codex/skills/hand-copy"

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
SOURCE_MIRROR="$ROOT/publish-mirror.git"
NIXOS_REPO="$ROOT/publish-nixos"
NIXOS_REMOTE="$ROOT/publish-nixos.git"
git init -q --bare "$SOURCE_REMOTE"
git init -q --bare "$SOURCE_MIRROR"
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
git -C "$SOURCE_REPO" remote add origin "$SOURCE_MIRROR"
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
  AGENT_HARNESS_FLEET_HOSTS=hwc-server:hwc-laptop:hwc-work \
  bash "$(dirname "$0")/control.sh" publish --check
}

run_publish_check >/dev/null

cat > "$BIN/nix" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HARNESS_TEST_ROOT/nix.log"
EOF
cat > "$BIN/ssh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HARNESS_TEST_ROOT/ssh.log"
case "$*" in *'agent-harness revision'*) printf 'rev1\nok\n' ;; esac
EOF
cat > "$BIN/hostname" <<'EOF'
#!/usr/bin/env bash
printf 'harness-test-host\n'
EOF
# The installed CLI after the switch; publish must hand the final doctor to it.
cat > "$BIN/agent-harness" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HARNESS_TEST_ROOT/installed-cli.log"
EOF
chmod +x "$BIN/nix" "$BIN/ssh" "$BIN/hostname" "$BIN/agent-harness"
HARNESS_TEST_ROOT="$ROOT" PATH="$BIN:$PATH" \
  AGENT_HARNESS_EXPECTED_MANIFEST="$ROOT/expected.json" \
  AGENT_HARNESS_SOURCE="$SOURCE_REPO" \
  AGENT_HARNESS_NIXOS="$NIXOS_REPO" \
  AGENT_HARNESS_FLEET_HOSTS=hwc-server:hwc-laptop:hwc-work \
  bash "$(dirname "$0")/control.sh" publish >/dev/null
[ "$(cat "$ROOT/installed-cli.log" 2>/dev/null)" = 'doctor --fleet' ] || {
  echo 'control.test: publish did not run the fleet doctor from the installed CLI' >&2
  exit 1
}
[ "$(git -C "$SOURCE_MIRROR" rev-parse refs/heads/main)" = "$STATIC_REVISION" ] || {
  echo 'control.test: static mirror did not receive the published revision' >&2
  exit 1
}
for host in hwc-server hwc-laptop hwc-work; do
  rg -q "nixosConfigurations\\.$host\\.config\\.system\\.build\\.toplevel" "$ROOT/nix.log" || {
    echo "control.test: $host was not built" >&2; exit 1;
  }
  # A remote host builds in its own store.
  rg -q -- "--store ssh-ng://$host .*nixosConfigurations\\.$host\\." "$ROOT/nix.log" || {
    echo "control.test: $host was not built in its own store" >&2; exit 1;
  }
  rg -q "$host .*git -C ~/.claude-config pull --ff-only" "$ROOT/ssh.log" || {
    echo "control.test: $host did not refresh its static authoring source" >&2; exit 1;
  }
done

if AGENT_HARNESS_FLEET_HOSTS='hwc-server:bad host' \
  AGENT_HARNESS_EXPECTED_MANIFEST="$ROOT/expected.json" \
  AGENT_HARNESS_SOURCE="$SOURCE_REPO" \
  AGENT_HARNESS_NIXOS="$NIXOS_REPO" \
  bash "$(dirname "$0")/control.sh" publish --check >/dev/null 2>&1; then
  echo 'control.test: invalid fleet unexpectedly passed publication preflight' >&2
  exit 1
fi
printf 'dirty\n' >> "$SOURCE_REPO/policy"
if run_publish_check >/dev/null 2>&1; then
  echo 'control.test: dirty static source unexpectedly passed publication preflight' >&2
  exit 1
fi

printf 'control.test: PASS\n'
