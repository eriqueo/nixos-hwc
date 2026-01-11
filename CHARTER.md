# HWC Architecture Charter v10.1

**Owner**: Eric  
**Scope**: `nixos-hwc/` — all machines, domains, profiles, Home Manager, and supporting files  
**Goal**: Deterministic, maintainable, scalable, reproducible NixOS configuration via strict domain separation, explicit APIs, and user-centric organization.  
**Philosophy**: This document defines **enforceable architectural laws**. Implementation details, patterns, and domain-specific guidance live in domain READMEs and `docs/patterns/`.  
**Current Date**: January 11, 2026

## 0. Preserve-First Doctrine

- Refactor = reorganize, **never rewrite**.
- Maintain 100% feature parity during migrations.
- Temporary wrappers/adapters must be tracked and eventually removed.
- Never deploy/switch on failing builds.

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

**All assertions and `osConfig` accesses must be guarded**:
```nix
assertions = lib.mkIf isNixOS [ ... ];
# or
osConfig.hwc.something or null
```

**Violation**: Unguarded `osConfig` access or assertion that fails when `osConfig = {}`.

### Law 2: 1:1 Namespace Fidelity

Option namespace **must exactly match** folder path.

Examples:  
`domains/home/apps/firefox/` → `hwc.home.apps.firefox.*`  
`domains/system/core/paths/` → `hwc.system.core.paths.*`

**Permanent blessed exceptions**:
- `hwc.paths` (universal path facade)
- `hwc.filesystem` (short for `hwc.system.core.filesystem`)
- `hwc.networking` (short for `hwc.system.services.networking`)
- `hwc.home.fonts` (short for `hwc.home.theme.fonts`)

**Violation**: Use of deprecated (`hwc.services.*`, `hwc.features.*`) or mismatched namespaces.

### Law 3: Path Abstraction Contract

**No filesystem paths may be hardcoded** outside `domains/system/core/paths.nix`.

**Correct**:
```nix
volumes = [ "${config.hwc.paths.media.music}:/music:ro" ];
```

**Incorrect**:
```nix
volumes = [ "/mnt/media/music:/music:ro" ];
```

**paths.nix guarantees**:
- Auto-detection of primary user/home
- Home-relative defaults for all storage tiers (`~/storage/hot`, etc.)
- Absolute path assertions
- No `null` defaults (use overrides in machines)

**Violation**: Any hardcoded `/mnt/`, `/home/eric/`, `/opt/` (except in `paths.nix` itself and documentation).

### Law 4: Unified Permission Model (1000:100)

All services **must** run as primary user (UID 1000) : `users` group (GID 100).

**Containers**:
```nix
environment.PUID = "1000";
environment.PGID = "100";  # NOT 1000!
```

**Native services**:
```nix
serviceConfig = {
  User = lib.mkForce "eric";
  Group = lib.mkForce "users";
  StateDirectory = "hwc/<service>";
};
```

**Secrets**:
```nix
age.secrets.<name> = {
  mode = "0440";
  owner = "root";
  group = "secrets";
};
```

**Violation**: PGID=1000, missing `secrets` group membership, secrets without 0440 mode.

### Law 5: Container Standard (mkContainer)

All OCI containers **must** use the `mkContainer` pure helper unless explicitly justified.

Location: `domains/server/containers/_shared/pure.nix`

**Guarantees**:
- PUID=1000, PGID=100
- TZ from host
- Consistent health-check pattern
- Minimal privileged flags

**Violation**: Raw `virtualisation.oci-containers.containers` blocks without justification comment.

### Law 6: Three Sections & Validation Discipline

Every `index.nix` **must** contain exactly three sections:

```nix
# OPTIONS (mandatory)
imports = [ ./options.nix ];

# IMPLEMENTATION (mandatory)
config = lib.mkIf cfg.enable { ... };

# VALIDATION (mandatory when dependencies exist)
config.assertions = lib.mkIf cfg.enable [ ... ];
```

**Violation**: Missing section, options outside `options.nix`, unguarded assertions.

### Law 7: sys.nix Lane Purity

Co-located `sys.nix` files in home domains belong **exclusively** to system lane.

**Rules**:
- `sys.nix` defines `hwc.system.apps.<name>.*` options
- Home `index.nix` **never** imports `sys.nix`
- System cannot depend on home options (evaluation order)

**Violation**: Home → system import, system → home dependency, `sys.nix` using `hwc.home` options.

### Law 8: Data Retention Contract

All persistent data stores **must** declare retention policy in Nix.

**Minimum**:
- Application-level retention (in config file or Nix option)
- Fail-safe systemd timer for cleanup

**Classification** (documented in module):
- CRITICAL: indefinite + backup
- REPLACEABLE: indefinite, no backup
- AUTO-MANAGED: time/size limited

**Violation**: Persistent volume without documented retention + timer.

### Law 9: Filesystem Materialization Discipline

Directory materialization for core paths **must** live in `domains/system/core/filesystem.nix`.

**Requirements**:
- Use systemd.tmpfiles for minimal bootstrap directories.
- Keep tmpfiles entries minimal and path-derived from `config.hwc.paths.*`.

**Violation**: Ad-hoc tmpfiles entries in unrelated modules for core path creation.

### Law 10: Primitive Module Exception

**Primitive Module Exception (sole current exception)**

The file `domains/paths/paths.nix` is permitted to co-locate option declarations and implementation
as the single foundational primitive for universal filesystem abstraction.

Requirements:

1. The file must contain a top-of-file header justifying the exception and referencing this law.
2. The module's scope must remain narrow: path references, overrides, exports, assertions, and only
   minimal bootstrap tmpfiles. The module must not grow payload (dotfiles/templates).
3. The module must provide a documented, discoverable per-machine override mechanism
   (e.g., `hwc.paths.overrides`) that supports nested/recursive overrides.
4. The mechanical linter suite may whitelist this file for the `mkOption` rule; no other file
   is exempt.
5. The exception is revocable: if the module acquires payload or grows complex, it must be split
   into `options.nix` + `index.nix` + `parts/` and this exception removed.

## 2. Domain Architecture Overview

Each domain has a **unique interaction boundary** with the system.  
Domain READMEs contain implementation details, patterns, and known limitations.

- **domains/home/** — User Environment (Home Manager)  
  Boundary: User-space configs, DE/WM, apps, dotfiles  
  Never contains: systemd.services, environment.systemPackages, users.users  
  Unique: sys.nix co-location for system-lane support (Law 7)

- **domains/system/** — Core OS & Services  
  Boundary: Accounts, networking, security, system packages  
  Never contains: Home Manager configs, secret declarations  
  Unique: paths.nix universal abstraction (Law 3)

- **domains/infrastructure/** — Hardware & Cross-Domain Orchestration  
  Boundary: GPU, power, virtualization, filesystem structure  
  Never contains: Home Manager configs, high-level apps

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
rg 'osConfig\.' domains/home --type nix | rg -v '\?|\bor false'
rg 'hwc\.services\.|hwc\.features\.' domains
rg '="/mnt/|="/home/eric/|="/opt/' domains --glob '!paths.nix' --glob '!*.md'
./workspace/utilities/lints/permission-lint.sh
rg 'options\.hwc\.' domains --type nix --glob '!options.nix' --glob '!sys.nix' --glob '!paths/paths.nix'
rg 'import.*sys.nix' domains/home/*/index.nix
rg 'oci-containers\.containers\.[^=]+=' domains/server --glob '!mkContainer'
rg -L 'retain:|retention:|cleanup.timer' domains/server
```

## 4. Enforcement Levels

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
- **v10.1 (2026-01-11)**: Added Law 9 (Filesystem Materialization) and Law 10 (Primitive Module Exception)  
- **v9.1 (2026-01-10)**: Added Law 5 (mkContainer), Law 8 (Retention), refined violation searches, enforcement levels  
- **v9.0 (2026-01-10)**: Laws + mechanical validation focus

**End of Charter v10.1**
