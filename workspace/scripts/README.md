# HWC Scripts Directory

Consolidated location for all workspace scripts following the three-tier architecture.

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
│   ├── grebuild.sh (legacy - use Nix command)
│   ├── list-services.sh (legacy - use Nix command)
│   └── (other dev tools)
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
**Location:** `domains/home/environment/shell/parts/`
**Purpose:** Production commands in PATH
**Examples:** `grebuild`, `journal-errors`, `list-services`, `charter-lint`, `caddy-health`

These are the commands you run directly from the terminal.

### Tier 2: Workspace Scripts (Implementation)
**Location:** `workspace/scripts/` (this directory)
**Purpose:** Implementation scripts, automation, development tools

These are the actual script files that Tier 1 commands may call, or standalone scripts for automation.

### Tier 3: Domain-Specific Scripts
**Location:** `domains/*/scripts/` or `domains/*/parts/`
**Purpose:** Scripts specific to a domain/service
**Examples:** `domains/server/frigate-v2/scripts/verify-config.sh`

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

### For User-Facing Commands
1. Create script in appropriate `workspace/scripts/` subdirectory
2. Create Nix wrapper in `domains/home/environment/shell/parts/`
3. Add option in `domains/home/environment/shell/options.nix`
4. Import in `domains/home/environment/shell/index.nix`
5. Add alias if desired

### For Implementation Scripts
1. Place in appropriate `workspace/scripts/` subdirectory
2. Make executable: `chmod +x script.sh`
3. Use proper shebang: `#!/usr/bin/env bash` or `#!/usr/bin/env python3`

### For Domain-Specific Scripts
Keep them in `domains/<domain>/scripts/` or `domains/<domain>/parts/`

## Migration Notes

This directory consolidates scripts from:
- `workspace/utilities/monitoring/` → `workspace/scripts/monitoring/`
- `workspace/utilities/lints/` → `workspace/scripts/development/`
- `workspace/utilities/scripts/` → `workspace/scripts/development/`
- `workspace/network/` → `workspace/scripts/utils/network/`
- `workspace/automation/` → `workspace/scripts/automation/`

Old locations are kept temporarily for compatibility but should be phased out.

## See Also

- `.claude/agents/SCRIPT-ORGANIZATION.md` - Full organization strategy
- `.script-inventory/SUMMARY.md` - Complete script inventory
- `domains/home/environment/shell/` - Nix command definitions
