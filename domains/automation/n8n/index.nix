# domains/automation/n8n/index.nix
#
# N8N - Workflow automation platform for alert routing and notifications
# Uses official n8nio/n8n container image
#
# NAMESPACE: hwc.automation.n8n.*
#
# DEPENDENCIES:
#   - hwc.paths.state (data directory)
#   - Optional: hwc.monitoring.alertmanager (webhook consumer)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.automation.n8n;
in
{
  #==========================================================================
  # IMPORTS
  #==========================================================================
  imports = [
    ./options.nix
    ./sys.nix
  ];

  #==========================================================================
  # IMPLEMENTATION (non-container config)
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Firewall - localhost + Tailscale
    networking.firewall.interfaces."lo".allowedTCPPorts = [ cfg.port ];
    networking.firewall.interfaces."tailscale0".allowedTCPPorts =
      lib.optional (config.networking.interfaces ? "tailscale0") cfg.port;

    # Tailscale Funnel service - expose /webhook publicly on port 10000
    systemd.services.tailscale-funnel-n8n = {
      description = "Tailscale Funnel for n8n webhook (public Slack integration)";
      after = [ "network.target" "tailscaled.service" "podman-n8n.service" ];
      wants = [ "tailscaled.service" "podman-n8n.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 5";
        ExecStart = "${pkgs.tailscale}/bin/tailscale funnel --bg --https=10000 --set-path=/webhook http://127.0.0.1:${toString cfg.port}";
        ExecStop = "${pkgs.tailscale}/bin/tailscale funnel --https=10000 off";
      };
    };

    # Tailscale Funnel - expose FULL n8n publicly (for Manus AI, external integrations)
    systemd.services.tailscale-funnel-n8n-full = lib.mkIf cfg.funnel.enable {
      description = "Tailscale Funnel for full n8n access (Manus AI, etc.)";
      after = [ "network.target" "tailscaled.service" "podman-n8n.service" ];
      wants = [ "tailscaled.service" "podman-n8n.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 5";
        ExecStart = "${pkgs.tailscale}/bin/tailscale funnel --bg --https=${toString cfg.funnel.port} http://127.0.0.1:${toString cfg.port}";
        ExecStop = "${pkgs.tailscale}/bin/tailscale funnel --https=${toString cfg.funnel.port} off";
      };
    };

    #========================================================================
    # VALIDATION
    #========================================================================
    assertions = [
      {
        assertion = cfg.port != 0;
        message = "n8n port must be configured (hwc.automation.n8n.port)";
      }
      {
        assertion = cfg.dataDir != "";
        message = "n8n data directory must be configured (hwc.automation.n8n.dataDir)";
      }
    ];
  };
}
