# CHARTER v8 Audit Tooling

Comprehensive drift detection and compliance linting for the nixos-hwc repository.

## Overview

This audit suite enforces CHARTER v8 architectural rules through two complementary tools:

- **`lint.sh`**: Fast fail-gate for hard blocker violations (exits non-zero on failure)
- **`drift.py`**: Comprehensive drift analysis for architectural issues (report-only)

Both tools use CHARTER rules as the single source of truth and respect structural file constraints (no automated rewrites).

## Quick Start

```bash
# Run linter (fail-fast gate)
./scripts/audit/lint.sh

# Run drift analyzer (comprehensive report)
./scripts/audit/drift.py

# Via flake
nix flake check          # Runs lint.sh automatically
nix run .#lint           # Run linter
nix run .#drift          # Run drift analyzer

# Check specific path
./scripts/audit/lint.sh domains/home
./scripts/audit/drift.py profiles
```

## Output Format

Both tools use standardized output:

```
CATEGORY | SEVERITY | FILE:LINE | MESSAGE
```

**Severity Levels:**
- `HIGH`: CHARTER hard blocker, must fix
- `MED`: Strong architectural drift, should fix
- `LOW`: Minor issue, consider fixing
- `SUGGESTION`: Naming/style drift, optional improvement

## Linter Categories (lint.sh)

### 1. OPTIONS_PLACEMENT (HIGH)
**Rule**: Options must only be defined in `options.nix` files (CHARTER §4, §14)

**Violation Example:**
```nix
# domains/home/apps/firefox/index.nix ❌
options.hwc.home.apps.firefox.enable = lib.mkEnableOption "Firefox";
```

**Fix:**
```nix
# domains/home/apps/firefox/options.nix ✅
{ lib, ... }:
{
  options.hwc.home.apps.firefox.enable = lib.mkEnableOption "Firefox";
}
```

**Remediation:**
1. Create `options.nix` in the module directory if missing
2. Move all `options.*` definitions to `options.nix`
3. Import `options.nix` in `index.nix` under `# OPTIONS` section

---

### 2. NAMESPACE_MISMATCH (HIGH)
**Rule**: Namespace must match folder structure (CHARTER §1, §4, §12)

**Pattern**: `domains/home/apps/firefox/` → `hwc.home.apps.firefox.*`

**Violation Example:**
```nix
# File: domains/home/apps/firefox/options.nix
options.hwc.browser.firefox.enable = ...  # ❌ Wrong namespace
```

**Fix:**
```nix
# File: domains/home/apps/firefox/options.nix
options.hwc.home.apps.firefox.enable = ...  # ✅ Matches folder path
```

**Remediation:**
1. Extract domain path from folder: `domains/<domain>/<category>/<module>/`
2. Construct namespace: `hwc.<domain>.<category>.<module>.*`
3. Rename all options to match namespace
4. Update references throughout codebase

---

### 3. HM_IN_PROFILES (HIGH)
**Rule**: Home Manager activation only in `machines/<host>/home.nix` and `profiles/home.nix` (menu only) (CHARTER §8, §14)

**Violation Example:**
```nix
# profiles/system.nix ❌
home-manager.users.eric = {
  imports = [ ... ];
};
```

**Fix:**
```nix
# machines/laptop/home.nix ✅
{ config, ... }:
{
  home-manager.users.eric = {
    imports = [
      ../../domains/home/apps/hyprland
      ../../domains/home/apps/waybar
    ];
  };
}
```

**Remediation:**
1. Remove `home-manager.users.*` from profiles (except `profiles/home.nix` feature menu)
2. Move to machine-specific `machines/<host>/home.nix`
3. Keep `profiles/home.nix` as feature menu (imports only, no activation)

---

### 4. MIXED_DOMAIN (HIGH)
**Rule**: Domains must not mix system and home concerns (CHARTER §3, §14)

**Violation Example:**
```nix
# domains/system/core/networking.nix ❌
{
  networking.hostName = "hwc-laptop";
  programs.firefox.enable = true;  # HM config in system domain
}
```

**Fix:**
```nix
# domains/system/core/networking.nix ✅
{
  networking.hostName = "hwc-laptop";
}

# domains/home/apps/firefox/index.nix ✅
{
  programs.firefox.enable = true;
}
```

**Remediation:**
1. Identify mixed concerns (system + HM in same file)
2. Extract HM configs (`programs.*`, `home.*`, `xdg.*`) to `domains/home/`
3. Keep system configs (`users.*`, `networking.*`, `services.*`) in `domains/system/`
4. User account definitions belong in `domains/system/users/`

---

### 5. HOME_ANTIPATTERN (HIGH)
**Rule**: Home domain must not contain system-lane configurations (CHARTER §14)

**Violations:**
- `systemd.services.*` in `domains/home/`
- `environment.systemPackages` in `domains/home/`
- `writeScriptBin` in `domains/home/` (should use `parts/`)

**Fix Pattern for writeScriptBin:**
```nix
# domains/home/apps/waybar/index.nix ❌
let
  myScript = pkgs.writeScriptBin "my-script" ''
    #!/bin/bash
    echo "hello"
  '';
in { ... }

# domains/home/apps/waybar/parts/scripts.nix ✅
{ pkgs, lib }:
{
  myScript = pkgs.writeScriptBin "my-script" ''
    #!/bin/bash
    echo "hello"
  '';
}

# domains/home/apps/waybar/index.nix ✅
let
  scripts = import ./parts/scripts.nix { inherit pkgs lib; };
in {
  home.packages = [ scripts.myScript ];
}
```

**Remediation:**
1. Move scripts to `parts/scripts.nix` as pure functions
2. Import and use in `index.nix`
3. For system packages needed by home app, use co-located `sys.nix`

---

### 6. HARDCODED_PATH (HIGH)
**Rule**: No hardcoded `/mnt/` paths in domains (CHARTER §14)

**Violation Example:**
```nix
# domains/server/jellyfin/index.nix ❌
volumes = [
  "/mnt/media/movies:/data/movies:ro"
];
```

**Fix:**
```nix
# domains/infrastructure/storage/index.nix ✅
config.hwc.infrastructure.storage.media = "/mnt/media";

# domains/server/jellyfin/index.nix ✅
volumes = [
  "${config.hwc.infrastructure.storage.media}/movies:/data/movies:ro"
];
```

**Remediation:**
1. Define paths in `domains/infrastructure/storage/`
2. Reference via `config.hwc.infrastructure.storage.*`
3. Keep filesystem structure centralized and configurable

---

### 7. FLOATING_TAG (HIGH/MED)
**Rule**: Container images must be pinned to specific versions

**Violation Example:**
```nix
# ❌ Floating tag
image = "ghcr.io/linuxserver/jellyfin:latest";

# ❌ No version specified
image = "redis";
```

**Fix:**
```nix
# ✅ Pinned version
image = "ghcr.io/linuxserver/jellyfin:10.8.13";

# ✅ Digest pinning (best)
image = "redis@sha256:abc123...";
```

**Remediation:**
1. Replace `:latest` with specific version tag
2. Document version in module comments
3. Consider digest pinning for critical services
4. Update regularly but explicitly

---

## Drift Categories (drift.py)

### Category 1: MISPLACED_SCOPE
**Issues:**
- Service implementations in profiles (should be in domains)
- Container definitions in profiles (should be in `domains/server`)
- Large config blocks in machines (should be extracted to modules)

**Example Finding:**
```
MISPLACED_SCOPE | HIGH | profiles/server.nix:42 | systemd service implementation in profile (profiles are menus, not implementation) (CHARTER §3)
```

**Remediation:**
1. Move service implementations from profiles to appropriate domain modules
2. Keep profiles as feature menus (imports + toggles only)
3. Extract large machine configs to domain modules
4. Machines should be composition + hardware facts only

**Profile Structure:**
```nix
# profiles/server.nix ✅
{
  imports = [
    ../domains/server/jellyfin
    ../domains/server/monitoring
  ];

  #==========================================================================
  # BASE - Critical for machine functionality
  #==========================================================================
  # Essential imports

  #==========================================================================
  # OPTIONAL FEATURES - Sensible defaults, override per machine
  #==========================================================================
  hwc.server.jellyfin.enable = lib.mkDefault true;
}
```

---

### Category 2: REDUNDANCY (DUP_*)
**Issues:**
- Multiple writers to same resource (ports, containers, paths)
- Violates single source of truth principle (CHARTER §13)

**Example Finding:**
```
DUP_PORT | HIGH | PORT=8081 | 3 occurrences
  → domains/server/jellyfin/index.nix:42
  → domains/server/monitoring/grafana/index.nix:28
  → machines/server/config.nix:15
```

**Remediation:**
1. **Port conflicts**: Assign unique ports to each service, document port allocations
2. **Container name conflicts**: Ensure container names are unique across repository
3. **Path conflicts**: Consolidate to single canonical definition

**Port Allocation Strategy:**
```nix
# Create docs/infrastructure/port-allocations.md
# Document all port assignments:
# 8096 - Jellyfin
# 8080 - Caddy
# 3000 - Grafana
# etc.

# Then ensure each service uses its assigned port
```

---

### Category 3: MODULE_ANATOMY
**Issues:**
- Missing required files (`options.nix`)
- Missing section markers (`# OPTIONS`, `# IMPLEMENTATION`, `# VALIDATION`)
- Impure `parts/` functions (options or config assignments)

**Example Finding:**
```
MODULE_ANATOMY | HIGH | domains/home/apps/myapp | Missing required options.nix (CHARTER §4)
```

**Required Module Structure:**
```
domains/<domain>/<category>/<module>/
├── options.nix         # MANDATORY: API definition
├── index.nix           # MANDATORY: Implementation aggregator
├── sys.nix             # OPTIONAL: System-lane co-located config
└── parts/              # OPTIONAL: Pure helper functions
    ├── config.nix
    ├── theme.nix
    └── scripts.nix
```

**index.nix Template:**
```nix
{ config, lib, pkgs, ... }:

let
  enabled = config.hwc.<domain>.<category>.<module>.enable or false;
  cfg = config.hwc.<domain>.<category>.<module>;
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
    # Module implementation
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  config.assertions = lib.mkIf enabled [
    {
      assertion = !enabled || <dependency-check>;
      message = "module requires dependency";
    }
  ];
}
```

**Remediation:**
1. Create missing `options.nix` files
2. Add section markers to `index.nix`
3. Add `# VALIDATION` section with dependency assertions
4. Ensure `parts/` files are pure (no options, no config assignments)

---

### Category 4: NAMING_DRIFT
**Issues:**
- Vague option names (`port`, `dir`, `path`, `config`, `data`)
- Inconsistent patterns across modules (`dataDir` vs `stateDir` vs `configDir`)

**Example Finding:**
```
NAMING_DRIFT | SUGGESTION | domains/home/apps/myapp/options.nix:12 | Vague option name 'port' (consider more specific: webPort, apiPort, etc.)
```

**Remediation (Suggested Standards):**
```nix
# ❌ Vague
port = lib.mkOption { ... };
dir = lib.mkOption { ... };

# ✅ Specific
webPort = lib.mkOption { ... };
apiPort = lib.mkOption { ... };
stateDir = lib.mkOption { ... };      # State directory (e.g., /var/lib/service)
configDir = lib.mkOption { ... };     # Config directory (e.g., /etc/service)
dataDir = lib.mkOption { ... };       # Data directory (e.g., /srv/service)
```

**Consistency:**
- Choose one pattern and stick to it (recommend `stateDir`, `configDir`, `dataDir`)
- Document standard in CHARTER or separate style guide
- This is SUGGESTION level - not blocking, but improves maintainability

---

### Category 5: SYS_COUPLING
**Issues:**
- `sys.nix` referencing `config.hwc.home.*` options (wrong evaluation order)
- `sys.nix` with conditional logic but no `hwc.system.*` options

**Example Finding:**
```
SYS_COUPLING | HIGH | domains/home/apps/hyprland/sys.nix:15 | sys.nix references config.hwc.home.* (system evaluates before HM) (CHARTER §6)
```

**sys.nix Architecture Pattern:**

System lane evaluates BEFORE Home Manager, so `sys.nix` cannot depend on `hwc.home.*` options.

**Correct Pattern:**
```nix
# domains/home/apps/hyprland/sys.nix ✅
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.system.apps.hyprland;  # System-lane option
in
{
  # OPTIONS - System-lane API
  options.hwc.system.apps.hyprland = {
    enable = lib.mkEnableOption "Hyprland system dependencies";
  };

  # IMPLEMENTATION - Conditional on system-lane option
  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      hyprland
      xdg-desktop-portal-hyprland
    ];

    programs.hyprland.enable = true;
  };
}
```

**Machine Configuration (both lanes):**
```nix
# machines/laptop/config.nix
{
  hwc.system.apps.hyprland.enable = true;  # System lane
}

# machines/laptop/home.nix (via profiles/home.nix)
{
  hwc.home.apps.hyprland.enable = true;    # Home lane
}
```

**Cross-Lane Validation:**
```nix
# domains/home/apps/hyprland/index.nix
{ config, osConfig, ... }:  # Note: osConfig to access system config
{
  config.assertions = [
    {
      # Home can check system (system evaluates first)
      assertion = !enabled || (osConfig.hwc.system.apps.hyprland.enable or false);
      message = "hwc.home.apps.hyprland requires hwc.system.apps.hyprland";
    }
  ];
}
```

**Remediation:**
1. Never reference `config.hwc.home.*` in `sys.nix`
2. Define `hwc.system.*` options in `sys.nix` for system-lane API
3. Enable both lanes independently in machine config
4. Use `osConfig` in home modules to validate system-lane dependencies

---

### Category 6: PROFILE_STRUCTURE
**Issues:**
- Profiles missing `# BASE` and `# OPTIONAL FEATURES` section markers

**Example Finding:**
```
PROFILE_STRUCTURE | MED | profiles/server.nix | Profile missing BASE/OPTIONAL FEATURES sections (CHARTER §2)
```

**Remediation:**
```nix
# profiles/server.nix ✅
{ config, lib, pkgs, ... }:

{
  imports = [
    ../domains/server/index.nix
    # ... other imports
  ];

  #==========================================================================
  # BASE - Critical for machine functionality
  #==========================================================================
  # Essential services that machine requires to function
  # - User accounts
  # - Network configuration
  # - Critical system services

  #==========================================================================
  # OPTIONAL FEATURES - Sensible defaults, override per machine
  #==========================================================================
  hwc.server.jellyfin.enable = lib.mkDefault true;
  hwc.server.monitoring.enable = lib.mkDefault true;
}
```

**BASE vs OPTIONAL Determination:**
- **BASE**: Required for basic machine operation (boot, management, auth, networking)
- **OPTIONAL**: Features that can be toggled per machine (applications, services)

---

## Integration with Development Workflow

### Pre-Commit Check
```bash
# Before committing
./scripts/audit/lint.sh || exit 1
```

### CI/CD Integration
```bash
# In CI pipeline
nix flake check  # Automatically runs lint.sh
```

### Development Flow
```bash
# 1. Make changes
vim domains/home/apps/myapp/index.nix

# 2. Run linter
./scripts/audit/lint.sh domains/home/apps/myapp

# 3. Fix violations
# ... fix issues ...

# 4. Run drift analysis (optional, for deeper review)
./scripts/audit/drift.py

# 5. Verify fixes
./scripts/audit/lint.sh

# 6. Test build
nix flake check

# 7. Commit
git commit -m "feat(home.apps.myapp): add feature"
```

---

## Common Remediation Workflows

### Workflow 1: Fixing Options Placement
```bash
# 1. Find violations
./scripts/audit/lint.sh domains/home/apps/firefox | grep OPTIONS_PLACEMENT

# 2. Create options.nix
cat > domains/home/apps/firefox/options.nix <<'EOF'
{ lib, ... }:
{
  options.hwc.home.apps.firefox = {
    enable = lib.mkEnableOption "Firefox browser";
    # ... other options
  };
}
EOF

# 3. Remove options from index.nix, add import
# Edit index.nix:
#   - Remove options.* definitions
#   - Add: imports = [ ./options.nix ];

# 4. Verify
./scripts/audit/lint.sh domains/home/apps/firefox
```

### Workflow 2: Fixing Namespace Mismatch
```bash
# 1. Identify mismatch
./scripts/audit/lint.sh domains/home/apps/firefox | grep NAMESPACE

# Expected: hwc.home.apps.firefox
# Actual: hwc.browser.firefox

# 2. Update options.nix
# Change: options.hwc.browser.firefox → options.hwc.home.apps.firefox

# 3. Update all references
rg "hwc\.browser\.firefox" . --files-with-matches | xargs sed -i 's/hwc\.browser\.firefox/hwc.home.apps.firefox/g'

# 4. Verify
./scripts/audit/lint.sh domains/home/apps/firefox
nix flake check
```

### Workflow 3: Extracting Mixed Domains
```bash
# 1. Identify mixed concerns
./scripts/audit/lint.sh domains/system/users/eric.nix | grep MIXED_DOMAIN

# Found: programs.zsh in system/users/eric.nix

# 2. Create home module
mkdir -p domains/home/apps/zsh
# Create options.nix, index.nix with zsh config

# 3. Remove from system module
# Edit domains/system/users/eric.nix, remove programs.zsh

# 4. Add to home activation
# Edit machines/laptop/home.nix, add: ../../domains/home/apps/zsh

# 5. Verify
./scripts/audit/lint.sh
nix flake check
```

---

## Reference: CHARTER Sections

- **§1**: Core Architectural Concepts (namespace mapping)
- **§2**: Core Layering & Flow (profile pattern)
- **§3**: Domain Boundaries & Responsibilities
- **§4**: Unit Anatomy (required files)
- **§6**: Lane Purity (sys.nix architecture)
- **§8**: Home Manager Boundary
- **§9**: Structural Rules
- **§11**: Helpers & Parts (purity requirements)
- **§12**: File Standards (naming, sections)
- **§13**: Enforcement Rules (single source of truth)
- **§14**: Validation & Anti-Patterns
- **§20**: Configuration Validity (assertions)

---

## Maintenance

### When CHARTER Changes
1. Update relevant checks in `lint.sh` and `drift.py`
2. Add new categories if needed
3. Update this README with examples
4. Bump CHARTER version reference in script headers
5. Test on existing codebase: `./scripts/audit/lint.sh && ./scripts/audit/drift.py`

### Adding New Checks
1. Determine if it's a hard blocker (lint.sh) or drift (drift.py)
2. Add check function following existing pattern
3. Add to execution section
4. Document in this README with examples
5. Reference CHARTER section(s)
6. Test against known violations

---

## Troubleshooting

### Linter False Positives
If linter reports false positives:
1. Check if the code actually violates CHARTER
2. If legitimate exception, document in CHARTER
3. Update linter logic to handle exception
4. Add test case

### Drift Report Overwhelming
If drift.py produces too many suggestions:
1. Focus on HIGH severity first
2. Then MED severity
3. SUGGESTION level is optional (style/consistency)
4. Create issues/tasks for gradual remediation

### Integration Issues
If flake check fails:
```bash
# Run linter directly to see detailed output
./scripts/audit/lint.sh

# Check specific domain
./scripts/audit/lint.sh domains/home

# Verify flake syntax
nix flake check --show-trace
```

---

**Audit Suite Version**: 1.0.0 (CHARTER v8 compliant)

**Maintained by**: Eric (with AI assistance)

**Questions**: Refer to `CHARTER.md` for authoritative architectural rules
