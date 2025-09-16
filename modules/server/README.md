# Services Domain

## Purpose & Scope

The **Services Domain** provides **application and daemon orchestration** - managing the lifecycle, configuration, and coordination of application services. This domain owns application daemons, implements service-specific business logic, and coordinates complex multi-service workflows.

**Key Principle**: If it owns an application daemon or implements service-specific logic → services domain. Services are the "application layer" that delivers user functionality.

## Domain Architecture

The services domain is organized into **4 service categories** based on functionality:

```
modules/services/
├── index.nix                    # Domain aggregator  
├── apps/                        # User-facing applications
│   ├── index.nix               # Apps aggregator
│   └── jellyfin.nix           # Media server application
├── data/                        # Data management services
│   ├── index.nix               # Data aggregator
│   └── (future: databases, ETL, analytics)
├── edge/                        # External integration services  
│   ├── index.nix               # Edge aggregator
│   └── (future: VPN, reverse proxy, CDN)
└── observability/              # Monitoring and logging services
    ├── index.nix               # Observability aggregator  
    └── (future: Prometheus, Grafana, logs)
```

## Service Categories

### 🎬 Apps (`apps/`)
**User-facing application services**

Applications that end users directly interact with - media servers, web applications, desktop services exposed via web interfaces.

**Current Services:**
- **Jellyfin** (`jellyfin.nix`): Media server with GPU transcoding

**Option Pattern:**
```nix
hwc.services.jellyfin = {
  enable = true;
  enableGpu = true;        # GPU acceleration for transcoding
  openFirewall = true;     # External access
  mediaLibraries = [       # Media directory integration
    { name = "Movies"; path = "/mnt/media/movies"; }
    { name = "TV Shows"; path = "/mnt/media/tv"; }
  ];
};
```

### 📊 Data (`data/`)
**Data storage, processing, and analytics services**

Services focused on data management - databases, ETL pipelines, analytics engines, data warehousing.

**Future Services:**
- PostgreSQL database clusters
- Redis caching layers  
- ETL workflow engines
- Data analytics platforms

**Future Option Pattern:**
```nix
hwc.services.postgresql = {
  enable = true;
  databases = [ "jellyfin" "immich" "business" ];
  backups = {
    enable = true;
    schedule = "daily";
    retention = "30d";
  };
};
```

### 🌐 Edge (`edge/`)
**External connectivity and integration services**

Services that handle external network integration - VPNs, reverse proxies, CDNs, external API integrations.

**Future Services:**  
- Tailscale/WireGuard VPN coordination
- Caddy/Traefik reverse proxy
- External API integrations
- Content delivery networks

**Future Option Pattern:**
```nix
hwc.services.caddy = {
  enable = true;
  sites = {
    "jellyfin.local" = { upstream = "localhost:8096"; };
    "radarr.local" = { upstream = "localhost:7878"; auth = "tailscale"; };
  };
  ssl.enable = true;
};
```

### 📈 Observability (`observability/`)
**Monitoring, logging, and system visibility services**

Services for system monitoring, log aggregation, metrics collection, alerting, and observability.

**Future Services:**
- Prometheus metrics collection
- Grafana dashboards
- Log aggregation (Loki/ELK)
- Alerting systems

**Future Option Pattern:**  
```nix
hwc.services.prometheus = {
  enable = true;
  targets = {
    system = { endpoint = "localhost:9100"; };
    jellyfin = { endpoint = "localhost:8096/metrics"; };
    caddy = { endpoint = "localhost:2019/metrics"; };
  };
  retention = "90d";
};
```

## Current Service Implementation

### 🎬 Jellyfin Media Server

**Purpose**: Self-hosted media streaming with GPU transcoding

**Key Features:**
- Automatic GPU acceleration detection via infrastructure domain
- Media library auto-configuration using system paths
- Container-based deployment with proper networking
- Firewall integration for external access

**Implementation Details:**
```nix
# Consumes GPU acceleration from infrastructure
gpu = config.hwc.infrastructure.hardware.gpu;

# Container deployment with GPU passthrough
virtualisation.oci-containers.containers.jellyfin = {
  image = "jellyfin/jellyfin:latest";
  ports = [ "8096:8096" ];
  
  # GPU acceleration automatically applied
  extraOptions = gpu.containerOptions or [];
  environment = gpu.containerEnvironment or {};
  
  # Media volumes from system paths
  volumes = [
    "/mnt/media:/media:ro"
    "/var/lib/jellyfin:/config"
  ];
};
```

**Data Flow:**
```
Machine Config → hwc.services.jellyfin.enable = true
       ↓  
Jellyfin Service → detects GPU from infrastructure.hardware.gpu
       ↓
Container Runtime → applies GPU passthrough if available
       ↓
Media Libraries → mounted from system storage paths
       ↓
Firewall Rules → ports opened for external access
       ↓
User Access → web UI available at machine-ip:8096
```

**Integration Points:**
- **Infrastructure GPU**: Automatic GPU detection and container integration
- **System Storage**: Media paths from `hwc.paths.*` configuration
- **System Networking**: Firewall rules and port management
- **Security**: Future integration with authentication services

## Service Development Patterns

### Service Template Structure
```nix
# modules/services/<category>/<service>.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.services.<service>;
  # Integration with other domains
  gpu = config.hwc.infrastructure.hardware.gpu;
  paths = config.hwc.paths;
in {
  #============================================================================
  # OPTIONS - Service Configuration Interface
  #============================================================================
  options.hwc.services.<service> = {
    enable = lib.mkEnableOption "<service> description";
    
    # Service-specific configuration
    port = lib.mkOption {
      type = lib.types.int;
      default = 8080;
      description = "Service port";
    };
    
    # Integration toggles
    enableGpu = lib.mkOption {
      type = lib.types.bool; 
      default = true;
      description = "Enable GPU acceleration if available";
    };
  };

  #============================================================================  
  # IMPLEMENTATION - Service Orchestration
  #============================================================================
  config = lib.mkIf cfg.enable {
    
    # Container or systemd service definition
    virtualisation.oci-containers.containers.<service> = {
      image = "<service>/<service>:latest";
      ports = [ "${toString cfg.port}:${toString cfg.port}" ];
      
      # Cross-domain integration
      extraOptions = lib.optionals (cfg.enableGpu && gpu.accel != "cpu") 
        gpu.containerOptions;
      environment = lib.optionalAttrs (cfg.enableGpu && gpu.accel != "cpu")
        gpu.containerEnvironment;
        
      volumes = [
        "${paths.hot}/<service>:/config"
        "${paths.media}:/media:ro"
      ];
    };
    
    # Networking integration
    networking.firewall.allowedTCPPorts = lib.optionals cfg.openFirewall [ cfg.port ];
    
    # Validation
    assertions = [{
      assertion = cfg.enableGpu -> gpu.accel != "none";
      message = "${service} GPU acceleration requires hwc.infrastructure.hardware.gpu.type to be configured";
    }];
  };
}
```

### Cross-Domain Integration Patterns

**Consuming Infrastructure:**
```nix
# GPU acceleration
gpu = config.hwc.infrastructure.hardware.gpu;
extraOptions = gpu.containerOptions or [];

# Storage paths  
volumes = [ "${config.hwc.paths.media}:/media:ro" ];

# User permissions
User = config.hwc.system.users.user.name;
```

**Providing Service Interfaces:**
```nix  
# Expose service endpoints for other services
options.hwc.services.<service>.endpoint = lib.mkOption {
  type = lib.types.str;
  default = "http://localhost:${toString cfg.port}";
  description = "Service API endpoint";
};

# Service discovery integration
config.hwc.infrastructure.mesh.services.<service> = {
  port = cfg.port;
  health = "/health";
};
```

## Service Lifecycle Management

### Service Dependencies
Services can depend on other services:

```nix
# Service A depends on Service B
systemd.services.<service-a> = {
  after = [ "container-<service-b>.service" ];
  requires = [ "container-<service-b>.service" ];
};
```

### Health Checking
Services should provide health endpoints:

```nix
# Health check integration
systemd.services."<service>-health" = {
  description = "<Service> health check";
  serviceConfig = {
    Type = "oneshot";
    ExecStart = "${pkgs.curl}/bin/curl -f http://localhost:${cfg.port}/health";
  };
};

systemd.timers."<service>-health" = {
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnCalendar = "*:0/5";  # Every 5 minutes
    Persistent = true;
  };
};
```

### Service Updates
Services should support graceful updates:

```nix
# Rolling update support
virtualisation.oci-containers.containers.<service> = {
  autoStart = true;
  
  # Update strategy
  labels = {
    "io.containers.autoupdate" = "registry";
  };
};
```

## Validation & Troubleshooting  

### Service Status
```bash
# Check service containers
podman ps -a

# Check systemd services  
systemctl status container-<service>

# Check service logs
podman logs <service>
journalctl -u container-<service>
```

### Cross-Domain Integration
```bash
# Check GPU integration
nix eval .#nixosConfigurations.hwc-laptop.config.hwc.infrastructure.hardware.gpu.accel

# Check storage paths
ls -la /mnt/media/ /mnt/hot/

# Check networking
ss -tlnp | grep 8096
```

### Service Health
```bash
# Test service endpoints
curl -I http://localhost:8096/health
curl http://localhost:8096/System/Info

# Check service logs for errors
podman logs jellyfin | grep -i error
```

## Anti-Patterns

**❌ Don't implement infrastructure in services**:
```nix
# Wrong - hardware integration belongs in infrastructure
hardware.nvidia.enable = true;
```

**❌ Don't manage users in services**:
```nix  
# Wrong - user management belongs in system domain
users.users.jellyfin = { ... };
```

**❌ Don't implement core system functionality**:
```nix
# Wrong - networking belongs in system domain  
networking.firewall.enable = true;
```

**✅ Do own application daemons**:
```nix
# Correct - service daemon management
systemd.services.jellyfin = { ... };
virtualisation.oci-containers.containers.jellyfin = { ... };
```

**✅ Do implement service-specific logic**:
```nix
# Correct - service configuration and business logic
services.jellyfin.mediaLibraries = [ ... ];
environment.JELLYFIN_CONFIG_DIR = "/var/lib/jellyfin";
```

**✅ Do integrate across domains cleanly**:
```nix  
# Correct - consuming other domain capabilities
gpu = config.hwc.infrastructure.hardware.gpu;
paths = config.hwc.paths;
user = config.hwc.system.users.user.name;
```

## Future Service Expansion

The services domain is designed to grow organically:

1. **Immediate**: Complete media stack (Radarr, Sonarr, qBittorrent)
2. **Short-term**: Monitoring stack (Prometheus, Grafana)  
3. **Medium-term**: Data services (PostgreSQL, Redis)
4. **Long-term**: Edge services (Caddy, VPN coordination)

Each new service follows the established patterns and integrates cleanly with existing infrastructure, system, and security domains.

---

The services domain provides the **application functionality** that users directly interact with, while maintaining clean separation from the foundational system capabilities and integration glue provided by other domains.