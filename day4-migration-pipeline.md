# Day 4: Service Migration Pipeline (4-5 hours)

## Morning Session (2.5 hours)
### 9:00 AM - Establish Migration Pattern ✅

```bash
cd /etc/nixos-next

# Step 1: Create service migration template
cat > operations/migration/SERVICE_TEMPLATE.nix << 'EOF'
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.SERVICE_NAME;
  paths = config.hwc.paths;
in {
  options.hwc.services.SERVICE_NAME = {
    enable = lib.mkEnableOption "SERVICE_DESCRIPTION";
    
    port = lib.mkOption {
      type = lib.types.port;
      default = PORT_NUMBER;
      description = "Port for SERVICE_NAME";
    };
    
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.state}/SERVICE_NAME";
      description = "Data directory";
    };
    
    # Add service-specific options here
  };
  
  config = lib.mkIf cfg.enable {
    # Service implementation
  };
}
EOF

# Step 2: Create migration automation script
cat > operations/migration/migrate-service.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

SERVICE=$1
OLD_PATH="/etc/nixos/hosts/server/modules/$SERVICE.nix"
NEW_PATH="/etc/nixos-next/modules/services/$SERVICE.nix"

echo "=== Migrating $SERVICE ==="

# Check if old service exists
if [ ! -f "$OLD_PATH" ]; then
    echo "⚠️  No old config found at $OLD_PATH"
    echo "Searching for service..."
    find /etc/nixos -name "*$SERVICE*" -type f
    exit 1
fi

# Create new module from template
cp operations/migration/SERVICE_TEMPLATE.nix "$NEW_PATH"

echo "✅ Created $NEW_PATH"
echo "📝 Now manually port the configuration"
echo ""
echo "Old config:"
head -20 "$OLD_PATH"
EOF
chmod +x operations/migration/migrate-service.sh
```

### 10:00 AM - Migrate Multiple Simple Services ✅

```bash
# Step 3: Migrate transcript-api
cat > modules/services/transcript-api.nix << 'EOF'
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.transcriptApi;
  paths = config.hwc.paths;
in {
  options.hwc.services.transcriptApi = {
    enable = lib.mkEnableOption "YouTube transcript API";
    
    port = lib.mkOption {
      type = lib.types.port;
      default = 5000;
      description = "API port";
    };
    
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.state}/transcript-api";
      description = "Data directory";
    };
    
    apiKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "YouTube API keys";
    };
  };
  
  config = lib.mkIf cfg.enable {
    systemd.services.transcript-api = {
      description = "YouTube Transcript API";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      
      environment = {
        API_PORT = toString cfg.port;
        DATA_DIR = cfg.dataDir;
      };
      
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python /etc/nixos/scripts/yt_transcript.py";
        Restart = "always";
        StateDirectory = "hwc/transcript-api";
        DynamicUser = true;
      };
    };
    
    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
EOF

# Step 4: Migrate monitoring base
cat > modules/services/prometheus.nix << 'EOF'
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.prometheus;
  paths = config.hwc.paths;
in {
  options.hwc.services.prometheus = {
    enable = lib.mkEnableOption "Prometheus monitoring";
    
    port = lib.mkOption {
      type = lib.types.port;
      default = 9090;
      description = "Prometheus port";
    };
    
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.state}/prometheus";
      description = "Data directory";
    };
    
    retention = lib.mkOption {
      type = lib.types.str;
      default = "30d";
      description = "Data retention period";
    };
    
    scrapeConfigs = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [];
      description = "Scrape configurations";
    };
  };
  
  config = lib.mkIf cfg.enable {
    services.prometheus = {
      enable = true;
      port = cfg.port;
      dataDir = cfg.dataDir;
      retentionTime = cfg.retention;
      
      globalConfig = {
        scrape_interval = "15s";
        evaluation_interval = "15s";
      };
      
      scrapeConfigs = [
        {
          job_name = "node";
          static_configs = [{
            targets = [ "localhost:9100" ];
          }];
        }
      ] ++ cfg.scrapeConfigs;
    };
    
    # Node exporter for system metrics
    services.prometheus.exporters.node = {
      enable = true;
      port = 9100;
    };
  };
}
EOF

# Step 5: Create Grafana module
cat > modules/services/grafana.nix << 'EOF'
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.grafana;
  paths = config.hwc.paths;
in {
  options.hwc.services.grafana = {
    enable = lib.mkEnableOption "Grafana dashboards";
    
    port = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Grafana port";
    };
    
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.state}/grafana";
      description = "Data directory";
    };
    
    domain = lib.mkOption {
      type = lib.types.str;
      default = "grafana.local";
      description = "Domain name";
    };
  };
  
  config = lib.mkIf cfg.enable {
    services.grafana = {
      enable = true;
      settings = {
        server = {
          http_port = cfg.port;
          domain = cfg.domain;
          root_url = "http://${cfg.domain}";
        };
        paths = {
          data = cfg.dataDir;
          logs = "${paths.state}/grafana/logs";
          plugins = "${cfg.dataDir}/plugins";
        };
      };
    };
    
    # Auto-provision datasource
    services.grafana.provision = {
      enable = true;
      datasources.settings.datasources = lib.mkIf config.hwc.services.prometheus.enable [
        {
          name = "Prometheus";
          type = "prometheus";
          url = "http://localhost:${toString config.hwc.services.prometheus.port}";
          isDefault = true;
        }
      ];
    };
  };
}
EOF
```

## Afternoon Session (2.5 hours)

### 2:00 PM - Create Service Profiles ✅

```bash
# Step 6: Create monitoring profile
cat > profiles/monitoring.nix << 'EOF'
{ ... }:
{
  imports = [
    ../modules/services/prometheus.nix
    ../modules/services/grafana.nix
  ];
  
  # Enable monitoring stack
  hwc.services.prometheus = {
    enable = true;
    retention = "90d";
  };
  
  hwc.services.grafana = {
    enable = true;
    domain = "grafana.hwc.local";
  };
}
EOF

# Step 7: Create base profile
cat > profiles/base.nix << 'EOF'
{ lib, ... }:
{
  imports = [
    ../modules/system/paths.nix
  ];
  
  # Basic system settings all machines need
  time.timeZone = "America/Denver";
  
  networking.firewall.enable = lib.mkDefault true;
  
  services.openssh = {
    enable = lib.mkDefault true;
    settings.PermitRootLogin = "no";
  };
  
  # Container runtime
  virtualisation.docker.enable = lib.mkDefault true;
  virtualisation.oci-containers.backend = "docker";
  
  # Basic packages
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    tmux
  ];
}
EOF

# Step 8: Update test machine to use profiles
cat > machines/test-refactor.nix << 'EOF'
{ config, lib, pkgs, ... }:
{
  imports = [
    /etc/nixos/hosts/server/hardware-configuration.nix
    ../profiles/base.nix
    ../profiles/monitoring.nix
    ../modules/services/ntfy.nix
    ../modules/services/transcript-api.nix
  ];
  
  networking.hostName = "test-refactor";
  
  # Enable specific services
  hwc.services.ntfy.enable = true;
  hwc.services.transcriptApi.enable = true;
  
  # Machine-specific settings
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  
  users.users.eric = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
  };
  
  system.stateVersion = "24.05";
}
EOF

# Step 9: Build test
sudo nixos-rebuild build --flake .#test-refactor
```

### 4:00 PM - Create Migration Tracker ✅

```bash
# Step 10: Create service inventory
cat > operations/migration/SERVICE_INVENTORY.md << 'EOF'
# Service Migration Status

## ✅ Completed (Day 3-4)
- [x] ntfy - Simple notification service
- [x] transcript-api - Python service
- [x] prometheus - Monitoring collector
- [x] grafana - Dashboard system

## 🔄 In Progress
- [ ] jellyfin - Media server (complex)

## 📋 Pending - Simple (Day 5)
- [ ] caddy - Reverse proxy
- [ ] homepage - Dashboard
- [ ] vaultwarden - Password manager

## 📋 Pending - Medium (Day 6)
- [ ] sonarr - TV management
- [ ] radarr - Movie management
- [ ] prowlarr - Indexer management
- [ ] bazarr - Subtitle management

## 📋 Pending - Complex (Day 7+)
- [ ] frigate - NVR with GPU
- [ ] immich - Photo management with ML
- [ ] ollama - Local LLM with GPU
- [ ] plex - Media server (alternative)

## Migration Complexity Factors
- **Simple**: No state, basic config, no dependencies
- **Medium**: Some state, container-based, simple dependencies
- **Complex**: Heavy state, GPU requirements, complex dependencies
EOF

git add -A
git commit -m "Day 4: Migration pipeline and monitoring stack"
```

## End of Day 4 Checklist

- [ ] 4 services migrated total
- [ ] Profiles created (base, monitoring)
- [ ] Service template created
- [ ] Migration tracker established
- [ ] Build still succeeds

## Validation

```bash
# Count migrated services
ls -1 modules/services/*.nix | wc -l

# Verify profile composition
nix eval --json .#nixosConfigurations.test-refactor.config.hwc.services | jq keys
```
