#!/usr/bin/env bash
# config-sync.test.sh — fixture test for config-sync.sh against throwaway repos.
#
# Every fixture is built here by hand, never from a live ~/.claude or hub, so a
# pass cannot come from the script agreeing with its own earlier output.
#
# Run: bash config-sync.test.sh
# Exit: 0 all pass · 1 a case failed
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC="$HERE/config-sync.sh"
[ -f "$SYNC" ] || { echo "FATAL: $SYNC not found"; exit 1; }

W=$(mktemp -d /tmp/config-sync-test.XXXXXX)
trap 'rm -rf "$W"' EXIT
PASS=0; FAIL=0
ok()   { printf '  ok    %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
q() { git -C "$1" "${@:2}" >/dev/null 2>&1; }

# Hub with the shared ignore/attribute rules and a CLAUDE.md carrying a block.
git init -q --bare "$W/hub.git"
git clone -q "$W/hub.git" "$W/seed" 2>/dev/null
q "$W/seed" checkout -B main
cat > "$W/seed/.gitignore" <<'EOF'
projects/*/*
!projects/*/memory/
projects/-tmp-*/
MISTAKES.md.lock
EOF
cat > "$W/seed/.gitattributes" <<'EOF'
MISTAKES.md merge=union
projects/*/memory/MEMORY.md merge=union
CLAUDE.md filter=standing-block
EOF
printf '# MISTAKES\n' > "$W/seed/MISTAKES.md"
printf 'rules\n<!-- BEGIN STANDING INSTRUCTIONS (generated) -->\n<!-- END STANDING INSTRUCTIONS -->\ntail\n' > "$W/seed/CLAUDE.md"
printf 'skill v1\n' > "$W/seed/skill.md"
q "$W/seed" add -A; q "$W/seed" commit -m seed; q "$W/seed" push origin main

host() { # <name>: clone + two config dirs
  git clone -q -b main "$W/hub.git" "$W/$1/repo" 2>/dev/null
  mkdir -p "$W/$1/claude/projects" "$W/$1/dx2/projects"
}
run() { # <host> <mode>
  CC_REPO="$W/$1/repo" CC_HOST="$1" CC_CONFIG_DIRS="$W/$1/claude:$W/$1/dx2" \
    bash "$SYNC" "$2" 2>"$W/$1.err" >"$W/$1.out"
}
host A; host B

echo "migration into the store"
M="$W/A/claude/projects/-home-eric-proj/memory"
mkdir -p "$M" "$W/A/claude/projects/-tmp-x/memory"
printf -- '- [one](one.md) — a\n' > "$M/MEMORY.md"
printf -- '---\nname: one\n---\nA body\n' > "$M/one.md"
printf 'tmp\n' > "$W/A/claude/projects/-tmp-x/memory/t.md"
run A sync; rcA=$?
S="$W/A/repo/projects/-home-eric-proj/memory"
check "sync exits 0"                                "[ $rcA = 0 ]"
check "memory file captured in store"              "cmp -s <(printf -- '---\nname: one\n---\nA body\n') '$S/one.md'"
check "real dir replaced by link to store"         "[ -L '$M' ] && [ \"\$(readlink '$M')\" = '$S' ]"
check "second config dir linked to store"          "[ -L '$W/A/dx2/projects/-home-eric-proj/memory' ]"
check "backup removed once fully captured"         "! compgen -G '$M.pre-sync-*' >/dev/null"
check "-tmp- slug left host-local"                 "[ ! -L '$W/A/claude/projects/-tmp-x/memory' ] && [ ! -e '$W/A/repo/projects/-tmp-x' ]"
check "store change pushed to hub"                 "git -C '$W/hub.git' show main:projects/-home-eric-proj/memory/one.md >/dev/null 2>&1"

echo "same-named memory on both hosts"
MB="$W/B/claude/projects/-home-eric-proj/memory"
mkdir -p "$MB"
printf -- '- [two](two.md) — b\n' > "$MB/MEMORY.md"
printf -- '---\nname: one\n---\nB body\n' > "$MB/one.md"
printf '# MISTAKES\n- B entry\n' > "$W/B/repo/MISTAKES.md"
run B sync; rcB=$?
SB="$W/B/repo/projects/-home-eric-proj/memory"
check "B sync exits 0"                             "[ $rcB = 0 ]"
check "hub version of one.md kept"                 "rg -q 'A body' '$SB/one.md'"
check "B version kept beside it"                   "rg -q 'B body' '$SB/one.from-B.md'"
check "MEMORY.md holds both index lines"           "rg -q 'one.md' '$SB/MEMORY.md' && rg -q 'two.md' '$SB/MEMORY.md'"
check "B link points at store"                     "[ -L '$MB' ]"
printf '# MISTAKES\n- A entry\n' > "$W/A/repo/MISTAKES.md"
run A sync
check "A receives B's copy"                        "[ -e '$S/one.from-B.md' ]"
check "MISTAKES.md unions both entries"            "rg -q 'A entry' '$W/A/repo/MISTAKES.md' && rg -q 'B entry' '$W/A/repo/MISTAKES.md'"

echo "hand edits and derived blocks"
printf 'rules\n<!-- BEGIN STANDING INSTRUCTIONS (generated) -->\nGENERATED TEXT\n<!-- END STANDING INSTRUCTIONS -->\ntail\n' > "$W/A/repo/CLAUDE.md"
run A sync; rc=$?
check "generated block alone: sync exits 0"        "[ $rc = 0 ]"
check "generated block alone leaves tree clean"    "[ -z \"\$(git -C '$W/A/repo' status --porcelain -- CLAUDE.md)\" ]"
check "generated text never committed"             "! git -C '$W/A/repo' log -p --all | rg -q 'GENERATED TEXT'"
q "$W/B/repo" pull --no-edit
printf 'rules\n<!-- BEGIN STANDING INSTRUCTIONS (generated) -->\n<!-- END STANDING INSTRUCTIONS -->\ntail edited on B\n' > "$W/B/repo/CLAUDE.md"
q "$W/B/repo" commit -am "hand edit CLAUDE.md"; q "$W/B/repo" push origin main
run A sync; rc=$?
check "upstream CLAUDE.md edit merges past a regenerated block" "[ $rc = 0 ] && rg -q 'tail edited on B' '$W/A/repo/CLAUDE.md'"
printf 'skill v2 from B\n' > "$W/B/repo/skill.md"; q "$W/B/repo" commit -am "skill v2"; q "$W/B/repo" push origin main
printf 'skill local draft\n' > "$W/A/repo/skill.md"
run A sync; rc=$?
check "overlapping dirty edit fails the unit"      "[ $rc = 1 ]"
check "failure names the blocking file"            "rg -q 'skill.md' '$W/A.err'"
check "hand edit untouched"                        "rg -q 'local draft' '$W/A/repo/skill.md'"
check "hand edit never auto-committed"             "! git -C '$W/A/repo' log -p --all | rg -q 'local draft'"

echo
echo "pass=$PASS fail=$FAIL"
[ "$FAIL" = 0 ]
