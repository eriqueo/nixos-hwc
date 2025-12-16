# HWC Architecture Charter

**Owner**: Eric
**Scope**: `nixos-hwc/` — all machines, domains, profiles, HM, and supporting files
**Goal**: Deterministic, maintainable, scalable, and reproducible NixOS via strict domain separation, explicit APIs, predictable patterns, and user-centric organization.

---

## 0) Preserve-First Doctrine

* **Refactor = reorganize, not rewrite**.
* 100% feature parity during migrations.
* Wrappers/adapters allowed only as temporary bridges (tracked & removed).
* Never switch on red builds.

---

## 1) Core Architectural Concepts

### **Domains**
- **Definition**: A folder of modules organized around a common interaction boundary (how they talk to the system), where each module handles one logical concern and follows the namespace pattern of its folder path
- **Purpose**: Clear separation of concerns based on system interaction boundaries
- **Location**: `domains/` folder
- **Namespace Rule**: `domains/home/apps/firefox/` → `hwc.home.apps.firefox.*`
- **Debugging**: Direct folder-to-namespace mapping for immediate error traceability

**Namespace exceptions (documented, temporary)**:
- `hwc.filesystem` (short for `hwc.system.core.filesystem`)
- `hwc.networking` (short for `hwc.system.services.networking`)
- `hwc.home.fonts` (short for `hwc.home.theme.fonts`)
- Legacy alias: `hwc.services.containers.*` → `hwc.server.containers.*` (compat shim present; use new namespace)

### **Modules**
- **Definition**: A single logical concern that provides one place to configure all aspects of that concern
- **Purpose**: "One place per concern" - all hyprland config, all user config, etc. lives in one logical location
- **Example**: `domains/home/apps/firefox/` contains everything firefox-related

### **Profiles**
- **Definition**: Domain-specific feature menus that aggregate modules to serve machine composition purposes
- **Structure**: Two clear sections per profile:
  - **BASE**: Required imports/options for domain functionality (won't boot/breaks without)
  - **OPTIONAL FEATURES**: Sensible defaults that can be overridden per machine
- **Types**: `system.nix`, `home.nix`, `infrastructure.nix`, `server.nix`
- **Machine Composition**: Machines import combination of domain profiles needed

### **Profile Pattern**
Each domain profile follows this structure:
```nix
# profiles/system.nix
{
  #==========================================================================
  # BASE SYSTEM - Critical for machine functionality  
  #==========================================================================
  # Essential imports, users, permissions, secrets, networking
  
  #==========================================================================
  # OPTIONAL FEATURES - Sensible defaults, override per machine
  #==========================================================================
  # Development tools, media packages, security levels, etc.
}
```

**Base Determination**: Anything required for basic machine operation - boot, management, permissions, authentication.

---

## 2) Core Layering & Flow

**NixOS system flow**
`flake.nix` → `machines/<host>/config.nix` → `profiles/*` → `domains/{system,infrastructure,server}/`

**Home Manager flow**
`machines/<host>/home.nix` → `domains/home/`

**Machine Composition Flow**
```
profiles/system.nix → domains/system/*
profiles/home.nix → domains/home/*
profiles/infrastructure.nix → domains/infrastructure/*
profiles/server.nix → domains/server/*
         ↓
machines/laptop/config.nix imports needed profiles
```

**Rules**

* Modules **implement** capabilities behind `options.nix`.
* Profiles **provide domain feature menus with base/optional structure**.
* Machines **declare hardware facts and import needed domain profiles**.
* **No cycles**: dependency direction is always downward.
* Home Manager lives at machine level, not profile level.

---

## 3) Domain Boundaries & Responsibilities

| Domain             | Purpose                          | Location                  | Must Contain                                                       | Must Not Contain                             |
| ------------------ | -------------------------------- | ------------------------- | ------------------------------------------------------------------ | -------------------------------------------- |
| **Infrastructure** | Hardware mgmt + cross-domain orchestration | `domains/infrastructure/` | GPU, power, udev, virtualization, filesystem structure             | HM configs                                   |
| **System**         | Core OS + accounts + OS services | `domains/system/`         | users, sudo, networking, security, paths, system packages          | HM configs, secret declarations              |
| **Secrets**        | Encrypted secrets via agenix     | `domains/secrets/`        | age declarations, secret API, emergency access, hardening          | Secret values (only encrypted .age files)    |
| **Server**         | Host-provided workloads          | `domains/server/`         | containers, reverse proxy, databases, media stacks, monitoring     | HM configs                                   |
| **Home**           | User environment (HM)            | `domains/home/`           | `programs.*`, `home.*`, DE/WM configs, shells                      | systemd.services, environment.systemPackages |
| **Profiles**       | Domain feature menus             | `profiles/`               | domain imports, base/optional toggles                              | HM activation (except hm.nix), implementation |
| **Machines**       | Hardware facts + profile composition | `machines/<host>/`        | `config.nix`, `home.nix`, storage, GPU type                        | Shared logic, profile-like orchestration     |

**Key Principles**

* User accounts → `domains/system/users/eric.nix`
* User env → `domains/home/` imported by `machines/<host>/home.nix`
* Secrets → `domains/secrets/` with stable API facade at `/run/agenix`
  - **Permission Model**: All secrets use `group = "secrets"; mode = "0440"` for shared access
  - **Service Access**: All service users must include `extraGroups = [ "secrets" ]`
  - **Age Key Management**: `sudo age-keygen -y /etc/age/keys.txt` for public key
  - **Secret Updates**: `echo "value" | age -r <pubkey> > domains/secrets/parts/domain/name.age`
  - **Verification**: `sudo age -d -i /etc/age/keys.txt path/to/secret.age`
* Cross-domain orchestrators → `domains/infrastructure/` (filesystem structure, etc.)
* Namespace follows folder structure: `domains/home/apps/firefox/` → `hwc.home.apps.firefox.*`

---

## 4) Unit Anatomy

Every **module** (app, tool, or workload) MUST include:

* `index.nix` → aggregator, imports options.nix, implements functionality
* `options.nix` → mandatory, API definition following folder→namespace pattern
* `sys.nix` → system-lane implementation, co-located but imported only by system profiles
* `parts/**` → pure functions, no options, no side-effects

**Rules**
* `options.nix` always exists - options never defined ad hoc in other files
* Namespace matches folder structure: `domains/home/apps/firefox/options.nix` defines `hwc.home.apps.firefox.*`
* One logical concern per module directory

---

## 5) Permission Model

### Overview

The nixos-hwc system uses a **unified permission model** optimized for single-user infrastructure:

**Core Principle**: All services run as `eric:users` (UID 1000, GID 100)

This simplifies management in a personal environment where service isolation is achieved through directory structure rather than user separation.

### Standard UID/GID Assignments

| Entity | UID | GID | Purpose |
|--------|-----|-----|---------|
| eric (user) | 1000 | - | Primary system user |
| users (group) | - | 100 | Primary user group |
| secrets (group) | - | (dynamic) | Secret access control |
| root | 0 | 0 | System administration |

**CRITICAL**: The `users` group is GID **100**, not 1000!

### Container Configuration Standard

All containers MUST use:
```nix
environment = {
  PUID = "1000";  # eric user
  PGID = "100";   # users group (NOT 1000!)
  TZ = config.time.timeZone;
};
```

**Rationale**: Containers create files as the user/group specified by PUID/PGID. Using GID 100 ensures files are owned by `eric:users`, allowing direct access without permission corrections.

### Service Configuration Standard

Native NixOS services should override default user creation:
```nix
systemd.services.<service> = {
  serviceConfig = {
    User = lib.mkForce "eric";
    Group = lib.mkForce "users";
    StateDirectory = "hwc/<service>";
  };
};
```

### Secret Access Pattern

All secrets use restrictive permissions with group-based access:
```nix
age.secrets.<name> = {
  file = ../../parts/<domain>/<name>.age;
  mode = "0440";   # Read-only for owner + group
  owner = "root";
  group = "secrets";
};
```

### Validation Requirements

All modules implementing services MUST:

1. **Document Permission Model**: Add comment explaining why service runs as eric
2. **Validate Dependencies**: Assert user configuration in VALIDATION section
3. **Use Standard Patterns**: Follow `docs/standards/permission-patterns.md`
4. **Pass Linter**: Validate with `./workspace/utilities/lints/permission-lint.sh`

### Reference Documentation

- **Standard Patterns**: `docs/standards/permission-patterns.md`
- **Troubleshooting**: `docs/troubleshooting/permissions.md`
- **Validation Linter**: `workspace/utilities/lints/permission-lint.sh`

---

## 6) Lane Purity

* **Lanes never import each other's `index.nix`**.
* Co-located `sys.nix` belongs to the **system lane**, even when inside `domains/home/apps/<unit>`.
* **Examples of valid sys.nix content**:
  - `domains/home/apps/kitty/sys.nix` → `environment.systemPackages = [ pkgs.kitty-themes ];`
  - `domains/home/apps/firefox/sys.nix` → `programs.firefox.policies = { ... };`
  - This is system-lane code imported by system profiles, **not HM boundary violations**.
* Profiles decide which lane's files to import.

### sys.nix Architecture Pattern

**Problem**: System lane evaluates BEFORE Home Manager, so `sys.nix` files cannot depend on `hwc.home.apps.*.enable` options.

**Solution**: `sys.nix` files must define their own system-lane options in `hwc.system.apps.*` namespace.

**Example** (`domains/home/apps/hyprland/sys.nix`):

```nix
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
  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      environment.systemPackages = [ /* ... */ ];
    })
    {} # Placeholder for unconditional config if needed
  ];
}
```

**Machine Configuration** (both lanes must be enabled):

```nix
# machines/laptop/config.nix
{
  hwc.system.apps.hyprland.enable = true;  # System lane
  # Home lane enabled via profiles/home.nix
}
```

**Cross-Lane Validation** (in home module's `index.nix`):

```nix
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

**Key Rules**:
- System cannot validate home-lane (evaluation order)
- Home CAN validate system-lane using `osConfig`
- Both lanes independently toggled in machine config
- No implicit coupling via `lib.attrByPath` fallbacks

---

## 7) Aggregators

* Aggregators are always named **`index.nix`**.
* Module aggregators = `domains/home/apps/waybar/index.nix`.
* Domain aggregators = `domains/home/index.nix`, `domains/server/index.nix`.
* Profiles may import domain aggregators and individual module indices.

---

## 8) Home Manager Boundary

* **HM activation is machine-specific, never in profiles.**
* **Exception**: `profiles/home.nix` serves as the Home Manager domain feature menu
* Example (`machines/laptop/home.nix`):

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

---

## 9) Structural Rules

* **Structural files** = all `.nix` sources under `domains/`, `profiles/`, `machines/` and `flake.{nix,lock}`.
* Never apply automated regex rewrites to structural files.
* Generated artifacts (systemd units, container manifests) are not structural.

---

## 10) Theming

* Palettes (`domains/home/theme/palettes/*.nix`) define tokens.
* Adapters (`domains/home/theme/adapters/*.nix`) transform palettes to app configs.
* No hardcoded colors in app configs.

---

## 11) Helpers & Parts

* `parts/**` and `_shared/**` MUST be pure helpers:

  * No options
  * No side effects
  * No direct system mutation

---

## 12) File Standards

* Files/dirs: `kebab-case.nix`
* Options: camelCase following folder structure (e.g. `hwc.home.apps.firefox.enable`)
* Scripts: `domain-purpose` (e.g. `waybar-gpu-status`)
* All modules include: **OPTIONS / IMPLEMENTATION / VALIDATION** sections
* Namespace matches folder: `domains/home/apps/firefox/` → `hwc.home.apps.firefox.*`

---

## 13) Enforcement Rules

* Functional purity per domain.
* Single source of truth.
* No multiple writers to same path.
* Profiles provide feature menus, machines compose profiles.
* One logical concern per module directory.
* Namespace follows folder structure for debugging.

---

## 14) Validation & Anti-Patterns

**Searches (must be empty):**

```bash
rg "writeScriptBin" domains/home/
rg "systemd\.services" domains/home/
rg "environment\.systemPackages" domains/home/
rg "home-manager" profiles/ --exclude profiles/home.nix
rg "/mnt/" domains/
```

**Hard blockers**

* HM activation in profiles (except profiles/home.nix domain menu)
* NixOS modules in HM
* HM modules in system/server
* User creation outside `domains/system/users/`
* Mixed-domain modules (e.g., `users.users` + `programs.zsh`)
* Options defined outside `options.nix` files
* Namespace not matching folder structure

---

## 15) Server Workloads

### Container vs Native Service Decisions

* **Native Services**: Use for external device connectivity (media servers, game servers)
  - Media services requiring LAN device access (Jellyfin for Roku/smart TVs)
  - Services with complex network discovery requirements
  - Example: `services.jellyfin.enable = true` instead of `hwc.server.containers.jellyfin.enable`

* **Containers**: Use for internal services, isolated workloads
  - API services, databases, processing workloads
  - Services without external device connectivity requirements
  - Better security isolation for untrusted workloads

### Container Architecture Rules

* Reverse proxy authority is central in `domains/server/containers/caddy/`.
* When host-level Caddy aggregator is enabled, containerized proxy units MUST be disabled.
* Per-unit container state defaults to `/opt/<category>/<unit>:/config`. Override only for ephemeral workloads, host storage policy, or multiple instances.
* Container networks create routing barriers - external devices may not reach containerized services despite proper port mapping.

---

## 16) Profiles & Import Order

* Profiles MUST import `options.nix` before any lane implementations.
* Example:

```nix
imports = [
  ../domains/system/index.nix
  ../domains/server/index.nix
] ++ (gatherSys ../domains/home/apps);
```

---

## 17) Migration Protocol

1. **Discovery** → list features.
2. **Classification** → Part / Adapter / Tool.
3. **Relocation** → Parts & adapters → Home, Tools → Infra.
4. **Interface** → canonical tool names only.
5. **Validation** → build-only → smoke → switch.

---

## 18) Status

* Phase 1 (Domain separation): ✅ complete.
* Phase 2 (Domain/Profile architecture): 🔄 in progress.
* Phase 3 (Namespace alignment): ⏳ pending.
* Phase 4 (Validation & optimization): ⏳ pending.

---

## 19) Charter Change Management

* Version bump on any normative change.
* PRs require non-author review.
* Linter (`tools/hwc-lint.sh`) updated in same PR.
* Include "Impact & Migration" notes for breaking changes.

---

## 20) Configuration Validity & Dependency Assertions

* **Mandatory Validation Section**: Every `index.nix` with `enable` toggle MUST include `# VALIDATION` section after `# IMPLEMENTATION`.
* **Assertion Requirement**: Modules MUST assert all runtime dependencies (system services, binaries, configuration reads).
* **Assertion Template**: `{ assertion = !enabled || config.hwc.dep.enable; message = "X requires Y"; }`
* **Sub-Toggle Policy**: Sub-toggles default to master state unless overridden. Dependents assert specific sub-toggle, not master.
* **Linting**: Charter linter verifies assertion presence and cross-domain dependency coverage.
* **Fail-Fast Principle**: Invalid configurations MUST fail at build time, never at runtime.
* **Examples**: See `domains/home/apps/waybar/index.nix`, `domains/home/apps/hyprland/index.nix` for reference patterns.

---

## 19) Complex Service Configuration Pattern

### The Config-First, Nix-Second Rule

For **complex services** with substantial configuration schemas (Frigate, Jellyfin, SABnzbd, Home Assistant, etc.):

**Pattern Requirements**:

1. **Canonical Config File**:
   - Maintain service configuration in the format the service expects (YAML/TOML/INI/XML)
   - Store in module directory: `domains/server/<service>/config/config.yml`
   - This file is **version-controlled** and **human-readable**
   - This file is **portable** - can work on non-NixOS systems with minimal changes

2. **Nix Responsibilities** (infrastructure only):
   - Container image/version pinning
   - Volume mounts (including config file)
   - Port mappings
   - GPU/device passthrough
   - Environment variables
   - Resource limits
   - **NOT** generating service-specific YAML/TOML/etc.

3. **Module Structure**:
   ```
   domains/server/<service>/
   ├── options.nix         # Nix-level options (image, ports, GPU, etc.)
   ├── index.nix           # Container definition
   ├── config/
   │   └── config.yml      # Canonical service config (mounted into container)
   └── README.md           # Service documentation
   ```

4. **Debug Workflow**:
   - To change service behavior: **Edit `config/config.yml` directly**
   - Restart service to apply changes
   - Once stable, commit the config file
   - **NOT**: Edit Nix → generate YAML → hope it's correct → debug generated output

### Rationale

**Why This Pattern**:
- ✅ **Debuggability**: Config is visible, not hidden in Nix string interpolation
- ✅ **Portability**: Config works on Docker/Podman/k8s with minimal changes
- ✅ **Validation**: Service's native tools can validate config
- ✅ **Documentation**: Upstream docs directly applicable
- ✅ **Complexity Management**: Service complexity stays in service format

**Anti-Pattern** (What NOT to Do):
```nix
# ❌ BAD: Encoding complex service config in Nix
hwc.server.frigate = {
  detectors.onnx = {
    type = "onnx";
    model = {
      path = "/config/model.onnx";
      input_dtype = "float";
      # ... 50 more options
    };
  };
  cameras.cam1 = {
    # ... complex RTSP/recording/detection config
  };
};
```

**Why It Fails**:
- YAML structure errors hidden in Nix indentation
- Service schema changes require Nix module updates
- Debugging requires inspecting generated files
- Not portable outside NixOS

**Correct Pattern**:
```nix
# ✅ GOOD: Nix handles infrastructure only
hwc.server.frigate = {
  enable = true;
  image = "ghcr.io/blakeblackshear/frigate:0.16.2";  # Explicit version
  gpu.enable = true;  # Infrastructure concern
  # Config comes from domains/server/frigate/config/config.yml
};
```

### When to Use Config-First

**Use Config-First for**:
- Services with >50 lines of configuration
- Services with complex nested schemas (Frigate, Home Assistant, Traefik)
- Services where upstream docs reference config files directly
- Services you need to debug frequently

**Nix Options Are Fine for**:
- Simple services with <20 config options
- Services where Nix options ARE the canonical interface (NixOS services)
- Infrastructure concerns (ports, volumes, env vars)

### Secrets Integration

Secrets (passwords, API keys) still use agenix:
- Reference secret files in config: `password_file: /run/agenix/service-password`
- Or use environment variable substitution in container
- **NOT**: Inline secrets in config files

### Validation Requirements

Modules using config-first pattern MUST:
1. Document config file location in README.md
2. Provide example/template config
3. Include verification script if possible
4. Document how to validate config (service's native tools)

### Migration from Nix-Generated Configs

When migrating from Nix-generated to config-first:
1. Extract current runtime config: `podman exec service cat /config/config.yml`
2. Save to `domains/server/<service>/config/config.yml`
3. Commit as-is (baseline)
4. Modify Nix to mount file instead of generating
5. Verify service works identically
6. Only then refactor config as needed

---

## 20) Data Retention & Lifecycle Management

**Rule**: All data retention policies MUST be declared in NixOS configuration with automated enforcement.

### Core Principles

1. **Declarative-First**: Retention policies defined in configuration, never ad-hoc
2. **Fail-Safe**: Automated enforcement even if primary application fails
3. **Predictable**: Time-based and size-based limits clearly documented
4. **Observable**: All cleanup operations logged to systemd journal
5. **Reproducible**: Version-controlled policies deployable to any machine

### Retention Policy Structure

Every data store with retention requirements MUST define:

```nix
{
  # Primary enforcement (application-level)
  retention = {
    days = 7;        # or weeks/months
    mode = "time";   # or "size" or "count"
  };

  # Fail-safe enforcement (systemd timer)
  systemd.timers.<service>-cleanup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };
}
```

### Data Classification System

| Category | Retention | Backup | Examples |
|----------|-----------|--------|----------|
| **CRITICAL** | Indefinite | ✅ Weekly | Photos, configs, business data |
| **REPLACEABLE** | Indefinite | ❌ No | Movies, TV shows, music |
| **AUTO-MANAGED** | 7-30 days | ❌ No | Surveillance, logs |
| **EPHEMERAL** | <7 days | ❌ No | Cache, temp files |

### Example: Surveillance Retention

**Pattern**: Application config + systemd timer fail-safe

```nix
# Primary: Frigate built-in retention
domains/server/frigate/config/config.yml:
  record:
    retain:
      days: 7  # Keep recordings for 7 days

# Fail-safe: systemd enforcement
machines/server/config.nix:
  systemd.timers.frigate-cleanup = {
    wantedBy = [ "timers.target" ];
    timerConfig.OnCalendar = "daily";
  };
  systemd.services.frigate-cleanup.script = ''
    find /mnt/media/surveillance -type f -mtime +7 -delete
  '';
```

### Backup Source Selection

**Rule**: Only back up CRITICAL and irreplaceable data. Exclude REPLACEABLE and AUTO-MANAGED data.

```nix
hwc.system.services.backup.local = {
  sources = [
    "/home"                  # User data, configs
    "/mnt/media/pictures"    # IRREPLACEABLE photos
    "/mnt/media/databases"   # Database backups
  ];

  excludePatterns = [
    "*/movies/*"             # Can re-download
    "*/tv/*"                 # Can re-download
    "*/surveillance/*"       # Auto-rotates
  ];
};
```

### Anti-Patterns

❌ **Manual cleanup scripts outside NixOS config**
```bash
# BAD: Ad-hoc cron job
crontab -e
0 0 * * * find /data -mtime +30 -delete
```

✅ **Declarative systemd timer**
```nix
# GOOD: In machines/server/config.nix
systemd.timers.data-cleanup = { ... };
```

❌ **Backing up replaceable media**
```nix
# BAD: Wasting 3TB on replaceable movies
sources = [ "/mnt/media/movies" ];
```

✅ **Backing up only critical data**
```nix
# GOOD: Only irreplaceable photos
sources = [ "/mnt/media/pictures" ];
```

### Monitoring & Verification

All retention policies MUST have verification commands documented:

```bash
# Check oldest files (should match retention period)
find /data -type f | head -1 | xargs stat -c "%y %n"

# Verify timer status
systemctl status cleanup.timer
journalctl -u cleanup.service -n 20
```

**Reference**: See `/docs/infrastructure/retention-and-cleanup.md` for complete policies

---

## 21) Related Documentation

* **Filesystem Charter** (`FILESYSTEM-CHARTER.md`): Home directory organization (`~/`) with domain-based structure
  - 3-digit prefix system (100_hwc, 200_personal, 300_tech, etc.)
  - XDG integration configured in `domains/system/core/paths.nix`
  - GTD-style inbox processing workflow
* **Claude Instructions** (`CLAUDE.md`): AI assistant working instructions and quick reference
* **Documentation Index** (`GEMINI.md`): Dynamic index to all authoritative sources

---

**Charter Version**: v8.0 - Data Retention & Lifecycle Management

**Version History**:
- v8.0 (2025-12-04): Added section 20 "Data Retention & Lifecycle Management" establishing declarative retention policies with fail-safe enforcement
- v7.0 (2025-11-23): Added section 19 "Complex Service Configuration Pattern" establishing config-first rule for services like Frigate
- v6.0: Configuration Validity & Dependency Assertions

---
