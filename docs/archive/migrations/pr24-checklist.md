# PR #24 Pre-Merge Checklist

Use this checklist when preparing to merge PR #24.

## Pre-Merge Actions

### 1. Fetch and Review PR
- [ ] `gh pr checkout 24`
- [ ] Review changes: `git diff main...HEAD`
- [ ] Read migration plan: `cat docs/migration-pr24-plan.md`

### 2. Apply Critical Fixes

#### Fix 1: Beets Container
File: `domains/server/containers/beets/options.nix`

```bash
# Line 23: hot.downloads.music
sed -i 's|config\.hwc\.paths\.hot\.downloads\.music or "/mnt/hot/downloads/music"|"${config.hwc.paths.hot.downloads}/music"|' \
  domains/server/containers/beets/options.nix

# Line 28: arr.downloads
sed -i 's|"\${config\.hwc\.paths\.arr\.downloads}/beets"|"/opt/downloads/beets"|' \
  domains/server/containers/beets/options.nix
```

**Verify**:
- [ ] Line 23 now reads: `default = "${config.hwc.paths.hot.downloads}/music";`
- [ ] Line 28 now reads: `default = "/opt/downloads/beets";`

#### Fix 2: Beets Native
File: `domains/server/native/beets-native/options.nix`

```bash
sed -i 's|config\.hwc\.paths\.hot\.downloads\.music or "/mnt/hot/downloads/music"|"${config.hwc.paths.hot.downloads}/music"|' \
  domains/server/native/beets-native/options.nix
```

**Verify**:
- [ ] Default now: `"${config.hwc.paths.hot.downloads}/music"`

#### Fix 3: Storage Options
File: `domains/server/native/storage/options.nix`

```bash
sed -i 's|hot\.downloads\.root|hot.downloads|' \
  domains/server/native/storage/options.nix
```

**Verify**:
- [ ] Path now: `"${config.hwc.paths.hot.downloads}/incomplete"`

#### Fix 4: Frigate (Manual Edit Required)
File: `domains/server/native/frigate/options.nix`

**Current** (around line 21):
```nix
default = "${config.hwc.paths.media.surveillance}/frigate/media";
```

**Change to**:
```nix
default = "${config.hwc.paths.media.root}/surveillance/frigate/media";
```

**Steps**:
```bash
$EDITOR domains/server/native/frigate/options.nix
# Find: media.surveillance
# Replace with: media.root}/surveillance
```

- [ ] Updated frigate options.nix

#### Fix 5: Pihole (Manual Edit Required)
File: `domains/server/containers/pihole/options.nix`

**Current** (two locations):
```nix
default = config.hwc.paths.networking.pihole;
default = "${config.hwc.paths.networking.pihole}/dnsmasq.d";
```

**Change to**:
```nix
default = "/opt/networking/pihole";
default = "/opt/networking/pihole/dnsmasq.d";
```

**Steps**:
```bash
$EDITOR domains/server/containers/pihole/options.nix
# Replace config.hwc.paths.networking.pihole with /opt/networking/pihole
```

- [ ] Updated pihole options.nix (both lines)

### 3. Optional: Update Documentation Comments

These won't break builds but should be updated for accuracy:

```bash
# GPU hardware comments
$EDITOR domains/infrastructure/hardware/parts/gpu.nix
# Update references to hwc.paths.cache and hwc.paths.logs

# Monitoring services comments
$EDITOR domains/server/native/{n8n,monitoring/grafana,monitoring/prometheus,monitoring/alertmanager}/index.nix
# Update references to hwc.paths.state
```

- [ ] Updated comment in gpu.nix (optional)
- [ ] Updated comments in monitoring services (optional)

### 4. Machine Configuration Updates

If server uses custom paths, update machine config:

**machines/server/config.nix**:
```nix
{
  # OLD (may no longer work)
  # hwc.paths.hot.root = "/mnt/hot";

  # NEW (use overrides)
  hwc.paths.overrides = {
    hot.root = "/mnt/hot";
    media.root = "/mnt/media";
  };
}
```

- [ ] Updated server config if using custom paths
- [ ] Updated laptop config if using custom paths

### 5. Build Validation

Test on both machines:

```bash
# Laptop
nix flake check
sudo nixos-rebuild build --flake .#hwc-laptop

# Server (if applicable)
sudo nixos-rebuild build --flake .#hwc-server
```

- [ ] Laptop build succeeds
- [ ] Server build succeeds
- [ ] No evaluation errors

### 6. Charter Compliance

```bash
./workspace/nixos/charter-lint.sh domains/
```

- [ ] Charter lint passes
- [ ] No violations in Law 10 (Primitive Module Exception)

### 7. Runtime Testing (Post-Deploy)

After applying changes:

**Laptop**:
```bash
# Check environment variables
env | grep HWC_ | sort
echo $HWC_HOT_STORAGE
echo $HWC_MEDIA_STORAGE

# Check XDG dirs
echo $XDG_DOWNLOAD_DIR
ls ~/000_inbox ~/100_hwc
```

- [ ] HWC variables set correctly
- [ ] XDG directories accessible
- [ ] Home structure intact

**Server**:
```bash
# Check critical services
systemctl status frigate
systemctl status grafana
sudo podman ps | grep -E 'pihole|beets'

# Check path accessibility
ls /opt/downloads/beets 2>/dev/null || echo "May need creation"
ls /opt/networking/pihole 2>/dev/null || echo "May need creation"
ls /mnt/hot /mnt/media
```

- [ ] Frigate running
- [ ] Monitoring stack healthy
- [ ] Containers running
- [ ] Storage accessible

### 8. Data Migration (If Needed)

Check if path changes affect existing data:

```bash
# Server only
if [ -d /opt/adhd-tools ]; then
  echo "WARN: /opt/adhd-tools exists but new path is /opt/adhd"
  echo "Consider: sudo mv /opt/adhd-tools /opt/adhd"
fi
```

- [ ] Checked for /opt/adhd-tools → /opt/adhd migration
- [ ] Moved data if necessary (or created symlink)

### 9. Commit and Document

```bash
git add .
git commit -m "fix: apply PR #24 compatibility updates

- Update beets to use simplified downloads path
- Update frigate to use media.root/surveillance
- Update pihole with hardcoded networking path
- Update storage options for new path structure

Fixes compatibility with PR #24 paths refactor.

Related: https://github.com/eriqueo/nixos-hwc/pull/24"

# Push to feature branch or merge
```

- [ ] Changes committed
- [ ] Descriptive commit message

### 10. Merge Decision

Choose one:

**A. Merge PR #24 now** (if all fixes applied and tested)
```bash
gh pr review 24 --approve
gh pr merge 24
```

**B. Request PR updates** (if you want PR author to include fixes)
```bash
gh pr comment 24 --body "Found breaking changes. See analysis: [link to migration doc]"
```

**C. Delay merge** (if more testing needed)
- Wait for additional validation
- Test on production for 24-48 hours

- [ ] Merge decision made and executed

---

## Emergency Rollback

If something breaks after merge:

```bash
# Quick rollback
git revert HEAD
sudo nixos-rebuild switch --flake .#hwc-laptop

# Or return to main
git checkout main
sudo nixos-rebuild switch --flake .#hwc-laptop
```

---

## Summary

**Total manual steps**: 5 critical files to fix
**Estimated time**: 30-60 minutes for fixes + testing
**Risk level**: HIGH if merged without fixes, LOW after fixes applied

**Files requiring manual attention**:
1. ✅ beets/options.nix (automated)
2. ✅ beets-native/options.nix (automated)
3. ✅ storage/options.nix (automated)
4. ⚠️ frigate/options.nix (manual)
5. ⚠️ pihole/options.nix (manual)
