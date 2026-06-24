#!/usr/bin/env bash
# music-reorg.sh — DRY-RUN BY DEFAULT proposed-fix script for /mnt/media/music
#
# Companion to docs/audits/media/music-audit.md (2026-06-24 audit).
#
# Usage:
#   ./music-reorg.sh                       # dry-run, MODE=current (lowest churn)
#   MODE=card ./music-reorg.sh             # dry-run, also rewrite NN<sp>title → NN - title (~2795 files)
#   DRY_RUN=0 ./music-reorg.sh             # actually do it (MODE=current)
#   DRY_RUN=0 MODE=card ./music-reorg.sh   # actually do it AND rewrite the 2795
#
# The nightly agent that emitted this script did NOT execute it. Review every
# section before running.

set -euo pipefail

DRY_RUN="${DRY_RUN:-1}"
MODE="${MODE:-current}"     # current | card
ROOT="${ROOT:-/mnt/media/music}"
QUAR="$ROOT/_unsorted-quarantine-2025-11/music-cleanup-20251110"

run() {
  # In dry-run print the command; otherwise execute it.
  if [[ "$DRY_RUN" == "1" ]]; then
    printf 'DRY-RUN: %s\n' "$*"
  else
    eval "$@"
  fi
}

echo "=========================================================="
echo "music-reorg.sh  DRY_RUN=$DRY_RUN  MODE=$MODE"
echo "ROOT=$ROOT"
echo "=========================================================="

# -----------------------------------------------------------------
# 1. Duplicate-album diffs (quarantine vs main library) — review only.
# -----------------------------------------------------------------
echo
echo "## 1. Duplicate-album diffs — review which copy to keep"
echo "##    (this section runs 'diff -rq' read-only regardless of DRY_RUN)"

dup_pairs=(
  "$ROOT/Rush/Roll the Bones|$QUAR/Roll the Bones"
  "$ROOT/Rush/Power Windows|$QUAR/Power Windows"
  "$ROOT/Rush/Presto|$QUAR/Presto"
  "$ROOT/Rush/Caress of Steel (1975)|$QUAR/Caress of Steel (1975)"
  "$ROOT/Brian Eno/Music for Films|$QUAR/Music for Films"
  "$ROOT/Brian Eno/Music for Civic Recovery Centre|$QUAR/Music for Civic Recovery Centre"
  "$ROOT/Brian Eno/Music for Prague|$QUAR/Music for Prague"
  "$ROOT/John Fahey/America|$QUAR/America"
  "$ROOT/John Fahey/Christmas Guitar|$QUAR/Christmas Guitar"
  "$ROOT/John Fahey/City of Refuge|$QUAR/City of Refuge"
  "$ROOT/John Fahey/Fare Forward Voyagers (Soldier’s Choice)|$QUAR/Fare Forward Voyagers (Soldier’s Choice)"
  "$ROOT/John Fahey/God, Time and Causality|$QUAR/God, Time and Causality"
  "$ROOT/John Fahey/Old Fashioned Love|$QUAR/Old Fashioned Love"
  "$ROOT/John Fahey/Old Girlfriends and Other Horrible Memories|$QUAR/Old Girlfriends and Other Horrible Memories"
  "$ROOT/John Fahey/Red Cross, Disciple of Christ Today|$QUAR/Red Cross, Disciple of Christ Today"
  "$ROOT/Ivor Cutler/Ludo|$QUAR/Ludo"
  "$ROOT/Kurt Vile/10 Songs|$QUAR/10 Songs"
  "$ROOT/Panda Bear _ Excepter/Carrots _ KKKKK|$QUAR/Panda Bear _ Excepter/Carrots _ KKKKK"
  "$ROOT/Brian Eno/Drums Between the Bells (2011)/CD 01|$QUAR/CD 01"
  "$ROOT/Brian Eno/Drums Between the Bells (2011)/CD 02|$QUAR/CD 02"
)

for pair in "${dup_pairs[@]}"; do
  main="${pair%%|*}"
  dup="${pair##*|}"
  echo "--- DIFF: $main  <->  $dup"
  if [[ -d "$main" && -d "$dup" ]]; then
    diff -rq "$main" "$dup" || true
  else
    echo "  (one side missing — re-verify)"
  fi
done

# -----------------------------------------------------------------
# 2. Loose tracks at artist root → fold into Artist/Album/
# -----------------------------------------------------------------
echo
echo "## 2. Loose tracks at artist root → move into album dirs"

# Aretha Franklin / A Brand New Me (14 files)
run "mkdir -p \"$ROOT/Aretha Franklin/A Brand New Me\""
for f in "$ROOT/Aretha Franklin/"Aretha\ Franklin_A\ Brand\ New\ Me_*.mp3; do
  [[ -e "$f" ]] || continue
  bn="$(basename "$f")"
  # Aretha Franklin_A Brand New Me_NN_Title.mp3 → NN - Title.mp3
  new="$(echo "$bn" | sed -E 's/^Aretha Franklin_A Brand New Me_([0-9]+)_(.*)\.mp3$/\1 - \2.mp3/')"
  run "mv -n -- \"$f\" \"$ROOT/Aretha Franklin/A Brand New Me/$new\""
done

# Scientist / 1999 Dub (3 files)
run "mkdir -p \"$ROOT/Scientist/1999 Dub\""
for f in "$ROOT/Scientist/"Scientist_1999\ Dub_*.mp3; do
  [[ -e "$f" ]] || continue
  bn="$(basename "$f")"
  new="$(echo "$bn" | sed -E 's/^Scientist_1999 Dub_([0-9]+)_(.*)\.mp3$/\1 - \2.mp3/')"
  run "mv -n -- \"$f\" \"$ROOT/Scientist/1999 Dub/$new\""
done

# -----------------------------------------------------------------
# 3. Delete incomplete downloads + junk sidecars
# -----------------------------------------------------------------
echo
echo "## 3. Delete .mp3.part + junk sidecars"

while IFS= read -r -d '' f; do
  run "rm -- \"$f\""
done < <(find "$QUAR/Various Classical" -type f -iname '*.mp3.part' -print0 2>/dev/null || true)

while IFS= read -r -d '' f; do
  run "rm -- \"$f\""
done < <(find "$ROOT" \( -name '.DS_Store' -o -name '*.I6Jwkt' \) -print0 2>/dev/null || true)

# -----------------------------------------------------------------
# 4. Filename-format fixes — depends on MODE
# -----------------------------------------------------------------
echo
echo "## 4. Filename-format fixes  (MODE=$MODE)"

# 4a. 56 tracks named "Artist - Album - NN - Title.ext"  → "NN - Title.ext"
#     (these are concentrated in two albums; we strip the leading
#     "<artist> - <album> - " prefix when the trailing portion matches
#     "NN - Title.ext")
fix_long_form() {
  local f="$1"
  local dir bn new
  dir="$(dirname "$f")"
  bn="$(basename "$f")"
  if [[ "$bn" =~ ^.*\ -\ .*\ -\ ([0-9]+)\ -\ (.+)$ ]]; then
    new="${BASH_REMATCH[1]} - ${BASH_REMATCH[2]}"
    [[ "$bn" == "$new" ]] && return 0
    run "mv -n -- \"$f\" \"$dir/$new\""
  fi
}

while IFS= read -r -d '' f; do
  fix_long_form "$f"
done < <(find "$ROOT" -mindepth 3 -type f \
            \( -iname '*.flac' -o -iname '*.mp3' -o -iname '*.m4a' \) \
            -not -path "$QUAR/*" -print0 2>/dev/null | \
         while IFS= read -r -d '' g; do
           # only the offenders: filename starts with a letter, contains " - NN - "
           bn="$(basename "$g")"
           if [[ "$bn" =~ ^[A-Za-z].*\ -\ [0-9]+\ -\ .+ ]]; then
             printf '%s\0' "$g"
           fi
         done)

# 4b. MODE=card → rewrite "NN <title>.ext" → "NN - <title>.ext"
if [[ "$MODE" == "card" ]]; then
  echo "## 4b. MODE=card → rewrite NN<sp>title → NN - title  (~2795 files)"
  while IFS= read -r -d '' f; do
    dir="$(dirname "$f")"
    bn="$(basename "$f")"
    if [[ "$bn" =~ ^([0-9]+)\ ([^-].*)$ ]]; then
      new="${BASH_REMATCH[1]} - ${BASH_REMATCH[2]}"
      run "mv -n -- \"$f\" \"$dir/$new\""
    fi
  done < <(find "$ROOT" -mindepth 3 -type f \
              \( -iname '*.flac' -o -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.ogg' -o -iname '*.opus' -o -iname '*.wav' \) \
              -not -path "$QUAR/*" -print0 2>/dev/null)
else
  echo "## 4b. MODE=current → leaving 'NN <title>' filenames alone"
fi

# -----------------------------------------------------------------
# 5. Real tag-gap audit — emit-only, run on a host with `beet`
# -----------------------------------------------------------------
cat <<'BEETS'

## 5. Tag-gap audit — run these manually on a host with `beet` configured

# Albums beets thinks are incomplete:
beet list -a -p missing:1

# Tracks with empty artist / album / title / track tags:
beet list -p "^artist::."
beet list -p "^album::."
beet list -p "^title::."
beet list -p "^track::[0-9]"

# Re-import quarantine after duplicates are resolved (still dry-run via -p):
beet import -p /mnt/media/music/_unsorted-quarantine-2025-11/music-cleanup-20251110

BEETS

echo
echo "Done. (DRY_RUN=$DRY_RUN — nothing was changed if DRY_RUN=1)"
