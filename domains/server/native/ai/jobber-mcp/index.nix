# domains/server/native/ai/jobber-mcp/index.nix
#
# Jobber MCP Server — native systemd service
# Exposes Jobber GraphQL API (clients, jobs, invoices, quotes, requests, timesheets)
# as MCP tools via SSE transport on port 8002, proxied via Caddy on port 20443.
{ config, lib, ... }:
let
  cfg = config.hwc.server.ai.jobberMcp;
  paths = config.hwc.paths;
  python = "${cfg.projectDir}/.venv/bin/python3";
  server = "${cfg.projectDir}/server.py";
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.server.ai.jobberMcp = {
    enable = lib.mkEnableOption "Jobber MCP Server";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8002;
      description = "Internal port the Jobber MCP server listens on";
    };

    reverseProxyPort = lib.mkOption {
      type = lib.types.port;
      default = 20443;
      description = "External Tailscale HTTPS port for Caddy reverse proxy";
    };

    projectDir = lib.mkOption {
      type = lib.types.path;
      default = "/home/eric/300_tech/320_projects/jobber-mcp";
      description = "Path to the jobber-mcp Python project";
    };

    envFile = lib.mkOption {
      type = lib.types.path;
      default = "/home/eric/300_tech/320_projects/jobber-mcp/.env";
      description = "Path to .env file containing JOBBER_ACCESS_TOKEN and OAuth credentials";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "eric";
      description = "User to run the service as";
    };
  };

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

  };
}
