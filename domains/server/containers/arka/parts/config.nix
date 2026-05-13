{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.containers.arka;
  podman = "${pkgs.podman}/bin/podman";
  networkName = "arka-network";
  backendEnvFile = config.age.secrets."arka-backend-env".path;
  postgresEnvFile = config.age.secrets."arka-postgres-env".path;
in
{
  config = lib.mkIf cfg.enable {

    #=========================================================================
    # STORAGE DIRECTORIES
    #=========================================================================
    systemd.tmpfiles.rules = [
      "d ${cfg.storage.dataDir} 0755 root root -"
      "d ${cfg.storage.dataDir}/postgres 0700 999 999 -"
    ];

    #=========================================================================
    # CONTAINER NETWORK
    #=========================================================================
    systemd.services.init-arka-network = {
      description = "Create podman arka-network (idempotent)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail
        if ! ${podman} network ls --format "{{.Name}}" | grep -qx "${networkName}"; then
          ${podman} network create ${networkName}
        else
          echo "${networkName} already exists"
        fi
      '';
    };

    #=========================================================================
    # POSTGRESQL CONTAINER
    #=========================================================================
    virtualisation.oci-containers.containers.arka-postgres = {
      image = cfg.images.postgres;
      autoStart = true;
      extraOptions = [
        "--network=${networkName}"
        "--network-alias=postgres"
      ];
      volumes = [
        "${cfg.storage.dataDir}/postgres:/var/lib/postgresql/data:rw"
      ];
      environment = {
        POSTGRES_DB = "arka_mcp_gateway";
        POSTGRES_USER = "arka";
        POSTGRES_INITDB_ARGS = "--encoding=UTF8 --locale=C";
      };
      environmentFiles = [ postgresEnvFile ];
    };

    systemd.services.podman-arka-postgres = {
      after = [ "init-arka-network.service" ];
      requires = [ "init-arka-network.service" ];
    };

    #=========================================================================
    # BACKEND CONTAINER
    #=========================================================================
    virtualisation.oci-containers.containers.arka-backend = {
      image = cfg.images.backend;
      autoStart = true;
      dependsOn = [ "arka-postgres" ];
      extraOptions = [
        "--network=${networkName}"
        "--network-alias=backend"
        "--pull=never"
      ];
      ports = [
        "127.0.0.1:${toString cfg.ports.backend}:8000"
      ];
      environment = {
        ARKA_JWT_ALGORITHM = "HS256";
        ARKA_JWT_ACCESS_TOKEN_EXPIRE_MINUTES = "30";
        ARKA_JWT_REFRESH_TOKEN_EXPIRE_DAYS = "7";
        ARKA_FRONTEND_URL = cfg.urls.frontend;
        ARKA_BACKEND_URL = cfg.urls.backend;
        ARKA_WORKER_URL = "http://worker:8001";
        ARKA_ENVIRONMENT = "production";
        ENV_FOR_DYNACONF = "production";
        ARKA_LOG_LEVEL = "INFO";
      };
      environmentFiles = [ backendEnvFile ];
      cmd = [ "uv" "run" "uvicorn" "main:app" "--host" "0.0.0.0" "--port" "8000" "--workers" "1" ];
    };

    systemd.services.podman-arka-backend = {
      serviceConfig = {
        Restart = lib.mkForce "on-failure";
        RestartSec = "5s";
      };
    };

    #=========================================================================
    # WORKER CONTAINER
    #=========================================================================
    virtualisation.oci-containers.containers.arka-worker = {
      image = cfg.images.backend;
      autoStart = true;
      dependsOn = [ "arka-postgres" ];
      extraOptions = [
        "--network=${networkName}"
        "--network-alias=worker"
        "--pull=never"
      ];
      ports = [
        "127.0.0.1:${toString cfg.ports.worker}:8001"
      ];
      environment = {
        ARKA_JWT_ALGORITHM = "HS256";
        ARKA_FRONTEND_URL = cfg.urls.frontend;
        ARKA_BACKEND_URL = cfg.urls.backend;
        ARKA_WORKER_URL = "http://worker:8001";
        ARKA_ENVIRONMENT = "production";
        ENV_FOR_DYNACONF = "production";
        ARKA_LOG_LEVEL = "INFO";
      };
      environmentFiles = [ backendEnvFile ];
      cmd = [ "uv" "run" "uvicorn" "worker:app" "--host" "0.0.0.0" "--port" "8001" ];
    };

    systemd.services.podman-arka-worker = {
      serviceConfig = {
        Restart = lib.mkForce "on-failure";
        RestartSec = "5s";
      };
    };

    #=========================================================================
    # FRONTEND CONTAINER
    #=========================================================================
    virtualisation.oci-containers.containers.arka-frontend = {
      image = cfg.images.frontend;
      autoStart = true;
      dependsOn = [ "arka-backend" ];
      extraOptions = [
        "--network=${networkName}"
        "--network-alias=frontend"
        "--pull=never"
      ];
      ports = [
        "127.0.0.1:${toString cfg.ports.frontend}:80"
      ];
    };

    #=========================================================================
    # CADDY REVERSE PROXY
    #=========================================================================
    services.caddy.extraConfig = ''
      # Arka MCP Gateway — port ${toString cfg.ports.caddy}
      hwc.ocelot-wahoo.ts.net:${toString cfg.ports.caddy} {
        tls {
          get_certificate tailscale
          protocols tls1.2 tls1.3
          alpn h2 http/1.1
        }
        encode zstd gzip
        reverse_proxy http://127.0.0.1:${toString cfg.ports.frontend} {
          header_up Host {host}
          header_up X-Real-IP {remote}
          header_up X-Forwarded-For {remote}
          header_up X-Forwarded-Proto {scheme}
          header_up X-Forwarded-Host {host}
          flush_interval -1
        }
      }
    '';

    networking.firewall.allowedTCPPorts = [ cfg.ports.caddy ];

    # Allow arka containers (10.89.1.0/24) to reach HWC MCP on port 6200
    networking.firewall.extraCommands = ''
      iptables -A nixos-fw -s 10.89.1.0/24 -p tcp --dport 6200 -j nixos-fw-accept
    '';
    networking.firewall.extraStopCommands = ''
      iptables -D nixos-fw -s 10.89.1.0/24 -p tcp --dport 6200 -j nixos-fw-accept 2>/dev/null || true
    '';
  };
}
