# NixOS Module for Remodel API Podman Container
#
# This module deploys the Bathroom Remodel Planner API as a Podman container
# with PostgreSQL database and Caddy reverse proxy integration.
#
# Usage:
#   Add to your server configuration:
#   imports = [ ./remodel-api/nix/container.nix ];
#   services.remodel-api.enable = true;

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.remodel-api;
in

{
  options.services.remodel-api = {
    enable = mkEnableOption "Bathroom Remodel Planner API";

    domain = mkOption {
      type = types.str;
      default = "remodel.yourdomain.com";
      description = "Domain name for the remodel planner";
    };

    port = mkOption {
      type = types.port;
      default = 8001;
      description = "Internal port for the API container";
    };

    databasePassword = mkOption {
      type = types.str;
      default = "";
      description = "PostgreSQL password (use agenix secret in production)";
    };
  };

  config = mkIf cfg.enable {
    # PostgreSQL database for remodel API
    services.postgresql = {
      enable = true;
      ensureDatabases = [ "remodel" ];
      ensureUsers = [
        {
          name = "remodel";
          ensureDBOwnership = true;
        }
      ];
    };

    # Podman container for the API
    virtualisation.oci-containers.containers.remodel-api = {
      image = "remodel-api:latest";  # Build and tag the image first
      autoStart = true;

      ports = [
        "127.0.0.1:${toString cfg.port}:8000"
      ];

      environment = {
        DATABASE_URL = "postgresql://remodel:${cfg.databasePassword}@host.containers.internal:5432/remodel";
      };

      # Allow container to access host PostgreSQL
      extraOptions = [
        "--network=slirp4netns:allow_host_loopback=true"
      ];

      volumes = [
        "/var/lib/remodel-api/pdfs:/app/pdfs"
      ];
    };

    # Create data directory
    systemd.tmpfiles.rules = [
      "d /var/lib/remodel-api 0755 root root -"
      "d /var/lib/remodel-api/pdfs 0755 root root -"
    ];

    # Caddy reverse proxy configuration
    services.caddy.virtualHosts."${cfg.domain}" = {
      extraConfig = ''
        # API endpoints
        handle /api/* {
          reverse_proxy localhost:${toString cfg.port}
        }

        # Health check
        handle /health {
          reverse_proxy localhost:${toString cfg.port}
        }

        # Serve frontend static files (future)
        handle /* {
          root * /var/www/remodel-planner
          file_server
          try_files {path} /index.html
        }
      '';
    };

    # Firewall: Allow HTTP/HTTPS (Caddy handles this)
    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}
