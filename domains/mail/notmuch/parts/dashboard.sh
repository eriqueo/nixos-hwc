#!/usr/bin/env bash
set -euo pipefail
last="$(date -r "${XDG_CACHE_HOME:-$HOME/.cache}/notmuch/.last-dashboard" +'%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
touch -d '1970-01-01' "${XDG_CACHE_HOME:-$HOME/.cache}/notmuch/.last-dashboard" 2>/dev/null || true
echo "Email Dashboard  Last checked: ${last:-never}"
echo
printf "INBOX: %s\n" "$(notmuch count 'tag:inbox and tag:unread')"
printf "Action: %s\n" "$(notmuch count 'tag:action and tag:unread')"
printf "Finance: %s\n" "$(notmuch count 'tag:finance and tag:unread')"
printf "Newsletters: %s\n" "$(notmuch count 'tag:newsletter and tag:unread')"
printf "Notifications: %s\n" "$(notmuch count 'tag:notification and tag:unread')"
echo
stale="$(notmuch count 'tag:action and date:..7d')"
if [ "${stale}" -gt 0 ]; then
  echo "Stale action items (>7d): ${stale}"
fi
mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/notmuch"
date +%s > "${XDG_CACHE_HOME:-$HOME/.cache}/notmuch/.last-dashboard"
