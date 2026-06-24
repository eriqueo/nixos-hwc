#!/usr/bin/env bash
# reconcile.sh — consolidate stray media from /mnt/hot orphans into /mnt/media,
# then prune verified-empty orphan dirs. Dry-run by default.
#
# Generated 2026-06-24 by the nightly-builds gauntlet card
# "03 — reconcile script generator". DO NOT run blindly. See
# docs/audits/mnt-hot/reconcile-checklist.md for the human run procedure.
#
# Contract (enforced below):
#   1. set -euo pipefail
#   2. DRY_RUN defaults to 1 (echo-only). Set DRY_RUN=0 to act.
#   3. is_protected() refuses to touch any path equal to or under an ACTIVE path.
#   4. /mnt/hot and /mnt/media themselves are never `rm` targets.
#   5. Consolidate phase uses rsync --ignore-existing so a re-run is a no-op.
#   6. Delete phase only removes orphan dirs that are empty of media AND outside
#      every active path.
#   7. Every destructive line is preceded by an `echo` of the intended action.
#   8. All output is also appended to a timestamped logfile.

set -euo pipefail

# ----------------------------- configuration ---------------------------------

DRY_RUN="${DRY_RUN:-1}"
HOT_ROOT="/mnt/hot"
MEDIA_ROOT="/mnt/media"

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
#   domains/media/{qbittorrent,sabnzbd}/parts/config.nix (events, downloads)
#   domains/media/{calibre,readarr,books,slskd,beets-container}/sys.nix (downloads/*)
#   domains/media/orchestration/* (downloads/{books,scripts})
#   domains/media/frigate/* + machines/server/config.nix (surveillance/frigate/buffer)
#   domains/media/youtube/* (youtube-transcripts)
#   domains/ai/local-workflows/index.nix + machines/server/config.nix:543 (inbox)
#   container appdata caches under /mnt/hot/cache and /mnt/hot/appdata are
#     treated as ACTIVE (live container state) even though some are
#     undeclared — protective default, not asserted by nix.
ACTIVE_PATHS=(
  "/mnt/hot"
  "/mnt/media"
  "/mnt/hot/appdata"
  "/mnt/hot/backups"
  "/mnt/hot/cache"
  "/mnt/hot/documents"
  "/mnt/hot/downloads"
  "/mnt/hot/events"
  "/mnt/hot/inbox"
  "/mnt/hot/processing"
  "/mnt/hot/receipts"
  "/mnt/hot/surveillance"
  "/mnt/hot/youtube-transcripts"
)

# ORPHAN ROUTES — from a fresh read-only walk of /mnt/hot on 2026-06-24.
# Format: "<orphan dir>|<media destination>"
# Each orphan dir is a TOP-LEVEL /mnt/hot entry NOT present in ACTIVE_PATHS.
# /mnt/hot/ai (models/ollama) is intentionally OMITTED: its content is service
# state, not media — review separately before adding here.
ORPHAN_ROUTES=(
  "/mnt/hot/library|/mnt/media/books"
  "/mnt/hot/transcript-text|/mnt/media/transcripts"
  "/mnt/hot/games|/mnt/media/retroarch"
)

# ----------------------------- helpers ---------------------------------------

log() { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

# Normalize a path: strip trailing slashes, collapse //, resolve via realpath -m
# (does not require the path to exist).
normalize() {
  local p="$1"
  p="$(realpath -m -- "$p")"
  printf '%s' "$p"
}

# is_protected PATH
# True (exit 0) if PATH equals or is a descendant of any ACTIVE path,
# OR if PATH equals /mnt/hot or /mnt/media themselves.
# False otherwise.
is_protected() {
  local target
  target="$(normalize "$1")"

  # Hard rails: the storage roots themselves are never valid `rm` targets.
  if [[ "$target" == "/mnt/hot" || "$target" == "/mnt/media" || "$target" == "/" ]]; then
    return 0
  fi

  local ap apn
  for ap in "${ACTIVE_PATHS[@]}"; do
    apn="$(normalize "$ap")"
    if [[ "$target" == "$apn" || "$target" == "$apn"/* ]]; then
      return 0
    fi
  done
  return 1
}

# act CMD ARGS...
# In DRY_RUN mode: echo the command. Otherwise: echo, then execute.
act() {
  if [[ "$DRY_RUN" == "1" ]]; then
    log "DRY-RUN would run: $*"
  else
    log "RUN: $*"
    "$@"
  fi
}

# guard_or_skip PATH REASON
# Returns 0 if path is safe to touch; 1 if protected (and logs the skip).
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
  log "FATAL: $HOT_ROOT does not exist"
  exit 2
fi
if [[ ! -d "$MEDIA_ROOT" ]]; then
  log "FATAL: $MEDIA_ROOT does not exist"
  exit 2
fi

# Sanity-check the guard. If any of these are NOT protected, abort — the
# active-paths data is broken and we must not proceed.
for must_be_protected in \
  "/mnt/hot" "/mnt/media" \
  "/mnt/hot/downloads" "/mnt/hot/downloads/incomplete" \
  "/mnt/hot/surveillance/frigate/buffer" \
  "/mnt/hot/processing/tdarr-temp" \
  "/mnt/hot/backups/databases" \
  "/mnt/hot/cache/jellyfin"
do
  if ! is_protected "$must_be_protected"; then
    log "FATAL: guard self-check failed — $must_be_protected is not protected"
    exit 3
  fi
done
log "guard self-check passed"

# ----------------------------- phase 1: consolidate --------------------------

log "=== PHASE 1: consolidate stray media into $MEDIA_ROOT ==="

for route in "${ORPHAN_ROUTES[@]}"; do
  src="${route%%|*}"
  dst="${route##*|}"

  if [[ ! -d "$src" ]]; then
    log "skip (orphan dir missing): $src"
    continue
  fi

  # The src is, by definition, outside every active path — but verify.
  if is_protected "$src"; then
    log "SKIP (orphan declared active by guard — fix data first): $src"
    continue
  fi

  # The dst must be under MEDIA_ROOT.
  dst_norm="$(normalize "$dst")"
  if [[ "$dst_norm" != "$MEDIA_ROOT"/* ]]; then
    log "SKIP (destination not under $MEDIA_ROOT): $dst"
    continue
  fi

  log "consolidate: $src  ->  $dst"
  act mkdir -p -- "$dst"

  # rsync flags chosen for idempotency:
  #   -a              : preserve mode/owner/group/times/symlinks
  #   --ignore-existing: never overwrite a file already present at dst (idempotent)
  #   --human-readable / --stats : informative log entries
  #   --info=name,stats2 : per-file name + summary
  # NOTE: we COPY (rsync) rather than MOVE in phase 1. Phase 2 only removes the
  # source dir if it is empty of media — meaning rsync took everything that
  # belongs at the destination. Anything left behind is by definition out of
  # scope for this routing and stays put.
  act rsync -a --ignore-existing --human-readable --stats \
    --info=name,stats2 -- "$src"/ "$dst"/
done

# ----------------------------- phase 2: prune --------------------------------

log "=== PHASE 2: remove verified-empty orphan dirs ==="

# Media-file extensions we care about for "is this dir empty of media?".
# Anything matching this list inside an orphan dir means the orphan still
# holds media we did not consolidate — DO NOT delete it.
MEDIA_GLOBS=(
  "*.mkv" "*.mp4" "*.avi" "*.mov" "*.m4v" "*.webm"
  "*.mp3" "*.flac" "*.m4a" "*.m4b" "*.opus" "*.ogg" "*.wav"
  "*.epub" "*.mobi" "*.azw3" "*.pdf"
  "*.iso" "*.zip" "*.7z" "*.rar"
  "*.srt" "*.ass" "*.vtt"
)

# has_media DIR
# Exit 0 if DIR contains any file matching MEDIA_GLOBS (recursively).
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
  src="${route%%|*}"

  if [[ ! -d "$src" ]]; then
    log "skip (already gone): $src"
    continue
  fi

  # Guard: never `rm` anything protected. This is the final hard rail.
  if ! guard_or_skip "$src" "active path"; then
    continue
  fi

  if has_media "$src"; then
    log "KEEP (orphan still contains media; phase 1 left files): $src"
    continue
  fi

  # At this point the orphan dir is outside every active path AND has no
  # media files left. Remove it. We use `rm -rf` to clear residual empty
  # subdirs and incidental dotfiles (e.g. .DS_Store).
  log "prune empty orphan dir: $src"
  act rm -rf -- "$src"
done

log "reconcile.sh finished; DRY_RUN=$DRY_RUN; log=$LOG_FILE"
