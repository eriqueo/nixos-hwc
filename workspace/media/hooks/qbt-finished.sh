#!/bin/sh
# qBittorrent external program hook; write a line to /mnt/hot/events/qbt.ndjson
# Expected args from qBittorrent: "%N" "%I" "%L" "%F"
set -eu
SPOOL="/mnt/hot/events/qbt.ndjson"
TS=$(date +%s)
NAME="${1:-}"; HASH="${2:-}"; CAT="${3:-}"; PATHP="${4:-}"
[ -n "$NAME" ] || exit 0
printf '{"client":"qbt","time":%s,"name":"%s","hash":"%s","category":"%s","content_path":"%s"}\n' \
  "$TS" "$NAME" "$HASH" "$CAT" "$PATHP" >> "$SPOOL"
