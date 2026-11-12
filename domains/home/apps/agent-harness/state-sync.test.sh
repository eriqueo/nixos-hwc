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

# A link from an older layout, for a project the store does not have yet, is
# imported and relinked; the old copy is kept.
mkdir -p "$ROOT/retired/projects/older/memory" "$ROOT/config/projects/older"
printf -- '---\nname: older\ndescription: d\nmetadata:\n  type: project\n---\nold\n' > "$ROOT/retired/projects/older/memory/older.md"
ln -s "$ROOT/retired/projects/older/memory" "$ROOT/config/projects/older/memory"
AGENT_STATE_DIR="$ROOT/state" AGENT_CONFIG_DIRS="$ROOT/config" AGENT_HOST=test \
  bash "$(dirname "$0")/state-sync.sh" link
test "$(readlink "$ROOT/config/projects/older/memory")" = "$ROOT/state/projects/older/memory"
rg -q '^old$' "$ROOT/state/projects/older/memory/older.md"
test -f "$ROOT/retired/projects/older/memory/older.md"
rm -r "$ROOT/state/projects/older" "$ROOT/config/projects/older" "$ROOT/retired/projects/older"

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
# Blocked state is committed locally but never published.
if git -C "$ROOT/hub.git" cat-file -e main:projects/demo/memory/invalid.md 2>/dev/null; then
  echo 'state-sync.test: blocked invalid memory reached the hub' >&2
  exit 1
fi
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
if git -C "$ROOT/hub.git" cat-file -e main:projects/demo/memory/invalid.md 2>/dev/null; then
  echo 'state-sync.test: deleted invalid memory is on the hub' >&2
  exit 1
fi

# A file an agent drops beside a project's memory is outside the contract. On
# 2026-11-09 two closeout records were staged with `git add projects`, failed
# validation and blocked hwc-work's sync for two days. Such a file stays local
# and untracked, and the sync still publishes.
printf '{}\n' > "$ROOT/state/projects/demo/closeout.json"
printf '\nentry\n' >> "$ROOT/state/MISTAKES.md"
AGENT_STATE_DIR="$ROOT/state" AGENT_CONFIG_DIRS="$ROOT/config" AGENT_HOST=test \
  bash "$(dirname "$0")/state-sync.sh" sync >/dev/null
if git -C "$ROOT/state" ls-files --error-unmatch projects/demo/closeout.json >/dev/null 2>&1; then
  echo 'state-sync.test: a file outside the contract was staged' >&2
  exit 1
fi
test -z "$(git -C "$ROOT/state" log --oneline origin/main..HEAD)"
git -C "$ROOT/hub.git" show main:MISTAKES.md | rg -q '^entry$'
rm "$ROOT/state/projects/demo/closeout.json"

# The validator must not fail a valid memory. With `set -o pipefail`,
# `printf ... | rg -q` fails when rg exits at the first match while printf is
# still writing; frontmatter larger than a pipe buffer makes that certain.
{
  printf -- '---\nname: big\nauthority: observation\nsource: test fixture\nmetadata:\n'
  for i in $(seq 1 4000); do printf '  note%04d: %s\n' "$i" 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'; done
  printf -- '---\n\nbody\n'
} > "$ROOT/state/projects/demo/memory/big.md"
if ! AGENT_STATE_DIR="$ROOT/state" bash "$VALIDATOR" >/dev/null 2>"$ROOT/validator.err"; then
  echo "state-sync.test: a valid memory with long frontmatter failed validation: $(tail -2 "$ROOT/validator.err" | head -1)" >&2
  exit 1
fi
rm "$ROOT/state/projects/demo/memory/big.md"

# A directory the validator cannot read must not hide a memory conflict. Under
# pipefail, find's permission error made `find | rg -q` report "no conflict".
mkdir -p "$ROOT/state/projects/held/recovery"
chmod 000 "$ROOT/state/projects/held/recovery"
printf -- '---\nname: note\nauthority: observation\nsource: test fixture\n---\n\nconflict\n' \
  > "$ROOT/state/projects/demo/memory/note.from-peer.md"
if AGENT_STATE_DIR="$ROOT/state" bash "$VALIDATOR" >/dev/null 2>"$ROOT/validator.err"; then
  echo 'state-sync.test: an unreadable directory hid a memory conflict' >&2
  exit 1
fi
rg -q 'unreconciled' "$ROOT/validator.err" || {
  echo 'state-sync.test: the validator failed without naming the memory conflict' >&2
  exit 1
}
chmod 700 "$ROOT/state/projects/held/recovery"
rm -r "$ROOT/state/projects/held" "$ROOT/state/projects/demo/memory/note.from-peer.md"

# A host blocked by invalid state that arrived FROM the hub must receive the
# hub's fix. Before, a blocked host skipped the fetch and stayed blocked
# forever (2026-10-14). Both sides also append to MISTAKES.md, as they did then.
# This hub has no pre-receive gate on purpose: it models invalid state that
# predates the gate, or that a stricter validator newly rejects.
git clone "$ROOT/hub.git" "$ROOT/peer" >/dev/null 2>&1
git -C "$ROOT/peer" config user.name peer
git -C "$ROOT/peer" config user.email peer@example.invalid
printf -- '---\nname: hub\ndescription: from the hub\n---\n\nbody\n' \
  > "$ROOT/peer/projects/demo/memory/hub.md"
git -C "$ROOT/peer" add -A && git -C "$ROOT/peer" commit -qm 'unvalidated hand commit'
git -C "$ROOT/peer" push -q
printf 'local mistake\n' >> "$ROOT/state/MISTAKES.md"
if AGENT_STATE_DIR="$ROOT/state" AGENT_CONFIG_DIRS="$ROOT/config" AGENT_HOST=test \
    bash "$(dirname "$0")/state-sync.sh" sync >/dev/null 2>&1; then
  echo 'state-sync.test: invalid hub memory did not block' >&2
  exit 1
fi
test "$(jq -r .state "$ROOT/state/.git/.sync-case.json")" = blocked
printf -- '---\nname: hub\ndescription: from the hub\nauthority: observation\nsource: test fixture\n---\n\nbody\n' \
  > "$ROOT/peer/projects/demo/memory/hub.md"
printf 'peer mistake\n' >> "$ROOT/peer/MISTAKES.md"
git -C "$ROOT/peer" add -A && git -C "$ROOT/peer" commit -qm 'fix hub memory'
git -C "$ROOT/peer" push -q
AGENT_STATE_DIR="$ROOT/state" AGENT_CONFIG_DIRS="$ROOT/config" AGENT_HOST=test \
  bash "$(dirname "$0")/state-sync.sh" sync >/dev/null
test "$(jq -r .state "$ROOT/state/.git/.sync-case.json")" = resolved
git -C "$ROOT/hub.git" show main:MISTAKES.md | rg -q '^local mistake$'
git -C "$ROOT/hub.git" show main:MISTAKES.md | rg -q '^peer mistake$'

# The agent-workspace ledger and guard files are part of the contract: they
# validate, and a sync commits and pushes them to the hub.
mkdir -p "$ROOT/state/ledger" "$ROOT/state/guard"
printf '{"host":"test","projects":{},"schemaVersion":1}\n' > "$ROOT/state/ledger/test.json"
printf '{"armDate":"2026-10-14","replayAccepted":null}\n' > "$ROOT/state/guard/arm.json"
AGENT_STATE_DIR="$ROOT/state" AGENT_CONFIG_DIRS="$ROOT/config" AGENT_HOST=test \
  bash "$(dirname "$0")/state-sync.sh" sync >/dev/null
test -z "$(git -C "$ROOT/state" status --porcelain)"
git -C "$ROOT/hub.git" cat-file -e main:ledger/test.json
git -C "$ROOT/hub.git" cat-file -e main:guard/arm.json
# Atomic ledger/guard writers leave a temporary file visible before rename.
# Synchronization must publish final JSON files without capturing that file.
printf 'ledger write in progress\n' > "$ROOT/state/ledger/test.json.atomic"
printf 'guard write in progress\n' > "$ROOT/state/guard/arm.json.atomic"
AGENT_STATE_DIR="$ROOT/state" AGENT_CONFIG_DIRS="$ROOT/config" AGENT_HOST=test \
  bash "$(dirname "$0")/state-sync.sh" sync >/dev/null
for temporary in ledger/test.json.atomic guard/arm.json.atomic; do
  if git -C "$ROOT/hub.git" cat-file -e "main:$temporary" 2>/dev/null; then
    echo "state-sync.test: published atomic temporary file $temporary" >&2
    exit 1
  fi
done
AGENT_STATE_DIR="$ROOT/state" bash "$VALIDATOR" >/dev/null
rm "$ROOT/state/ledger/test.json.atomic" "$ROOT/state/guard/arm.json.atomic"
# Anything else stays outside the contract.
printf 'x\n' > "$ROOT/state/stray.txt"
git -C "$ROOT/state" add stray.txt
if AGENT_STATE_DIR="$ROOT/state" bash "$VALIDATOR" >/dev/null 2>&1; then
  echo 'state-sync.test: a path outside the contract validated' >&2
  exit 1
fi
git -C "$ROOT/state" rm -q --cached stray.txt
rm "$ROOT/state/stray.txt"

# Claude Code's memory writer moves authority/source under metadata:; that form
# declares them. Other nesting does not, and nested standing policy is rejected.
memory() { printf -- '---\nname: m\n%s\n---\n\nbody\n' "$1"; }
memory $'metadata:\n  node_type: memory\n  authority: decision\n  source: "Eric"' \
  | bash "$VALIDATOR" memory-stdin nested.md >/dev/null
for bad in $'meta:\n  authority: decision\n  source: x' \
           $'metadata:\n  deep:\n    authority: decision\n    source: x' \
           $'metadata:\n  authority: decision\n  source: x\n  standing: always'; do
  if memory "$bad" | bash "$VALIDATOR" memory-stdin bad.md >/dev/null 2>&1; then
    echo "state-sync.test: accepted invalid frontmatter: $bad" >&2
    exit 1
  fi
done
# The hub's pre-receive gate: a hand push of invalid state is refused at the hub,
# not only by state-sync (e6d3151 reached the hub by hand on 2026-10-12).
git clone --bare -q "$ROOT/hub.git" "$ROOT/gated.git"
git -C "$ROOT/gated.git" config receive.denyDeleteCurrent ignore
printf '#!/usr/bin/env bash\nexec bash %q pre-receive\n' "$VALIDATOR" > "$ROOT/gated.git/hooks/pre-receive"
chmod +x "$ROOT/gated.git/hooks/pre-receive"
git clone -q "$ROOT/gated.git" "$ROOT/hand"
git -C "$ROOT/hand" config user.name hand
git -C "$ROOT/hand" config user.email hand@example.invalid
gated_main() { git -C "$ROOT/gated.git" rev-parse main; }
refused() {  # refused <label> <push args...>: the push must fail and leave main unchanged
  local label=$1 before; shift
  before=$(gated_main)
  if git -C "$ROOT/hand" push "$@" > "$ROOT/push.log" 2>&1; then
    echo "state-sync.test: hub accepted $label" >&2
    exit 1
  fi
  test "$(gated_main)" = "$before"
}
printf -- '---\nname: ok\nauthority: observation\nsource: test fixture\n---\n\nbody\n' \
  > "$ROOT/hand/projects/demo/memory/ok.md"
git -C "$ROOT/hand" add -A && git -C "$ROOT/hand" commit -qm 'valid hand push'
git -C "$ROOT/hand" push -q origin main
test "$(gated_main)" = "$(git -C "$ROOT/hand" rev-parse HEAD)"

printf -- '---\nname: bad\n---\n\nbody\n' > "$ROOT/hand/projects/demo/memory/bad.md"
git -C "$ROOT/hand" add -A && git -C "$ROOT/hand" commit -qm 'invalid hand push'
refused 'an invalid memory' origin main
rg -q 'remote: agent-state-validate: FAIL projects/demo/memory/bad.md' "$ROOT/push.log"
git -C "$ROOT/hand" reset -q --hard origin/main

refused 'a ref other than main' origin HEAD:refs/heads/other
rg -q 'accepts only refs/heads/main' "$ROOT/push.log"
refused 'deleting main' origin :main
rg -q 'REJECT deleting refs/heads/main' "$ROOT/push.log"

git -C "$ROOT/hand" rm -q .harness-schema.json
git -C "$ROOT/hand" commit -qm 'drop the schema'
refused 'a tip it cannot check' origin main
rg -q 'failed validation or could not be checked' "$ROOT/push.log"
printf 'state-sync.test: PASS\n'
