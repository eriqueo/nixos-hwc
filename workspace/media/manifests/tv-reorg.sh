#!/usr/bin/env bash
# tv-reorg.sh — dry-run fix plan for /mnt/media/tv naming/layout drift.
#
# Companion to docs/audits/media/tv-audit.md (2026-06-24).
#
# DEFAULTS TO DRY-RUN. Nothing is renamed or deleted unless DRY_RUN=0 is
# explicitly set. Even then, the script only operates under $ROOT and refuses
# to run if $ROOT is not a directory.
#
# Usage:
#   ./tv-reorg.sh                # dry-run, prints what it would do
#   DRY_RUN=0 ./tv-reorg.sh      # actually performs the moves/deletes
#
# Categories of work, each gated independently:
#
#   1. Delete macOS sidecar trash (.DS_Store, ._*)
#   2. Rename single-digit / prefixed season folders → Season NN
#   3. Rename "Specials" → "Season 00"
#   4. Rename "S0N 480p DVD" → "Season 0N" (It's Always Sunny)
#   5..9 Manual-review blocks (printed, never executed): extras dirs,
#        Life on Earth E-only files, MST3K/Octonauts specials renumber,
#        season-less shows (A Real Bug's Life, Cars on the Road),
#        missing/empty year suffixes.

set -euo pipefail

ROOT="${ROOT:-/mnt/media/tv}"
DRY_RUN="${DRY_RUN:-1}"

if [[ ! -d "$ROOT" ]]; then
  echo "ERROR: \$ROOT ($ROOT) is not a directory." >&2
  exit 2
fi

if [[ "$DRY_RUN" == "1" ]]; then
  echo "==> DRY-RUN: nothing will be changed. Set DRY_RUN=0 to apply."
else
  echo "==> APPLY MODE: changes will be written to $ROOT"
fi
echo "==> ROOT=$ROOT"
echo

run() {
  # run "<description>" <cmd...>
  local desc="$1"; shift
  echo "  $desc"
  printf '    $'
  printf ' %q' "$@"
  printf '\n'
  if [[ "$DRY_RUN" != "1" ]]; then
    "$@"
  fi
}

#-----------------------------------------------------------------------------
# 1. Delete macOS sidecar trash
#-----------------------------------------------------------------------------
echo "=== 1. Delete macOS sidecar files (.DS_Store, ._*) ==="
while IFS= read -r -d '' f; do
  run "rm $f" rm -f "$f"
done < <(find "$ROOT" \( -name '.DS_Store' -o -name '._*' \) -type f -print0)
echo

#-----------------------------------------------------------------------------
# 2. Rename season folders to canonical "Season NN"
#-----------------------------------------------------------------------------
echo "=== 2. Canonicalize season folders → 'Season NN' ==="
# Find any dir at depth 2 (one level under a show) whose basename matches
# the buggy variants we want to normalize:
#   "Season N"          (single-digit, no zero-pad)
#   "<Show> Season N"   (redundant prefix)
#   "<Show> Season NN"  (redundant prefix, already two digits)
while IFS= read -r -d '' dir; do
  base="$(basename "$dir")"
  # Extract the trailing season number
  if [[ "$base" =~ Season[[:space:]]+([0-9]{1,3})$ ]]; then
    n="${BASH_REMATCH[1]}"
    # Zero-pad to two digits (cap at 99; for >99 keep as-is)
    if (( n < 100 )); then
      printf -v padded "%02d" "$n"
    else
      padded="$n"
    fi
    target="$(dirname "$dir")/Season $padded"
    if [[ "$dir" != "$target" ]]; then
      run "mv $dir -> $target" mv -n -- "$dir" "$target"
    fi
  fi
done < <(find "$ROOT" -mindepth 2 -maxdepth 2 -type d \
           \( -regex '.*/Season [0-9]+$' \
              -o -regex '.*/[^/]+ Season [0-9]+$' \) -print0)
echo

#-----------------------------------------------------------------------------
# 3. Rename "Specials" → "Season 00"
#-----------------------------------------------------------------------------
echo "=== 3. Rename 'Specials' → 'Season 00' ==="
while IFS= read -r -d '' dir; do
  target="$(dirname "$dir")/Season 00"
  if [[ -e "$target" ]]; then
    echo "  SKIP (target exists): $dir -> $target"
    continue
  fi
  run "mv $dir -> $target" mv -n -- "$dir" "$target"
done < <(find "$ROOT" -mindepth 2 -maxdepth 2 -type d -name 'Specials' -print0)
echo

#-----------------------------------------------------------------------------
# 4. Rename "S0N 480p DVD" → "Season 0N"  (It's Always Sunny)
#-----------------------------------------------------------------------------
echo "=== 4. Rename 'S0N 480p DVD' → 'Season 0N' ==="
while IFS= read -r -d '' dir; do
  base="$(basename "$dir")"
  if [[ "$base" =~ ^S([0-9]{1,3})[[:space:]]+.*$ ]]; then
    n="${BASH_REMATCH[1]}"
    printf -v padded "%02d" "$n"
    target="$(dirname "$dir")/Season $padded"
    if [[ -e "$target" ]]; then
      echo "  SKIP (target exists): $dir -> $target"
      continue
    fi
    run "mv $dir -> $target" mv -n -- "$dir" "$target"
  fi
done < <(find "$ROOT" -mindepth 2 -maxdepth 2 -type d -regex '.*/S[0-9]+ .*' -print0)
echo

#-----------------------------------------------------------------------------
# 5. Manual review: non-standard extras directories
#-----------------------------------------------------------------------------
echo "=== 5. MANUAL REVIEW: non-standard extras directories ==="
echo "(featurettes/, trailers/, other/ — not Sonarr-managed; either delete or"
echo " move out of /mnt/media/tv, e.g. to /mnt/media/extras/<show>/)"
find "$ROOT" -mindepth 2 -maxdepth 2 -type d \
     \( -name 'featurettes' -o -name 'trailers' -o -name 'other' \) -print \
     | sed 's/^/    /'
echo

#-----------------------------------------------------------------------------
# 6. Manual review: Life on Earth — files use E-only, need S01 prefix
#-----------------------------------------------------------------------------
echo "=== 6. MANUAL REVIEW: Life on Earth — add S01 prefix to E-only filenames ==="
echo "(Pattern: 'Life.On.Earth.ENN.*' -> 'Life.On.Earth.S01ENN.*')"
find "$ROOT/Life on Earth" -type f -iname '*.mkv' 2>/dev/null \
     | grep -E 'Life\.On\.Earth\.E[0-9]+' | sed 's/^/    /' || true
echo

#-----------------------------------------------------------------------------
# 7. Manual review: MST3K + Octonauts Above and Beyond specials
#-----------------------------------------------------------------------------
echo "=== 7. MANUAL REVIEW: Specials needing explicit S00ENN assignment ==="
echo "(MST3K — 41 named-only specials; OAaB — 3 named-only specials)"
find "$ROOT/Mystery Science Theater 3000 ()/Specials" -type f -iname '*.avi' 2>/dev/null \
     | head -5 | sed 's/^/    [MST3K] /' || true
echo "    ... (41 total)"
find "$ROOT/Octonauts Above and Beyond (2021)/Specials" -type f -iname '*.mkv' 2>/dev/null \
     | sed 's/^/    [OAaB]  /' || true
echo

#-----------------------------------------------------------------------------
# 8. Manual review: shows with no season folders (all files loose)
#-----------------------------------------------------------------------------
echo "=== 8. MANUAL REVIEW: shows with no Season folders ==="
echo "(Create Season 0N dirs and mv files in by their SxxEyy token.)"
for show in "A Real Bug's Life" "Cars on the Road"; do
  if [[ -d "$ROOT/$show" ]]; then
    echo "  $show/"
    find "$ROOT/$show" -maxdepth 1 -type f -iname '*.mkv' \
         | sed 's/^/    /'
  fi
done
echo

#-----------------------------------------------------------------------------
# 9. Manual review: missing / empty year suffix in show folder names
#-----------------------------------------------------------------------------
echo "=== 9. MANUAL REVIEW: show folders missing / with empty year suffix ==="
echo "(Sonarr should re-resolve against TVDB to fill the year.)"
find "$ROOT" -mindepth 1 -maxdepth 1 -type d \
     \( -regex '.*()$' -o ! -regex '.*([0-9][0-9][0-9][0-9])$' \) \
     | sort | sed 's/^/    /'
echo

echo "==> Done."
if [[ "$DRY_RUN" == "1" ]]; then
  echo "==> (Dry-run; no changes were written.)"
fi
