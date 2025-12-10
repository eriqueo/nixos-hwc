# HWC Scripts Directory

Consolidated location for all workspace scripts following the three-tier architecture with dynamic workspace root indirection.

## Structure

```
workspace/scripts/
├── monitoring/          # System monitoring scripts
│   ├── disk-space-monitor.sh
│   ├── gpu-monitor.sh
│   ├── systemd-failure-notifier.sh
│   ├── daily-summary.sh
│   ├── nixos-rebuild-notifier.sh
│   └── caddy-health-check.sh
│
├── maintenance/         # Maintenance and cleanup tasks
│   └── (future scripts)
│
├── development/         # Development utilities
│   ├── charter-lint.sh
│   ├── script-inventory.sh
│   ├── grebuild.sh
│   ├── list-services.sh
│   └── (other dev tools)
│
├── internal/            # Internal workspace helpers
│   ├── validate-workspace-script.sh
│   └── promote-to-domain.sh
│
├── automation/          # Automated workflows
│   ├── media-orchestrator.py
│   ├── qbt-finished.sh
│   └── sab-finished.py
│
└── utils/              # General utilities
    └── network/        # Network diagnostics
        ├── quicknet.sh
        ├── netcheck.sh
        └── (other network tools)
```

## Three-Tier Architecture

### Tier 1: Nix Commands (User-Facing)
**Location:** `domains/home/environment/shell/parts/*.nix`
**Purpose:** Production commands in PATH via Nix derivations
**Examples:** `grebuild`, `journal-errors`, `list-services`, `charter-lint`, `caddy-health`
**Type:** Nix `writeShellApplication` derivations with pinned runtime dependencies

These are the commands you run directly from the terminal. They are Nix derivations that wrap Tier 2 workspace scripts with proper dependency management.

**Current Commands:**
- `grebuild` → `workspace/scripts/development/grebuild.sh`
- `journal-errors` → `workspace/scripts/monitoring/journal-errors.sh`
- `list-services` → `workspace/scripts/development/list-services.sh`
- `charter-lint` → `workspace/scripts/development/charter-lint.sh`
- `caddy-health` → `workspace/scripts/monitoring/caddy-health-check.sh`

### Tier 2: Workspace Scripts (Implementation)
**Location:** `workspace/scripts/` (this directory)
**Purpose:** Implementation scripts, automation, development tools
**Type:** Bash/Python scripts that can be edited without rebuilding NixOS

These are the actual script files that Tier 1 commands call, or standalone scripts for automation. The workspace scripts are editable at runtime and can be tested without NixOS rebuilds.

**Key Feature:** Dynamic workspace root indirection via `HWC_WORKSPACE_ROOT` and `HWC_WORKSPACE_SCRIPTS` environment variables allows testing scripts from alternate locations without rebuilding.

### Tier 3: Domain-Specific Scripts
**Location:** `domains/*/scripts/` or `domains/*/parts/`
**Purpose:** Scripts specific to a domain/service
**Examples:** `domains/server/frigate-v2/scripts/verify-config.sh`

These scripts are tightly coupled to specific services or domains and should not be promoted to Tier 1/2.

## Dynamic Workspace Root

The workspace scripts use dynamic path resolution via environment variables:

```bash
HWC_WORKSPACE_ROOT="${HOME}/.nixos/workspace"  # Set by Nix config
HWC_WORKSPACE_SCRIPTS="$HWC_WORKSPACE_ROOT/scripts"
```

### Runtime Override

To test scripts from a different workspace location without rebuilding:

```bash
export HWC_WORKSPACE_ROOT="/path/to/custom/workspace"
export HWC_WORKSPACE_SCRIPTS="$HWC_WORKSPACE_ROOT/scripts"

# Now all Tier 1 commands will use scripts from the custom location
grebuild --help
```

This allows:
- Testing workspace changes without NixOS rebuilds
- Development workflow isolation
- Quick script iteration during development

**Important:** Override only affects the current shell session. To persist, rebuild with modified Nix configuration.

## Usage

### From Terminal (Tier 1 Commands)
```bash
# Service monitoring
services              # List all services
ss                    # Short alias for list-services

# System health
errors                # Check journal errors
errors-hour           # Errors from last hour
caddy                 # Caddy health check
health                # Alias for caddy-health

# Development
rebuild               # Git + NixOS rebuild
lint                  # Charter compliance check
```

### Direct Script Execution (Tier 2)
```bash
# Monitoring
./workspace/scripts/monitoring/disk-space-monitor.sh
./workspace/scripts/monitoring/gpu-monitor.sh

# Development
./workspace/scripts/development/script-inventory.sh
./workspace/scripts/development/charter-lint.sh

# Automation (usually triggered by systemd)
./workspace/scripts/automation/media-orchestrator.py
```

## Adding New Scripts

### Quick Method: Use Promotion Helper

For user-facing commands (Tier 1):

```bash
# 1. Create your script in workspace/scripts/
vim workspace/scripts/development/my-tool.sh
chmod +x workspace/scripts/development/my-tool.sh

# 2. Validate it meets promotion requirements
bash workspace/scripts/internal/validate-workspace-script.sh workspace/scripts/development/my-tool.sh

# 3. Promote to domain command
bash workspace/scripts/internal/promote-to-domain.sh workspace/scripts/development/my-tool.sh my-tool

# 4. Follow the manual steps printed by promote-to-domain.sh:
#    - Add import in domains/home/environment/shell/index.nix
#    - Add to home.packages
#    - Review runtime dependencies in generated .nix file
#    - Test and rebuild
```

### Manual Method: For User-Facing Commands

1. **Create script** in appropriate `workspace/scripts/` subdirectory:
   ```bash
   vim workspace/scripts/development/my-tool.sh
   chmod +x workspace/scripts/development/my-tool.sh
   ```

2. **Create Nix derivation** in `domains/home/environment/shell/parts/`:
   ```nix
   # domains/home/environment/shell/parts/my-tool.nix
   { pkgs, config, ... }:

   let
     workspaceRoot = config.home.homeDirectory + "/.nixos/workspace";
     workspaceScripts = workspaceRoot + "/scripts";
   in
   pkgs.writeShellApplication {
     name = "my-tool";
     runtimeInputs = with pkgs; [
       bash
       # Add other dependencies
     ];
     text = ''
       exec bash "${workspaceScripts}/development/my-tool.sh" "$@"
     '';
   }
   ```

3. **Import in shell module** (`domains/home/environment/shell/index.nix`):
   ```nix
   let
     cfg = config.hwc.home.shell;

     # Add your import
     my-tool = import ./parts/my-tool.nix { inherit pkgs config; };
   in
   ```

4. **Add to packages**:
   ```nix
   home.packages = cfg.packages
     ++ [ ... ]
     ++ [
       my-tool  # Add here
     ];
   ```

5. **Test and rebuild**:
   ```bash
   nix flake check
   sudo nixos-rebuild test --flake .#hwc-laptop
   which my-tool
   sudo nixos-rebuild switch --flake .#hwc-laptop
   ```

### For Implementation Scripts (Tier 2)

1. Place in appropriate `workspace/scripts/` subdirectory
2. Make executable: `chmod +x script.sh`
3. Use proper shebang: `#!/usr/bin/env bash` or `#!/usr/bin/env python3`
4. Include usage documentation (search for "Usage:")
5. Use `set -euo pipefail` for robust error handling

### For Domain-Specific Scripts (Tier 3)

Keep them in `domains/<domain>/scripts/` or `domains/<domain>/parts/`

## Migration Notes

This directory consolidates scripts from legacy locations (migration completed 2025-12-10):
- `workspace/utilities/monitoring/` → `workspace/scripts/monitoring/` ✓
- `workspace/utilities/lints/` → `workspace/scripts/development/` ✓
- `workspace/network/` → `workspace/scripts/utils/network/` ✓
- `workspace/scripts/automation/` → `workspace/automation/` ✓

Some utility scripts remain in `workspace/utilities/scripts/` for deployment and setup tasks.

## See Also

- `.claude/agents/SCRIPT-ORGANIZATION.md` - Full organization strategy
- `.script-inventory/SUMMARY.md` - Complete script inventory
- `domains/home/environment/shell/` - Nix command definitions
