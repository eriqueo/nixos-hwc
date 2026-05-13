# domains/server/native/ai/jobber-mcp/index.nix
#
# Jobber MCP Server — native systemd service
# Exposes Jobber GraphQL API (clients, jobs, invoices, quotes, requests, timesheets)
# as MCP tools via SSE transport on port 8002, proxied via Caddy on port 17443.
{ config, lib, ... }:
let
  cfg = config.hwc.server.ai.jobberMcp;
  python = "${cfg.projectDir}/.venv/bin/python3";
  server = "${cfg.projectDir}/server.py";
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {

    #==========================================================================
    # SYSTEMD SERVICE
    #==========================================================================
    systemd.services.jobber-mcp = {
      description = "Jobber MCP Server (SSE)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${python} ${server}";
        WorkingDirectory = cfg.projectDir;
        EnvironmentFile = cfg.envFile;
        User = lib.mkForce cfg.user;
        Restart = "on-failure";
        RestartSec = "5s";

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "true";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        SystemCallArchitectures = "native";
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;

        # Allow read/write to project dir (tokens.db lives there)
        ReadWritePaths = [ cfg.projectDir ];
      };
    };

    #==========================================================================
    # CADDY REVERSE PROXY ROUTE
    # SSE needs flush_interval -1 — routes-lib adds it when ws=true (default)
    #==========================================================================
    hwc.networking.shared.routes = [{
      name = "jobber-mcp";
      mode = "port";
      port = cfg.reverseProxyPort;
      upstream = "http://127.0.0.1:${toString cfg.port}";
    }];

    #==========================================================================
    # FIREWALL
    #==========================================================================
    networking.firewall.allowedTCPPorts = [ cfg.reverseProxyPort ];

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = builtins.pathExists cfg.envFile;
        message = "jobber-mcp: envFile ${cfg.envFile} does not exist. Create it with JOBBER_ACCESS_TOKEN set.";
      }
    ];
  };
}
