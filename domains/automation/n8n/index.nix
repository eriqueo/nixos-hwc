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
  paths = config.hwc.paths;
in
{
  # OPTIONS
  options.hwc.automation.n8n = {
    enable = lib.mkEnableOption "n8n workflow automation platform";

    image = lib.mkOption {
      type = lib.types.str;
      default = "docker.io/n8nio/n8n:latest";
      description = "n8n container image";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 5678;
      description = "n8n web interface port";
    };

    webhookUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://${config.hwc.networking.shared.rootHost}";
      defaultText = "https://\${config.hwc.networking.shared.rootHost}";
      description = "Base URL for webhook callbacks";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.state}/n8n";
      description = "Data directory for n8n workflows and configuration";
    };

    timezone = lib.mkOption {
      type = lib.types.str;
      default = "America/Denver";
      description = "Timezone for workflow scheduling";
    };

    encryption = {
      keyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to encryption key file for credentials (via agenix)";
      };
    };

    database = {
      type = lib.mkOption {
        type = lib.types.enum [ "sqlite" "postgres" ];
        default = "sqlite";
        description = "Database type for n8n";
      };

      sqlite = {
        file = lib.mkOption {
          type = lib.types.path;
          default = "${paths.state}/n8n/database.sqlite";
          description = "SQLite database file path";
        };
      };
    };

    extraEnv = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Additional environment variables for n8n";
      example = {
        N8N_METRICS = "true";
        N8N_LOG_LEVEL = "info";
      };
    };

    funnel = {
      enable = lib.mkEnableOption "Expose full n8n publicly via Tailscale Funnel (for Manus AI, etc.)";

      port = lib.mkOption {
        type = lib.types.port;
        default = 8443;
        description = "Public HTTPS port for full n8n access via Tailscale Funnel. Must be 443, 8443, or 10000 (Funnel limitation).";
      };
    };

    owner = {
      email = lib.mkOption {
        type = lib.types.str;
        default = "eric@iheartwoodcraft.com";
        description = "Owner account email address";
      };

      firstName = lib.mkOption {
        type = lib.types.str;
        default = "Eric";
        description = "Owner account first name";
      };

      lastName = lib.mkOption {
        type = lib.types.str;
        default = "Okeefe";
        description = "Owner account last name";
      };

      passwordHashFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to file containing bcrypt password hash for owner account (via agenix)";
      };
    };
  };

  #==========================================================================
  # IMPORTS
  #==========================================================================
  imports = [
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

    # Tailscale Funnel service - expose n8n publicly on port 10000
    # Full access enabled for external automation tools (Manus AI, etc.)
    systemd.services.tailscale-funnel-n8n = {
      description = "Tailscale Funnel for n8n (public access on port 10000)";
      after = [ "network.target" "tailscaled.service" "podman-n8n.service" ];
      wants = [ "tailscaled.service" "podman-n8n.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 5";
        ExecStart = "${pkgs.tailscale}/bin/tailscale funnel --bg --https=10000 http://127.0.0.1:${toString cfg.port}";
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
