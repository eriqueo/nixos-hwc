---
name: Add Home App
description: Automated workflow to scaffold a new Home Manager application in nixos-hwc following Charter v6.0 patterns with full structure and validation
---

# Add Home App Workflow

This skill provides a **complete automated workflow** to add a new Home Manager application to nixos-hwc.

## What This Skill Does

When you need to add a new desktop/terminal application (Firefox, Slack, VSCode, etc.), this skill:

1. ✅ Creates proper directory structure
2. ✅ Generates `options.nix` with correct namespace
3. ✅ Generates `index.nix` with HM configuration
4. ✅ Creates `sys.nix` if system packages needed
5. ✅ Adds import to `profiles/home.nix`
6. ✅ Validates build succeeds

**Token savings**: ~70% compared to manual exploration and creation.

## Usage

Just say: **"Add home app for [application-name]"**

Examples:
- "Add home app for Slack"
- "Add home app for VSCode"
- "Add home app for Alacritty terminal"

## Workflow Steps

### Step 1: Gather Information

I'll ask you:
- **App name** (kebab-case, e.g., `visual-studio-code`)
- **Description** (one-line, e.g., "Visual Studio Code IDE")
- **Package name** from nixpkgs (e.g., `vscode`)
- **Needs system packages?** (Yes/No - for themes, dependencies, etc.)
- **Configuration needed?** (Basic enable only, or custom config?)
- **Dependencies?** (Other HWC modules it requires)

### Step 2: Create Directory Structure

```bash
mkdir -p domains/home/apps/<app-name>
```

Creates: `domains/home/apps/<app-name>/`

### Step 3: Generate `options.nix`

```nix
# domains/home/apps/<app-name>/options.nix
{ lib, ... }: {
  options.hwc.home.apps.<app-name> = {
    enable = lib.mkEnableOption "<description>";

    # Additional options if needed
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.<package-name>;
      description = "Package to use for <app-name>";
    };
  };
}
```

**Namespace**: `hwc.home.apps.<app-name>.*` (matches folder structure!)

### Step 4: Generate `index.nix`

**Template A: Simple Package Install**
```nix
# domains/home/apps/<app-name>/index.nix
{ config, pkgs, lib, ... }:
let
  cfg = config.hwc.home.apps.<app-name>;
in {
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    # IMPLEMENTATION
    home.packages = [ cfg.package ];

    # VALIDATION
    # (Add if dependencies exist)
  };
}
```

**Template B: With Program Configuration**
```nix
# domains/home/apps/<app-name>/index.nix
{ config, pkgs, lib, ... }:
let
  cfg = config.hwc.home.apps.<app-name>;
in {
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    # IMPLEMENTATION
    programs.<app-name> = {
      enable = true;
      package = cfg.package;

      # App-specific configuration
      settings = {
        # ...
      };
    };

    # VALIDATION
    assertions = [{
      assertion = !cfg.enable || <dependency-check>;
      message = "<app-name> requires <dependency>";
    }];
  };
}
```

**Template C: XDG Desktop App**
```nix
# domains/home/apps/<app-name>/index.nix
{ config, pkgs, lib, ... }:
let
  cfg = config.hwc.home.apps.<app-name>;
in {
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    # IMPLEMENTATION
    home.packages = [ cfg.package ];

    xdg.configFile."<app-name>/config.json".text = builtins.toJSON {
      # Configuration
    };

    # VALIDATION
  };
}
```

### Step 5: Generate `sys.nix` (If Needed)

Only if app needs system-level packages (fonts, themes, system dependencies):

```nix
# domains/home/apps/<app-name>/sys.nix
{ config, pkgs, lib, ... }:
let
  cfg = config.hwc.home.apps.<app-name>;
in {
  config = lib.mkIf cfg.enable {
    # System-lane code (imported by profiles/system.nix)
    environment.systemPackages = with pkgs; [
      <app-name>-themes
      <app-name>-plugins
    ];

    # System-level policies
    programs.<app-name>.policies = {
      # ...
    };
  };
}
```

### Step 6: Add to Profile

Edit `profiles/home.nix` in the **OPTIONAL FEATURES** section:

```nix
# profiles/home.nix
{
  #==========================================================================
  # OPTIONAL FEATURES - Sensible defaults, override per machine
  #==========================================================================

  imports = [
    # ... existing imports ...
    ../domains/home/apps/<app-name>
  ];

  # Default: enabled (override in machine config if needed)
  hwc.home.apps.<app-name>.enable = lib.mkDefault true;
}
```

If `sys.nix` exists, also add to `profiles/system.nix`:

```nix
# profiles/system.nix
imports = [
  # ... existing imports ...
  ../domains/home/apps/<app-name>/sys.nix
];
```

### Step 7: Validate Build

```bash
# Dry build to check for errors
nixos-rebuild dry-build --flake .#laptop

# If successful, show success message
# If errors, diagnose and fix
```

### Step 8: Test on Machine (Optional)

```bash
# Build and switch
nixos-rebuild switch --flake .#laptop

# Verify app is installed
which <app-name>

# Test launch (if GUI)
<app-name> &
```

## Common App Patterns

### Terminal App (Simple)
```nix
# Just add package
home.packages = [ pkgs.htop ];
```

### Terminal App (With Config)
```nix
# Use programs.* module
programs.zsh = {
  enable = true;
  # ... config ...
};
```

### GUI App (Flatpak-like)
```nix
# Package + XDG config
home.packages = [ pkgs.obsidian ];
xdg.configFile."obsidian/config.json".source = ./config.json;
```

### Browser
```nix
# Complex programs.* config
programs.firefox = {
  enable = true;
  profiles.default = {
    # ... extensive config ...
  };
};
```

### IDE/Editor
```nix
# Programs + extensions
programs.vscode = {
  enable = true;
  extensions = with pkgs.vscode-extensions; [
    # ...
  ];
  userSettings = {
    # ...
  };
};
```

## Dependencies Handling

If app depends on other HWC modules:

```nix
# VALIDATION section
assertions = [
  {
    assertion = !cfg.enable || config.hwc.home.apps.hyprland.enable;
    message = "hwc.home.apps.waybar requires hwc.home.apps.hyprland to be enabled";
  }
];

# Auto-enable dependency (optional)
hwc.home.apps.hyprland.enable = lib.mkDefault true;
```

## Theme Integration

For apps that support theming:

```nix
# Use theme adapter
let
  theme = import ../../theme/adapters/<app-name>.nix { inherit config; };
in {
  programs.<app-name> = {
    enable = true;
    colors = theme.colors;  # No hardcoded colors!
  };
}
```

If app needs new theme adapter:
```nix
# domains/home/theme/adapters/<app-name>.nix
{ config }:
let
  palette = config.hwc.home.theme.palette;
in {
  colors = {
    background = palette.base00;
    foreground = palette.base05;
    # ... map palette to app color scheme
  };
}
```

## Checklist

Before marking complete, verify:

- [ ] Directory created: `domains/home/apps/<app-name>/`
- [ ] `options.nix` exists with correct namespace `hwc.home.apps.<app-name>.*`
- [ ] `index.nix` exists with `imports = [ ./options.nix ]`
- [ ] `sys.nix` created if system packages needed
- [ ] Added to `profiles/home.nix` OPTIONAL section
- [ ] Added to `profiles/system.nix` if `sys.nix` exists
- [ ] Dependencies have assertions in VALIDATION section
- [ ] Build succeeds: `nixos-rebuild dry-build --flake .#laptop`
- [ ] Namespace matches folder structure exactly

## Error Handling

If build fails, see error patterns:

- "option does not exist" → Check namespace matches folder
- "infinite recursion" → Check for circular imports
- "attribute missing" → Check if using HM option in system module
- "assertion failed" → Dependency not enabled (enable it or remove assertion)

Use the **nixos-build-doctor** skill for detailed diagnosis!

## Example Session

```
User: Add home app for Slack

Skill: I'll help you add Slack as a Home Manager app. Let me gather some info:

1. Package name in nixpkgs: slack
2. Description: Slack desktop client
3. Needs system packages? No
4. Configuration needed? Basic enable only
5. Dependencies? None

Creating structure...
✅ Created domains/home/apps/slack/
✅ Generated options.nix with hwc.home.apps.slack namespace
✅ Generated index.nix with simple package install
✅ Added to profiles/home.nix OPTIONAL section
✅ Build validation succeeded!

Slack is now available. On next rebuild, it will be installed.
To disable on specific machine: hwc.home.apps.slack.enable = false;
```

## Remember

This is a **workflow skill** - follow the steps systematically:
1. Gather info (ask user)
2. Create structure (mkdir + files)
3. Generate code (using templates)
4. Integrate (profiles)
5. Validate (build)

Don't skip steps! Charter compliance depends on following the pattern exactly.
