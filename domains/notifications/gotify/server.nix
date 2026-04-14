# domains/notifications/gotify/server.nix
#
# Gotify notification server container
#
# NAMESPACE: hwc.notifications.gotify.*
#
# DEPENDENCIES:
#   - hwc.paths (for dataDir)
#
# USED BY:
#   - Alert routing system (Alertmanager bridge)
#   - Mobile push notifications (iGotify)
#   - Cross-machine alerting

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.notifications.gotify;

  # Generate an env file from the raw password secret
  adminPasswordEnvFile = pkgs.writeShellScript "gotify-admin-env" ''
    PASS=$(cat ${cfg.adminPasswordFile})
    echo "GOTIFY_DEFAULTUSER_PASS=$PASS" > /run/gotify-admin-env
    chmod 0400 /run/gotify-admin-env
  '';
in
{
  options.hwc.notifications.gotify = {
    enable = lib.mkEnableOption "gotify notification server (container)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 2586;
      description = "External HTTPS port (Tailscale serve). Clients connect here.";
    };

    internalPort = lib.mkOption {
      type = lib.types.port;
      default = 2587;
      description = "Internal container port on localhost. Tailscale proxies from port to internalPort.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${(config.hwc.paths or {}).state or "/var/lib"}/gotify";
      description = "Data directory for gotify server";
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "gotify/server:latest";
      description = "Gotify container image";
    };

    adminPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Environment file containing GOTIFY_DEFAULTUSER_PASS=<password>";
    };

    # TAXONOMY v1.0 — map of "universe:domain" → token file path
    # Auto-populated in server/config.nix by scanning config.age.secrets for
    # secrets named "gotify-{universe}-{domain}" (e.g. gotify-hwc-ops).
    # Adding a new Gotify app only requires creating the agenix secret — no
    # further edits to this file or secrets-api.nix.
    tokens = lib.mkOption {
      type    = lib.types.attrsOf (lib.types.nullOr lib.types.path);
      default = {};
      example = { "hwc:ops" = "/run/agenix/gotify-hwc-ops"; "home:admin" = "/run/agenix/gotify-home-admin"; };
      description = ''
        Map of Gotify app key to decrypted token file path.
        Key format: "{universe}:{domain}"  (e.g. "hwc:ops", "home:admin")
        Populated automatically from agenix secrets named gotify-{universe}-{domain}.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Container configuration
    virtualisation.oci-containers.containers.gotify = {
      image = cfg.image;
      ports = [ "127.0.0.1:${toString cfg.internalPort}:80" ];
      volumes = [
        "${cfg.dataDir}:/app/data"
      ];
      environment = {
        TZ = "America/Denver";
        GOTIFY_DEFAULTUSER_NAME = "admin";
      };
      environmentFiles = lib.optional (cfg.adminPasswordFile != null) "/run/gotify-admin-env";
    };

    # Generate env file from raw password before container starts
    systemd.services.podman-gotify = lib.mkIf (cfg.adminPasswordFile != null) {
      serviceConfig.ExecStartPre = [ "+${adminPasswordEnvFile}" ];
    };

    # Ensure directories exist
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 root root -"
    ];

    # Expose gotify via Tailscale HTTPS (persists across reboots)
    # iGotify app connects to https://hwc.ocelot-wahoo.ts.net:2586
    systemd.services.tailscale-serve-gotify = {
      description = "Tailscale HTTPS serve for gotify";
      after = [ "tailscaled.service" "podman-gotify.service" "network-online.target" ];
      wants = [ "tailscaled.service" "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Wait for Tailscale to be connected (not just the daemon started)
        ExecStartPre = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 30); do ${pkgs.tailscale}/bin/tailscale status >/dev/null 2>&1 && exit 0; sleep 1; done; echo Tailscale not ready; exit 1'";
        ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg --https ${toString cfg.port} http://127.0.0.1:${toString cfg.internalPort}";
        ExecStop = "${pkgs.tailscale}/bin/tailscale serve --https=${toString cfg.port} off";
      };
    };

    # No firewall rule needed — external access is via Tailscale HTTPS serve,
    # and internal services connect to 127.0.0.1:internalPort directly.
  };
}
