#!/usr/bin/env bash
# Beets Container Helper - Wrapper to run beets commands in container
# This version automatically detects and uses the beets container

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() {
  echo -e "${BLUE}ℹ${NC} $*"
}

success() {
  echo -e "${GREEN}✅${NC} $*"
}

error() {
  echo -e "${RED}❌${NC} $*"
}

# Find beets container
CONTAINER_NAME=$(podman ps --filter ancestor=lscr.io/linuxserver/beets --format "{{.Names}}" 2>/dev/null | head -1)

if [ -z "$CONTAINER_NAME" ]; then
  error "Beets container not found!"
  echo ""
  echo "Available containers:"
  podman ps --format "table {{.Names}}\t{{.Image}}"
  echo ""
  echo "Is the beets container running?"
  echo "  sudo systemctl status podman-beets"
  exit 1
fi

info "Found beets container: $CONTAINER_NAME"
echo ""

# Run command in container
case "${1:-help}" in
  analyze|analyze-library)
    info "Analyzing library in container..."
    echo ""
    podman exec "$CONTAINER_NAME" bash -c '
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "BEETS LIBRARY ANALYSIS"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo ""
      echo "📊 Library Statistics:"
      beet stats -e
      echo ""
      echo "🔍 Duplicates:"
      beet duplicates | head -20
      echo ""
      echo "🎨 Albums Missing Art:"
      beet ls -a artpath:: | wc -l
      echo ""
      echo "❓ Unmatched Items:"
      beet ls mb_albumid:: | wc -l
      echo ""
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    '
    ;;

  duplicates|dupes)
    info "Finding duplicates..."
    podman exec "$CONTAINER_NAME" beet duplicates -k
    ;;

  update)
    info "Updating database from filesystem..."
    podman exec "$CONTAINER_NAME" beet update
    success "Database updated!"
    ;;

  stats)
    info "Library statistics..."
    podman exec "$CONTAINER_NAME" beet stats -e
    ;;

  fetchart)
    info "Fetching album art..."
    podman exec "$CONTAINER_NAME" beet fetchart -q
    success "Album art fetched!"
    ;;

  embedart)
    info "Embedding album art..."
    podman exec "$CONTAINER_NAME" beet embedart -q
    success "Album art embedded!"
    ;;

  shell|bash)
    info "Opening shell in container..."
    echo "Type 'exit' to return"
    echo ""
    podman exec -it "$CONTAINER_NAME" bash
    ;;

  *)
    cat <<EOF
Beets Container Helper

Automatically runs beets commands inside the container.

USAGE:
  $0 <command>

COMMANDS:
  analyze          Comprehensive library analysis
  duplicates       Find duplicate tracks
  update           Update database from filesystem (fixes orphaned entries)
  stats            Show library statistics
  fetchart         Download album artwork
  embedart         Embed artwork into files
  shell            Open bash shell in container

EXAMPLES:
  # Analyze library
  $0 analyze

  # Find duplicates
  $0 duplicates

  # Fix orphaned database entries
  $0 update

  # Get shell to run any beet command
  $0 shell

INSIDE SHELL:
  beet update                    # Fix orphaned entries
  beet duplicates -k             # Find duplicates by checksum
  beet fetchart -q               # Download all missing art
  beet ls artist:Ween            # Search library
  beet stats -e                  # Extended statistics

Container: $CONTAINER_NAME
EOF
    ;;
esac
