#!/usr/bin/env bash
set -euo pipefail

STATE=${AGENT_STATE_DIR:-$HOME/800_agents/state}
SCHEMA="$STATE/.harness-schema.json"
failures=0

fail() {
  printf 'agent-state-validate: FAIL %s\n' "$*" >&2
  failures=$((failures + 1))
}

validate_memory_file() {
  local file=$1 display=$2 frontmatter
  # Top-level keys, plus the direct children of `metadata:`. Claude Code's memory
  # writer rewrites a newly written memory with every non-standard key moved
  # under metadata:. Measured 2026-09-25: two memories written with top-level
  # authority/source came back nested, failed this check, and blocked the
  # store sync. The writer's form counts as a declaration.
  frontmatter=$(awk '
    NR == 1 && $0 != "---" { exit }
    NR > 1 && $0 == "---" { exit }
    NR > 1 && /^[^ ]/ { in_meta = /^metadata:[ ]*$/; print; next }
    NR > 1 && in_meta && /^  [^ ]/ { print substr($0, 3) }
  ' "$file")
  if ! printf '%s\n' "$frontmatter" | rg -q '^authority: (observation|reference|decision)$'; then
    fail "$display must declare authority: observation|reference|decision (top level or under metadata:)"
  fi
  if ! printf '%s\n' "$frontmatter" | rg -q '^source: .+'; then
    fail "$display must declare a non-empty source (top level or under metadata:)"
  fi
  if printf '%s\n' "$frontmatter" | rg -q '^standing:'; then
    fail "$display declares standing policy; move the rule to static or project policy"
  fi
}

if [ "${1:-}" = memory-stdin ]; then
  tmp=$(mktemp)
  trap 'rm -f "$tmp"' EXIT
  cat > "$tmp"
  validate_memory_file "$tmp" "${2:-memory input}"
  if [ "$failures" -ne 0 ]; then
    printf 'agent-state-validate: %d failure(s)\n' "$failures" >&2
    exit 1
  fi
  printf 'agent-state-validate: PASS\n'
  exit 0
fi

# The state hub's pre-receive hook. A hand push (e6d3151, 2026-10-12) landed
# memories this validator rejects and blocked every host, because only
# state-sync validated before pushing. Each pushed tip is checked out into a
# throwaway repo that borrows the hub's objects and the push quarantine, then
# validated by re-running THIS script on it. Re-run the script, not the
# agent-state-validate wrapper: the wrapper pins AGENT_STATE_DIR to the host's
# own clone and would validate that instead (S0 spike). Any error rejects.
if [ "${1:-}" = pre-receive ]; then
  hub=$(cd "${GIT_DIR:-.}" && pwd)
  quarantine=${GIT_QUARANTINE_PATH:-}
  status=0
  while read -r _old new ref; do
    if [ "$ref" != refs/heads/main ]; then
      printf 'agent-state-validate: REJECT %s: the state hub accepts only refs/heads/main\n' "$ref" >&2
      status=1
      continue
    fi
    if [ -z "${new//0/}" ]; then
      printf 'agent-state-validate: REJECT deleting refs/heads/main\n' >&2
      status=1
      continue
    fi
    tree=$(mktemp -d)
    # errexit does not apply inside an if condition, so every step is chained.
    if ! (
      for name in $(compgen -e); do
        if [[ $name == GIT_* ]]; then unset "$name"; fi
      done
      git -c init.defaultBranch=main init -q "$tree" \
        && { printf '%s\n' "$hub/objects"; [ -z "$quarantine" ] || printf '%s\n' "$quarantine"; } \
             > "$tree/.git/objects/info/alternates" \
        && git -C "$tree" -c advice.detachedHead=false checkout -q --detach "$new" \
        && AGENT_STATE_DIR="$tree" bash "${BASH_SOURCE[0]}"
    ); then
      printf 'agent-state-validate: REJECT %s: %s failed validation or could not be checked\n' "$ref" "$new" >&2
      status=1
    fi
    rm -rf "$tree"
  done
  exit "$status"
fi

[ "$#" -eq 0 ] || {
  printf 'usage: agent-state-validate [memory-stdin [display-name] | pre-receive]\n' >&2
  exit 2
}

[ -d "$STATE/.git" ] || { printf 'agent-state-validate: missing git clone at %s\n' "$STATE" >&2; exit 1; }
[ -r "$SCHEMA" ] || { printf 'agent-state-validate: missing %s\n' "$SCHEMA" >&2; exit 1; }

schema_version=$(jq -r '.schemaVersion // empty' "$SCHEMA")
base_commit=$(jq -r '.memoryContractBase // empty' "$SCHEMA")
[ "$schema_version" = 1 ] || fail 'unsupported or missing schemaVersion'
if [ -z "$base_commit" ] || ! git -C "$STATE" cat-file -e "$base_commit^{commit}" 2>/dev/null; then
  fail 'memoryContractBase is missing or is not a commit in this clone'
fi

while IFS= read -r path; do
  [ -n "$path" ] || continue
  case "$path" in
    .gitattributes|.gitignore|.harness-schema.json|.mistakes-dismissed.log|MISTAKES.md|projects/*/memory/*) ;;
    ledger/*.json|guard/*.json) ;;
    *) fail "tracked path is outside the mutable-state contract: $path" ;;
  esac
done < <(git -C "$STATE" ls-files)

if find "$STATE/projects" -type f -name '*.from-*.md' -print -quit | rg -q .; then
  fail 'unreconciled *.from-<host>.md memory conflict exists'
fi

changed=$(
  {
    if [ -n "$base_commit" ] && git -C "$STATE" cat-file -e "$base_commit^{commit}" 2>/dev/null; then
      git -C "$STATE" diff --name-only "$base_commit"..HEAD -- 'projects/*/memory/*.md'
    fi
    git -C "$STATE" diff --name-only HEAD -- 'projects/*/memory/*.md'
    git -C "$STATE" diff --cached --name-only -- 'projects/*/memory/*.md'
    git -C "$STATE" ls-files --others --exclude-standard -- 'projects/*/memory/*.md'
  } | sort -u
)

while IFS= read -r path; do
  [ -n "$path" ] || continue
  [ "${path##*/}" != MEMORY.md ] || continue
  file="$STATE/$path"
  [ -f "$file" ] || continue
  validate_memory_file "$file" "$path"
done <<< "$changed"

if [ "$failures" -ne 0 ]; then
  printf 'agent-state-validate: %d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'agent-state-validate: PASS\n'
