# Email System Migration to Hybrid Per-Account Architecture

**Date**: October 8, 2025
**Goal**: Migrate from unified folders to per-account structure with hardlink-based unified inbox
**Total Data**: ~14.5GB, 13,684 messages in current inbox

---

## Current State Analysis

### Existing Structure (Unified - Has Duplicates)
```
~/Maildir/
├── 000_inbox/          # 1.5GB - ALL accounts mixed (13,684 messages)
├── 010_sent/           # 3.4GB - ALL accounts mixed
├── 011_drafts/         # 1.4MB - ALL accounts mixed
├── 110_hwc-important/  # 8.3MB - Gmail business starred
├── 190_hwc-archive/    # 464KB - Proton hwc archive
├── 210_pers-important/ # 9.8GB - Gmail personal starred
├── 290_pers-archive/   # 464KB - Proton personal archive
├── 800_spam/           # Global spam
├── 900_trash/          # Global trash
└── Labels/             # Proton labels
```

### Problems with Current Structure
1. **Duplicates**: Same email appears 4-8 times when sent to multiple addresses
2. **Broken tagging**: Path-based tags don't work (all mail in `000_inbox`)
3. **No account identity**: Can't tell which account received a message

### Target Structure (Per-Account + Unified View)
```
~/Maildir/
├── 100_hwc/
│   ├── inbox/          # iheartwoodcraft INBOX only
│   ├── sent/           # iheartwoodcraft Sent only
│   ├── drafts/         # iheartwoodcraft Drafts only
│   ├── archive/        # iheartwoodcraft Archive
│   └── important/      # (future - starred/flagged)
├── 110_gmail-business/
│   ├── inbox/          # gmail-business INBOX only
│   ├── sent/           # gmail-business Sent only
│   ├── drafts/         # gmail-business Drafts only
│   └── starred/        # Gmail starred (110_hwc-important)
├── 200_gmail-personal/
│   ├── inbox/          # gmail-personal INBOX only
│   ├── sent/           # gmail-personal Sent only
│   ├── drafts/         # gmail-personal Drafts only
│   └── starred/        # Gmail starred (210_pers-important)
├── 000_unified/        # PHYSICAL unified view (hardlinks)
│   └── inbox/          # Aggregated inbox via hardlinks
├── 010_sent/           # Global sent (optional - can use per-account)
├── 011_drafts/         # Global drafts (optional)
├── 800_spam/           # Global spam
└── 900_trash/          # Global trash
```

---

## Migration Strategy

### Key Principle: **NO MASSIVE RE-SYNC**

We will:
- ✅ Create new folder structure
- ✅ Update mbsync config to point to new folders
- ✅ Let mbsync do incremental sync (only new/changed messages)
- ✅ Keep old `000_inbox` as backup until verified
- ❌ NOT delete anything until verified working
- ❌ NOT force full re-download of 14.5GB

---

## Phase 1: Prepare & Backup (CRITICAL - Do First)

### Step 1.1: Stop mbsync timer
```bash
systemctl --user stop mbsync.timer
systemctl --user status mbsync.timer  # Verify stopped
```

**Why**: Prevent sync conflicts during migration

### Step 1.2: Create safety backup
```bash
# Create backup (hardlinks for speed/space efficiency)
cp -al ~/Maildir ~/Maildir.backup-$(date +%Y%m%d-%H%M%S)

# Verify backup
ls -lah ~/Maildir.backup-*/
du -sh ~/Maildir.backup-*/
```

**Why**: Allows complete rollback if something goes wrong

### Step 1.3: Verify Proton Bridge is running
```bash
systemctl --user status protonmail-bridge.service
pass show email/proton/bridge  # Verify password accessible
```

**Why**: Proton accounts require bridge active for sync

---

## Phase 2: Create New Folder Structure

### Step 2.1: Create per-account directories
```bash
cd ~/Maildir

# Create hwc account structure
mkdir -p 100_hwc/{inbox,sent,drafts,archive}/{cur,new,tmp}

# Create gmail-business structure
mkdir -p 110_gmail-business/{inbox,sent,drafts,starred}/{cur,new,tmp}

# Create gmail-personal structure
mkdir -p 200_gmail-personal/{inbox,sent,drafts,starred}/{cur,new,tmp}

# Create unified inbox structure
mkdir -p 000_unified/inbox/{cur,new,tmp}

# Verify structure
tree -L 3 ~/Maildir/{100_hwc,110_gmail-business,200_gmail-personal,000_unified}
```

**Why**: mbsync needs maildir structure (cur/new/tmp) to exist

### Step 2.2: Set correct permissions
```bash
chmod 700 ~/Maildir/{100_hwc,110_gmail-business,200_gmail-personal,000_unified}
chmod 700 ~/Maildir/{100_hwc,110_gmail-business,200_gmail-personal,000_unified}/**
```

**Why**: Email security - only owner should read mail

---

## Phase 3: Update mbsync Configuration

### Step 3.1: Backup current config
```bash
cp ~/.mbsyncrc ~/.mbsyncrc.backup-$(date +%Y%m%d)
```

### Step 3.2: Rewrite mbsync config

**New config structure** (detailed config to be written):

```ini
# iheartwoodcraft account
IMAPAccount iheartwoodcraft
Host 127.0.0.1
Port 1143
User eric@iheartwoodcraft.com
PassCmd "sh -c 'pass show email/proton/bridge'"
TLSType None

IMAPStore iheartwoodcraft-remote
Account iheartwoodcraft

MaildirStore iheartwoodcraft-local
Path /home/eric/Maildir/100_hwc/
Inbox /home/eric/Maildir/100_hwc/inbox
SubFolders Verbatim

Channel iheartwoodcraft-INBOX
Far :iheartwoodcraft-remote:"INBOX"
Near :iheartwoodcraft-local:"inbox"
Create Both
Expunge Both
SyncState *

Channel iheartwoodcraft-Sent
Far :iheartwoodcraft-remote:"Sent"
Near :iheartwoodcraft-local:"sent"
Create Both
Expunge Both
SyncState *

Channel iheartwoodcraft-Drafts
Far :iheartwoodcraft-remote:"Drafts"
Near :iheartwoodcraft-local:"drafts"
Create Both
Expunge Both
SyncState *

Channel iheartwoodcraft-Archive
Far :iheartwoodcraft-remote:"Archive"
Near :iheartwoodcraft-local:"archive"
Create Both
Expunge Both
SyncState *

Group iheartwoodcraft
Channel iheartwoodcraft-INBOX
Channel iheartwoodcraft-Sent
Channel iheartwoodcraft-Drafts
Channel iheartwoodcraft-Archive

# Repeat similar structure for:
# - gmail-business (110_gmail-business/)
# - gmail-personal (200_gmail-personal/)

# Global folders (spam/trash) can stay shared or move to per-account
```

**Key changes**:
- `Path` now points to account-specific directory
- `Inbox` points to `100_hwc/inbox` instead of `000_inbox`
- Each account completely isolated
- Groups make syncing easier (`mbsync iheartwoodcraft` syncs all channels)

### Step 3.3: Clear mbsync state for remapped folders
```bash
# Remove state files for folders we're remapping
rm -f ~/.mbsync/*
rm -f ~/Maildir/000_inbox/.mbsyncstate*
rm -f ~/Maildir/000_inbox/.uidvalidity
rm -f ~/Maildir/010_sent/.mbsyncstate*
rm -f ~/Maildir/011_drafts/.mbsyncstate*
```

**Why**: Folder path changes require state reset to avoid UIDVALIDITY errors

---

## Phase 4: Initial Sync to New Structure

### Step 4.1: Sync one account first (test)
```bash
# Test with iheartwoodcraft first
mbsync -V iheartwoodcraft-INBOX

# Check results
ls -lah ~/Maildir/100_hwc/inbox/new/
ls -lah ~/Maildir/100_hwc/inbox/cur/
find ~/Maildir/100_hwc/inbox -type f | wc -l  # Count messages
```

**Why**: Test with one account before doing all

### Step 4.2: If test successful, sync all accounts
```bash
# Sync all accounts
mbsync -a

# This will take time but should be INCREMENTAL
# Watch progress - should not re-download everything
```

**Expected behavior**:
- mbsync detects most messages already exist (by Message-ID)
- Only downloads messages not present locally
- Should complete in minutes, not hours

### Step 4.3: Verify sync results
```bash
# Count messages per account
find ~/Maildir/100_hwc/inbox -type f | wc -l
find ~/Maildir/110_gmail-business/inbox -type f | wc -l
find ~/Maildir/200_gmail-personal/inbox -type f | wc -l

# Total should be roughly same as old 000_inbox (13,684)
# Or MORE if there were duplicates before
```

---

## Phase 5: Create Hardlink-Based Unified Inbox

### Step 5.1: Create hardlink sync script
```bash
# Script location: ~/Maildir/sync-unified-inbox.sh
```

**Script contents**:
```bash
#!/usr/bin/env bash
# Maintain hardlink-based unified inbox

UNIFIED_INBOX="/home/eric/Maildir/000_unified/inbox"
ACCOUNTS=(
  "/home/eric/Maildir/100_hwc/inbox"
  "/home/eric/Maildir/110_gmail-business/inbox"
  "/home/eric/Maildir/200_gmail-personal/inbox"
)

# Clear unified inbox (removes hardlinks, doesn't affect source)
rm -f "$UNIFIED_INBOX/new/"* "$UNIFIED_INBOX/cur/"*

# Create hardlinks from each account
for account_inbox in "${ACCOUNTS[@]}"; do
  # Link new messages
  for msg in "$account_inbox/new/"*; do
    [ -f "$msg" ] && ln -f "$msg" "$UNIFIED_INBOX/new/"
  done

  # Link cur messages
  for msg in "$account_inbox/cur/"*; do
    [ -f "$msg" ] && ln -f "$msg" "$UNIFIED_INBOX/cur/"
  done
done

echo "Unified inbox synced: $(find "$UNIFIED_INBOX" -type f | wc -l) messages"
```

### Step 5.2: Make script executable
```bash
chmod +x ~/Maildir/sync-unified-inbox.sh
```

### Step 5.3: Test script
```bash
~/Maildir/sync-unified-inbox.sh

# Verify unified inbox populated
ls -lah ~/Maildir/000_unified/inbox/new/
ls -lah ~/Maildir/000_unified/inbox/cur/
find ~/Maildir/000_unified/inbox -type f | wc -l
```

### Step 5.4: Verify hardlinks (not copies)
```bash
# Check inode - hardlinks share same inode
stat ~/Maildir/100_hwc/inbox/new/* | grep Inode
stat ~/Maildir/000_unified/inbox/new/* | grep Inode

# Should see matching inodes between source and unified
```

**Why hardlinks**:
- No duplicate storage (same file, multiple paths)
- Mark read in one place, updates everywhere
- Delete from unified = delete from source (unified inbox workflow)

---

## Phase 6: Update systemd Service for Auto-Sync

### Step 6.1: Update mbsync.service
```bash
# Edit systemd user service (NixOS will regenerate, so note for config)
# Add ExecStartPost to run unified inbox sync
```

**Service addition**:
```ini
ExecStartPost = /home/eric/Maildir/sync-unified-inbox.sh
```

**Why**: Automatically maintain unified inbox after every mbsync

---

## Phase 7: Update notmuch Configuration

### Step 7.1: Update notmuch tagging hooks

**New post-new hook** (`~/.notmuch/hooks/post-new`):
```bash
#!/usr/bin/env bash

# Tag by account (path-based - reliable)
notmuch tag +hwc_email -- 'path:100_hwc/** and not tag:hwc_email'
notmuch tag +gmail_work -- 'path:110_gmail-business/** and not tag:gmail_work'
notmuch tag +gmail_personal -- 'path:200_gmail-personal/** and not tag:gmail_personal'

# Tag by folder type
notmuch tag +inbox -- 'path:**/inbox/** and not tag:inbox'
notmuch tag +sent -- 'path:**/sent/** and not tag:sent'
notmuch tag +drafts -- 'path:**/drafts/** and not tag:drafts'
notmuch tag +important -- 'path:**/starred/** and not tag:important'
notmuch tag +archive -- 'path:**/archive/** and not tag:archive'

# Work vs Personal domain tags
notmuch tag +work -- '(tag:hwc_email or tag:gmail_work) and not tag:work'
notmuch tag +personal -- '(tag:gmail_personal) and not tag:personal'
```

### Step 7.2: Reindex notmuch database
```bash
# Backup notmuch database
notmuch dump > ~/Maildir/.notmuch/backup-$(date +%Y%m%d).dump

# Remove old database (will rebuild)
rm -rf ~/Maildir/.notmuch/xapian/

# Reindex with new structure
notmuch new

# Verify tags applied
notmuch count tag:hwc_email
notmuch count tag:gmail_work
notmuch count tag:gmail_personal
notmuch count tag:inbox
```

**Why**: Path-based tagging now works reliably with per-account folders

---

## Phase 8: Update aerc Configuration

### Step 8.1: Update default folder
```ini
# ~/.config/aerc/aerc.conf
[general]
default-folder = maildir:///home/eric/Maildir/000_unified/inbox
```

### Step 8.2: Add account-specific folder shortcuts
```ini
# ~/.config/aerc/binds.conf
[messages]
# Unified inbox (default)
<Space>gi = :cf 000_unified/inbox<Enter>

# Per-account inboxes (for troubleshooting/isolation)
<Space>g1 = :cf 100_hwc/inbox<Enter>
<Space>g2 = :cf 110_gmail-business/inbox<Enter>
<Space>g3 = :cf 200_gmail-personal/inbox<Enter>

# Sent/Drafts (can be per-account or global)
<Space>gs = :cf 010_sent<Enter>
<Space>gd = :cf 011_drafts<Enter>
```

### Step 8.3: Update color coding (still works on sender)
```ini
# Color coding works same as before - based on From header
# No changes needed to stylesets
```

---

## Phase 9: Testing & Verification

### Step 9.1: Test aerc operations
```bash
# Launch aerc
aerc

# Test operations:
# 1. View unified inbox (should see all accounts)
# 2. Read a message (verify opens correctly)
# 3. Mark as read (verify updates in source folder too)
# 4. Move to archive (verify moves from source, not just unified)
# 5. Compose and send (verify saves to correct account sent folder)
# 6. Check per-account folders (verify isolation)
```

### Step 9.2: Verify deduplication
```bash
# Search for a message you know was sent to multiple accounts
notmuch search "subject:YOUR_DUPLICATE_MESSAGE"

# Should show multiple results (one per account folder)
# But unified inbox should only show ONE (via hardlinks)

# Verify hardlink deduplication
find ~/Maildir/000_unified/inbox -type f | wc -l  # Should be LESS than sum of account inboxes
```

### Step 9.3: Verify tags working
```bash
# Search by account tag
notmuch search tag:hwc_email
notmuch search tag:gmail_work
notmuch search tag:gmail_personal

# Search by folder type
notmuch search tag:inbox
notmuch search tag:sent

# Verify counts make sense
notmuch count tag:inbox
notmuch count tag:sent
```

---

## Phase 10: Cleanup & Resume

### Step 10.1: Archive old unified folders
```bash
# Only after VERIFYING new system works!
mkdir -p ~/Maildir/.old-structure-$(date +%Y%m%d)
mv ~/Maildir/000_inbox ~/Maildir/.old-structure-*/
mv ~/Maildir/010_sent ~/Maildir/.old-structure-*/
mv ~/Maildir/011_drafts ~/Maildir/.old-structure-*/

# Keep for 30 days, then delete if no issues
```

### Step 10.2: Resume mbsync timer
```bash
systemctl --user start mbsync.timer
systemctl --user status mbsync.timer  # Verify running

# Watch first sync
journalctl --user -u mbsync.service -f
```

### Step 10.3: Monitor for issues
```bash
# Check sync logs daily for first week
journalctl --user -u mbsync.service --since today

# Verify unified inbox stays in sync
watch -n 60 'find ~/Maildir/000_unified/inbox -type f | wc -l'
```

---

## Rollback Procedure (If Something Goes Wrong)

### If migration fails at any point:

```bash
# 1. Stop mbsync
systemctl --user stop mbsync.timer

# 2. Restore from backup
rm -rf ~/Maildir
mv ~/Maildir.backup-TIMESTAMP ~/Maildir

# 3. Restore old mbsync config
cp ~/.mbsyncrc.backup-TIMESTAMP ~/.mbsyncrc

# 4. Restore notmuch database
notmuch restore < ~/Maildir/.notmuch/backup-TIMESTAMP.dump

# 5. Resume normal operation
systemctl --user start mbsync.timer
```

---

## Expected Results

### Before Migration
- ✅ 13,684 messages in unified `000_inbox`
- ❌ Same message appears 4-8 times (duplicates)
- ❌ Can't tag by account (path-based tags broken)
- ❌ Can't tell which account received message

### After Migration
- ✅ ~13,684 messages across per-account inboxes (distributed by source)
- ✅ Unified inbox shows deduplicated view (via hardlinks)
- ✅ Path-based tagging works: `tag:hwc_email`, `tag:gmail_work`, etc.
- ✅ Can view per-account folders for isolation
- ✅ Hardlinks auto-deduplicate (same message to multiple accounts = one file)
- ✅ Mark read/move/delete in unified inbox affects source folders

---

## Key Safety Features

1. **No data loss**: Migration creates new folders, keeps old
2. **Full backup**: Complete Maildir backup before any changes
3. **Incremental sync**: mbsync reuses existing messages, doesn't re-download
4. **Rollback ready**: Can restore to previous state anytime
5. **Testable**: Can test at each phase before proceeding
6. **Hardlink safety**: Hardlinks don't duplicate data, just create new paths

---

## Timeline Estimate

- **Phase 1 (Backup)**: 5-10 minutes
- **Phase 2 (Create folders)**: 2 minutes
- **Phase 3 (Update config)**: 15-20 minutes (careful editing)
- **Phase 4 (Initial sync)**: 10-30 minutes (incremental, not full re-download)
- **Phase 5 (Hardlink script)**: 10 minutes
- **Phase 6 (Systemd)**: 5 minutes
- **Phase 7 (Notmuch)**: 10-15 minutes (reindex time)
- **Phase 8 (aerc config)**: 5 minutes
- **Phase 9 (Testing)**: 15-30 minutes
- **Phase 10 (Cleanup)**: 5 minutes

**Total**: ~1.5-2.5 hours

---

## Questions Before We Start

1. **Do you have a backup location?** (External drive, cloud, etc.)
2. **Is Proton Bridge currently running?** (`systemctl --user status protonmail-bridge.service`)
3. **Do you want to keep global sent/drafts folders, or move to per-account?**
4. **Any specific concerns about the hardlink approach?**

---

**Ready to proceed when you are!**
