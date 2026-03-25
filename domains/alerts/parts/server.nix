# domains/alerts/parts/server.nix
#
# ntfy notification server container
#
# NAMESPACE: hwc.alerts.server.*
#
# DEPENDENCIES:
#   - hwc.paths (for dataDir)
#
# USED BY:
#   - Alert routing system (webhook receiver)
#   - Mobile push notifications
#   - Cross-machine alerting

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.alerts.server;

  # ntfy server config — enables iOS push via ntfy.sh upstream relay
  ntfyServerConfig = pkgs.writeText "server.yml" ''
    base-url: https://hwc.ocelot-wahoo.ts.net:2586
    upstream-base-url: https://ntfy.sh
    log-level: debug
  '';
in
{
  config = lib.mkIf cfg.enable {
    # Container configuration
    virtualisation.oci-containers.containers.ntfy = {
      image = cfg.image;
      cmd = [ "serve" ];  # CRITICAL: Tell ntfy to run the server
      ports = [ "${toString cfg.port}:80" ];
      volumes = [
        "${cfg.dataDir}:/var/cache/ntfy"
        "${ntfyServerConfig}:/etc/ntfy/server.yml:ro"
      ];
      environment = {
        TZ = "America/Denver";
      };
    };

    # Ensure directories exist
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 root root -"
      "d ${cfg.dataDir}/etc 0750 root root -"
    ];

    # Expose ntfy via Tailscale HTTPS (persists across reboots)
    # iOS ntfy app connects to https://hwc.ocelot-wahoo.ts.net:2586
    systemd.services.tailscale-serve-ntfy = {
      description = "Tailscale HTTPS serve for ntfy";
      after = [ "tailscaled.service" "podman-ntfy.service" ];
      wants = [ "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg --https ${toString cfg.port} http://127.0.0.1:${toString cfg.port}";
        ExecStop = "${pkgs.tailscale}/bin/tailscale serve --https=${toString cfg.port} off";
      };
    };

    # Open firewall
    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
