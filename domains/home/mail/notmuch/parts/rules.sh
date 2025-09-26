#!/usr/bin/env bash
set -euo pipefail

# Helper
tag() { notmuch tag "$@"; }

# ---- Special folders → tags (use EXACT folder: paths) ----
# SENT
tag +sent   -inbox -unread -- \
  'folder:"proton/Sent" \
   OR folder:"gmail-personal/[Gmail]/Sent Mail"  OR folder:"gmail-business/[Gmail]/Sent Mail" \
   OR folder:"gmail-personal/[Google Mail]/Sent Mail" OR folder:"gmail-business/[Google Mail]/Sent Mail"'

# TRASH
tag +trash  -inbox -unread -- \
  'folder:"proton/Trash" \
   OR folder:"gmail-personal/[Gmail]/Trash"  OR folder:"gmail-business/[Gmail]/Trash" \
   OR folder:"gmail-personal/[Google Mail]/Trash" OR folder:"gmail-business/[Google Mail]/Trash"'

# SPAM
tag +spam   -inbox -unread -- \
  'folder:"proton/Spam" \
   OR folder:"gmail-personal/[Gmail]/Spam"   OR folder:"gmail-business/[Gmail]/Spam"  \
   OR folder:"gmail-personal/[Google Mail]/Spam"  OR folder:"gmail-business/[Google Mail]/Spam"'

# DRAFTS
tag +draft  -inbox -unread -- \
  'folder:"proton/Drafts" \
   OR folder:"gmail-personal/[Gmail]/Drafts" OR folder:"gmail-business/[Gmail]/Drafts" \
   OR folder:"gmail-personal/[Google Mail]/Drafts" OR folder:"gmail-business/[Google Mail]/Drafts"'

# ARCHIVE / ALL MAIL
tag +archive -inbox -- \
  'folder:"proton/Archive" OR folder:"proton/All Mail" \
   OR folder:"gmail-personal/[Gmail]/All Mail"  OR folder:"gmail-business/[Gmail]/All Mail" \
   OR folder:"gmail-personal/[Google Mail]/All Mail" OR folder:"gmail-business/[Google Mail]/All Mail"'

# (your newsletter / notification / finance / action sections can stay as-is)
# Safety: don't classify system folders as action/newsletter/etc.
tag -action -newsletter -notification -- 'tag:sent OR tag:trash OR tag:spam OR tag:draft'
