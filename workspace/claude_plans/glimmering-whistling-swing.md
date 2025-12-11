# Plan: Refactor Workspace Scripts with Dynamic Root Indirection

## Status: Exploration Complete - Awaiting User Clarification

### User Requirements
- Consolidate duplicated script implementations
- Remove Nix writeShellApplication sprawl
- Add dynamic workspace-root indirection (HWC_WORKSPACE_ROOT)
- Make shell module a pure invocation surface
- Preserve git history with git mv

### Critical Discovery - Assumption Mismatch

**CRITICAL FINDING**: User's assumptions do not match actual codebase state!

#### Assumption vs Reality

**User Assumed:**
- Nix `writeShellApplication` derivations exist in `domains/home/environment/shell/parts/`
- Need to extract scripts from these derivations
- Need to archive parts/*.nix files

**Actual State:**
- **NO `parts/` directory exists** in `domains/home/environment/shell/`
- Scripts are implemented as **simple bash functions** in `index.nix` (lines 201-219)
- These functions directly call workspace scripts with hardcoded paths
- **TRIPLE DUPLICATION** exists:
  1. Bash functions in `index.nix` (invocation layer)
  2. Primary scripts in `workspace/scripts/development/` and `workspace/scripts/monitoring/`
  3. Legacy duplicates in `workspace/utilities/scripts/`

#### Current Implementation Pattern

From `domains/home/environment/shell/index.nix:201-219`:
```nix
grebuild() {
  bash ${config.home.homeDirectory}/.nixos/workspace/scripts/development/grebuild.sh "$@"
}

journal-errors() {
  bash ${config.home.homeDirectory}/.nixos/workspace/scripts/monitoring/journal-errors.sh "$@"
}

list-services() {
  bash ${config.home.homeDirectory}/.nixos/workspace/scripts/development/list-services.sh "$@"
}

charter-lint() {
  bash ${config.home.homeDirectory}/.nixos/workspace/scripts/development/charter-lint.sh "$@"
}

caddy-health() {
  bash ${config.home.homeDirectory}/.nixos/workspace/scripts/monitoring/caddy-health-check.sh "$@"
}
```

#### Script Locations Identified

**Primary Location** - `workspace/scripts/`:
- `development/grebuild.sh` (588 lines)
- `monitoring/journal-errors.sh` (102 lines)
- `development/list-services.sh` (180 lines)
- `development/charter-lint.sh` (31KB)
- `monitoring/caddy-health-check.sh` (47 lines)

**Legacy Duplicates** - `workspace/utilities/scripts/`:
- `grebuild.sh`
- `list-services.sh`
- `caddy-health-check.sh`

**Other Files Found**:
- `workspace/utilities/hwc-status.py` (comprehensive system status collector)
- `workspace/utilities/health-check.sh` (simple health check)
- `domains/home/apps/n8n/parts/n8n-workflows/scripts/health-check.sh`

#### Architecture Documented vs Actual

`workspace/scripts/README.md` describes a three-tier architecture:
- **Tier 1**: Nix commands in `domains/home/environment/shell/parts/` (DOES NOT EXIST)
- **Tier 2**: Workspace scripts in `workspace/scripts/` (EXISTS)
- **Tier 3**: Domain scripts (EXISTS in various domains)

The README appears to be **aspirational** rather than documenting actual state.

---

## Critical Questions Requiring User Input

Before proceeding, I need clarification on:

1. **Architectural Approach**: Given that no Nix derivations exist, should we:
   - Option A: Keep bash functions but add HWC_WORKSPACE_ROOT indirection
   - Option B: Convert to writeShellApplication pattern (implementing aspirational architecture)

2. **Canonical Script Location**: Which is the source of truth:
   - `workspace/scripts/development/` and `workspace/scripts/monitoring/` (newer, better organized)
   - `workspace/utilities/scripts/` (legacy location)

3. **Implementation Steps**:
   - Steps 2-4 of original plan (extract from Nix, compare, archive parts/*.nix) **do not apply**
   - Need revised approach based on actual architecture

---

## Proposed Adapted Plan (Option A - Simpler Approach)

If user confirms Option A (adapt to current bash function pattern):

### Phase 1: Consolidate Duplicates
1. Identify canonical versions (likely `workspace/scripts/`)
2. Remove duplicates from `workspace/utilities/scripts/`
3. Use `git rm` for tracked duplicates

### Phase 2: Add Dynamic Workspace Root
1. Update `index.nix` to define environment variables:
   ```nix
   HWC_WORKSPACE_ROOT="${config.home.homeDirectory}/.nixos/workspace";
   HWC_WORKSPACE_SCRIPTS="$HWC_WORKSPACE_ROOT/scripts";
   ```

2. Update bash functions to use variables:
   ```nix
   grebuild() {
     bash "$HWC_WORKSPACE_SCRIPTS/development/grebuild.sh" "$@"
   }
   ```

### Phase 3: Add Validation Helpers
1. Create `workspace/scripts/internal/validate-workspace-script.sh`
2. Create `workspace/scripts/internal/promote-to-domain.sh`

### Phase 4: Documentation
1. Update `workspace/scripts/README.md` to reflect actual architecture
2. Document HWC_WORKSPACE_ROOT override mechanism

---

## Alternative Plan (Option B - Implement Aspirational Architecture)

If user wants to implement the writeShellApplication pattern:

### Phase 1: Create parts/ Directory
1. Create `domains/home/environment/shell/parts/`
2. Convert bash functions to Nix derivations

### Phase 2: Extract to Workspace
1. Create canonical scripts in `workspace/scripts/`
2. Update derivations to call workspace scripts

### Phase 3-4: Same as Option A

---

## Next Steps

Awaiting user clarification on:
1. Which architectural approach to pursue (A or B)
2. Which script location is canonical
3. Whether to proceed with adapted plan or different approach

---

## USER DECISION

**Architectural Approach**: Option B - Implement writeShellApplication pattern (robust and standardized)
**Canonical Location**: workspace/scripts/ (newer organized structure)

---

## FINAL IMPLEMENTATION PLAN

### Phase 1: Consolidate to Canonical Location
**Goal**: Make `workspace/scripts/` the single source of truth

1. **Verify canonical scripts exist**:
   ```bash
   ls -la workspace/scripts/development/
   ls -la workspace/scripts/monitoring/
   ```

2. **Remove legacy duplicates**:
   ```bash
   git rm workspace/utilities/scripts/grebuild.sh
   git rm workspace/utilities/scripts/list-services.sh
   git rm workspace/utilities/scripts/caddy-health-check.sh
   git commit -m "chore(workspace): remove legacy script duplicates from utilities/scripts/"
   ```

3. **Handle special files**:
   - Keep `workspace/utilities/hwc-status.py` (not a duplicate, different tool)
   - Keep `workspace/utilities/health-check.sh` (may have different purpose - needs verification)

### Phase 2: Create Nix Derivation Layer (parts/ directory)
**Goal**: Implement Tier 1 (writeShellApplication wrappers)

1. **Create parts/ directory**:
   ```bash
   mkdir -p domains/home/environment/shell/parts
   ```

2. **Create writeShellApplication derivations** for each script:
   
   **File**: `domains/home/environment/shell/parts/grebuild.nix`
   ```nix
   { pkgs, config, ... }:

   let
     workspaceRoot = config.home.homeDirectory + "/.nixos/workspace";
     workspaceScripts = workspaceRoot + "/scripts";
   in
   pkgs.writeShellApplication {
     name = "grebuild";
     runtimeInputs = with pkgs; [ bash ];
     text = ''
       exec bash "${workspaceScripts}/development/grebuild.sh" "$@"
     '';
   }
   ```

   Repeat for:
   - `journal-errors.nix` → `monitoring/journal-errors.sh`
   - `list-services.nix` → `development/list-services.sh`
   - `charter-lint.nix` → `development/charter-lint.sh`
   - `caddy-health.nix` → `monitoring/caddy-health-check.sh`

3. **Add runtime dependencies** where needed:
   - `grebuild.nix`: may need git, nix
   - `journal-errors.nix`: may need systemd (journalctl)
   - `list-services.nix`: may need systemd
   - `charter-lint.nix`: likely needs grep/rg, bash
   - `caddy-health.nix`: may need curl, jq

### Phase 3: Update Shell Module (index.nix)
**Goal**: Replace bash functions with Nix derivations

1. **Import parts/** at top of index.nix:
   ```nix
   let
     # Import script derivations
     grebuild = import ./parts/grebuild.nix { inherit pkgs config; };
     journal-errors = import ./parts/journal-errors.nix { inherit pkgs config; };
     list-services = import ./parts/list-services.nix { inherit pkgs config; };
     charter-lint = import ./parts/charter-lint.nix { inherit pkgs config; };
     caddy-health = import ./parts/caddy-health.nix { inherit pkgs config; };
   in
   ```

2. **Replace IMPLEMENTATION section** (remove bash functions, add to packages):
   ```nix
   config = lib.mkIf enabled {
     home.packages = [
       grebuild
       journal-errors
       list-services
       charter-lint
       caddy-health
     ];
   };
   ```

3. **Add environment variables** for runtime override:
   ```nix
   config = lib.mkIf enabled {
     home.sessionVariables = {
       HWC_WORKSPACE_ROOT = "${config.home.homeDirectory}/.nixos/workspace";
       HWC_WORKSPACE_SCRIPTS = "$HWC_WORKSPACE_ROOT/scripts";
     };

     home.packages = [ /* ... */ ];
   };
   ```

### Phase 4: Add Validation and Promotion Helpers

1. **Create internal scripts directory**:
   ```bash
   mkdir -p workspace/scripts/internal
   ```

2. **Create validation script**:
   
   **File**: `workspace/scripts/internal/validate-workspace-script.sh`
   ```bash
   #!/usr/bin/env bash
   # Validates a workspace script meets promotion requirements
   
   set -euo pipefail
   
   SCRIPT_PATH="${1:?Usage: $0 <script-path>}"
   
   echo "Validating: $SCRIPT_PATH"
   
   # Check exists
   [[ -f "$SCRIPT_PATH" ]] || { echo "ERROR: File not found"; exit 1; }
   
   # Check executable
   [[ -x "$SCRIPT_PATH" ]] || { echo "ERROR: Not executable"; exit 1; }
   
   # Check shebang
   head -1 "$SCRIPT_PATH" | grep -q '^#!/' || { echo "ERROR: Missing shebang"; exit 1; }
   
   # Check set -euo pipefail
   grep -q 'set -euo pipefail' "$SCRIPT_PATH" || { echo "WARNING: Missing 'set -euo pipefail'"; }
   
   # Check has usage/help
   grep -q 'Usage:' "$SCRIPT_PATH" || { echo "WARNING: No usage documentation"; }
   
   echo "✓ Validation passed"
   ```

3. **Create promotion script**:
   
   **File**: `workspace/scripts/internal/promote-to-domain.sh`
   ```bash
   #!/usr/bin/env bash
   # Promotes a workspace script to a domain-level Nix derivation
   
   set -euo pipefail
   
   SCRIPT_PATH="${1:?Usage: $0 <workspace-script-path> <command-name>}"
   COMMAND_NAME="${2:?}"
   
   # Validate first
   bash "$(dirname "$0")/validate-workspace-script.sh" "$SCRIPT_PATH"
   
   # Derive paths
   SCRIPT_REL_PATH="${SCRIPT_PATH#workspace/scripts/}"
   PARTS_FILE="domains/home/environment/shell/parts/${COMMAND_NAME}.nix"
   
   echo "Creating Nix derivation: $PARTS_FILE"
   
   cat > "$PARTS_FILE" <<EOF
   { pkgs, config, ... }:
   
   let
     workspaceRoot = config.home.homeDirectory + "/.nixos/workspace";
     workspaceScripts = workspaceRoot + "/scripts";
   in
   pkgs.writeShellApplication {
     name = "${COMMAND_NAME}";
     runtimeInputs = with pkgs; [
       # TODO: Add required runtime dependencies
       bash
     ];
     text = ''
       exec bash "\${workspaceScripts}/${SCRIPT_REL_PATH}" "\$@"
     '';
   }
   EOF
   
   echo "✓ Created $PARTS_FILE"
   echo "TODO: Add to domains/home/environment/shell/index.nix imports and home.packages"
   ```

4. **Make scripts executable**:
   ```bash
   chmod +x workspace/scripts/internal/validate-workspace-script.sh
   chmod +x workspace/scripts/internal/promote-to-domain.sh
   ```

### Phase 5: Documentation

1. **Update workspace/scripts/README.md** to reflect implemented architecture:
   - Tier 1: Nix derivations in `domains/home/environment/shell/parts/` (NOW EXISTS)
   - Tier 2: Workspace scripts in `workspace/scripts/` (canonical)
   - Tier 3: Domain scripts (unchanged)

2. **Document HWC_WORKSPACE_ROOT override**:
   ```markdown
   ## Runtime Override
   
   To use scripts from a different workspace location:
   
   ```bash
   export HWC_WORKSPACE_ROOT="/path/to/custom/workspace"
   export HWC_WORKSPACE_SCRIPTS="$HWC_WORKSPACE_ROOT/scripts"
   ```
   
   This allows testing workspace changes without rebuilding.
   ```

3. **Document promotion workflow**:
   ```markdown
   ## Promoting Workspace Scripts to Domain Commands
   
   1. Create script in `workspace/scripts/<category>/my-script.sh`
   2. Test thoroughly in workspace
   3. Validate: `bash workspace/scripts/internal/validate-workspace-script.sh workspace/scripts/<category>/my-script.sh`
   4. Promote: `bash workspace/scripts/internal/promote-to-domain.sh workspace/scripts/<category>/my-script.sh my-command`
   5. Add to `domains/home/environment/shell/index.nix` imports and packages
   6. Rebuild: `sudo nixos-rebuild switch --flake .#hwc-laptop`
   ```

### Phase 6: Testing and Verification

1. **Build test**:
   ```bash
   nix flake check
   ```

2. **Rebuild test (no activation)**:
   ```bash
   sudo nixos-rebuild test --flake .#hwc-laptop
   ```

3. **Verify commands exist in PATH**:
   ```bash
   which grebuild
   which journal-errors
   which list-services
   which charter-lint
   which caddy-health
   ```

4. **Test each command**:
   ```bash
   grebuild --help || true
   journal-errors --help || true
   list-services || true
   charter-lint --help || true
   caddy-health || true
   ```

5. **Test environment variables**:
   ```bash
   echo $HWC_WORKSPACE_ROOT
   echo $HWC_WORKSPACE_SCRIPTS
   ```

6. **Test runtime override**:
   ```bash
   export HWC_WORKSPACE_SCRIPTS="/tmp/test-scripts"
   mkdir -p /tmp/test-scripts/development
   echo '#!/bin/bash' > /tmp/test-scripts/development/grebuild.sh
   echo 'echo "TEST OVERRIDE WORKS"' >> /tmp/test-scripts/development/grebuild.sh
   chmod +x /tmp/test-scripts/development/grebuild.sh
   grebuild  # Should print "TEST OVERRIDE WORKS"
   unset HWC_WORKSPACE_SCRIPTS
   ```

7. **If all tests pass, switch**:
   ```bash
   sudo nixos-rebuild switch --flake .#hwc-laptop
   ```

---

## Implementation Order

1. Phase 1: Consolidate (remove duplicates) - SAFE, no breakage risk
2. Phase 4: Add helpers (validation/promotion) - SAFE, new functionality
3. Phase 2: Create parts/ directory - SAFE, not yet used
4. Phase 3: Update index.nix - REQUIRES TESTING, changes active config
5. Phase 5: Documentation - SAFE
6. Phase 6: Testing - VERIFICATION

---

## Success Criteria

- ✓ No duplicate scripts in workspace/utilities/scripts/
- ✓ All 5 commands have Nix derivations in parts/
- ✓ Commands available in PATH after rebuild
- ✓ HWC_WORKSPACE_ROOT and HWC_WORKSPACE_SCRIPTS set
- ✓ Runtime override works correctly
- ✓ Validation and promotion helpers functional
- ✓ Documentation updated and accurate
- ✓ All tests pass

---

## Risks and Mitigations

**Risk**: Breaking currently working commands
**Mitigation**: Use `nixos-rebuild test` first, verify all commands work before `switch`

**Risk**: Missing runtime dependencies in derivations
**Mitigation**: Test each command thoroughly, add dependencies as needed

**Risk**: Path resolution issues with workspace override
**Mitigation**: Test override mechanism explicitly in Phase 6

**Risk**: Git history loss
**Mitigation**: Use `git mv` and `git rm` for all file operations

