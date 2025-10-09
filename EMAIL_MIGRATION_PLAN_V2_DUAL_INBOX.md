# Email System Migration Plan v2.0: "Dual Unified Inbox"

**Date**: October 8, 2025
**Goal**: Migrate from a single, flawed unified inbox to a robust, per-account structure with two distinct, hardlink-based unified inboxes for "Work" and "Personal".
**System Owner**: Eric

---

## Target Architecture: The Dual Unified Inbox

This new architecture provides complete separation between Work and Personal contexts, eliminating clutter while retaining a unified workflow for each domain. It solves all critical issues of the previous system (duplicates, broken tagging) by design.

```
~/Maildir/
├── 100_hwc/              # Source: Proton Work Mail (from 'hwc-inbox' folder)
│   ├── inbox/
│   └── ... (sent, archive, etc.)
├── 110_gmail-business/   # Source: Gmail Work Mail
│   ├── inbox/
│   └── ...
├── 200_personal/         # Source: Proton Personal Mail (from 'personal-inbox' folder)
│   ├── inbox/
│   └── ...
├── 210_gmail-personal/   # Source: Gmail Personal Mail
│   ├── inbox/
│   └── ...
│
├── 010_unified-work/     # PHYSICAL Unified WORK Inbox (Hardlinks from 1xx sources)
│   └── inbox/
└── 020_unified-personal/ # PHYSICAL Unified PERSONAL Inbox (Hardlinks from 2xx sources)
    └── inbox/
```

---

## Migration Strategy: A Phased, No-Data-Loss Approach

We will use your existing backup to seed the new structure, avoiding a massive re-download. The process is designed to be safe, verifiable at each step, and fully reversible.

---

## Phase 1: Server-Side & Local Preparation (CRITICAL - Do First)

### Step 1.1: Pre-sort Proton Mail on the Server
This is the most important new step. It cleanly separates your two Proton identities at the source.

1.  Log in to your Proton Mail web account.
2.  Go to **Settings -> Go to settings -> Filters**.
3.  Create two new folders on the server: `hwc-inbox` and `personal-inbox`.
4.  Create two filters:
    *   **Work Filter:** If a message is delivered `To` `eric@iheartwoodcraft.com`, then `Move to` the `hwc-inbox` folder.
    *   **Personal Filter:** If a message is delivered `To` `eriqueo@proton.me`, then `Move to` the `personal-inbox` folder.
5.  Ensure these filters are active. This makes your main Proton `INBOX` effectively empty for new mail, as everything is pre-sorted.

### Step 1.2: Stop Local Syncing
```bash
systemctl --user stop mbsync.timer
pkill -9 mbsync # Ensure any running sync is terminated
systemctl --user status mbsync.timer # Verify it's inactive
```

### Step 1.3: Create Safety Backup
```bash
# Create a hardlink copy for speed and space efficiency
cp -al ~/Maildir ~/Maildir.backup-$(date +%Y%m%d-%H%M%S)
# Verify the backup was created successfully
ls -ld ~/Maildir.backup-*/
```

### Step 1.4: Create New Folder Structure
```bash
cd ~/Maildir

# Create the FOUR source account directories
mkdir -p 100_hwc/{inbox,sent,drafts,archive}/{cur,new,tmp}
mkdir -p 110_gmail-business/{inbox,sent,drafts,archive}/{cur,new,tmp}
mkdir -p 200_personal/{inbox,sent,drafts,archive}/{cur,new,tmp}
mkdir -p 210_gmail-personal/{inbox,sent,drafts,archive}/{cur,new,tmp}

# Create the TWO unified inbox directories
mkdir -p 010_unified-work/inbox/{cur,new,tmp}
mkdir -p 020_unified-personal/inbox/{cur,new,tmp}

# Set secure permissions
chmod -R 700 1* 2* 0*

# Verify the new structure
tree -L 2 100_hwc 110_gmail-business 200_personal 210_gmail-personal 010_unified-work 020_unified-personal
```

---

## Phase 2: Migrate Local Data & Update Config

### Step 2.1: Migrate Mail from Backup
Use your backup to populate the new structure. This avoids re-downloading 14.5GB of mail.

**IMPORTANT**: We need to determine the actual folder names in your backup first. Run:
```bash
ls -la ~/Maildir.backup-*/
```

Then migrate based on actual structure. Example commands (adjust based on your backup):

```bash
# --- WORK MIGRATION ---
# Proton Work (adjust folder names based on backup structure)
# If backup has separate folders for iheartwoodcraft:
rsync -av ~/Maildir.backup-*/[iheartwoodcraft-folder]/inbox/ ~/Maildir/100_hwc/inbox/
rsync -av ~/Maildir.backup-*/[iheartwoodcraft-folder]/sent/ ~/Maildir/100_hwc/sent/

# Gmail Work
rsync -av ~/Maildir.backup-*/[gmail-business-folder]/inbox/ ~/Maildir/110_gmail-business/inbox/
rsync -av ~/Maildir.backup-*/[gmail-business-folder]/sent/ ~/Maildir/110_gmail-business/sent/

# --- PERSONAL MIGRATION ---
# Proton Personal
rsync -av ~/Maildir.backup-*/[proton-personal-folder]/inbox/ ~/Maildir/200_personal/inbox/
rsync -av ~/Maildir.backup-*/[proton-personal-folder]/sent/ ~/Maildir/200_personal/sent/

# Gmail Personal
rsync -av ~/Maildir.backup-*/[gmail-personal-folder]/inbox/ ~/Maildir/210_gmail-personal/inbox/
rsync -av ~/Maildir.backup-*/[gmail-personal-folder]/sent/ ~/Maildir/210_gmail-personal/sent/
```

**NOTE**: Since your current structure has unified folders (000_inbox, 010_sent), we may NOT have separate per-account backups. In that case, we'll skip this step and let mbsync do a fresh sync to the new folders.

### Step 2.2: Rewrite `mbsync` Configuration
Update your `~/.mbsyncrc` (or the Nix file that generates it) to reflect the new four-account structure.

**Key Logic for `mbsyncrc`:**

**Proton Work Account (100_hwc)**
```ini
IMAPAccount hwc
Host 127.0.0.1
Port 1143
User eric@iheartwoodcraft.com
PassCmd "sh -c 'pass show email/proton/bridge'"
TLSType None

IMAPStore hwc-remote
Account hwc

MaildirStore hwc-local
Path /home/eric/Maildir/100_hwc/
Inbox /home/eric/Maildir/100_hwc/inbox
SubFolders Verbatim

Channel hwc-inbox
Far :hwc-remote:"hwc-inbox"
Near :hwc-local:"inbox"
Create Both
Expunge Both
SyncState *

Channel hwc-sent
Far :hwc-remote:"Sent"
Near :hwc-local:"sent"
Create Both
Expunge Both
SyncState *

Channel hwc-drafts
Far :hwc-remote:"Drafts"
Near :hwc-local:"drafts"
Create Both
Expunge Both
SyncState *

Channel hwc-archive
Far :hwc-remote:"Archive"
Near :hwc-local:"archive"
Create Both
Expunge Both
SyncState *

Group hwc
Channel hwc-inbox
Channel hwc-sent
Channel hwc-drafts
Channel hwc-archive
```

**Gmail Work Account (110_gmail-business)**
```ini
IMAPAccount gmail-business
Host imap.gmail.com
Port 993
User heartwoodcraftmt@gmail.com
PassCmd "sh -c 'tr -d \"\\n\" < \"$0\"' /run/agenix/gmail-business-password"
TLSType IMAPS

IMAPStore gmail-business-remote
Account gmail-business

MaildirStore gmail-business-local
Path /home/eric/Maildir/110_gmail-business/
Inbox /home/eric/Maildir/110_gmail-business/inbox
SubFolders Verbatim

Channel gmail-business-inbox
Far :gmail-business-remote:"INBOX"
Near :gmail-business-local:"inbox"
Create Near
Expunge Both
SyncState *

Channel gmail-business-sent
Far :gmail-business-remote:"[Gmail]/Sent Mail"
Near :gmail-business-local:"sent"
Create Near
Expunge Both
SyncState *

Channel gmail-business-drafts
Far :gmail-business-remote:"[Gmail]/Drafts"
Near :gmail-business-local:"drafts"
Create Near
Expunge Both
SyncState *

Channel gmail-business-starred
Far :gmail-business-remote:"[Gmail]/Starred"
Near :gmail-business-local:"starred"
Create Near
Expunge Both
SyncState *

Group gmail-business
Channel gmail-business-inbox
Channel gmail-business-sent
Channel gmail-business-drafts
Channel gmail-business-starred
```

**Proton Personal Account (200_personal)**
```ini
IMAPAccount personal
Host 127.0.0.1
Port 1143
User eriqueo@proton.me
PassCmd "sh -c 'pass show email/proton/bridge'"
TLSType None

IMAPStore personal-remote
Account personal

MaildirStore personal-local
Path /home/eric/Maildir/200_personal/
Inbox /home/eric/Maildir/200_personal/inbox
SubFolders Verbatim

Channel personal-inbox
Far :personal-remote:"personal-inbox"
Near :personal-local:"inbox"
Create Both
Expunge Both
SyncState *

Channel personal-sent
Far :personal-remote:"Sent"
Near :personal-local:"sent"
Create Both
Expunge Both
SyncState *

Channel personal-drafts
Far :personal-remote:"Drafts"
Near :personal-local:"drafts"
Create Both
Expunge Both
SyncState *

Channel personal-archive
Far :personal-remote:"Archive"
Near :personal-local:"archive"
Create Both
Expunge Both
SyncState *

Group personal
Channel personal-inbox
Channel personal-sent
Channel personal-drafts
Channel personal-archive
```

**Gmail Personal Account (210_gmail-personal)**
```ini
IMAPAccount gmail-personal
Host imap.gmail.com
Port 993
User eriqueokeefe@gmail.com
PassCmd "sh -c 'tr -d \"\\n\" < \"$0\"' /run/agenix/gmail-personal-password"
TLSType IMAPS

IMAPStore gmail-personal-remote
Account gmail-personal

MaildirStore gmail-personal-local
Path /home/eric/Maildir/210_gmail-personal/
Inbox /home/eric/Maildir/210_gmail-personal/inbox
SubFolders Verbatim

Channel gmail-personal-inbox
Far :gmail-personal-remote:"INBOX"
Near :gmail-personal-local:"inbox"
Create Near
Expunge Both
SyncState *

Channel gmail-personal-sent
Far :gmail-personal-remote:"[Gmail]/Sent Mail"
Near :gmail-personal-local:"sent"
Create Near
Expunge Both
SyncState *

Channel gmail-personal-drafts
Far :gmail-personal-remote:"[Gmail]/Drafts"
Near :gmail-personal-local:"drafts"
Create Near
Expunge Both
SyncState *

Channel gmail-personal-starred
Far :gmail-personal-remote:"[Gmail]/Starred"
Near :gmail-personal-local:"starred"
Create Near
Expunge Both
SyncState *

Group gmail-personal
Channel gmail-personal-inbox
Channel gmail-personal-sent
Channel gmail-personal-drafts
Channel gmail-personal-starred
```

### Step 2.3: Clear All Sync State
This is critical. We must force `mbsync` to forget the old structure.
```bash
rm -rf ~/.mbsync/
find ~/Maildir -name ".mbsyncstate*" -delete
find ~/Maildir -name ".uidvalidity" -delete
```

---

## Phase 3: Sync & Aggregate

### Step 3.1: Run Reconciling Sync
This sync will download mail to the new structure. If you migrated from backup, it will be incremental. If not, it will be a full sync.

```bash
echo "Starting reconciling sync..."
mbsync -aV 2>&1 | tee ~/mbsync-reconcile.log
echo "Sync finished. Check log for details."
```

**Expected time**:
- If migrated from backup: 10-30 minutes (incremental)
- If fresh sync: 1-2 hours (full download)

### Step 3.2: Create and Run the Hardlink Script
This script builds your two unified inboxes.

**File: `~/Maildir/sync-unified.sh`**
```bash
#!/usr/bin/env bash
set -euo pipefail

# --- Define Unified Work Inbox ---
UNIFIED_WORK="/home/eric/Maildir/010_unified-work/inbox"
WORK_SOURCES=(
  "/home/eric/Maildir/100_hwc/inbox"
  "/home/eric/Maildir/110_gmail-business/inbox"
)

# --- Define Unified Personal Inbox ---
UNIFIED_PERS="/home/eric/Maildir/020_unified-personal/inbox"
PERS_SOURCES=(
  "/home/eric/Maildir/200_personal/inbox"
  "/home/eric/Maildir/210_gmail-personal/inbox"
)

# Function to sync a unified inbox
sync_inbox() {
  local unified_dir="$1"; shift; local source_dirs=("$@")
  echo "Syncing to $unified_dir..."

  # Remove existing hardlinks (doesn't affect source files)
  find "$unified_dir/new" -type f -delete 2>/dev/null || true
  find "$unified_dir/cur" -type f -delete 2>/dev/null || true

  # Create new hardlinks from source folders
  for source in "${source_dirs[@]}"; do
    if [ -d "$source/new" ]; then
      find "$source/new" -type f -exec ln -f {} "$unified_dir/new/" \; 2>/dev/null || true
    fi
    if [ -d "$source/cur" ]; then
      find "$source/cur" -type f -exec ln -f {} "$unified_dir/cur/" \; 2>/dev/null || true
    fi
  done

  local count=$(find "$unified_dir" -type f | wc -l)
  echo "Sync complete for $unified_dir ($count messages)."
}

echo "=== Syncing Unified Inboxes ==="
sync_inbox "$UNIFIED_WORK" "${WORK_SOURCES[@]}"
sync_inbox "$UNIFIED_PERS" "${PERS_SOURCES[@]}"
echo "=== All unified inboxes are up to date ==="
```

**Make it executable and run it:**
```bash
chmod +x ~/Maildir/sync-unified.sh
~/Maildir/sync-unified.sh
```

**Verify unified inboxes:**
```bash
# Check work inbox
find ~/Maildir/010_unified-work/inbox -type f | wc -l

# Check personal inbox
find ~/Maildir/020_unified-personal/inbox -type f | wc -l

# Verify hardlinks (should share inodes with source)
ls -i ~/Maildir/100_hwc/inbox/new/* | head -3
ls -i ~/Maildir/010_unified-work/inbox/new/* | head -3
# Same filenames should have matching inode numbers
```

---

## Phase 4: Re-index and Reconfigure Clients

### Step 4.1: Rebuild `notmuch` Database
Your file paths have completely changed, so a full re-index is required.

```bash
# Backup old database (optional)
notmuch dump > ~/notmuch-tags-backup-$(date +%Y%m%d).dump

# Remove old database
rm -rf ~/Maildir/.notmuch/xapian/

# Reindex with new structure
notmuch new

# Verify counts
notmuch count '*'
```

### Step 4.2: Update `notmuch` Tagging Hooks
Create/update `~/.notmuch/hooks/post-new` with path-based tagging (100% reliable):

```bash
#!/usr/bin/env bash

# Tag by source account (path-based - infallible)
notmuch tag +hwc_email -- 'path:100_hwc/** and not tag:hwc_email'
notmuch tag +gmail_work -- 'path:110_gmail-business/** and not tag:gmail_work'
notmuch tag +proton_pers -- 'path:200_personal/** and not tag:proton_pers'
notmuch tag +gmail_pers -- 'path:210_gmail-personal/** and not tag:gmail_pers'

# Tag by domain (work vs personal)
notmuch tag +work -- '(tag:hwc_email or tag:gmail_work) and not tag:work'
notmuch tag +personal -- '(tag:proton_pers or tag:gmail_pers) and not tag:personal'

# Tag by folder type
notmuch tag +inbox -- 'path:**/inbox/** and not tag:inbox'
notmuch tag +sent -- 'path:**/sent/** and not tag:sent'
notmuch tag +drafts -- 'path:**/drafts/** and not tag:drafts'
notmuch tag +archive -- 'path:**/archive/** and not tag:archive'
notmuch tag +starred -- 'path:**/starred/** and not tag:starred'

# Remove inbox tag from non-inbox folders
notmuch tag -inbox -- 'not path:**/inbox/** and tag:inbox'
```

**Make executable:**
```bash
chmod +x ~/.notmuch/hooks/post-new
```

**Run manually to apply tags:**
```bash
~/.notmuch/hooks/post-new
```

**Verify tags:**
```bash
notmuch count tag:hwc_email
notmuch count tag:gmail_work
notmuch count tag:work
notmuch count tag:personal
notmuch count tag:inbox
```

### Step 4.3: Update `aerc` Configuration
Point `aerc` to your new unified work inbox as the default.

**`~/.config/aerc/aerc.conf`:**
```ini
[general]
# Default to the unified WORK inbox on startup
default-folder = maildir:///home/eric/Maildir/010_unified-work/inbox
```

**`~/.config/aerc/binds.conf`:**
```ini
[messages]
# Unified inboxes
<Space>giw = :cf 010_unified-work/inbox<Enter>       # Go to Inbox (Work)
<Space>gip = :cf 020_unified-personal/inbox<Enter>   # Go to Inbox (Personal)

# Per-account inboxes (for debugging/isolation)
<Space>g1 = :cf 100_hwc/inbox<Enter>                 # HWC inbox
<Space>g2 = :cf 110_gmail-business/inbox<Enter>      # Gmail work inbox
<Space>g3 = :cf 200_personal/inbox<Enter>            # Proton personal inbox
<Space>g4 = :cf 210_gmail-personal/inbox<Enter>      # Gmail personal inbox

# Sent/Archive
<Space>gs = :cf 100_hwc/sent<Enter>                  # Sent (adjust based on preference)
<Space>ga = :cf 100_hwc/archive<Enter>               # Archive
```

**Update accounts.conf (if needed):**
All accounts should point to `maildir:///home/eric/Maildir` as source. Sending identities remain separate.

---

## Phase 5: Finalization

### Step 5.1: Test Extensively
Launch `aerc` and verify:

1. ✅ Opens to unified work inbox
2. ✅ Work inbox contains only mail from 100_hwc and 110_gmail-business
3. ✅ Can switch to personal inbox (`<Space>gip`)
4. ✅ Personal inbox contains only mail from 200_personal and 210_gmail-personal
5. ✅ Colors applied correctly based on sender
6. ✅ Mark as read in unified inbox → marks read in source folder
7. ✅ Archive/delete in unified inbox → affects source folder
8. ✅ Compose and send works (verify saves to correct sent folder)
9. ✅ No duplicate messages in unified views

**Testing checklist:**
```bash
# In aerc:
# - Read a message
# - Mark as read/unread
# - Flag a message
# - Move to archive
# - Delete a message
# - Compose and send
# - Check source folders to verify changes propagated
```

### Step 5.2: Automate and Resume
Update your systemd `mbsync.service` to run the unified inbox sync script.

**Add to service (in NixOS config or systemd user unit):**
```ini
ExecStartPost = /home/eric/Maildir/sync-unified.sh
ExecStartPost = /usr/bin/bash -lc 'notmuch new || true'
```

**Re-enable timer:**
```bash
systemctl --user daemon-reload  # If you modified the service
systemctl --user start mbsync.timer
systemctl --user status mbsync.timer  # Verify active
```

**Watch first automated sync:**
```bash
journalctl --user -u mbsync.service -f
```

### Step 5.3: Clean Up
After verifying system is stable (1 week recommended):

```bash
# Archive old backup
mkdir -p ~/archive-old-maildir/
mv ~/Maildir.backup-* ~/archive-old-maildir/

# Archive old unified folders (if they still exist)
mv ~/Maildir/000_inbox ~/archive-old-maildir/ 2>/dev/null || true
mv ~/Maildir/010_sent ~/archive-old-maildir/ 2>/dev/null || true
mv ~/Maildir/011_drafts ~/archive-old-maildir/ 2>/dev/null || true

# After 30 days, if no issues:
# rm -rf ~/archive-old-maildir/
```

---

## Two-Way Sync and End Goal

This architecture fully achieves your end goal. Because `aerc` is operating on physical files (via hardlinks), any action you take—moving, deleting, changing flags—modifies the source file. The next time `mbsync` runs, it will see this change and sync it back to the server. This is the robust, bidirectional sync you wanted.

**How it works:**
1. You read/flag/delete a message in `010_unified-work/inbox`
2. The hardlink points to the actual file in `100_hwc/inbox/` or `110_gmail-business/inbox/`
3. The modification affects the source file
4. Next `mbsync` sync detects the change (read flag, moved file, etc.)
5. mbsync syncs the change back to the IMAP server
6. Change is now reflected on all devices

---

## Troubleshooting

### Issue: Proton Bridge not running
```bash
systemctl --user start protonmail-bridge.service
systemctl --user status protonmail-bridge.service
```

### Issue: Proton filters not working
- Log into Proton webmail
- Check Settings → Filters
- Verify folders `hwc-inbox` and `personal-inbox` exist
- Verify filters are enabled and in correct order

### Issue: mbsync fails with UIDVALIDITY error
```bash
# Clear state for affected channel
rm -f ~/.mbsync/[channel-name]*
rm -f ~/Maildir/[folder]/.mbsyncstate*
rm -f ~/Maildir/[folder]/.uidvalidity

# Re-sync
mbsync [channel-name]
```

### Issue: Hardlinks not created
```bash
# Verify source folders have mail
ls -lah ~/Maildir/100_hwc/inbox/new/

# Verify script permissions
ls -l ~/Maildir/sync-unified.sh
chmod +x ~/Maildir/sync-unified.sh

# Run manually with verbose output
bash -x ~/Maildir/sync-unified.sh
```

### Issue: notmuch tags not applied
```bash
# Verify hook is executable
chmod +x ~/.notmuch/hooks/post-new

# Run manually
~/.notmuch/hooks/post-new

# Check for errors
notmuch search tag:hwc_email
```

---

## Rollback Procedure

If anything goes wrong:

```bash
# 1. Stop mbsync
systemctl --user stop mbsync.timer

# 2. Restore from backup
rm -rf ~/Maildir
cp -al ~/Maildir.backup-[TIMESTAMP] ~/Maildir

# 3. Restore old mbsync config
cp ~/.mbsyncrc.backup ~/mbsyncrc

# 4. Restore notmuch database (optional)
notmuch restore < ~/notmuch-tags-backup-[TIMESTAMP].dump

# 5. Resume
systemctl --user start mbsync.timer
```

---

## Summary of Benefits

### Before (Single Unified Inbox)
- ❌ Duplicates (same message 4-8 times)
- ❌ Broken account tagging (path-based tags don't work)
- ❌ No work/personal separation
- ❌ Can't determine source account

### After (Dual Unified Inbox)
- ✅ No duplicates (per-account storage + hardlink deduplication)
- ✅ Reliable account tagging (path-based on per-account folders)
- ✅ Clean work/personal separation (two unified inboxes)
- ✅ Source account always identifiable
- ✅ Bidirectional sync works correctly
- ✅ Can view per-account folders for debugging
- ✅ Simpler, more maintainable architecture

---

---

## Migration Tracking

### Changelog Maintenance

**CRITICAL**: Maintain `EMAIL_MIGRATION_CHANGELOG.md` throughout the migration to track:
- Progress through each phase/step
- Issues encountered and resolutions
- Rollback points and timestamps
- Commands executed
- Observations and notes

**Update the changelog**:
- ✅ Before starting each phase
- ✅ After completing each step
- ✅ When encountering any issues
- ✅ At the end of each work session
- ✅ Before any breaks (in case session is interrupted)

This ensures migration can resume seamlessly even if:
- Session is interrupted
- Token limits reached
- Different AI assistant takes over
- Days/weeks pass between work sessions

**Changelog location**: `/home/eric/.nixos/EMAIL_MIGRATION_CHANGELOG.md`

---

**Ready to execute when you confirm!**
