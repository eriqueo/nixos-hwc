# mkModule Wrapper Plan

## Analysis Summary

Examined module patterns across the codebase:

| Pattern | Example | Structure | Complexity |
|---------|---------|-----------|------------|
| Simple | kitty, polkit | index.nix + options.nix | Low |
| Config-heavy | yazi | index + options + parts/ (attr sets) | Medium |
| Cross-lane | hyprland | index + options + sys.nix + parts/ | High |
| Container | sonarr, lidarr | index + options + sys.nix + parts/ | High |

## Key Observations

### 1. Two Types of Parts
- **Attribute sets** (yazi): Parts return plain data, merged by index.nix
  ```nix
  # parts/keymap.nix returns:
  { "yazi/keymap.toml" = { text = ''...''; }; }
  ```
- **Mini-modules** (hyprland): Parts are functions with `{ config, lib, pkgs, ... }:`
  ```nix
  # parts/session.nix returns:
  { execOnce = [...]; env = [...]; packages = [...]; files = {...}; }
  ```

### 2. sys.nix Pattern
When a home-lane module needs system-lane dependencies:
- `sys.nix` defines `hwc.system.apps.<name>` options
- Provides systemPackages, systemd services, tmpfiles
- System evaluates BEFORE Home Manager
- Validation flows one way: home can check system, not vice versa

### 3. Consistent Naming Convention
Already established for containers, apply to all:
- `index.nix` - Main module, imports, mkIf wrapper
- `options.nix` - Option declarations
- `sys.nix` - System-lane dependencies (when needed)
- `parts/config.nix` - App configuration fragments
- `parts/setup.nix` - Runtime/external setup

## Proposal: mkModule Helper

Rather than a full wrapper (which would add complexity), provide **documentation + validation** that enforces the pattern.

### Why NOT a Heavy Wrapper

1. **Too many variations**: Home apps, system modules, containers all have different needs
2. **NixOS module system is already powerful**: mkIf, mkMerge, imports work well
3. **Wrapper hides learning**: New contributors should understand NixOS modules
4. **Debugging**: Wrapped modules are harder to trace

### What WOULD Help

1. **Standardized scaffolding** (already have `add-home-app` skill)
2. **Validation module** that checks structure at build time
3. **Documentation in lib/** (already added to mkContainer.nix)

## Recommended Actions

### 1. Add Module Structure Documentation to lib/
Create `/domains/lib/module-patterns.nix` with:
- Structure guidelines (same as mkContainer.nix comment block)
- When to use sys.nix
- Parts naming convention

### 2. Create Light Helpers (Optional)
```nix
# domains/lib/mkModule.nix
{ lib }:
{
  # Standard option declaration pattern
  mkEnableOpt = desc: lib.mkEnableOption desc;

  # Merge parts into a target attribute (like xdg.configFile)
  mergeParts = parts: lib.mkMerge (map (p: p) parts);

  # Common assertions
  mkDependsOn = { name, requires }: {
    assertion = requires;
    message = "${name} requires ${toString requires} to be enabled";
  };
}
```

### 3. Update Existing Modules Gradually
- Apply `config.nix` / `setup.nix` naming to home apps with parts/
- Add sys.nix where system dependencies exist but aren't separated

## Implementation Priority

1. **Document** - Add module-patterns.nix (low effort, high value)
2. **Standardize naming** - Rename existing parts/ files (medium effort)
3. **Optional helpers** - Only if patterns repeat frequently

## Questions for User

1. Should helpers be prescriptive (enforce structure) or suggestive (provide utilities)?
2. Are there modules that don't fit these patterns?
3. Priority: documentation-first or helpers-first?
