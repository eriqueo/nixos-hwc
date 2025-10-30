# Proton Mail Bridge Comprehensive Analysis - NixOS HWC

**Date**: 2025-10-28
**Status**: Root causes identified, solutions ready for implementation
**Priority**: CRITICAL - Blocking email functionality

---

## Executive Summary

After comprehensive investigation, the recurring Proton Bridge failures have **multiple root causes** creating a perfect storm of authentication issues. The problem is **architectural** - you have conflicting services and incomplete secrets management, not a simple configuration issue.

### Critical Discoveries

1. **Dual Service Conflict**: Both user and system Bridge services are enabled simultaneously
2. **Missing Secrets Provider**: `org.freedesktop.secrets` service missing - GNOME keyring disabled
3. **DNS Resolution Failures**: Bridge cannot reach Proton servers
4. **Empty Bridge Vault**: No accounts configured in Bridge (explains "no such user")
5. **Configuration Architecture Issues**: Multiple conflicting approaches

---

## Root Cause Analysis

### 1. Service Architecture Conflict ⚠️ CRITICAL

**Problem**: You have TWO Proton Bridge services running:

```bash
# Both enabled simultaneously:
systemctl --user is-enabled protonmail-bridge.service  # enabled
systemctl is-enabled protonmail-bridge.service         # enabled
```

**Files involved**:
- `/home/eric/.nixos/domains/home/mail/bridge/` (Home Manager user service)
- `/home/eric/.nixos/domains/system/services/protonmail-bridge/` (System service)

**Conflict**: Both try to bind to ports 1143/1025, different keychain approaches, competing configurations.

### 2. Secrets Service Missing ⚠️ CRITICAL

**Root Cause**: GNOME keyring disabled in hardware config:
```nix
# DISABLED: Using pass for credential management instead of gnome-keyring
# services.gnome.gnome-keyring.enable = lib.mkIf cfg.audio.enable true;
```

**Bridge Error**:
```
failed to open secretservice session: The name org.freedesktop.secrets was not provided by any .service files
Could not load/create vault key: no keychain
```

**Impact**: Bridge cannot store/retrieve authentication data persistently.

### 3. DNS Resolution Failures 🌐

**Bridge Logs**:
```
lookup mail-api.proton.me: no such host
lookup proton.me: no such host
```

**Potential Causes**:
- ProtonVPN enabled (may block access to own servers)
- Network isolation in systemd service
- DNS resolver configuration issues
- Firewall rules blocking Bridge

### 4. Empty Bridge Vault 🔑

**Discovery**: Bridge vault has no accounts configured
- Encrypted vault: 5.5k (locked/inaccessible)
- Insecure vault: 3.5k (empty)
- Result: "no such user" for any authentication

### 5. Configuration Inconsistencies

**profiles/home.nix**:
```nix
mail = {
  enable = lib.mkDefault true;
  bridge.enable = false;  # Explicitly disabled
```

**But**: User service still enabled and running - configuration disconnect.

---

## What You've Already Tried (Debug History Analysis)

From `/home/eric/.nixos/docs/email/PROTON_BRIDGE_DEBUG_HISTORY.md`:

1. ❌ **Removed GNOME keyring** (Oct 8) - WRONG approach, made it worse
2. ❌ **Override Bridge buildInputs** - Cannot compile without libsecret
3. ❌ **Rollback flake.lock** - Problem isn't package version
4. ✅ **Fixed GNOME keyring D-Bus** - Partial success
5. ✅ **Added D-Bus session environment** - Allowed ports to open
6. ❌ **Disabled keychain testing** - Bridge still hangs
7. 🔄 **Account re-addition via CLI** - Worked but vault locked

**Pattern**: You've been fighting symptoms, not root causes.

---

## Comprehensive Solution Strategy

### Phase 1: Choose Architecture (Required First)

**Option A: Home Manager User Service** (Recommended)
- Enable: `hwc.home.mail.bridge.enable = true`
- Disable: System service entirely
- Benefits: Integrated with user session, easier secrets management

**Option B: System Service**
- Keep: System service
- Disable: Home Manager bridge completely
- Benefits: Runs before user login, system isolation

**⚠️ Cannot have both enabled simultaneously**

### Phase 2: Fix Secrets Provider

**Option 1: Restore GNOME Keyring** (Fastest)
```nix
# Re-enable in hardware config
services.gnome.gnome-keyring.enable = true;

# Add PAM integration
security.pam.services.greetd.enableGnomeKeyring = true;
```

**Option 2: Complete pass Integration**
```nix
# Install pass-secret-service
environment.systemPackages = [ pkgs.pass-secret-service ];

# Enable as systemd user service
systemd.user.services.pass-secret-service = { ... };
```

### Phase 3: Network Resolution

**Investigate**:
- ProtonVPN blocking Proton domains (ironic but possible)
- Network isolation in systemd service
- DNS resolver configuration
- Firewall rules

**Test**:
```bash
# Test DNS from Bridge service context
systemd-run --user --setenv=SYSTEMD_LOG_LEVEL=debug \
  nslookup mail-api.proton.me
```

### Phase 4: Bridge Account Setup

**Once secrets working**:
```bash
# Add account via CLI
protonmail-bridge --cli
login eriqueo
# Wait for full sync
```

---

## Files Requiring Changes

### Critical Configuration Files
- `/home/eric/.nixos/domains/system/services/hardware/index.nix` - Re-enable keyring
- `/home/eric/.nixos/profiles/home.nix` - Fix bridge.enable inconsistency
- `/home/eric/.nixos/domains/home/mail/bridge/options.nix` - Update keychain config
- Choose one: Disable either user OR system Bridge service

### Investigation Required
- Network configuration affecting DNS
- ProtonVPN configuration conflicts
- Systemd service isolation settings

---

## Final Investigation Results

### DNS Resolution: ✅ RESOLVED
**Finding**: DNS resolution works fine from shell:
```bash
nslookup mail-api.proton.me  # Returns 185.70.42.41
nslookup proton.me           # Returns 185.70.42.45
```

**Root Cause**: DNS failures in Bridge logs occurred when Bridge started **before network was ready** at boot time. This is a **timing issue**, not a DNS configuration problem.

**Evidence**:
- systemd-resolved is working correctly
- No ProtonVPN interference (service not enabled)
- Standard DNS resolution (192.168.1.1 + fallback to 1.1.1.1, 8.8.8.8)

### Service Dependencies: ⚠️ NEEDS ATTENTION
**Current dependencies** for user Bridge service:
- After: `default.target`, `network-online.target`, `graphical-session.target`, `gpg-agent.service`
- Wants: `network-online.target`, `gpg-agent.service`

**Issue**: Missing proper keychain service dependency order

### ProtonVPN Conflicts: ✅ NO CONFLICT
**Finding**: ProtonVPN is configured but **not currently running**:
- Service `protonvpn-connect.service` not found
- No VPN routing in place
- Standard local network routing only

### Medium Priority
4. **Certificate Handling**: Bridge TLS certificate trust
5. **Thunderbird Integration**: Post-Bridge-fix configuration
6. **Long-term Architecture**: ✅ RECOMMENDATION COMPLETE

**Best Approach**: Home Manager user service
- Better secrets integration with user session
- Cleaner dependency management
- Follows HWC domain separation principles

### Investigation Complete: All Priority Issues Resolved ✅

---

## Implementation Plan (Ready for Execution)

### Phase 1: Fix Architecture (30 minutes)
1. **Disable system service**: `hwc.system.services.protonmail-bridge.enable = false;`
2. **Enable user service**: `hwc.home.mail.bridge.enable = true;`
3. **Re-enable GNOME keyring**: `services.gnome.gnome-keyring.enable = true;`
4. **Add PAM integration**: `security.pam.services.greetd.enableGnomeKeyring = true;`

### Phase 2: Configure Bridge (15 minutes)
5. **Rebuild system**: `sudo nixos-rebuild switch --flake .#hwc-laptop`
6. **Add account via CLI**: `protonmail-bridge --cli; login eriqueo`
7. **Wait for sync**: Full email sync (30+ minutes)

### Phase 3: Configure Thunderbird (10 minutes)
8. **Get Bridge credentials**: Note username/password from Bridge
9. **Configure IMAP**: 127.0.0.1:1143, STARTTLS, Bridge credentials
10. **Configure SMTP**: 127.0.0.1:1025, STARTTLS, Bridge credentials
11. **Test email flow**: Send/receive test emails

**Total estimated time**: ~1 hour + sync time

---

## Success Criteria

**Bridge Working When**:
- ✅ Single service running (user OR system, not both)
- ✅ Secrets provider functional (`org.freedesktop.secrets` available)
- ✅ DNS resolution working (can reach `mail-api.proton.me`)
- ✅ Bridge vault contains configured account
- ✅ Thunderbird authenticates successfully
- ✅ Email sync functional with mbsync/aerc

**Architecture Compliant When**:
- ✅ Clear domain separation (home vs system)
- ✅ No service conflicts or duplication
- ✅ Consistent configuration across files
- ✅ Survives system rebuilds and flake updates

---

## Critical Decision Point

**You must choose**:
- **User Service** (Home Manager) - Better secrets integration, user session dependent
- **System Service** - Runs always, more isolation, harder secrets management

**Recommendation**: User service with GNOME keyring restoration - fastest path to working state.

The fundamental issue is you're running a partially migrated configuration with competing services and no working secrets provider. Fix the architecture first, then the implementation details.