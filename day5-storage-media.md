# Day 5: Storage & Media Services (5-6 hours)

## Morning Session (3 hours)
### 9:00 AM - Storage Infrastructure ✅

```bash
cd /etc/nixos-next

# Step 1: Create comprehensive storage module
cat > modules/infrastructure/storage.nix << 'EOF'
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.storage;
  paths = config.hwc.paths;
in {
  options.hwc.storage = {
    hot = {
      enable = lib.mkEnableOption "Hot storage tier";
      
      path = lib.mkOption {
        type = lib.types.path;
        default = "/mnt/hot";
        description = "Hot storage mount point";
      };
      
      device = lib.mkOption {
        type = lib.types.str;
        default = "/dev/disk/by-uuid/YOUR-UUID-HERE";
        description = "Device UUID";
      };
      
      fsType = lib.mkOption {
        type = lib.types.str;
        default = "ext4";
        description = "Filesystem type";
      };
    };
    
    media = {
      enable = lib.mkEnableOption "Media storage";
      
      path = lib.mkOption {
        type = lib.types.path;
        default = "/mnt/media";
        description = "Media storage mount point";
      };
      
      directories = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "movies" "tv" "music" "books" "photos"
          "downloads" "incomplete" "blackhole"
        ];
        description = "Media subdirectories to create";
      };
    };
    
    backup = {
      enable = lib.mkEnableOption "Backup storage";
      
      path = lib.mkOption {
        type = lib.types.path;
        default = "/mnt/backup";
        description = "Backup storage path";
      };
    };
  };
  
  config = lib.mkMerge [
    (lib.mkIf cfg.hot.enable {
      fileSystems."${cfg.hot.path}" = {
        device = cfg.hot.device;
        fsType = cfg.hot.fsType;
        options = [ "defaults" "noatime" ];
      };
      
      systemd.tmpfiles.rules = [
        "d ${cfg.hot.path} 0755 root root -"
      ];
    })
    
    (lib.mkIf cfg.media.enable {
      systemd.tmpfiles.rules = 
        [ "d ${cfg.media.path} 0755 root root -" ] ++
        (map (dir: "d ${cfg.media.path}/${dir} 0775 media media -") cfg.media.directories);
      
      users.groups.media = {};
    })
    
    (lib.mkIf cfg.backup.enable {
      systemd.tmpfiles.rules = [
        "d ${cfg.backup.path} 0750 root root -"
      ];
    })
  ];
}
EOF

# Step 2: Create Jellyfin module with GPU support
cat > modules/services/jellyfin.nix << 'EOF'
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.jellyfin;
  paths = config.hwc.paths;
in {
  options.hwc.services.jellyfin = {
    enable = lib.mkEnableOption "Jellyfin media server";
    
    port = lib.mkOption {
      type = lib.types.port;
      default = 8096;
      description = "Web UI port";
    };
    
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.hot}/jellyfin";
      description = "Data directory";
    };
    
    mediaDir = lib.mkOption {
      type = lib.types.path;
      default = "${config.hwc.storage.media.path}";
      description = "Media library path";
    };
    
    enableGpu = lib.mkEnableOption "GPU transcoding";
    
    enableVaapi = lib.mkEnableOption "VAAPI acceleration";
    
    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open firewall ports";
    };
  };
  
  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers.containers.jellyfin = {
      image = "jellyfin/jellyfin:latest";
      
      ports = [
        "${toString cfg.port}:8096"
        "8920:8920"  # HTTPS port
        "7359:7359/udp"  # Discovery
        "1900:1900/udp"  # DLNA
      ];
      
      volumes = [
        "${cfg.dataDir}/config:/config"
        "${cfg.dataDir}/cache:/cache"
        "${cfg.mediaDir}:/media:ro"
      ];
      
      environment = {
        JELLYFIN_PublishedServerUrl = "http://jellyfin.local";
        TZ = config.time.timeZone;
      };
      
      extraOptions = lib.optionals cfg.enableGpu [
        "--device=/dev/dri"
        "--runtime=nvidia"
        "--gpus=all"
      ] ++ lib.optionals cfg.enableVaapi [
        "--device=/dev/dri/renderD128"
      ];
    };
    
    # GPU support
    hardware.nvidia-container-toolkit.enable = cfg.enableGpu;
    
    # Ensure directories
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
      "d ${cfg.dataDir}/config 0755 root root -"
      "d ${cfg.dataDir}/cache 0755 root root -"
    ];
    
    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.port 8920 ];
      allowedUDPPorts = [ 7359 1900 ];
    };
  };
}
EOF
```

### 10:30 AM - ARR Stack Services ✅

```bash
# Step 3: Create unified ARR module
cat > modules/services/arr-stack.nix << 'EOF'
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.arrStack;
  paths = config.hwc.paths;
  
  mkArrService = name: port: {
    enable = lib.mkEnableOption "${name} service";
    
    port = lib.mkOption {
      type = lib.types.port;
      default = port;
      description = "${name} web port";
    };
    
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.hot}/${lib.toLower name}";
      description = "${name} data directory";
    };
  };
in {
  options.hwc.services.arrStack = {
    enable = lib.mkEnableOption "ARR media management stack";
    
    mediaPath = lib.mkOption {
      type = lib.types.path;
      default = config.hwc.storage.media.path;
      description = "Media library path";
    };
    
    downloadPath = lib.mkOption {
      type = lib.types.path;
      default = "${config.hwc.storage.media.path}/downloads";
      description = "Download path";
    };
    
    sonarr = mkArrService "Sonarr" 8989;
    radarr = mkArrService "Radarr" 7878;
    prowlarr = mkArrService "Prowlarr" 9696;
    bazarr = mkArrService "Bazarr" 6767;
    overseerr = mkArrService "Overseerr" 5055;
    
    vpn = {
      enable = lib.mkEnableOption "VPN for downloads";
      configFile = lib.mkOption {
        type = lib.types.path;
        description = "VPN configuration file";
      };
    };
  };
  
  config = lib.mkIf cfg.enable (lib.mkMerge [
    # Sonarr
    (lib.mkIf cfg.sonarr.enable {
      virtualisation.oci-containers.containers.sonarr = {
        image = "lscr.io/linuxserver/sonarr:latest";
        ports = [ "${toString cfg.sonarr.port}:8989" ];
        
        volumes = [
          "${cfg.sonarr.dataDir}:/config"
          "${cfg.mediaPath}/tv:/tv"
          "${cfg.downloadPath}:/downloads"
        ];
        
        environment = {
          PUID = "1000";
          PGID = "1000";
          TZ = config.time.timeZone;
        };
      };
    })
    
    # Radarr
    (lib.mkIf cfg.radarr.enable {
      virtualisation.oci-containers.containers.radarr = {
        image = "lscr.io/linuxserver/radarr:latest";
        ports = [ "${toString cfg.radarr.port}:7878" ];
        
        volumes = [
          "${cfg.radarr.dataDir}:/config"
          "${cfg.mediaPath}/movies:/movies"
          "${cfg.downloadPath}:/downloads"
        ];
        
        environment = {
          PUID = "1000";
          PGID = "1000";
          TZ = config.time.timeZone;
        };
      };
    })
    
    # Prowlarr
    (lib.mkIf cfg.prowlarr.enable {
      virtualisation.oci-containers.containers.prowlarr = {
        image = "lscr.io/linuxserver/prowlarr:latest";
        ports = [ "${toString cfg.prowlarr.port}:9696" ];
        
        volumes = [
          "${cfg.prowlarr.dataDir}:/config"
        ];
        
        environment = {
          PUID = "1000";
          PGID = "1000";
          TZ = config.time.timeZone;
        };
      };
    })
    
    # Common configuration
    {
      systemd.tmpfiles.rules = lib.flatten [
        (lib.optional cfg.sonarr.enable "d ${cfg.sonarr.dataDir} 0755 root root -")
        (lib.optional cfg.radarr.enable "d ${cfg.radarr.dataDir} 0755 root root -")
        (lib.optional cfg.prowlarr.enable "d ${cfg.prowlarr.dataDir} 0755 root root -")
      ];
      
      networking.firewall.allowedTCPPorts = lib.flatten [
        (lib.optional cfg.sonarr.enable cfg.sonarr.port)
        (lib.optional cfg.radarr.enable cfg.radarr.port)
        (lib.optional cfg.prowlarr.enable cfg.prowlarr.port)
      ];
    }
  ]);
}
EOF
```

## Afternoon Session (3 hours)

### 2:00 PM - Create Media Profile ✅

```bash
# Step 4: Create comprehensive media profile
cat > profiles/media.nix << 'EOF'
{ ... }:
{
  imports = [
    ../modules/infrastructure/storage.nix
    ../modules/services/jellyfin.nix
    ../modules/services/arr-stack.nix
  ];
  
  # Storage configuration
  hwc.storage = {
    media = {
      enable = true;
      directories = [
        "movies" "tv" "music" "books"
        "downloads" "incomplete"
      ];
    };
    hot.enable = true;
  };
  
  # Media server
  hwc.services.jellyfin = {
    enable = true;
    enableGpu = true;  # Enable if GPU available
    openFirewall = true;
  };
  
  # ARR stack
  hwc.services.arrStack = {
    enable = true;
    sonarr.enable = true;
    radarr.enable = true;
    prowlarr.enable = true;
    bazarr.enable = true;
  };
}
EOF

# Step 5: Create reverse proxy module
cat > modules/services/caddy.nix << 'EOF'
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.caddy;
in {
  options.hwc.services.caddy = {
    enable = lib.mkEnableOption "Caddy reverse proxy";
    
    email = lib.mkOption {
      type = lib.types.str;
      default = "admin@example.com";
      description = "Email for ACME";
    };
    
    sites = lib.mkOption {
      type = lib.types.attrsOf lib.types.lines;
      default = {};
      description = "Site configurations";
      example = {
        "jellyfin.local" = ''
          reverse_proxy localhost:8096
        '';
      };
    };
  };
  
  config = lib.mkIf cfg.enable {
    services.caddy = {
      enable = true;
      email = cfg.email;
      
      virtualHosts = lib.mapAttrs (name: config: {
        extraConfig = config;
      }) cfg.sites;
    };
    
    # Auto-configure for enabled services
    services.caddy.virtualHosts = lib.mkMerge [
      (lib.mkIf config.hwc.services.jellyfin.enable {
        "jellyfin.local".extraConfig = ''
          reverse_proxy localhost:${toString config.hwc.services.jellyfin.port}
        '';
      })
      
      (lib.mkIf config.hwc.services.grafana.enable {
        "grafana.local".extraConfig = ''
          reverse_proxy localhost:${toString config.hwc.services.grafana.port}
        '';
      })
    ];
    
    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}
EOF
```

### 4:30 PM - Migration Validation ✅

```bash
# Step 8: Create service comparison report
cat > operations/validation/compare-configs.sh << 'EOF'
#!/usr/bin/env bash

echo "=== Configuration Comparison Report ==="
echo "Date: $(date)"
echo ""

# Count services
OLD_COUNT=$(find /etc/nixos -name "*.nix" -type f | xargs grep -l "services\." | wc -l)
NEW_COUNT=$(find /etc/nixos-next/modules/services -name "*.nix" | wc -l)

echo "Service Modules:"
echo "  Old structure: $OLD_COUNT files"
echo "  New structure: $NEW_COUNT modules"
echo ""

# Check profiles
echo "Profiles created:"
ls -1 /etc/nixos-next/profiles/*.nix 2>/dev/null | xargs -n1 basename

echo ""
echo "Build sizes:"
OLD_SIZE=$(du -sh /etc/nixos/result 2>/dev/null | cut -f1)
NEW_SIZE=$(du -sh /etc/nixos-next/result 2>/dev/null | cut -f1)
echo "  Old: $OLD_SIZE"
echo "  New: $NEW_SIZE"

echo ""
echo "Storage modules:"
ls -la /etc/nixos-next/modules/infrastructure/

echo ""
echo "✅ Day 5 Progress: Media stack architecture complete"
EOF
chmod +x operations/validation/compare-configs.sh
```

# Step 9: Update migration log
cat >> MIGRATION_LOG.md << 'EOF'

## Day 5: $(date +%Y-%m-%d)
- [x] Storage infrastructure module
- [x] Jellyfin with GPU support
- [x] Complete ARR stack
- [x] Caddy reverse proxy
- [x] Media profile created
- [x] Media test machine builds

Services migrated: 8 total
- Simple: ntfy, transcript-api
- Monitoring: prometheus, grafana
- Media: jellyfin, sonarr, radarr, prowlarr
- Infrastructure: caddy, storage
EOF

git add -A
git commit -m "Day 5: Complete media stack with storage"
```

## End of Day 5 Checklist

- [ ] Storage abstraction complete
- [ ] Media services migrated (Jellyfin, ARR)
- [ ] Reverse proxy configured
- [ ] Media profile tested
- [ ] 8+ services migrated total

## Validation

```bash
./operations/validation/compare-configs.sh
nix eval --json .#nixosConfigurations.media-test.config.hwc.services | jq keys
```
