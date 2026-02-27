# Container Consistency Analysis

**Date**: 2025-11-18
**Status**: Container Infrastructure Audit Complete
**Scope**: All NixOS containers and networking infrastructure

---

## Executive Summary

This analysis evaluates all 18 container services in the nixos-hwc infrastructure for:
- **Consistency**: Standardization across container definitions
- **Charter Compliance**: Adherence to Charter v6 requirements
- **Networking**: Proper integration with Tailscale, Caddy, and Gluetun
- **Robustness**: Error handling, assertions, and validation
- **Troubleshootability**: Documentation, logging, and debugging capabilities

### Key Findings

✅ **Strengths:**
- Excellent networking architecture with layered security (Tailscale → Caddy → containers)
- Strong VPN fail-safe pattern (containers share Gluetun's network namespace)
- Standardized `mkContainer` helper for rapid deployment
- Comprehensive routing configuration with 14+ services

⚠️**Gaps Identified:**
- **Charter v6 Migration Incomplete**: Only 4/18 containers (22%) have full assertions
- **Inconsistent Patterns**: Two competing patterns (mkContainer vs manual)
- **Missing Validations**: Most containers lack dependency assertions
- **Documentation Gaps**: Not all containers have troubleshooting guides
- **Network Mode Inconsistency**: Some containers hardcode network decisions

---

## Container Inventory

### 📊 Total Containers: 18

| Container | Pattern | Charter v6 | Networking | Assertions | Notes |
|-----------|---------|------------|------------|------------|-------|
| **qbittorrent** | Manual | ✅ | VPN (Gluetun) | ✅ | Fully compliant |
| **sabnzbd** | Manual | ✅ | VPN (Gluetun) | ✅ | Fully compliant |
| **organizr** | Manual | ✅ | Media Network | ✅ | Fully compliant |
| **tdarr** | Manual | ✅ | Media Network | ✅ | Fully compliant |
| **gluetun** | Manual | Partial | Media Network | ❌ | Missing assertions |
| **sonarr** | mkContainer | ❌ | Configurable | ❌ | Needs migration |
| **radarr** | mkContainer | ❌ | Configurable | ❌ | Needs migration |
| **lidarr** | mkContainer | ❌ | Configurable | ❌ | Needs migration |
| **prowlarr** | mkContainer | ❌ | Configurable | ❌ | Needs migration |
| **navidrome** | mkContainer | ❌ | Media Network | ❌ | Needs migration |
| **jellyfin** | mkContainer | ❌ | Media Network | ❌ | Needs migration |
| **jellyseerr** | mkContainer | ❌ | Media Network | ❌ | Needs migration |
| **immich** | mkContainer | ❌ | Media Network | ❌ | Needs migration |
| **beets** | mkContainer | ❌ | Media Network | ❌ | Needs migration |
| **caddy** | mkContainer | ❌ | Host | ❌ | Needs migration |
| **slskd** | Unknown | ❌ | Media Network | ❌ | Needs investigation |
| **soularr** | Unknown | ❌ | Media Network | ❌ | Needs investigation |
| **recyclarr** | Unknown | ❌ | Media Network | ❌ | Needs investigation |

---

## Networking Architecture Analysis

### Layer 1: External Access (Tailscale)
- **Domain**: `hwc.ocelot-wahoo.ts.net`
- **Server IP**: `100.115.126.41/32`
- **Purpose**: Secure remote access point
- **TLS**: Automatic via Tailscale certificates
- **Status**: ✅ **Properly configured**

### Layer 2: Reverse Proxy (Caddy)
- **Routes Configured**: 14 services
- **TLS**: Via `get_certificate tailscale`
- **Compression**: `zstd gzip` on all responses
- **Routing Modes**:
  - **Subpath (preserve)**: 7 services (Sonarr, Radarr, Lidarr, Prowlarr, Navidrome, SABnzbd, CouchDB)
  - **Subpath (strip)**: 2 services (qBittorrent, Jellyseerr)
  - **Dedicated ports**: 6 services (Jellyseerr:5543, Immich:7443, Frigate:5443, SLSKD:8443, Tdarr:8267, Organizr:9443)
- **Status**: ✅ **Well-designed**, ⚠️ **3 routing modes may cause confusion**

### Layer 3: VPN Tunnel (Gluetun)
- **Provider**: ProtonVPN (OpenVPN)
- **Region**: Netherlands
- **Dependent Containers**: qBittorrent, SABnzbd
- **Network Mode**: `--network=container:gluetun`
- **Fail-safe**: ✅ If VPN drops, dependent containers lose all connectivity (prevents IP leakage)
- **Health Check**: Every 5 minutes, HTTP test to 1.1.1.1:443
- **Status**: ✅ **Excellent security design**

### Layer 4: Container Network (media-network)
- **Type**: Podman bridge network
- **Subnet**: `10.89.0.0/24`
- **DNS**: Enabled (hostname resolution between containers)
- **Containers**: 13+ connected
- **Status**: ✅ **Properly configured**

### Networking Issues Identified

#### ⚠️ Issue 1: Inconsistent Port Binding
**Problem**: Mixed strategies for port exposure
- Download clients (Gluetun): `0.0.0.0` (accessible from LAN)
- Media services (*arr stack): `127.0.0.1` (localhost only)
- Native services: Varies (Jellyfin: all interfaces, Immich: tailscale0 only)

**Impact**: Confusing, potential security gaps
**Recommendation**: Standardize to `127.0.0.1` for all services except those requiring LAN discovery

#### ⚠️ Issue 2: Unused Framework Code
**Problem**: VLAN/bridge/mDNS framework exists but unused
**Impact**: Code bloat, maintenance burden
**Recommendation**: Remove unused code or document planned usage

#### ⚠️ Issue 3: Three Caddy Routing Modes
**Problem**: `needsUrlBase` flag creates preserve/strip confusion
**Impact**: Developers must understand each app's URL base requirements
**Recommendation**: Document URL base requirements per app in routes.nix

---

## Charter v6 Compliance Analysis

### Charter Requirements for Containers

From CHARTER.md v6.0:
1. ✅ **Namespace Rule**: All containers use `hwc.server.containers.<name>`
2. ⚠️ **Module Anatomy**: Not all have proper `parts/` structure
3. ❌ **Configuration Validity**: Only 4/18 have assertions and validation
4. ✅ **Native vs Container**: Decisions documented in `NATIVE_VS_CONTAINER_ANALYSIS.md`
5. ⚠️ **Lane Purity**: Some mixing of concerns in shared libs

### Migration Status

**Charter v6 Compliant (4/18 = 22%)**:
- qbittorrent - Full assertions, systemd dependencies, firewall config
- sabnzbd - Full assertions, tmpfiles rules, environment validation
- organizr - Full assertions, proper dependency management
- tdarr - Full assertions, WebSocket-aware configuration

**Using mkContainer Helper (10/18 = 56%)**:
- sonarr, radarr, lidarr, prowlarr (all *arr stack)
- navidrome, jellyfin, jellyseerr, immich, beets, caddy
- **Pattern**: Clean, DRY, but lacks Charter v6 validation requirements
- **Action Required**: Migrate to manual pattern OR enhance mkContainer with validation support

**Unknown/Hybrid (4/18 = 22%)**:
- gluetun - Manual but missing assertions
- slskd, soularr, recyclarr - Need investigation

---

## Pattern Comparison

### Pattern A: mkContainer Helper (Old/Simple)

**File**: `_shared/pure.nix`

**Example**:
```nix
helpers.mkContainer {
  name = "sonarr";
  image = cfg.image;
  networkMode = cfg.network.mode;
  ports = [ "127.0.0.1:8989:8989" ];
  volumes = [ "/opt/downloads/sonarr:/config" ];
  environment = { SONARR__URLBASE = "/sonarr"; };
  dependsOn = if cfg.network.mode == "vpn" then [ "gluetun" ] else [ "prowlarr" ];
}
```

**Pros**:
- ✅ DRY (Don't Repeat Yourself)
- ✅ Rapid deployment (5-10 lines)
- ✅ Consistent resource limits (2GB RAM, 1 CPU, 4GB swap)
- ✅ Automatic PUID/PGID/TZ handling

**Cons**:
- ❌ No assertions or validation (Charter v6 requirement)
- ❌ No documentation sections
- ❌ Hidden complexity (magic defaults)
- ❌ Hard to debug when things go wrong

### Pattern B: Manual Configuration (New/Charter v6)

**Example**: `qbittorrent/parts/config.nix`

**Structure**:
```nix
{
  assertions = [
    { assertion = ...; message = "..."; }
  ];

  virtualisation.oci-containers.containers.qbittorrent = {
    # Explicit configuration
  };

  systemd.services.podman-qbittorrent = {
    # Explicit dependencies
  };

  networking.firewall.allowedTCPPorts = [ ... ];
}
```

**Pros**:
- ✅ Charter v6 compliant (assertions section)
- ✅ Self-documenting (comments explain "why")
- ✅ Explicit dependencies (systemd)
- ✅ Firewall integration
- ✅ Easy to debug and troubleshoot

**Cons**:
- ❌ Verbose (50-100 lines per container)
- ❌ Repetitive boilerplate
- ❌ Harder to maintain consistency

---

## Recommendations

### 🎯 High Priority

#### 1. Complete Charter v6 Migration
**Action**: Migrate all 14 remaining containers to Charter v6 pattern
**Why**: Assertions prevent misconfiguration, improve troubleshooting
**Effort**: ~1-2 hours per container
**Priority**: High

**Suggested Order**:
1. Critical path: gluetun (everything depends on it)
2. Download clients: Already done ✅
3. *arr stack: sonarr, radarr, lidarr, prowlarr (similar patterns)
4. Media: jellyfin, navidrome, immich
5. Support: jellyseerr, beets, caddy
6. Unknown: slskd, soularr, recyclarr

#### 2. Standardize Network Mode Pattern
**Action**: Remove hardcoded network modes, make all configurable via `cfg.network.mode`
**Why**: Flexibility, easier to test/debug
**Effort**: 30 minutes per container
**Priority**: High

#### 3. Add Container Health Checks
**Action**: Implement health checks for all containers
**Why**: Auto-recovery, better monitoring
**Example**:
```nix
healthcheck = {
  test = [ "CMD" "curl" "-f" "http://localhost:8989/health" ];
  interval = "30s";
  timeout = "10s";
  retries = 3;
};
```
**Effort**: 15 minutes per container
**Priority**: Medium

### 🔧 Medium Priority

#### 4. Unify Port Binding Strategy
**Action**: Standardize all services to bind `127.0.0.1` (Caddy will proxy)
**Exception**: Services requiring LAN discovery (Jellyfin mDNS)
**Why**: Reduced attack surface, clearer security model
**Effort**: 10 minutes per container
**Priority**: Medium

#### 5. Document Routing Modes
**Action**: Add comments in routes.nix explaining why each service uses preserve/strip/port
**Why**: Future maintainers understand decisions
**Effort**: 30 minutes total
**Priority**: Medium

#### 6. Create Troubleshooting Runbook
**Action**: Document common issues per container (in READMEs)
**Why**: Faster incident response
**Topics**: Port conflicts, VPN failures, volume permissions, network connectivity
**Effort**: 1 hour per container (can be incremental)
**Priority**: Low-Medium

### 📚 Low Priority (Quality of Life)

#### 7. Remove Unused Framework Code
**Action**: Delete or document VLAN/mDNS code in network.nix
**Why**: Reduce cognitive load
**Effort**: 1 hour
**Priority**: Low

#### 8. Centralize Container Defaults
**Action**: Move `--memory=2g --cpus=1.0` defaults to shared config
**Why**: Easy to tune all containers at once
**Effort**: 2 hours
**Priority**: Low

#### 9. Add Container Metrics
**Action**: Integrate Prometheus metrics for all containers
**Why**: Better visibility, capacity planning
**Effort**: 4-6 hours
**Priority**: Low

---

## Validation Checklist

Use this checklist when adding/modifying containers:

### 📋 Container Configuration Checklist

#### Namespace & Structure
- [ ] Option namespace: `hwc.server.containers.<name>.*`
- [ ] File structure: `index.nix`, `options.nix`, `sys.nix` OR `parts/config.nix`
- [ ] Imports: Proper module imports in `containers/index.nix`

#### Charter v6 Compliance
- [ ] **ASSERTIONS**: Validate dependencies (e.g., Gluetun for VPN mode)
- [ ] **ASSERTIONS**: Validate required paths (e.g., hwc.paths.hot exists)
- [ ] Comments: Explain "why" not "what"
- [ ] Section headers: `#===` separators for clarity

#### Container Definition
- [ ] **Image**: Configurable via `cfg.image` option
- [ ] **AutoStart**: Set to `true`
- [ ] **Network**: Either `--network=media-network` OR `--network=container:gluetun`
- [ ] **Ports**: Bind to `127.0.0.1` unless LAN access required
- [ ] **Volumes**: Use `/opt/<category>/<name>:/config` pattern
- [ ] **Environment**: Always set `PUID=1000`, `PGID=1000`, `TZ`
- [ ] **Resources**: Set `--memory`, `--cpus`, `--memory-swap`
- [ ] **Dependencies**: Use `dependsOn` for container dependencies

#### Systemd Integration
- [ ] **after**: `network-online.target`, `init-media-network.service` OR `podman-gluetun.service`
- [ ] **wants**: Same as `after`
- [ ] **Secrets**: Use `agenix.service` if secrets required

#### Networking
- [ ] **Firewall**: Open ports ONLY if not using Caddy proxy
- [ ] **Caddy Route**: Add to `routes.nix` if web UI exists
- [ ] **needsUrlBase**: Set correctly based on app's URL base support
- [ ] **Headers**: Include `X-Forwarded-Prefix` for subpath apps

#### Testing
- [ ] Build: `nixos-rebuild build` succeeds
- [ ] Start: Container starts without errors
- [ ] Health: Service responds on expected port
- [ ] Logs: `journalctl -u podman-<name>` shows no errors
- [ ] Network: Service accessible via Caddy route
- [ ] VPN (if applicable): IP check shows VPN location

---

## Troubleshooting Guide

### Common Issues

#### Issue: Container won't start
**Symptoms**: `systemctl status podman-<name>` shows failed
**Debug**:
```bash
# Check container logs
podman logs <name>

# Check systemd logs
journalctl -u podman-<name> -n 50

# Check assertions
nixos-rebuild build
```
**Common Causes**:
- Missing dependency (check assertions)
- Port conflict (check `ss -tlnp`)
- Volume permission issue (check `/opt/downloads/<name>` ownership)
- Image pull failure (check network connectivity)

#### Issue: Service not accessible via Caddy
**Symptoms**: 502 Bad Gateway or timeout
**Debug**:
```bash
# Check Caddy logs
journalctl -u caddy -n 50

# Check container is running
podman ps | grep <name>

# Test direct connection
curl http://127.0.0.1:<port>

# Check route configuration
cat /home/user/nixos-hwc/domains/server/routes.nix
```
**Common Causes**:
- Wrong port in routes.nix
- Container bound to wrong interface
- Firewall blocking connection
- needsUrlBase misconfigured

#### Issue: VPN container has no internet
**Symptoms**: qBittorrent/SABnzbd can't connect
**Debug**:
```bash
# Check Gluetun status
podman exec gluetun curl https://ifconfig.me

# Check Gluetun logs
podman logs gluetun | tail -n 50

# Verify VPN connection
podman exec qbittorrent curl https://ifconfig.me
```
**Common Causes**:
- Gluetun failed to connect to VPN
- Credentials expired/wrong
- Network mode not set to `--network=container:gluetun`
- Gluetun container not running

#### Issue: Container using wrong network
**Symptoms**: Container can't resolve other container names
**Debug**:
```bash
# Check container network
podman inspect <name> | jq '.[0].NetworkSettings.Networks'

# Check media-network exists
podman network ls

# Test DNS resolution
podman exec <name> ping prowlarr
```
**Common Causes**:
- `init-media-network.service` failed
- Container started before network creation
- Wrong network mode in configuration

---

## Future Improvements

### Potential Enhancements

1. **Automated Container Testing**
   - CI/CD pipeline to test container builds
   - Automated health checks post-deployment
   - Integration tests for Caddy routing

2. **Container Resource Optimization**
   - Per-container resource limits based on actual usage
   - Memory/CPU monitoring and alerting
   - OOMKiller protection for critical services

3. **Advanced Networking**
   - Multiple VPN providers (load balancing)
   - Per-service VPN routing (some via VPN, some not)
   - Wireguard support alongside OpenVPN

4. **Backup & Recovery**
   - Automated `/opt/downloads` backups
   - Container state snapshots
   - Disaster recovery playbook

5. **Observability**
   - Grafana dashboards for all containers
   - Log aggregation (Loki)
   - Distributed tracing (Tempo)

6. **Security Hardening**
   - AppArmor/SELinux profiles per container
   - Secret rotation automation
   - Network policy enforcement (zero-trust)

---

## Appendix

### A. Container Images

| Container | Image Source | Update Policy |
|-----------|-------------|---------------|
| qbittorrent | linuxserver/qbittorrent | Manual |
| sabnzbd | linuxserver/sabnzbd | Manual |
| sonarr | linuxserver/sonarr | Manual |
| radarr | linuxserver/radarr | Manual |
| lidarr | linuxserver/lidarr | Manual |
| prowlarr | linuxserver/prowlarr | Manual |
| gluetun | qmcgaw/gluetun | Manual |

### B. Network Ports

| Service | Internal Port | External Access | Notes |
|---------|---------------|-----------------|-------|
| Sonarr | 8989 | Caddy /sonarr | Subpath preserve |
| Radarr | 7878 | Caddy /radarr | Subpath preserve |
| qBittorrent | 8080 | Caddy /qbt | Subpath strip |
| SABnzbd | 8081 | Caddy /sab | Subpath preserve |
| Jellyseerr | 5055 | Caddy :5543 | Dedicated port |
| Immich | 2283 | Caddy :7443 | Dedicated port |
| Organizr | 9983 | Caddy :9443 | Dedicated port |

### C. Resource Allocation

**Default per container** (from mkContainer):
- Memory: 2GB
- CPUs: 1.0
- Memory Swap: 4GB

**Total if all 18 running**:
- Memory: 36GB
- CPUs: 18.0 (overcommitted)
- Swap: 72GB

---

## Conclusion

The nixos-hwc container infrastructure is **well-architected** with excellent networking security through Tailscale + Caddy + Gluetun. However, **Charter v6 migration is incomplete** (only 22% compliant), creating inconsistency in how containers are defined and validated.

**Immediate Action Required**:
1. Complete Charter v6 migration for all 14 remaining containers
2. Standardize network mode configuration
3. Add health checks for auto-recovery

**Long-term Goals**:
1. Implement comprehensive monitoring and alerting
2. Automate testing and validation
3. Create detailed troubleshooting runbooks per service

This analysis provides a roadmap for achieving **robust, standardized, and easily troubleshootable** container infrastructure.
