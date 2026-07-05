#!/usr/bin/env bash
# aux-reorg.sh — dry-run fix plan for /mnt/media aux libraries:
#   courses, podcasts, youtube, photos
#
# Companion to docs/audits/media/aux-audit.md (2026-06-24).
#
# DEFAULTS TO DRY-RUN. Nothing is moved, renamed, or removed unless DRY_RUN=0
# is explicitly set. Even then, the script only operates under $ROOT and
# refuses to run if $ROOT is not a directory. Per-library work is gated into
# sections; each section is independently no-op if its target paths are
# absent.
#
# Usage:
#   ./aux-reorg.sh                # dry-run, prints what it would do
#   DRY_RUN=0 ./aux-reorg.sh      # actually performs the moves
#
# Sections (each may be a no-op if the relevant tree is empty/missing):
#
#   1. courses/  — promote 'Linux Security for Beginners/~Get Your Files
#                  Here !/' contents up one level; flag 23× '*.url' shortcuts;
#                  flag misplaced .epub course; flag 'UPDATE 1/' sub-tree
#   2. podcasts/ — no-op; library is empty
#   3. youtube/  — flag 'Gary Katz - Finish Carpentry#/' duplicate channel
#                  for manual merge into 'Gary Katz/'
#   4. photos/   — flag two UUID-named Immich backups under archive/;
#                  flag 3-way Camera-Uploads collapse; flag empty .keep dirs

set -euo pipefail

ROOT="${ROOT:-/mnt/media}"
DRY_RUN="${DRY_RUN:-1}"

if [[ ! -d "$ROOT" ]]; then
  echo "ERROR: \$ROOT ($ROOT) is not a directory." >&2
  exit 2
fi

if [[ "$DRY_RUN" == "1" ]]; then
  echo "==> DRY-RUN: nothing will be changed. Set DRY_RUN=0 to apply."
else
  echo "==> APPLY MODE: changes will be written under $ROOT"
fi
echo "==> ROOT=$ROOT"
echo

run() {
  # run "<description>" <cmd...>
  local desc="$1"; shift
  echo "  $desc"
  if [[ "$DRY_RUN" == "0" ]]; then
    "$@"
  fi
}

flag() {
  # flag "<reason>" "<path-or-detail>"
  echo "  FLAG: $1"
  echo "        $2"
}

# ---------------------------------------------------------------------------
# 1. courses/
# ---------------------------------------------------------------------------
echo "==> [1/4] courses/"

C_ROOT="$ROOT/courses"
if [[ ! -d "$C_ROOT" ]]; then
  echo "  (skip: $C_ROOT missing)"
else
  # 1a. Promote 'Linux Security for Beginners/~Get Your Files Here !/'
  #     contents up to the course root.
  WRAP="$C_ROOT/Linux Security for Beginners/~Get Your Files Here !"
  if [[ -d "$WRAP" ]]; then
    echo "  Linux Security for Beginners: promote wrapper-dir contents up one level"
    while IFS= read -r -d '' item; do
      base="$(basename "$item")"
      dest="$C_ROOT/Linux Security for Beginners/$base"
      if [[ -e "$dest" ]]; then
        echo "    SKIP (dest exists): $dest"
      else
        run "    mv: $item -> $dest" mv -n -- "$item" "$dest"
      fi
    done < <(find "$WRAP" -mindepth 1 -maxdepth 1 -print0)
    # Only remove the wrapper if it ended up empty.
    if [[ -d "$WRAP" ]] && [[ -z "$(ls -A "$WRAP" 2>/dev/null || true)" ]]; then
      run "    rmdir: $WRAP" rmdir -- "$WRAP"
    fi
  fi

  # 1b. Flag (do NOT delete) the 23× '.url' advertising shortcuts so the
  #     human can decide. Deletion is destructive; we never auto-delete.
  url_count=$(find "$C_ROOT" -type f -name '*.url' 2>/dev/null | wc -l)
  if (( url_count > 0 )); then
    echo "  $url_count× '*.url' advertising shortcuts found (manual review):"
    find "$C_ROOT" -type f -name '*.url' -printf '    %p\n' | head -10
    if (( url_count > 10 )); then echo "    … ($((url_count-10)) more)"; fi
  fi

  # 1c. Flag misplaced course / single-file 'courses'.
  if [[ -f "$C_ROOT/Ultimate Time Management Toolkit/The Ultimate Time Management Toolkit - Risa Williams.epub" ]]; then
    flag "course is a single .epub; belongs under media/books/ebooks/ not media/courses/" \
         "$C_ROOT/Ultimate Time Management Toolkit/"
  fi
  if [[ -f "$C_ROOT/ADHD 30 Days to the Life You Deserve/ADHD 30 Days To The Life You Deserve.zip" ]]; then
    flag "course delivered only as an unextracted .zip; extract to NN-Lesson.ext layout or remove" \
         "$C_ROOT/ADHD 30 Days to the Life You Deserve/"
  fi

  # 1d. Flag 'UPDATE 1/' duplicate-sections tree for manual review.
  if [[ -d "$C_ROOT/ChatGPT Mastery Course/UPDATE 1" ]]; then
    flag "ChatGPT Mastery Course/UPDATE 1/ overlaps parent section numbering (02-, 03-, …); manual reconcile" \
         "$C_ROOT/ChatGPT Mastery Course/UPDATE 1/"
  fi
fi

echo

# ---------------------------------------------------------------------------
# 2. podcasts/
# ---------------------------------------------------------------------------
echo "==> [2/4] podcasts/"
P_ROOT="$ROOT/podcasts"
if [[ ! -d "$P_ROOT" ]]; then
  echo "  (skip: $P_ROOT missing)"
else
  entry_count=$(find "$P_ROOT" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)
  if (( entry_count == 0 )); then
    echo "  no-op: $P_ROOT is empty; standard is Show/YYYY-MM-DD - Episode.ext"
  else
    echo "  unexpected: $P_ROOT not empty ($entry_count entries); audit was based on empty tree"
    find "$P_ROOT" -mindepth 1 -maxdepth 2 -printf '    %p\n' | head -20
  fi
fi

echo

# ---------------------------------------------------------------------------
# 3. youtube/
# ---------------------------------------------------------------------------
echo "==> [3/4] youtube/"
Y_ROOT="$ROOT/youtube"
SHOWS="$Y_ROOT/shows"
if [[ ! -d "$Y_ROOT" ]]; then
  echo "  (skip: $Y_ROOT missing)"
else
  CANON="$SHOWS/Gary Katz"
  DUP="$SHOWS/Gary Katz - Finish Carpentry#"
  if [[ -d "$DUP" ]]; then
    flag "duplicate channel folder for Gary Katz" \
         "$DUP  ($(find "$DUP" -type f | wc -l) files, $(du -sh "$DUP" | cut -f1)) overlaps $CANON"
    echo "    Suggested manual merge (review first, then run by hand):"
    echo "      rsync -avn --ignore-existing \"$DUP/\" \"$CANON/\""
    echo "      # then, after manual diff confirms nothing unique remains in the # variant:"
    echo "      rm -rIv \"$DUP\""
    # We intentionally do NOT auto-merge: 4 filenames overlap byte-for-byte,
    # 11 files are unique to the # variant; a wrong --ignore-existing pass
    # could destroy unique content. Manual gate.
  fi

  # Trailing '.keep' marker at /mnt/media/youtube/.keep is harmless once
  # shows/ exists. Flagged only; not auto-removed.
  if [[ -f "$Y_ROOT/.keep" ]] && [[ -d "$SHOWS" ]]; then
    flag "leftover '.keep' marker; safe to delete once shows/ tree is stable" \
         "$Y_ROOT/.keep"
  fi
fi

echo

# ---------------------------------------------------------------------------
# 4. photos/
# ---------------------------------------------------------------------------
echo "==> [4/4] photos/"
H_ROOT="$ROOT/photos"
if [[ ! -d "$H_ROOT" ]]; then
  echo "  (skip: $H_ROOT missing)"
else
  # 4a. Two UUID-named Immich library backups under archive/.
  for uuid in 42ce7cc4-56f5-4549-ad30-8a061747b269 ff28bcb9-0346-4dba-a7b9-b92981d06920; do
    BK="$H_ROOT/archive/$uuid"
    if [[ -d "$BK" ]]; then
      flag "Immich-style content-addressed backup; confirm Immich's own backup before removing" \
           "$BK  ($(find "$BK" -type f | wc -l) files, $(du -sh "$BK" | cut -f1))"
    fi
  done

  # 4b. Three-way camera-dump collapse.
  CU="$H_ROOT/archive/Camera Uploads"
  U1="$H_ROOT/archive/upload"
  U2="$H_ROOT/archive/uploads"
  for d in "$CU" "$U1" "$U2"; do
    if [[ -d "$d" ]]; then
      c=$(find "$d" -type f 2>/dev/null | wc -l)
      echo "  camera-dump bucket: $d ($c files)"
    fi
  done
  if [[ -d "$U2" ]] && [[ -z "$(ls -A "$U2" 2>/dev/null || true)" ]]; then
    flag "empty bucket; collapse into one of the camera-dump siblings or remove" \
         "$U2"
  fi
  flag "three-way camera-dump split (Camera Uploads/ + upload/ + uploads/); merge after manual review" \
       "$CU, $U1, $U2"

  # 4c. Year vs event mix at archive/ root.
  if compgen -G "$H_ROOT/archive/2[0-9][0-9][0-9]" >/dev/null; then
    flag "year folders coexist with event folders at archive/ root; consider archive/years/ + archive/events/ split" \
         "$H_ROOT/archive/"
  fi

  # 4d. Empty Immich-managed dirs at the photos root.
  for d in library profile thumbs; do
    P="$H_ROOT/$d"
    if [[ -d "$P" ]]; then
      c=$(find "$P" -type f 2>/dev/null | wc -l)
      if (( c <= 1 )); then
        flag "near-empty Immich-managed dir at photos root ($c files); leave for Immich, do not delete here" \
             "$P"
      fi
    fi
  done

  # 4e. Trailing-space directory name.
  if [[ -d "$H_ROOT/archive/Banjo Era " ]]; then
    flag "directory name has trailing space; rename to 'Banjo Era/'" \
         "$H_ROOT/archive/Banjo Era "
  fi
fi

echo
echo "==> done. Re-run with DRY_RUN=0 to apply the (currently zero) safe moves."
echo "    All other items are flagged for manual review and intentionally not"
echo "    actioned by this script."
