# NixOS HWC: DDD Refactor Plan v3

## 1. Strategic Goal

Evolve nixos-hwc from a monolithic `domains/server/` architecture to a pure
capability-stack model. A machine's identity no longer defines its capabilities.
Instead, machines compose directly from self-contained domains.

## 2. The Three-Layer Architecture

```
Layer 3: machines/    "I am hwc-server. Here are my disks, my GPU, my paths."
                      Imports profiles + domains directly. Enables specific services.

Layer 2: profiles/    RARE cross-domain glue. Only two survive:
                      core.nix (every machine) and session.nix (GUI machines).

Layer 1: domains/     Self-contained capabilities. Everything OFF by default.
                      Each domain owns its options, containers, native services,
                      and directory setup.
```

**Key rules:**
- Domains default everything to `false/null`. Machines or profiles enable with `mkDefault`.
- No `isPrimary`. No `hwc.server.role`. Each machine declares exactly what it uses.
- Profiles are NOT 1:1 domain wrappers. If a machine needs one domain, it imports that domain directly.
- Container definitions live inside their domain (e.g., `domains/media/jellyfin/` contains the container spec). Pure container helpers (`mkContainer`, `mkInfraContainer`) live in `lib/`.

---

## 3. Final Architecture

### 3.1 Profiles (Layer 2) — Only Two

#### `profiles/core.nix`
**Replaces:** system.nix, base.nix, and absorbs secrets from security.nix

Cross-domain bundle that every machine imports:
- Imports `domains/system/index.nix`
- Imports `domains/paths/paths.nix`
- Imports `domains/secrets/index.nix`
- Preserves the `gatherSys` auto-discovery pattern (Charter Law 7)
- Sets universal defaults: nix settings, garbage collection, fstrim, timezone
- Enables shell, users, networking, SSH

#### `profiles/session.nix`
**Replaces:** home.nix

Cross-domain bundle for human-facing machines (laptop, xps, gaming):
- Sets up `home-manager.users.eric` with `domains/home/index.nix` import
- Enables audio (`hwc.system.services.hardware.audio.enable = mkDefault true`)
- Enables display manager (`hwc.system.services.session.loginManager.enable = mkDefault true`)
- Sets GUI app defaults (hyprland, waybar, kitty, browsers, etc.)
- Enables fonts, theme

**Server never imports session.nix** — so it never inherits GUI defaults, eliminating
the 30+ `mkForce false` lines.

#### Eliminated profiles:
- `base.nix` — dead code, never imported by any machine
- `server.nix` — machines import domains directly
- `security.nix` — secrets absorbed into core.nix
- `monitoring.nix` — 1:1 wrapper, machines import domains/monitoring directly
- `media.nix` — 1:1 wrapper, machines import domains/media directly
- `alerts.nix` — 1:1 wrapper, machines import domains/alerts directly
- `business.nix` — 1:1 wrapper, machines import domains/business directly
- `ai.nix` — 1:1 wrapper, machines import domains/ai directly
- `gaming.nix` — absorbed into machine configs (it sets auto-login, performance tuning, audio — these are machine-specific)
- `firestick.nix` — absorbed into machine config
- `api.nix` — absorbed into machine config or networking domain
- `home.nix` — replaced by session.nix

### 3.2 Domains (Layer 1) — Final List

```
domains/
├── system/           # UNCHANGED. OS primitives, hardware, virtualization, services.
│   ├── core/         #   identity, packages
│   ├── hardware/     #   gpu, drivers
│   ├── networking/   #   SSH, tailscale, firewall, samba
│   ├── services/     #   shell, session, hardware (audio/bluetooth), backup, ntfy, polkit, vpn
│   ├── storage/      #   mount management
│   ├── users/        #   account creation
│   └── virtualization/ # QEMU/KVM, Podman, WinApps
│
├── paths/            # UNCHANGED. Path definitions per Charter v10.1.
├── secrets/          # UNCHANGED. Agenix integration.
├── home/             # UNCHANGED. Home Manager context.
│
├── networking/       # NEW. All network infrastructure.
│   ├── caddy/        #   Reverse proxy (owns hwc.networking.reverseProxy.*)
│   ├── pihole/       #   DNS filtering
│   ├── gluetun/      #   VPN container for download stack
│   ├── routes/       #   Route definitions (from domains/server/native/routes.nix)
│   └── podman-network/ # media-network systemd service
│
├── media/            # NEW. All entertainment services.
│   ├── jellyfin/
│   ├── jellyseerr/
│   ├── navidrome/
│   ├── sonarr/
│   ├── radarr/
│   ├── lidarr/
│   ├── prowlarr/
│   ├── readarr/
│   ├── qbittorrent/
│   ├── sabnzbd/
│   ├── audiobookshelf/
│   ├── immich/
│   ├── frigate/
│   ├── tdarr/
│   ├── organizr/
│   ├── mousehole/
│   ├── pinchflat/
│   ├── beets/
│   ├── slskd/
│   ├── soularr/
│   ├── recyclarr/
│   ├── calibre/
│   ├── books/
│   ├── youtube/
│   ├── downloaders/
│   └── orchestrator/
│
├── monitoring/       # NEW. Observability stack.
│   ├── prometheus/
│   ├── grafana/
│   ├── alertmanager/
│   ├── cadvisor/
│   └── exportarr/
│
├── data/             # NEW. Data infrastructure.
│   ├── databases/    #   PostgreSQL, Redis
│   ├── backup/       #   from server/native/backup
│   ├── storage/      #   from server/native/storage
│   └── couchdb/      #   from server/native/couchdb
│
├── ai/               # EXISTS. Merge server/native/ai into it.
│
├── alerts/           # EXISTS. Stays as-is. Remove profile wrapper.
│
├── automation/       # NEW. Workflow automation.
│   └── n8n/          #   from server/native/n8n
│
├── business/         # EXISTS. Update internal refs to new namespaces.
│
└── gaming/           # NEW.
    ├── retroarch/    #   from server/native/retroarch
    └── webdav/       #   from server/native/webdav (RetroArch save sync)
```

### 3.3 Container Helpers (`lib/`)

Pure, importable helper functions. No NixOS module options — just functions.

```
lib/
├── mkContainer.nix       # from _shared/pure.nix
├── mkInfraContainer.nix  # from _shared/infra.nix
└── arr-config.nix        # from _shared/arr-config.nix
```

Each domain that uses containers calls `import ../../lib/mkContainer.nix { inherit lib pkgs; }`.
Each domain manages its own tmpfiles/directories inside its own module.

### 3.4 Namespace Migration Map

| Current | Target |
|---------|--------|
| `hwc.server.enable` | **DELETED** |
| `hwc.server.role` | **DELETED** |
| `hwc.server.reverseProxy.*` | `hwc.networking.reverseProxy.*` |
| `hwc.server.shared.*` | `hwc.networking.shared.*` |
| `hwc.server.storage.*` | `hwc.data.storage.*` |
| `hwc.features.monitoring.*` | **DELETED** (direct enablement) |
| `hwc.server.containers.jellyfin.*` | `hwc.media.jellyfin.*` |
| `hwc.server.containers.jellyseerr.*` | `hwc.media.jellyseerr.*` |
| `hwc.server.containers.sonarr.*` | `hwc.media.sonarr.*` |
| `hwc.server.containers.radarr.*` | `hwc.media.radarr.*` |
| `hwc.server.containers.lidarr.*` | `hwc.media.lidarr.*` |
| `hwc.server.containers.prowlarr.*` | `hwc.media.prowlarr.*` |
| `hwc.server.containers.readarr.*` | `hwc.media.readarr.*` |
| `hwc.server.containers.qbittorrent.*` | `hwc.media.qbittorrent.*` |
| `hwc.server.containers.sabnzbd.*` | `hwc.media.sabnzbd.*` |
| `hwc.server.containers.audiobookshelf.*` | `hwc.media.audiobookshelf.*` |
| `hwc.server.containers.immich.*` | `hwc.media.immich.*` |
| `hwc.server.containers.tdarr.*` | `hwc.media.tdarr.*` |
| `hwc.server.containers.organizr.*` | `hwc.media.organizr.*` |
| `hwc.server.containers.mousehole.*` | `hwc.media.mousehole.*` |
| `hwc.server.containers.pinchflat.*` | `hwc.media.pinchflat.*` |
| `hwc.server.containers.beets.*` | `hwc.media.beets.*` |
| `hwc.server.containers.slskd.*` | `hwc.media.slskd.*` |
| `hwc.server.containers.soularr.*` | `hwc.media.soularr.*` |
| `hwc.server.containers.recyclarr.*` | `hwc.media.recyclarr.*` |
| `hwc.server.containers.calibre.*` | `hwc.media.calibre.*` |
| `hwc.server.containers.books.*` | `hwc.media.books.*` |
| `hwc.server.containers.navidrome.*` | `hwc.media.navidrome.*` |
| `hwc.server.containers.caddy.*` | `hwc.networking.caddy.*` |
| `hwc.server.containers.pihole.*` | `hwc.networking.pihole.*` |
| `hwc.server.containers.gluetun.*` | `hwc.networking.gluetun.*` |
| `hwc.server.containers.paperless.*` | `hwc.business.paperless.*` |
| `hwc.server.containers.firefly.*` | `hwc.business.firefly.*` |
| `hwc.server.native.monitoring.*` | `hwc.monitoring.*` |
| `hwc.server.native.jellyfin.*` | `hwc.media.jellyfin.*` |
| `hwc.server.native.navidrome.*` | `hwc.media.navidrome.*` |
| `hwc.server.native.immich.*` | `hwc.media.immich.*` |
| `hwc.server.native.frigate.*` | `hwc.media.frigate.*` |
| `hwc.server.native.media.*` | `hwc.media.*` |
| `hwc.server.native.ai.*` | `hwc.ai.*` (merge into existing) |
| `hwc.server.native.backup.*` | `hwc.data.backup.*` |
| `hwc.server.native.storage.*` | `hwc.data.storage.*` |
| `hwc.server.native.couchdb.*` | `hwc.data.couchdb.*` |
| `hwc.server.native.n8n.*` | `hwc.automation.n8n.*` |
| `hwc.server.native.orchestration.*` | `hwc.media.orchestrator.*` |
| `hwc.server.native.youtube.*` | `hwc.media.youtube.*` |
| `hwc.server.native.retroarch.*` | `hwc.gaming.retroarch.*` |
| `hwc.server.native.webdav.*` | `hwc.gaming.webdav.*` |
| `hwc.server.native.networking.*` | **DELETED** (deprecated, empty) |
| `hwc.server.native.downloaders.*` | `hwc.media.downloaders.*` |
| `hwc.server.databases.*` | `hwc.data.databases.*` |

### 3.5 Machine Composition — Final Form

#### `machines/server/config.nix`
```nix
imports = [
  ./hardware.nix
  ../../profiles/core.nix
  # Server does NOT import session.nix — no GUI, no mkForce false needed

  # Domains — server picks exactly what it needs
  ../../domains/networking/index.nix
  ../../domains/media/index.nix
  ../../domains/monitoring/index.nix
  ../../domains/data/index.nix
  ../../domains/ai/index.nix
  ../../domains/alerts/index.nix
  ../../domains/automation/index.nix
  ../../domains/business/index.nix
  ../../domains/gaming/index.nix
];

# Machine identity
networking.hostName = "hwc-server";

# Machine-specific paths
hwc.paths.hot.root = "/mnt/hot";
hwc.paths.media.root = "/mnt/media";

# Machine-specific hardware
hwc.system.hardware.gpu = { enable = true; type = "nvidia"; ... };

# Enable exactly the services this machine runs
hwc.media.jellyfin.enable = true;
hwc.media.sonarr.enable = true;
hwc.monitoring.prometheus.enable = true;
hwc.networking.reverseProxy.enable = true;
# ... etc
```

#### `machines/laptop/config.nix`
```nix
imports = [
  ./hardware.nix
  ../../profiles/core.nix
  ../../profiles/session.nix    # GUI machine — gets desktop, audio, display
  ../../domains/ai/index.nix    # Only domain laptop needs directly
];

networking.hostName = "hwc-laptop";
hwc.paths.hot.root = "/home/eric/500_media/hot";
hwc.ai.enable = true;
hwc.ai.ollama.enable = false;   # Laptop doesn't run Ollama by default
```

#### `machines/xps/config.nix`
```nix
imports = [
  ./hardware.nix
  ../../profiles/core.nix
  ../../profiles/session.nix
  ../../domains/networking/index.nix
  ../../domains/data/index.nix
  ../../domains/ai/index.nix
];
# XPS runs a subset of server services — just import what it needs
hwc.data.couchdb.enable = true;
hwc.networking.reverseProxy.enable = true;
```

#### `machines/gaming/config.nix`
```nix
imports = [
  ./hardware.nix
  ../../profiles/core.nix
  ../../profiles/session.nix
];
# Simple gaming box — session profile gives it GUI, no extra domains needed
# Machine-specific: auto-login, performance tuning, bluetooth
```

#### `machines/firestick/config.nix`
```nix
imports = [
  ./hardware.nix
  ../../profiles/core.nix
];
# Lean travel stick — just core, Tailscale only
```

---

## 4. Implementation Phases

Every phase ends with `nix flake check` passing. No "break everything" commits.

### Phase 0: Clean Dead Code
**Goal:** Remove noise before the real work starts.

1. Delete `profiles/base.nix` (dead code, never imported).
2. Remove `hwc.features.monitoring.enable` from `profiles/monitoring.nix` — replace with direct option enablement.
3. Remove `hwc.features.monitoring.enable = true` from both machine configs.
4. Delete deprecated `domains/server/native/networking/options.nix` (empty, already migrated).
5. `nix flake check` must pass.
6. Commit: `chore: remove dead code and deprecated hwc.features namespace`

### Phase 1: Create New Profiles
**Goal:** Establish core.nix and session.nix without breaking existing imports.

1. Create `profiles/core.nix`:
   - Copy content from `profiles/system.nix`
   - Add imports for `domains/paths/` and `domains/secrets/`
   - Preserve `gatherSys` pattern
   - Remove audio/display defaults (those move to session.nix)
   - Remove hardcoded Samba share, protonmail-bridge wrapper, autoLoginUser
2. Create `profiles/session.nix`:
   - Move `home-manager.users.eric` setup from `profiles/home.nix`
   - Add audio, display manager, font, theme defaults
   - Add GUI app defaults (hyprland, waybar, kitty, browsers, etc.)
3. Update machine configs to import `core.nix` + `session.nix` instead of `system.nix` + `home.nix` + `security.nix`.
4. Non-GUI machines (server, firestick) import only `core.nix`.
5. Keep old profiles temporarily — machines still import `server.nix`, `monitoring.nix`, etc. for now.
6. `nix flake check` + build test.
7. Commit: `feat(profiles): create core.nix and session.nix, replace system/home/security`

### Phase 2: Container Helpers to `lib/`
**Goal:** Extract pure container helpers so domains can use them independently.

1. Create `lib/` directory.
2. Copy `_shared/pure.nix` → `lib/mkContainer.nix`
3. Copy `_shared/infra.nix` → `lib/mkInfraContainer.nix`
4. Copy `_shared/arr-config.nix` → `lib/arr-config.nix`
5. Update existing container modules to import from `lib/` instead of `_shared/`.
6. Keep `_shared/` files in place temporarily (old imports still work).
7. `nix flake check` must pass.
8. Commit: `feat(lib): extract pure container helpers to lib/`

### Phase 3: Create `domains/networking/`
**Goal:** Networking is the backbone — most domains need reverse proxy routes.

1. Create `domains/networking/` with `index.nix`, `options.nix`.
2. Move `_shared/caddy.nix` → `domains/networking/caddy/`
3. Move `_shared/lib.nix` → `domains/networking/routes/` (route accumulator)
4. Move `_shared/network.nix` → `domains/networking/podman-network/`
5. Move `domains/server/native/routes.nix` → `domains/networking/routes/`
6. Move `domains/server/containers/caddy/` → `domains/networking/caddy/`
7. Move `domains/server/containers/pihole/` → `domains/networking/pihole/`
8. Move `domains/server/containers/gluetun/` → `domains/networking/gluetun/`
9. Migrate namespace: `hwc.server.reverseProxy.*` → `hwc.networking.reverseProxy.*`
10. Migrate namespace: `hwc.server.shared.*` → `hwc.networking.shared.*`
11. Update all 14+ files that reference these namespaces.
12. Update machine configs: add `../../domains/networking/index.nix` to imports, remove networking bits from server.nix.
13. `nix flake check` + build test.
14. Commit: `feat(networking): create networking domain, migrate reverseProxy namespace`

### Phase 4: Create `domains/monitoring/`
**Goal:** Self-contained observability. Simplest domain to migrate after networking.

1. Move `domains/server/native/monitoring/` → `domains/monitoring/`
2. Migrate namespace: `hwc.server.native.monitoring.*` → `hwc.monitoring.*`
3. Move n8n alertmanager webhook config to machine config (it's machine-specific: the webhook URL).
4. Delete `profiles/monitoring.nix` wrapper.
5. Update machine configs to import `domains/monitoring/index.nix` directly.
6. `nix flake check` + build test.
7. Commit: `feat(monitoring): create monitoring domain`

### Phase 5: Create `domains/data/`
**Goal:** Consolidate data infrastructure.

1. Move `domains/server/databases/` → `domains/data/databases/`
2. Move `domains/server/native/backup/` → `domains/data/backup/`
3. Move `domains/server/native/storage/` → `domains/data/storage/`
4. Move `domains/server/native/couchdb/` → `domains/data/couchdb/`
5. Migrate namespaces: `hwc.server.databases.*` → `hwc.data.databases.*`, etc.
6. Update machine configs.
7. `nix flake check` + build test.
8. Commit: `feat(data): create data domain`

### Phase 6: Create `domains/automation/`
**Goal:** Separate n8n from monitoring.

1. Move `domains/server/native/n8n/` → `domains/automation/n8n/`
2. Migrate namespace: `hwc.server.native.n8n.*` → `hwc.automation.n8n.*`
3. Update monitoring's alertmanager config to reference new n8n namespace.
4. Update machine configs.
5. `nix flake check` + build test.
6. Commit: `feat(automation): create automation domain for n8n`

### Phase 7: Create `domains/media/`
**Goal:** Largest migration. Move in batches.

**Note:** Resolve the sops/agenix conflict (stable vs unstable `age.secrets` paths) during this phase. The media orchestrator was likely developed against unstable — verify and fix for stable.

**Batch 7a: Streaming services**
- Move jellyfin (container + native), navidrome (container + native), audiobookshelf, jellyseerr
- Migrate namespaces
- Test + commit

**Batch 7b: Acquisition stack**
- Move sonarr, radarr, lidarr, prowlarr, readarr, qbittorrent, sabnzbd
- Migrate namespaces
- Test + commit

**Batch 7c: Processing + utilities**
- Move tdarr, organizr, mousehole, pinchflat, beets, recyclarr, slskd, soularr, calibre, books
- Migrate namespaces
- Test + commit

**Batch 7d: Photos, video, downloads**
- Move immich (container + native), frigate, youtube, downloaders, orchestrator
- Migrate namespaces
- Test + commit

Each batch: `feat(media): migrate [batch description]`

### Phase 8: Update Existing Domains
**Goal:** Fix domains that already exist at top level but reference old namespaces.

1. `domains/alerts/` — Remove `profiles/alerts.nix` wrapper. Update any `hwc.server.*` references.
2. `domains/business/` — Update refs from `hwc.server.containers.paperless` → `hwc.business.paperless`, `hwc.server.containers.firefly` → `hwc.business.firefly`. Move container definitions from `domains/server/containers/paperless/` and `domains/server/containers/firefly/` into `domains/business/`.
3. `domains/ai/` — Merge `domains/server/native/ai/` into existing `domains/ai/`. Remove duplicates.
4. `nix flake check` + build test.
5. Commit per domain.

### Phase 9: Create `domains/gaming/`
**Goal:** Small, isolated domain.

1. Move `domains/server/native/retroarch/` → `domains/gaming/retroarch/`
2. Move `domains/server/native/webdav/` → `domains/gaming/webdav/`
3. Migrate namespaces.
4. Absorb relevant parts of `profiles/gaming.nix` machine-specific config into `machines/gaming/config.nix`.
5. Delete `profiles/gaming.nix`.
6. `nix flake check` + build test.
7. Commit: `feat(gaming): create gaming domain`

### Phase 10: Gut `profiles/server.nix` and Delete `domains/server/`
**Goal:** Remove the old architecture entirely.

1. By this point, all services have been migrated out of `domains/server/`.
2. Verify `domains/server/` is empty (or contains only `options.nix` and `index.nix` stubs).
3. Delete `domains/server/` entirely.
4. Delete `profiles/server.nix`.
5. Delete `hwc.server.enable`, `hwc.server.role` option definitions.
6. Delete remaining old profile files (`profiles/api.nix`, `profiles/firestick.nix`, etc.).
7. Remove `_shared/` directory (helpers already in `lib/`).
8. `nix flake check` + full build test on ALL 5 machines.
9. Commit: `feat: complete DDD refactor, delete domains/server and profiles/server`

### Phase 11: Final Polish
1. Update `README.md` in every domain (Charter Law 12).
2. Update `CHARTER.md` to codify the three-layer architecture.
3. Search for any remaining `hwc.server.*` or `hwc.features.*` references.
4. Final `nix flake check` + `nixos-rebuild test` on all machines.
5. Commit: `docs: update charter and domain READMEs for DDD architecture`

---

## 5. Validation Checklist

Every phase must pass before proceeding:
- [ ] `nix flake check` passes
- [ ] No `hwc.server.*` namespaces remain (after Phase 10)
- [ ] No `hwc.features.*` namespaces remain (after Phase 0)
- [ ] No `isPrimary` conditionals remain
- [ ] No `profiles/server.nix` import anywhere
- [ ] Server config has zero `mkForce false` for GUI apps
- [ ] All 5 machines build cleanly
- [ ] Namespace matches folder path (Charter Law 2): `domains/media/jellyfin/` → `hwc.media.jellyfin.*`

## 6. Rollback Strategy

Each phase is a single commit (or small group of commits for Phase 7). Any phase can be reverted with `git revert` without affecting other phases.

## 7. Open Questions (To Resolve During Implementation)

1. **sops/agenix conflict** — The media orchestrator may use `age.secrets` paths that assume unstable. Need to verify and fix for stable during Phase 7.
2. **Podman config** — Currently in `profiles/server.nix`. Should move to `domains/system/virtualization/` since it's a system-level runtime, not a server concern. All machines that run containers need it.
3. **Server-specific kernel tuning** — Currently in `profiles/server.nix` (sysctl, I/O schedulers, smartd, journald). These are machine-specific and should move to `machines/server/config.nix`.
4. **Home Manager on server** — Server currently imports `profiles/home.nix` for CLI tools (shell, git, aider). With session.nix owning the HM setup, how does server get CLI-only HM? Options: (a) core.nix includes a minimal HM setup for CLI, (b) server imports domains/home directly with no GUI defaults, (c) server gets its own minimal HM block.
