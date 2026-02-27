# Native vs Container Services Analysis

**Document Version**: 1.0
**Date**: 2025-10-31
**Author**: HWC Architecture Team
**Status**: Approved for Implementation

---

## Executive Summary

This document provides a comprehensive analysis of when to use native NixOS services versus containerized services in the HWC architecture. Based on empirical analysis of the Jellyfin containerization issue, we provide definitive guidance for service deployment strategies.

**Key Finding**: Services requiring external device connectivity must use native NixOS services due to container network isolation barriers.

---

## Background

The HWC architecture initially containerized most services for security and isolation benefits. However, the Jellyfin external connectivity failure revealed fundamental limitations with containerized services when external device access is required.

### Problem Statement

Containerized Jellyfin could not be accessed by external devices (Roku TVs, mobile apps) despite proper port mapping and firewall configuration. Root cause analysis revealed that container network isolation (`media-network` with IP `10.89.0.123`) prevented external devices from reaching the service.

### Reference Implementation

The working `/etc/nixos` system uses native services for external-facing applications:
- Jellyfin: Native NixOS service
- Immich: Native NixOS service
- Both accessible from external devices without connectivity issues

---

## Decision Framework

### Use Native Services When:

1. **External Device Connectivity Required**
   - Smart TV access (Roku, Apple TV, etc.)
   - Mobile app connectivity
   - Cross-network access from client devices

2. **Performance Critical**
   - GPU acceleration requirements
   - High-throughput operations
   - Low-latency requirements

3. **Deep System Integration**
   - Hardware access requirements
   - Filesystem performance needs
   - Native library dependencies

### Use Containers When:

1. **Security Isolation Required**
   - Download clients (VPN routing)
   - P2P applications
   - Untrusted workloads

2. **Internal-Only Services**
   - Service coordination (Prowlarr)
   - Backend processing
   - API-only services

3. **Resource Control Needed**
   - Memory/CPU limiting
   - Network bandwidth control
   - Storage isolation

---

## Service Classification

### External Connectivity Services ’ Native

| Service | Reason | Priority |
|---------|--------|----------|
| **Jellyfin** | Smart TV access, mobile apps |  IMPLEMENTED |
| **Immich** | Photo backup, mobile apps | =% IMMEDIATE |
| **Navidrome** | Music streaming apps, Subsonic API | =% IMMEDIATE |

### Internal Services ’ Containers

| Service | Reason | Status |
|---------|--------|--------|
| **Radarr/Sonarr/Lidarr** | Internal coordination, working well |  KEEP |
| **Prowlarr** | Indexer coordination only |  KEEP |
| **qBittorrent** | VPN isolation required |  KEEP |
| **SABnzbd** | VPN isolation required |  KEEP |
| **Gluetun** | VPN container essential |  KEEP |
| **SLSKD/Soularr** | P2P security isolation |  KEEP |

---

## Implementation Plan

### Phase 1: Critical External Services (Immediate)

1. **Immich Migration**
   - Disable container service
   - Configure native `services.immich`
   - Add firewall port 2283
   - Test photo backup and mobile access

2. **Navidrome Migration**
   - Disable container service
   - Configure native `services.navidrome`
   - Add firewall port 4533
   - Test Subsonic API access

### Phase 2: Validation & Documentation

1. **Connectivity Testing**
   - Mobile app access verification
   - Cross-network connectivity tests
   - Performance baseline establishment

2. **Documentation Updates**
   - Update Charter with decision framework
   - Document firewall requirements
   - Create troubleshooting guides

---

## Technical Implementation

### Native Service Configuration

```nix
# Immich - Photo Management
services.immich = {
  enable = true;
  host = "0.0.0.0";
  port = 2283;
  mediaLocation = "/mnt/photos";
  database.createDB = true;
  redis.enable = true;
};

# Navidrome - Music Streaming
services.navidrome = {
  enable = true;
  settings = {
    Address = "0.0.0.0";
    Port = 4533;
    MusicFolder = "/mnt/media/music";
    DataFolder = "/var/lib/navidrome";
  };
};

# Jellyfin - Media Server (implemented)
services.jellyfin = {
  enable = true;
  openFirewall = false;  # Manual firewall management
};
```

### Firewall Configuration

```nix
networking.firewall = {
  allowedTCPPorts = [
    # Media Services (Native)
    8096   # Jellyfin HTTP
    7359   # Jellyfin additional TCP
    2283   # Immich
    4533   # Navidrome

    # Container services via reverse proxy only
    # (No direct external access)
  ];

  allowedUDPPorts = [
    7359   # Jellyfin discovery
  ];
};
```

---

## Security Considerations

### Native Service Security

**Risks**:
- Larger attack surface on host system
- Direct filesystem access
- Manual firewall management required

**Mitigations**:
- systemd service isolation
- Explicit firewall rules
- Regular security updates via system rebuild

### Container Service Security

**Benefits**:
- Namespace isolation
- Network segmentation
- Resource controls via cgroups
- Attack surface reduction

**Maintained For**:
- Download clients (VPN isolation)
- P2P services (network isolation)
- Internal coordination services

---

## Performance Analysis

### Native Services
- ** Direct hardware access** (GPU for Immich ML)
- ** No container networking overhead**
- ** Filesystem performance optimized**
- **L Tighter system coupling**

### Container Services
- ** Resource isolation and control**
- ** Independent update cycles**
- ** VPN integration (Gluetun)**
- **L Networking complexity**
- **L Performance overhead**

---

## Monitoring & Validation

### Success Criteria

1. **External Connectivity**
   - Roku TV access to Jellyfin 
   - Mobile photo backup to Immich
   - Music app streaming via Navidrome

2. **Performance Metrics**
   - Immich ML processing times
   - Navidrome streaming latency
   - Overall system resource usage

3. **Security Posture**
   - No degradation in download client isolation
   - Firewall rules properly configured
   - Service isolation maintained

### Rollback Plan

- Container configurations preserved as comments
- Quick reversion possible via profile switches
- Service data location compatibility maintained

---

## Lessons Learned

1. **Container Network Isolation**: Container networks create routing barriers that prevent external device access, regardless of port mapping configuration.

2. **Reference Architecture Value**: The working `/etc/nixos` system provided crucial validation that native services solve external connectivity issues.

3. **Hybrid Approach Optimal**: Combination of native services (external access) and containers (security/isolation) provides optimal balance.

4. **Testing Critical**: External connectivity cannot be assumed - requires actual device testing from external networks.

---

## Conclusion

The analysis conclusively demonstrates that services requiring external device connectivity must use native NixOS services. Container network isolation, while beneficial for security, creates insurmountable barriers for external access.

The recommended hybrid approach maintains security for download clients and internal services while providing reliable external connectivity for user-facing applications.

**Approved Implementation**: Immediate migration of Immich and Navidrome to native services, with container retention for internal and security-sensitive services.

---

## References

- Charter v6.0: Container vs Native Service Guidelines
- Jellyfin Migration Case Study (2025-10-31)
- `/etc/nixos` Reference Implementation Analysis
- HWC Firewall Architecture Documentation