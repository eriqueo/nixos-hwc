# domains/server/n8n/index.nix
#
# N8N - Workflow automation platform for alert routing and notifications
#
# NAMESPACE: hwc.server.native.n8n.*
#
# DEPENDENCIES:
#   - hwc.paths.state (data directory)
#   - Optional: hwc.server.monitoring.alertmanager (webhook consumer)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.server.native.n8n;
  paths = config.hwc.paths;

  # Build environment variables for n8n
  n8nEnv = {
    N8N_PORT = toString cfg.port;
    N8N_PROTOCOL = "https";
    N8N_HOST = "hwc.ocelot-wahoo.ts.net";
    WEBHOOK_URL = "https://hwc.ocelot-wahoo.ts.net/";  # Force webhook URLs to use standard HTTPS port
    N8N_USER_MANAGEMENT_DISABLED = "true";
    N8N_USER_FOLDER = cfg.dataDir;
    GENERIC_TIMEZONE = cfg.timezone;
    N8N_PERSONALIZATION_ENABLED = "false";
    N8N_VERSION_NOTIFICATIONS_ENABLED = "false";
    N8N_DIAGNOSTICS_ENABLED = "false";
    N8N_HIRING_BANNER_ENABLED = "false";
    
           
    SLACK_SIGNING_SECRET= "2e56128bbb2e1f6973e891e623f4ed0b";
  } // (lib.optionalAttrs (cfg.database.type == "sqlite") {
    DB_TYPE = "sqlite";
    DB_SQLITE_DATABASE = cfg.database.sqlite.file;
  }) // (lib.optionalAttrs (cfg.encryption.keyFile != null) {
    N8N_ENCRYPTION_KEY = "$(<${cfg.encryption.keyFile})";
  }) // (lib.optionalAttrs (config.hwc.secrets.api.slackWebhookUrlFile != null) {
    SLACK_WEBHOOK_URL = "$(<${config.hwc.secrets.api.slackWebhookUrlFile})";
  }) // (lib.optionalAttrs (config.hwc.secrets.api.jellyfinApiKeyFile != null) {
     JELLYFIN_API_KEY = "$(<${config.hwc.secrets.api.jellyfinApiKeyFile})";
  }) // cfg.extraEnv;




in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # n8n systemd service
    systemd.services.n8n = {
      description = "n8n workflow automation platform";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
       # add this:
      path = with pkgs; [
        bash
        coreutils
        findutils
        gnugrep
        gnused
        systemd
        git
        curl
        jq
        python3
        podman
        nix
        # add any other tools you want available in Execute Command
      ];
      environment = n8nEnv // {
        # Add workspace scripts to PATH for Execute Command node
        PATH = lib.mkForce "/home/eric/.nixos/workspace/scripts:/etc/profiles/per-user/eric/bin:/run/current-system/sw/bin";
      };
      serviceConfig = {
              Type = "simple";
              User = lib.mkForce "eric";
              Group = lib.mkForce "users";
              ExecStart = "${pkgs.n8n}/bin/n8n start";
              Restart = "on-failure";
              RestartSec = "10s";
      # Relax hardening so n8n behaves like a normal user session
      NoNewPrivileges = lib.mkForce false;
      PrivateTmp = lib.mkForce false;
      ProtectHome = lib.mkForce false;
      
              # Either drop this, or broaden it.
              # If you omit ReadWritePaths, eric's normal permissions apply everywhere.
      ReadWritePaths = lib.mkForce [ ];

        # Resource limits
        MemoryMax = "2G";
        CPUQuota = "200%";
      };

      preStart = ''
        # Create database directory if using SQLite
        ${lib.optionalString (cfg.database.type == "sqlite") ''
          mkdir -p $(dirname ${cfg.database.sqlite.file})
        ''}
      '';
    };

    # Ensure data directory exists with correct ownership
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 eric users -"
      "d ${cfg.dataDir}/.n8n 0755 eric users -"
    ];

    # Firewall - localhost + Tailscale
    networking.firewall.interfaces."lo".allowedTCPPorts = [ cfg.port ];
    networking.firewall.interfaces."tailscale0".allowedTCPPorts =
      lib.optional (config.networking.interfaces ? "tailscale0") cfg.port;

    # Add eric user to secrets group for encryption key access
    users.users.eric = lib.mkIf (cfg.encryption.keyFile != null) {
      extraGroups = [ "secrets" ];
    };

    # Tailscale Funnel service - expose /webhook publicly on port 10000
    systemd.services.tailscale-funnel-n8n = {
      description = "Tailscale Funnel for n8n webhook (public Slack integration)";
      after = [ "network.target" "tailscaled.service" "n8n.service" ];
      wants = [ "tailscaled.service" "n8n.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 5";  # Wait for tailscaled
        ExecStart = "${pkgs.tailscale}/bin/tailscale funnel --bg --https=10000 --set-path=/webhook http://127.0.0.1:${toString cfg.port}";
        ExecStop = "${pkgs.tailscale}/bin/tailscale funnel --https=10000 off";
      };
    };

    #========================================================================
    # VALIDATION
    #========================================================================
    assertions = [
      {
        assertion = !cfg.enable || (cfg.port != 0);
        message = "n8n port must be configured (hwc.server.n8n.port)";
      }
      {
        assertion = !cfg.enable || (cfg.dataDir != "");
        message = "n8n data directory must be configured (hwc.server.n8n.dataDir)";
      }
      {
        assertion = !cfg.enable || (cfg.webhookUrl != "");
        message = "n8n webhook URL must be configured (hwc.server.n8n.webhookUrl)";
      }
      {
        assertion = !cfg.enable || (cfg.database.type == "sqlite" -> cfg.database.sqlite.file != "");
        message = "n8n SQLite database file must be configured when using SQLite";
      }
    ];
  };
}
