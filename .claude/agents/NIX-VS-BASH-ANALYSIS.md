# Nix Files vs Bash Scripts: Analysis & Recommendation

## The Question

**Why do `grebuild` and `journal-errors` have separate `.nix` files in `parts/`, while other scripts just live in `workspace/scripts/`?**

Is this necessary, or just legacy sprawl?

## Current State

### Approach A: Nix Derivation (grebuild, journal-errors)
```
domains/home/environment/shell/parts/
├── grebuild.nix (395 lines)
└── journal-errors.nix (99 lines)

Usage in index.nix:
  grebuildScript = import ./parts/grebuild.nix { inherit pkgs; };
  home.packages = [ grebuildScript ];
```

### Approach B: Shell Function (list-services, charter-lint, caddy-health)
```
workspace/scripts/
├── development/list-services.sh
├── development/charter-lint.sh
└── monitoring/caddy-health-check.sh

Usage in index.nix:
  initContent = ''
    list-services() { bash ~/.nixos/workspace/scripts/.../list-services.sh "$@" }
  '';
```

## Key Differences

### Approach A: `pkgs.writeShellApplication` (Nix Derivation)

**What it does:**
```nix
pkgs.writeShellApplication {
  name = "grebuild";
  runtimeInputs = with pkgs; [ git nixos-rebuild sudo coreutils hostname ];
  text = ''
    # Script content embedded here
  '';
}
```

**Result:**
- Creates executable in `/nix/store/...-grebuild/bin/grebuild`
- Automatically in PATH (via `home.packages`)
- Dependencies guaranteed available
- Script is immutable (can't edit without rebuild)

**Benefits:**
- ✅ Dependency management: Nix ensures all tools available
- ✅ Reproducible: Same script, same dependencies, everywhere
- ✅ Pure: Lives in Nix store, can't be accidentally modified
- ✅ Portable: Works on any NixOS system

**Drawbacks:**
- ❌ Requires rebuild to update script
- ❌ Script content embedded in Nix file (not in workspace/)
- ❌ More complex (Nix syntax + shell escaping)
- ❌ Creates "sprawl" (script exists in parts/, not workspace/)

### Approach B: Shell Function + Bash Script

**What it does:**
```nix
initContent = ''
  list-services() {
    bash ~/.nixos/workspace/scripts/development/list-services.sh "$@"
  }
'';
```

**Result:**
- Function defined in `.zshrc`
- Calls script from `workspace/scripts/`
- Script can be edited directly
- Dependencies assumed to exist in environment

**Benefits:**
- ✅ No sprawl: Script in workspace/ only
- ✅ Easy updates: Edit script, no rebuild
- ✅ Simple: Just bash, no Nix complexity
- ✅ Visible: Script is a real file you can see/edit

**Drawbacks:**
- ❌ No dependency management: Assumes tools installed
- ❌ Not in PATH directly (need function wrapper)
- ❌ Less portable: Might break if tools missing
- ❌ Not pure: Script can be modified

## The Real Question: Do We Need Nix Dependency Management?

### What Dependencies Do These Scripts Actually Need?

**grebuild (parts/grebuild.nix):**
```nix
runtimeInputs = [ git nixos-rebuild sudo coreutils hostname ];
```

**grebuild (workspace/grebuild.sh):**
```bash
#!/usr/bin/env bash
# Uses: git, nixos-rebuild, sudo, curl, systemctl
```

**journal-errors (parts/journal-errors.nix):**
```nix
runtimeInputs = [ systemd coreutils gawk gnused gnugrep ];
```

**Analysis:**
- All these tools are **already in your base environment**
- `git`, `sudo`, `systemd`, `coreutils` are NixOS defaults
- `nixos-rebuild` is always available on NixOS
- These aren't exotic dependencies

**Conclusion:** The `runtimeInputs` in the Nix files aren't adding much value because these tools are already guaranteed to exist on your system.

## The Duplication Problem

You actually have **TWO versions** of grebuild:

1. **`parts/grebuild.nix`** (395 lines) - Nix derivation
2. **`workspace/scripts/development/grebuild.sh`** (457 lines) - Bash script

**Which one is used?**
- Currently: The Nix version (via `home.packages`)
- The workspace version is ignored (dead code)

**This is sprawl!** You're maintaining two versions of the same script.

## Recommendation: Unified Approach

### Option 1: Pure Workspace (Recommended) ✅

**Eliminate sprawl, keep it simple:**

```nix
# In index.nix
programs.zsh = {
  initContent = ''
    # All commands as functions
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
  '';
};
```

**Result:**
```
workspace/scripts/
├── development/
│   ├── grebuild.sh
│   ├── list-services.sh
│   └── charter-lint.sh
└── monitoring/
    ├── journal-errors.sh
    └── caddy-health-check.sh

domains/home/environment/shell/
├── index.nix (functions only)
└── options.nix (aliases only)
```

**Benefits:**
- ✅ **No sprawl:** All scripts in ONE place
- ✅ **Easy updates:** Edit script directly, no rebuild
- ✅ **Charter compliant:** Module invokes, doesn't duplicate
- ✅ **Simple:** Just bash, no Nix complexity
- ✅ **Dual-use:** Same scripts work with AI or terminal

**Tradeoffs:**
- ⚠️ No explicit dependency management (but not needed for these scripts)
- ⚠️ Not directly in PATH (but aliases make this irrelevant)

### Option 2: Hybrid (Not Recommended) ⚠️

Keep Nix files for "critical" scripts, shell functions for others.

**Problem:** Inconsistent, hard to remember which is which, still creates sprawl.

### Option 3: All Nix Derivations (Not Recommended) ❌

Move all scripts to `parts/` as Nix derivations.

**Problem:** Maximum sprawl, hard to update, complex, overkill for simple scripts.

## Dependency Management: The Real Story

### When Nix Dependency Management Matters

**Good use cases:**
- Script needs exotic tools not in base system
- Script needs specific versions of tools
- Script needs to be portable across non-NixOS systems
- Script is part of a package build process

**Example:**
```nix
pkgs.writeShellApplication {
  name = "video-processor";
  runtimeInputs = [ ffmpeg imagemagick python312Packages.opencv ];
  text = ''...''
}
```

### When It Doesn't Matter

**Your scripts:**
- Use only base system tools (git, systemd, coreutils)
- Run on NixOS only (not portable)
- Need frequent updates (rebuild friction)
- Are personal utilities (not distributed packages)

**Verdict:** For your use case, Nix dependency management is **overkill**.

## How to Handle Dependencies

### Approach: Document + Verify

Instead of Nix `runtimeInputs`, use script headers:

```bash
#!/usr/bin/env bash
# grebuild - Git + NixOS rebuild workflow
#
# Dependencies: git, nixos-rebuild, sudo (all standard on NixOS)
# Location: workspace/scripts/development/grebuild.sh

set -euo pipefail

# Verify critical dependencies (optional)
for cmd in git nixos-rebuild sudo; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: Required command '$cmd' not found" >&2
    exit 1
  fi
done

# Rest of script...
```

**Benefits:**
- ✅ Documents what's needed
- ✅ Fails fast if something missing
- ✅ No Nix complexity
- ✅ Easy to understand

## Migration Plan

### Step 1: Consolidate grebuild

**Current state:**
- `parts/grebuild.nix` (395 lines) - Used
- `workspace/scripts/development/grebuild.sh` (457 lines) - Ignored

**Action:**
1. Compare the two versions
2. Keep the better one (probably workspace version)
3. Delete the other
4. Add shell function in `index.nix`

### Step 2: Move journal-errors

**Current state:**
- `parts/journal-errors.nix` (99 lines) - Used
- No workspace version

**Action:**
1. Extract script from `.nix` file
2. Save to `workspace/scripts/monitoring/journal-errors.sh`
3. Add shell function in `index.nix`
4. Delete `parts/journal-errors.nix`

### Step 3: Clean up

**Delete:**
- `domains/home/environment/shell/parts/grebuild.nix`
- `domains/home/environment/shell/parts/journal-errors.nix`

**Result:**
- `parts/` directory is empty (can delete)
- All scripts in `workspace/scripts/`
- All functions in `index.nix`
- All aliases in `options.nix`

## Final Recommendation

### ✅ Use Pure Workspace Approach

**Why:**
1. **No sprawl:** Scripts in ONE place only
2. **Charter compliant:** Separation of invocation and implementation
3. **Easy maintenance:** Edit scripts directly, no rebuild
4. **Simple:** No Nix complexity, just bash
5. **Sufficient:** Dependency management not needed for your use case

**Structure:**
```
workspace/scripts/
├── development/
│   ├── grebuild.sh
│   ├── list-services.sh
│   └── charter-lint.sh
└── monitoring/
    ├── journal-errors.sh
    ├── caddy-health-check.sh
    ├── disk-space-monitor.sh
    └── gpu-monitor.sh

domains/home/environment/shell/
├── index.nix
│   └── initContent = ''
│         grebuild() { bash ~/.nixos/workspace/scripts/.../grebuild.sh "$@" }
│         journal-errors() { bash ~/.nixos/workspace/scripts/.../journal-errors.sh "$@" }
│         list-services() { bash ~/.nixos/workspace/scripts/.../list-services.sh "$@" }
│         ...
│       '';
└── options.nix
    └── aliases = {
          "rebuild" = "grebuild";
          "errors" = "journal-errors";
          "services" = "list-services";
          ...
        };
```

**Usage:**
```bash
$ grebuild "commit message"    # Function calls script
$ rebuild "commit message"     # Alias calls function
$ errors                       # Alias calls function
$ services                     # Alias calls function
```

## Summary

### The Answer

**Q: Why do grebuild and journal-errors have separate Nix files?**

**A: They don't need to.** It's legacy sprawl from before you established the workspace organization pattern.

### The Solution

1. **Extract scripts** from `.nix` files to `workspace/scripts/`
2. **Define functions** in `index.nix` to call scripts
3. **Keep aliases** in `options.nix` for convenience
4. **Delete** `parts/*.nix` files

### The Benefits

- ✅ Clean: All scripts in one place
- ✅ Simple: No Nix complexity
- ✅ Maintainable: Edit scripts directly
- ✅ Charter compliant: No sprawl
- ✅ Sufficient: Dependency management not needed

### Next Steps

Want me to:
1. Extract `journal-errors` from Nix to workspace?
2. Consolidate the two `grebuild` versions?
3. Update `index.nix` with all functions?
4. Delete the `parts/` directory?
