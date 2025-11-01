# Server Domain

## Purpose & Scope

The **Server Domain** provides **application services and container orchestration** - managing containerized applications, service coordination, media automation, AI services, and server-specific functionality. This domain owns application containers, implements service workflows, and coordinates complex multi-container deployments.

**Key Principle**: If it's a containerized application service or server-specific automation → server domain. The server domain is the "application layer" that delivers user functionality through coordinated services.

## Domain Architecture

The server domain is organized by **service categories** based on functionality:

```
domains/server/
├── index.nix                    # Domain aggregator
├── containers/                  # Containerized application services
│   ├── index.nix               # Container aggregator
│   ├── _shared/                # Shared container utilities
│   ├── caddy/                  # Reverse proxy & TLS termination
│   ├── jellyfin/               # Media server
│   ├── immich/                 # Photo management
│   ├── radarr/                 # Movie automation
│   ├── sonarr/                 # TV show automation
│   ├── lidarr/                 # Music automation
│   ├── prowlarr/               # Indexer management
│   ├── qbittorrent/            # Torrent client
│   ├── sabnzbd/                # Usenet client
│   ├── slskd/                  # SoulSeek daemon
│   ├── soularr/                # Music library organization
│   ├── navidrome/              # Music streaming server
│   └── gluetun/                # VPN container networking
├── orchestration/              # Service coordination & automation
│   ├── index.nix               # Orchestration aggregator
│   └── media-orchestrator.nix  # Media workflow automation
├── ai/                         # AI & LLM services
│   ├── ollama/                 # Local LLM server
│   └── ai-bible/               # AI-powered Bible study
├── business/                   # Business application services
│   ├── default.nix            # Business services
│   └── parts/business-api.nix  # Business API integration
├── networking/                 # Network services & databases
│   ├── default.nix            # Network service coordination
│   └── parts/                  # Database, NTFY, VPN coordination
├── monitoring/                 # Observability & metrics
│   ├── default.nix            # Monitoring coordination
│   └── parts/                  # Grafana, Prometheus, dashboards
├── storage/                    # Storage management & cleanup
│   ├── index.nix               # Storage coordination
│   └── parts/                  # Cleanup automation, monitoring
├── backup/                     # Backup services
│   ├── default.nix            # Backup coordination
│   └── parts/user-backup.nix   # User backup automation
└── downloaders/                # Download client orchestration
    ├── index.nix               # Downloader coordination
    └── parts/                  # Download automation, scripts
```

## Domain Boundaries

### ✅ **This Domain Manages**
- **Container Services**: Application containers and their orchestration
- **Media Automation**: Complete *arr stack workflow coordination
- **Service Integration**: Cross-service communication and dependencies
- **AI Services**: Local LLM and AI-powered applications
- **Business Services**: Business application APIs and integrations
- **Network Services**: Application-layer networking (databases, NTFY)
- **Monitoring Services**: Application metrics and observability
- **Backup Automation**: Service-specific backup coordination

### ❌ **This Domain Does NOT Manage**
- **System Services**: → Goes to `domains/system/`
- **Hardware Management**: → Goes to `domains/infrastructure/`
- **Secret Management**: → Goes to `domains/secrets/`
- **User Environment**: → Goes to `domains/home/`

### 🔗 **Integration Points**
- **Consumes from**: `domains/secrets/` (API keys), `domains/infrastructure/` (GPU, storage paths), `domains/system/` (networking, users)
- **Provides to**: External users via web interfaces, other services via APIs
- **Coordination**: Media workflow automation, container networking, service discovery

## Core Service Categories

### 🐳 Containers (`containers/`)
**Containerized application services with full orchestration**

The heart of the server domain - all application services run as containers with sophisticated networking, storage, and GPU integration.

**Key Features:**
- **Unified Container Framework**: Consistent patterns across all services
- **VPN-aware Networking**: Selective VPN routing via Gluetun
- **GPU Acceleration**: Automatic GPU passthrough for media services
- **Shared Storage**: Coordinated access to media libraries and processing
- **API Integration**: Cross-service communication and automation

**Container Architecture:**
```
Gluetun VPN Container
  ↓ (VPN network namespace)
Download Clients (qBittorrent, SABnzbd, SLSKD)
  ↓ (shared storage + events)
Media Automation (*arr stack)
  ↓ (shared media libraries)
Media Servers (Jellyfin, Navidrome)
  ↓ (reverse proxy)
Caddy (TLS termination + routing)
```

**Current Container Services:**
- **Caddy**: Reverse proxy with automatic TLS
- **Jellyfin**: Media server with GPU transcoding
- **Immich**: Photo management and sharing
- **Radarr/Sonarr/Lidarr**: Media automation (*arr stack)
- **Prowlarr**: Indexer management for *arr services
- **qBittorrent**: Torrent client (VPN-routed)
- **SABnzbd**: Usenet client (VPN-routed)
- **SLSKD**: SoulSeek daemon for rare music
- **Soularr**: Music library organization and metadata
- **Navidrome**: Subsonic-compatible music streaming
- **Gluetun**: VPN container for download clients

### 🎭 Orchestration (`orchestration/`)
**Service workflow automation and coordination**

Handles complex multi-service workflows, especially for media processing automation.

**Media Orchestrator** (`media-orchestrator.nix`):
- **Event-driven Architecture**: Monitors download completion events
- **Cross-service Integration**: Triggers rescans in Radarr/Sonarr/Lidarr
- **Workspace Integration**: Scripts deployed from `workspace/automation/`
- **Agenix Secrets**: Uses agenix for API key management
- **Real-time Processing**: File monitoring and service coordination

**Recent Changes:**
- ✅ **Fixed sops→agenix migration**: Converted from sops to agenix secrets
- ✅ **Workspace integration**: Scripts now deploy from `workspace/automation/`
- ✅ **Service enablement**: Re-enabled after resolving secrets conflict

### 🤖 AI Services (`ai/`)
**Artificial Intelligence and Large Language Model services**

**Ollama** (`ai/ollama/`):
- Local LLM server with GPU acceleration
- Model management and serving
- API integration for other services

**AI Bible** (`ai/ai-bible/`):
- AI-powered Bible study application
- Integration with Ollama for natural language processing
- Customizable prompts and study workflows

### 💼 Business Services (`business/`)
**Business application services and API integrations**

Handles business-specific applications and external API integrations.

### 🌐 Networking Services (`networking/`)
**Application-layer networking and databases**

- **Database Services**: Application databases and coordination
- **NTFY**: Notification services for automation
- **VPN Coordination**: Application-layer VPN management

### 📊 Monitoring (`monitoring/`)
**Service observability and metrics**

- **Grafana**: Dashboard and visualization
- **Prometheus**: Metrics collection and alerting
- **Service Health**: Application health monitoring

### 💾 Storage Management (`storage/`)
**Storage automation and cleanup**

- **Cleanup Automation**: Automated cleanup of temporary files
- **Storage Monitoring**: Disk usage and health monitoring

### 🔄 Backup Services (`backup/`)
**Automated backup coordination**

- **User Backup**: Automated user data backup
- **Service Configuration**: Backup of service configurations

## Service Development Patterns

### Standard Container Service Structure
```nix
# domains/server/containers/<service>/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.containers.<service>;
  paths = config.hwc.paths;
in
{
  imports = [
    ./options.nix       # Service configuration API
    ./sys.nix          # System integration (if needed)
    ./parts/config.nix  # Core container configuration
  ];

  config = lib.mkIf cfg.enable {
    # Container orchestration
    virtualisation.oci-containers.containers.<service> = {
      image = cfg.image;
      autoStart = true;

      # VPN networking (conditional)
      extraOptions = if cfg.network.mode == "vpn"
        then [ "--network=container:gluetun" ]
        else [ "--network=media-network" ];

      # Storage integration
      volumes = [
        "${paths.hot}/<service>:/config"
        "${paths.hot}/downloads:/downloads"
        "/opt/downloads/scripts:/config/scripts:ro"
      ];

      # Environment configuration
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = config.time.timeZone;
      };
    };

    # Service dependencies
    systemd.services.podman-<service> = {
      after = lib.optionals (cfg.network.mode == "vpn")
        [ "podman-gluetun.service" ];
    };

    # Firewall integration
    networking.firewall.allowedTCPPorts =
      lib.optionals (cfg.network.mode != "vpn") [ cfg.webPort ];
  };
}
```

### Workspace Integration Pattern
```nix
# Script deployment from workspace
systemd.services.media-orchestrator-install = {
  script = ''
    # Deploy automation scripts from workspace
    cp /home/eric/.nixos/workspace/automation/media-orchestrator.py /opt/downloads/scripts/
    cp /home/eric/.nixos/workspace/automation/qbt-finished.sh /opt/downloads/scripts/
    cp /home/eric/.nixos/workspace/automation/sab-finished.py /opt/downloads/scripts/
    chmod +x /opt/downloads/scripts/*.py /opt/downloads/scripts/*.sh
  '';
};
```

### Agenix Secrets Integration
```nix
# Reading API keys from agenix
preStart = ''
  cat > /tmp/service.env << EOF
SONARR_API_KEY=$(cat ${config.age.secrets.sonarr-api-key.path})
RADARR_API_KEY=$(cat ${config.age.secrets.radarr-api-key.path})
LIDARR_API_KEY=$(cat ${config.age.secrets.lidarr-api-key.path})
EOF
'';
serviceConfig.EnvironmentFile = "/tmp/service.env";
```

## Recent Major Changes

### ✅ Workspace Reorganization (October 2024)
- **Script Organization**: Moved from `scripts/` to `workspace/automation/`
- **Purpose-based Structure**: Organized by function vs machine
- **Automatic Deployment**: Scripts deploy from workspace on rebuild
- **Version Control**: All automation scripts in git

### ✅ Media Orchestrator Fixes (October 2024)
- **Sops→Agenix Migration**: Fixed secrets compatibility
- **Service Re-enablement**: Media orchestrator now functional
- **Real-time Automation**: Download completion triggers service rescans
- **API Integration**: Proper API key management via agenix

### ✅ Container Architecture Maturity
- **VPN Networking**: Selective VPN routing for download clients
- **GPU Integration**: Hardware acceleration for media services
- **Storage Coordination**: Shared storage across service stack
- **Network Isolation**: Container networking with proper isolation

## Validation & Troubleshooting

### Service Status
```bash
# Check all containers
podman ps -a

# Check specific service
systemctl status podman-<service>
podman logs <service>

# Check media orchestrator
systemctl status media-orchestrator.service
systemctl status media-orchestrator-install.service
```

### Workspace Integration
```bash
# Verify script deployment
ls -la /opt/downloads/scripts/
stat /opt/downloads/scripts/sab-finished.py

# Check workspace structure
ls -la ~/.nixos/workspace/automation/
```

### Container Networking
```bash
# Check VPN routing
podman exec gluetun curl -s ifconfig.me
podman exec qbittorrent curl -s ifconfig.me

# Check container networks
podman network ls
```

### Service Integration
```bash
# Test service APIs
curl http://localhost:8989/api/v3/system/status  # Sonarr
curl http://localhost:7878/api/v3/system/status  # Radarr
curl http://localhost:8096/System/Info           # Jellyfin
```

### Required Firewall Ports
```nix
# Common media service ports for machine firewall configuration
firewall.extraTcpPorts = [
  # Media Management (*arr stack)
  7878   # Radarr
  8989   # Sonarr
  8686   # Lidarr
  9696   # Prowlarr

  # Media Servers
  8096   # Jellyfin HTTP
  7359   # Jellyfin additional TCP
  4533   # Navidrome

  # Download Clients (if not VPN-routed)
  8080   # qBittorrent
  8081   # SABnzbd
  5030   # SLSKD
];

firewall.extraUdpPorts = [
  7359   # Jellyfin discovery
  50300  # SLSKD
];
```

**Note**: Container vs Native Service Port Handling
- **Containerized services**: Ports handled automatically by container networking
- **Native services** (e.g., `services.jellyfin`): Require explicit firewall configuration
- See Charter v6.0 "Server Workloads" for container vs native service decisions

## Profile Integration

### Server Profile Enablement
```nix
# profiles/server.nix
hwc.services.containers = {
  jellyfin.enable = true;
  radarr.enable = true;
  sonarr.enable = true;
  lidarr.enable = true;
  # ... other services
};

hwc.server.orchestration.mediaOrchestrator.enable = true;
```

## Future Expansion

The server domain continues to evolve:

1. **Immediate**: Enhanced monitoring and alerting
2. **Short-term**: Additional AI services and models
3. **Medium-term**: Business application expansion
4. **Long-term**: Multi-node container orchestration

---

**Domain Version**: v3.0 - Full container orchestration with automation
**Charter Compliance**: ✅ Full compliance with HWC Charter v6.0
**Last Updated**: October 2024 - Post workspace reorganization and agenix migration