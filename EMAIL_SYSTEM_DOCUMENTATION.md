# Email System Technical Documentation

**Date**: October 7, 2025
**System Owner**: Eric
**Architecture**: Unified Inbox with Multi-Account Sync

---

## System Overview

A GTD-style unified inbox email system that consolidates mail from 4 email accounts into a single inbox view, with color-coded visual differentiation by source account and notmuch-based tagging for advanced filtering.

---

## Architecture Components

### 1. Email Accounts

| Account | Type | Address | Purpose | Bridge/Protocol |
|---------|------|---------|---------|-----------------|
| iheartwoodcraft | Proton | eric@iheartwoodcraft.com | Work primary | Proton Bridge (IMAP) |
| proton | Proton | eriqueo@proton.me | Personal (same account as iheartwoodcraft) | Proton Bridge (IMAP) |
| gmail-business | Gmail | heartwoodcraftmt@gmail.com | Work secondary | Direct IMAP |
| gmail-personal | Gmail | eriqueokeefe@gmail.com | Personal primary | Direct IMAP |

**Note**: iheartwoodcraft and proton are the same Proton account with two email addresses configured as aliases.

### 2. Software Stack

| Component | Tool | Purpose |
|-----------|------|---------|
| **Mail Client** | aerc 0.21.0 | Terminal-based email client with vim-like keybindings |
| **Sync Engine** | mbsync (isync 1.5.1) | Bidirectional IMAP ↔ Maildir synchronization |
| **Bridge** | Proton Bridge 3.21.2 | Exposes Proton Mail via local IMAP/SMTP servers |
| **Indexing/Search** | notmuch 5.6.0 | Fast email indexing, tagging, and search |
| **Sending** | msmtp | SMTP client for outgoing mail |
| **Password Store** | pass | GPG-encrypted password management |

---

## Data Flow

```
┌─────────────────────────────────────────────────────────────┐
│                   REMOTE EMAIL SERVERS                       │
├─────────────────────────────────────────────────────────────┤
│  Gmail IMAP          Gmail IMAP         Proton Bridge       │
│  (business)          (personal)         (IMAP localhost)    │
│      ↓                   ↓                    ↓             │
└──────┬───────────────────┬────────────────────┬─────────────┘
       │                   │                    │
       └───────────────────┴────────────────────┘
                           ↓
              ┌────────────────────────┐
              │   mbsync (isync)       │
              │   - Runs every 5min    │
              │   - Bidirectional sync │
              └────────────────────────┘
                           ↓
              ┌────────────────────────┐
              │  ~/Maildir/            │
              │  (Unified Structure)   │
              ├────────────────────────┤
              │  000_inbox/            │ ← ALL accounts INBOX
              │  010_sent/             │ ← ALL accounts Sent
              │  011_drafts/           │ ← ALL accounts Drafts
              │  210_pers-important/   │ ← Gmail Starred (personal)
              │  800_spam/             │ ← ALL accounts Spam
              │  900_trash/            │ ← ALL accounts Trash
              │  Labels/               │ ← Proton labels
              └────────────────────────┘
                           ↓
              ┌────────────────────────┐
              │   notmuch new          │
              │   - Indexes mail       │
              │   - Applies tags       │
              │   - Post-sync hook     │
              └────────────────────────┘
                           ↓
              ┌────────────────────────┐
              │   aerc                 │
              │   - Displays mail      │
              │   - Color codes        │
              │   - Unified view       │
              └────────────────────────┘
```

---

## Folder Structure

### Unified Maildir Layout

```
~/Maildir/
├── .notmuch/              # notmuch database
├── 000_inbox/             # Unified inbox (ALL accounts)
│   ├── cur/              # Read messages
│   ├── new/              # Unread messages
│   └── tmp/              # Temp during delivery
├── 010_sent/              # Global sent folder
├── 011_drafts/            # Global drafts folder
├── 210_pers-important/    # Gmail Starred (personal)
├── 800_spam/              # Global spam folder
├── 900_trash/             # Global trash folder
└── Labels/                # Proton labels (aerc, proton)
    ├── aerc/
    └── proton/
```

**Design Principles**:
- 3-digit numbering scheme (000-999)
- Domain prefixes: 0xx=global, 1xx=work, 2xx=personal, 8xx=system, 9xx=trash
- Underscore separators for readability
- ALL inboxes map to single `000_inbox` (GTD unified inbox)
- Per-domain archives removed to avoid syncing massive Gmail "All Mail"

---

## mbsync Configuration

### Channel Mapping Strategy

Each email account has **multiple channels** - one per IMAP folder being synced. Channels map remote IMAP folders to local Maildir folders.

**Example (iheartwoodcraft)**:
```
Channel iheartwoodcraft-INBOX
  Far: :iheartwoodcraft-remote:"INBOX"
  Near: :iheartwoodcraft-local:"000_inbox"

Channel iheartwoodcraft-Sent
  Far: :iheartwoodcraft-remote:"Sent"
  Near: :iheartwoodcraft-local:"010_sent"
```

### Key Configuration Details

**MaildirStore Path**: All accounts point to `/home/eric/Maildir/` (root) with shared `Inbox = /home/eric/Maildir/000_inbox`

**Gmail-specific**:
- `Create Near` policy (only create local folders, not on server)
- Escaped brackets for folder names: `[Gmail]/Sent Mail` → `"\[Gmail\]/Sent Mail"`
- **Gmail All Mail excluded** to prevent syncing entire archive (tens of thousands of duplicate messages)

**Proton Bridge**:
- Local IMAP server: `127.0.0.1:1143`
- Password stored in `pass` at `email/proton/bridge`
- Requires bridge service running: `systemctl --user start protonmail-bridge.service`

### Sync State Management

- State files: `~/.mbsync/` and `~/Maildir/<folder>/.mbsyncstate*`
- UIDVALIDITY tracking in `~/Maildir/<folder>/.uidvalidity`
- Lock file: `~/.cache/mbsync.lock`

**Important**: Changing folder structure requires clearing state files to avoid UIDVALIDITY errors.

---

## notmuch Configuration

### Tagging Strategy

Currently **broken** due to unified folder architecture. Original tags relied on per-account folder paths:

```bash
# OLD (non-functional with unified folders)
notmuch tag +hwc_email -- 'path:100_hwc/**'
notmuch tag +gmail_work -- 'path:110_gmail-business/**'
notmuch tag +gmail_personal -- 'path:200_personal/**'
notmuch tag +proton_personal -- 'path:210_proton/**'
```

**Problem**: Per-account paths no longer exist. All mail is in `000_inbox`, so path-based tagging fails.

**Current fallback**: Tags applied by sender address:
```bash
notmuch tag +hwc_email -- 'from:*@iheartwoodcraft.com'
notmuch tag +gmail_work -- 'from:*heartwoodcraftmt@gmail.com'
notmuch tag +gmail_personal -- 'from:*eriqueokeefe@gmail.com'
notmuch tag +proton_personal -- 'from:*@proton.me'
```

**Limitation**: Sender-based tagging doesn't work for:
- Emails you send yourself
- Emails from external senders to multiple of your addresses
- Mailing lists

### Database Location

- Database: `~/Maildir/.notmuch/`
- Config: `~/.notmuch-config`
- Runs after every mbsync via systemd hook

---

## aerc Configuration

### Account Configuration

All accounts share the same `source = maildir:///home/eric/Maildir` - each account is just a **sending identity**.

```ini
[iheartwoodcraft]
from = Eric <eric@iheartwoodcraft.com>
source = maildir:///home/eric/Maildir
outgoing = exec:msmtp -a iheartwoodcraft
postpone = maildir:///home/eric/Maildir/011_drafts
copy-to = maildir:///home/eric/Maildir/010_sent

[gmail-business]
from = Eric O'Keefe <heartwoodcraftmt@gmail.com>
source = maildir:///home/eric/Maildir
outgoing = exec:msmtp -a gmail-business
postpone = maildir:///home/eric/Maildir/011_drafts
copy-to = maildir:///home/eric/Maildir/010_sent
```

### Color Coding (Dynamic Styling)

Messages are color-coded by sender email address using header-based pattern matching:

**Work Domain (Blue Spectrum)**:
```ini
msglist_*.From,~/@iheartwoodcraft\\.com/.fg = #5DA0DE    # Light blue
msglist_*.From,~/heartwoodcraftmt@gmail\\.com/.fg = #2563EB  # Dark blue
```

**Personal Domain (Purple Spectrum)**:
```ini
msglist_*.From,~/eriqueokeefe@gmail\\.com/.fg = #C084FC   # Light purple
msglist_*.From,~/@proton\\.me/.fg = #9333EA               # Dark purple
```

**Syntax**: `msglist_*.Header,~/regex/.attribute = value`

### Keybindings

**Navigation** (`<Space>g` prefix):
```
<Space>gi  → :cf 000_inbox        # Go to unified inbox
<Space>gs  → :cf 010_sent         # Go to sent
<Space>gd  → :cf 011_drafts       # Go to drafts
```

**Filing** (`<Space>m` prefix):
```
<Space>mi  → :mv 210_pers-important  # Move to important
```

---

## Systemd Automation

### mbsync Service

**Unit**: `mbsync.service`
**Timer**: `mbsync.timer` (runs every 5 minutes)

```ini
[Service]
ExecStartPre = /usr/bin/mkdir -p %h/.cache
ExecStart = /usr/bin/flock -n %h/.cache/mbsync.lock -c 'mbsync -a'
ExecStartPost = /usr/bin/bash -lc 'notmuch new || true'
TimeoutStartSec = 1h
```

**Flow**:
1. Lock acquired via `flock` to prevent concurrent syncs
2. `mbsync -a` syncs all accounts
3. `notmuch new` indexes new mail and applies tags
4. Timer triggers next sync in 5 minutes

---

## Current Issues

### 1. **Duplicate Messages**

**Symptom**: Same email appearing 4-8 times in unified inbox.

**Root Cause**: Emails sent to multiple addresses (e.g., both gmail-personal and iheartwoodcraft) are synced from each account into the same 000_inbox folder as separate files.

**Example**: "Toy Trains Newsletter" exists 8 times because it was delivered to multiple email addresses.

**Impact**: Cluttered inbox, wasted storage.

### 2. **Broken Account Tagging**

**Symptom**: Cannot filter by source account reliably.

**Root Cause**: Path-based tagging (`path:100_hwc/**`) no longer works with unified folders. Sender-based tagging (`from:*@iheartwoodcraft.com`) fails for:
- Self-sent emails
- Emails from senders to multiple addresses
- Mailing lists

**Impact**: Cannot determine which account received a message.

### 3. **No Visual Account Indicator**

**Symptom**: Can't tell at a glance which account received an email (beyond color, which is sender-based).

**Root Cause**: aerc message list doesn't show account/folder metadata for unified inbox.

**Impact**: Difficult to manage multiple identities.

### 4. **Proton Bridge Cache Corruption**

**Symptom**: Bridge periodically loses account configuration, requires re-login.

**Root Cause**: Bridge vault encryption failures during restart.

**Workaround**: Delete `~/.local/share/protonmail/bridge-v3/gluon/` and restart bridge.

### 5. **Gmail All Mail Excluded**

**Decision**: Excluded `[Gmail]/All Mail` to prevent syncing tens of thousands of archived messages.

**Trade-off**: Cannot access full archive locally. Inbox + Sent + Starred only.

---

## Recommended Improvements

### Priority 1: Fix Duplicate Detection

**Option A: notmuch Deduplication**

Configure notmuch to suppress duplicate Message-IDs in search results:

```ini
# ~/.notmuch-config
[search]
exclude_tags=duplicate
```

Post-new hook script:
```bash
# Mark all but first occurrence as duplicate
notmuch search --output=messages --duplicate=2 '*' | \
  xargs -I{} notmuch tag +duplicate -- id:{}
```

**Pros**: Clean unified inbox view
**Cons**: Must manually review duplicates folder occasionally

**Option B: Per-Account Inbox Subfolders**

Restructure to:
```
000_inbox/
├── hwc/           # iheartwoodcraft INBOX
├── gmail-work/    # gmail-business INBOX
├── gmail-pers/    # gmail-personal INBOX
└── proton/        # proton INBOX
```

Update mbsync channels to sync to subfolders. Update notmuch to tag by subfolder path.

**Pros**: No duplicates, path-based tagging works
**Cons**: Breaks unified inbox concept, requires folder navigation

**Option C: Proton Account Consolidation**

Since `iheartwoodcraft` and `proton` are the same account:
- Only sync `iheartwoodcraft`
- Configure Proton to forward `@proton.me` mail to `@iheartwoodcraft.com`
- Reduces accounts from 4 to 3

**Pros**: Fewer duplicates, simpler config
**Cons**: Lose ability to reply from `@proton.me` address

### Priority 2: Restore Account Tagging

**Option A: X-Delivery-Account Header Injection**

Modify mbsync post-fetch hook to inject custom header:
```bash
# For each message synced from gmail-business:
sed -i '1iX-Account: gmail-business' message.eml
```

Update notmuch hooks:
```bash
notmuch tag +gmail_work -- 'header:X-Account=gmail-business'
```

**Pros**: Reliable, works for all message types
**Cons**: Requires custom scripting, modifies message files

**Option B: Virtual Folder Tags**

Use aerc virtual folders with notmuch queries:
```ini
# ~/.config/aerc/accounts.conf
[iheartwoodcraft]
source = notmuch://~/Maildir?query=folder:000_inbox AND from:*@iheartwoodcraft.com

[gmail-business]
source = notmuch://~/Maildir?query=folder:000_inbox AND from:*heartwoodcraftmt@gmail.com
```

**Pros**: No config changes, leverages existing notmuch
**Cons**: Still broken for self-sent mail

**Option C: Accept Sender-Based Tagging Limitation**

Keep current system, manually tag edge cases.

**Pros**: Simple, no changes
**Cons**: Manual work, incomplete automation

### Priority 3: Improve Workflow Organization

**GTD Processing Workflow**

Implement proper GTD email processing with dedicated folders:

```
000_inbox/          # Unprocessed (Inbox Zero target)
020_action/         # Requires action/response
030_waiting/        # Waiting for reply
040_reference/      # Keep for reference
050_someday/        # Future/low priority
```

**Keybindings**:
```
<Space>ma  → :mv 020_action
<Space>mw  → :mv 030_waiting
<Space>mr  → :mv 040_reference
<Space>ms  → :mv 050_someday
```

**notmuch Queries**:
```bash
# Dashboard queries
[saved_searches]
inbox = folder:000_inbox
action = folder:020_action AND tag:unread
waiting = folder:030_waiting AND date:7d..
```

### Priority 4: Smart Filtering & Auto-Filing

**Email Rules Engine**

Use notmuch auto-tagging for automated filing:

```bash
# Auto-file newsletters
notmuch tag +newsletter +someday -- from:newsletter OR from:updates

# Auto-file receipts
notmuch tag +receipt +reference -- subject:receipt OR subject:invoice

# Auto-file social notifications
notmuch tag +social -- from:*@linkedin.com OR from:*@facebook.com
```

**Conditional Move**:
```bash
# Move newsletters to someday after tagging
notmuch search --output=files tag:newsletter AND folder:000_inbox | \
  xargs -I{} mv {} ~/Maildir/050_someday/cur/
```

### Priority 5: Enhanced Search & Filtering

**notmuch Saved Searches**

```ini
# ~/.notmuch-config
[saved_searches]
unread_work = folder:000_inbox AND tag:unread AND (tag:hwc_email OR tag:gmail_work)
unread_personal = folder:000_inbox AND tag:unread AND (tag:gmail_personal OR tag:proton_personal)
flagged = tag:flagged
recent = date:7d..
```

**aerc Integration**:
```
:cf notmuch://unread_work
:cf notmuch://flagged
```

### Priority 6: Backup & Disaster Recovery

**Current State**: No automated backups of Maildir.

**Recommendation**:
```bash
# Daily backup to external drive
rsync -av --delete ~/Maildir/ /mnt/backup/maildir/

# Weekly encrypted backup to cloud
tar czf - ~/Maildir | gpg -e -r eric@iheartwoodcraft.com | \
  rclone copy - remote:backup/maildir-$(date +%Y%m%d).tar.gz.gpg
```

**notmuch Database Backup**:
```bash
# Backup search index (can be regenerated but slow)
notmuch dump --output=~/Maildir/.notmuch/backup.dump
```

---

## Performance Considerations

### Current Metrics

- **Total Messages**: ~13,681 in 000_inbox (as of Oct 7, 2025)
- **Initial Sync Time**: ~90 minutes for 4 accounts
- **Incremental Sync**: ~10-30 seconds every 5 minutes
- **notmuch Index Time**: ~72 seconds for 10,222 files
- **Disk Usage**: TBD (measure with `du -sh ~/Maildir`)

### Optimization Opportunities

1. **Limit Initial Sync Depth**
   - Use `MaxMessages` in mbsync to limit initial history
   - Example: `MaxMessages 1000` per folder

2. **Exclude Large Attachments**
   - mbsync `MaxSize` option to skip large attachments
   - Download on-demand via web interface

3. **Notmuch Database Optimization**
   ```bash
   notmuch compact  # Compact database
   notmuch reindex  # Rebuild index
   ```

4. **SSD Storage**
   - Move Maildir to SSD for faster search/indexing
   - Symlink: `ln -s /mnt/ssd/Maildir ~/Maildir`

---

## Security Considerations

### Password Management

- **Proton Bridge Password**: Stored in `pass` at `email/proton/bridge`
- **Gmail App Passwords**: Stored in agenix secrets at `/run/agenix/gmail-*-password`
- **GPG Keys**: `~/.gnupg/` for pass encryption

**Best Practice**: Rotate Proton Bridge password after vault corruption.

### Email Encryption

- **GPG Integration**: aerc supports PGP encryption/signing (configured but not documented here)
- **TLS**: All IMAP/SMTP connections use STARTTLS (Proton Bridge) or TLS (Gmail)

### Local Storage

- **Maildir Permissions**: `~/.Maildir/` is `0700` (owner read/write/execute only)
- **notmuch Database**: `~/.notmuch/` is `0700`
- **Proton Bridge Vault**: `~/.local/share/protonmail/bridge-v3/` is `0700`

---

## Troubleshooting

### Common Issues

**Issue**: `UIDVALIDITY genuinely changed`
**Fix**: Delete `.mbsyncstate*` and `.uidvalidity` files in affected folder

**Issue**: `no such user` (Proton Bridge)
**Fix**: Check bridge is running, password in `pass` matches bridge config

**Issue**: `channel is locked`
**Fix**: `rm -f ~/.cache/mbsync.lock ~/Maildir/*/.mbsyncstate.lock`

**Issue**: Proton Bridge vault corruption
**Fix**: `rm -rf ~/.local/share/protonmail/bridge-v3/gluon/` and restart bridge

**Issue**: Missing colors in aerc
**Fix**: Verify styleset syntax uses `~/regex/` format, check `styleset-name=hwc-theme`

### Debug Commands

```bash
# Test mbsync for single account
mbsync -V iheartwoodcraft-INBOX

# Check notmuch database
notmuch count '*'
notmuch search --output=tags '*' | sort

# Verify aerc config
aerc -c ~/.config/aerc/aerc.conf

# Check Proton Bridge status
systemctl --user status protonmail-bridge.service
journalctl --user -u protonmail-bridge.service -n 50

# Verify password retrieval
pass show email/proton/bridge
```

---

## Future Enhancements

### Short-term (1-3 months)

1. Implement notmuch deduplication
2. Fix account tagging with X-Account headers
3. Add GTD workflow folders (action, waiting, reference, someday)
4. Configure automated backups
5. Document PGP encryption workflow

### Medium-term (3-6 months)

1. Migrate to per-account inbox subfolders for better isolation
2. Implement smart filtering rules
3. Add server-side filtering (Gmail filters, Proton sieve)
4. Configure contacts management (abook integration)
5. Add calendar integration (khal/vdirsyncer)

### Long-term (6-12 months)

1. Evaluate switching to notmuch-based mail client (neomutt, mutt, notmuch-emacs)
2. Implement machine learning for auto-filing (offlineimap ML features)
3. Add mobile sync (K-9 Mail, FairEmail with Maildir sync)
4. Consider self-hosted mail server for consolidation
5. Implement full E2EE for all accounts (not just Proton)

---

## Conclusion

The current email system successfully implements a unified inbox architecture combining 4 email accounts into a single view with visual differentiation. The core infrastructure (mbsync, notmuch, aerc) is solid and performant.

**Key Strengths**:
- GTD-style unified inbox reduces context switching
- Color-coded visual differentiation
- Fast local search via notmuch
- Automated sync and indexing
- Vim-like keyboard-driven workflow

**Key Weaknesses**:
- Duplicate messages from cross-account delivery
- Broken account tagging due to unified folder structure
- Occasional Proton Bridge stability issues
- No automated backups
- Limited mobile access

**Recommended Next Steps**:
1. Implement notmuch deduplication (Priority 1A)
2. Evaluate Proton account consolidation (Priority 1C)
3. Add GTD workflow folders (Priority 3)
4. Configure automated backups (Priority 6)

The system is production-ready but would benefit from deduplication and improved tagging to reach optimal workflow efficiency.

---

**Document Version**: 1.0
**Last Updated**: October 7, 2025
**Maintainer**: Eric
