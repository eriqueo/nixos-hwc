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

# The manifest's matrix and outside-skill lists, as Nix renders them.
cat > "$ROOT/matrix.json" <<'EOF'
{"matrix":{"rules":{"claude":"provided","codex":"missing","pi":"provided"},
           "skills":{"claude":"provided","codex":"provided","pi":"provided"},
           "guards":{"claude":"unsupported","codex":"missing","pi":"provided"}},
 "outside":{"codex":{"system":["listed"]}}}
EOF
mkdir "$HOME_T/.codex/skills/.system/listed"

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
  AGENT_HARNESS_MATRIX="${MATRIX_FILE:-$ROOT/matrix.json}" \
  AGENT_HARNESS_CLAUDE_HOME="$HOME_T/.claude" \
  AGENT_HARNESS_CLAUDE_MCP="$HOME_T/.mcp.json" \
  AGENT_HARNESS_CODEX_INSTRUCTIONS="$HOME_T/.codex/AGENTS.md" \
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

# The matrix: provided cells are probed; a cell with no probe, a failing probe,
# or an undeclared program fails. Missing and unsupported cells pass as declared.
run_doctor matrix >/dev/null
for seed in '.matrix.subagents.codex = "provided"' '.matrix.memory = {"codex":"provided"}' '.matrix.commands = {"codex":"provided"}' '.matrix.mcp = {"codex":"provided"}' '.matrix.rules.codex = "provided"' '.matrix.skills.extra = "maybe"'; do
  jq "$seed" "$ROOT/matrix.json" > "$ROOT/matrix-seed.json"
  if MATRIX_FILE="$ROOT/matrix-seed.json" run_doctor >/dev/null 2>&1; then
    echo "control.test: matrix seed unexpectedly passed: $seed" >&2
    exit 1
  fi
done
rm "$ROOT/matrix-seed.json"

# A skill a program loads from outside the harness must be listed.
mkdir "$HOME_T/.codex/skills/.system/unlisted"
if run_doctor >/dev/null 2>&1; then
  echo 'control.test: unlisted Codex system skill unexpectedly passed' >&2
  exit 1
fi
rmdir "$HOME_T/.codex/skills/.system/unlisted"
mkdir -p "$HOME_T/.claude/plugins/synced/bucket/synced-plugin" "$HOME_T/.claude/plugins/synced/bucket/synced-plugin~g2"
if run_doctor >/dev/null 2>&1; then
  echo 'control.test: unlisted claude.ai synced plugin unexpectedly passed' >&2
  exit 1
fi
rm -r "$HOME_T/.claude/plugins"
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
git init -q --bare -b main "$SOURCE_REMOTE"
git init -q --bare -b main "$SOURCE_MIRROR"
git init -q --bare -b main "$NIXOS_REMOTE"
git init -q -b main "$SOURCE_REPO"
git init -q -b main "$NIXOS_REPO"
git -C "$SOURCE_REPO" config user.name test
git -C "$SOURCE_REPO" config user.email test@example.invalid
git -C "$NIXOS_REPO" config user.name test
git -C "$NIXOS_REPO" config user.email test@example.invalid
mkdir -p "$SOURCE_REPO/checks"
cat > "$SOURCE_REPO/checks/harness-policy-check" <<'EOF'
#!/usr/bin/env bash
[ "$PWD" = "$(git rev-parse --show-toplevel)" ]
exit 0
EOF
chmod +x "$SOURCE_REPO/checks/harness-policy-check"
mkdir -p "$SOURCE_REPO/guards/tests"
cat > "$SOURCE_REPO/guards/tests/run.sh" <<'EOF'
#!/usr/bin/env bash
[ "$1" = --live ] || exit 1
# Lets a test land another session's push while the suites run.
[ -z "${HARNESS_RACE:-}" ] || bash "$HARNESS_RACE"
EOF
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

cat > "$BIN/nix" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HARNESS_TEST_ROOT/nix.log"
# Pin what the static source holds, as the real `nix flake update` would.
[ "$*" != 'flake update agent-harness' ] || printf '{"nodes":{"agent-harness":{"locked":{"rev":"%s"}}}}\n' \
  "$(git -C "$AGENT_HARNESS_SOURCE" rev-parse HEAD)" > flake.lock
EOF
# Remote hosts report rev1; a host named in HARNESS_OFFLINE is unreachable.
cat > "$BIN/ssh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HARNESS_TEST_ROOT/ssh.log"
for arg in "$@"; do case " ${HARNESS_OFFLINE:-} " in *" $arg "*) exit 255 ;; esac; done
case "$*" in *'agent-harness revision'*) printf 'rev1\n' ;; esac
EOF
cat > "$BIN/hostname" <<'EOF'
#!/usr/bin/env bash
printf 'hwc-test\n'
EOF
# The installed CLI after the switch; publish must hand the final doctor to it.
cat > "$BIN/agent-harness" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HARNESS_TEST_ROOT/installed-cli.log"
EOF
# The release runner, as publish calls it: verify records the candidate and
# origin main at that moment (HARNESS_REFUSE makes it refuse); deploy
# fast-forwards main, as only the runner may.
cat > "$BIN/python3" <<'EOF'
#!/usr/bin/env bash
case "$1" in */workspace/nixos-dev/verification/release.py) ;; *) exit 99 ;; esac
shift
printf '%s\n' "$*" >> "$HARNESS_TEST_ROOT/release.log"
[ "$1" = --repo ] && repo=$2 && shift 2
case "$1" in
  verify) [ -z "${HARNESS_REFUSE:-}" ] || exit 1
          printf '%s %s\n' "$3" "$(git -C "$repo" ls-remote origin refs/heads/main | cut -f1)" >> "$HARNESS_TEST_ROOT/verified.log" ;;
  deploy) git -C "$repo" merge --ff-only --quiet "$3" ;;
esac
EOF
# Any activation outside the runner is a bypass.
for command in sudo nixos-rebuild home-manager; do
  printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" %s "$*" >> "$HARNESS_TEST_ROOT/bypass.log"\n' "$command" > "$BIN/$command"
done
chmod +x "$BIN"/{nix,ssh,hostname,agent-harness,python3,sudo,nixos-rebuild,home-manager}

FLEET=hwc-test:hwc-server:hwc-work
run_publish() {
  HARNESS_TEST_ROOT="$ROOT" PATH="$BIN:$PATH" \
  AGENT_HARNESS_EXPECTED_MANIFEST="$ROOT/expected.json" \
  AGENT_HARNESS_SOURCE="$SOURCE_REPO" \
  AGENT_HARNESS_NIXOS="$NIXOS_REPO" \
  AGENT_HARNESS_FLEET_HOSTS="$FLEET" \
  bash "$(dirname "$0")/control.sh" publish "$@"
}
run_publish_check() { run_publish --check; }
no_bypass() {
  [ ! -e "$ROOT/bypass.log" ] && [ -z "$(rg -v '^flake update agent-harness$' "$ROOT/nix.log" 2>/dev/null)" ] || {
    echo "control.test: publish activated or built outside the release runner ($1)" >&2; exit 1;
  }
}

run_publish_check >/dev/null

# A new harness commit: --plan changes nothing; a refused verification keeps
# the pin off main; publish pins it verify -> push -> runner deploy, here only.
printf 'new\n' > "$SOURCE_REPO/policy"; git -C "$SOURCE_REPO" commit -q -am new
STATIC_REVISION=$(git -C "$SOURCE_REPO" rev-parse HEAD)
heads() { git -C "$SOURCE_REMOTE" rev-parse main; git -C "$NIXOS_REMOTE" rev-parse main; git -C "$NIXOS_REPO" rev-parse main; }
BEFORE=$(heads)
PLAN=$(run_publish --plan 2>&1) || { echo 'control.test: publish --plan failed' >&2; exit 1; }
[ "$(heads)" = "$BEFORE" ] && [ ! -e "$ROOT/release.log" ] && [ ! -e "$ROOT/nix.log" ] \
  && printf '%s\n' "$PLAN" | rg -q 'hwc-work \(runs rev1\): not activated' \
  && printf '%s\n' "$PLAN" | rg -q 'hwc-test \(this host.*release.py deploy' || {
  echo 'control.test: publish --plan changed something or did not show each host' >&2; exit 1;
}
if HARNESS_REFUSE=1 run_publish >/dev/null 2>&1 || [ "$(git -C "$NIXOS_REMOTE" rev-parse main)" != "$(awk 'NR==2' <<< "$BEFORE")" ] \
    || [ "$(git -C "$NIXOS_REPO" rev-parse main)" != "$(awk 'NR==3' <<< "$BEFORE")" ]; then
  echo 'control.test: a pin the runner refused reached main' >&2; exit 1
fi
rm -rf "$NIXOS_REPO-worktrees"; git -C "$NIXOS_REPO" worktree prune
git -C "$NIXOS_REPO" for-each-ref --format='%(refname:short)' 'refs/heads/harness-publish/*' | xargs -r git -C "$NIXOS_REPO" branch -q -D
: > "$ROOT/release.log"
run_publish >/dev/null
PIN=$(git -C "$NIXOS_REMOTE" rev-parse main)
[ "$(git -C "$NIXOS_REMOTE" show "$PIN:flake.lock" | jq -r '.nodes."agent-harness".locked.rev')" = "$STATIC_REVISION" ] \
  && [ "$(git -C "$NIXOS_REPO" rev-parse main)" = "$PIN" ] \
  && [ "$(cat "$ROOT/release.log")" = "$(printf -- '--repo %s verify --candidate %s\n--repo %s deploy --candidate %s' "$NIXOS_REPO" "$PIN" "$NIXOS_REPO" "$PIN")" ] \
  && [ "$(awk 'END {print $2}' "$ROOT/verified.log")" != "$PIN" ] || {
  echo 'control.test: the pin did not go verify -> push -> runner deploy' >&2; exit 1;
}
no_bypass default
! rg -q 'release.py' "$ROOT/ssh.log" || { echo 'control.test: default publish activated a remote host' >&2; exit 1; }
[ "$(cat "$ROOT/installed-cli.log")" = doctor ] || {
  echo 'control.test: default publish did not run the local doctor from the installed CLI' >&2; exit 1;
}
[ "$(git -C "$SOURCE_MIRROR" rev-parse refs/heads/main)" = "$STATIC_REVISION" ] || {
  echo 'control.test: static mirror did not receive the published revision' >&2
  exit 1
}
# --fleet: each reachable remote runs its own runner; an unreachable one is reported.
: > "$ROOT/ssh.log"; : > "$ROOT/installed-cli.log"
if HARNESS_OFFLINE=hwc-server run_publish --fleet >/dev/null 2>"$ROOT/fleet.err"; then
  echo 'control.test: publish passed with an unreachable host' >&2; exit 1
fi
rg -q 'not switched: hwc-server \(unreachable\)' "$ROOT/fleet.err" \
  && rg -q '^-t hwc-work git -C ~/800_agents/harness pull --ff-only && .*release.py deploy --candidate origin/main$' "$ROOT/ssh.log" \
  && ! rg -q 'hwc-server .*release.py' "$ROOT/ssh.log" \
  && [ "$(cat "$ROOT/installed-cli.log")" = 'doctor --fleet' ] || {
  echo 'control.test: --fleet did not gate each host or report the unreachable one' >&2; exit 1;
}
no_bypass fleet

# Another session's pushes: one before publish starts, one during the suites.
OTHER="$ROOT/publish-other"
git clone -q "$SOURCE_REMOTE" "$OTHER"
git -C "$OTHER" config user.name other
git -C "$OTHER" config user.email other@example.invalid
printf 'one\n' > "$OTHER/other"; git -C "$OTHER" add other
git -C "$OTHER" commit -q -m one && git -C "$OTHER" push -q origin main
BEHIND_REVISION=$(git -C "$OTHER" rev-parse HEAD)
printf '{"nodes":{"agent-harness":{"locked":{"rev":"%s"}}}}\n' "$BEHIND_REVISION" > "$NIXOS_REPO/flake.lock"
git -C "$NIXOS_REPO" commit -q -am "pin $BEHIND_REVISION" && git -C "$NIXOS_REPO" push -q origin main
cat > "$ROOT/race.sh" <<EOF
printf 'two\n' >> "$OTHER/other"
git -C "$OTHER" commit -q -am two && git -C "$OTHER" push -q origin main
EOF
HARNESS_RACE="$ROOT/race.sh" run_publish >/dev/null 2>&1 || {
  echo 'control.test: publish failed when other sessions pushed the harness' >&2; exit 1;
}
[ "$(git -C "$SOURCE_REPO" rev-parse HEAD)" = "$BEHIND_REVISION" ] || {
  echo 'control.test: publish did not fast-forward a behind static source' >&2; exit 1;
}
[ "$(git -C "$SOURCE_MIRROR" rev-parse refs/heads/main)" = "$BEHIND_REVISION" ] || {
  echo 'control.test: mirror did not receive the checked revision' >&2; exit 1;
}
[ "$(git -C "$SOURCE_REMOTE" rev-parse refs/heads/main)" = "$(git -C "$OTHER" rev-parse HEAD)" ] || {
  echo 'control.test: publish rewound the newer github main' >&2; exit 1;
}

# A session's unpushed local commit while others push, before and during the suites.
printf 'local\n' > "$SOURCE_REPO/local"; git -C "$SOURCE_REPO" add local
git -C "$SOURCE_REPO" commit -q -m local
cat > "$ROOT/race.sh" <<EOF
[ -e "$ROOT/raced" ] && exit 0; : > "$ROOT/raced"
printf 'three\n' >> "$OTHER/other"
git -C "$OTHER" commit -q -am three && git -C "$OTHER" push -q origin main
EOF
HARNESS_RACE="$ROOT/race.sh" run_publish >/dev/null 2>&1 || {
  echo 'control.test: publish failed with an unpushed local commit beside other pushes' >&2; exit 1;
}
PUBLISHED=$(git -C "$SOURCE_REMOTE" rev-parse refs/heads/main)
[ "$PUBLISHED" = "$(git -C "$SOURCE_REPO" rev-parse HEAD)" ] \
  && [ "$(git -C "$SOURCE_REMOTE" show "$PUBLISHED:other")" = "$(printf 'one\ntwo\nthree')" ] \
  && git -C "$SOURCE_REMOTE" cat-file -e "$PUBLISHED:local" \
  && [ "$(jq -r '.nodes."agent-harness".locked.rev' "$NIXOS_REPO/flake.lock")" = "$PUBLISHED" ] || {
  echo 'control.test: diverged publish did not ship local work on top of every push' >&2; exit 1;
}
no_bypass races
# A real conflict stops and leaves the copy as it was.
printf 'mine\n' > "$SOURCE_REPO/other"; git -C "$SOURCE_REPO" commit -q -am mine
git -C "$OTHER" pull -q --rebase origin main
printf 'theirs\n' > "$OTHER/other"; git -C "$OTHER" commit -q -am theirs && git -C "$OTHER" push -q origin main
BEFORE=$(git -C "$SOURCE_REPO" rev-parse HEAD)
if run_publish_check >/dev/null 2>&1; then
  echo 'control.test: conflicting local commit unexpectedly passed preflight' >&2; exit 1
fi
[ "$(git -C "$SOURCE_REPO" rev-parse HEAD)" = "$BEFORE" ] && [ ! -e "$SOURCE_REPO/.git/rebase-merge" ] || {
  echo 'control.test: a conflicting rebase was not aborted cleanly' >&2; exit 1;
}
git -C "$SOURCE_REPO" reset -q --hard "$(git -C "$OTHER" rev-parse HEAD)"

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
