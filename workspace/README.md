# HWC Workspace Directory

**Purpose-Driven Script Organization**

Reorganized 2025-12-10 to eliminate ambiguous categories (development, automation, utilities) in favor of explicit purpose-driven structure.

---

## Structure

```
workspace/
├── nixos/           # NixOS config development tools
├── monitoring/      # System health & status checks
├── hooks/           # Event-driven automation scripts
├── diagnostics/     # Troubleshooting & debugging tools
├── setup/           # One-time deployment/installation scripts
├── bible/           # Bible automation system (domain-specific)
├── media/           # Media management tools
└── projects/        # Standalone projects & integrations
```

---

## Category Descriptions

### nixos/ - NixOS Development Tools
**Purpose**: Tools for developing, linting, and managing NixOS configurations

**Contents**:
- Charter compliance tools (charter-lint.sh, autofix.sh, namespace checks)
- Build workflow (grebuild.sh)
- Module scaffolding (add-home-app.sh, add-assertions.sh)
- Development helpers (list-services.sh, promote-to-domain.sh)
- Config analysis (graph/, config-validation/)

**When to use**: Building, testing, or refactoring NixOS modules

---

### monitoring/ - System Health & Status
**Purpose**: Continuous or periodic system health monitoring

**Contents**:
- health-check.sh (comprehensive system health with JSON output)
- journal-errors.sh (system log analysis with filters)
- caddy-health-check.sh (reverse proxy health checks)
- gpu-monitor.sh, disk-space-monitor.sh
- Service-specific health checks (frigate, immich, media)

**When to use**: Scheduled timers, manual health checks, dashboards

---

### hooks/ - Event-Driven Automation
**Purpose**: Scripts triggered by events (downloads, builds, failures)

**Contents**:
- Download completion hooks (qbt-finished.sh, sab-finished.py)
- Media orchestration (media-orchestrator.py)
- System event notifiers (systemd-failure-notifier.sh, nixos-rebuild-notifier.sh)
- Verification hooks (slskd-verify.sh, receipt-monitor.sh)

**When to use**: systemd OnFailure=, download completion callbacks, webhooks

---

### diagnostics/ - Troubleshooting Tools
**Purpose**: Interactive debugging and problem investigation

**Contents**:
- **network/** - Network diagnostics (quicknet.sh, netcheck.sh, wifi tools)
- **config-validation/** - Config analysis and validation
- **nixos-translator/** - System migration/translation tools
- **server/** - Service debugging (debug-slskd.sh, fix_both.sh)
- Repair tools (fix-service-permissions.sh)
- GPU diagnostics (check-gpu-acceleration.sh)

**When to use**: Troubleshooting issues, investigating problems, system audits

---

### setup/ - One-Time Deployment
**Purpose**: Initial installation and deployment scripts

**Contents**:
- deploy-age-keys.sh (encryption key deployment)
- sops-verify.sh (secrets verification)
- setup-monitoring.sh, setup-tdarr-auto.py
- deploy-agent-improvements.sh

**When to use**: New system setup, major deployments, infrastructure changes

---

### bible/ - Bible Automation System
**Purpose**: Automated consistency management for biblical text corpus

**Contents**:
- Workflow management (bible_workflow_manager.py)
- System lifecycle (installer, migrator, validator, cleanup)
- Content processing (rewriter, consistency_manager)
- Post-build hooks and debugging toolkit

**When to use**: Domain-specific automation - kept together for cohesion

---

### media/ - Media Management Tools
**Purpose**: Media library organization and management

**Contents**:
- beets-helper.sh, beets-container-helper.sh (music library management)
- media-organizer.sh (file organization)
- immich-configure-storage.sh (photo management setup)

**When to use**: Media library maintenance, organization workflows

---

### projects/ - Standalone Projects
**Purpose**: Self-contained projects and integrations

**Structure**:
```
projects/
├── productivity/        # Productivity tools
│   ├── transcript-formatter/
│   ├── ai-docs/
│   └── music_duplicate_detector.sh
├── bible-plan/          # Bible study planning
├── estimate-automation/ # Estimation system
├── receipts-pipeline/   # OCR receipt processing
└── site-crawler/        # Web scraping project
```

**When to use**: Standalone tooling, planned n8n workflow integrations

---

## Three-Tier Architecture

### Tier 1: User Commands (Nix Derivations)
**Location**: `domains/home/environment/shell/parts/*.nix`
**Purpose**: Production commands in PATH via Nix derivations
**Examples**: `grebuild`, `journal-errors`, `list-services`, `charter-lint`, `caddy-health`

These are Nix `writeShellApplication` derivations that wrap Tier 2 workspace scripts with proper dependency management.

### Tier 2: Workspace Scripts (Implementation)
**Location**: `workspace/{nixos,monitoring,hooks,diagnostics,setup}/`
**Purpose**: Implementation scripts that can be edited without rebuilding NixOS
**Type**: Bash/Python scripts

These are the actual script files. The workspace scripts are editable at runtime and can be tested without NixOS rebuilds.

### Tier 3: Domain-Specific Scripts
**Location**: `domains/*/scripts/` or `domains/*/parts/`
**Purpose**: Scripts tightly coupled to specific services or domains

These scripts are domain-specific and should not be promoted to Tier 1/2.

---

## Adding New Scripts

### For User-Facing Commands (Tier 1):

1. **Create script** in appropriate workspace category:
   ```bash
   vim workspace/nixos/my-tool.sh
   chmod +x workspace/nixos/my-tool.sh
   ```

2. **Create Nix derivation** in `domains/home/environment/shell/parts/`:
   ```nix
   # domains/home/environment/shell/parts/my-tool.nix
   { pkgs, config, ... }:

   let
     workspace = config.home.homeDirectory + "/.nixos/workspace";
   in
   pkgs.writeShellApplication {
     name = "my-tool";
     runtimeInputs = with pkgs; [
       bash
       # Add dependencies
     ];
     text = ''
       exec bash "${workspace}/nixos/my-tool.sh" "$@"
     '';
   }
   ```

3. **Import in shell module** (`domains/home/environment/shell/index.nix`):
   ```nix
   let
     # Add import
     my-tool = import ./parts/my-tool.nix { inherit pkgs config; };
   in
   {
     config = lib.mkIf cfg.enable {
       home.packages = cfg.packages ++ [
         # ... other packages
         my-tool  # Add here
       ];
     };
   }
   ```

4. **Test and rebuild**:
   ```bash
   nix flake check
   sudo nixos-rebuild test --flake .#hwc-laptop
   which my-tool
   sudo nixos-rebuild switch --flake .#hwc-laptop
   ```

### For Implementation Scripts (Tier 2):

1. Place in appropriate workspace category based on purpose
2. Make executable: `chmod +x script.sh`
3. Use proper shebang: `#!/usr/bin/env bash` or `#!/usr/bin/env python3`
4. Include usage documentation
5. Use `set -euo pipefail` for robust error handling

---

## Organization Principles

### Purpose Over Function
Scripts are categorized by:
- **What triggers them** (user command, event, timer)
- **What domain they serve** (NixOS dev, system monitoring, media)
- **When you use them** (setup once, diagnose problem, automate event)

### Explicit > Implicit
- `nixos/` - immediately clear: NixOS development
- `hooks/` - immediately clear: triggered by events
- `diagnostics/` - immediately clear: troubleshooting tools

vs. old ambiguous structure:
- `development/` - development of what? NixOS? Media? Apps?
- `automation/` - automated how? Events? Timers? CI/CD?
- `utilities/` - utility for what? Everything is a utility!

### Domain Cohesion
Bible automation system kept together despite spanning multiple purposes (setup, hooks, validation) because domain cohesion > strict categorization.

---

## Migration History

**2025-12-10**: Reorganized from arbitrary categories to purpose-driven structure
- Removed intermediate `scripts/` directory (flattened)
- Distributed 100+ scripts across purpose-driven categories
- Updated all references in shell wrappers and modules
- Completes consolidation effort started in commits ff8be80 and 1568e16

**Old structure** (deprecated):
```
workspace/
├── scripts/           # Unnecessary intermediate directory
│   ├── development/   # Ambiguous category
│   ├── monitoring/    # Better, but nested under scripts/
│   └── utils/         # Generic catch-all
├── automation/        # Ambiguous purpose
├── utilities/         # Another generic catch-all
└── infrastructure/    # Unclear boundary
```

**New structure** (current):
```
workspace/
├── nixos/            # NixOS config dev (clear purpose)
├── monitoring/       # System health (clear trigger)
├── hooks/            # Event-driven (clear trigger)
├── diagnostics/      # Troubleshooting (clear purpose)
├── setup/            # One-time deployment (clear usage)
├── bible/            # Domain-specific (clear boundary)
├── media/            # Media tools (clear domain)
└── projects/         # Standalone projects (clear boundary)
```

---

## Environment Variables

- `HWC_WORKSPACE_ROOT` - Workspace root directory (default: `~/.nixos/workspace`)

For runtime testing without rebuilds:
```bash
export HWC_WORKSPACE_ROOT="/path/to/custom/workspace"
grebuild --help  # Now uses custom workspace location
```

---

## See Also

- `CLAUDE.md` - Repository guide for AI assistants
- `domains/home/environment/shell/` - Nix command definitions (Tier 1)
- `.claude/agents/SCRIPT-ORGANIZATION.md` - Original organization strategy
