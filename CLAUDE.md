# CLAUDE.md - AI Assistant Guide for nixos-hwc

**Version**: 2.0
**Last Updated**: 2026-01-18
**Charter Version**: v10.3 (January 17, 2026)
**Purpose**: Comprehensive guide for AI assistants working on the HWC NixOS configuration repository

---

## Table of Contents

1. [Repository Overview](#repository-overview)
2. [Architecture Philosophy](#architecture-philosophy)
3. [Directory Structure](#directory-structure)
4. [Development Workflow](#development-workflow)
5. [Module Anatomy](#module-anatomy)
6. [Domain Boundaries](#domain-boundaries)
7. [Common Tasks](#common-tasks)
8. [Validation & Testing](#validation--testing)
9. [Anti-Patterns](#anti-patterns)
10. [Quick Reference](#quick-reference)

---

## Repository Overview

This is a **NixOS flake-based configuration repository** managing multiple machines (laptop and server) using a strict domain-oriented architecture. The repository implements deterministic, reproducible system configurations with clear separation of concerns.

**Key Facts:**
- **Language**: Nix (declarative configuration language)
- **Architecture**: Domain-driven design with strict boundaries
- **Charter Version**: v10.3 (January 17, 2026)
- **Machines**: `hwc-laptop` (workstation), `hwc-server` (infrastructure)
- **Build System**: Nix flakes with Home Manager integration
- **Primary User**: `eric`

**Related Documentation:**
- `CHARTER.md` v10.3 - Authoritative architectural rules and patterns (PRIMARY AUTHORITY)
- `FILESYSTEM_CHARTER.md` - Home directory organization (`~/` structure)
- `AGENTS.md` - Repository agent guidelines (condensed version)
- `workspace/utilities/lints/README.md` - Linting and validation tools

---

## Architecture Philosophy

### Core Principles

1. **Domain Separation**: Code is organized by system interaction boundaries, not by functionality
2. **Namespace Mapping**: Folder paths directly map to option namespaces (`domains/home/apps/firefox/` → `hwc.home.apps.firefox.*`)
3. **Single Source of Truth**: Each concern has exactly one canonical location
4. **Preserve-First**: Refactor = reorganize, never rewrite; 100% feature parity during migrations
5. **Fail-Fast**: Invalid configurations must fail at build time, never at runtime

### Domain Model

```
┌─────────────────────────────────────────────────────────────┐
│  flake.nix (orchestration only, no implementation)          │
└───────────────────────┬─────────────────────────────────────┘
                        │
        ┌───────────────┴───────────────┐
        │                               │
┌───────▼────────┐            ┌─────────▼──────┐
│ Machines       │            │  Profiles      │
│ (hardware +    │            │  (domain       │
│  composition)  │───imports──│   menus)       │
└────────────────┘            └────────┬───────┘
                                       │
                        ┌──────────────┴────────────────┐
                        │                               │
                ┌───────▼────────┐            ┌─────────▼──────────┐
                │  Domains       │            │  Modules           │
                │  (boundaries)  │───contains─│  (implementations) │
                └────────────────┘            └────────────────────┘
```

---

## Directory Structure

```
nixos-hwc/
├── flake.nix                    # Orchestrator: pins inputs, exports nixosConfigurations
├── flake.lock                   # Pinned dependency versions
├── CHARTER.md                   # PRIMARY ARCHITECTURE AUTHORITY (READ THIS FIRST!)
├── FILESYSTEM_CHARTER.md        # Home directory organization rules
├── AGENTS.md                    # Repository agent guidelines
├── CLAUDE.md                    # This file - AI assistant guide
│
├── machines/                    # Machine-specific configuration
│   ├── laptop/
│   │   ├── config.nix          # Hardware facts + profile imports
│   │   ├── hardware.nix        # Hardware-specific settings
│   │   └── home.nix            # Home Manager activation (machine-specific)
│   └── server/
│       ├── config.nix
│       ├── hardware.nix
│       └── home.nix
│
├── profiles/                    # Domain feature menus (BASE + OPTIONAL)
│   ├── system.nix              # System domain menu
│   ├── home.nix                # Home Manager domain menu
│   ├── infrastructure.nix      # Infrastructure domain menu
│   ├── server.nix              # Server workloads menu
│   ├── security.nix            # Security hardening menu
│   ├── monitoring.nix          # Monitoring services menu
│   ├── media.nix               # Media services menu
│   ├── business.nix            # Business workloads menu
│   └── ai.nix                  # AI/ML services menu
│
├── domains/                     # Domain implementations
│   ├── system/                 # Core OS, users, services, packages
│   │   ├── index.nix           # Domain aggregator
│   │   ├── core/               # Essential system components
│   │   ├── users/              # User account definitions
│   │   ├── services/           # System services
│   │   ├── packages/           # System package collections
│   │   └── storage/            # System storage configuration
│   │
│   ├── home/                   # User environment (Home Manager)
│   │   ├── index.nix           # Domain aggregator
│   │   ├── apps/               # Application modules
│   │   ├── environment/        # Shell, scripts, environment
│   │   ├── core/               # Essential HM configuration
│   │   └── theme/              # Theming system (palettes + adapters)
│   │
│   ├── infrastructure/         # Hardware management + cross-domain orchestration
│   │   ├── index.nix
│   │   ├── hardware/           # GPU, power, peripherals
│   │   ├── storage/            # Filesystem structure
│   │   └── winapps/            # Windows application integration
│   │
│   ├── server/                 # Host-provided workloads
│   │   ├── index.nix
│   │   ├── containers/         # Containerized services
│   │   ├── jellyfin/           # Media server (native)
│   │   ├── navidrome/          # Music server
│   │   ├── monitoring/         # Grafana, Prometheus, etc.
│   │   └── [other services]
│   │
│   └── secrets/                # Encrypted secrets (agenix)
│       ├── index.nix
│       ├── declarations/       # Secret declarations (API)
│       └── parts/              # Encrypted .age files
│
├── docs/                       # Reference documentation
│   ├── infrastructure/
│   ├── deployment/
│   └── [other docs]
│
└── workspace/                  # Automation, utilities, lints
    ├── automation/             # Deployment scripts, helpers
    ├── utilities/              # Tools and helpers
    │   └── lints/              # Charter compliance linters
    ├── infrastructure/         # Infrastructure automation
    ├── productivity/           # Productivity tools
    ├── projects/               # Project templates
    └── network/                # Network utilities
```

---

## Development Workflow

### Before Starting Work

1. **Read the Charter**: Always consult `CHARTER.md` - it's the primary authority
2. **Understand the Domain**: Identify which domain(s) your work affects
3. **Check Dependencies**: Use `nix flake check` to verify current state
4. **Review Recent Changes**: `git log --oneline -10` to see recent work

### Making Changes

```bash
# 1. Verify current state
nix flake check

# 2. Make changes to appropriate domain module(s)
# Follow module anatomy: options.nix, index.nix, parts/, sys.nix

# 3. Test changes (staging, no activation)
sudo nixos-rebuild test --flake .#hwc-laptop  # or hwc-server

# 4. Run charter linter
./workspace/utilities/lints/charter-lint.sh domains/system --fix  # adjust domain as needed

# 5. Verify with flake check again
nix flake check

# 6. Apply changes if tests pass
sudo nixos-rebuild switch --flake .#hwc-laptop

# 7. Commit with conventional commit format
git commit -m "feat(home.apps.firefox): add privacy hardening settings"
```

### Commit Message Format

Follow conventional commits matching module paths:

```
<type>(<scope>): <description>

Examples:
- feat(home.apps.firefox): add privacy hardening
- fix(system.users.eric): correct shell path
- refactor(server.containers.caddy): restructure routing
- docs(charter): clarify domain boundary rules
- chore(secrets): rotate API keys
```

**Scopes match namespaces**: `home.apps.firefox`, `system.core.networking`, `server.jellyfin`

---

## Module Anatomy

Every module follows a strict structure. Understanding this is critical.

### Required Files

```
domains/<domain>/<category>/<module>/
├── options.nix                  # MANDATORY: API definition (always present)
├── index.nix                    # MANDATORY: Implementation aggregator
├── sys.nix                      # OPTIONAL: System-lane co-located config
└── parts/                       # OPTIONAL: Pure helper functions
    ├── config.nix
    ├── packages.nix
    └── scripts.nix
```

### options.nix

**Purpose**: Define the module's API using NixOS option system
**Namespace**: MUST match folder path

```nix
# domains/home/apps/firefox/options.nix
{ lib, ... }:

{
  options.hwc.home.apps.firefox = {
    enable = lib.mkEnableOption "Enable Firefox browser";

    profiles = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Firefox profiles configuration";
    };
  };
}
```

**Rules:**
- Options NEVER defined outside `options.nix`
- Namespace follows folder: `domains/home/apps/firefox/` → `hwc.home.apps.firefox.*`
- Always use `lib.mkEnableOption` for toggles
- Document all options with `description`

### index.nix

**Purpose**: Main implementation aggregator
**Structure**: OPTIONS → IMPLEMENTATION → VALIDATION

```nix
# domains/home/apps/waybar/index.nix
{ config, lib, pkgs, ... }:

let
  enabled = config.hwc.home.apps.waybar.enable or false;
  cfg = config.hwc.home.apps.waybar;

  # Import pure functions from parts/
  scripts = import ./parts/scripts.nix { inherit pkgs lib; };
  theme = import ./parts/theme.nix { inherit config lib; };
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf enabled {
    home.packages = [ pkgs.waybar ];

    programs.waybar = {
      enable = true;
      settings = {
        # ... configuration
      };
    };
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  config.assertions = lib.mkIf enabled [
    {
      assertion = config.hwc.home.apps.hyprland.enable;
      message = "waybar requires hyprland to be enabled";
    }
  ];
}
```

**Mandatory Sections:**
1. `# OPTIONS` - Import `options.nix`
2. `# IMPLEMENTATION` - Actual configuration (wrapped in `lib.mkIf enabled`)
3. `# VALIDATION` - Assert all dependencies (REQUIRED for fail-fast principle)

### sys.nix

**Purpose**: System-lane configuration co-located with home modules
**When to Use**: When a home app needs system-level packages or configuration

```nix
# domains/home/apps/kitty/sys.nix
{ pkgs, ... }:

{
  # System packages that support the home module
  environment.systemPackages = with pkgs; [
    kitty-themes
  ];
}
```

**Rules:**
- `sys.nix` belongs to SYSTEM lane, even when in `domains/home/apps/`
- Imported by system profiles, NOT by the home module's `index.nix`
- Valid uses: system packages, system policies, udev rules for apps

### parts/

**Purpose**: Pure helper functions with no side effects
**Characteristics:**
- No options definitions
- No direct system configuration
- Return data structures or functions
- Can be imported by `index.nix`

```nix
# domains/home/apps/waybar/parts/theme.nix
{ config, lib }:

let
  palette = config.hwc.home.theme.palette;
in
{
  background = palette.base00;
  foreground = palette.base05;
  # ... pure transformation of theme data
}
```

---

## Domain Boundaries

Understanding domain boundaries is critical to avoid violations.

### Domain Table

| Domain | Purpose | Valid Content | Invalid Content |
|--------|---------|---------------|-----------------|
| **system** | Core OS, users, services | `users.*`, `networking.*`, `services.*`, `environment.systemPackages` | HM configs (`programs.*`, `home.*`), secret values |
| **home** | User environment (HM) | `programs.*`, `home.*`, `xdg.*`, DE/WM configs | `systemd.services`, `environment.systemPackages`, `users.*` |
| **infrastructure** | Hardware + cross-domain orchestration | GPU, storage, virtualization, udev, filesystem structure | HM configs, high-level app logic |
| **server** | Host workloads | Containers, databases, web services, media servers | HM configs |
| **secrets** | Encrypted secrets | Age declarations, secret API at `/run/agenix` | Unencrypted secrets, secret values in git |
| **profiles** | Feature menus | Imports, toggles, BASE/OPTIONAL structure | Implementation logic, HM activation (except `profiles/home.nix`) |
| **machines** | Hardware facts + composition | Hardware config, profile imports, machine-specific overrides | Shared logic, reusable modules |

### Lane Purity Rules

**Critical Concept**: Lanes (system vs home) never cross-import each other's `index.nix`

**Valid:**
- `profiles/system.nix` imports `domains/home/apps/firefox/sys.nix` (system importing system-lane)
- `profiles/home.nix` imports `domains/home/apps/firefox/index.nix` (home importing home-lane)

**Invalid:**
- `domains/home/apps/firefox/index.nix` importing `domains/system/users/eric.nix`
- `domains/system/core/networking.nix` importing any home module

### Home Manager Boundary

**Rule**: Home Manager activation is MACHINE-SPECIFIC, never in profiles

**Exception**: `profiles/home.nix` is the Home Manager domain feature menu

**Pattern in machines/laptop/home.nix:**

```nix
{ config, pkgs, lib, ... }: {
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.eric = {
      imports = [
        ../../domains/home/apps/hyprland
        ../../domains/home/apps/waybar
        ../../domains/home/apps/kitty
      ];
      home.stateVersion = "24.05";
    };
  };
}
```

### Secrets Management

**Location**: `domains/secrets/`

**Permission Model**:
- All secrets: `group = "secrets"; mode = "0440"`
- Service users: `extraGroups = [ "secrets" ]`

**Workflow**:

```bash
# Get public key
sudo age-keygen -y /etc/age/keys.txt

# Encrypt secret
echo "secret-value" | age -r <pubkey> > domains/secrets/parts/domain/name.age

# Verify
sudo age -d -i /etc/age/keys.txt domains/secrets/parts/domain/name.age

# Use in module
config.age.secrets.my-secret = {
  file = ../secrets/parts/domain/name.age;
  group = "secrets";
  mode = "0440";
};
```

---

## Common Tasks

### Adding a New Application Module

```bash
# 1. Create directory structure
mkdir -p domains/home/apps/myapp/parts

# 2. Create options.nix
cat > domains/home/apps/myapp/options.nix <<'EOF'
{ lib, ... }:

{
  options.hwc.home.apps.myapp.enable =
    lib.mkEnableOption "Enable MyApp";
}
EOF

# 3. Create index.nix with mandatory sections
cat > domains/home/apps/myapp/index.nix <<'EOF'
{ config, lib, pkgs, ... }:

let
  enabled = config.hwc.home.apps.myapp.enable or false;
  cfg = config.hwc.home.apps.myapp;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf enabled {
    home.packages = [ pkgs.myapp ];
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  config.assertions = lib.mkIf enabled [
    # Add dependency assertions here
  ];
}
EOF

# 4. Add to profile (profiles/home.nix)
# Import the module in the appropriate section

# 5. Enable in machine config (machines/laptop/home.nix)
# Add to imports list

# 6. Test
nix flake check
sudo nixos-rebuild test --flake .#hwc-laptop
```

### Adding a System Service

```bash
# 1. Create in appropriate domain (system or server)
mkdir -p domains/server/myservice

# 2. Create options.nix
# Follow same pattern as application module

# 3. Create index.nix with service configuration
# Use systemd.services.<name> in IMPLEMENTATION section

# 4. Add to profile (profiles/server.nix)

# 5. Enable in machine config (machines/server/config.nix)
```

### Refactoring a Module

**Remember**: Preserve-First Doctrine - refactor = reorganize, not rewrite

```bash
# 1. Identify feature list
# Document ALL current functionality

# 2. Create new structure following charter
# Maintain 100% feature parity

# 3. Use wrappers/adapters temporarily if needed
# Track in TODO/FIXME comments for removal

# 4. Verify with linter
./workspace/utilities/lints/charter-lint.sh domains/home --fix

# 5. Test both old and new
# Ensure identical behavior

# 6. Switch only on green build
nix flake check && sudo nixos-rebuild test --flake .#hwc-laptop
```

### Updating Dependencies

```bash
# Update all inputs
nix flake update

# Update specific input
nix flake lock --update-input nixpkgs

# Test after update
nix flake check
sudo nixos-rebuild test --flake .#hwc-laptop
```

---

## Validation & Testing

### Charter Linter

**Location**: `workspace/utilities/lints/charter-lint.sh`

**Purpose**: Enforce architectural rules from `CHARTER.md`

```bash
# Check specific domain
./workspace/utilities/lints/charter-lint.sh domains/system

# Auto-fix issues
./workspace/utilities/lints/charter-lint.sh domains/home --fix

# Check all domains
for domain in domains/*/; do
  ./workspace/utilities/lints/charter-lint.sh "$domain"
done
```

**What it Checks**:
- Options defined outside `options.nix`
- Namespace alignment with folder structure
- HM configs in system domain
- System configs in home domain
- Missing VALIDATION sections
- Incorrect import patterns

### Build Validation

```bash
# Evaluate all configurations
nix flake check

# Build specific machine (dry-run)
nixos-rebuild build --flake .#hwc-laptop

# Test without activation
sudo nixos-rebuild test --flake .#hwc-laptop

# Apply changes
sudo nixos-rebuild switch --flake .#hwc-laptop
```

### Validation Anti-Patterns

**Searches that MUST return empty:**

```bash
# HM modules writing system packages (invalid)
rg "environment\.systemPackages" domains/home/

# System services in home domain (invalid)
rg "systemd\.services" domains/home/

# Home Manager activation in profiles (invalid, except profiles/home.nix)
rg "home-manager" profiles/ --exclude profiles/home.nix

# Hardcoded mount paths in domains (invalid)
rg "/mnt/" domains/

# writeScriptBin in home (should use parts/)
rg "writeScriptBin" domains/home/
```

---

## Anti-Patterns

### Structural Anti-Patterns

❌ **Defining options outside options.nix**
```nix
# BAD: in index.nix
options.hwc.home.apps.myapp.enable = lib.mkEnableOption "MyApp";

# GOOD: in options.nix
# domains/home/apps/myapp/options.nix
{ lib, ... }:
{
  options.hwc.home.apps.myapp.enable = lib.mkEnableOption "MyApp";
}
```

❌ **Cross-lane imports**
```nix
# BAD: home module importing system module
{ config, ... }:
{
  imports = [ ../../system/users/eric.nix ];  # WRONG!
}

# GOOD: use co-located sys.nix for system needs
# domains/home/apps/myapp/sys.nix provides system-lane config
```

❌ **Mixed domain concerns**
```nix
# BAD: User creation + shell config in same file
{
  users.users.eric = { ... };  # System domain
  programs.zsh = { ... };       # Home domain
}

# GOOD: Separate into domains/system/users/eric.nix and domains/home/apps/zsh/
```

❌ **HM activation in profiles**
```nix
# BAD: in profiles/system.nix
home-manager.users.eric = {
  imports = [ ... ];
};

# GOOD: Only in machines/<host>/home.nix
# Exception: profiles/home.nix is the HM feature menu
```

❌ **Namespace mismatch**
```nix
# BAD: File at domains/home/apps/firefox/options.nix
options.hwc.browser.firefox.enable = ...  # Wrong namespace!

# GOOD:
options.hwc.home.apps.firefox.enable = ...  # Matches folder path
```

### Implementation Anti-Patterns

❌ **Missing VALIDATION section**
```nix
# BAD: No dependency assertions
config = lib.mkIf enabled {
  # Uses hyprland but doesn't assert dependency
};

# GOOD:
config.assertions = lib.mkIf enabled [
  {
    assertion = config.hwc.home.apps.hyprland.enable;
    message = "waybar requires hyprland";
  }
];
```

❌ **Impure parts/ functions**
```nix
# BAD: parts/config.nix directly setting options
{ config, ... }:
{
  programs.firefox.enable = true;  # Side effect!
}

# GOOD: parts/ returns pure data
{ config, lib }:
let
  palette = config.hwc.home.theme.palette;
in
{
  background = palette.base00;  # Pure transformation
}
```

❌ **Hardcoded values instead of theme system**
```nix
# BAD:
background = "#1e1e2e";

# GOOD:
background = config.hwc.home.theme.palette.base00;
```

### Workflow Anti-Patterns

❌ **Skipping testing steps**
```bash
# BAD:
git commit -m "add feature"
git push

# GOOD:
nix flake check
sudo nixos-rebuild test --flake .#hwc-laptop
./workspace/utilities/lints/charter-lint.sh domains/home
nix flake check
git commit -m "feat(home.apps.myapp): add feature"
git push
```

❌ **Committing secrets**
```bash
# BAD:
git add domains/secrets/api-key.txt  # Unencrypted!

# GOOD:
echo "value" | age -r <pubkey> > domains/secrets/parts/api/key.age
git add domains/secrets/parts/api/key.age  # Encrypted .age only
```

---

## Quick Reference

### File Naming Conventions

- **Files/Directories**: `kebab-case.nix`, `my-module/`
- **Options**: `camelCase` following folder structure
  - `hwc.home.apps.firefox.enable`
  - `hwc.system.core.networking.hostname`
- **Scripts**: `domain-purpose` format
  - `waybar-gpu-status`
  - `system-backup-runner`

### Essential Commands

```bash
# Validation
nix flake check                              # Evaluate all configs
./workspace/utilities/lints/charter-lint.sh  # Charter compliance

# Building
sudo nixos-rebuild test --flake .#hwc-laptop   # Test without activation
sudo nixos-rebuild switch --flake .#hwc-laptop # Apply changes

# Development
nix develop                                  # Enter dev shell (if defined)
nix flake update                            # Update dependencies
nix flake show                              # Show flake outputs

# Secrets
sudo age-keygen -y /etc/age/keys.txt        # Get public key
age -r <pubkey> -e input > secret.age       # Encrypt
age -d -i /etc/age/keys.txt secret.age      # Decrypt

# Git
git log --oneline -10                       # Recent commits
git status                                  # Current state
```

### Namespace Pattern Examples

```
Folder Path                              → Option Namespace
─────────────────────────────────────────────────────────────────
domains/home/apps/firefox/               → hwc.home.apps.firefox.*
domains/system/core/networking/          → hwc.system.core.networking.*
domains/server/containers/caddy/         → hwc.server.containers.caddy.*
domains/infrastructure/hardware/gpu/     → hwc.infrastructure.hardware.gpu.*
```

### Profile Structure Template

```nix
# profiles/<domain>.nix
{ config, lib, pkgs, ... }:

{
  imports = [
    ../domains/<domain>/index.nix
    # ... other imports
  ];

  #==========================================================================
  # BASE - Critical for machine functionality
  #==========================================================================
  # Essential imports, base requirements

  #==========================================================================
  # OPTIONAL FEATURES - Sensible defaults, override per machine
  #==========================================================================
  hwc.<domain>.<module>.enable = lib.mkDefault true;
  # ... other feature toggles
}
```

### Machine Configuration Template

```nix
# machines/<host>/config.nix
{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware.nix           # Hardware-specific configuration
    ../../profiles/base.nix  # Base profile
    ../../profiles/system.nix
    # ... other profiles
  ];

  # Hardware facts
  networking.hostName = "hwc-<host>";

  # Machine-specific overrides
  hwc.system.core.networking.hostname = "hwc-<host>";

  # ... other machine-specific configuration
}
```

### Dependency Assertion Template

```nix
config.assertions = lib.mkIf enabled [
  {
    assertion = !enabled || config.hwc.dependency.enable;
    message = "module X requires dependency Y to be enabled";
  }
  {
    assertion = !enabled || (builtins.pathExists /path/to/required/file);
    message = "module X requires /path/to/required/file";
  }
];
```

---

## Working with This Repository - Best Practices

### Before Making Changes

1. **Read CHARTER.md** - It's the authoritative source
2. **Understand the domain** - Which domain(s) does this affect?
3. **Check existing patterns** - Look at similar modules for reference
4. **Verify current state** - `nix flake check` before starting

### During Development

1. **Follow module anatomy** - `options.nix`, `index.nix`, sections
2. **Maintain namespace alignment** - Folder path = option namespace
3. **Add validation** - Assert all dependencies in VALIDATION section
4. **Use parts/ for helpers** - Keep pure functions separate
5. **Test incrementally** - Don't accumulate untested changes

### Before Committing

1. **Run linter** - `./workspace/utilities/lints/charter-lint.sh`
2. **Test build** - `nix flake check`
3. **Test runtime** - `sudo nixos-rebuild test`
4. **Write clear commit** - Follow conventional commit format
5. **Check for secrets** - Never commit unencrypted secrets

### After Committing

1. **Push to feature branch** - Never directly to main
2. **Create PR** - Include summary, test plan, screenshots
3. **Wait for review** - Green CI + human review required
4. **Address feedback** - Iterate based on review

---

## Troubleshooting

### Build Failures

**Error**: "attribute 'X' missing"
- Check imports in profile
- Verify module is in domain aggregator (`index.nix`)
- Ensure namespace matches folder path

**Error**: "infinite recursion"
- Check for circular imports
- Verify no cross-lane imports (home ↔ system)
- Review dependency chain in profiles

**Error**: "assertion failed"
- Read assertion message
- Enable required dependency
- Or disable the dependent module

### Linter Failures

**Error**: "options defined outside options.nix"
- Move option definitions to `options.nix`
- Never define options ad-hoc in `index.nix`

**Error**: "namespace mismatch"
- Rename option to match folder path
- `domains/home/apps/X/` → `hwc.home.apps.X.*`

**Error**: "missing VALIDATION section"
- Add `# VALIDATION` section to `index.nix`
- Include dependency assertions

### Runtime Issues

**Symptom**: Service not starting
- Check `systemctl status <service>`
- Review dependency assertions
- Verify service user has `secrets` group if needed

**Symptom**: Configuration not applying
- Ensure module is enabled in machine config
- Check profile imports
- Verify Home Manager activation (for HM modules)

**Symptom**: Permission denied on secrets
- Check `group = "secrets"; mode = "0440"`
- Add user to `extraGroups = [ "secrets" ]`
- Verify age key exists: `sudo ls /etc/age/keys.txt`

### Permission Issues

**Common permission errors and resolutions:**

1. **Container Permission Denied**
   - Symptom: Container can't write to volumes
   - Cause: Wrong PGID (1000 instead of 100)
   - Fix: See `docs/troubleshooting/permissions.md` section 1

2. **StateDirectory Access Denied**
   - Symptom: Service can't write to /var/lib/hwc/<service>
   - Cause: Missing User/Group in serviceConfig
   - Fix: See `docs/troubleshooting/permissions.md` section 2

3. **Secret File Not Readable**
   - Symptom: Service can't access /run/agenix/<secret>
   - Cause: Service user not in secrets group
   - Fix: See `docs/troubleshooting/permissions.md` section 3

4. **HOME is "/" on SSH Login**
   - Symptom: SSH login shows HOME=/ instead of /home/eric
   - Cause: NixOS 26.05 HOME variable issue (already fixed)
   - Fix: Rebuild system if still broken

**Diagnostic Tools**:
```bash
# Run permission linter
./workspace/utilities/lints/permission-lint.sh domains/server

# Check service user configuration
systemctl show <service> | grep -E 'User=|Group='

# Verify container PGID
sudo podman inspect <container> | jq '.[0].Config.Env'

# Check for GID=1000 files (should be none)
find /mnt/hot /mnt/media -group 1000 2>/dev/null | wc -l
```

**Full Guide**: `docs/troubleshooting/permissions.md`
**Standard Patterns**: `docs/standards/permission-patterns.md`

---

## Additional Resources

### Documentation Files

- `CHARTER.md` - Primary architectural authority
- `FILESYSTEM_CHARTER.md` - Home directory organization
- `AGENTS.md` - Repository agent guidelines
- `workspace/utilities/lints/README.md` - Linter documentation
- `docs/infrastructure/` - Infrastructure documentation
- `docs/deployment/` - Deployment guides

### Useful Commands Reference

```bash
# Find all modules with enable options
rg "mkEnableOption" domains/ -l

# Find where a module is imported
rg "domains/home/apps/firefox" .

# Check namespace usage
./workspace/utilities/lints/analyze-namespace.sh domains/home

# Quick anatomy check
./workspace/utilities/lints/quick-anatomy.sh domains/home/apps/firefox

# Add section headers to module
./workspace/utilities/lints/add-section-headers.sh domains/home/apps/myapp/index.nix
```

### External References

- [Nix Manual](https://nixos.org/manual/nix/stable/)
- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [Nix Pills](https://nixos.org/guides/nix-pills/) - Deep dive into Nix

---

## Checklist for AI Assistants

When working on this repository, ensure you:

- [ ] Have read and understood `CHARTER.md`
- [ ] Understand which domain(s) the task affects
- [ ] Know the correct namespace for new options
- [ ] Will create `options.nix` for any new modules
- [ ] Will include all three sections: OPTIONS, IMPLEMENTATION, VALIDATION
- [ ] Will add dependency assertions in VALIDATION
- [ ] Will maintain lane purity (no cross-lane imports)
- [ ] Will test with `nix flake check` before committing
- [ ] Will run charter-lint on affected domains
- [ ] Will use conventional commit format matching namespace
- [ ] Will never commit unencrypted secrets
- [ ] Will preserve existing functionality during refactors

---

**Version History:**

- v1.0 (2025-11-18): Initial comprehensive guide for AI assistants

**Maintained by**: Eric (with AI assistance)
**Questions**: Refer to `CHARTER.md` for authoritative answers
