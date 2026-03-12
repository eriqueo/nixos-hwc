# domains/gaming/webdav/index.nix
#
# WebDAV server implementation using dufs
# Lightweight Rust-based WebDAV server for RetroArch save sync
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.gaming.webdav;

  # Build the dufs command with authentication and paths
  # dufs supports basic auth via --auth user:pass@/path format
  dufsCommand = pkgs.writeShellScript "webdav-start" ''
    set -euo pipefail

    # Read credentials from agenix secrets
    USERNAME=""
    PASSWORD=""

    ${lib.optionalString (cfg.auth.usernameFile != null) ''
      USERNAME=$(cat ${cfg.auth.usernameFile})
    ''}
    ${lib.optionalString (cfg.auth.passwordFile != null) ''
      PASSWORD=$(cat ${cfg.auth.passwordFile})
    ''}

    # Build auth argument if credentials are provided
    AUTH_ARG=""
    if [ -n "$USERNAME" ] && [ -n "$PASSWORD" ]; then
      # dufs auth format: --auth user:pass@/path (read+write access to path)
      AUTH_ARG="--auth $USERNAME:$PASSWORD@/"
    fi

    # Determine root directory based on configuration
    ROOT_DIR="${cfg.retroarch.dataDir}"

    # Start dufs with WebDAV enabled
    exec ${pkgs.dufs}/bin/dufs \
      --bind ${cfg.settings.bindAddress} \
      --port ${toString cfg.settings.port} \
      --allow-upload \
      --allow-delete \
      --allow-search \
      $AUTH_ARG \
      "$ROOT_DIR"
  '';
in
{
  # OPTIONS
  options.hwc.gaming.webdav = {
    enable = lib.mkEnableOption "WebDAV server using dufs for file synchronization";

    settings = {
      port = lib.mkOption {
        type = lib.types.port;
        default = 8282;
        description = "Internal port for dufs WebDAV server";
      };

      bindAddress = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Address to bind the WebDAV server (localhost for reverse proxy)";
      };
    };

    # Authentication
    auth = {
      usernameFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to file containing WebDAV username (from agenix)";
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to file containing WebDAV password (from agenix)";
      };
    };

    # RetroArch-specific preset
    retroarch = {
      enable = lib.mkEnableOption "Expose RetroArch save directories via WebDAV";

      syncSaves = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Expose .srm save RAM files for sync";
      };

      syncStates = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Expose save state files for sync";
      };

      dataDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/hwc/retroarch";
        description = "RetroArch data directory containing saves and states";
      };
    };

    # Caddy reverse proxy integration
    reverseProxy = {
      enable = lib.mkEnableOption "Enable Caddy reverse proxy route for WebDAV";

      path = lib.mkOption {
        type = lib.types.str;
        default = "/retroarch-sync";
        description = "URL path for WebDAV access via reverse proxy";
      };
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open firewall port for direct WebDAV access (not needed with reverse proxy)";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Install dufs package
    environment.systemPackages = [ pkgs.dufs ];

    # Create data directories for RetroArch sync
    systemd.tmpfiles.rules = lib.mkIf cfg.retroarch.enable [
      "d ${cfg.retroarch.dataDir} 0755 eric users -"
      "d ${cfg.retroarch.dataDir}/saves 0755 eric users -"
      "d ${cfg.retroarch.dataDir}/states 0755 eric users -"
    ];

    # dufs WebDAV systemd service
    systemd.services.webdav = {
      description = "dufs WebDAV server for file synchronization";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = dufsCommand;
        Restart = "always";
        RestartSec = "5s";

        # Run as eric user for access to RetroArch directories
        User = "eric";
        Group = "users";

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths = [ cfg.retroarch.dataDir ];

        # Allow reading secrets
        SupplementaryGroups = [ "secrets" ];
      };
    };

    # Firewall configuration (if direct access is needed)
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [
      cfg.settings.port
    ];

    # Register route with shared routes for Caddy reverse proxy
    hwc.networking.shared.routes = lib.mkIf cfg.reverseProxy.enable [
      {
        name = "webdav-retroarch";
        mode = "subpath";
        path = cfg.reverseProxy.path;
        upstream = "http://${cfg.settings.bindAddress}:${toString cfg.settings.port}";
        needsUrlBase = false;  # Strip prefix - dufs serves from root
        headers = {
          "X-Forwarded-Prefix" = cfg.reverseProxy.path;
        };
      }
    ];

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = !cfg.reverseProxy.enable || config.hwc.networking.reverseProxy.enable;
        message = "hwc.gaming.webdav.reverseProxy requires hwc.networking.reverseProxy.enable = true";
      }
      {
        assertion = cfg.auth.usernameFile != null && cfg.auth.passwordFile != null;
        message = "hwc.gaming.webdav requires auth.usernameFile and auth.passwordFile to be set for security";
      }
      {
        assertion = !cfg.retroarch.enable || config.hwc.gaming.retroarch.enable;
        message = "hwc.gaming.webdav.retroarch requires hwc.gaming.retroarch.enable = true";
      }
    ];
  };
}
