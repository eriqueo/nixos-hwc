# Proton Bridge Authentication Failure - Debug History

**Date**: 2025-10-08
**Duration**: ~2 hours
**Status**: UNRESOLVED
**Context**: Email migration Phase 3 - Bridge authentication failing after `nix flake update`

---

## Background

### What Was Working
- Proton Bridge v3.21.2 was working perfectly 3 weeks ago
- User could authenticate via CLI and service ran successfully
- mbsync could sync mail from bridge without issues
- Commit `fa96b80` (3 weeks ago) added gnome-keyring integration - this was when it worked

### What Changed Today
- User ran `nix flake update`
- nixpkgs updated from `e9f00bd893984bc8ce46c895c3bf7cac95331127` to `c9b6fb798541223bbb396d287d16f43520250518`
- Bridge authentication started failing

### Current State
- Bridge version: 3.21.2 (unchanged)
- NixOS version: 25.11 (Xantusia)
- OS build: 25.11.20250928.e9f00bd (after rollback)
- gnome-keyring-daemon: running (PID varies)
- Gluon database: EXISTS with synced emails at `~/.local/share/protonmail/bridge-v3/gluon/`
- Vault files: Multiple vaults exist (encrypted and insecure)

---

## The Core Problem

**Bridge hangs during initialization when trying to test/access the keychain.**

Symptoms:
- CLI `protonmail-bridge --cli login` hangs indefinitely at "Creating keychain list"
- Service starts but doesn't open IMAP/SMTP ports (127.0.0.1:1143, 127.0.0.1:1025)
- Bridge logs show: "Failed to add test credentials to keychain"
- Then: "The vault key could not be retrieved; the vault will not be encrypted"
- Then: HANGS (no further progress)

---

## What Was Attempted (Chronologically)

### Attempt 1: Removed gnome-keyring Dependencies (WRONG)
**Assumption**: gnome-keyring dependencies in service violated HWC architecture

**Actions**:
- Removed `graphical-session-pre.target` from `domains/home/mail/bridge/parts/service.nix`
- Removed `Wants = [ "graphical-session-pre.target" ]`

**Result**: FAILED - Bridge still hung, and this was the WRONG fix
**Commit**: "fix(mail): remove gnome-keyring dependency from protonmail-bridge service"

**User Correction**: Provided git history showing commit `fa96b80` ADDED gnome-keyring intentionally 3 weeks ago when it worked

**Reverted**: Restored `graphical-session-pre.target` dependency
**Commit**: "fix(mail): restore graphical-session-pre dependency for protonmail-bridge"

---

### Attempt 2: Override Bridge Package buildInputs (FAILED)
**Assumption**: Bridge package needs libsecret removed to avoid keychain

**Actions**:
- Modified `domains/home/mail/bridge/options.nix`
- Added `buildInputs = []` override to remove libsecret

**Result**: FAILED - Build error
```
error: Cannot build protonmail-bridge
Package libsecret-1 was not found in the pkg-config search path
```

**Why it failed**: Bridge code imports `github.com/docker/docker-credential-helpers/secretservice` which requires libsecret at COMPILE time. Cannot compile without it.

**Reverted**: Removed buildInputs override
**Commit**: "fix(mail): rollback flake.lock to working nixpkgs version (e9f00bd) for bridge"

---

### Attempt 3: Rollback flake.lock to Old nixpkgs (INEFFECTIVE)
**Assumption**: The nixpkgs update broke the bridge package

**Actions**:
- Rolled back `flake.lock` to nixpkgs `e9f00bd893984bc8ce46c895c3bf7cac95331127` (from 3 weeks ago)
- Rebuilt NixOS with old nixpkgs

**Result**: FAILED - Bridge still hung at keychain initialization with old nixpkgs
**Conclusion**: Problem is NOT the bridge package version from nixpkgs

---

### Attempt 4: Identified Stale gnome-keyring-daemon (PARTIAL SUCCESS)
**Discovery**: gnome-keyring-daemon was running but NOT responding to D-Bus

**Investigation**:
```bash
ps aux | rg gnome-keyring
# Found: PID 2554 running

busctl --user list | rg secret
# Found: org.freedesktop.secrets (activatable) but not active

dbus-send --session --dest=org.freedesktop.secrets ...
# Result: "Did not receive a reply" - TIMEOUT
```

**Root Cause**: gnome-keyring-daemon was running but NOT registered on D-Bus properly

**Fix Attempt**:
```bash
pkill -9 -f gnome-keyring
# D-Bus automatically restarted gnome-keyring
# D-Bus secret service now responds
```

**Result**: PARTIAL SUCCESS
- Bridge CLI now shows ASCII banner (progress!)
- But still hangs waiting for interactive input
- Service still doesn't start IMAP/SMTP servers

---

### Attempt 5: Fixed Bridge Login Username (NECESSARY BUT INSUFFICIENT)
**Discovery**: mbsync was using wrong usernames for Proton accounts

**Problem**:
- mbsync tried to authenticate as `eric@iheartwoodcraft.com` and `eriqueo@proton.me`
- Bridge expects bridge username: `eriqueo` (the Proton account name)

**Actions**:
- Updated `domains/home/mail/accounts/index.nix`
- Set `login = "eriqueo"` for both Proton accounts (iheartwoodcraft and proton)

**Commit**: "fix(mail): set Proton Bridge login to 'eriqueo' for both accounts"

**Result**: CORRECT but couldn't test because bridge still not running

---

### Attempt 6: Added DBUS_SESSION_BUS_ADDRESS Environment (PARTIAL SUCCESS)
**Discovery**: Bridge service didn't have D-Bus session bus address

**Actions**:
- Modified `domains/home/mail/bridge/parts/runtime.nix`
- Added `DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/%U/bus` to baseEnv

**Commit**: "fix(mail): add DBUS_SESSION_BUS_ADDRESS to bridge environment"

**Result**: PARTIAL SUCCESS
- Bridge service now opens IMAP port 1143!
- But: mbsync authentication fails with "no such user"
- Bridge doesn't have account credentials in vault

---

### Attempt 7: Account Re-addition via CLI (PARTIAL SUCCESS)
**Discovery**: User added account via `protonmail-bridge --cli login`

**What Happened**:
- User successfully logged in as `eriqueo`
- Bridge started syncing: "Account eriqueo was added successfully"
- Sync progressed to 100% (took ~30 minutes)
- Gluon database populated with emails

**But Then**:
- mbsync still failed: "no such user"
- Bridge service failed: "Failed to create lock file; another instance is running"
- CLI was still running, preventing service from starting

---

### Attempt 8: Vault File Management (COMPLICATED)
**Discovery**: TWO vault files exist

**Files Found**:
```
~/.config/protonmail/bridge-v3/vault.enc (5.3k, encrypted, locked by keyring)
~/.config/protonmail/bridge-v3/insecure/vault.enc (3.5k, unencrypted)
```

**Analysis**:
- The encrypted vault (5.3k) has the account from CLI login
- The insecure vault (3.5k) is created when keyring fails
- Service can't decrypt encrypted vault (keyring locked)
- Service falls back to empty insecure vault (no accounts)

**Actions**:
- Moved encrypted vault to backup: `vault.enc.backup-20251008`
- Restarted service to use only insecure vault

**Result**: Service starts, IMAP port opens, but vault is EMPTY (no accounts)

---

### Attempt 9: Disable Keychain Test (FAILED)
**Discovery**: Bridge has `keychain.json` config file

**File**: `~/.config/protonmail/bridge-v3/keychain.json`
```json
{
  "Helper": "pass-app",
  "DisableTest": false
}
```

**Actions**:
- Set `"DisableTest": true`
- Restarted service

**Result**: FAILED - Bridge still tests keychain despite DisableTest flag

---

### Attempt 10: Remove Keychain Helper Entirely (FAILED)
**Actions**:
- Set `"Helper": ""` in keychain.json
- Set `"DisableTest": true`

**Result**: FAILED - Bridge still hangs at keychain initialization

---

## Key Files and Locations

### Bridge Data Directories
```
~/.local/share/protonmail/bridge-v3/
├── gluon/
│   └── backend/store/86246291-.../  # Email database (EXISTS, populated)
└── logs/                            # Bridge logs

~/.config/protonmail/bridge-v3/
├── vault.enc.backup-20251008        # Encrypted vault (has account, locked)
├── insecure/vault.enc               # Unencrypted vault (empty)
├── keychain.json                    # Keychain config
└── grpcFocusServerConfig.json

~/.cache/protonmail/bridge-v3/
└── bridge-v3.lock                   # Process lock file
```

### NixOS Configuration Files
```
/home/eric/.nixos/domains/home/mail/bridge/
├── options.nix          # Bridge module options
├── parts/
│   ├── service.nix      # systemd service definition
│   └── runtime.nix      # Environment and args

/home/eric/.nixos/domains/home/mail/accounts/index.nix
# Email account configurations (login usernames)

/home/eric/.nixos/domains/home/mail/mbsync/parts/render.nix
# mbsync configuration generator
```

### Generated Files
```
~/.mbsyncrc               # Generated mbsync config
~/.config/systemd/user/protonmail-bridge.service  # Generated service
```

---

## Error Patterns

### Pattern 1: Keychain Timeout
```
WARN Failed to add test credentials to keychain    error="timed out after 10s"
```
- gnome-keyring not responding to D-Bus
- Fixed by restarting gnome-keyring

### Pattern 2: Locked Collection
```
WARN Failed to add test credentials to keychain    error="Cannot create an item in a locked collection"
ERRO Could not load/create vault key               error="could not create keychain: no keychain"
WARN The vault key could not be retrieved; the vault will not be encrypted
```
- Keyring is locked (password required)
- Bridge creates insecure vault but then HANGS

### Pattern 3: Prompt Dismissed
```
WARN Failed to add test credentials to keychain    error="failed to prompt: prompt dismissed"
```
- GUI password prompt appears but is auto-dismissed
- Happens in headless/systemd context

---

## What We Know For Sure

### Facts
1. **Gluon database EXISTS** with synced emails from the successful CLI login
2. **Bridge v3.21.2 is the SAME VERSION** that worked 3 weeks ago
3. **gnome-keyring is running** but becomes unresponsive periodically
4. **Bridge REQUIRES keychain** to load vault and expose IMAP/SMTP
5. **Two vaults exist**: encrypted (has account, locked) and insecure (empty)
6. **Account was successfully added** via CLI (synced to 100%)
7. **Bridge opens IMAP port** when D-Bus env is set, but has no accounts loaded

### The Chicken-and-Egg Problem
- Bridge needs unlocked keyring to decrypt vault and load accounts
- Keyring requires interactive password prompt to unlock
- systemd service can't provide interactive password
- Without unlocked vault, bridge won't serve IMAP even though it's running

---

## Possible Root Causes (Hypotheses)

### Hypothesis 1: gnome-keyring Auto-Unlock Broken
- **Before**: Keyring auto-unlocked at login (PAM integration?)
- **After flake update**: Something broke auto-unlock
- **Evidence**: Keyring shows "locked collection" errors
- **Solution**: Fix PAM integration or keyring auto-unlock

### Hypothesis 2: Bridge Behavior Changed
- **Unlikely**: Same bridge version (v3.21.2)
- **Possible**: Dependencies changed in nixpkgs affecting bridge runtime behavior
- **Evidence**: Nothing changed in bridge configuration

### Hypothesis 3: D-Bus Session Bus Issues
- **Before**: D-Bus properly initialized for user services
- **After**: D-Bus session bus not available or broken for systemd user services
- **Evidence**: Had to add DBUS_SESSION_BUS_ADDRESS manually
- **Solution**: Fix D-Bus session bus initialization

### Hypothesis 4: Missing PAM/Session Setup
- **Before**: graphical-session-pre.target properly set up keyrings
- **After**: Session initialization broken
- **Evidence**: keyring runs but doesn't auto-unlock
- **Solution**: Fix session initialization order

---

## What Needs to Be Investigated

1. **Why does gnome-keyring keep becoming unresponsive?**
   - D-Bus configuration issue?
   - Session initialization order?
   - Missing dependency?

2. **Why doesn't the keyring auto-unlock?**
   - PAM configuration?
   - login.keyring vs Default_keyring?
   - Password management?

3. **Can bridge run without keychain entirely?**
   - Use insecure vault permanently?
   - Alternative credential storage?
   - Pass-based storage instead?

4. **What changed in nixpkgs between e9f00bd and c9b6fb7?**
   - gnome-keyring package changes?
   - D-Bus service files?
   - PAM configuration?

---

## Potential Solutions to Try

### Solution 1: Fix Keyring Auto-Unlock
**Approach**: Configure PAM or systemd to auto-unlock keyring at login
```bash
# Check PAM configuration
cat /etc/pam.d/login | rg keyring

# Check if login.keyring is the default
cat ~/.local/share/keyrings/default

# Unlock keyring manually via D-Bus
# (requires finding proper D-Bus commands)
```

### Solution 2: Use Bridge GUI Once to Set Up
**Approach**: Run bridge GUI to properly configure vault with unlocked keyring
```bash
systemctl --user stop protonmail-bridge.service
protonmail-bridge  # GUI mode
# Add account via GUI (with keyring prompt)
# Exit GUI
systemctl --user start protonmail-bridge.service
```

### Solution 3: Migrate to Pass-Based Storage
**Approach**: Configure bridge to use `pass` instead of keyring
- Research if bridge supports pass helper directly
- Modify keychain.json to use pass helper
- Store credentials in ~/.password-store/

### Solution 4: Accept Insecure Vault
**Approach**: Use unencrypted vault permanently
- Delete encrypted vault.enc
- Re-add account to insecure vault
- Accept security tradeoff for headless operation

### Solution 5: Run Bridge in User Session, Not systemd
**Approach**: Start bridge from window manager/desktop startup
- Remove from systemd user services
- Add to Hyprland startup
- Requires GUI session to be running

### Solution 6: Investigate nixpkgs Changes
**Approach**: Find what specifically changed affecting keyring
```bash
# Compare gnome-keyring between nixpkgs versions
nix-store --query --references $(nix-build -A gnome.gnome-keyring '<nixpkgs>' --no-out-link)

# Check D-Bus service file changes
diff <old-nixpkgs-dbus-services> <new-nixpkgs-dbus-services>
```

---

## Commands for Next Session

### Diagnostic Commands
```bash
# Check keyring status
ps aux | rg gnome-keyring
busctl --user list | rg secret

# Test D-Bus secret service
dbus-send --session --print-reply --dest=org.freedesktop.secrets \
  /org/freedesktop/secrets \
  org.freedesktop.DBus.Properties.Get \
  string:org.freedesktop.Secret.Service string:Collections

# Check bridge logs
journalctl --user -u protonmail-bridge.service -n 50 --no-pager
tail -50 ~/.local/share/protonmail/bridge-v3/logs/*.log

# Check bridge ports
ss -tlnp | rg "1143\|1025"

# Check vault files
ls -lah ~/.config/protonmail/bridge-v3/*.enc
ls -lah ~/.config/protonmail/bridge-v3/insecure/*.enc

# Check keychain config
cat ~/.config/protonmail/bridge-v3/keychain.json

# Check keyring files
ls -lah ~/.local/share/keyrings/
cat ~/.local/share/keyrings/default
```

### Fix Attempt Commands
```bash
# Restart gnome-keyring
pkill -9 -f gnome-keyring
# Wait for D-Bus to restart it

# Restart bridge service
systemctl --user restart protonmail-bridge.service
systemctl --user status protonmail-bridge.service

# Try bridge GUI
systemctl --user stop protonmail-bridge.service
protonmail-bridge  # GUI mode - may allow keyring unlock

# Test mbsync
mbsync -V iheartwoodcraft-hwc_inbox
```

---

## Git Commits During Debug Session

```
bbb7b4b fix(mail): use per-account maildirName in mbsync Path and Inbox
ac5f0b7 refactor(mail): update mbsync config for dual unified inbox architecture
d70e932 fix(mail): override protonmail-bridge to remove libsecret buildInputs
d642169 fix(mail): restore graphical-session-pre dependency for protonmail-bridge
ea68fc5 fix(mail): rollback flake.lock to working nixpkgs version (e9f00bd) for bridge
e5e5540 docs(email): update migration changelog with D-Bus gnome-keyring fix
5228c97 fix(mail): set Proton Bridge login to 'eriqueo' for both accounts
a480b5d fix(mail): add DBUS_SESSION_BUS_ADDRESS to bridge environment
```

---

## Current System State (End of Session)

### Services
- `protonmail-bridge.service`: Running but hung at keychain initialization
- `gnome-keyring-daemon`: Running (PID varies, keeps restarting)

### Bridge State
- No IMAP/SMTP ports listening (service hung)
- Insecure vault exists but is empty
- Encrypted vault backed up with account data inside (locked)
- Gluon database has ~30 minutes of synced emails

### Configuration
- mbsync config: Uses `eriqueo` as username for Proton accounts (CORRECT)
- Bridge service: Has DBUS_SESSION_BUS_ADDRESS environment (CORRECT)
- keychain.json: Helper="" DisableTest=true (INEFFECTIVE)

### Files Modified
- `domains/home/mail/bridge/parts/runtime.nix` - Added D-Bus env
- `domains/home/mail/accounts/index.nix` - Fixed login usernames
- `~/.config/protonmail/bridge-v3/keychain.json` - Disabled test
- `~/.config/protonmail/bridge-v3/vault.enc` → `vault.enc.backup-20251008`

---

## Recommendations for Better LLM

1. **Don't assume anything** - User said "this was working 3 weeks ago" - BELIEVE THEM
2. **Check git history FIRST** before removing things
3. **gnome-keyring is REQUIRED** - don't try to remove it
4. **Bridge v3 has hard dependency on keychain** - can't bypass easily
5. **The problem is keyring UNLOCK, not keyring existence**
6. **Focus on PAM/session initialization** not bridge package
7. **Try GUI mode early** - it might unlock keyring and fix everything
8. **Read ALL bridge docs** about headless operation and keychain
9. **Check HWC architecture docs** for session management patterns
10. **Test hypotheses quickly** - don't spend 30 minutes on wrong path

---

## Questions for User

1. Do you have a password set on your gnome-keyring login.keyring?
2. Does the keyring auto-unlock when you log into Hyprland normally?
3. Are there any PAM configuration files in HWC for keyring unlock?
4. Has anything else broken since the flake update besides bridge?
5. Do you want to accept an insecure vault (no keyring encryption)?

---

## Additional Context

### Email Migration Plan
This is part of Phase 3 of a larger email migration to dual unified inbox architecture:
- Phase 1: COMPLETE - Server-side filters, local prep, folder creation
- Phase 2: COMPLETE - Data migration, mbsync config updates
- Phase 3: **BLOCKED** - Bridge authentication, mbsync sync
- Phase 4: PENDING - Notmuch reindex, aerc config
- Phase 5: PENDING - Testing, finalization

### HWC Architecture Constraints
- Everything must be declarative in NixOS
- No manual configuration outside of `/etc/nixos/`
- Services must survive reboots
- Must work in headless/systemd context

---

**Last Updated**: 2025-10-08 22:20 MDT
**Next Action**: Try bridge GUI mode to unlock keyring and properly add account
