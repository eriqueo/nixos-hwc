#!/usr/bin/env bash
# reconcile.sh — consolidate stray media from /mnt/hot orphans into /mnt/media,
# then prune verified-empty orphan dirs. Dry-run by default.
#
# Generated 2026-06-24 by the nightly-builds gauntlet card
# "03 — reconcile script generator (v2)". DO NOT run blindly. See
# docs/audits/mnt-hot/reconcile-checklist.md for the human run procedure.
#
# Contract (enforced below):
#   1. set -euo pipefail
#   2. DRY_RUN defaults to 1 (echo-only). Set DRY_RUN=0 to act.
#   3. is_protected() refuses to touch any path equal to or under an ACTIVE path.
#   4. /mnt/hot and /mnt/media themselves are never `rm` targets.
#   5. Consolidate phase MOVES files (rsync --remove-source-files) — the source
#      is removed only AFTER rsync verifies the destination byte-stream. A
#      re-run is a no-op (the source is gone). This fixes the v1 defect where
#      phase 1 only COPIED, leaving phase 2 unable to delete a still-populated
#      orphan and reclaiming nothing.
#   6. Delete phase only removes orphan dirs proven empty of media AND outside
#      every active path.
#   7. Every destructive line is preceded by an `echo` of the intended action.
#   8. All output is also appended to a timestamped logfile.
#
# Roots are overridable via env (HOT_ROOT/MEDIA_ROOT/LOG_DIR) so the script
# can be exercised against a scratch fixture without touching /mnt. The script
# refuses to run if either root is missing.

set -euo pipefail

# ----------------------------- configuration ---------------------------------

DRY_RUN="${DRY_RUN:-1}"
HOT_ROOT="${HOT_ROOT:-/mnt/hot}"
MEDIA_ROOT="${MEDIA_ROOT:-/mnt/media}"

LOG_DIR="${LOG_DIR:-/var/log/mnt-hot-reconcile}"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/reconcile-$(date -u +%Y%m%dT%H%M%SZ).log"

# Mirror all stdout/stderr to the logfile.
exec > >(tee -a "$LOG_FILE") 2>&1

# ACTIVE PATHS — self-derived 2026-06-24 from nixos-hwc modules:
#   domains/paths/paths.nix              (hot.root, hot.downloads, hot.surveillance, hot.receipts)
#   domains/data/storage/index.nix       (processing/{sonarr,radarr,lidarr}-temp, downloads/incomplete)
#   domains/data/backup/parts/server-backup-scripts.nix (backups/{containers,databases,system})
#   domains/business/paperless/index.nix (documents/{consume,export,staging})
#   domains/media/tdarr/parts/config.nix (processing/{tdarr-temp,tdarr-backups})
#   domains/media/{qbittorrent,sabnzbd}  (events, downloads)
#   domains/media/{calibre,readarr,books,slskd} (downloads/*)
#   domains/media/orchestration          (downloads/{books,scripts})
#   domains/media/frigate + machines/server/config.nix:701 (surveillance/frigate/buffer)
#   domains/ai/local-workflows + machines/server/config.nix:554 (inbox)
#
# Paths are recorded RELATIVE to HOT_ROOT/MEDIA_ROOT so the same data set
# works for the live /mnt and the scratch-fixture self-test. is_protected()
# expands them at runtime.
#
# IMPORTANT: HOT_ROOT and MEDIA_ROOT themselves are NOT in these lists — the
# hard-rail in is_protected() refuses the roots directly. Listing HOT_ROOT
# here would make every descendant (including legitimate orphans) appear
# protected, which would inert the whole script.
ACTIVE_HOT_RELS=(
  "appdata"
  "backups"
  "cache"
  "documents"
  "downloads"
  "events"
  "inbox"
  "processing"
  "receipts"
  "surveillance"
  "youtube-transcripts"
)
ACTIVE_MEDIA_RELS=()

# ORPHAN ROUTES — from a fresh read-only walk of /mnt/hot on 2026-06-24.
# Format: "<orphan path under HOT_ROOT>|<destination path under MEDIA_ROOT>"
# Each orphan src is NOT under an ACTIVE path (asserted at runtime).
# /mnt/hot/ai (Ollama models / ssh keypair) is intentionally OMITTED — it is
# service state, not media; route it manually after a /opt/ai parity check.
ORPHAN_ROUTES=(
  "library|books"
  "transcript-text|transcripts"
  "games|retroarch"
)

# ----------------------------- helpers ---------------------------------------

log() { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

# normalize PATH → realpath -m (does not require existence).
normalize() { realpath -m -- "$1"; }

# Expand the relative active sets into absolute paths once, after the roots
# are known.
build_active_paths() {
  ACTIVE_PATHS=()
  local r
  for r in "${ACTIVE_HOT_RELS[@]}"; do
    ACTIVE_PATHS+=("$(normalize "$HOT_ROOT/$r")")
  done
  # ACTIVE_MEDIA_RELS may be empty; only expand if non-empty.
  if (( ${#ACTIVE_MEDIA_RELS[@]} > 0 )); then
    for r in "${ACTIVE_MEDIA_RELS[@]}"; do
      ACTIVE_PATHS+=("$(normalize "$MEDIA_ROOT/$r")")
    done
  fi
}

# is_protected PATH
# Exit 0 if PATH equals or is a descendant of any ACTIVE path,
# or if PATH is one of the hard rails (HOT_ROOT, MEDIA_ROOT, /).
is_protected() {
  local target hot_n media_n
  target="$(normalize "$1")"
  hot_n="$(normalize "$HOT_ROOT")"
  media_n="$(normalize "$MEDIA_ROOT")"

  if [[ "$target" == "/" || "$target" == "$hot_n" || "$target" == "$media_n" ]]; then
    return 0
  fi

  local ap
  for ap in "${ACTIVE_PATHS[@]}"; do
    if [[ "$target" == "$ap" || "$target" == "$ap"/* ]]; then
      return 0
    fi
  done
  return 1
}

# act CMD ARGS...
# DRY_RUN=1: echo only. DRY_RUN=0: echo then execute.
act() {
  if [[ "$DRY_RUN" == "1" ]]; then
    log "DRY-RUN would run: $*"
  else
    log "RUN: $*"
    "$@"
  fi
}

guard_or_skip() {
  local p="$1" reason="$2"
  if is_protected "$p"; then
    log "SKIP (protected: $reason): $p"
    return 1
  fi
  return 0
}

# ----------------------------- preflight -------------------------------------

log "reconcile.sh starting; DRY_RUN=$DRY_RUN; log=$LOG_FILE"
log "HOT_ROOT=$HOT_ROOT MEDIA_ROOT=$MEDIA_ROOT"

if [[ ! -d "$HOT_ROOT" ]]; then
  log "FATAL: HOT_ROOT does not exist: $HOT_ROOT"
  exit 2
fi
if [[ ! -d "$MEDIA_ROOT" ]]; then
  log "FATAL: MEDIA_ROOT does not exist: $MEDIA_ROOT"
  exit 2
fi

build_active_paths

# Guard self-check: each of these must be protected. If any aren't, the
# data is broken and we refuse to proceed.
for must_be_protected in \
  "$HOT_ROOT" "$MEDIA_ROOT" \
  "$HOT_ROOT/downloads" \
  "$HOT_ROOT/downloads/incomplete" \
  "$HOT_ROOT/surveillance" \
  "$HOT_ROOT/backups"
do
  if ! is_protected "$must_be_protected"; then
    log "FATAL: guard self-check failed — not protected: $must_be_protected"
    exit 3
  fi
done
log "guard self-check passed (${#ACTIVE_PATHS[@]} active paths)"

# ----------------------------- phase 1: consolidate (MOVE) -------------------

log "=== PHASE 1: MOVE stray media from $HOT_ROOT orphans into $MEDIA_ROOT ==="
log "    semantics: rsync --remove-source-files removes each source file ONLY"
log "    after rsync verifies the destination byte-stream matches the source."

for route in "${ORPHAN_ROUTES[@]}"; do
  src_rel="${route%%|*}"
  dst_rel="${route##*|}"
  src="$HOT_ROOT/$src_rel"
  dst="$MEDIA_ROOT/$dst_rel"

  if [[ ! -d "$src" ]]; then
    log "skip (orphan dir missing): $src"
    continue
  fi

  # Defense in depth: the src is, by definition, an orphan — but verify.
  if is_protected "$src"; then
    log "SKIP (orphan path is somehow protected — fix data first): $src"
    continue
  fi

  # The dst must be under MEDIA_ROOT.
  dst_norm="$(normalize "$dst")"
  media_norm="$(normalize "$MEDIA_ROOT")"
  if [[ "$dst_norm" != "$media_norm"/* ]]; then
    log "SKIP (destination not under $MEDIA_ROOT): $dst"
    continue
  fi

  log "consolidate (MOVE): $src  ->  $dst"
  act mkdir -p -- "$dst"

  # rsync flags chosen for verified MOVE + idempotent re-run:
  #   -a                     preserve mode/owner/group/times/symlinks
  #   --remove-source-files  delete each source FILE only after the
  #                          destination is verified byte-identical
  #                          (rsync's internal checksum-or-rolling-verify);
  #                          this is what makes phase 1 a real MOVE.
  #   --ignore-existing      never overwrite a file already at the dst,
  #                          but the source file is STILL removed if rsync
  #                          considers it already-transferred — wait, that
  #                          is not what --ignore-existing does. To get
  #                          dedupe-and-remove behavior for already-present
  #                          dst files, we DO NOT pass --ignore-existing;
  #                          instead rsync's default skip-if-same (size+mtime)
  #                          handles re-runs as no-ops (source already gone).
  #   --human-readable / --stats / --info=name,stats2  informative log
  act rsync -a --remove-source-files --human-readable --stats \
    --info=name,stats2 -- "$src"/ "$dst"/
done

# ----------------------------- phase 2: prune empty orphans ------------------

log "=== PHASE 2: remove orphan dirs that are now empty of media ==="

MEDIA_GLOBS=(
  "*.mkv" "*.mp4" "*.avi" "*.mov" "*.m4v" "*.webm"
  "*.mp3" "*.flac" "*.m4a" "*.m4b" "*.opus" "*.ogg" "*.wav"
  "*.epub" "*.mobi" "*.azw3" "*.pdf" "*.cbz" "*.cbr"
  "*.iso" "*.zip" "*.7z" "*.rar"
  "*.srt" "*.ass" "*.vtt"
  "*.jpg" "*.jpeg" "*.png"
)

# has_media DIR — exit 0 if any file matching MEDIA_GLOBS exists under DIR.
has_media() {
  local d="$1" g
  for g in "${MEDIA_GLOBS[@]}"; do
    if find "$d" -type f -iname "$g" -print -quit 2>/dev/null | grep -q .; then
      return 0
    fi
  done
  return 1
}

for route in "${ORPHAN_ROUTES[@]}"; do
  src_rel="${route%%|*}"
  src="$HOT_ROOT/$src_rel"

  if [[ ! -d "$src" ]]; then
    log "skip (already gone): $src"
    continue
  fi

  if ! guard_or_skip "$src" "active path"; then
    continue
  fi

  if has_media "$src"; then
    log "KEEP (orphan still contains media; phase 1 left files behind): $src"
    continue
  fi

  log "prune (empty of media): $src"
  act rm -rf -- "$src"
done

log "reconcile.sh done; DRY_RUN=$DRY_RUN; see $LOG_FILE"
