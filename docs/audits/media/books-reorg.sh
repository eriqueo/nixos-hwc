#!/usr/bin/env bash
# books-reorg.sh — dry-run fix plan for /mnt/media/books layout drift.
#
# Companion to docs/audits/media/books-audit.md (2026-06-24).
#
# DEFAULTS TO DRY-RUN. Nothing is renamed or moved unless DRY_RUN=0 is
# explicitly set. Even then, the script only operates under $ROOT and refuses
# to run if $ROOT is not a directory. It also refuses to touch
# $ROOT/.audiobookshelf-metadata/ at all (Audiobookshelf sidecar).
#
# Usage:
#   ./books-reorg.sh                # dry-run, prints what it would do
#   DRY_RUN=0 ./books-reorg.sh      # actually performs the moves
#
# Categories of work, each gated independently:
#
#   1. audiobooks/ — split flat "Author - Title/" into "Author/Title/"
#      (7 mechanical renames; preserves disc subfolders for Gerber/E-Myth)
#   2. ebooks/    — author the two loose .epub files into Author/Title/
#   3. Manual-review blocks (printed, never executed):
#      3a. audiobooks/ entries with no parseable author
#      3b. ebooks/ topic shelves and nested calibre dump
#      3c. Cross-format duplicate (Cal Newport / Slow Productivity)

set -euo pipefail

ROOT="${ROOT:-/mnt/media/books}"
DRY_RUN="${DRY_RUN:-1}"

if [[ ! -d "$ROOT" ]]; then
  echo "ERROR: \$ROOT ($ROOT) is not a directory." >&2
  exit 2
fi

# Hard guard: never touch the Audiobookshelf sidecar.
SIDECAR="$ROOT/.audiobookshelf-metadata"

if [[ "$DRY_RUN" == "1" ]]; then
  echo "==> DRY-RUN: nothing will be changed. Set DRY_RUN=0 to apply."
else
  echo "==> APPLY MODE: changes will be written to $ROOT"
fi
echo "==> ROOT=$ROOT"
echo "==> SIDECAR (never touched): $SIDECAR"
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

guard_path() {
  # Refuse to operate on paths under the Audiobookshelf sidecar.
  local p="$1"
  case "$p" in
    "$SIDECAR"|"$SIDECAR"/*)
      echo "REFUSING to touch sidecar path: $p" >&2
      exit 3
      ;;
  esac
}

# move_into_author <library> <flat-dir-name> <author> <title>
# Renames "$ROOT/<library>/<flat-dir-name>" → "$ROOT/<library>/<author>/<title>".
move_into_author() {
  local lib="$1" flat="$2" author="$3" title="$4"
  local src="$ROOT/$lib/$flat"
  local dst_author="$ROOT/$lib/$author"
  local dst="$dst_author/$title"
  guard_path "$src"; guard_path "$dst"
  if [[ ! -d "$src" ]]; then
    echo "  SKIP (missing): $src"
    return 0
  fi
  if [[ -e "$dst" ]]; then
    echo "  SKIP (dst exists): $dst"
    return 0
  fi
  run "ensure author dir: $author" mkdir -p "$dst_author"
  run "rename: $flat → $author/$title" mv -n "$src" "$dst"
}

# move_loose_into_author <library> <file-basename> <author> <title>
# Moves "$ROOT/<library>/<basename>" → "$ROOT/<library>/<author>/<title>/<basename>"
move_loose_into_author() {
  local lib="$1" file="$2" author="$3" title="$4"
  local src="$ROOT/$lib/$file"
  local dst_author="$ROOT/$lib/$author"
  local dst_title="$dst_author/$title"
  local dst="$dst_title/$file"
  guard_path "$src"; guard_path "$dst"
  if [[ ! -f "$src" ]]; then
    echo "  SKIP (missing): $src"
    return 0
  fi
  if [[ -e "$dst" ]]; then
    echo "  SKIP (dst exists): $dst"
    return 0
  fi
  run "ensure title dir: $author/$title" mkdir -p "$dst_title"
  run "move loose file: $file → $author/$title/$file" mv -n "$src" "$dst"
}

# -----------------------------------------------------------------------------
# 1. audiobooks/ — split flat "Author - Title" into "Author/Title"
# -----------------------------------------------------------------------------
echo "==> 1. audiobooks/: split flat 'Author - Title' → 'Author/Title'"
move_into_author audiobooks \
  "Brian Tracy - The Miracle of Self Discipline The 'No Excuses' Way to Getting Things Done" \
  "Brian Tracy" \
  "The Miracle of Self Discipline - The No Excuses Way to Getting Things Done"

# Cal Newport already has an Author/ dir — merge the flat title into it.
move_into_author audiobooks \
  "Cal Newport - So Good They Can't Ignore You" \
  "Cal Newport" \
  "So Good They Can't Ignore You"

move_into_author audiobooks \
  "Elaine Aron - The Highly Sensitive Child (Unabridged)" \
  "Elaine Aron" \
  "The Highly Sensitive Child"

# Gerber: top dir is Author-Title flat, children are disc splits of ONE title.
# Renaming the top dir promotes the discs in place — they stay under the title dir.
move_into_author audiobooks \
  "Gerber, Michael E. - The E-Myth Revisited - Why Most Small Businesses Don't Work and What to Do About It" \
  "Gerber, Michael E." \
  "The E-Myth Revisited - Why Most Small Businesses Don't Work and What to Do About It"

move_into_author audiobooks \
  "Johann Hari - Stolen Focus Why You Can't Pay Attention—and How to Think Deeply Again" \
  "Johann Hari" \
  "Stolen Focus - Why You Can't Pay Attention and How to Think Deeply Again"

move_into_author audiobooks \
  "Robert Greene - The 48 Laws of Power" \
  "Robert Greene" \
  "The 48 Laws of Power"

move_into_author audiobooks \
  "William F. Buckley - God and Man at Yale - The Superstitions of Academic Freedom (Unabridged)" \
  "William F. Buckley" \
  "God and Man at Yale - The Superstitions of Academic Freedom"

echo

# -----------------------------------------------------------------------------
# 2. ebooks/ — author the two loose .epub files
# -----------------------------------------------------------------------------
echo "==> 2. ebooks/: author loose .epub files"
move_loose_into_author ebooks \
  "Cal Newport - Slow Productivity.epub" \
  "Cal Newport" \
  "Slow Productivity"

move_loose_into_author ebooks \
  "The Man Who Was Thursday - G.K. Chesterton.epub" \
  "G.K. Chesterton" \
  "The Man Who Was Thursday"

echo

# -----------------------------------------------------------------------------
# 3. Manual-review blocks (printed only — never executed)
# -----------------------------------------------------------------------------
cat <<'EOF'
==> 3a. audiobooks/: no parseable author — REVIEW MANUALLY
    These need a human to pick the canonical Author/Title pair before any move.

      audiobooks/01 -  Master & Commander/
        → suggested: "Patrick O'Brian/Master & Commander/"
          (already have audiobooks/Patrick O'Brian/ with two later titles)

      audiobooks/Count of Monte Cristo - Dumas - Audiobook - Richard Matthews/
        → suggested: "Alexandre Dumas/The Count of Monte Cristo/"
          (drop narrator suffix; canonicalize "Dumas")

      audiobooks/Philosophy of Thomas Aquinas/
        → suggested: "Peter Kreeft/The Philosophy of Thomas Aquinas/" (verify)

      audiobooks/The Courage to Be Disliked/
        → suggested: "Ichiro Kishimi/The Courage to Be Disliked/" (verify co-author Fumitake Koga)

==> 3b. ebooks/: non-Author shelves and nested calibre dump — REVIEW MANUALLY
    None of these is safe to mechanically rename. Decide policy first.

      ebooks/coding/                            # topic shelf (~26 pdf in 3 publisher bundles + readme/trackers.txt)
      ebooks/Survival, Homesteading & Self-Sufficiency/  # topic shelf (~140 pdf, one flat level)
      ebooks/ebooks/calibre/                    # nested Calibre library — has metadata.db, .calnotes/
      ebooks/ebooks/calibre/G.K. Chesterton/Father Brown Stories (1)/
      ebooks/ebooks/calibre/G.K. Chesterton/William Blake (2)/

    Options to discuss:
      - Promote calibre/<Author>/<Title>/ entries into ebooks/<Author>/<Title>/
        and retire the calibre dump (export with Calibre first).
      - Keep coding/ + Survival… as topic shelves OUTSIDE the Readarr root,
        e.g. move to /mnt/media/documents/ — Readarr expects per-author roots.
      - Or: tell Readarr to ignore these subdirs and accept they are not
        managed by Readarr.

==> 3c. Cross-format duplicates — REVIEW MANUALLY
      Cal Newport — Slow Productivity:
        - audio: audiobooks/Cal Newport/Slow Productivity/
        - ebook: ebooks/Cal Newport - Slow Productivity.epub
                 (step 2 will move it to ebooks/Cal Newport/Slow Productivity/)
        → After step 2 runs, the title exists under both libraries with
          parallel paths. That is the intended Readarr/Bookshelf layout.

EOF

echo "==> done."
