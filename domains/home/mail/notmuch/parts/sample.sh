#!/usr/bin/env bash
set -euo pipefail
MAILROOT="$(notmuch config get database.path)"
mapfile -t ACCS < <(find "$MAILROOT" -mindepth 2 -maxdepth 2 -type d -iname INBOX -printf '%P\n' | awk -F/ '{print $1}' | sort -u)
for ACC in "${ACCS[@]}"; do
  out="$HOME/${ACC}_inbox_sample.txt"
  notmuch search --output=files --limit=200 "tag:inbox and path:${ACC}/INBOX/*" > "$out" || true
  notmuch show --format=raw --entire-thread=false "tag:inbox and path:${ACC}/INBOX/*" \
    | rg -i '^From:' | sed 's/^From:\s*//' | sort | uniq -c | sort -nr | head -n 30 > "$HOME/${ACC}_inbox_top_senders.txt" || true
done
printf '%s\n' "${ACCS[@]}"
