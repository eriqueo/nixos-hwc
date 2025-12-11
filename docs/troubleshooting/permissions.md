# Permission Troubleshooting - nixos-hwc

**Quick Reference**: Common permission issues and resolutions

**Last Updated**: 2025-12-11
**Version**: 1.0

---

## Table of Contents

1. [Container "Permission Denied" Errors](#1-container-permission-denied-errors)
2. ["Cannot Write to StateDirectory"](#2-cannot-write-to-statedirectory)
3. ["Secret File Not Readable"](#3-secret-file-not-readable)
4. ["$HOME is /" on SSH Login](#4-home-is--on-ssh-login)
5. [Service Fails with Ownership Errors](#5-service-fails-with-ownership-errors)
6. [Diagnostic Commands](#diagnostic-commands)
7. [Prevention Checklist](#prevention-checklist)

---

## 1. Container "Permission Denied" Errors

**Symptom**: Container logs show "Permission denied" when writing to volumes

**Example**:
```
Error: EACCES: permission denied, open '/media/movies/Example.mkv'
```

### Diagnosis

```bash
# Check container environment
sudo podman inspect <container> | jq '.[0].Config.Env | .[] | select(contains("PGID"))'

# Check directory ownership
ls -la /mnt/media/movies
ls -la /opt/downloads/<service>
```

**Expected**: `PGID=100`, directories owned by `eric:users`

### Root Causes

1. **Wrong PGID**: Container using `PGID="1000"` instead of `PGID="100"`
2. **Wrong ownership**: Directory owned by `root:root` instead of `eric:users`
3. **Wrong permissions**: Directory mode less than 0755

### Fix

#### If PGID=1000 (WRONG):
```bash
# 1. Fix in module (see docs/standards/permission-patterns.md Pattern 1)
# Edit domains/server/<service>/index.nix
# Change PGID from "1000" to "100"

# 2. Rebuild system
sudo nixos-rebuild switch --flake .#hwc-server

# 3. Restart container
sudo systemctl restart podman-<service>.service

# 4. Verify
sudo podman inspect <service> | jq '.[0].Config.Env | .[] | select(contains("PGID"))'
```

#### If directory ownership wrong:
```bash
# Fix ownership
sudo chown -R eric:users /mnt/media/<dir>
sudo chmod 755 /mnt/media/<dir>

# Restart container
sudo systemctl restart podman-<service>.service
```

---

## 2. "Cannot Write to StateDirectory"

**Symptom**: Native service fails with "Permission denied" on /var/lib/hwc/<service>

**Example**:
```
Error: Failed to create directory /var/lib/hwc/jellyfin/config: Permission denied
```

### Diagnosis

```bash
# Check service user
systemctl show <service> | grep '^User='
systemctl show <service> | grep '^Group='

# Check StateDirectory ownership
ls -ld /var/lib/hwc/<service>
```

**Expected**: `User=eric`, `Group=users`, directory owned by `eric:users`

### Root Causes

1. **Missing User/Group**: Service using default user instead of eric
2. **Missing mkForce**: NixOS module creating dedicated user
3. **StateDirectory created before User set**: Race condition

### Fix

```nix
# In service module (e.g., domains/server/<service>/index.nix)
systemd.services.<service> = {
  serviceConfig = {
    User = lib.mkForce "eric";      # mkForce is CRITICAL
    Group = lib.mkForce "users";
    StateDirectory = "hwc/<service>";
  };
};
```

**After editing**:
```bash
# Rebuild
sudo nixos-rebuild switch --flake .#hwc-server

# Fix existing directory if needed
sudo chown -R eric:users /var/lib/hwc/<service>

# Restart service
sudo systemctl restart <service>.service
```

---

## 3. "Secret File Not Readable"

**Symptom**: Service can't read `/run/agenix/<secret>`

**Example**:
```
Error: EACCES: permission denied, open '/run/agenix/jellyfin-api-key'
```

### Diagnosis

```bash
# Check secret permissions
ls -l /run/agenix/<secret>

# Check service user groups
id eric

# Check if eric in secrets group
groups eric | grep secrets
```

**Expected**:
- Secret mode: `0440` (r--r-----)
- Secret group: `secrets`
- eric in `secrets` group

### Root Causes

1. **Wrong secret permissions**: Mode not 0440
2. **Wrong secret group**: Not in `secrets` group
3. **Service user not in secrets group**: eric missing from secrets group

### Fix

```nix
# In domains/secrets/declarations/<domain>.nix
age.secrets.<name> = {
  file = ../../parts/<domain>/<name>.age;
  mode = "0440";      # Read-only for owner + group
  owner = "root";
  group = "secrets";  # CRITICAL
};

# Ensure user in secrets group (already configured for eric)
# In domains/system/users/eric.nix
users.users.eric.extraGroups = [ "secrets" ];  # Should already exist
```

**After editing**:
```bash
# Rebuild
sudo nixos-rebuild switch --flake .#hwc-server

# Verify
ls -l /run/agenix/<secret>
groups eric | grep secrets

# Restart service
sudo systemctl restart <service>.service
```

---

## 4. "$HOME is /" on SSH Login

**Symptom**: SSH login shows `HOME=/` instead of `/home/eric`

**Example**:
```bash
$ ssh eric@hwc-server
$ echo $HOME
/
```

### Diagnosis

```bash
# After SSH login
echo $HOME
# If "/" → HOME not set correctly

# Check PAM environment
cat /etc/pam/environment 2>/dev/null || echo "File doesn't exist"

# Check session variables
env | grep HOME
```

**Expected**: `HOME=/home/eric`

### Root Cause

NixOS 26.05 doesn't automatically set HOME in `/etc/pam/environment`, causing SSH logins to default HOME to "/" instead of "/home/eric"

### Fix

**Already applied** in `domains/system/core/paths.nix:404`:
```nix
environment.sessionVariables = {
  HOME = cfg.user.home;  # Explicit HOME for NixOS 26.05
};
```

**If still broken**:
```bash
# Rebuild system
sudo nixos-rebuild switch --flake .#hwc-server

# Re-login (logout and SSH back in)
exit
ssh eric@hwc-server
echo $HOME  # Should show /home/eric
```

---

## 5. Service Fails with Ownership Errors

**Symptom**: Service logs show ownership errors on startup

**Example**:
```
Failed to create runtime directory: Operation not permitted
chown: changing ownership of '/run/<service>': Operation not permitted
```

### Diagnosis

```bash
# Check service definition
systemctl cat <service>.service | grep -E 'User=|Group=|StateDirectory='

# Check runtime directory
ls -ld /run/<service> 2>/dev/null || echo "Doesn't exist"
ls -ld /var/lib/<service> 2>/dev/null || echo "Doesn't exist"

# Check service status
systemctl status <service> --no-pager -l
```

### Common Causes

1. **Missing User/Group**: Service running as wrong user
2. **StateDirectory created before User defined**: Timing issue
3. **mkForce conflict**: Multiple modules trying to set User
4. **RuntimeDirectory without User**: Directory created as root

### Fix

```nix
# Always specify User AND Group together
systemd.services.<service> = {
  serviceConfig = {
    User = lib.mkForce "eric";
    Group = lib.mkForce "users";
    StateDirectory = "hwc/<service>";      # Auto-creates as eric:users
    RuntimeDirectory = "<service>";        # Auto-creates as eric:users
    CacheDirectory = "hwc/<service>";      # Auto-creates as eric:users
  };
};
```

**Manual fix for existing directories**:
```bash
# Fix ownership
sudo chown -R eric:users /var/lib/<service>
sudo chown -R eric:users /var/cache/<service>
sudo chown -R eric:users /run/<service>

# Restart service
sudo systemctl restart <service>.service
```

---

## Diagnostic Commands

### Check all eric-owned services

```bash
# List all services running as eric
systemctl show podman-*.service | grep '^User=' | sort -u
systemctl show *.service | grep 'User=eric' -B1
```

### Find files with wrong GID

```bash
# Find all files with GID=1000 (should be none)
find /mnt/hot /mnt/media -group 1000 2>/dev/null | head -20

# Count by directory
echo "/mnt/hot: $(find /mnt/hot -group 1000 2>/dev/null | wc -l)"
echo "/mnt/media: $(find /mnt/media -group 1000 2>/dev/null | wc -l)"
```

### Check container environments

```bash
# Check PGID for all running containers
for c in $(sudo podman ps --format '{{.Names}}'); do
  echo "=== $c ==="
  sudo podman inspect $c | jq -r '.[0].Config.Env | .[] | select(contains("PGID"))'
done
```

### Verify secrets group

```bash
# Check secrets group exists and has members
getent group secrets

# Check secrets directory
ls -la /run/agenix/

# Check if user in secrets group
groups eric | grep secrets
```

### Check storage tier ownership

```bash
# Check mount points
ls -ld /mnt/hot /mnt/media /mnt/archive /mnt/backup 2>/dev/null

# Check subdirectories
ls -la /mnt/hot/
ls -la /mnt/media/
```

### Comprehensive permission audit

```bash
#!/usr/bin/env bash
# Run comprehensive permission check

echo "=== UID/GID Check ==="
id eric
getent group users
getent group secrets
echo ""

echo "=== Container PGID Check ==="
for c in $(sudo podman ps --format '{{.Names}}'); do
  PGID=$(sudo podman inspect $c | jq -r '.[0].Config.Env | .[] | select(contains("PGID"))')
  echo "$c: $PGID"
done
echo ""

echo "=== GID=1000 Files (should be 0) ==="
echo "/mnt/hot: $(find /mnt/hot -group 1000 2>/dev/null | wc -l)"
echo "/mnt/media: $(find /mnt/media -group 1000 2>/dev/null | wc -l)"
echo "/opt/downloads: $(find /opt/downloads -group 1000 2>/dev/null | wc -l)"
echo ""

echo "=== Storage Tier Ownership ==="
ls -ld /mnt/hot /mnt/media 2>/dev/null
echo ""

echo "=== HOME Check ==="
echo "HOME=$HOME"
ls -ld /home/eric
```

---

## Prevention Checklist

Before adding new service module:

- [ ] Read `docs/standards/permission-patterns.md`
- [ ] Choose correct pattern (Container, StateDirectory, Secrets, Storage)
- [ ] For containers: Use `PGID="100"` (NOT 1000!)
- [ ] For native services: Include `User = mkForce "eric"`
- [ ] For secrets: Set `group = "secrets"`, `mode = "0440"`
- [ ] Add dependency assertions in VALIDATION section
- [ ] Test with `sudo nixos-rebuild test --flake .#<machine>`
- [ ] Verify service starts: `systemctl status <service>`
- [ ] Check file ownership: `ls -la <directories>`
- [ ] Run linter: `./workspace/utilities/lints/charter-lint.sh domains/<domain>`

Before deploying changes:

- [ ] Commit changes to git
- [ ] Review diff: `git diff`
- [ ] Run `nix flake check`
- [ ] Test build: `sudo nixos-rebuild test`
- [ ] Check for errors in service logs
- [ ] Verify no GID=1000 files created during test

After deployment:

- [ ] Verify containers have PGID=100
- [ ] Check for GID=1000 files (should be none)
- [ ] Test service functionality
- [ ] Monitor logs for permission errors
- [ ] Document any issues in git commit

---

## Quick Reference Card

| Issue | Quick Check | Quick Fix |
|-------|-------------|-----------|
| Container can't write | `sudo podman inspect <c> \| jq '.Config.Env'` | Change PGID to "100" |
| Service can't write | `systemctl show <s> \| grep User` | Add `User = mkForce "eric"` |
| Secret not readable | `ls -l /run/agenix/<s>` | Set `group = "secrets"` |
| HOME is / | `echo $HOME` | Rebuild system |
| GID=1000 files | `find /mnt -group 1000` | Run migration script |

---

## References

- **Permission Patterns**: `docs/standards/permission-patterns.md`
- **CHARTER.md**: Permission Model section
- **Migration Script**: `workspace/setup/fix-permissions-migration.sh`
- **Linter**: `workspace/utilities/lints/charter-lint.sh`
- **Plan**: `/home/eric/.claude/plans/structured-dazzling-backus.md`

---

**Version History**:
- v1.0 (2025-12-11): Initial troubleshooting guide
