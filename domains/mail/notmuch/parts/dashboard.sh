#!/usr/bin/env bash
set -euo pipefail
last="$(date -r "${XDG_CACHE_HOME:-$HOME/.cache}/notmuch/.last-dashboard" +'%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
touch -d '1970-01-01' "${XDG_CACHE_HOME:-$HOME/.cache}/notmuch/.last-dashboard" 2>/dev/null || true
echo "Email Dashboard  Last checked: ${last:-never}"
echo
printf "INBOX: %s\n" "$(notmuch count 'tag:inbox and tag:unread')"
printf "DO: %s\n" "$(notmuch count '@DO_QUERY@ and tag:unread')"
printf "Finance: %s\n" "$(notmuch count '@FINANCE_QUERY@ and tag:unread')"
printf "Newsletters: %s\n" "$(notmuch count '@NEWSLETTER_QUERY@ and tag:unread')"
printf "Security: %s\n" "$(notmuch count '@SECURITY_QUERY@ and tag:unread')"
echo
stale="$(notmuch count '@DO_QUERY@ and date:..7d')"
if [ "${stale}" -gt 0 ]; then
  echo "Stale DO items (>7d): ${stale}"
fi
mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/notmuch"
date +%s > "${XDG_CACHE_HOME:-$HOME/.cache}/notmuch/.last-dashboard"
