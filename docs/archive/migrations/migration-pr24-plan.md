# PR #24 Migration Plan: Paths Module Refactor

**PR**: https://github.com/eriqueo/nixos-hwc/pull/24
**Title**: feat(paths): add primitive hwc.paths module and filesystem materializer
**Risk Level**: 🔴 HIGH - Breaking changes to path structure
**Estimated Time**: 2-3 hours for careful migration

---

## Executive Summary

PR #24 introduces a major refactor of the paths system:
- **Moves** `domains/system/core/paths.nix` → `domains/paths/paths.nix`
- **Simplifies** path structure by removing ~20 nested options
- **Introduces** new override system (`hwc.paths.overrides`)
- **Updates** Charter to v10.1 (Law 9: Filesystem Materialization, Law 10: Primitive Module Exception)
- **Removes** several path options that modules currently depend on

**⚠️ CRITICAL**: This refactor will break 8+ modules if merged without updates.

---

## Breaking Changes Summary

### 1. Removed Options (MUST update modules)

| Old Option | Status | Affected Modules |
|------------|--------|------------------|
| `hwc.paths.hot.downloads.root` | → `hwc.paths.hot.downloads` (string) | storage, beets, beets-native |
| `hwc.paths.hot.downloads.music` | ❌ REMOVED | beets, beets-native |
| `hwc.paths.media.surveillance` | ❌ REMOVED | frigate |
| `hwc.paths.arr.downloads` | ❌ REMOVED | beets |
| `hwc.paths.networking.pihole` | ❌ REMOVED | pihole |
| `hwc.paths.state` | ❌ REMOVED | n8n, grafana, prometheus, alertmanager |
| `hwc.paths.cache` | ❌ REMOVED | gpu hardware |
| `hwc.paths.logs` | ❌ REMOVED | gpu hardware |
| `hwc.paths.temp` | ❌ REMOVED | (none found) |
| `hwc.paths.userDirs.*` | ❌ REMOVED | xdg-dirs |
| `hwc.paths.mediaPaths.*` | ❌ REMOVED | (none found) |

### 2. Changed Paths

| Old Value | New Value | Impact |
|-----------|-----------|--------|
| `hwc.paths.adhd.root = "/opt/adhd-tools"` | `"/opt/adhd"` | Path change on server |

### 3. Removed Environment Variables

- `HWC_HOT_DOWNLOADS_MUSIC` - used by beets
- `HWC_MEDIA_SURVEILLANCE` - may be used in scripts
- `HWC_STATE_DIR`, `HWC_CACHE_DIR`, `HWC_LOGS_DIR`, `HWC_TEMP_DIR` - used by various services
- `HWC_NETWORKING_*` - pihole related
- `HWC_LIDARR_CONFIG`, `HWC_RADARR_CONFIG`, etc. - all *arr paths
- `HWC_XDG_*` - all XDG directory variables
- `HEARTWOOD_COLD_STORAGE`, `HEARTWOOD_SECRETS_DIR`, `HEARTWOOD_SOPS_AGE_KEY` - legacy

---

## Files Requiring Updates

### Critical Priority (Will Break Build)

#### 1. `domains/server/containers/beets/options.nix`
**Line 23**:
```nix
# OLD (BROKEN)
default = config.hwc.paths.hot.downloads.music or "/mnt/hot/downloads/music";

# FIX: Replace with
default = "${config.hwc.paths.hot.downloads}/music";
```

**Line 28**:
```nix
# OLD (BROKEN)
default = "${config.hwc.paths.arr.downloads}/beets";

# FIX: Replace with hardcoded or new override
default = "/opt/downloads/beets";
```

#### 2. `domains/server/native/beets-native/options.nix`
**Line**: (same as beets above)
```nix
# OLD (BROKEN)
default = config.hwc.paths.hot.downloads.music or "/mnt/hot/downloads/music";

# FIX: Replace with
default = "${config.hwc.paths.hot.downloads}/music";
```

#### 3. `domains/server/native/storage/options.nix`
**Line**: (references hot.downloads.root)
```nix
# OLD (BROKEN)
"${config.hwc.paths.hot.downloads.root}/incomplete"

# FIX: Replace with
"${config.hwc.paths.hot.downloads}/incomplete"
```

#### 4. `domains/server/native/frigate/options.nix`
**Line**: (references media.surveillance)
```nix
# OLD (BROKEN)
default = "${config.hwc.paths.media.surveillance}/frigate/media";

# FIX: Use media root directly
default = "${config.hwc.paths.media.root}/surveillance/frigate/media";
```

#### 5. `domains/server/containers/pihole/options.nix`
**Two references to networking.pihole**:
```nix
# OLD (BROKEN)
default = config.hwc.paths.networking.pihole;
default = "${config.hwc.paths.networking.pihole}/dnsmasq.d";

# FIX: Define locally or use new override
default = "/opt/networking/pihole";
default = "/opt/networking/pihole/dnsmasq.d";
```

### Medium Priority (Comments/Documentation Only)

#### 6. `domains/server/native/n8n/index.nix`
- Update comment referencing `hwc.paths.state`

#### 7. `domains/infrastructure/hardware/parts/gpu.nix`
- Update comments referencing `hwc.paths.cache` and `hwc.paths.logs`

#### 8. `domains/server/native/monitoring/*/index.nix`
- Update comments in: prometheus, alertmanager, grafana
- References to `hwc.paths.state` in comments

### Low Priority (May Cause Issues)

#### 9. `domains/home/core/xdg-dirs.nix`
- Currently imports `domains/system/core/paths.nix`
- **Must update import** to new location or ensure paths are still accessible

---

## File Location Changes

### Import Updates Required

All modules importing paths need updates:

```nix
# OLD
imports = [ ../system/core/paths.nix ];

# NEW (paths now in domains/paths/)
# Actually, paths.nix should be imported through profiles
# Most modules don't need to import it directly
```

### System Core Index Update

`domains/system/core/index.nix` must change:
```nix
# OLD
imports = [
  ./paths.nix
];

# NEW (if paths moves out)
# Remove paths.nix import or update path
```

---

## Migration Strategy

### Phase 1: Pre-Merge Assessment (1 hour)

1. **Backup current state**
   ```bash
   cd ~/.nixos
   git stash
   git checkout main
   git pull origin main
   ```

2. **Fetch PR branch locally**
   ```bash
   gh pr checkout 24
   # Or: git fetch origin pull/24/head:pr-24 && git checkout pr-24
   ```

3. **Review exact changes**
   ```bash
   git diff main...pr-24 -- domains/
   ```

4. **Test build (expect failures)**
   ```bash
   nix flake check 2>&1 | tee /tmp/pr24-build-errors.txt
   ```

### Phase 2: Fix Breaking Changes (1-2 hours)

#### Step 1: Update Beets Modules
```bash
# domains/server/containers/beets/options.nix
sed -i 's|config\.hwc\.paths\.hot\.downloads\.music|${config.hwc.paths.hot.downloads}/music|g' \
  domains/server/containers/beets/options.nix

sed -i 's|config\.hwc\.paths\.arr\.downloads|/opt/downloads|g' \
  domains/server/containers/beets/options.nix

# domains/server/native/beets-native/options.nix
sed -i 's|config\.hwc\.paths\.hot\.downloads\.music|${config.hwc.paths.hot.downloads}/music|g' \
  domains/server/native/beets-native/options.nix
```

#### Step 2: Update Storage Options
```bash
# domains/server/native/storage/options.nix
sed -i 's|hot\.downloads\.root|hot.downloads|g' \
  domains/server/native/storage/options.nix
```

#### Step 3: Update Frigate
```bash
# domains/server/native/frigate/options.nix
# Manual edit required - replace:
#   ${config.hwc.paths.media.surveillance}/frigate/media
# With:
#   ${config.hwc.paths.media.root}/surveillance/frigate/media
```

#### Step 4: Update Pihole
```bash
# domains/server/containers/pihole/options.nix
# Manual edit - replace networking.pihole with hardcoded /opt/networking/pihole
```

#### Step 5: Update Home XDG Dirs
```bash
# domains/home/core/xdg-dirs.nix
# Update import if needed
```

#### Step 6: Update System Core
```bash
# domains/system/core/index.nix
# Verify paths.nix is still imported or update to new location
```

### Phase 3: Machine-Specific Overrides (30 min)

If you have machine-specific path overrides:

**machines/server/config.nix**:
```nix
# OLD (no longer works)
hwc.paths.hot.root = "/mnt/hot";
hwc.paths.media.root = "/mnt/media";

# NEW (use overrides)
hwc.paths.overrides = {
  hot.root = "/mnt/hot";
  media.root = "/mnt/media";
};
```

### Phase 4: Validation (30 min)

1. **Rebuild and test**
   ```bash
   nix flake check
   sudo nixos-rebuild build --flake .#hwc-laptop
   sudo nixos-rebuild build --flake .#hwc-server
   ```

2. **Check path values**
   ```bash
   # After applying config
   env | grep HWC_ | sort

   # Verify key paths exist
   echo $HWC_HOT_STORAGE
   echo $HWC_MEDIA_STORAGE
   ```

3. **Run charter lint**
   ```bash
   ./workspace/nixos/charter-lint.sh domains/
   ```

4. **Test affected services**
   ```bash
   # On server
   systemctl status frigate
   systemctl status grafana
   systemctl status n8n
   sudo podman ps | grep -E 'pihole|beets'
   ```

---

## Rollback Plan

If migration fails:

```bash
# Return to main branch
git checkout main
sudo nixos-rebuild switch --flake .#hwc-laptop  # or hwc-server

# Or if already committed
git revert <commit-hash>
sudo nixos-rebuild switch --flake .#hwc-laptop
```

---

## Risk Assessment

### High Risk Areas

1. **Server media services** - Frigate, Beets rely on removed paths
2. **Download paths** - Multiple services reference arr.downloads
3. **Monitoring stack** - References hwc.paths.state (removed)
4. **Pihole** - References networking.pihole (removed)

### Low Risk Areas

1. **AI services** - Mostly use /opt/ai which is preserved
2. **Business services** - Use /opt/business which is preserved
3. **User home structure** - PARA paths preserved

### Data Loss Risk

**⚠️ CRITICAL: Path changes could cause data accessibility issues**

- `/opt/adhd-tools` → `/opt/adhd`: If server has data at old path, services won't find it
- Symlinks may be needed temporarily

---

## Testing Checklist

After migration, verify:

### Laptop
- [ ] Build succeeds: `nix flake check`
- [ ] XDG directories work: `echo $XDG_DOWNLOAD_DIR`
- [ ] Home paths accessible: `ls ~/000_inbox ~/100_hwc`

### Server
- [ ] Build succeeds: `nix flake check`
- [ ] Frigate running: `systemctl status frigate`
- [ ] Beets accessible: `ls /opt/downloads/beets` or wherever moved
- [ ] Pihole running: `sudo podman ps | grep pihole`
- [ ] Monitoring stack: `systemctl status grafana prometheus`
- [ ] Storage paths valid: `ls /mnt/hot /mnt/media`

### Both Machines
- [ ] Session variables set: `env | grep HWC_`
- [ ] No evaluation errors: `nix flake check`
- [ ] Charter compliance: `./workspace/nixos/charter-lint.sh`

---

## Post-Migration Actions

1. **Update any custom scripts** that reference removed env vars
2. **Update documentation** referencing old path structure
3. **Consider adding machine overrides** for server storage paths
4. **Monitor services** for 24-48 hours post-migration

---

## Questions to Resolve Before Merging

1. **arr.downloads removal**: Do we need a new path for this? Currently used by beets
2. **networking.pihole removal**: Should this be re-added or hardcoded?
3. **state/cache/logs removal**: Are these truly unused or just not grep-able?
4. **XDG directories**: How will xdg-dirs.nix access user directories now?
5. **ADHD path change**: Will `/opt/adhd-tools` → `/opt/adhd` break existing server data?

---

## Recommended Approach

**Option 1: Fix-then-merge** (Recommended)
1. Create feature branch from PR #24
2. Apply all fixes documented above
3. Test both machines
4. Merge when green

**Option 2: Merge-then-fix** (Not Recommended)
- Higher risk of broken state
- May require multiple rebuild cycles
- Could leave system temporarily broken

**Option 3: Request PR updates** (Safest but slowest)
1. Comment on PR #24 with breaking changes list
2. Ask PR author to include compatibility shims
3. Wait for updates before merging

---

## Additional Notes

- **Charter v10.1 compliance**: New linter rules added, ensure charter-lint.sh works
- **Primitive module exception**: Only `domains/paths/paths.nix` exempt from options.nix rule
- **CI checks**: New `ci/checks.sh` validates primitive header exists

---

**Document Version**: 1.0
**Last Updated**: 2026-01-11
**Author**: Claude (via Eric's request)
