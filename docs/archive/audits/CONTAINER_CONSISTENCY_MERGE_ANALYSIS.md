# Container Consistency Branch - Merge Analysis

**Date:** 2025-11-20
**Branch:** `claude/analyze-container-consistency-01Y3ZNXstKgnaCUbuyPVEjmn`
**Status:** ⚠️ NEEDS CAREFUL REVIEW - Branch approach conflicts with current main

---

## Executive Summary

The `analyze-container-consistency` branch attempted to migrate all 14 containers to Charter v6 compliance by:
1. Moving container definitions from `sys.nix` → `parts/config.nix`
2. Disabling `sys.nix` files (set to `lib.mkIf false { }`)
3. Adding comprehensive assertions and validation

**CRITICAL FINDING:**
- The branch is **41 commits behind main**
- Main has **evolved differently** - containers still use `sys.nix` with mkContainer
- Merging as-is would **BREAK all containers** by disabling their active definitions

**RECOMMENDATION:**
**DO NOT MERGE** - Instead, extract valuable patterns and apply selectively

---

## What The Branch Does Right

### 1. Comprehensive Assertions ✅
Example from branch's sonarr/parts/config.nix:
```nix
assertions = [
  {
    assertion = cfg.network.mode != "vpn" || config.hwc.server.containers.gluetun.enable;
    message = "Sonarr with VPN networking requires gluetun container to be enabled";
  }
  {
    assertion = paths.media != null;
    message = "Sonarr requires hwc.paths.media to be configured for TV library";
  }
  {
    assertion = paths.hot != null;
    message = "Sonarr requires hwc.paths.hot to be configured for downloads";
  }
];
```
**Value:** These assertions are excellent and should be adopted

### 2. Proper systemd Dependencies ✅
```nix
systemd.services.podman-sonarr = {
  after = [
    "network-online.target"
    "agenix.service"
  ] ++ (
    if cfg.network.mode == "vpn"
    then [ "podman-gluetun.service" ]
    else [ "init-media-network.service" ]
  );
  wants = [ "network-online.target" ];
  requires = if cfg.network.mode == "vpn" then [ "podman-gluetun.service" ] else [];
};
```
**Value:** More robust than current main's simple dependency lists

### 3. Resource Limits ✅
```nix
extraOptions = [
  "--memory=2g"
  "--cpus=1.0"
  "--memory-swap=4g"
];
```
**Value:** Good production practice, currently missing in main

### 4. Documentation ✅
The branch includes:
- `CONTAINER_CONSISTENCY_ANALYSIS.md` - Excellent audit document
- `CONTAINER_MIGRATION_FIXES.md` - Detailed migration notes
- Validation scripts

**Value:** Documentation should be preserved

---

## What The Branch Does Wrong

### 1. Staleness ❌
- **41 commits behind main**
- Main has continued evolving containers independently
- Changes may be obsolete or conflict with recent work

### 2. All-or-Nothing Approach ❌
- Disables ALL sys.nix files at once
- No incremental migration path
- High risk of breaking everything

### 3. Assumption Mismatch ❌
**Branch assumes:**
- `sys.nix` should be disabled
- Full container definition moves to `parts/config.nix`

**Main's reality:**
- `sys.nix` uses mkContainer helper (active and working)
- `parts/config.nix` only adds systemd dependencies
- Both coexist peacefully (no conflicts currently)

---

## Conflict Analysis

### Test Merge Results
```bash
git merge origin/claude/analyze-container-consistency-01Y3ZNXstKgnaCUbuyPVEjmn
# Result: Only 1 conflict (slskd/parts/config.nix)
```

**Good News:** Surprisingly few conflicts!
**Bad News:** Successful merge ≠ working system

### What Would Break

If we merged the branch as-is:

**Containers with disabled sys.nix:**
- sonarr, radarr, lidarr, prowlarr
- navidrome, jellyfin, jellyseerr, immich
- beets, caddy

**Result:**
- All 10 containers would have NO container definition
- `parts/config.nix` from branch would activate
- BUT those files are 41 commits old
- Configuration drift = likely failures

---

## Recommended Strategy

### Option A: Cherry-Pick Specific Improvements (RECOMMENDED)
Extract valuable patterns without breaking current system:

#### 1. Add Assertions to Current System
For each container in main, enhance `parts/config.nix` with:
```nix
assertions = [
  # Dependency checks
  # Path validations
  # Network mode validations
];
```

#### 2. Add Resource Limits
Update mkContainer calls in `sys.nix`:
```nix
helpers.mkContainer {
  name = "sonarr";
  extraOptions = [
    "--memory=2g"
    "--cpus=1.0"
  ];
  # ... rest of config
}
```

#### 3. Improve systemd Dependencies
Enhance `parts/config.nix` files:
```nix
systemd.services."podman-${name}".after = [
  "network-online.target"
  "agenix.service"
] ++ conditionalDeps;
```

#### 4. Adopt Documentation
Copy analysis documents to main:
- `docs/architecture/CONTAINER_CONSISTENCY_ANALYSIS.md`
- Validation scripts

**Benefits:**
- ✅ No risk of breaking current system
- ✅ Incremental improvements
- ✅ Can test each change independently
- ✅ Maintains current architecture

---

### Option B: Full Rebase and Migration (HIGH RISK)
1. Rebase branch onto current main (41 commits)
2. Resolve all conflicts
3. Test EVERY container starts
4. Verify all routes work via Caddy
5. Check GPU passthrough still works
6. Validate VPN fail-safe with gluetun

**Effort:** 4-8 hours
**Risk:** HIGH - too many moving parts
**Benefit:** Charter v6 compliance

---

### Option C: Archive and Reference (SAFE)
1. Don't merge the branch
2. Keep it as reference documentation
3. Use it as blueprint for future incremental improvements

**Benefits:**
- ✅ Zero risk
- ✅ Preserves valuable analysis
- ✅ Can cherry-pick ideas over time

---

## Specific Changes Worth Adopting

### 1. Navidrome Music Library Mount
**Branch correctly identified:**
```nix
volumes = [
  "${paths.media}/music:/music:ro"  # ← MISSING in main!
];
```

**Main currently has:**
```nix
volumes = [
  "/opt/downloads/navidrome:/config"
  # ← No music library mount!
];
```

**Action:** Add music mount to main's navidrome/sys.nix

---

### 2. Recyclarr Assertion Syntax Fix
**Branch fixed:**
```nix
# WRONG (in old version):
assertion = config.age.secrets ? cfg.services.recyclarr.apiKeySecret;

# CORRECT (in branch):
assertion = builtins.hasAttr cfg.services.recyclarr.apiKeySecret config.age.secrets;
```

**Action:** Check if main's recyclarr has this issue

---

### 3. Container Validation Script
**Branch provides:**
```bash
scripts/validate-containers.sh
scripts/lints/container-lint.sh
```

**Action:** Copy scripts to main for ongoing validation

---

## Files Changed by Branch

### Container Configs (24 files):
```
domains/server/containers/beets/parts/config.nix
domains/server/containers/beets/sys.nix
domains/server/containers/caddy/parts/config.nix
domains/server/containers/caddy/sys.nix
domains/server/containers/gluetun/parts/config.nix
domains/server/containers/immich/parts/config.nix
domains/server/containers/immich/sys.nix
domains/server/containers/jellyfin/parts/config.nix
domains/server/containers/jellyfin/sys.nix
domains/server/containers/jellyseerr/parts/config.nix
domains/server/containers/jellyseerr/sys.nix
domains/server/containers/lidarr/parts/config.nix
domains/server/containers/lidarr/sys.nix
domains/server/containers/navidrome/parts/config.nix
domains/server/containers/navidrome/sys.nix
domains/server/containers/prowlarr/parts/config.nix
domains/server/containers/prowlarr/sys.nix
domains/server/containers/radarr/parts/config.nix
domains/server/containers/radarr/sys.nix
domains/server/containers/recyclarr/parts/config.nix
domains/server/containers/slskd/parts/config.nix
domains/server/containers/sonarr/parts/config.nix
domains/server/containers/sonarr/sys.nix
domains/server/containers/soularr/parts/config.nix
```

### Documentation (5 files):
```
docs/architecture/CONTAINER_CONSISTENCY_ANALYSIS.md (NEW)
docs/architecture/CONTAINER_MIGRATION_FIXES.md (NEW)
scripts/lints/README.md (NEW)
scripts/lints/container-lint.sh (NEW)
scripts/validate-containers.sh (NEW)
```

---

## Recommended Action Plan

### Phase 1: Extract Documentation (Safe, 15 minutes)
```bash
# Cherry-pick just the documentation commits
git cherry-pick <commit-hash-for-docs>
# Or manually copy:
git show origin/claude/analyze-container-consistency-01Y3ZNXstKgnaCUbuyPVEjmn:docs/architecture/CONTAINER_CONSISTENCY_ANALYSIS.md > docs/architecture/CONTAINER_CONSISTENCY_ANALYSIS.md
git show origin/claude/analyze-container-consistency-01Y3ZNXstKgnaCUbuyPVEjmn:docs/architecture/CONTAINER_MIGRATION_FIXES.md > docs/architecture/CONTAINER_MIGRATION_FIXES.md
```

### Phase 2: Fix Navidrome (Safe, 10 minutes)
```bash
# Add music library mount to current navidrome
# Edit domains/server/containers/navidrome/sys.nix
# Add: "${config.hwc.paths.media}/music:/music:ro"
nixos-rebuild build --flake .#hwc-server
# Test navidrome works
```

### Phase 3: Add Assertions Incrementally (Medium risk, 2-4 hours)
For each container (one at a time):
1. Copy assertion block from branch's parts/config.nix
2. Paste into main's parts/config.nix
3. Test build succeeds
4. Commit

### Phase 4: Add Resource Limits (Low risk, 1-2 hours)
Update mkContainer calls with memory/CPU limits

---

## Decision Matrix

| Option | Risk | Effort | Benefit | Recommendation |
|--------|------|--------|---------|----------------|
| **A: Cherry-pick** | Low | Medium | High | ✅ **RECOMMENDED** |
| **B: Full merge** | High | High | High | ⚠️ Not worth risk |
| **C: Archive** | None | Low | Medium | ✅ Fallback option |

---

## Next Steps

1. **Immediate:** Copy documentation files to main
2. **This week:** Fix Navidrome music mount
3. **Next 2 weeks:** Add assertions to 3-5 high-priority containers
4. **Future:** Consider full Charter v6 migration when less risky

---

## Conclusion

The `analyze-container-consistency` branch contains **excellent analysis and patterns** but its **all-or-nothing migration approach** conflicts with how main has evolved.

**Best path forward:**
- Archive the branch as reference
- Cherry-pick specific improvements
- Incrementally enhance current system
- Avoid risky full merge

Would you like me to proceed with Phase 1 (extracting documentation)?
