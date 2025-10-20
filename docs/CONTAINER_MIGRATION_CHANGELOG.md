# Container Migration Changelog

**Project**: Charter v6 Migration - Monolith to Modular Containers
**Scope**: Migration from `/etc/nixos/hosts/server/modules/media-containers.nix` to `domains/server/containers/`

---

## Migration Roadmap

### Phase 1: Foundation & VPN Infrastructure ✅ Complete

#### ✅ Gluetun VPN Container (2025-01-19)
- **Status**: Complete and tested
- **Files Modified**:
  - `domains/server/containers/gluetun/index.nix` - Main module implementation
  - `domains/server/containers/gluetun/parts/config.nix` - Container definition with agenix integration
  - `domains/server/containers/gluetun/sys.nix` - System lane support (conflict resolution)
  - `profiles/server.nix` - Enabled container services import and gluetun
- **Key Changes**:
  - ✅ SOPS → agenix secrets migration (VPN credentials)
  - ✅ Environment file generation from `config.age.secrets.vpn-{username,password}.path`
  - ✅ Proper Charter namespace: `hwc.services.containers.gluetun.enable`
  - ✅ Validation assertions for secrets and Podman backend
  - ✅ Service dependencies: agenix → gluetun-env-setup → podman-gluetun
- **Testing**:
  - ✅ Build succeeds: `sudo nixos-rebuild build --flake .#hwc-server`
  - ✅ Secrets rendered to `/run/secrets/rendered/gluetun.env`
  - ✅ No configuration conflicts

---

### Phase 2: Download Clients (Planned)

#### 🟡 qBittorrent Torrent Client
- **Dependencies**: gluetun (VPN networking)
- **Secrets Required**: None (uses gluetun's VPN connection)
- **Key Features**:
  - Network mode: `--network=container:gluetun`
  - Web UI exposed through gluetun ports
  - Download path: `/mnt/hot/downloads`
  - Config volume: `/opt/downloads/qbittorrent:/config`
- **Migration Pattern**: Extract from monolith `buildDownloadContainer` function

#### 🟡 SABnzbd Usenet Client
- **Dependencies**: gluetun (VPN networking)
- **Critical Mounts**:
  - `/mnt/hot/events:/mnt/hot/events` (event processing - CRITICAL)
  - `/opt/downloads/scripts:/config/scripts:ro` (script access)
- **Key Features**:
  - Network mode: `--network=container:gluetun`
  - Post-processing scripts for media automation
  - Hostname whitelist configuration
- **Migration Notes**: Most complex due to event system integration

---

### Phase 3: Media Management (*arr Stack)

#### 🟡 Prowlarr Indexer Proxy
- **Dependencies**: None (base service)
- **Secrets Required**: API keys for *arr integration
- **Key Features**:
  - Central indexer management
  - Auto-sync to Sonarr/Radarr/Lidarr
  - Authentication: Forms + Enabled

#### 🟡 Sonarr TV Series Management
- **Dependencies**: prowlarr, download clients
- **Secrets Required**: `sonarr-api-key` (from agenix)
- **Key Features**:
  - Media path: `/mnt/media/tv`
  - Processing temp: `/mnt/hot/processing/sonarr-temp`
  - Reverse proxy: `/sonarr` subpath

#### 🟡 Radarr Movie Management
- **Dependencies**: prowlarr, download clients
- **Secrets Required**: `radarr-api-key` (from agenix)
- **Key Features**:
  - Media path: `/mnt/media/movies`
  - Processing temp: `/mnt/hot/processing/radarr-temp`
  - Reverse proxy: `/radarr` subpath

#### 🟡 Lidarr Music Management
- **Dependencies**: prowlarr, download clients
- **Secrets Required**: `lidarr-api-key` (from agenix)
- **Key Features**:
  - Media path: `/mnt/media/music`
  - Processing temp: `/mnt/hot/processing/lidarr-temp`
  - Reverse proxy: `/lidarr` subpath
  - Special: Soularr integration point

---

### Phase 4: Specialized Services

#### 🟡 Soularr Soulseek Integration
- **Dependencies**: lidarr, slskd
- **Secrets Required**: `slskd-api-key`, `lidarr-api-key` (from agenix)
- **Key Features**:
  - Config seeding from secrets to `/data/config.ini`
  - Music discovery automation
  - No web UI (background service)
- **Migration Notes**: Complex config file generation

#### 🟡 SLSKD Soulseek Daemon
- **Dependencies**: None
- **Secrets Required**: `slskd-api-key` (from agenix)
- **Key Features**:
  - P2P music sharing/downloading
  - Web UI at port 5030
  - Download integration with Soularr

#### 🟡 Navidrome Music Server
- **Dependencies**: None
- **Secrets Required**: None (uses initial admin creds)
- **Key Features**:
  - Music streaming from `/mnt/media/music`
  - Web UI at port 4533
  - Reverse proxy: `/navidrome` subpath

---

### Phase 5: Infrastructure Services

#### 🟡 Caddy Reverse Proxy
- **Dependencies**: All container services
- **Current State**: Partially implemented in `domains/server/containers/caddy/`
- **Key Features**:
  - Tailscale HTTPS certificates
  - Subpath routing for all services
  - Load balancing and health checks
- **Migration Notes**: May need coordination with existing Caddy config

---

### Phase 6: Support Services (Planned)

#### 🟡 Media Network Management
- **Current State**: Implemented in `_shared/network.nix`
- **Features**:
  - Creates `media-network` Podman network
  - Idempotent network creation
  - Service dependency management

#### 🟡 Storage Automation
- **Services**:
  - `media-cleanup` (daily temp file removal)
  - `media-migration` (hot→cold storage moves)
  - `storage-monitor` (Prometheus metrics)
- **Migration Pattern**: Extract from monolith systemd services

#### 🟡 Health Monitoring
- **Services**:
  - `arr-health-monitor` (*arr API status checks)
  - Container log rotation
  - Resource usage metrics
- **Integration**: Prometheus/Grafana metrics collection

---

## Migration Validation Protocol

### Per-Service Checklist
- [ ] **Extract Definition**: Container config from monolith
- [ ] **Implement Charter Structure**: options.nix, index.nix, parts/config.nix, sys.nix
- [ ] **Convert Secrets**: SOPS → agenix paths
- [ ] **Resolve Conflicts**: Ensure single container definition
- [ ] **Test Build**: `sudo nixos-rebuild build --flake .#hwc-server`
- [ ] **Enable in Profile**: Add to `profiles/server.nix`
- [ ] **Validate Dependencies**: Network, storage, secrets
- [ ] **System Distiller**: Compare old vs new system state

### Critical Validation Points
1. **Secrets Access**: All agenix paths resolve correctly
2. **Network Isolation**: VPN-routed containers use gluetun network namespace
3. **Volume Mounts**: All critical mounts preserved (especially `/mnt/hot/events`)
4. **Service Ordering**: Dependencies respect startup sequence
5. **Port Exposure**: Only intended ports exposed (security)

### End-to-End Testing
- [ ] **VPN Verification**: Download clients show VPN IP, not local ISP
- [ ] **Media Pipeline**: Download → *arr import → library placement
- [ ] **Web Access**: All services accessible via Tailscale subpaths
- [ ] **Authentication**: Forms auth working on all *arr apps
- [ ] **Mobile Access**: HTTPS certificates valid on mobile devices

---

## Risk Assessment & Mitigation

### High Risk Items
- **SABnzbd Events Mount**: Critical for automation pipeline
- **Service Dependencies**: VPN network isolation must be preserved
- **Secret Access**: agenix paths must be available before container start

### Rollback Strategy
- **Per-Service**: Disable individual services in `profiles/server.nix`
- **Full Rollback**: Remove container imports, return to current config
- **Emergency**: `sudo nixos-rebuild switch --rollback`

### Monitoring Points
- Container startup success rates
- VPN connection stability
- Media processing throughput
- Storage usage patterns

---

## Implementation Timeline

**Estimated**: 2-3 days per phase with testing

1. **Phase 1**: ✅ Complete (Gluetun foundation)
2. **Phase 2**: Download clients (1 day)
3. **Phase 3**: *arr stack (1-2 days)
4. **Phase 4**: Specialized services (1 day)
5. **Phase 5**: Infrastructure (0.5 days)
6. **Phase 6**: Support services (0.5 days)

**Total Estimated**: 4-6 days for complete migration

---

## Success Criteria

### Technical Validation
- All 11 containers migrated to Charter-compliant modules
- 100% functional parity with monolithic configuration
- No SOPS dependencies remaining
- All services accessible via Tailscale with valid HTTPS

### Operational Validation
- Complete media download and processing pipeline functional
- VPN isolation maintained for download clients
- Mobile access working across all services
- Monitoring and automation services operational

### Charter Compliance
- All modules follow Unit Anatomy pattern
- Proper namespace alignment (`hwc.services.containers.*`)
- Validation assertions prevent invalid configurations
- Lane purity maintained (no HM violations)