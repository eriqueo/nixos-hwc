# domains/alerts/parts/server.nix
#
# Gotify notification server container
#
# NAMESPACE: hwc.alerts.server.*
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
  cfg = config.hwc.alerts.server;
in
{
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
      environmentFiles = lib.optional (cfg.adminPasswordFile != null) cfg.adminPasswordFile;
    };

    # Ensure directories exist
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 root root -"
    ];

    # Expose gotify via Tailscale HTTPS (persists across reboots)
    # iGotify app connects to https://hwc.ocelot-wahoo.ts.net:2586
    systemd.services.tailscale-serve-gotify = {
      description = "Tailscale HTTPS serve for gotify";
      after = [ "tailscaled.service" "podman-gotify.service" ];
      wants = [ "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg --https ${toString cfg.port} http://127.0.0.1:${toString cfg.internalPort}";
        ExecStop = "${pkgs.tailscale}/bin/tailscale serve --https=${toString cfg.port} off";
      };
    };

    # No firewall rule needed — external access is via Tailscale HTTPS serve,
    # and internal services connect to 127.0.0.1:internalPort directly.
  };
}
