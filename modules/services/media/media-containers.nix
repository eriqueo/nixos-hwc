# nixos-hwc/modules/services/media/media-containers.nix
#
# MEDIA CONTAINERS - Container orchestration for media services
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.services.media-containers.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../modules/services/media/media-containers.nix
#
# USAGE:
#   hwc.services.media-containers.enable = true;
#   # TODO: Add specific usage examples

{ config, lib, pkgs, ... }:

with lib;

{
  #============================================================================
  # OPTIONS - Service Configuration Interface
  #============================================================================

  options.hwc.services.media-containers = {
    enable = mkEnableOption "Media container orchestration services";
  };

  #============================================================================
  # IMPLEMENTATION - Service Definition
  #============================================================================

  config = mkIf config.hwc.services.media-containers.enable {
    # TODO: Implement media containers service configuration
    warnings = [ "Media containers service is not yet implemented" ];
  };
}

# hosts/server/modules/media-containers.nix (merged)
{ config, lib, pkgs, ... }:

let
  # Paths: keep current /opt/downloads/* layout to avoid breaking existing configs
  cfgRoot   = "/opt/downloads";
  paths = config.hwc.paths;
  hotRoot   = paths.hot;
  mediaRoot = paths.media;

  # Helper for per-service config volumes
  configVol = service: "${cfgRoot}/${service}:/config";

  # Standard env
  mediaServiceEnv = {
    PUID = "1000";
    PGID = "1000";
    TZ   = config.time.timeZone or "America/Denver";
  };

  # Networking
  mediaNetworkName   = "media-network";
  mediaNetworkOptions = [ "--network=${mediaNetworkName}" ];
  vpnNetworkOptions   = [ "--network=container:gluetun" ];

  # GPU passthrough (kept as-is)
  nvidiaGpuOptions = [
    "--device=/dev/nvidia0:/dev/nvidia0:rwm"
    "--device=/dev/nvidiactl:/dev/nvidiactl:rwm"
    "--device=/dev/nvidia-modeset:/dev/nvidia-modeset:rwm"
    "--device=/dev/nvidia-uvm:/dev/nvidia-uvm:rwm"
    "--device=/dev/nvidia-uvm-tools:/dev/nvidia-uvm-tools:rwm"
    "--device=/dev/dri:/dev/dri:rwm"
  ];
  intelGpuOptions = [ "--device=/dev/dri:/dev/dri" ];

  nvidiaEnv = {
    NVIDIA_VISIBLE_DEVICES = "all";
    NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
  };

  # Volume helpers
  hotCache          = service: "${hotRoot}/cache/${service}:/cache";
  torrentDownloads  = "${hotRoot}/downloads:/downloads";
  usenetDownloads   = "${hotRoot}/downloads:/hot-downloads";

  # Builders
  buildMediaServiceContainer = { name, image, mediaType, extraVolumes ? [], extraOptions ? [], environment ? {} }: {
    inherit image;
    autoStart = true;
    extraOptions = mediaNetworkOptions ++ nvidiaGpuOptions ++ extraOptions ++ [
      "--memory=2g" "--cpus=1.0" "--memory-swap=4g"
    ];
    environment = mediaServiceEnv // nvidiaEnv // environment;
    ports = {
      "sonarr"  = [ "127.0.0.1:8989:8989" ];
      "radarr"  = [ "127.0.0.1:7878:7878" ];
      "lidarr"  = [ "127.0.0.1:8686:8686" ];
    }.${name} or [];
    volumes = [
      (configVol name)
      "${mediaRoot}/${mediaType}:/${mediaType}"
      "${hotRoot}/downloads:/hot-downloads"
      "${hotRoot}/manual/${mediaType}:/manual"
      "${hotRoot}/quarantine/${mediaType}:/quarantine"
      "${hotRoot}/processing/${name}-temp:/processing"
    ] ++ extraVolumes;
  };

  buildDownloadContainer = { name, image, downloadPath, network ? "vpn", extraVolumes ? [], extraOptions ? [], environment ? {} }: {
    inherit image;
    autoStart = true;
    dependsOn = if network == "vpn" then [ "gluetun" ] else [];
    extraOptions = (if network == "vpn" then vpnNetworkOptions else mediaNetworkOptions) ++ nvidiaGpuOptions ++ extraOptions ++ [
      "--memory=2g" "--cpus=1.0" "--memory-swap=4g"
    ];
    environment = mediaServiceEnv // nvidiaEnv // environment;
    ports = {
      # only gluetun exposes these, so downloaders don't bind ports directly
      "qbittorrent" = [ ];
      "sabnzbd"     = [ ];
    }.${name} or [];
    volumes = [ (configVol name) downloadPath ] ++ extraVolumes;
  };
in
{
  ####################################################################
  # 0. Secrets
  ####################################################################
  sops.secrets.vpn_username = {
    sopsFile = ../../../secrets/admin.yaml;
    key = "vpn/protonvpn/username";
    mode = "0400"; owner = "root"; group = "root";
  };
  sops.secrets.vpn_password = {
    sopsFile = ../../../secrets/admin.yaml;
    key = "vpn/protonvpn/password";
    mode = "0400"; owner = "root"; group = "root";
  };
  sops.secrets.arr_api_keys_env = {
    sopsFile = ../../../secrets/arr_api_keys.env;
    format = "dotenv";
    mode = "0400"; owner = "root"; group = "root";
  };

  ####################################################################
  # 1. Media network + unit ordering
  ####################################################################
  systemd.services.init-media-network = {
    description = "Create media-network";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = let podman = "${pkgs.podman}/bin/podman"; in ''
      if ! ${podman} network ls --format "{{.Name}}" | grep -qx ${mediaNetworkName}; then
        ${podman} network create ${mediaNetworkName}
      else
        echo "${mediaNetworkName} exists"
      fi
    '';
  };

  # Ensure containers start after network/gluetun as needed
  systemd.services."podman-gluetun".after  = [ "network-online.target" "init-media-network.service" ];
  systemd.services."podman-gluetun".wants  = [ "network-online.target" ];
  systemd.services."podman-sonarr".after   = [ "init-media-network.service" ];
  systemd.services."podman-radarr".after   = [ "init-media-network.service" ];
  systemd.services."podman-lidarr".after   = [ "init-media-network.service" ];
  systemd.services."podman-prowlarr".after = [ "init-media-network.service" ];
  systemd.services."podman-slskd".after    = [ "init-media-network.service" ];
  systemd.services."podman-soularr".after  = [ "init-media-network.service" ];
  systemd.services."podman-qbittorrent".after = [ "podman-gluetun.service" ];
  systemd.services."podman-sabnzbd".after     = [ "podman-gluetun.service" ];

  # Build gluetun env file from SOPS before gluetun starts
  systemd.services.gluetun-env-setup = {
    description = "Generate Gluetun env from SOPS";
    before   = [ "podman-gluetun.service" ];
    wantedBy = [ "podman-gluetun.service" ];
    wants    = [ "sops-install-secrets.service" ];
    after    = [ "sops-install-secrets.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      mkdir -p ${cfgRoot}
      VPN_USERNAME=$(cat ${config.sops.secrets.vpn_username.path})
      VPN_PASSWORD=$(cat ${config.sops.secrets.vpn_password.path})
      cat > ${cfgRoot}/.env <<EOF
VPN_SERVICE_PROVIDER=protonvpn
VPN_TYPE=openvpn
OPENVPN_USER=$VPN_USERNAME
OPENVPN_PASSWORD=$VPN_PASSWORD
SERVER_COUNTRIES=Netherlands
HEALTH_VPN_DURATION_INITIAL=30s
EOF
      chmod 600 ${cfgRoot}/.env
      chown root:root ${cfgRoot}/.env
    '';
  };

  ####################################################################
  # 2. Containers (Podman)
  ####################################################################
  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      # VPN base (exposes downloaders’ UIs on localhost only)
      gluetun = {
        image = "qmcgaw/gluetun:latest";
        autoStart = true;
        extraOptions = [
          "--cap-add=NET_ADMIN"
          "--device=/dev/net/tun:/dev/net/tun"
          "--network=${mediaNetworkName}"
          "--network-alias=gluetun"
        ];
        ports = [
          "127.0.0.1:8080:8080"  # qBittorrent UI
          "127.0.0.1:8081:8085"  # SABnzbd (container uses 8085 internally)
        ];
        volumes = [ "${cfgRoot}/gluetun:/gluetun" ];
        environmentFiles = [ "${cfgRoot}/.env" ];
        environment = { TZ = config.time.timeZone or "America/Denver"; };
      };

      # Download clients (share gluetun’s netns)
      qbittorrent = buildDownloadContainer {
        name = "qbittorrent";
        image = "lscr.io/linuxserver/qbittorrent";
        downloadPath = torrentDownloads;
        network = "vpn";
        extraVolumes = [ (hotCache "qbittorrent") "${mediaRoot}:/cold-media" ];
        environment = { WEBUI_PORT = "8080"; };
      };

      sabnzbd = buildDownloadContainer {
        name = "sabnzbd";
        image = "lscr.io/linuxserver/sabnzbd:latest";
        downloadPath = usenetDownloads;
        network = "vpn";
        extraVolumes = [ "${hotRoot}/cache:/incomplete-downloads" ];
      };

      # *arr apps
      lidarr = buildMediaServiceContainer {
        name = "lidarr"; image = "lscr.io/linuxserver/lidarr:latest"; mediaType = "music";
      };
      sonarr = buildMediaServiceContainer {
        name = "sonarr"; image = "lscr.io/linuxserver/sonarr:latest"; mediaType = "tv";
      };
      radarr = buildMediaServiceContainer {
        name = "radarr"; image = "lscr.io/linuxserver/radarr:latest"; mediaType = "movies";
      };
      prowlarr = {
        image = "lscr.io/linuxserver/prowlarr:latest";
        autoStart = true;
        extraOptions = mediaNetworkOptions ++ nvidiaGpuOptions ++ [ "--memory=1g" "--cpus=0.5" ];
        environment = mediaServiceEnv // nvidiaEnv;
        ports = [ "127.0.0.1:9696:9696" ];
        volumes = [ (configVol "prowlarr") ];
      };

      # slskd
      slskd = {
        image = "slskd/slskd:latest";
        autoStart = true;
        extraOptions = mediaNetworkOptions;
        environment = mediaServiceEnv // {
          SLSKD_USERNAME = "eriqueok";
          SLSKD_PASSWORD = "il0wwlm?";
          SLSKD_SLSK_USERNAME = "eriqueok";
          SLSKD_SLSK_PASSWORD = "il0wwlm?";
        };
        ports = [ "127.0.0.1:5030:5030" ];
        cmd = [ "--config" "/config/slskd.yml" ];
        volumes = [
          (configVol "slskd")
          "${hotRoot}/downloads:/downloads"
          "${mediaRoot}/music:/data/music:ro"
          "${mediaRoot}/music-soulseek:/data/music-soulseek:ro"
          "${mediaRoot}/music:/data/downloads"
        ];
      };

      # Soularr (no web UI; /data contains config.ini)
      soularr = {
        image = "docker.io/mrusse08/soularr:latest";
        autoStart = true;
        extraOptions = mediaNetworkOptions ++ [ "--memory=1g" "--cpus=0.5" ];
        volumes = [
          (configVol "soularr")
          "${cfgRoot}/soularr:/data"
          "${hotRoot}/downloads:/downloads"
        ];
        dependsOn = [ "slskd" "lidarr" ];
      };

      # Navidrome - Enable reverse proxy support for Caddy subpath
      navidrome = {
        image = "deluan/navidrome";
        autoStart = true;
        extraOptions = mediaNetworkOptions;
        environment = {
          ND_MUSICFOLDER   = "/music";
          ND_DATAFOLDER    = "/data";
          ND_LOGLEVEL      = "info";
          ND_SESSIONTIMEOUT= "24h";
          # No ND_BASEURL - run at root for direct access
          ND_INITIAL_ADMIN_USER = "admin";
          ND_INITIAL_ADMIN_PASSWORD = "il0wwlm?";
        };
        ports = [ "0.0.0.0:4533:4533" ];
        volumes = [ (configVol "navidrome") "${mediaRoot}/music:/music:ro" ];
      };
    };
  };

  ####################################################################
  # 3. Config seeders & helpers
  ####################################################################
  # Seed Soularr /data/config.ini from SOPS env (dummy keys ok; replace later)
  systemd.services.soularr-config = {
    description = "Seed Soularr /data/config.ini from SOPS env";
    wantedBy = [ "podman-soularr.service" ];
    before   = [ "podman-soularr.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      set -e
      mkdir -p ${cfgRoot}/soularr
      . ${config.sops.secrets.arr_api_keys_env.path} || true
      cfg=${cfgRoot}/soularr/config.ini
      cat > "$cfg" <<EOF
[Lidarr]
host_url = http://lidarr:8686
api_key  = ''${LIDARR_API_KEY:-dummy-lidarr}
download_dir = /downloads

[Slskd]
host_url = http://slskd:5030
api_key  = ''${SLSKD_API_KEY:-dummy-sls}
download_dir = /downloads

[General]
interval = 300
EOF
      chmod 600 "$cfg"
    '';
  };

  ####################################################################
  # CADDY REVERSE PROXY CONFIGURATION
  ####################################################################
  # Caddy reverse proxy for all services
  services.caddy = {
    enable = true;
    virtualHosts = {
      "hwc.ocelot-wahoo.ts.net".extraConfig = ''
      # Obsidian LiveSync proxy: strip /sync prefix and forward to CouchDB
      @sync path /sync*
      handle @sync {
        uri strip_prefix /sync
        reverse_proxy 127.0.0.1:5984 {
          # preserve the Host header for CouchDB auth
          header_up Host {host}
          # rewrite any CouchDB redirect back under /sync
          header_down Location ^/(.*)$ /sync/{1}
        }
      }

      # Download clients (VPN-routed)
      handle_path /qbt/* {
        reverse_proxy localhost:8080
      }
      handle_path /sab/* {
        reverse_proxy localhost:8081
      }

      # Media services
      handle_path /media/* {
        reverse_proxy localhost:8096
      }

      # Immich - Direct port exposure (no subpath proxy due to SvelteKit issues)
      # HTTPS access: https://hwc.ocelot-wahoo.ts.net:2283 (Tailscale HTTPS)
      # Local access: http://192.168.1.13:2283 (direct)
      # Both use same database/credentials

      # Navidrome - strip /navidrome prefix for direct backend access
      handle_path /navidrome/* {
        reverse_proxy 127.0.0.1:4533
      }

      # *ARR stack - Keep UrlBase in apps, DO NOT strip prefix in Caddy
      # Apps have UrlBase=/app, Caddy passes paths as-is - no conflict

      # ---- Sonarr
      handle /sonarr { redir /sonarr/ 301 }
      route /sonarr* {
        reverse_proxy localhost:8989 {
          header_up Host {host}
          header_up X-Forwarded-Host {host}
          header_up X-Forwarded-Proto {scheme}
          header_up X-Forwarded-Port {server_port}
          header_up X-Forwarded-For {remote}
          header_up X-Real-IP {remote}
        }
      }

      # ---- Radarr
      handle /radarr { redir /radarr/ 301 }
      route /radarr* {
        reverse_proxy localhost:7878 {
          header_up Host {host}
          header_up X-Forwarded-Host {host}
          header_up X-Forwarded-Proto {scheme}
          header_up X-Forwarded-Port {server_port}
          header_up X-Forwarded-For {remote}
          header_up X-Real-IP {remote}
        }
      }

      # ---- Lidarr
      handle /lidarr { redir /lidarr/ 301 }
      route /lidarr* {
        reverse_proxy localhost:8686 {
          header_up Host {host}
          header_up X-Forwarded-Host {host}
          header_up X-Forwarded-Proto {scheme}
          header_up X-Forwarded-Port {server_port}
          header_up X-Forwarded-For {remote}
          header_up X-Real-IP {remote}
        }
      }

      # ---- Prowlarr
      handle /prowlarr { redir /prowlarr/ 301 }
      route /prowlarr* {
        reverse_proxy localhost:9696 {
          header_up Host {host}
          header_up X-Forwarded-Host {host}
          header_up X-Forwarded-Proto {scheme}
          header_up X-Forwarded-Port {server_port}
          header_up X-Forwarded-For {remote}
          header_up X-Real-IP {remote}
        }
      }

      # ---- slskd
      handle /slskd { redir /slskd/ 301 }
      handle_path /slskd/* {
        uri strip_prefix /slskd
        reverse_proxy 127.0.0.1:5030 {
          header_up Host {host}
          header_up X-Forwarded-Host {host}
          header_up X-Forwarded-Proto {scheme}
          header_up X-Forwarded-Port {server_port}
          header_up X-Forwarded-For {remote}
          header_up X-Real-IP {remote}
        }
      }

      # Business services
      handle /business* {
        reverse_proxy localhost:8000
      }
      handle /dashboard* {
        reverse_proxy localhost:8501
      }

      # Private notification service - strip /notify prefix for mobile app compatibility
      handle_path /notify/* {
        reverse_proxy localhost:8282
      }

      # Monitoring services
      handle_path /grafana/* {
        reverse_proxy localhost:3000
      }
      handle_path /prometheus/* {
        reverse_proxy localhost:9090
      }
    '';

    };
  };

  # Firewall: only expose HTTP/S publicly, other services only on Tailscale
  networking.firewall.allowedTCPPorts = [ 80 443 ];
  networking.firewall.interfaces."tailscale0" = {
    allowedTCPPorts = [ 5984 8000 8501 8282 2283 ];
  };

  # Fix config file permissions for container access
  systemd.services.arr-config-permissions = {
    description = "Fix *arr config file permissions for container access";
    after = [ "network-online.target" ];
    before = [ "podman-sonarr.service" "podman-radarr.service" "podman-lidarr.service" "podman-prowlarr.service" "podman-sabnzbd.service" "podman-qbittorrent.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      # Fix ownership for all *arr config directories and files
      for app in sonarr radarr lidarr prowlarr sabnzbd qbittorrent gluetun; do
        if [ -d "${cfgRoot}/$app" ]; then
          chown -R 1000:100 "${cfgRoot}/$app"
          echo "Fixed permissions for $app config"
        f
