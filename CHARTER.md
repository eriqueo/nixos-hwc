# HWC Architecture Charter v9.0

**Owner**: Eric
**Scope**: `nixos-hwc/` — all machines, domains, profiles, Home Manager, and supporting files
**Goal**: Deterministic, maintainable, scalable, and reproducible NixOS via strict domain separation, explicit APIs, predictable patterns, and user-centric organization.

**Philosophy**: This Charter defines **architectural laws** (cross-domain rules) and provides **brief domain overviews** with pointers to domain-specific documentation. Implementation details live in domain READMEs and `docs/patterns/`.

---

## 0) Preserve-First Doctrine

* **Refactor = reorganize, not rewrite**.
* 100% feature parity during migrations.
* Wrappers/adapters allowed only as temporary bridges (tracked & removed).
* Never switch on red builds.

---

## 1) Architectural Laws (Cross-Domain Rules)

These laws are **testable** and violations are **mechanically detectable**. Each law has a violation type for tracking compliance.

### Law 1: The Handshake Protocol (Cross-Distro Detection)

**Rule**: Home-lane modules must support non-NixOS hosts via optional `osConfig`.

```nix
# Function signature (REQUIRED)
{ config, lib, pkgs, osConfig ? {}, ... }:

# Feature detection (REQUIRED)
let
  isNixOSHost = osConfig ? hwc;
in
```

**Requirement**: Home modules must evaluate successfully when `osConfig = {}`.

**Violation Type 1**: Home module blocking evaluation on empty `osConfig` (assertions without `isNixOSHost` guard).

### Law 2: The 1:1 Namespace Rule

**Rule**: Option namespace MUST match folder structure for immediate error traceability.

```
domains/home/apps/firefox/  →  hwc.home.apps.firefox.*
domains/system/core/paths/  →  hwc.system.core.paths.*
domains/server/jellyfin/    →  hwc.server.jellyfin.*
```

**Blessed Shortcuts** (permanent exceptions, documented):
- `hwc.paths` — Universal path abstraction (special cross-domain API)
- `hwc.filesystem` — Short for `hwc.system.core.filesystem`
- `hwc.networking` — Short for `hwc.system.services.networking`
- `hwc.home.fonts` — Short for `hwc.home.theme.fonts`

**Violation Type 2**: Namespace mismatch or use of deprecated namespaces:
- ❌ `hwc.services.*` (should be `hwc.server.*` or `hwc.system.services.*`)
- ❌ `hwc.features.*` (deprecated)
- ❌ Option path not matching folder path

### Law 3: The Path Abstraction Contract

**Rule**: No hardcoded filesystem paths in implementation. All paths via `config.hwc.paths.*`.

```nix
# ✓ CORRECT
volumes = [ "${config.hwc.paths.media.music}:/music:ro" ];

# ✗ VIOLATION
volumes = [ "/mnt/media/music:/music:ro" ];
```

**Auto-Detection**: `paths.nix` auto-detects primary user and provides home-relative defaults:
- `primaryUser` — Detected from `config.users.users` (prefers "eric", falls back to first normal user)
- `detectedHome` — Primary user's home directory
- All storage tiers default to `${detectedHome}/storage/*` (never null)

**Violation Type 3**: Hardcoded `/mnt/` or `/home/` paths in `domains/` (excluding `paths.nix` and documentation).

### Law 4: The 1000:100 Permission Standard

**Rule**: All services run as primary user (UID 1000) with primary group (GID 100).

```nix
# Containers (REQUIRED)
environment = {
  PUID = "1000";  # Primary user
  PGID = "100";   # users group (NOT 1000!)
  TZ = config.time.timeZone;
};

# Native services (REQUIRED)
systemd.services.<service> = {
  serviceConfig = {
    User = lib.mkForce "eric";
    Group = lib.mkForce "users";
    StateDirectory = "hwc/<service>";
  };
};

# Secrets (REQUIRED)
age.secrets.<name> = {
  file = ../../parts/<domain>/<name>.age;
  mode = "0440";   # Read-only for owner + group
  owner = "root";
  group = "secrets";
};

# Service user secret access (REQUIRED)
users.users.eric.extraGroups = [ "secrets" ];
```

**Rationale**: Single-user infrastructure model. GID 100 (`users`) ensures files are owned by `eric:users` for direct access.

**Violation Type 4**:
- Container using PGID 1000 instead of 100
- Service not in `secrets` group when accessing secrets
- Secrets without `mode = "0440"` or `group = "secrets"`

### Law 5: The Three Sections Pattern

**Rule**: Every `index.nix` must have exactly three sections in order.

```nix
{ config, lib, pkgs, ... }:
let
  enabled = config.hwc.<domain>.<module>.enable or false;
  cfg = config.hwc.<domain>.<module>;
in
{
  #==========================================================================
  # OPTIONS (MANDATORY)
  #==========================================================================
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION (MANDATORY)
  #==========================================================================
  config = lib.mkIf enabled {
    # Module implementation
  };

  #==========================================================================
  # VALIDATION (MANDATORY if dependencies exist)
  #==========================================================================
  config.assertions = lib.mkIf enabled [
    {
      assertion = !enabled || config.hwc.dependency.enable;
      message = "Module X requires dependency Y to be enabled";
    }
  ];
}
```

**Violation Type 5**:
- Missing VALIDATION section when module has dependencies
- Options defined outside `options.nix`
- Implementation not wrapped in `lib.mkIf enabled`

### Law 6: The sys.nix Co-location Pattern

**Rule**: Home apps requiring system-level support use co-located `sys.nix` for system-lane code.

```
domains/home/apps/hyprland/
├── options.nix    # hwc.home.apps.hyprland.* (Home-lane API)
├── index.nix      # Home Manager implementation
├── sys.nix        # hwc.system.apps.hyprland.* (System-lane API)
└── parts/         # Pure helpers
```

**Critical Rules**:
- `sys.nix` belongs to **system lane**, imported by system profiles
- `sys.nix` defines its own options in `hwc.system.apps.*` namespace (evaluation order requirement)
- `index.nix` (Home-lane) **never imports** `sys.nix` (System-lane)
- Valid `sys.nix` content: `environment.systemPackages`, `programs.*.policies`, udev rules

**Violation Type 6**:
- Home `index.nix` importing `sys.nix`
- `sys.nix` importing home modules
- `sys.nix` depending on `hwc.home.apps.*` options (evaluation order violation)

---

## 2) Domain Architecture Overview

Each domain has a **unique interaction boundary** with the system. Domain READMEs contain implementation details.

### domains/home/ — User Environment (Home Manager)

**Boundary**: User-space configs, desktop environment, window manager, applications, dotfiles

**Contains**:
- `programs.*`, `home.*`, `xdg.*` (Home Manager options)
- Application configurations
- User theme and appearance

**Never Contains**:
- `systemd.services` (system services)
- `environment.systemPackages` (system packages)
- `users.*` (user account creation)

**Unique Pattern**: `sys.nix` co-location for system-lane support (Law 6)

**Details**: See `domains/home/README.md`

### domains/system/ — Core OS & Services

**Boundary**: User accounts, networking, security policies, system packages, OS services

**Contains**:
- User account definitions (`domains/system/users/`)
- Core system services (`domains/system/services/`)
- System package collections
- **Path abstraction layer** (`domains/system/core/paths.nix`)

**Never Contains**:
- Home Manager configs (`programs.*`, `home.*`, `xdg.*`)
- Secret declarations (those live in `domains/secrets/`)

**Unique Pattern**: `paths.nix` provides universal path abstraction (Law 3)

**Details**: See `domains/system/README.md`

### domains/infrastructure/ — Hardware & Cross-Domain Orchestration

**Boundary**: Hardware management, GPU, power, peripherals, virtualization, filesystem structure

**Contains**:
- Hardware drivers and configuration
- Power management
- Virtualization (libvirt, winapps)
- Storage infrastructure layer

**Never Contains**:
- Home Manager configs
- High-level application logic

**Unique Pattern**: Orchestrates across system/home boundaries for hardware concerns

**Details**: See `domains/infrastructure/README.md`

### domains/server/ — Host Workloads

**Boundary**: Containers, databases, web services, media servers, reverse proxy

**Contains**:
- OCI containers (`domains/server/containers/`)
- Native services (`domains/server/native/`)
- Reverse proxy routing
- Media orchestration

**Never Contains**:
- Home Manager configs

**Unique Patterns**:
- **mkContainer helper** — Pure function reducing container boilerplate (~50 lines → ~18 lines)
  - Location: `domains/server/containers/_shared/pure.nix`
  - Standard: PUID=1000, PGID=100, timezone auto-set
- **Config-First rule** — Complex services (Frigate, Jellyfin) use canonical config files (YAML/TOML) mounted into containers, NOT Nix-generated configs

**Details**: See `domains/server/README.md`

### domains/secrets/ — Encrypted Secrets (agenix)

**Boundary**: Age secret declarations, encrypted `.age` files, secret API at `/run/agenix`

**Contains**:
- Secret declarations in `age.secrets.*`
- Encrypted `.age` files in `parts/`
- Secret API facade (`secrets-api.nix`)

**Never Contains**:
- Unencrypted secrets
- Secret values in git (only encrypted `.age` files)

**Permission Model**: All secrets `mode = "0440"`, `group = "secrets"` (Law 4)

**Details**: See `domains/secrets/README.md`

### domains/ai/ — AI/ML Services

**Boundary**: Ollama, Open WebUI, MCP servers, AI workflows, model routing

**Contains**:
- Local AI infrastructure (Ollama)
- AI interfaces (Open WebUI)
- MCP servers for Claude Code integration
- Automated workflows

**Never Contains**:
- Home Manager configs (AI services are system/server-lane)

**Unique Pattern**: Router facade for local-first with cloud fallback

**Details**: See `domains/ai/README.md`

---

## 3) Universal Patterns (Cross-Domain Standards)

### Module Anatomy

All modules follow this structure:

```
domains/<domain>/<category>/<module>/
├── options.nix    # API definition (MANDATORY)
├── index.nix      # Implementation (Three Sections: OPTIONS/IMPLEMENTATION/VALIDATION)
├── sys.nix        # System-lane co-located config (optional, home apps only)
├── parts/         # Pure helper functions (optional)
│   ├── config.nix
│   ├── scripts.nix
│   └── theme.nix
└── README.md      # Usage documentation (recommended)
```

**Rules**:
- `options.nix` always exists — options never defined ad hoc in other files
- Namespace matches folder structure: `domains/home/apps/firefox/options.nix` → `hwc.home.apps.firefox.*`
- One logical concern per module directory
- `parts/` contains pure functions only (no options, no side effects)

### Profiles — Domain Feature Menus

**Purpose**: Aggregate domain modules into BASE + OPTIONAL structure for machine composition.

**Structure**:
```nix
# profiles/<domain>.nix
{ config, lib, pkgs, ... }:
{
  imports = [
    ../domains/<domain>/index.nix
    # ... other domain imports
  ];

  #==========================================================================
  # BASE — Critical for machine functionality
  #==========================================================================
  # Essential imports, required for domain to function

  #==========================================================================
  # OPTIONAL FEATURES — Sensible defaults, override per machine
  #==========================================================================
  hwc.<domain>.<module>.enable = lib.mkDefault true;
  # ... other feature toggles
}
```

**Types**: `system.nix`, `home.nix`, `infrastructure.nix`, `server.nix`, `ai.nix`, `security.nix`, `media.nix`, etc.

**Machine Composition**: Machines import combination of profiles needed:
```nix
# machines/laptop/config.nix
imports = [
  ../../profiles/system.nix
  ../../profiles/home.nix
  ../../profiles/infrastructure.nix
];
```

### Layering & Flow

**NixOS System Flow**:
```
flake.nix
  → machines/<host>/config.nix (hardware facts + profile imports)
    → profiles/* (domain feature menus)
      → domains/{system,infrastructure,server,ai}/ (implementations)
```

**Home Manager Flow**:
```
machines/<host>/home.nix (HM activation point)
  → domains/home/ (user environment implementations)
```

**Critical Rule**: Home Manager activation ONLY in `machines/<host>/home.nix`, never in profiles.

**Dependency Direction**: Always downward (flake → machines → profiles → domains).

---

## 4) Mechanical Validation (Enforcement)

These searches identify architectural violations. All MUST return empty or zero results.

### Law 1: Handshake Protocol Violations

```bash
# Home modules without optional osConfig
rg 'osConfig,' domains/home --type nix | rg -v 'osConfig \?'
```

### Law 2: Namespace Violations

```bash
# Deprecated hwc.services.* namespace (should be hwc.server.* or hwc.system.services.*)
rg 'options\.hwc\.services\.' domains --glob '!_shared/*'

# Deprecated hwc.features.* namespace
rg 'options\.hwc\.features\.' domains
```

### Law 3: Path Abstraction Violations

```bash
# Hardcoded /mnt/ or /home/ paths (excluding paths.nix and docs)
rg '="/mnt/|="/home/' domains --glob '!paths.nix' --glob '!*.md'
```

### Law 4: Permission Standard Violations

```bash
# Permission linter (checks PGID 100, secrets group, etc.)
./workspace/utilities/lints/permission-lint.sh domains
```

### Law 5: Module Structure Violations

```bash
# Options defined outside options.nix
rg 'options\.hwc\.' domains --type nix --glob '!options.nix' --glob '!sys.nix'
```

### Cross-Domain Boundary Violations

```bash
# Home Manager configs in system/infrastructure/server domains
rg 'programs\.|home\.|xdg\.' domains/system/ domains/infrastructure/ domains/server/

# System configs in home domain
rg 'systemd\.services|environment\.systemPackages|users\.users\.' domains/home/

# Home Manager activation in profiles (except profiles/home.nix)
rg 'home-manager\.users\.' profiles/ --glob '!home.nix'
```

---

## 5) Related Documentation

### Domain-Specific Details

Each domain has a comprehensive README with implementation patterns:

- **domains/home/README.md** — Home Manager patterns, sys.nix usage, app modules
- **domains/system/README.md** — User management, path system, core services
- **domains/infrastructure/README.md** — Hardware abstraction, storage, virtualization
- **domains/server/README.md** — Container patterns, native services, routing
- **domains/secrets/README.md** — Secret management workflow, agenix usage
- **domains/ai/README.md** — AI service architecture, router pattern, workflows

### Implementation Patterns

Detailed recipes for common tasks:

- **docs/patterns/config-first-services.md** — Complex service configuration (Frigate, Jellyfin, etc.)
- **docs/patterns/container-standard.md** — mkContainer helper usage and examples
- **docs/patterns/path-system.md** — Path abstraction details and override patterns

### Standards & Policies

- **docs/standards/permission-patterns.md** — Permission model examples and troubleshooting
- **docs/policies/data-retention.md** — Retention rules and lifecycle management

### Troubleshooting

- **docs/troubleshooting/permissions.md** — Common permission issues and resolutions
- **docs/troubleshooting/build-failures.md** — Debugging evaluation and build errors

---

## 6) Charter Change Management

**Proposal Process**:
1. Draft changes in `workspace/claude_plans/<descriptive-name>.md`
2. Include rationale and migration impact assessment
3. Review against existing domain READMEs
4. Version bump triggers domain README review cycle

**Version History**:
- **v9.0 (2026-01-10)**: Architectural Laws & Domain Pointer Philosophy — Streamlined Charter to testable laws with domain README pointers
- v8.0 (2025-12-04): Data Retention & Lifecycle Management
- v7.0 (2025-11-23): Complex Service Configuration Pattern (Config-First Rule)
- v6.0: Configuration Validity & Dependency Assertions

**Current Version**: **v9.0**

**Philosophy Evolution**: Charter is **architectural law**, not implementation cookbook. Laws are testable. Details live in domain READMEs and `docs/patterns/`. This Charter defines cross-domain rules and provides pointers to domain-specific documentation.

---

**End of Charter v9.0**
