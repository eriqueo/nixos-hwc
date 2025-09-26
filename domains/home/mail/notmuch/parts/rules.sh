#!/usr/bin/env bash
set -euo pipefail

# Notmuch tagging rules — folder-based (robust with [Gmail]/[Google Mail] names)
tag() { notmuch tag "$@"; }

# 0) Normalize special folders → canonical tags
# Proton
tag +sent    -inbox -unread -- 'folder:"proton/Sent"'
tag +trash   -inbox -unread -- 'folder:"proton/Trash"'
tag +spam    -inbox -unread -- 'folder:"proton/Spam"'
tag +archive -inbox         -- 'folder:"proton/Archive" OR folder:"proton/All Mail"'
tag +draft   -inbox -unread -- 'folder:"proton/Drafts"'

# Gmail (handle both “[Gmail]” and “[Google Mail]” namespaces)
tag +sent    -inbox -unread -- 'folder:"gmail-*/[Gmail]/Sent Mail"     OR folder:"gmail-*/[Google Mail]/Sent Mail"'
tag +trash   -inbox -unread -- 'folder:"gmail-*/[Gmail]/Trash"         OR folder:"gmail-*/[Google Mail]/Trash"'
tag +spam    -inbox -unread -- 'folder:"gmail-*/[Gmail]/Spam"          OR folder:"gmail-*/[Google Mail]/Spam"'
tag +archive -inbox         -- 'folder:"gmail-*/[Gmail]/All Mail"      OR folder:"gmail-*/[Google Mail]/All Mail"'
tag +draft   -inbox -unread -- 'folder:"gmail-*/[Gmail]/Drafts"        OR folder:"gmail-*/[Google Mail]/Drafts"'

# 1) Newsletters
# If you rely on List-Id, uncomment the next line (works well on most lists):
# tag +newsletter -inbox -- 'list:*'
# Sender/domain heuristics (expanded by Nix):
__NEWSLETTER_BLOCK__

# 2) Notifications / bots / no-reply (expanded by Nix):
__NOTIFICATION_BLOCK__

# 3) Finance (receipts/statements) (expanded by Nix):
__FINANCE_BLOCK__

# 4) Action-worthy subjects (expanded by Nix):
__ACTION_SUBJECT_BLOCK__

# 5) Safety: don't mix system folders into categories
tag -action -newsletter -notification -- 'tag:sent OR tag:trash OR tag:spam OR tag:draft'
