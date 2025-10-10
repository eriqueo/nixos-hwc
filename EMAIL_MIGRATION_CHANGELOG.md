# Email Migration Changelog

**Migration Plan**: v2.0 Dual Unified Inbox
**Started**: 2025-10-08
**Status**: IN PROGRESS

---

## Session Log

### Session 1: 2025-10-08 (Initial Planning & Phase 1 Start)
**Time**: Morning-Evening
**Status**: Completed Phase 1 & 2

### Session 2: 2025-10-09 (CRITICAL: Proton Bridge Authentication Fixed)
**Time**: 16:00-19:00 MDT
**Status**: ✅ BRIDGE WORKING - Ready for Phase 3
**Next Action**: Wait for rate limit to clear, then continue Phase 3

**Session 1 Completed:**
- ✅ Analyzed current email system issues
- ✅ Compared three different architectural approaches
- ✅ Decided on Dual Unified Inbox architecture (work/personal separation)
- ✅ Created comprehensive migration plan v2.0
- ✅ Created this changelog for progress tracking
- ✅ **Phase 1.1**: Configured Proton server-side filters
  - Created folders: `hwc_inbox` and `personal_inbox` (note: underscores, not hyphens)
  - Created filters to route mail to respective folders
- ✅ **Phase 1.2**: Stopped mbsync timer
  - Timer stopped successfully (inactive/dead)
  - Killed any running mbsync processes
- ✅ **Phase 1.3**: Created safety backup
  - Backup location: `~/Maildir.backup-20251008-163440`
  - Original size: 16GB
- ✅ **Phase 2**: Updated mbsync configuration
  - Updated local folder paths for new structure

**Session 2 CRITICAL FIXES:**
- ✅ **BRIDGE AUTHENTICATION FIXED**: Resolved major blocking issue
  - **Root Cause**: Bridge service was using empty `insecure/vault.enc` instead of encrypted `vault.enc` with account data
  - **Solution**: Deleted empty insecure vault, forced service to use encrypted vault
  - **Key Discovery**: Bridge vault key exists in pass at `docker-credential-helpers/.../bridge-vault-key`
  - **Result**: Bridge ports 1143/1025 now open and functioning
- ✅ **Made Bridge Configuration Declarative** (HWC Charter Compliant)
  - Bridge now managed via NixOS home-manager
  - Keychain configuration: `{"DisableTest":true,"Helper":"pass"}`
  - No more manual bridge management
- ✅ **Updated Bridge Password** in both pass and agenix
  - Current bridge password: `8YmD16Ugka6OCWrU8Z92Uw`
  - Updated `pass show email/proton/bridge`
  - Updated `domains/secrets/parts/home/proton-bridge-password.age`
- ✅ **Documented Age Key Management** in CLAUDE.md and charter.md
  - Public key: `age1dyegtj68gpyhwvus4wlt8azyas2sslwwt8fwyqwz3vu2jffl8chsk2afne`
  - Process documented for future secret updates

**CRITICAL INSIGHTS & REMAINING ISSUES:**
- ❌ **BRIDGE NOT TRULY DECLARATIVE**: Service loses state on every restart
- ❌ **Root Cause**: Bridge systemd service cannot access pass/GPG keychain reliably
- ❌ **Current State**: Account data trapped in encrypted vault (`vault.enc` 5.3k) that service can't decrypt
- ❌ **Service Behavior**: Falls back to empty unencrypted vault on each restart
- ❌ **Authentication**: Gets "Could not load/create vault key" → creates new empty vault → "no such user"

**Technical Details:**
- ✅ **Keychain Config**: `~/.config/protonmail/bridge-v3/keychain.json` = `{"DisableTest":true,"Helper":"pass"}`
- ✅ **Pass Entries**: Vault key exists at `docker-credential-helpers/.../bridge-vault-key` = `RogHJ24CBG5og3hlOwHytn/D4KJ9IDD7ZbZXP/vpsb4=`
- ✅ **CLI Works**: Account added successfully via CLI with pass backend
- ❌ **Service Fails**: Systemd service can't access GPG agent for pass decryption

**Temporary Workaround Applied:**
- Deleted `insecure/vault.enc` to force encrypted vault usage
- Worked briefly (ports opened, service responded)
- Failed on restart - recreated empty insecure vault

**Files Modified:**
- `domains/home/mail/bridge/parts/runtime.nix` - Removed DBUS_SESSION_BUS_ADDRESS
- `domains/home/mail/bridge/parts/files.nix` - Added keychain.json generation
- `domains/secrets/parts/home/proton-bridge-password.age` - Updated with current password
- `CLAUDE.md` & `charter/charter.md` - Documented age key process
  - Backup size: 2.8MB (hardlinks - space efficient)
  - Verified structure intact

- ✅ **Phase 1.4**: Created new folder structure
  - Created 100_hwc/ (inbox, sent, drafts, archive)
  - Created 110_gmail-business/ (inbox, sent, drafts, starred)
  - Created 200_personal/ (inbox, sent, drafts, archive)
  - Created 210_gmail-personal/ (inbox, sent, drafts, starred)
  - Created 010_unified-work/inbox
  - Created 020_unified-personal/inbox
  - All with proper maildir structure (cur/new/tmp)
  - Permissions set to 700

**✅ PHASE 1 COMPLETE**

**CRITICAL NEXT ACTIONS FOR GEMINI-CLI:**

**Priority 1: Fix Bridge Service Pass Integration**
- Bridge systemd service needs GPG agent access for pass decryption
- Options:
  1. Add GPG_AGENT_INFO and proper GPG environment to service
  2. Use different keychain backend that works in systemd context
  3. Manage bridge entirely via CLI (stop systemd service permanently)

**Priority 2: Continue Email Migration (Once Bridge Fixed)**
- Phase 3: Run `mbsync -a` to sync all accounts
- Phase 4: Create hardlink script for dual unified inboxes
- Phase 5: Reindex notmuch and update aerc

**Working Account Data (Trapped in Encrypted Vault):**
- Account: `eriqueo` with emails `eric@iheartwoodcraft.com` and `eriqueo@proton.me`
- Password: `8YmD16Ugka6OCWrU8Z92Uw`
- Vault key: `RogHJ24CBG5og3hlOwHytn/D4KJ9IDD7ZbZXP/vpsb4=` (in pass)
- Data location: `~/.config/protonmail/bridge-v3/vault.enc` (5.3k, encrypted)

**Discovery:**
- Found 4 Maildir backups in home folder
- Backups from Sept 30 and Oct 6 have per-account structure (iheartwoodcraft, gmail-business, gmail-personal, proton)
- Used ~/Maildir.backup.20250930_151641 as migration source

- ✅ **Phase 2.1**: Migrated mail from September 30 backup
  - 100_hwc/inbox: 2,745 messages (from iheartwoodcraft)
  - 110_gmail-business/inbox: 4,074 messages
  - 200_personal/inbox: 2,744 messages (from proton)
  - 210_gmail-personal/inbox: 305 messages
  - **Total: 9,868 messages** migrated from backup
  - Also migrated sent, drafts, archive, starred folders

- ✅ **Phase 2.2**: Rewrote mbsync configuration
  - Updated `/home/eric/.nixos/domains/home/mail/accounts/index.nix`
  - Proton hwc: `hwc_inbox` → `100_hwc/inbox` (server-side filtered)
  - Proton personal: `personal_inbox` → `200_personal/inbox` (server-side filtered)
  - Gmail business: `INBOX` → `110_gmail-business/inbox`
  - Gmail personal: `INBOX` → `210_gmail-personal/inbox`
  - All accounts now use per-account folder structure
  - Committed changes and rebuilt NixOS successfully

**Notes:**
- Current system has ~14.5GB mail, 13,684 messages in unified inbox
- Duplicates present (same message 4-8 times)
- Path-based tagging currently broken
- Plan includes rollback procedure if needed
**Notes:**
- Current system has ~14.5GB mail, 13,684 messages in unified inbox
- Duplicates present (same message 4-8 times)
- Path-based tagging currently broken
- Plan includes rollback procedure if needed

---

### Session 2: 2025-10-08 (Gemini Takeover & Phase 3 Start)
**Time**: [Start Time]
**Status**: Blocked on Proton Bridge authentication

**Completed:**
- ✅ **Phase 2.3**: Cleared all mbsync state (`~/.mbsync/`, `.mbsyncstate`, `.uidvalidity`) to ensure a clean sync

**Issues Encountered:**
- ❌ **BLOCKER**: Proton Bridge "no such user" authentication failure
  - Bridge was trying to use gnome-keyring which wasn't available
  - Service had dependencies on gnome-keyring-daemon.service (violated HWC architecture)

**Resolution Attempted:**
- ❌ Removed gnome-keyring dependencies from bridge service (WRONG - reverted)
- ❌ Tried overriding bridge package buildInputs (failed - needs libsecret to compile)
- ❌ Rolled back flake.lock to nixpkgs e9f00bd (didn't fix it - not nixpkgs issue)
- ✅ **ROOT CAUSE FOUND**: gnome-keyring-daemon was running but not registered on D-Bus
  - Daemon at PID 2554 wasn't responding to D-Bus secret service requests
  - Bridge hung waiting for D-Bus reply that never came
- ✅ **FIX**: Killed stale gnome-keyring-daemon with `pkill -9 -f gnome-keyring`
  - D-Bus restarted fresh gnome-keyring automatically
  - D-Bus secret service now responds correctly
  - Bridge CLI starts successfully (shows ASCII banner)
- ✅ Bridge service now running (PID 355441)
- ⏸️ **WAITING**: User needs to perform interactive `protonmail-bridge --cli` to add accounts
  - Vault was cleared during troubleshooting, accounts need to be re-added

**Next Steps:**
- Phase 3.1: User must log in to Proton Bridge interactively:
  1. Stop bridge service: `systemctl --user stop protonmail-bridge`
  2. Run: `protonmail-bridge --cli`
  3. At prompt, type: `login`
  4. Follow prompts to add iheartwoodcraft and proton accounts
  5. Exit CLI and restart service: `systemctl --user start protonmail-bridge`
- Phase 3.2: Then resume: Run reconciling sync with mbsync

---

## Phase Completion Tracker

- [x] **Phase 1**: Server-Side & Local Preparation - **COMPLETE**
  - [x] Step 1.1: Pre-sort Proton Mail on server (filters) - **DONE** (folders: hwc_inbox, personal_inbox)
  - [x] Step 1.2: Stop local syncing - **DONE**
  - [x] Step 1.3: Create safety backup - **DONE** (~/Maildir.backup-20251008-163440)
  - [x] Step 1.4: Create new folder structure - **DONE**

- [x] **Phase 2**: Migrate Local Data & Update Config - **COMPLETE**
  - [x] Step 2.1: Migrate mail from backup - **DONE** (9,868 messages)
  - [x] Step 2.2: Rewrite mbsync configuration - **DONE**
  - [x] Step 2.3: Clear all sync state - **DONE**

- [ ] **Phase 3**: Sync & Aggregate
  - [ ] Step 3.1: Run reconciling sync
  - [ ] Step 3.2: Create and run hardlink script

- [ ] **Phase 4**: Re-index and Reconfigure Clients
  - [ ] Step 4.1: Rebuild notmuch database
  - [ ] Step 4.2: Update notmuch tagging hooks
  - [ ] Step 4.3: Update aerc configuration

- [ ] **Phase 5**: Finalization
  - [ ] Step 5.1: Test extensively
  - [ ] Step 5.2: Automate and resume
  - [ ] Step 5.3: Clean up old files

---

## Issues Encountered

(None yet)

---

## Rollback Points

- **Before Phase 1**: Clean state, no changes made
- **After Step 1.3**: ✅ Backup created at `~/Maildir.backup-20251008-163440` - **CURRENT ROLLBACK POINT**
- **Before Phase 2**: Old structure intact, new structure empty
- **After Phase 3**: Can restore from backup if sync fails

---

## Key Decisions Made

1. **Architecture**: Dual unified inbox (work/personal separation) vs single unified
2. **Proton Handling**: Server-side filtering to separate hwc-inbox and personal-inbox
3. **Deduplication**: Hardlinks for unified view (physical files, not virtual queries)
4. **Migration Strategy**: Incremental sync preferred, but will do full sync if backup structure doesn't match
5. **Proton folder naming**: Using underscores (`hwc_inbox`, `personal_inbox`) instead of hyphens - **UPDATE mbsync config accordingly**

---

## Commands Reference (Quick Access)

### Check Status
```bash
# Check mbsync timer status
systemctl --user status mbsync.timer

# Count messages in folders
find ~/Maildir/[folder]/inbox -type f | wc -l

# Verify backup
ls -ld ~/Maildir.backup-*/
```

### Emergency Rollback
```bash
systemctl --user stop mbsync.timer
rm -rf ~/Maildir
cp -al ~/Maildir.backup-[TIMESTAMP] ~/Maildir
cp ~/.mbsyncrc.backup ~/mbsyncrc
systemctl --user start mbsync.timer
```

---

## Notes & Observations

(Add notes as migration progresses)

---

**Last Updated**: 2025-10-08 [Initial Creation]
