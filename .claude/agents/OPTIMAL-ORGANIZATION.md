# Optimal Script Organization Strategy

## Core Principle

**ONE location for scripts, functions to invoke them.**

```
Scripts (Implementation)     → workspace/scripts/
Functions (Invocation)       → domains/home/environment/shell/index.nix
Aliases (Convenience)        → domains/home/environment/shell/options.nix
```

## The Clean Architecture

### Directory Structure

```
workspace/scripts/
├── development/              # Development utilities
│   ├── grebuild.sh          # Git + rebuild workflow
│   ├── list-services.sh     # Service status
│   ├── charter-lint.sh      # Code quality
│   └── script-inventory.sh  # Script management
│
├── monitoring/              # System monitoring
│   ├── journal-errors.sh    # Log analysis
│   ├── caddy-health-check.sh
│   ├── disk-space-monitor.sh
│   ├── gpu-monitor.sh
│   └── systemd-failure-notifier.sh
│
├── automation/              # Automated workflows
│   ├── media-orchestrator.py
│   ├── qbt-finished.sh
│   └── sab-finished.py
│
├── maintenance/             # Maintenance tasks
│   └── (future scripts)
│
└── utils/                   # General utilities
    └── network/             # Network diagnostics
        ├── quicknet.sh
        └── netcheck.sh

domains/home/environment/shell/
├── index.nix                # Function definitions
└── options.nix              # Alias definitions
```

### No More `parts/` Directory

**Delete it.** Scripts don't belong there.

## Implementation Pattern

### 1. Script (in workspace/scripts/)

```bash
#!/usr/bin/env bash
# grebuild - Git + NixOS rebuild workflow
#
# Dependencies: git, nixos-rebuild, sudo (standard on NixOS)
# Location: workspace/scripts/development/grebuild.sh
# Invoked by: Shell function in domains/home/environment/shell/index.nix

set -euo pipefail

# Optional: Verify dependencies
for cmd in git nixos-rebuild sudo; do
  command -v "$cmd" &>/dev/null || {
    echo "Error: Required command '$cmd' not found" >&2
    exit 1
  }
done

# Script logic here...
```

### 2. Function (in index.nix)

```nix
programs.zsh = lib.mkIf cfg.zsh.enable {
  initContent = ''
    # Development commands
    grebuild() {
      bash ${config.home.homeDirectory}/.nixos/workspace/scripts/development/grebuild.sh "$@"
    }
    
    list-services() {
      bash ${config.home.homeDirectory}/.nixos/workspace/scripts/development/list-services.sh "$@"
    }
    
    charter-lint() {
      bash ${config.home.homeDirectory}/.nixos/workspace/scripts/development/charter-lint.sh "$@"
    }
    
    # Monitoring commands
    journal-errors() {
      bash ${config.home.homeDirectory}/.nixos/workspace/scripts/monitoring/journal-errors.sh "$@"
    }
    
    caddy-health() {
      bash ${config.home.homeDirectory}/.nixos/workspace/scripts/monitoring/caddy-health-check.sh "$@"
    }
  '';
};
```

### 3. Aliases (in options.nix)

```nix
aliases = lib.mkOption {
  default = {
    # Development
    "rebuild" = "grebuild";
    "lint" = "charter-lint";
    
    # Monitoring
    "services" = "list-services";
    "ss" = "list-services";
    "errors" = "journal-errors";
    "caddy" = "caddy-health";
    "health" = "caddy-health";
  };
};
```

## Benefits

### ✅ No Sprawl
- Scripts exist in ONE place only
- No duplication between `parts/` and `workspace/`
- Clear separation of concerns

### ✅ Easy Maintenance
- Edit script directly in `workspace/scripts/`
- No rebuild required for script changes
- Version control tracks actual scripts

### ✅ Charter Compliant
- Module defines invocation, not implementation
- Scripts are implementation details
- Clean architecture

### ✅ Dual-Use
- Same scripts work with AI agents
- Same scripts work from terminal
- Single source of truth

### ✅ Simple
- No Nix complexity for simple scripts
- Just bash, easy to understand
- Easy to debug

## When to Use Nix Derivations

**Only when truly necessary:**

### Use Case 1: Exotic Dependencies
```nix
# Script needs tools not in base system
pkgs.writeShellApplication {
  name = "video-processor";
  runtimeInputs = [ ffmpeg imagemagick python312Packages.opencv ];
  text = ''...'';
}
```

### Use Case 2: Portable Packages
```nix
# Script distributed as package
pkgs.writeShellApplication {
  name = "my-tool";
  runtimeInputs = [ ... ];
  text = ''...'';
}
```

### Use Case 3: Build-Time Scripts
```nix
# Script runs during Nix build
pkgs.runCommand "generate-config" { ... } ''
  ...
'';
```

### NOT for Personal Utilities

**Your daily driver scripts:**
- ❌ Don't need exotic dependencies
- ❌ Aren't distributed packages
- ❌ Don't run at build time
- ✅ Should be in `workspace/scripts/`

## Migration Steps

### Step 1: Extract journal-errors

```bash
# Create the script file
cat > workspace/scripts/monitoring/journal-errors.sh << 'EOF'
#!/usr/bin/env bash
# journal-errors - Summarize and deduplicate journalctl errors
# Dependencies: systemd, coreutils, gawk, sed, grep (standard on NixOS)

set -euo pipefail

TIME_WINDOW="${1:-10 minutes ago}"
SERVICE="${2:-}"

# [Rest of script from journal-errors.nix...]
EOF

chmod +x workspace/scripts/monitoring/journal-errors.sh
```

### Step 2: Consolidate grebuild

```bash
# You have two versions:
# 1. parts/grebuild.nix (395 lines)
# 2. workspace/scripts/development/grebuild.sh (457 lines)

# Compare them
diff -u domains/home/environment/shell/parts/grebuild.nix \
        workspace/scripts/development/grebuild.sh

# Keep the better one (probably workspace version)
# Make sure it's executable
chmod +x workspace/scripts/development/grebuild.sh
```

### Step 3: Update index.nix

```nix
# Remove these lines:
let
  grebuildScript = import ./parts/grebuild.nix { inherit pkgs; };
  journalErrorsScript = import ./parts/journal-errors.nix { inherit pkgs; };
in
{
  home.packages = [
    grebuildScript
    journalErrorsScript
  ];
}

# Add these to initContent:
programs.zsh = {
  initContent = ''
    grebuild() {
      bash ${config.home.homeDirectory}/.nixos/workspace/scripts/development/grebuild.sh "$@"
    }
    
    journal-errors() {
      bash ${config.home.homeDirectory}/.nixos/workspace/scripts/monitoring/journal-errors.sh "$@"
    }
  '';
};
```

### Step 4: Clean up

```bash
# Delete the Nix files
rm domains/home/environment/shell/parts/grebuild.nix
rm domains/home/environment/shell/parts/journal-errors.nix

# Delete the parts directory (now empty)
rmdir domains/home/environment/shell/parts/
```

### Step 5: Update options.nix

```nix
# Remove these (no longer needed):
scripts = {
  grebuild = lib.mkOption { ... };
  journalErrors = lib.mkOption { ... };
};

# Aliases stay the same (already correct)
```

## Result

### Before (Sprawl ❌)
```
domains/home/environment/shell/parts/
├── grebuild.nix (395 lines)          ← Nix derivation
└── journal-errors.nix (99 lines)     ← Nix derivation

workspace/scripts/development/
└── grebuild.sh (457 lines)           ← Duplicate, ignored

Result: Scripts in TWO places, duplication, complexity
```

### After (Clean ✅)
```
workspace/scripts/
├── development/
│   ├── grebuild.sh                   ← Single source
│   ├── list-services.sh
│   └── charter-lint.sh
└── monitoring/
    ├── journal-errors.sh             ← Single source
    └── caddy-health-check.sh

domains/home/environment/shell/
├── index.nix                         ← Functions only
└── options.nix                       ← Aliases only

Result: Scripts in ONE place, no duplication, simple
```

## Usage Examples

### After Migration

```bash
# All commands work the same
$ grebuild "commit message"
$ rebuild "commit message"    # via alias

$ journal-errors
$ errors                      # via alias
$ errors-hour                 # via alias

$ list-services
$ services                    # via alias
$ ss                          # via alias

$ charter-lint domains/
$ lint domains/               # via alias

$ caddy-health
$ caddy                       # via alias
$ health                      # via alias
```

### Script Updates

```bash
# Edit script directly
$ micro workspace/scripts/development/grebuild.sh

# Changes take effect immediately (no rebuild)
$ grebuild "test change"
```

### AI Integration

```yaml
# Claude agent skill
- name: check-services
  steps:
    - run: bash workspace/scripts/development/list-services.sh
    - analyze: output

- name: check-errors
  steps:
    - run: bash workspace/scripts/monitoring/journal-errors.sh "1 hour ago"
    - summarize: errors
```

## Decision Tree

### "Should this be a Nix derivation or workspace script?"

```
Does it need exotic dependencies not in base NixOS?
├─ YES → Nix derivation (writeShellApplication)
└─ NO ↓

Is it distributed as a package to others?
├─ YES → Nix derivation (writeShellApplication)
└─ NO ↓

Does it run at build time?
├─ YES → Nix derivation (runCommand, etc.)
└─ NO ↓

Is it a personal utility script?
└─ YES → Workspace script (workspace/scripts/)
```

### For Your Scripts

```
grebuild          → Workspace (uses standard tools)
journal-errors    → Workspace (uses standard tools)
list-services     → Workspace (uses standard tools)
charter-lint      → Workspace (uses standard tools)
caddy-health      → Workspace (uses standard tools)
disk-space-monitor → Workspace (uses standard tools)
gpu-monitor       → Workspace (uses standard tools)
```

**All should be in `workspace/scripts/`.**

## Summary

### The Strategy

1. **Scripts in workspace/scripts/** - Single source of truth
2. **Functions in index.nix** - Invocation layer
3. **Aliases in options.nix** - Convenience layer
4. **No parts/ directory** - Eliminate sprawl

### The Benefits

- ✅ Clean: No sprawl, no duplication
- ✅ Simple: Just bash, no Nix complexity
- ✅ Maintainable: Edit scripts directly
- ✅ Charter compliant: Proper separation
- ✅ Robust: Dependency verification in scripts
- ✅ Dual-use: Works with AI and terminal

### The Migration

1. Extract `journal-errors` from Nix to workspace
2. Consolidate two `grebuild` versions
3. Update `index.nix` with functions
4. Remove `parts/` directory
5. Clean up `options.nix`

### Next Steps

Want me to execute this migration?
