#!/usr/bin/env bash
# domains/automation/n8n/parts/workflow-export.sh
#
# Snapshot every n8n workflow into a local git-versioned directory.
#
# Read-only on the n8n side: GETs /api/v1/workflows (cursor-paginated), writes
# one pretty-printed JSON file per workflow (stable key order so git diffs are
# meaningful), prunes files for workflows that no longer exist, commits the
# change. Idempotent: a second run with no upstream change makes zero commits.
#
# Env (all optional except API key file):
#   N8N_EXPORT_DIR    target dir (default /var/lib/hwc/n8n/workflow-export)
#   N8N_API_URL       base URL (default http://localhost:5678)
#   N8N_API_KEY_FILE  file containing the X-N8N-API-KEY value
#                     (default /run/agenix/n8n-api-key)

set -euo pipefail

EXPORT_DIR="${N8N_EXPORT_DIR:-/var/lib/hwc/n8n/workflow-export}"
API_URL="${N8N_API_URL:-http://localhost:5678}"
API_KEY_FILE="${N8N_API_KEY_FILE:-/run/agenix/n8n-api-key}"

if [ ! -r "$API_KEY_FILE" ]; then
  echo "FATAL: cannot read API key file: $API_KEY_FILE" >&2
  exit 1
fi
API_KEY="$(cat "$API_KEY_FILE")"
if [ -z "$API_KEY" ]; then
  echo "FATAL: API key file is empty: $API_KEY_FILE" >&2
  exit 1
fi

mkdir -p "$EXPORT_DIR"
cd "$EXPORT_DIR"

# Git repo init on first run. Use a fixed identity so unattended commits
# succeed even when the runtime user has no global git config.
if [ ! -d .git ]; then
  git init -q -b main
fi
git config user.email "n8n-workflow-export@hwc.local"
git config user.name  "n8n workflow export"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ALL="$WORK/all.json"
echo '[]' >"$ALL"

# Cursor-paginated GET. n8n returns {"data":[...],"nextCursor":"..."|null}.
cursor=""
pages=0
while :; do
  pages=$((pages + 1))
  if [ -z "$cursor" ]; then
    url="$API_URL/api/v1/workflows?limit=100"
  else
    # cursor is opaque base64 — URL-encode just in case it ever contains +/=.
    enc="$(printf '%s' "$cursor" | jq -sRr @uri)"
    url="$API_URL/api/v1/workflows?limit=100&cursor=$enc"
  fi

  page="$WORK/page-$pages.json"
  if ! curl -fsS -m 30 -H "X-N8N-API-KEY: $API_KEY" -H 'accept: application/json' \
        "$url" -o "$page"; then
    echo "FATAL: GET $url failed" >&2
    exit 1
  fi

  jq -e '.data | type == "array"' "$page" >/dev/null \
    || { echo "FATAL: unexpected response shape on page $pages" >&2; exit 1; }

  # Merge page.data into the rolling array.
  jq -s '.[0] + .[1].data' "$ALL" "$page" >"$ALL.next"
  mv "$ALL.next" "$ALL"

  cursor="$(jq -r '.nextCursor // empty' "$page")"
  [ -z "$cursor" ] && break
  if [ "$pages" -ge 200 ]; then
    echo "FATAL: refusing to paginate past $pages pages (likely API loop)" >&2
    exit 1
  fi
done

count="$(jq 'length' "$ALL")"
echo "fetched $count workflows in $pages page(s)"

# Write one JSON file per workflow. Slug each name to kebab-ish ascii so the
# filename is stable + path-safe; id stays the unique prefix so renames in n8n
# don't produce orphans (the file just moves to a new name on next snapshot).
KEEP="$WORK/keep.txt"
: >"$KEEP"

jq -c '.[]' "$ALL" | while IFS= read -r wf; do
  id="$(printf '%s' "$wf" | jq -r '.id')"
  if [ -z "$id" ] || [ "$id" = "null" ]; then
    echo "WARN: skipping workflow with no id" >&2
    continue
  fi
  name="$(printf '%s' "$wf" | jq -r '.name // ""')"
  slug="$(printf '%s' "$name" \
            | tr '[:upper:]' '[:lower:]' \
            | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' \
            | cut -c1-80)"
  [ -n "$slug" ] || slug="unnamed"
  fname="${id}--${slug}.json"
  printf '%s\n' "$fname" >>"$KEEP"
  printf '%s' "$wf" | jq -S . >"$EXPORT_DIR/$fname"
done

# Prune files for workflows that vanished from n8n. Only touch *.json at the
# top level — never recurse, never touch dotfiles.
shopt -s nullglob
for f in "$EXPORT_DIR"/*.json; do
  base="$(basename "$f")"
  if ! grep -qxF "$base" "$KEEP"; then
    echo "pruning $base (no longer present in n8n)"
    rm -f -- "$f"
  fi
done
shopt -u nullglob

git add -A
if git diff --cached --quiet; then
  echo "no changes; nothing to commit"
  exit 0
fi

stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
git commit -q -m "n8n export $stamp: $count workflows"
echo "committed snapshot: $count workflows at $stamp"
