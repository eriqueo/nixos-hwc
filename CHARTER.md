# HWC Architecture Charter v11.1

**Owner**: Eric
**Scope**: `nixos-hwc/` — all machines, domains, profiles, Home Manager, and supporting files
**Goal**: Deterministic, maintainable, scalable, reproducible NixOS configuration via strict domain separation, explicit APIs, and user-centric organization.
**Philosophy**: This document defines **enforceable architectural laws**. Implementation details, patterns, and domain-specific guidance live in domain READMEs (per Law 12).
**Current Date**: March 12, 2026

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

Location: `domains/lib/mkContainer.nix`

**Guarantees**:
- PUID=1000, PGID=100
- TZ from host
- Consistent health-check pattern
- Minimal privileged flags

**Violation**: Raw `virtualisation.oci-containers.containers` blocks without justification comment.

### Law 6: Unified Module Structure

Every directory module's `index.nix` **must** contain sections in this order:

```nix
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.<namespace>;
in
{
  # OPTIONS (mandatory for directory modules)
  options.hwc.<namespace> = {
    enable = lib.mkEnableOption "...";
    # other options
  };

  # IMPLEMENTATION (mandatory)
  config = lib.mkIf cfg.enable {
    # service config, packages, etc.

    # VALIDATION (inline, when dependencies exist)
    assertions = [ ... ];
  };
}
```

**Optional HELPERS section** (if needed):
```nix
let
  cfg = config.hwc.<namespace>;
  # HELPERS (optional, must be clearly labeled)
  scriptHelpers = import ./parts/scripts.nix { inherit pkgs lib; };
in
```

Place HELPERS in the `let` block before the module body. Helpers must be pure functions with no side effects.

Cross-cutting assertions (spanning multiple submodules) must live in the highest relevant parent `index.nix`, but no more than one level up from the submodules involved. All must be guarded by the enabling option(s).

**Violation**: Missing OPTIONS or IMPLEMENTATION section, wrong section order, unguarded assertions, assertions not placed at the appropriate level, unlabeled helper code.

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

- **Leaf module** = single `.nix` file. Use for simple, self-contained config with no payload management (e.g., package sets, basic toggles). **Leaf modules are implementation-only** and must NOT declare `hwc.*` options. No `index.nix` or `parts/`.

- **Directory module** = folder with `index.nix` (+ `parts/` if needed). Use **only** when the module owns a namespace (declares `hwc.*` options) or manages payload: multiple generated files, dotfiles bundle, or internal helpers/fragments. **Directory modules declare options inline** in `index.nix` under a `# OPTIONS` section (see Law 6).

Litmus test: If it only sets `packages/programs/services.*` and has no dotfiles/fragments/helpers → leaf. If it declares any `hwc.*` options → directory.

**Violation**: Directory without justified payload or namespace ownership, leaf file declaring options, leaf file with scattered impl.

### Law 10: Option Declaration Locality

Option declarations (`mkOption`) **must appear** in `index.nix` files under a clearly marked `# OPTIONS` section (see Law 6).

**Allowed locations for mkOption**:
- `index.nix` — standard location for directory modules
- `paths.nix` — primitive bootstrap module (see exception below)

**Primitive Module Exception**
The file `domains/paths/paths.nix` is permitted to co-locate option declarations and implementation as the single foundational primitive for universal filesystem abstraction.

Requirements:
1. The file must contain a top-of-file header justifying the exception and referencing this law.
2. The module's scope must remain narrow: path references, overrides, exports, assertions, and only minimal bootstrap tmpfiles.
3. The module must provide a documented, discoverable per-machine override mechanism (e.g., `hwc.paths.overrides`).

**Violation**: `mkOption` in leaf modules, `mkOption` in `parts/*.nix` files, `mkOption` in `sys.nix` (except for `hwc.system.apps.*` options per Law 7).

### Law 11: Domain Evaluation Order

Domains must respect a safe evaluation dependency direction:

```
paths → lib → system → home → [service domains] → secrets
```

Service domains (media, ai, networking, automation, data, monitoring, alerts, gaming, business) may depend on each other but must not create cycles. All service domains may depend on paths, lib, system, and home.

**Violation**: Cyclic dependencies, reverse dependencies (e.g., system depending on media options).

### Law 12: Domain Documentation Contract

Every domain and subdomain **must** have a `README.md` that serves as the canonical reference for that hierarchy's intent, boundaries, and structure.

**Required sections** (minimal, in order):
```markdown
# [Domain/Subdomain Name]

## Purpose
[1-3 sentences: What this hierarchy manages and why it exists]

## Boundaries
- ✅ Manages: [list]
- ❌ Does NOT manage: [list with "→ goes to X" redirects]

## Structure
[Current directory tree or module list]

## Changelog
[Most recent entries first, appended on commits touching this hierarchy]
- YYYY-MM-DD: [Brief description of change]
```

**Update trigger**: When a commit modifies files within a domain/subdomain, the README's Structure and Changelog sections **must** be updated. This is enforced via pre-commit hook, `/commit` skill, or the `readme-butler` tool (`domains/ai/tools/parts/readme-butler.sh`).

**Changelog format**: Single line per logical change. Reference commit hash optional. Pruning permitted after 6 months.

**Violation**: Missing README, missing required section, README not updated after structural changes, changelog older than last structural commit.

**Lint**:
```bash
# Law 12: Domain README presence
for d in domains/*/; do [ -f "$d/README.md" ] || echo "Missing: $d/README.md"; done

# Law 12: Required sections present
rg -L '^## Purpose|^## Boundaries|^## Structure|^## Changelog' domains/*/README.md
```

## 2. Domain Architecture Overview

Each domain has a **unique interaction boundary** with the system.
Domain READMEs contain implementation details, patterns, and known limitations.

### Core Domains

- **domains/paths/** — Universal Filesystem Abstraction
  Boundary: All filesystem paths, mount points, storage tiers, user home detection
  Never contains: Actual service/container config, dotfiles
  Unique: Provides dynamic, centralized, overridable path references used across all other domains

- **domains/lib/** — Shared Pure Helpers
  Boundary: Pure Nix functions, container helpers, reusable patterns
  Never contains: Option declarations, config assignments
  Unique: `mkContainer.nix` (Law 5), `mkInfraContainer.nix`, `arr-config.nix`

- **domains/home/** — User Environment (Home Manager)
  Boundary: User-space configs, DE/WM, apps, dotfiles
  Never contains: systemd.services, environment.systemPackages, users.users
  Unique: sys.nix co-location for system-lane support (Law 7)

- **domains/system/** — Core OS, Hardware & Services
  Boundary: Accounts, networking, security, system packages, GPU, storage tiers, virtualization, peripherals
  Never contains: Home Manager configs, secret declarations
  Subdomains: hardware/ (GPU, drivers), virtualization/ (QEMU/KVM, Podman, WinApps), storage/, services/hardware/

- **domains/secrets/** — Encrypted Secrets (agenix)
  Boundary: Age declarations, encrypted files, /run/agenix facade
  Never contains: Unencrypted values

### Service Domains

- **domains/media/** — Media Services & Containers
  Boundary: Jellyfin, *arr stack, Frigate, Immich, downloaders, media management
  Never contains: Home Manager configs
  Unique: Uses mkContainer helper (Law 5)

- **domains/ai/** — AI/ML Services
  Boundary: Ollama, Open WebUI, AnythingLLM, MCP servers, cloud API integration (Anthropic/OpenAI), local/cloud routing, NanoClaw agent orchestrator, AI CLI tools
  Never contains: Home Manager configs
  Unique: Local-first router with cloud fallback; `domains/ai/nanoclaw/` hosts the NanoClaw AI agent; `domains/ai/tools/` hosts AI CLI tools including `readme-butler` (automated Law 12 changelog updater)

- **domains/networking/** — Network Services
  Boundary: Reverse proxy (Caddy), VPN, Gluetun, Pi-hole, Tailscale routes
  Never contains: Home Manager configs

- **domains/automation/** — Automation & Workflows
  Boundary: n8n, ntfy, scheduled tasks
  Never contains: Home Manager configs

- **domains/data/** — Data Management
  Boundary: Backups (Borg), storage policies, databases
  Never contains: Service configs

- **domains/monitoring/** — Observability
  Boundary: Prometheus, Grafana, exporters, dashboards
  Never contains: Service configs

- **domains/alerts/** — Alerting System
  Boundary: Alert rules, notification routing
  Never contains: Metric collection

### Specialized Domains

- **domains/gaming/** — Gaming & Entertainment
  Boundary: RetroArch, Steam, game servers, WebDAV
  Never contains: Media server configs

- **domains/business/** — Business Tools
  Boundary: Invoicing, CRM, business-specific services
  Never contains: Personal configs

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

# Law 10: Option declaration locality (mkOption only in index.nix, paths.nix, or sys.nix)
rg 'mkOption' domains --type nix --glob '!index.nix' --glob '!domains/paths/paths.nix' --glob '!sys.nix'
rg 'mkOption' domains/*/parts --type nix  # Should find nothing

# Law 7: sys.nix lane purity
rg 'import.*sys.nix' domains/home/*/index.nix

# Law 5: Container standard (check media domain for raw container blocks)
rg 'oci-containers\.containers\.[^=]+=' domains/media --glob '!mkContainer'

# Law 8: Data retention
rg -L 'retain:|retention:|cleanup.timer' domains

# Law 12: Domain README presence and sections
for d in domains/*/; do [ -f "$d/README.md" ] || echo "Missing: $d/README.md"; done
rg -L '^## Purpose|^## Boundaries|^## Structure|^## Changelog' domains/*/README.md
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
- **v11.1 (2026-03-12)**: Incremental updates reflecting post-v11.0 structural changes:
  - **domains/ai/**: Updated boundary description to include NanoClaw agent orchestrator (`domains/ai/nanoclaw/`) and AI CLI tools (`domains/ai/tools/`), including the `readme-butler` tool for automated Law 12 changelog updates
  - **Law 12**: Added `readme-butler` as a third enforcement mechanism alongside pre-commit hook and `/commit` skill
  - Completed `options.nix` → `index.nix` inline migration across all domains (eliminated 37 separate `options.nix` files)
- **v11.0 (2026-03-07)**: Major architecture update reflecting week of refactoring:
  - **Law 6**: Rewrote to require options inline in `index.nix` with `# OPTIONS` section header (eliminated separate `options.nix` pattern)
  - **Law 9**: Updated to reflect directory modules declare options in `index.nix`, not `options.nix`
  - **Law 10**: Rewrote to allow `mkOption` in `index.nix` files (primary location), removed `options.nix` requirement
  - **Law 5**: Updated mkContainer location from `domains/server/containers/_shared/pure.nix` to `domains/lib/mkContainer.nix`
  - **Law 11**: Updated evaluation order to include `lib` domain and clarified service domain dependencies
  - **Domain Architecture**: Removed `domains/server/` (deleted), added `domains/lib/`, `domains/media/`, `domains/networking/`, `domains/automation/`, `domains/data/`, `domains/monitoring/`, `domains/alerts/`, `domains/gaming/`, `domains/business/`
  - Updated mechanical lints for new patterns
- **v10.5 (2026-02-28)**: Completed infrastructure domain migration. All modules from `domains/infrastructure/` now live in `domains/system/`.
- **v10.4 (2026-02-26)**: Added Law 12 (Domain Documentation Contract).
- **v10.3 (2026-01-17)**: Hardened Charter laws for production readiness.
- **v10.2 (2026-01-17)**: Corrected Charter to reflect reality - `domains/infrastructure/` still exists.
- **v10.1 (2026-01-11)**: Added `domains/paths/` as a new domain.
- **v10.0 (2026-01-11)**: Removed all blessed namespace exceptions (Law 2 strict); added Laws 9, 10, 11.
- **v9.1 (2026-01-10)**: Added Law 5 (mkContainer), Law 8 (Retention).
- **v9.0 (2026-01-10)**: Laws + mechanical validation focus.

**End of Charter v11.0**