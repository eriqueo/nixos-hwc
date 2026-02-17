# domains/server/native/webdav/index.nix
#
# WebDAV server implementation using dufs
# Lightweight Rust-based WebDAV server for RetroArch save sync
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.native.webdav;

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
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./options.nix
  ];

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
    hwc.server.shared.routes = lib.mkIf cfg.reverseProxy.enable [
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
        assertion = !cfg.reverseProxy.enable || config.hwc.server.reverseProxy.enable;
        message = "hwc.server.native.webdav.reverseProxy requires hwc.server.reverseProxy.enable = true";
      }
      {
        assertion = cfg.auth.usernameFile != null && cfg.auth.passwordFile != null;
        message = "hwc.server.native.webdav requires auth.usernameFile and auth.passwordFile to be set for security";
      }
      {
        assertion = !cfg.retroarch.enable || config.hwc.server.native.retroarch.enable;
        message = "hwc.server.native.webdav.retroarch requires hwc.server.native.retroarch.enable = true";
      }
    ];
  };
}
