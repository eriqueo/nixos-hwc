# Branch Risk Analysis & Merge Recommendations

**Date:** 2025-11-20
**Repository:** nixos-hwc
**Total Active Branches:** 26
**Already Merged (Safe to Delete):** 9
**With Unique Changes:** 17

---

## Cleanup Script

The following branches are **100% verified as fully merged** into main:

```bash
# Run this to delete merged branches:
chmod +x /tmp/cleanup_merged_branches.sh && /tmp/cleanup_merged_branches.sh
```

---

## Remaining Branches - Categorized by Risk & Recommendation

### 🔴 HIGH PRIORITY - Critical System Changes (Review & Test Before Merging)

#### 1. `claude/fix-agenix-immich-issues-01C3cWv9eTx8nn8JWBkwwrht`
**Risk Level:** 🟠 **MEDIUM-HIGH**

- **Behind:** 14 commits | **Ahead:** 5 commits | **Files:** 6
- **Changes:**
  - Immich crash loop fixes (duplicate path resolution)
  - Database migration repair scripts
  - MCP re-enable after recursion fix
  - Flake and server config updates

**Critical Files Changed:**
- `flake.nix`
- `machines/server/config.nix`
- `domains/server/immich/index.nix`
- `domains/server/ai/mcp/default.nix`

**Improvements Needed Before Merge:**
1. ✅ **Verify Immich changes** - Check if the duplicate path fix is still relevant (main might have diverged)
2. ✅ **Test database repair script** - Ensure it works on current schema
3. ✅ **Rebase onto main** - 14 commits behind is significant
4. ✅ **Test build** - Run `nixos-rebuild build` to ensure no conflicts
5. ✅ **Review MCP changes** - Ensure they don't conflict with current MCP state

**Merge Strategy:**
```bash
git checkout claude/fix-agenix-immich-issues-01C3cWv9eTx8nn8JWBkwwrht
git rebase origin/main
# Resolve any conflicts
nixos-rebuild build --flake .#hwc-server
# If successful:
git push -f origin claude/fix-agenix-immich-issues-01C3cWv9eTx8nn8JWBkwwrht
# Then create PR or merge to main
```

---

#### 2. `claude/analyze-container-consistency-01Y3ZNXstKgnaCUbuyPVEjmn`
**Risk Level:** 🟠 **HIGH** (Most files changed)

- **Behind:** 41 commits | **Ahead:** 3 commits | **Files:** 29 (24 Nix files!)
- **Changes:**
  - Charter v6 compliance migration for 14 containers
  - Build-breaking conflict fixes
  - Container validation tools

**Critical Files Changed:**
- All major containers: Jellyfin, Immich, Radarr, Sonarr, Lidarr, Beets, Caddy, Gluetun, etc.
- System-wide container architecture changes

**Improvements Needed Before Merge:**
1. ⚠️ **EXTREMELY STALE** - 41 commits behind main
2. ⚠️ **HIGH RISK** - Touches 14 critical container configs
3. ✅ **Audit each container change** - Main may have evolved these containers independently
4. ✅ **Check for duplicate fixes** - Some fixes might already be in main
5. ✅ **Test EVERY container** - Each one must start successfully
6. ✅ **Rebase carefully** - Expect conflicts due to staleness

**Merge Strategy:**
```bash
# This needs VERY careful handling
git checkout -b test-container-consistency main
git merge --no-commit origin/claude/analyze-container-consistency-01Y3ZNXstKgnaCUbuyPVEjmn
# Review ALL conflicts carefully
# Test each container individually
podman ps -a  # Verify all containers start
```

**Alternative:** May be safer to **cherry-pick** specific fixes rather than merge entire branch.

---

#### 3. `claude/analyze-codebase-011LwaLri7grCHdWvbEMFjMn`
**Risk Level:** 🟡 **MEDIUM**

- **Behind:** 41 commits | **Ahead:** 2 commits | **Files:** 18 (14 Nix files)
- **Changes:**
  - Security, performance, and reliability improvements
  - Backup system enhancements
  - Secrets management improvements
  - Navidrome configuration updates

**Critical Files Changed:**
- `domains/secrets/` - Secret declarations and templates
- `domains/server/backup/` - Backup system
- `domains/server/navidrome/` - Music server config

**Improvements Needed Before Merge:**
1. ✅ **Verify backup changes** - Check against current backup system state
2. ✅ **Review secrets changes** - Ensure no conflicts with current secrets
3. ✅ **Test Navidrome** - Verify music server still works
4. ✅ **Rebase onto main** - 41 commits is very stale

**Decision:** Likely **merge-worthy** but needs testing after rebase.

---

### 🟢 LOW RISK - New Features (Safe to Merge After Update)

#### 4. `claude/plan-client-intake-tool-01J7p3XjvWXiiU9ZhnN2V8vJ`
**Risk Level:** 🟢 **LOW**

- **Behind:** 15 commits | **Ahead:** 1 commit | **Files:** 17
- **Changes:** Bathroom remodel planner API (completely new feature in `remodel-api/`)

**Why Low Risk:**
- ✅ Self-contained new feature
- ✅ Doesn't touch existing system
- ✅ All new files in isolated directory

**Improvements Needed:**
1. ✅ **Rebase onto main** - Simple update
2. ✅ **Test API** - Ensure it starts correctly
3. ✅ **Document deployment** - Add README for how to use it

**Merge Strategy:** Straightforward rebase and merge.

---

#### 5. `claude/receipts-ocr-pipeline-012TRfh8KFoziSFDpjxAuaJc`
**Risk Level:** 🟢 **LOW-MEDIUM**

- **Behind:** 37 commits | **Ahead:** 1 commit | **Files:** 15
- **Changes:** OCR pipeline with n8n orchestration (new business feature)

**Critical Files Changed:**
- `domains/secrets/declarations/receipts-ocr.nix` (new)
- `domains/server/business/parts/receipts-ocr.nix` (new)

**Why Low-Medium Risk:**
- ✅ Mostly new files
- ⚠️ Adds secrets declarations
- ✅ Business domain feature (isolated)

**Improvements Needed:**
1. ✅ **Rebase onto main**
2. ✅ **Verify secrets are properly encrypted**
3. ✅ **Test n8n integration**

**Merge Strategy:** Rebase, verify secrets, merge.

---

#### 6. `claude/pihole-adblocking-module-011CgWZr8smLf61NRmiXQgzo`
**Risk Level:** 🟢 **LOW**

- **Behind:** 41 commits | **Ahead:** 1 commit | **Files:** 5
- **Changes:** Pi-hole ad blocking container (new feature)

**Critical Files Changed:**
- `domains/server/containers/index.nix` (adds pihole to imports)
- `domains/server/containers/pihole/*` (all new)

**Improvements Needed:**
1. ✅ **Rebase onto main**
2. ✅ **Test Pi-hole container starts**
3. ✅ **Document configuration**

**Merge Strategy:** Simple rebase and merge.

---

#### 7. `claude/plan-rest-api-017DFY3VvBpkZEnQrReVwanX`
**Risk Level:** 🟡 **MEDIUM** (touches flake)

- **Behind:** 41 commits | **Ahead:** 1 commit | **Files:** 8
- **Changes:** hwc-graph dependency analysis tool

**Critical Files Changed:**
- `flake.nix` (adds dependency analysis tool)

**Improvements Needed:**
1. ✅ **Rebase onto main** - Flake might have changed
2. ✅ **Test tool works**
3. ✅ **Verify no flake conflicts**

**Merge Strategy:** Rebase carefully due to flake.nix changes.

---

### 📄 DOCUMENTATION ONLY - Safe to Merge Anytime

These branches **only add documentation** and have **zero risk** to system functionality:

#### 8. `claude/audit-networking-security-01KsrxA3Noiwhvj1iYyatC1B`
- **Files:** 1 documentation file
- **Changes:** Security audit documentation
- **Action:** ✅ Merge immediately after quick rebase

#### 9. `claude/audit-paths-naming-01Cpw2p7eXqSc6V9DBzhVYkC`
- **Files:** 2 documentation files
- **Changes:** Standards and compliance report
- **Action:** ✅ Merge immediately after quick rebase

#### 10. `claude/audit-systemd-services-018tpGYMCXhECKE5mF4HPeRG`
- **Files:** 5 documentation files
- **Changes:** Systemd services audit
- **Action:** ✅ Merge immediately after quick rebase

#### 11. `claude/automate-domain-docs-01KeDTYVRsdNxAc9MBcQNYTo`
- **Files:** 4 files (2 docs, 1 script, 1 config)
- **Changes:** Domain README validation
- **Action:** ✅ Merge after quick rebase

#### 12. `claude/review-nixos-modules-01Kkz8gatchqgNbV8Bzb68gc`
- **Files:** 1 documentation file
- **Changes:** NixOS charter analysis
- **Action:** ✅ Merge immediately after quick rebase

---

### 🟡 MEDIUM PRIORITY - Improvements to Existing Systems

#### 13. `claude/backup-system-01N1gSvQa2gtDHBeJcUjXXgd`
**Risk Level:** 🟡 **MEDIUM**

- **Behind:** 40 commits | **Ahead:** 1 commit | **Files:** 6 (5 Nix files)
- **Changes:** Security & reliability improvements to backup system

**Improvements Needed:**
1. ✅ **Check if already applied** - Main may have incorporated these fixes
2. ✅ **Rebase onto main**
3. ✅ **Test backup system**

**Merge Strategy:** Review against current backup system, rebase, test.

---

#### 14. `claude/claude-md-mi54wxxr6ccfkam4-011prmAcWRUQmZQ4CbmLFgp6`
**Risk Level:** 🟡 **MEDIUM**

- **Behind:** 41 commits | **Ahead:** 4 commits | **Files:** 12
- **Changes:**
  - CLAUDE.md guide for AI assistants
  - Charter structure improvements
  - Linter enhancements

**Improvements Needed:**
1. ✅ **Rebase onto main**
2. ✅ **Review linter changes** - Ensure they don't conflict
3. ✅ **Test charter validation**

**Merge Strategy:** Rebase and test linter tools.

---

### ⚙️ TOOLING & UTILITIES

#### 15. `claude/remove-nixos-dependency-014C2eUwgyL2yjGRvVmJMdoK`
**Risk Level:** 🟢 **LOW** (doesn't affect system)

- **Behind:** 41 commits | **Ahead:** 3 commits | **Files:** 22 (19 scripts!)
- **Changes:** NixOS translator for distro migration

**Why Low Risk:**
- ✅ All new files in `workspace/utilities/nixos-translator/`
- ✅ Doesn't touch system configuration
- ✅ Optional migration tool

**Decision:**
- ✅ **Keep as feature branch** if you're not actively migrating
- ✅ **Merge** if you want the tooling available for future use

---

#### 16. `claude/fetch-latest-commits-01QMLisvf4jP89rmiSjo8nuM`
**Risk Level:** 🟡 **MEDIUM** (very stale)

- **Behind:** 59 commits (MOST STALE!) | **Ahead:** 2 commits | **Files:** 3
- **Changes:** Agenix-secrets skill for token-efficient secrets management

**Improvements Needed:**
1. ⚠️ **VERY STALE** - Check if superseded by newer work
2. ✅ **Verify still needed**
3. ✅ **Rebase onto main** if keeping

**Decision:** Review if functionality already exists, then decide to merge or delete.

---

## Summary Recommendations

### Immediate Actions

1. **Delete 9 merged branches** - Run `/tmp/cleanup_merged_branches.sh`

### High Priority (This Week)

2. **`fix-agenix-immich-issues`** - Rebase, test, merge (Immich fixes needed)
3. **`backup-system`** - Review and merge (security improvements)

### Medium Priority (Next 2 Weeks)

4. **Documentation branches** (5 total) - Quick rebase and merge all
5. **New features** - Client intake, receipts OCR, Pi-hole (if needed)

### Low Priority (Review Before Decision)

6. **`analyze-container-consistency`** - VERY RISKY due to staleness and scope
   - Recommend: Cherry-pick specific fixes rather than full merge
7. **`remove-nixos-dependency`** - Only if migrating off NixOS
8. **`fetch-latest-commits`** - Check if superseded, likely delete

### Consider Archiving

- **`claude-md-mi54wxxr6ccfkam4-011prmAcWVFWsdd`** - If linter changes already applied
- **`plan-rest-api`** - If dependency tool not needed

---

## Branch Hygiene Best Practices Going Forward

1. **Merge within 15 commits** - Don't let branches get >15 commits behind main
2. **Delete after merge** - Immediately clean up merged branches
3. **Feature flags** - Use feature flags for long-running work instead of long-lived branches
4. **Weekly syncs** - Rebase feature branches weekly to stay current
5. **CI/CD checks** - Add automated staleness warnings

---

## Next Steps

1. Run cleanup script to delete 9 merged branches
2. Review this document
3. Prioritize which branches you actually want to merge
4. I can help you rebase and test each one systematically

Would you like me to help with specific branches?
