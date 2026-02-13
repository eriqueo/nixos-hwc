# HWC Architecture Charter v10.3

**Owner**: Eric  
**Scope**: `nixos-hwc/` — all machines, domains, profiles, Home Manager, and supporting files  
**Goal**: Deterministic, maintainable, scalable, reproducible NixOS configuration via strict domain separation, explicit APIs, and user-centric organization.  
**Philosophy**: This document defines **enforceable architectural laws**. Implementation details, patterns, and domain-specific guidance live in domain READMEs and `docs/patterns/`.
**Current Date**: January 17, 2026

## 0. Preserve-First Doctrine

- Refactor = reorganize, **never rewrite**.
- Maintain 100% feature parity during migrations.
- Temporary wrappers/adapters must be tracked and eventually removed.
- Never deploy/switch on failing builds.
- For large refactors, use feature flags (e.g., `hwc.migration.<feature>`) or temporary domain aliases to ensure safe, incremental alignment.

## 1. Architectural Laws (Enforceable Rules)

Violations are **mechanically detectable** via lint scripts and searches. Each law defines a clear violation type.

### Law 1: Handshake Protocol (Standalone / Cross-Distro Compatibility)

Home-lane modules **must** evaluate cleanly on non-NixOS hosts.

**Required signature**:
```nix
{ config, lib, pkgs, osConfig ? {}, ... }:
```

**Required guard**:
```nix
let isNixOS = osConfig ? hwc or false;
in { ... }
```

**Safe access patterns (ONLY these are permitted)**:
```nix
# Pattern 1: Guard with isNixOS check
assertions = lib.mkIf isNixOS [ ... ];

# Pattern 2: Provide empty fallback for entire namespace
let osHwc = osConfig.hwc or {};
in osHwc.paths.media or "/fallback"

# Pattern 3: Use attrByPath for deep access
lib.attrByPath ["hwc" "paths" "media"] "/fallback" osConfig
```

**Unsafe patterns (FORBIDDEN)**:
```nix
osConfig.hwc.something or null  # Fails when osConfig = {}
osConfig.hwc.paths.media        # No fallback, crashes on non-NixOS
```

**Violation**: Unguarded `osConfig` access, use of unsafe access patterns, or assertion that fails when `osConfig = {}`.

### Law 2: Strict Namespace Fidelity

Option namespace **must exactly match** the folder path hierarchy, with no shortcuts or aliases.

Examples:  
`domains/home/apps/firefox/` → `hwc.home.apps.firefox.*`  
`domains/paths/` → `hwc.paths.*`

**No exceptions permitted**. All shortcuts must be deprecated and removed.

**Violation**: Any use of shortened or mismatched namespaces (e.g., `hwc.paths`, `hwc.networking`, `hwc.services.*`).

### Law 3: Path Abstraction Contract

**No filesystem paths may be hardcoded** outside `domains/paths/index.nix`.

**Correct**:
```nix
volumes = [ "${config.hwc.paths.media.music}:/music:ro" ];
```

**Incorrect**:
```nix
volumes = [ "/mnt/media/music:/music:ro" ];
```

**paths/index.nix guarantees**:
- Auto-detection of primary user/home
- Home-relative defaults for all storage tiers (`~/storage/hot`, etc.)
- Absolute path assertions
- No `null` defaults (use overrides in machines)

**Violation**: Any hardcoded `/mnt/`, `/home/eric/`, `/opt/` (except in `paths/index.nix` itself and documentation).

### Law 4: Unified Permission Model (Source-of-Truth Identity)

All services **must** run as primary user (UID 1000) : `users` group (GID 100).

**Source of truth**: `hwc.system.identity.{puid,pgid,user,group}` options defined in `domains/system/core/identity.nix` (to be implemented).

**Containers** (use identity options):
```nix
let
  identity = config.hwc.system.identity;
in
environment.PUID = toString identity.puid;  # "1000"
environment.PGID = toString identity.pgid;  # "100"
```

**Native services** (use identity options):
```nix
let
  identity = config.hwc.system.identity;
in
serviceConfig = {
  User = lib.mkForce identity.user;          # "eric"
  Group = lib.mkForce identity.group;        # "users"
  StateDirectory = "hwc/<service>";
};
```

**Secrets** (standard pattern):
```nix
age.secrets.<name> = {
  mode = "0440";
  owner = "root";
  group = "secrets";
};
```

**Literal fallback**: When identity options aren't in scope (e.g., `mkContainer` helper), hardcoded `1000` and `100` are permitted with a justifying comment.

**Violation**: PGID=1000 (should be 100), hardcoded UID/GID/user/group when identity options are available, missing `secrets` group membership, secrets without 0440 mode.

### Law 5: Container Standard (mkContainer)

All OCI containers **must** use the `mkContainer` pure helper unless explicitly justified.

Location: `domains/server/containers/_shared/pure.nix`

**Guarantees**:
- PUID=1000, PGID=100
- TZ from host
- Consistent health-check pattern
- Minimal privileged flags

**Violation**: Raw `virtualisation.oci-containers.containers` blocks without justification comment.

### Law 6: Three Mandatory Sections & Validation Discipline

Every `index.nix` **must** contain three mandatory sections in order:

```nix
# OPTIONS (mandatory)
imports = [ ./options.nix ];

# IMPLEMENTATION (mandatory)
config = lib.mkIf cfg.enable { ... };

# VALIDATION (mandatory when dependencies exist)
config.assertions = lib.mkIf cfg.enable [ ... ];
```

**Optional HELPERS section** (if needed):
```nix
# HELPERS (optional, must be clearly labeled)
let
  scriptHelpers = import ./parts/scripts.nix { inherit pkgs lib; };
  # ... other pure helpers
in
```

Place HELPERS section **before** OPTIONS section when used. Helpers must be pure functions with no side effects.

Cross-cutting assertions (spanning multiple submodules) must live in the highest relevant parent `index.nix`, but no more than one level up from the submodules involved. All must be guarded by the enabling option(s).

**Violation**: Missing mandatory section, wrong section order, options outside `options.nix`, unguarded assertions, assertions not placed at the appropriate level, unlabeled helper code.

### Law 7: sys.nix Lane Purity

Co-located `sys.nix` files in home domains belong **exclusively** to system lane.

**Rules**:
- `sys.nix` defines `hwc.system.apps.<name>.*` options
- Home `index.nix` **never** imports `sys.nix`
- System cannot depend on home options (evaluation order)

**Violation**: Home → system import, system → home dependency, `sys.nix` using `hwc.home` options.

### Law 8: Data Retention Contract

All persistent data stores (anywhere in the config) **must** declare retention policy in Nix.

**Minimum**:
- Application-level retention (in config file or Nix option)
- Fail-safe systemd timer for cleanup

**Classification** (documented in module):
- CRITICAL: indefinite + backup
- REPLACEABLE: indefinite, no backup
- AUTO-MANAGED: time/size limited

**Violation**: Persistent volume or state without documented retention + timer.

### Law 9: Module Shape Discipline (Leaf vs Directory)

Modules must follow a strict shape based on complexity:

- **Leaf module** = single `.nix` file. Use for simple, self-contained config with no payload management (e.g., package sets, basic toggles). **Leaf modules are implementation-only** and must NOT declare `hwc.*` options. No `options.nix`, `index.nix`, or `parts/`.

- **Directory module** = folder with `options.nix` + `index.nix` (+ `parts/` if needed). Use **only** when the module owns a namespace (declares `hwc.*` options) or manages payload: multiple generated files, dotfiles bundle, or internal helpers/fragments. **Directory modules own their namespace** via `options.nix`.

Litmus test: If it only sets `packages/programs/services.*` and has no dotfiles/fragments/helpers → leaf. If it declares any `hwc.*` options → directory.

**Violation**: Directory without justified payload or namespace ownership, leaf file declaring options, leaf file with scattered impl, directory missing `options.nix`.

### Law 10: Option Declaration Purity

Option declarations (`mkOption`) **may only appear** in files named `options.nix`.

Domain/subdomain root `options.nix` must be slim: only truly shared/cross-cutting options. Substantial options belong in dedicated subdomains or modules.

**Primitive Module Exception (sole current exception)**  
The file `domains/paths/paths.nix` is permitted to co-locate option declarations and implementation as the single foundational primitive for universal filesystem abstraction.

Requirements:
1. The file must contain a top-of-file header justifying the exception and referencing this law.
2. The module's scope must remain narrow: path references, overrides, exports, assertions, and only minimal bootstrap tmpfiles. The module must not grow payload (dotfiles/templates).
3. The module must provide a documented, discoverable per-machine override mechanism (e.g., `hwc.paths.overrides`) that supports nested/recursive overrides.
4. The mechanical linter suite may whitelist this file for the `mkOption` rule; no other file is exempt.
5. The exception is revocable: if the module acquires payload or grows complex, it must be split into `options.nix` + `index.nix` + `parts/` and this exception removed.

**Violation**: `mkOption` outside `options.nix` (except the primitive), bloated root `options.nix`.

### Law 11: Domain Evaluation Order

Domains must respect a safe evaluation dependency direction: paths → system → infrastructure → home → server → ai → secrets (reverse dependencies forbidden).

Note: Infrastructure will eventually merge into system, at which point this order becomes: paths → system → home → server → ai → secrets.

**Violation**: Cyclic or reverse dependencies (e.g., server depending on home options).

## 2. Domain Architecture Overview

Each domain has a **unique interaction boundary** with the system.  
Domain READMEs contain implementation details, patterns, and known limitations.

- **domains/paths/** — Universal Filesystem Abstraction  
  Boundary: All filesystem paths, mount points, storage tiers, user home detection  
  Never contains: Actual service/container config, dotfiles  
  Unique: Provides dynamic, centralized, overridable path references used across all other domains

- **domains/home/** — User Environment (Home Manager)  
  Boundary: User-space configs, DE/WM, apps, dotfiles  
  Never contains: systemd.services, environment.systemPackages, users.users  
  Unique: sys.nix co-location for system-lane support (Law 7)

- **domains/system/** — Core OS & Services
  Boundary: Accounts, networking, security, system packages
  Never contains: Home Manager configs, secret declarations
  Unique: Relies on paths domain for abstractions (Law 3)
  Note: Avoid `services/` as a god-directory; promote semantic subdomains (e.g., networking, storage, session) and flatten simple modules to leaves.
  Future: Hardware management from infrastructure domain will migrate here (system/hardware/, system/virtualization/)

- **domains/infrastructure/** — Hardware Management & Orchestration
  Boundary: GPU, power, peripherals, storage tiers, virtualization, udev rules
  Never contains: Home Manager configs, high-level app logic
  Status: **MIGRATION PENDING** - Content will be absorbed into domains/system/ as semantic subdomains (system/hardware/, system/virtualization/, system/storage/)

- **domains/server/** — Host Workloads  
  Boundary: Containers, databases, media servers, reverse proxy  
  Never contains: Home Manager configs  
  Unique: mkContainer helper (Law 5), Config-First for complex services

- **domains/secrets/** — Encrypted Secrets (agenix)  
  Boundary: Age declarations, encrypted files, /run/agenix facade  
  Never contains: Unencrypted values

- **domains/ai/** — AI/ML Services  
  Boundary: Ollama, Open WebUI, MCP servers, workflows  
  Never contains: Home Manager configs  
  Unique: Local-first router with cloud fallback

## 3. Mechanical Validation Suite

Run these regularly / in CI. All **must return zero violations**.

```bash
# Law 1: Safe osConfig access (allowlist-based)
# Flag any osConfig usage NOT matching safe patterns: (osConfig.hwc or {}), attrByPath, or isNixOS guard
rg 'osConfig\.' domains/home --type nix | rg -v 'osConfig\.hwc or \{\}|attrByPath|lib\.mkIf isNixOS'

# Law 2: Namespace fidelity (deprecated shortcuts)
# Note: hwc.paths.* is valid (domains/paths/), hwc.system.networking.* is valid (domains/system/networking/)
rg 'hwc\.services\.|hwc\.features\.|hwc\.filesystem|hwc\.home\.fonts|\bhwc\.networking\b' domains

# Law 3: Path abstraction (hardened - matches any hardcoded path string)
rg '"/mnt/|"/home/eric/|"/opt/|'\''/mnt/|'\''/home/eric/|'\''/opt/' domains --type nix --glob '!domains/paths/**' --glob '!*.md'

# Law 4: Permission model
./workspace/utilities/lints/permission-lint.sh

# Law 10: Option declaration purity
rg 'options\.hwc\.' domains --type nix --glob '!options.nix' --glob '!sys.nix'
rg 'mkOption' domains --type nix --glob '!options.nix' --glob '!domains/paths/paths.nix'

# Law 7: sys.nix lane purity
rg 'import.*sys.nix' domains/home/*/index.nix

# Law 5: Container standard
rg 'oci-containers\.containers\.[^=]+=' domains/server --glob '!mkContainer'

# Law 8: Data retention
rg -L 'retain:|retention:|cleanup.timer' domains
```

**Nix-level validations** (fail at eval/build, not just lint):
- Path absoluteness/non-null: Enforced in `domains/paths/index.nix` via assertions
- Container PUID/PGID: Enforced in `mkContainer` helper via default values
- Missing dependencies: Enforced via module VALIDATION sections

## 4. Exception Annotation Protocol

Laws may permit exceptions when architecturally justified. All exceptions **must** be documented with formal annotations.

**Annotation format**:
```nix
# HWC-EXCEPTION(Law X): <brief reason>
# Justification: <detailed explanation>
# Plan: <link to workspace/plans/ or "permanent by design">
# Revocable: <yes/no>
```

**Example**:
```nix
# HWC-EXCEPTION(Law 10): Primitive module co-location
# Justification: paths.nix is foundational bootstrap layer requiring atomic option+impl
# Plan: permanent by design (see CHARTER.md Law 10 primitive exception)
# Revocable: yes (if module acquires payload, must split)
```

**Current exceptions**:
- **Law 10**: `domains/paths/paths.nix` primitive module (documented in law itself)

**No exceptions permitted**:
- **Law 2**: Strict namespace fidelity (never)

Exceptions require:
1. Charter documentation (for structural exceptions like Law 10 primitive)
2. In-code annotation using format above
3. Revocation conditions when temporary
4. Lint whitelist entry where applicable

## 5. Enforcement Levels

| Severity | Description                        | Action                     |
|----------|------------------------------------|----------------------------|
| Critical | Build failure / runtime breakage   | Immediate fix required     |
| High     | Charter law violation              | Fix before next major work |
| Medium   | Deprecated pattern / inconsistency | Track in backlog           |
| Low      | Documentation/style nit            | Optional nice-to-have      |

## 5. Change Management & Version History

- Major law changes require lint pass + domain README review
- Proposals in `workspace/plans/`
- Version bump on normative change

**Version History** (excerpt):
- **v10.3 (2026-01-17)**: Hardened Charter laws for production readiness:
  - Law 1: Replaced unsafe `osConfig.hwc.x or null` with safe canonical patterns (attrByPath, namespace fallback, isNixOS guard); updated lint to allowlist-based check
  - Law 4: Introduced `hwc.system.identity.*` source-of-truth options; forbid hardcoded UID/GID when identity options available; literal fallback permitted with justification
  - Law 6: Relaxed from "exactly three sections" to "three mandatory sections" (OPTIONS/IMPLEMENTATION/VALIDATION) with optional clearly-labeled HELPERS section
  - Law 9: Clarified that leaf modules are implementation-only (no `hwc.*` options), directory modules own namespaces via `options.nix`
  - Law 3 lint: Hardened to match any hardcoded path string (not just `="..."`), explicit exclude for `domains/paths/**`
  - Added Section 4: Exception Annotation Protocol (formal HWC-EXCEPTION format); Law 2 permits no exceptions
  - Strengthened mechanical detection: documented Nix-level validations (paths, container PUID/PGID, dependencies) that fail at eval/build
  - Reorganized mechanical validation suite with law-labeled comments
- **v10.2 (2026-01-17)**: Corrected Charter to reflect reality - `domains/infrastructure/` still exists and is active. Documented migration vision: infrastructure will be absorbed into system domain as semantic subdomains. Updated Law 11 evaluation order to include infrastructure. Marked infrastructure domain as MIGRATION PENDING.
- **v10.1 (2026-01-11)**: Added `domains/paths/` as a new domain; updated Law 3 to reference `hwc.paths.*`; adjusted Law 11 evaluation order to include paths first; updated lints for paths; refined Law 6 for assertion passing (one parent max).
- **v10.0 (2026-01-11)**: Removed all blessed namespace exceptions (Law 2 strict); added Laws 9 (module shapes), 10 (option purity), 11 (evaluation order); simplified validation placement (Law 6); generalized Law 8; erroneously claimed removal of infrastructure domain; aspirational push against `services/` god-directory; updated lints.
- **v9.1 (2026-01-10)**: Added Law 5 (mkContainer), Law 8 (Retention), refined violation searches, enforcement levels
- **v9.0 (2026-01-10)**: Laws + mechanical validation focus

**End of Charter v10.3**