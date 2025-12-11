# Workspace Reorganization Plan - Option A Structure

## Overview
Reorganize workspace/ from arbitrary categories (development, automation, utilities) to purpose-driven structure that explicitly shows what triggers and what purpose each category serves.

## User Decisions
- Bible automation: Keep together in workspace/bible/ (not split by purpose)
- Standalone dirs: Create workspace/projects/ for productivity/ + projects/, distribute infrastructure/
- utilities/ → rename to media/ (focus on media tools)
- scripts/internal/ → move to nixos/ (NixOS dev tools)

---

## Final Structure

```
workspace/
├── nixos/           # NixOS config development tools
├── monitoring/      # System health/status checks
├── hooks/           # Event-driven scripts (download completion, webhooks)
├── diagnostics/     # Troubleshooting tools (network, debugging, validation)
├── setup/           # One-time deployment/installation scripts
├── bible/           # Bible automation system (kept together)
├── media/           # Media management tools (renamed from utilities/)
└── projects/        # Standalone projects (productivity + projects dirs)
```

---

## Detailed Migration Map

### Phase 1: Create New Top-Level Directories

Create 5 new directories (bible, media, projects already exist):
```bash
mkdir -p workspace/{nixos,monitoring,hooks,diagnostics,setup}
```

---

### Phase 2: Move Scripts by Category

#### nixos/ (NixOS Development Tools)

**From scripts/development/:**
- charter-lint.sh
- add-assertions.sh
- add-section-headers.sh
- analyze-namespace.sh
- autofix.sh
- smart-charter-fix.sh
- quick-anatomy.sh
- simple-checker.sh
- lint-helper.sh
- debug_test.sh
- grebuild.sh
- list-services.sh
- script-inventory.sh
- migrate-media-stack.sh

**From scripts/internal/:**
- validate-workspace-script.sh
- promote-to-domain.sh

**From infrastructure/filesystem/:**
- add-home-app.sh
- simple-header-update.sh
- update-headers.sh

**From utilities/graph/:**
- Entire directory (hwc_graph.py + modules)

**From utilities/config-validation/:**
- config-differ.sh
- config-extractor.py
- system-distiller.py

**From utilities/docs/:**
- generate-domain-readmes.py

**Total: ~35 scripts**

---

#### monitoring/ (System Health & Status)

**From scripts/monitoring/:**
- health-check.sh (in utilities/ but logically monitoring)
- journal-errors.sh
- caddy-health-check.sh
- disk-space-monitor.sh
- gpu-monitor.sh
- daily-summary.sh
- media_check.py

**From utilities/:**
- health-check.sh
- frigate-health.sh
- media-automation-status.sh
- immich-gpu-check.sh

**Total: ~12 scripts**

---

#### hooks/ (Event-Driven Scripts)

**From automation/:**
- media-orchestrator.py
- qbt-finished.sh
- sab-finished.py
- slskd-verify.sh

**From scripts/monitoring/:**
- nixos-rebuild-notifier.sh
- systemd-failure-notifier.sh

**From projects/receipts-pipeline/monitoring/:**
- receipt-monitor.sh

**Total: ~10 scripts** (excluding bible, which stays separate)

---

#### diagnostics/ (Troubleshooting Tools)

**From scripts/utils/network/:**
- All 9 network scripts (quicknet.sh, netcheck.sh, advnetcheck.sh, advnetcheck2.sh, homewifi-audit.sh, hw-overview.sh, toolscan.sh, wifibrute.sh, wifisurvery.sh)

**From utilities/config-validation/:**
- quick-start.sh
- sabnzbd-analyzer.py

**From utilities/:**
- fix-service-permissions.sh
- check-gpu-acceleration.sh (from utilities/scripts/)

**From utilities/nixos-translator/:**
- Entire directory (specialized migration/translation tool)

**From infrastructure/server/:**
- debug-slskd.sh
- fix_both.sh
- test-integration.sh

**Total: ~20 scripts**

---

#### setup/ (One-Time Deployment)

**From utilities/scripts/:**
- deploy-age-keys.sh
- sops-verify.sh
- deploy-agent-improvements.sh
- setup-monitoring.sh
- setup-tdarr-auto.py

**Total: ~8 scripts**

---

#### bible/ (Keep Together - Already in automation/bible/)

**Action:** Move workspace/automation/bible/ → workspace/bible/

**Contains:**
- bible_system_installer.py
- bible_system_migrator.py
- bible_system_validator.py
- bible_workflow_manager.py
- bible_debug_toolkit.py
- bible_system_cleanup.py
- bible_rewriter.py
- consistency_manager.py
- bible_post_build_hook.sh

**Total: 9 scripts**

---

#### media/ (Renamed from utilities/)

**Action:** Rename workspace/utilities/ → workspace/media/

**Keep in place:**
- beets-helper.sh
- beets-container-helper.sh
- media-organizer.sh
- immich-configure-storage.sh

**Remove from media/ (moved to other categories):**
- health-check.sh → monitoring/
- frigate-health.sh → monitoring/
- media-automation-status.sh → monitoring/
- fix-service-permissions.sh → diagnostics/
- graph/ → nixos/
- config-validation/ → split between nixos/ and diagnostics/
- docs/ → nixos/
- nixos-translator/ → diagnostics/
- scripts/ → setup/

**Result:** Clean media-focused directory

---

#### projects/ (Consolidate Standalone Projects)

**Action:** Move productivity/ → projects/productivity/

**Final structure:**
```
workspace/projects/
├── productivity/
│   ├── transcript-formatter/
│   ├── ai-docs/
│   └── music_duplicate_detector.sh
├── bible-plan/
├── estimate-automation/
├── receipts-pipeline/
└── site-crawler/
```

---

### Phase 3: Remove Old Directories

After migration, remove empty directories:
```bash
rm -rf workspace/scripts/
rm -rf workspace/automation/ (after bible moved)
rm -rf workspace/infrastructure/
rm -rf workspace/productivity/ (moved to projects/)
```

Note: workspace/utilities/ renamed to media/, not removed

---

## Phase 4: Update All References

### Critical Files to Update:

1. **workspace/scripts/README.md** → workspace/README.md
   - Complete rewrite for new structure
   - Update all path references
   - Update tier 1/2/3 examples

2. **domains/home/environment/shell/index.nix**
   - Update all writeShellApplication paths
   - OLD: `${workspaceScripts}/development/grebuild.sh`
   - NEW: `${workspace}/nixos/grebuild.sh`

3. **domains/home/environment/shell/parts/*.nix**
   - Update paths in all Nix wrapper derivations
   - charter-lint.nix, grebuild.nix, list-services.nix, etc.

4. **domains/system/services/monitoring/index.nix.disabled**
   - Already updated in previous cleanup
   - Verify paths point to new monitoring/ location

5. **Grep for all references:**
   ```bash
   rg "workspace/scripts" domains/ workspace/
   rg "workspace/automation" domains/ workspace/
   rg "workspace/utilities" domains/ workspace/
   rg "workspace/infrastructure" domains/ workspace/
   ```

### Systemd Service Paths
Search for any systemd services that reference old paths:
```bash
rg "ExecStart.*workspace" domains/
```

### Documentation Files
- CLAUDE.md (repository guide)
- docs/ directory references
- Any .claude/agents/ references

---

## Phase 5: Git Operations

### Strategy: Preserve History with git mv

**Important:** Use `git mv` to preserve file history, not `rm` + `add`

#### Step-by-step:

1. **Create new directories:**
   ```bash
   mkdir -p workspace/{nixos,monitoring,hooks,diagnostics,setup}
   ```

2. **Move files preserving history:**
   ```bash
   # Example for nixos/
   git mv workspace/scripts/development/charter-lint.sh workspace/nixos/
   git mv workspace/scripts/development/grebuild.sh workspace/nixos/
   # ... repeat for all files

   # Move entire bible directory
   git mv workspace/automation/bible workspace/bible

   # Rename utilities to media
   git mv workspace/utilities workspace/media

   # Move productivity to projects
   git mv workspace/productivity workspace/projects/productivity
   ```

3. **Remove empty directories:**
   ```bash
   git rm -r workspace/scripts/
   git rm -r workspace/automation/
   git rm -r workspace/infrastructure/
   ```

4. **Stage reference updates:**
   ```bash
   git add domains/home/environment/shell/
   git add workspace/README.md
   git add CLAUDE.md
   # ... other updated files
   ```

5. **Commit with detailed message:**
   ```bash
   git commit -m "refactor(workspace): reorganize to purpose-driven structure (Option A)

   Flatten workspace/ structure and organize by trigger/purpose instead of
   arbitrary categories (development, automation, utilities).

   New structure:
   - nixos/       - NixOS development tools (lint, rebuild, module scaffolding)
   - monitoring/  - System health checks (health-check, journal-errors, gpu)
   - hooks/       - Event-driven scripts (download hooks, orchestrators, notifiers)
   - diagnostics/ - Troubleshooting tools (network, validation, debugging)
   - setup/       - One-time deployment scripts (deploy-age-keys, installers)
   - bible/       - Bible automation system (kept together as domain)
   - media/       - Media management tools (renamed from utilities/)
   - projects/    - Standalone projects (productivity, bible-plan, etc.)

   Changes:
   - Move 35 scripts → nixos/ (charter-lint, grebuild, internal tools, etc.)
   - Move 12 scripts → monitoring/ (health checks, status scripts)
   - Move 10 scripts → hooks/ (completion hooks, orchestrators, notifiers)
   - Move 20 scripts → diagnostics/ (network tools, validators, debuggers)
   - Move 8 scripts → setup/ (deployment, installation scripts)
   - Move automation/bible/ → bible/ (kept together)
   - Rename utilities/ → media/ (focus on media tools)
   - Move productivity/ → projects/productivity/
   - Distribute infrastructure/ scripts to appropriate categories
   - Remove scripts/ intermediate directory (flattened)

   Update all references:
   - Shell command wrappers (domains/home/environment/shell/)
   - README documentation
   - CLAUDE.md repository guide
   - Systemd service paths

   Rationale: Purpose-driven structure makes it immediately clear:
   - What triggers the script (hook, timer, user command)
   - What domain it serves (nixos dev, system monitoring, media)
   - When you would use it (setup once, diagnose problem, automate event)

   This eliminates ambiguity between 'development', 'automation', and 'utilities'.

   🤖 Generated with [Claude Code](https://claude.com/claude-code)

   Co-Authored-By: Claude <noreply@anthropic.com>"
   ```

---

## Verification Checklist

Before committing:
- [ ] All `git mv` operations completed (preserves history)
- [ ] No references to old paths remain (`rg "workspace/scripts"` returns empty)
- [ ] All shell command wrappers updated and tested
- [ ] README.md rewritten for new structure
- [ ] CLAUDE.md updated with new structure
- [ ] No broken symlinks or references
- [ ] Git status shows expected moves (not deletes + adds)

After committing:
- [ ] `nix flake check` passes
- [ ] Test key commands: `grebuild`, `charter-lint`, `journal-errors`, `caddy-health`
- [ ] Systemd services still work (if any reference workspace scripts)
- [ ] Can navigate new structure intuitively

---

## Migration Script Template

For automation, here's a template for the migration:

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "=== Workspace Reorganization ==="
echo "Creating new directory structure..."

# Create new directories
mkdir -p workspace/{nixos,monitoring,hooks,diagnostics,setup}

echo "Moving scripts to nixos/..."
for file in charter-lint.sh grebuild.sh list-services.sh add-assertions.sh \
            add-section-headers.sh analyze-namespace.sh autofix.sh \
            smart-charter-fix.sh quick-anatomy.sh simple-checker.sh \
            lint-helper.sh debug_test.sh script-inventory.sh \
            migrate-media-stack.sh; do
  git mv "workspace/scripts/development/$file" "workspace/nixos/" 2>/dev/null || true
done

# Move internal scripts
git mv workspace/scripts/internal/validate-workspace-script.sh workspace/nixos/
git mv workspace/scripts/internal/promote-to-domain.sh workspace/nixos/

# Move infrastructure/filesystem
git mv workspace/infrastructure/filesystem/add-home-app.sh workspace/nixos/
git mv workspace/infrastructure/filesystem/simple-header-update.sh workspace/nixos/
git mv workspace/infrastructure/filesystem/update-headers.sh workspace/nixos/

# ... continue for other categories

echo "Renaming utilities to media..."
git mv workspace/utilities workspace/media

echo "Moving bible system..."
git mv workspace/automation/bible workspace/bible

echo "Organizing projects..."
mkdir -p workspace/projects
git mv workspace/productivity workspace/projects/productivity

echo "Cleaning up old directories..."
git rm -r workspace/scripts/ || true
git rm -r workspace/automation/ || true
git rm -r workspace/infrastructure/ || true

echo "Migration complete! Now update references in:"
echo "  - domains/home/environment/shell/"
echo "  - workspace/README.md"
echo "  - CLAUDE.md"
```

---

## Risk Assessment

**Risk Level:** Medium

**Risks:**
1. Breaking shell command wrappers if paths not updated correctly
2. Systemd services failing if they reference old paths
3. Losing git history if using `rm` + `add` instead of `git mv`
4. Developer confusion during transition

**Mitigation:**
1. Use `git mv` exclusively to preserve history
2. Comprehensive grep searches for all references before committing
3. Test all tier 1 commands after migration
4. Update documentation immediately
5. Single atomic commit for easy revert

---

## Timeline

This is a large refactoring touching 100+ files. Execution phases:

1. **Preparation** (5 min): Create directories, plan moves
2. **Migration** (15 min): Execute all `git mv` operations
3. **Reference Updates** (10 min): Update shell wrappers, README, CLAUDE.md
4. **Verification** (10 min): Grep searches, test commands, flake check
5. **Commit** (5 min): Stage all changes, commit with detailed message

**Total: ~45 minutes** for complete reorganization

---

## Post-Migration

### Update Documentation

1. **workspace/README.md** - Complete rewrite explaining new structure
2. **CLAUDE.md** - Update workspace section with new categories
3. **.claude/agents/SCRIPT-ORGANIZATION.md** - Update if exists
4. **docs/** - Any workspace references

### Communication

If this is a team repository:
- Announce reorganization before merging
- Provide migration guide for local checkouts
- Update any CI/CD that references old paths
- Update any external documentation/wikis

---

## Notes

1. **Bible system kept together** per user preference - domain cohesion > categorization
2. **Media tools focused** - utilities/ → media/ removes ambiguity
3. **Projects consolidated** - all standalone projects in projects/
4. **Scripts/ eliminated** - flattened structure, no intermediate directory
5. **Infrastructure distributed** - scripts integrated into appropriate categories
6. **All moves use git mv** - preserves full git history for every file
