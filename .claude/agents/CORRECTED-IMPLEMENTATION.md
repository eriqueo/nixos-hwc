# Charter-Compliant Script Organization Implementation

## What Was Wrong

❌ **Previous approach:** Created separate `.nix` files in `parts/` for each command
- `parts/list-services.nix`
- `parts/charter-lint.nix`
- `parts/caddy-health.nix`

**Problem:** This creates sprawl and violates the charter. Scripts should live in ONE location (`workspace/scripts/`), and the module should simply call them.

## What's Correct Now

✅ **Charter-compliant approach:** All scripts in `workspace/scripts/`, functions defined inline in shell module

### Architecture

```
Scripts (Implementation)
└── workspace/scripts/
    ├── monitoring/caddy-health-check.sh
    ├── development/charter-lint.sh
    └── development/list-services.sh

Shell Module (Invocation)
└── domains/home/environment/shell/index.nix
    └── initContent = ''
          list-services() { bash ~/.nixos/workspace/scripts/.../list-services.sh "$@" }
          charter-lint() { bash ~/.nixos/workspace/scripts/.../charter-lint.sh "$@" }
          caddy-health() { bash ~/.nixos/workspace/scripts/.../caddy-health-check.sh "$@" }
        '';

Aliases (Convenience)
└── domains/home/environment/shell/options.nix
    └── aliases = {
          "services" = "list-services";
          "lint" = "charter-lint";
          "caddy" = "caddy-health";
        };
```

## Implementation Details

### 1. Scripts Location ✅
All scripts live in `workspace/scripts/`:
```
workspace/scripts/
├── monitoring/
│   └── caddy-health-check.sh
└── development/
    ├── list-services.sh
    └── charter-lint.sh
```

### 2. Shell Functions (in index.nix) ✅
```nix
programs.zsh = lib.mkIf cfg.zsh.enable {
  initContent = ''
    # Daily driver script functions
    list-services() {
      bash ${config.home.homeDirectory}/.nixos/workspace/scripts/development/list-services.sh "$@"
    }

    charter-lint() {
      bash ${config.home.homeDirectory}/.nixos/workspace/scripts/development/charter-lint.sh "$@"
    }

    caddy-health() {
      bash ${config.home.homeDirectory}/.nixos/workspace/scripts/monitoring/caddy-health-check.sh "$@"
    }
  '';
};
```

### 3. Aliases (in options.nix) ✅
```nix
aliases = {
  # Service monitoring
  "services" = "list-services";
  "ss" = "list-services";
  
  # Development
  "rebuild" = "grebuild";
  "lint" = "charter-lint";
  
  # Health checks
  "caddy" = "caddy-health";
  "health" = "caddy-health";
};
```

## How It Works

### Flow
```
User types: $ services

1. Zsh alias resolves: services → list-services
2. Shell function executes: list-services() { bash ~/.nixos/workspace/scripts/.../list-services.sh }
3. Script runs from workspace/scripts/
4. Output displayed
```

### Benefits
✅ **Single source of truth:** Scripts only in `workspace/scripts/`
✅ **No sprawl:** No separate wrapper files
✅ **Charter compliant:** Module defines invocation, not implementation
✅ **Easy updates:** Edit script directly, no rebuild needed
✅ **Dual-use:** Same scripts work with AI agents or terminal

## Files Modified

### Removed ❌
- `domains/home/environment/shell/parts/list-services.nix` (deleted)
- `domains/home/environment/shell/parts/charter-lint.nix` (deleted)
- `domains/home/environment/shell/parts/caddy-health.nix` (deleted)

### Modified ✅
- `domains/home/environment/shell/index.nix`
  - Removed script imports
  - Added shell functions in `initContent`
  
- `domains/home/environment/shell/options.nix`
  - Kept aliases (already correct)
  - Removed unnecessary script enable options

### Unchanged ✅
- `workspace/scripts/` (all scripts stay here)
- `domains/home/environment/shell/parts/grebuild.nix` (kept - already correct pattern)
- `domains/home/environment/shell/parts/journal-errors.nix` (kept - already correct pattern)

## Usage

### After Rebuild
```bash
# Rebuild
$ grebuild "fix: make script organization charter-compliant"

# Test commands
$ list-services        # Direct function call
$ services             # Via alias
$ ss                   # Short alias

$ charter-lint         # Direct function call
$ lint                 # Via alias

$ caddy-health         # Direct function call
$ caddy                # Via alias
$ health               # Via alias
```

### Script Locations
```bash
# All scripts in one place
$ ls workspace/scripts/monitoring/
caddy-health-check.sh
daily-summary.sh
disk-space-monitor.sh
gpu-monitor.sh
...

$ ls workspace/scripts/development/
charter-lint.sh
list-services.sh
script-inventory.sh
...
```

## Comparison: Before vs After

### Before (Wrong ❌)
```
domains/home/environment/shell/parts/
├── grebuild.nix
├── journal-errors.nix
├── list-services.nix        ← Wrapper file (sprawl)
├── charter-lint.nix         ← Wrapper file (sprawl)
└── caddy-health.nix         ← Wrapper file (sprawl)

workspace/scripts/
├── development/
│   ├── list-services.sh     ← Actual script
│   └── charter-lint.sh      ← Actual script
└── monitoring/
    └── caddy-health-check.sh ← Actual script
```

**Problem:** Scripts exist in TWO places (parts/ and workspace/)

### After (Correct ✅)
```
domains/home/environment/shell/
├── index.nix                ← Functions defined here
└── options.nix              ← Aliases defined here

workspace/scripts/
├── development/
│   ├── list-services.sh     ← Script (single source)
│   └── charter-lint.sh      ← Script (single source)
└── monitoring/
    └── caddy-health-check.sh ← Script (single source)
```

**Solution:** Scripts in ONE place, invoked by module

## Pattern to Follow

### For New Commands

**DON'T:**
```nix
# ❌ Don't create separate wrapper files
domains/home/environment/shell/parts/my-command.nix
```

**DO:**
```nix
# ✅ Add function to index.nix initContent
programs.zsh = {
  initContent = ''
    my-command() {
      bash ${config.home.homeDirectory}/.nixos/workspace/scripts/category/my-script.sh "$@"
    }
  '';
};

# ✅ Add alias to options.nix
aliases = {
  "mc" = "my-command";
};
```

### Exception: Complex Nix Scripts

**When to use `parts/`:**
- Script needs Nix dependency management (like `grebuild`)
- Script is complex and benefits from `writeShellApplication`
- Script needs to be in Nix store for purity

**Example:** `grebuild.nix` and `journal-errors.nix` are correctly in `parts/` because they use `writeShellApplication` with `runtimeInputs`.

## Summary

### What Changed
1. ✅ Removed wrapper files from `parts/`
2. ✅ Added shell functions to `index.nix` `initContent`
3. ✅ Kept aliases in `options.nix`
4. ✅ All scripts remain in `workspace/scripts/`

### Result
- **Charter compliant:** No sprawl, single source of truth
- **Functional:** Commands work via functions + aliases
- **Maintainable:** Edit scripts directly, no rebuild
- **Dual-use:** Works with or without AI

### Commands Available
```bash
# Direct functions
list-services
charter-lint
caddy-health

# Via aliases
services, ss      → list-services
lint              → charter-lint
caddy, health     → caddy-health
rebuild           → grebuild
errors            → journal-errors
```

**Ready to rebuild and test!**
