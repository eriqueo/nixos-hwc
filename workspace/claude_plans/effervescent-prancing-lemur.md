# System Error Remediation Plan

## Executive Summary

**Goal**: Simple, consistent permission model - everything runs as `eric:users`. No per-service users, no DynamicUser complexity, just straightforward permissions that work.

Investigation revealed 4 issues from the error logs:
1. **Media user references** - Legacy user causing tmpfiles failures (CRITICAL - needs fix)
2. **Alertmanager DynamicUser conflict** - Inconsistent with eric-user pattern (CRITICAL - causing service instability)
3. **ntfy service** - Configured but not enabled (USER WANTS ENABLED)
4. **tdarr service** - Intentionally disabled for resource conservation (NO ACTION - working as intended)

**Consistent Pattern Applied Everywhere**: All services run as `eric:users`, all data directories owned by `eric:users`, no exceptions.

---

## Issue 1: Media User References (CRITICAL)

### Problem
Tmpfiles errors on every boot:
```
systemd-tmpfiles[2800948]: /etc/tmpfiles.d/00-nixos.conf:120-123: Failed to resolve user 'media': No such process
```

### Root Cause
`domains/infrastructure/storage/index.nix` line 105 creates directories with `media:media` ownership, but no media user exists. Only a media group is defined (line 107). This is a legacy artifact from before the permission simplification (commit 70851a3).

### Evidence
- Container directories script already uses `chown -R eric:users /mnt/media` (domains/server/containers/_shared/directories.nix:76-78)
- Frigate correctly uses `eric users` for all tmpfiles (domains/server/frigate/index.nix:171-177)
- Recent commits show explicit migration to eric user for all services

### Fix
**File**: `domains/infrastructure/storage/index.nix`

**Change line 105 from:**
```nix
(map (dir: "d ${cfg.media.path}/${dir} 0775 media media -") cfg.media.directories);
```

**To:**
```nix
(map (dir: "d ${cfg.media.path}/${dir} 0755 eric users -") cfg.media.directories);
```

**Remove line 107:**
```nix
users.groups.media = { gid = 1000; };  # DELETE THIS LINE
```

### Affected Directories
- `/mnt/media/movies`
- `/mnt/media/tv`
- `/mnt/media/music`
- `/mnt/media/books`
- `/mnt/media/photos`
- `/mnt/media/downloads`
- `/mnt/media/incomplete`
- `/mnt/media/blackhole`

### Validation
After fix, verify:
```bash
sudo systemd-tmpfiles --create --remove
journalctl -b --no-pager | rg "Failed to resolve user"  # Should be empty
```

---

## Issue 2: Alertmanager Symlink Conflict (CRITICAL)

### Problem
Systemd warning:
```
systemd-tmpfiles[2800948]: "/var/lib/hwc/alertmanager" already exists and is not a directory.
```

Service works but shows instability in logs attempting to create `/var/lib/alertmanager`.

### Root Cause
**Conflicting configuration** in `domains/server/monitoring/alertmanager/index.nix`:

1. Upstream NixOS module uses `DynamicUser=true` (creates symlink at `/var/lib/alertmanager`)
2. Your overrides force `User=eric` + `StateDirectory=hwc/alertmanager` (conflicts with DynamicUser)
3. Tmpfiles rule redundantly tries to create the same directory
4. Result: Multiple systems fighting over directory ownership

### Current Configuration (Lines 68-88)
```nix
systemd.services.alertmanager = {
  serviceConfig = {
    User = lib.mkForce "eric";                    # Conflicts with DynamicUser
    Group = lib.mkForce "users";
    StateDirectory = lib.mkForce "hwc/alertmanager";  # Conflicts with DynamicUser
    # ... DynamicUser=true still active from upstream
  };
};

systemd.tmpfiles.rules = [
  "d ${cfg.dataDir} 0755 eric users -"  # Redundant with StateDirectory
];
```

### Solution: Consistent eric:users Pattern

**File**: `domains/server/monitoring/alertmanager/index.nix`

**Add to line 73 (inside serviceConfig block):**
```nix
systemd.services.alertmanager = {
  serviceConfig = {
    User = lib.mkForce "eric";
    Group = lib.mkForce "users";
    StateDirectory = lib.mkForce "hwc/alertmanager";
    DynamicUser = lib.mkForce false;  # ADD THIS - disable complexity, use simple eric user
    WorkingDirectory = lib.mkForce cfg.dataDir;
    # ... rest of config
  };
};
```

**Remove lines 87-89 (tmpfiles rule - StateDirectory handles this):**
```nix
systemd.tmpfiles.rules = [
  "d ${cfg.dataDir} 0755 eric users -"  # DELETE - redundant
];
```

### Why This Works
- **Simple**: Everything runs as eric:users
- **Consistent**: Matches all other services (Frigate, Jellyfin, Grafana, etc.)
- **No conflicts**: StateDirectory creates directory automatically with correct ownership
- **Just works**: No symlink magic, no dynamic users, no permission surprises

### Validation
After fix:
```bash
sudo systemctl restart alertmanager
systemctl status alertmanager  # Should show no directory creation errors
ls -la /var/lib/alertmanager    # Symlink should be gone
ls -la /var/lib/hwc/alertmanager  # Should be proper directory owned by eric:users
```

---

## Issue 3: ntfy Service Not Running (ENABLE)

### Problem
Health check shows ntfy returning 502 on both:
- Caddy proxy: `https://hwc.ocelot-wahoo.ts.net/notify` → 502
- Direct access: `http://127.0.0.1:2586` → Connection refused

### Root Cause
Service is fully configured but **not enabled**. No `hwc.services.ntfy.enable = true` in machine config or profiles.

### Current State
- Container configuration exists: `domains/server/networking/parts/ntfy.nix`
- Options defined: Port 8080 (default), data directory configured
- Routes configured: `/notify` subpath in `domains/server/routes.nix`
- **But**: `hwc.services.ntfy.enable` is never set to `true`

### Port Configuration Note
- Routes file expects port 2586
- Options default to port 8080
- Container binds internal port 80 to `cfg.port` (which is 8080 by default)

### Solution: Enable with Custom Port

**USER DECISION**: Enable ntfy notification server

**File**: `machines/server/config.nix`

Add after line 97 (after the system.services.ntfy.enable = false):
```nix
# ntfy notification server (container)
hwc.services.ntfy = {
  enable = true;
  port = 2586;  # Match expected port in routes and Tailscale config
};
```

This will:
1. Enable the ntfy container service
2. Set port to 2586 (matching current routes.nix expectations)
3. Container will bind internal port 80 to external 2586
4. Caddy reverse proxy will route `/notify` to `http://127.0.0.1:2586`

---

## Issue 4: tdarr Service Not Running (NO ACTION NEEDED)

### Status
**INTENTIONALLY DISABLED** - This is correct behavior, not an error.

### Evidence
From `profiles/server.nix` lines 307-317:
```nix
# Tdarr video transcoding - INTENTIONALLY DISABLED (high resource usage)
# Disabled because:
# - Resource intensive (~4 CPU cores, 12GB RAM when active)
# - Not needed unless active transcoding pipeline required
# - GPU passthrough configured but service dormant to conserve resources
# - Conflicts with AI workloads for GPU/CPU resources
hwc.services.containers.tdarr.enable = false;
```

### Configuration Status
- Fully configured with GPU acceleration
- Ready to enable if needed
- Deliberately kept off to preserve resources for AI workloads (Ollama, Open WebUI)

### Action
None required. Remove from health check script or keep as informational "disabled by design" status.

---

## Implementation Order

1. **Fix media user issue** (immediate - prevents boot errors)
2. **Fix alertmanager DynamicUser conflict** (immediate - service stability)
3. **Enable ntfy service** (add to machine config)
4. **Update health check script** (optional - mark tdarr as intentionally disabled)

---

## Files to Modify

### Critical Fixes
1. `domains/infrastructure/storage/index.nix` - Lines 105, 107
2. `domains/server/monitoring/alertmanager/index.nix` - Lines 73, 87-89

### ntfy Enable
3. `machines/server/config.nix` - Add ntfy.enable = true with port 2586

### Documentation
5. `workspace/scripts/monitoring/caddy-health-check.sh` - Update tdarr expectations

---

## Validation Steps

After implementing fixes:

```bash
# 1. Rebuild system
sudo nixos-rebuild switch --flake .#hwc-server

# 2. Check for tmpfiles errors
journalctl -b --no-pager | rg "Failed to resolve user"  # Should be empty

# 3. Verify alertmanager
systemctl status alertmanager  # Should be stable
ls -la /var/lib/hwc/alertmanager  # Should be directory, not symlink

# 4. Verify media directories
ls -la /mnt/media/  # All subdirs should be eric:users

# 5. Run health check
health  # Should show all services green except tdarr (intentionally disabled)

# 6. Test ntfy
curl http://127.0.0.1:2586  # Should return ntfy web interface
curl -d "Test notification" https://hwc.ocelot-wahoo.ts.net/notify/test  # Should send notification
```

---

## Consistent Permission Pattern Summary

**Before**: Mixed bag of users (media, DynamicUser, eric, service-specific users)
**After**: Everything runs as `eric:users` - simple, consistent, no surprises

| Service | Old Pattern | New Pattern | Status |
|---------|-------------|-------------|--------|
| Media dirs | `media:media` (user doesn't exist) | `eric:users` | **Fixed** |
| Alertmanager | DynamicUser + eric (conflict) | `eric:users` | **Fixed** |
| Frigate | `eric:users` | `eric:users` | ✅ Already correct |
| Jellyfin | `eric:users` | `eric:users` | ✅ Already correct |
| Grafana | `eric:users` | `eric:users` | ✅ Already correct |
| n8n | `eric:users` | `eric:users` | ✅ Already correct |
| PostgreSQL | `eric:users` | `eric:users` | ✅ Already correct |
| All containers | `eric:users` | `eric:users` | ✅ Already correct |

**Result**: One user, one pattern, zero permission errors.

## Risk Assessment

- **Media user fix**: LOW risk - Just making config match reality (already overridden)
- **Alertmanager fix**: LOW risk - Aligning with existing pattern used everywhere else
- **ntfy enable**: LOW risk - Same pattern as all other services
- **Overall**: Safe cleanup - making configuration consistent with what already works
