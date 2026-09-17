#!/usr/bin/env bash
# config-sync.sh — two-way sync of the shared claude-config repo, and the link
# layer that puts its per-project memory store behind every Claude config dir.
#
# Lives beside index.nix, not inline, for the reason settings-heal.jq does:
# config-sync.test.sh runs these exact bytes against throwaway repos.
#
# Usage:
#   config-sync.sh link   # migrate real memory dirs into the repo, link repo dirs back
#   config-sync.sh sync   # link, commit data paths, merge the hub, link again, push
#
# Inputs (environment, bound by the Nix wrapper):
#   CC_REPO          working tree of claude-config (a clone of the hub)
#   CC_HOST          host name used in commit messages and conflict copies
#   CC_CONFIG_DIRS   colon-separated absolute Claude config dirs (~/.claude first)
#   CC_POST_MERGE    optional executable run after a merge changed the tree
#
# Data paths are the only things this commits: MISTAKES.md and
# projects/*/memory. Hand edits to skills, hooks and CLAUDE.md stay the author's
# to commit. The hub merge runs WITHOUT --autostash, so git itself refuses a
# merge that would overwrite a dirty file, and the unit fails loud naming it.
set -uo pipefail

MODE="${1:-sync}"
: "${CC_REPO:?CC_REPO unset}" "${CC_HOST:?CC_HOST unset}" "${CC_CONFIG_DIRS:?CC_CONFIG_DIRS unset}"
STORE="$CC_REPO/projects"

log() { printf 'claude-config-sync: %s\n' "$*"; }
warn() { printf 'claude-config-sync: WARNING: %s\n' "$*" >&2; }

cd "$CC_REPO" || { warn "repo $CC_REPO missing"; exit 1; }
[ -d .git ] || { warn "$CC_REPO is not a git clone"; exit 1; }

# One lock for every writer of this tree (timer, activation, manual runs).
exec 9>"$CC_REPO/.git/.sync.lock"
flock 9

# The standing-instructions block in CLAUDE.md is regenerated from memories on
# every prompt. .gitattributes routes CLAUDE.md through this clean filter, so
# git only ever sees the two markers. Inline awk, not a store path: a clone's
# config must not point at a path garbage collection can delete.
git config filter.standing-block.clean \
  "awk '/^<!-- BEGIN STANDING INSTRUCTIONS/{print; skip=1; next} /^<!-- END STANDING INSTRUCTIONS -->/{skip=0} !skip'"
git config filter.standing-block.smudge cat

# Git marks a file modified when its SIZE changes, before any filter runs, so a
# regenerated block leaves CLAUDE.md stat-dirty with no content difference —
# and a stat-dirty file makes `git merge` refuse. When the filtered content
# equals the index, re-adding stages the same blob and only refreshes the stat.
refresh_derived() {
  if git diff --quiet -- CLAUDE.md 2>/dev/null; then
    git add -- CLAUDE.md 2>/dev/null || true
  fi
}
refresh_derived

# ---- link layer -------------------------------------------------------------

# capture <src-file> <dst-file>: copy one memory file into the store without
# ever overwriting a different version. Returns 0 when the source is captured.
capture() {
  local src="$1" dst="$2" alt n
  mkdir -p "$(dirname "$dst")"
  if [ ! -e "$dst" ]; then
    cp -p "$src" "$dst"
    return 0
  fi
  cmp -s "$src" "$dst" && return 0
  if [ "$(basename "$dst")" = "MEMORY.md" ]; then
    # Index: append the lines the store lacks, the same result as merge=union.
    local add
    add=$(awk 'NR==FNR{seen[$0]=1; next} !seen[$0]' "$dst" "$src")
    [ -n "$add" ] && printf '%s\n' "$add" >> "$dst"
    return 0
  fi
  alt="${dst%.md}.from-$CC_HOST.md"
  n=1
  while [ -e "$alt" ] && ! cmp -s "$src" "$alt"; do
    alt="${dst%.md}.from-$CC_HOST-$n.md"; n=$((n + 1))
  done
  [ -e "$alt" ] || cp -p "$src" "$alt"
  warn "kept both versions of ${dst#"$CC_REPO"/}: host copy at ${alt#"$CC_REPO"/}"
  return 0
}

# captured <src-file> <dst-file>: is every byte of src already in the store?
captured() {
  local src="$1" dst="$2" f
  [ -e "$dst" ] || return 1
  cmp -s "$src" "$dst" && return 0
  if [ "$(basename "$dst")" = "MEMORY.md" ]; then
    [ -z "$(awk 'NR==FNR{seen[$0]=1; next} !seen[$0]' "$dst" "$src")" ]
    return
  fi
  for f in "${dst%.md}".from-"$CC_HOST"*.md; do
    [ -e "$f" ] && cmp -s "$src" "$f" && return 0
  done
  return 1
}

migrate_dir() { # <real memory dir> <store memory dir>
  local d="$1" t="$2" rel backup ok
  mkdir -p "$t"
  # A memory dir can be its own git repo (datax-main was, 2026-08-17..09-17).
  # Its .git never enters the store: copied in, it would make git record the
  # store as a gitlink and ship none of the files.
  while IFS= read -r -d '' rel; do
    capture "$d/$rel" "$t/$rel"
  done < <(cd "$d" && find . -path ./.git -prune -o -type f -print0)
  backup="$d.pre-sync-$(date +%Y%m%d%H%M%S)"
  mv "$d" "$backup" || { warn "could not move $d aside"; return; }
  if ! ln -s "$t" "$d"; then
    warn "could not link $d (recreated by a live write?); retrying next run"
  fi
  # Late writes that landed between the copy and the move.
  ok=1
  while IFS= read -r -d '' rel; do
    captured "$backup/$rel" "$t/$rel" || capture "$backup/$rel" "$t/$rel"
    captured "$backup/$rel" "$t/$rel" || ok=0
  done < <(cd "$backup" && find . -path ./.git -prune -o -type f -print0)
  if [ -e "$backup/.git" ]; then
    ok=0
    warn "$d was its own git repo; its history stays in $backup/.git (fold it in by hand)"
  fi
  if [ "$ok" = 1 ]; then
    rm -rf -- "$backup"
  else
    warn "kept $backup: not every file is in the store"
  fi
  log "migrated ${d} into ${t#"$CC_REPO"/}"
}

link_layer() {
  local dir d slug link t IFS=':'
  mkdir -p "$STORE"
  for dir in $CC_CONFIG_DIRS; do
    [ -n "$dir" ] || continue
    # a) real memory dirs move into the store.
    for d in "$dir"/projects/*/memory; do
      [ -d "$d" ] && [ ! -L "$d" ] || continue
      slug=$(basename "$(dirname "$d")")
      case "$slug" in -tmp-*) continue ;; esac
      migrate_dir "$d" "$STORE/$slug/memory"
    done
    # b) every store dir is linked into this config dir.
    for t in "$STORE"/*/memory; do
      [ -d "$t" ] || continue
      slug=$(basename "$(dirname "$t")")
      link="$dir/projects/$slug/memory"
      if [ -L "$link" ]; then
        [ "$(readlink "$link")" = "$t" ] || warn "$link points at $(readlink "$link"), not $t"
        continue
      fi
      [ -e "$link" ] && continue
      mkdir -p "$dir/projects/$slug"
      ln -s "$t" "$link"
    done
  done
}

link_layer
[ "$MODE" = "link" ] && exit 0
[ "$MODE" = "sync" ] || { warn "unknown mode $MODE"; exit 2; }

# ---- commit data paths ------------------------------------------------------

DATA=(MISTAKES.md projects)
nested=$(find projects -mindepth 2 -name .git 2>/dev/null | head -n 5)
if [ -n "$nested" ]; then
  warn "refusing to commit: nested git repo in the memory store (would become a gitlink): $nested"
  exit 1
fi
{
  # log-mistake holds this lock while it rewrites the ledger.
  exec 8>"$CC_REPO/MISTAKES.md.lock"
  flock 8
  git add -A -- "${DATA[@]}"
  if ! git diff --cached --quiet -- "${DATA[@]}"; then
    git commit --quiet -m "sync($CC_HOST): memories and mistakes ledger" -- "${DATA[@]}" \
      || { warn "commit of data paths failed"; exit 1; }
    log "committed local data changes"
  fi
  exec 8>&-
}

# ---- merge the hub ----------------------------------------------------------

git fetch --quiet origin || { warn "fetch failed"; exit 1; }
UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) \
  || { warn "no upstream branch configured"; exit 1; }

BEFORE=$(git rev-parse HEAD)
if [ -n "$(git rev-list HEAD.."$UPSTREAM")" ]; then
  if ! git merge --quiet --no-edit "$UPSTREAM" >/dev/null 2>&1; then
    conflicted=$(git diff --name-only --diff-filter=U)
    if [ -z "$conflicted" ]; then
      # git refused before touching anything: uncommitted local edits overlap.
      blocking=$(git diff --name-only HEAD "$UPSTREAM" | awk 'NR==FNR{u[$0]=1; next} u[$0]' - <(git diff --name-only))
      warn "merge blocked by uncommitted local edits: ${blocking:-see git status}"
      exit 1
    fi
    while IFS= read -r f; do
      case "$f" in
        projects/*/memory/*.md)
          if git cat-file -e ":3:$f" 2>/dev/null && git cat-file -e ":2:$f" 2>/dev/null; then
            git show ":2:$f" > "${f%.md}.from-$CC_HOST.md"
            git show ":3:$f" > "$f"
            git add -- "$f" "${f%.md}.from-$CC_HOST.md"
          elif git cat-file -e ":2:$f" 2>/dev/null; then
            git show ":2:$f" > "$f"; git add -- "$f"
          else
            git show ":3:$f" > "$f"; git add -- "$f"
          fi
          warn "memory conflict on $f: hub version kept, $CC_HOST version saved beside it"
          ;;
        *)
          git merge --abort 2>/dev/null
          warn "merge conflict outside memory store ($f); aborted, resolve by hand"
          exit 1
          ;;
      esac
    done <<< "$conflicted"
    git commit --quiet --no-edit || { git merge --abort 2>/dev/null; warn "merge commit failed"; exit 1; }
  fi
  log "merged $UPSTREAM"
fi

if [ "$(git rev-parse HEAD)" != "$BEFORE" ]; then
  link_layer
  if [ -n "${CC_POST_MERGE:-}" ]; then
    "$CC_POST_MERGE" || warn "post-merge step failed"
  fi
fi

# ---- publish ----------------------------------------------------------------

if [ -n "$(git rev-list "$UPSTREAM"..HEAD)" ]; then
  git push --quiet origin HEAD || { warn "PUSH FAILED — hub not updated"; exit 1; }
  log "pushed to hub"
fi
exit 0
