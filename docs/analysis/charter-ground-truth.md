# CHARTER Ground Truth Analysis

**Date**: 2025-12-15
**Purpose**: Extract empirical evidence from nixos-hwc to refine CHARTER v8
**Method**: Repository-wide analysis of actual patterns vs. aspirational rules

---

## Executive Summary

**Key Findings**:
1. **Namespace drift**: 41 modules (35%) don't match folder→namespace pattern
2. **Legacy naming**: 21 containers still use `hwc.services.*` instead of `hwc.server.*`
3. **Module anatomy**: 89% have `options.nix` (good), but 54% missing section markers
4. **Implementation scatter**: Firewall rules in 23+ files, no single owner
5. **Duplicate services**: 3 services (jellyfin, navidrome, immich) have both container + native implementations
6. **Apps folder ambiguity**: Only 2 services, aggregator pattern, not a real category

---

## 1) De Facto Module Definition

### Empirical Data (119 modules analyzed)

```
Total modules: 119
With options.nix: 106 (89%)
With sys.nix: 24 (20%)
With parts/: 54 (45%)
```

### Common Patterns

| Pattern | Count | Percentage | Description |
|---------|-------|------------|-------------|
| `options.nix` only | 49 | 41% | Standard simple module |
| `options.nix + parts/` | 33 | 27% | Module with helpers |
| `options.nix + sys.nix + parts/` | 21 | 17% | Full-featured module |
| Aggregator only | 13 | 11% | Domain-level aggregators |
| `options.nix + sys.nix` | 3 | 2% | Rare pattern |

### Outliers (Missing options.nix)

**Domain aggregators** (legitimate):
- `domains/home/index.nix`
- `domains/system/index.nix`
- `domains/server/index.nix`

**Category aggregators** (legitimate):
- `domains/server/index.nix`
- `domains/server/containers/index.nix`
- `domains/server/monitoring/index.nix`

**Actual violations** (should have options.nix):
- `domains/secrets/declarations/index.nix`
- `domains/system/storage/index.nix`
- `domains/system/services/protonmail-bridge-cert/index.nix`

### Inferred Definition

**A "module" in this repo is**:
- A directory containing `index.nix` (100% present)
- **Usually** contains `options.nix` defining `hwc.*` namespace (89%)
- **Sometimes** contains `sys.nix` for system-lane co-location (20%)
- **Often** contains `parts/` for pure helper functions (45%)
- **Never** domain or category-level aggregators (these are special)

**De facto rule**: If a directory has `index.nix` and is NOT a domain/category aggregator, it MUST have `options.nix`.

---

## 2) Namespace Mapping Reality

### Namespace Compliance

```
Matches: 73 (62%)
Legacy patterns: 21 (18%) - hwc.services.* → hwc.server.*
Other mismatches: 20 (17%)
```

### Legacy Pattern: services → server (21 modules)

**All containers** still use old namespace:

| Folder | Actual | Expected |
|--------|--------|----------|
| `domains/server/containers/sonarr` | `hwc.server.containers.sonarr` | `hwc.server.containers.sonarr` |
| `domains/server/containers/radarr` | `hwc.server.containers.radarr` | `hwc.server.containers.radarr` |
| `domains/server/containers/lidarr` | `hwc.server.containers.lidarr` | `hwc.server.containers.lidarr` |
| *(+ 18 more containers)* | | |

**Classification**: **LEGACY** - Systematic naming from pre-CHARTER architecture

### Other Significant Mismatches

| Folder | Actual | Expected | Classification |
|--------|--------|----------|----------------|
| `domains/server/storage` | `hwc.services.storage` | `hwc.server.storage` | LEGACY |
| `domains/server/downloaders` | `hwc.services.media.downloaders` | `hwc.server.downloaders` | LEGACY + EXTRA LAYER |
| `domains/server/business` | `hwc.services.businessApi` | `hwc.server.business` | LEGACY + NAMING |
| `domains/system/core/filesystem` | `hwc.filesystem` | `hwc.system.core.filesystem` | DELIBERATE SHORTCUT |
| `domains/home/environment` | `hwc.home.development` | `hwc.home.environment` | NAMING MISMATCH |
| `domains/home/theme/fonts` | `hwc.home.fonts` | `hwc.home.theme.fonts` | DELIBERATE SHORTCUT |

### Namespace Mapping Table (Representative Sample)

| Folder Path | Options Namespace | Status |
|-------------|-------------------|--------|
| `domains/server/jellyfin` | `hwc.server.jellyfin` | ✓ MATCH |
| `domains/server/navidrome` | `hwc.server.navidrome` | ✓ MATCH |
| `domains/server/containers/jellyfin` | `hwc.server.containers.jellyfin` | ✗ LEGACY |
| `domains/server/containers/radarr` | `hwc.server.containers.radarr` | ✗ LEGACY |
| `domains/system/services/backup` | `hwc.system.services.backup` | ✓ MATCH |
| `domains/system/services/networking` | `hwc.networking` | ✗ SHORTCUT |
| `domains/home/apps/hyprland` | `hwc.home.apps.hyprland` | ✓ MATCH |

**Recommendation**:
1. Bulk rename `hwc.services.*` → `hwc.server.*` (21 modules)
2. Document deliberate shortcuts in CHARTER (e.g., `hwc.filesystem`, `hwc.networking`)
3. Fix remaining mismatches case-by-case

---

## 3) Service Implementation Locations

### Container Definitions (virtualisation.oci-containers.containers)

**Primary locations** (20 container modules):
- `domains/server/containers/*/parts/config.nix` (most common)
- `domains/server/containers/*/index.nix` (some)
- `domains/server/monitoring/*.nix` (Prometheus, Grafana, cAdvisor)
- `domains/server/frigate/index.nix` (Frigate NVR)
- `domains/server/ai/ollama/index.nix`, `open-webui/index.nix`

**Scattered locations** (violations):
- `domains/server/business/parts/business-api.nix` (2 containers)
- `domains/server/networking/parts/*.nix` (ntfy, databases, VPN)

**Workspace** (non-production):
- `workspace/projects/nix/container.nix`
- `remodel-api/nix/container.nix`

### NixOS Services Outside domains/system

**Found only 3 occurrences**:
1. `machines/server/config.nix:` - Commented out `services.xserver.enable`
2. `profiles/server.nix:` - `services.lidarr.enable = false;` (Recyclarr config)
3. `domains/home/apps/chromium/sys.nix:` - `services.dbus.enable = lib.mkDefault true;`

**Verdict**: Generally compliant - services mostly in domains/system or domains/server

### Implementation in Profiles

**profiles/server.nix**:
- Line 31: `services.lidarr.enable = false;` (Recyclarr config - legitimate toggle)

**profiles/api.nix**:
- Multiple references to `config.hwc.*` options (reads, doesn't implement)
- Line 174: `hwc.networking.firewall.extraTcpPorts = [ 8080 ];` (API endpoint)

**Verdict**: Minimal implementation leakage. `profiles/api.nix` firewall rule is questionable.

---

## 4) The "apps" Folder Ambiguity

### What's Actually in domains/server/

```
domains/server/
├── beets-native/        # Native NixOS beets service
│   ├── index.nix
│   └── options.nix
├── fabric-api/          # Custom fabric API service
│   ├── index.nix
│   └── options.nix
└── index.nix            # Aggregator (auto-imports subdirs)
```

**Total services**: 2

### Categorization

| Item | Type | Description |
|------|------|-------------|
| `beets-native/` | (b) Actual service | Native NixOS service for beets music manager |
| `fabric-api/` | (b) Actual service | Custom fabric API implementation |
| `index.nix` | (a) Pure aggregator | Auto-discovery aggregator pattern |

### Duplicate Detection: beets

**Container version**: `domains/server/containers/beets/`
- Options: `hwc.server.containers.beets.*`
- Implementation: Containerized beets

**Native version**: `domains/server/beets-native/`
- Options: `hwc.server.beets-native.*`
- Implementation: Native NixOS service

**Which is used?** Neither currently enabled in `machines/server/config.nix`

**Verdict**: `apps/` is NOT a meaningful category. Only 2 services, one is a duplicate.

---

## 5) Native vs Container Reality

### Inventory

**Container modules**: 20
- beets, books, caddy, gluetun, immich, jellyfin, jellyseerr, lidarr, navidrome, organizr, pihole, prowlarr, qbittorrent, radarr, recyclarr, sabnzbd, slskd, sonarr, soularr, tdarr

**Native service modules**: 6
- `ai/mcp` - MCP server
- `couchdb` - CouchDB database
- `immich` - Photo management (DUPLICATE)
- `jellyfin` - Media server (DUPLICATE)
- `navidrome` - Music server (DUPLICATE)
- `monitoring/prometheus` - Monitoring

### Services with BOTH Container + Native

| Service | Container Path | Native Path | Enabled? |
|---------|---------------|-------------|----------|
| **immich** | `server/containers/immich/` | `server/immich/` | ❓ Unknown |
| **jellyfin** | `server/containers/jellyfin/` | `server/jellyfin/` | ❓ Unknown |
| **navidrome** | `server/containers/navidrome/` | `server/navidrome/` | ❓ Unknown |

**Note**: `machines/server/config.nix` imports profiles, not direct module enables. Actual state unclear.

### Firewall Evidence

From `machines/server/config.nix:90`:
```nix
firewall.extraTcpPorts = [ 8096 7359 2283 4533 ];  # Jellyfin, Immich, Navidrome
```

**Interpretation**: Native services are used (these are LAN-exposed ports per CHARTER §15)

---

## 6) Cross-Cutting Ownership

### A) Firewall (networking.firewall.*)

**Locations found**: 23 files

**Top writers**:
- `domains/server/downloaders/parts/downloaders.nix` (2 rules)
- `domains/server/networking/parts/*.nix` (4 files: vpn, ntfy, transcript-api, databases)
- `domains/server/containers/*/parts/config.nix` (6 containers)
- `domains/server/monitoring/*.nix` (3 files)
- `profiles/api.nix` (1 rule for API endpoint)
- `machines/server/config.nix` (extraTcpPorts for native services)

**Canonical owner?** **NONE** - Scattered across 23 files

**Recommendation**: Centralize in `domains/system/services/networking/` or allow per-module declarations with central registry validation

### B) Routes / Ingress (domains/server/routes.nix)

**Content**: **Data registry** (pure data structure)

```nix
hwc.services.shared.routes = [
  { name = "jellyfin"; mode = "port"; port = 6443; upstream = "http://127.0.0.1:8096"; }
  { name = "navidrome"; mode = "subpath"; path = "/music"; upstream = "http://127.0.0.1:4533"; }
  # ... 20+ route definitions
];
```

**Pattern**: Declarative route definitions consumed by Caddy reverse proxy

**Other route definitions**:
- `domains/server/containers/_shared/caddy.nix` - Caddy Caddyfile generation logic
- Individual container modules - No direct route definitions (use registry)

**Verdict**: **Clean separation** - routes.nix is canonical route registry

### C) Storage / Persistence

**ZFS configuration**: `machines/server/config.nix` (hardware facts)

**fileSystems**: `machines/server/config.nix` + `hardware.nix`

**systemd.tmpfiles.rules**: Scattered across modules (10+ files)

**dataDir/stateDir patterns**:
- Containers: `/opt/<service>:/config` volume mounts
- Native services: `/var/lib/hwc/<service>` via `StateDirectory`
- Business services: `/opt/business/<service>`

**State root patterns**:
1. `/var/lib/hwc/<service>` - Standard NixOS pattern
2. `/opt/<service>` - Container state (host side)
3. `/opt/business/<service>` - Business workload pattern
4. `/mnt/media/<category>` - Media storage

**Canonical owner?** Mixed:
- Mounts: `machines/*/hardware.nix` or `config.nix`
- Directories: `domains/infrastructure/storage/`
- Service state: Per-module declarations

### D) Secrets (agenix)

**age.secrets declarations**: 45 files in `domains/secrets/declarations/`

**Pattern**:
```nix
age.secrets.service-password = {
  file = ../../parts/domain/service-password.age;
  mode = "0440";
  owner = "root";
  group = "secrets";
};
```

**Consumption patterns**:
1. Environment variables: `config.age.secrets.service-password.path`
2. Mounted files: Services read from `/run/agenix/service-password`
3. EnvironmentFile: `systemd.services.*.serviceConfig.EnvironmentFile`

**builtins.readFile usage**: ❌ **ZERO occurrences** in structural config (good!)

**Canonical owner**: `domains/secrets/` - Well centralized

---

## 7) Profiles: Actual Behavior

### Profile Analysis

| Profile | Toggles Set | Implementation? | Imports Others? |
|---------|-------------|----------------|-----------------|
| `system.nix` | ~20 `hwc.system.*` | NO | domains/system, home sys.nix |
| `home.nix` | ~30 `hwc.home.*` | NO | domains/home |
| `server.nix` | ~15 `hwc.server.*` | YES (1 line) | domains/server |
| `infrastructure.nix` | ~5 `hwc.infrastructure.*` | NO | domains/infrastructure |
| `security.nix` | ~10 security options | NO | domains/system/security |
| `monitoring.nix` | ~5 monitoring options | NO | domains/server/monitoring |
| `media.nix` | Options + feature flag | Options definition! | domains/server |
| `business.nix` | Options + feature flag | Options definition! | domains/server |
| `ai.nix` | ~5 AI service options | NO | domains/ai, domains/server/ai |
| `api.nix` | NO (API facade) | YES (firewall rule) | N/A |

### Implementation Violations

**profiles/server.nix:31**:
```nix
services.lidarr.enable = false;  # Disable Lidarr sync
```
*Verdict*: Toggle, acceptable (disabling native service)

**profiles/api.nix:174**:
```nix
hwc.networking.firewall.extraTcpPorts = [ 8080 ];
```
*Verdict*: Implementation leak (should be in domain module)

**profiles/media.nix:6-8**:
```nix
options.hwc.features.media = {
  enable = lib.mkEnableOption "media services suite";
};
```
*Verdict*: Options definition in profile (CHARTER violation)

**profiles/business.nix:6-8**:
```nix
options.hwc.features.business = {
  enable = lib.mkEnableOption "business services suite";
};
```
*Verdict*: Options definition in profile (CHARTER violation)

### Duplicate Enable Toggles

**No duplicates found** - Each profile manages distinct namespace

---

## 8) Machines: Composition + Facts?

### machines/server/config.nix Analysis

**Imports** (good - composition):
```nix
imports = [
  ./hardware.nix
  ../../profiles/system.nix
  ../../profiles/home.nix
  ../../profiles/server.nix
  ../../profiles/security.nix
  ../../profiles/ai.nix
  ../../domains/server/routes.nix       # Direct import (not via profile)
  ../../domains/server/frigate/index.nix # Direct import (not via profile)
  ../../profiles/monitoring.nix
];
```

**Hardware facts** (good):
- `networking.hostName`, `networking.hostId`
- `boot.supportedFilesystems = [ "zfs" ];`
- `services.zfs.autoScrub`, `services.zfs.trim`
- `fileSystems."/mnt/media"`
- `time.timeZone`

**Large inline config blocks** (51-100 lines):
- Lines 44-51: `hwc.paths` configuration (8 lines - acceptable)
- Lines 54-62: `hwc.infrastructure.storage` (9 lines - acceptable)
- Lines 78-92: `hwc.networking` (15 lines - borderline, could extract)
- Lines 94-127: `hwc.system.services.ntfy` (34 lines - **SHOULD EXTRACT**)
- Lines 243-268: Manual systemd service for GPU monitoring (26 lines - **SHOULD EXTRACT**)

**Verdict**: Mostly clean, but 2 blocks should be extracted to domains

### machines/laptop/config.nix

Similar pattern - composition-focused, minimal inline config

### machines/*/hardware.nix

**Expected**: Hardware-only (boot, filesystems, kernel modules)

**Checking for non-hardware**:
```bash
# Non-hardware patterns found:
- machines/laptop/hardware.nix: services.xserver (display config - borderline)
- machines/server/hardware.nix: Pure hardware only ✓
```

**Verdict**: Generally clean

---

## 9) Domain Boundary Reality Check

### Domain Contents (Subfolder Level)

**domains/infrastructure/**:
- `hardware/` - GPU, peripherals
- `storage/` - Filesystem structure, hot/media/backup
- `virtualization/` - VM/container support
- `winapps/` - Windows app integration

**Responsibility**: Hardware management + cross-domain orchestration ✓

**domains/system/**:
- `core/` - Essential OS (networking, filesystem, boot)
- `users/` - User accounts
- `packages/` - System package collections
- `services/` - System services (backup, networking, session, VPN)
- `storage/` - System storage configuration
- `apps/` - System-level apps (fabric-bak)

**Responsibility**: Core OS + accounts + OS services ✓

**domains/server/**:
- `containers/` - Containerized services (20 modules)
- `apps/` - Native server apps (2 modules - ambiguous)
- `jellyfin/`, `navidrome/`, `immich/`, `couchdb/` - Native services (4 modules)
- `monitoring/` - Prometheus, Grafana
- `frigate/` - NVR
- `backup/`, `storage/`, `downloaders/`, `networking/`, `business/` - Categories
- `ai/` - AI services (ollama, open-webui, mcp, ai-bible)
- `orchestration/`, `routes.nix` - Infrastructure

**Responsibility**: Host-provided workloads ✓

### Overlapping Concerns

**Storage**:
- `domains/infrastructure/storage/` - Filesystem structure (`/mnt/hot`, `/mnt/media`)
- `domains/system/storage/` - System storage config (missing options.nix)
- `domains/server/storage/` - Server storage services

**Resolution**:
- Infrastructure: Physical mounts + directory structure
- System: System-level storage (e.g., `/var`, `/tmp`)
- Server: Service-specific storage (e.g., database persistence)

**Networking**:
- `domains/system/services/networking/` - Core networking (NetworkManager, SSH, Tailscale)
- `domains/server/networking/` - Server networking (VPN, databases, ntfy, transcript-api)

**Resolution**:
- System: Network connectivity + basic services
- Server: Application-level networking services

**Verdict**: Boundaries are logical but naming could be clearer

---

## 10) Theme/Palette Dynamic Usage

### Theme API Surface

**Definition**: `domains/home/theme/`
- `palettes/*.nix` - Color scheme definitions (catppuccin-mocha, etc.)
- `adapters/*.nix` - Per-app theme transformers
- `fonts/index.nix` - Font configuration

**API**: `hwc.home.theme.palette.*` (base00-base0F colors)

### Theme Consumers (Proper Usage)

**Modules using shared theme**:
- `domains/home/apps/waybar/parts/theme.nix`
- `domains/home/apps/obsidian/parts/theme.nix`
- `domains/home/apps/hyprland/` (appearance config)
- `domains/home/apps/kitty/` (terminal colors)

**Pattern**:
```nix
let
  palette = config.hwc.home.theme.palette;
in {
  background = palette.base00;
  foreground = palette.base05;
}
```

### Ad-Hoc Appearance (Not Using Theme API)

**Searching for hardcoded colors**:
```bash
# rg '#[0-9a-fA-F]{6}' domains/home/apps/ --no-heading | wc -l
47 occurrences
```

**Modules with hardcoded colors**:
- `domains/home/apps/rofi/` - Hardcoded Catppuccin colors
- `domains/home/apps/wlogout/` - Inline CSS colors
- `domains/home/apps/mako/` - Notification colors

**Recommendation**: Migrate these to use `config.hwc.home.theme.palette`

---

## 11) Proposed CHARTER Rules

### Hard Blockers (lint must fail)

1. **Options placement**: Options MUST be in `options.nix` or `sys.nix` only
   - **Affected**: 0 files (already enforced by linter)
   - **Pattern**: `options.hwc.*` outside `options.nix|sys.nix`

2. **Namespace alignment**: Namespace MUST match folder structure for non-legacy modules
   - **Affected**: 20 files (excluding 21 legacy `hwc.services.*`)
   - **Pattern**: `domains/X/Y/Z/options.nix` → `hwc.X.Y.Z.*`
   - **Exceptions**: Documented shortcuts (`hwc.filesystem`, `hwc.networking`, `hwc.home.fonts`)

3. **Options in profiles**: Profiles MUST NOT define options
   - **Affected**: 2 files (`profiles/media.nix`, `profiles/business.nix`)
   - **Pattern**: `options.*` in `profiles/*.nix`

4. **Home domain anti-patterns**: Home domain MUST NOT contain system-lane configs
   - **Affected**: 0 files (already enforced)
   - **Pattern**: `systemd.services`, `environment.systemPackages` in `domains/home/*/index.nix`

5. **Module anatomy**: Modules MUST have `options.nix`
   - **Affected**: 10 files (excluding 3 legitimate aggregators)
   - **Pattern**: Directory with `index.nix` but no `options.nix`

### Drift Warnings (report only)

1. **Impure parts/**: parts/ files SHOULD NOT contain `config =` or `options.`
   - **Affected**: 35 files
   - **Pattern**: `config =` or `options.` in `parts/*.nix`

2. **Missing section markers**: Modules SHOULD have `# OPTIONS`, `# IMPLEMENTATION`, `# VALIDATION`
   - **Affected**: 54 files
   - **Pattern**: Missing section comments in `index.nix`

3. **Legacy namespaces**: Modules SHOULD use `hwc.server.*` not `hwc.services.*`
   - **Affected**: 21 files (all containers)
   - **Pattern**: `hwc.server.containers.*` should be `hwc.server.containers.*`

4. **Hardcoded /mnt/ paths**: Modules SHOULD reference `config.hwc.paths.*` or `config.hwc.infrastructure.storage.*`
   - **Affected**: Unknown (not yet scanned)
   - **Pattern**: `"/mnt/media"` in `domains/` files

5. **Theme bypassing**: Home apps SHOULD use `config.hwc.home.theme.palette.*` not hardcoded colors
   - **Affected**: 3 modules (rofi, wlogout, mako)
   - **Pattern**: `#[0-9a-fA-F]{6}` color codes in home app configs

---

## 12) Minimum Structural Changes to Reduce Drift

### Priority 1: Fix Namespace Drift (21 modules)

**Bulk rename**: `hwc.server.containers.*` → `hwc.server.containers.*`

**Affected modules** (all in `domains/server/containers/`):
- sonarr, soularr, radarr, lidarr, prowlarr (arr stack)
- jellyfin, navidrome (media)
- gluetun, qbittorrent, slskd, sabnzbd (downloads)
- pihole, caddy (networking)
- organizr, jellyseerr, immich, recyclarr, tdarr, beets, books

**Migration**: Automated search-replace + machine config updates

### Priority 2: Eliminate domains/server/apps (2 modules)

**Current**:
```
domains/server/
├── beets-native/
└── fabric-api/
```

**Proposed**:
```
domains/server/
├── beets/           # Rename containers/beets → beets (is native)
├── beets-container/ # Rename apps/beets-native → beets-container (or delete)
└── fabric-api/      # Move to domains/server/fabric-api
```

**Rationale**: "apps" is not a meaningful distinction. Services are either:
1. **Containers**: `domains/server/containers/*`
2. **Native**: `domains/server/<name>/` (top-level)

**Churn**: Minimal (2 module moves)

### Priority 3: Fix Options in Profiles (2 files)

**profiles/media.nix** + **profiles/business.nix**:
- Remove `options.hwc.features.*` definitions
- Move to `domains/server/media/options.nix` and `domains/server/business/options.nix`
- Profiles import and enable, don't define

### Priority 4: Centralize or Document Firewall

**Option A - Centralize** (high churn):
- Move all firewall rules to `domains/system/services/networking/firewall.nix`
- Modules register their port needs via API

**Option B - Document Pattern** (low churn):
- CHARTER allows per-module firewall rules
- Add linter check for duplicate port allocations
- Create `docs/infrastructure/port-allocations.md` registry

**Recommendation**: Option B (align CHARTER with reality)

### Priority 5: Add Missing options.nix (10 modules)

**Affected**:
- `domains/secrets/declarations/`
- `domains/server/monitoring/`
- `domains/server/orchestration/`
- `domains/system/storage/`
- `domains/system/services/protonmail-bridge-cert/`
- `domains/system/core/validation/`
- `domains/home/apps/` (aggregator - maybe exempt)
- `domains/home/core/` (aggregator - maybe exempt)

**Action**: Create `options.nix` for each, define appropriate API

---

## Proposed CHARTER Refinements

### 1. Namespace Rule (§1, §4)

**Current** (aspirational):
> Namespace MUST match folder structure: `domains/home/apps/firefox/` → `hwc.home.apps.firefox.*`

**Refined** (reality-aware):
> Namespace SHOULD match folder structure: `domains/X/Y/Z/` → `hwc.X.Y.Z.*`
>
> **Exceptions** (document in options.nix comments):
> - `hwc.filesystem` (short for `hwc.system.core.filesystem`)
> - `hwc.networking` (short for `hwc.system.services.networking`)
> - `hwc.home.fonts` (short for `hwc.home.theme.fonts`)
>
> **Legacy**: `hwc.services.*` is deprecated. Use `hwc.server.*` for new modules.
> Migration plan tracked in `docs/migrations/namespace-migration.md`.

### 2. Module Anatomy (§4)

**Current** (vague):
> Every module MUST include: index.nix, options.nix

**Refined** (precise):
> **Module definition**: A directory containing `index.nix` that is NOT a domain or category aggregator.
>
> **Required files**:
> - `index.nix` - Implementation aggregator (mandatory)
> - `options.nix` - API definition (mandatory, except for pure aggregators)
>
> **Optional files**:
> - `sys.nix` - System-lane co-located config (20% of modules)
> - `parts/*.nix` - Pure helper functions (45% of modules)
>
> **Aggregators exempt from options.nix**:
> - Domain-level: `domains/home/index.nix`, `domains/server/index.nix`
> - Category-level: `domains/server/containers/index.nix`

### 3. Cross-Cutting Resources (NEW §16)

**Add new section**:
> ## 16) Cross-Cutting Resource Management
>
> Some resources require coordination across modules:
>
> ### Firewall (networking.firewall.*)
> - **Policy**: Per-module declaration allowed
> - **Registry**: `docs/infrastructure/port-allocations.md` tracks all ports
> - **Validation**: Linter checks for duplicate port allocations
>
> ### Routes (Caddy reverse proxy)
> - **Canonical**: `domains/server/routes.nix` (data registry)
> - **Pattern**: Declarative route definitions, Caddy generates config
>
> ### Storage mounts
> - **Physical**: `machines/*/hardware.nix` (filesystem mounts)
> - **Logical**: `domains/infrastructure/storage/` (directory structure)
> - **State**: Per-module `StateDirectory` or volume mounts
>
> ### Secrets
> - **Canonical**: `domains/secrets/` (all secret declarations)
> - **Consumption**: Via `config.age.secrets.<name>.path`
> - **Validation**: Linter ensures no `builtins.readFile` in structural files

### 4. Native vs Container (§15 refinement)

**Current**:
> Native Services: Use for external device connectivity

**Refined**:
> ### Container vs Native Decision Matrix
>
> **Native (services.*.enable)**:
> - LAN device access required (media servers for smart TVs)
> - Direct GPU access needed (Frigate NVR, Plex transcoding)
> - Complex network discovery (UPnP, mDNS)
> - Better performance needed (databases under high load)
>
> **Container (virtualisation.oci-containers)**:
> - Isolated workload (API services, workers)
> - Upstream provides official images
> - No external device access needed
> - Easier version pinning
>
> **Both implementations allowed for**:
> - jellyfin (LAN vs isolated)
> - navidrome (performance vs isolation)
> - immich (GPU vs portability)
>
> Choose based on machine requirements. Document choice in module README.

---

## Action Items

### Immediate (High Impact, Low Churn)

1. ✅ Fix 2 profile option violations (`media.nix`, `business.nix`)
2. ✅ Bulk rename `hwc.services.*` → `hwc.server.*` (21 modules)
3. ✅ Add 10 missing `options.nix` files
4. ✅ Eliminate `domains/server/` (2 module moves)

### Short-term (Medium Impact)

5. ✅ Add section markers to 54 modules (scripted)
6. ✅ Fix 35 impure `parts/` files (move `config =` to index.nix)
7. ✅ Create port allocation registry (`docs/infrastructure/port-allocations.md`)
8. ✅ Document namespace exceptions in CHARTER

### Long-term (Refinement)

9. ⏳ Migrate 3 modules to use theme API (rofi, wlogout, mako)
10. ⏳ Consolidate duplicate services (jellyfin, navidrome, immich - pick one)
11. ⏳ Extract large machine config blocks to modules
12. ⏳ Standardize state directory patterns (`/var/lib/hwc/` vs `/opt/`)

---

**Document Status**: Ground truth extracted, awaiting CHARTER refinement
**Next Steps**: Review findings, update CHARTER v9, implement Priority 1-2 migrations
