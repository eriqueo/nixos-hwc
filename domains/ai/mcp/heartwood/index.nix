# domains/ai/mcp/heartwood/index.nix
#
# Heartwood MCP Server — unified interface to all business systems
# (JobTread, Paperless-ngx, Firefly III, n8n workflows)
#
# NAMESPACE: hwc.ai.mcp.heartwood.*
#
# DEPENDENCIES:
#   - hwc.ai.mcp (parent MCP infrastructure, mkMcpService template)
#   - hwc.paths (storage paths)
#   - agenix secrets: jobtread-grant-key
#
# REPLACES: datax JT MCP connector ($50/month)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.ai.mcp.heartwood;
  mcpCfg = config.hwc.ai.mcp;
  paths = config.hwc.paths;
  inherit (lib) mkIf mkMerge;

  # Build the environment file content from secrets
  envFileScript = pkgs.writeShellScript "heartwood-mcp-env" ''
    cat > /run/heartwood-mcp/env <<ENVEOF
    JT_GRANT_KEY=$(cat ${config.age.secrets.jobtread-grant-key.path})
    JT_ORG_ID=${cfg.jt.orgId}
    JT_USER_ID=${cfg.jt.userId}
    JT_API_URL=${cfg.jt.apiUrl}
    TRANSPORT=${cfg.transport}
    SSE_HOST=${cfg.sse.host}
    SSE_PORT=${toString cfg.sse.port}
    LOG_LEVEL=${cfg.logLevel}
    ENVEOF
    # Strip leading whitespace from env file (heredoc indentation artifact)
    sed -i 's/^[[:space:]]*//' /run/heartwood-mcp/env
    chmod 0400 /run/heartwood-mcp/env
    chown ${cfg.user}:users /run/heartwood-mcp/env
  '';

in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.ai.mcp.heartwood = {
    enable = lib.mkEnableOption "Heartwood MCP Server — unified business system interface";

    # ── Server source ────────────────────────────────────────────────────
    srcDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.business.root or "/opt/business"}/heartwood-mcp";
      description = "Path to the built Heartwood MCP server (contains dist/)";
    };

    # ── Identity ─────────────────────────────────────────────────────────
    user = lib.mkOption {
      type = lib.types.str;
      default = "eric";
      description = "User to run the service as";
    };

    # ── Transport ────────────────────────────────────────────────────────
    transport = lib.mkOption {
      type = lib.types.enum [ "stdio" "sse" ];
      default = "sse";
      description = ''
        Transport mode:
        - stdio: For local Claude Code (via Tailscale SSH)
        - sse: For remote access (Claude chat, n8n webhooks)
      '';
    };

    sse = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "SSE transport bind host (localhost for Caddy proxy)";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 6100;
        description = "SSE transport port";
      };
    };

    # ── Logging ──────────────────────────────────────────────────────────
    logLevel = lib.mkOption {
      type = lib.types.enum [ "debug" "info" "warn" "error" ];
      default = "info";
      description = "Log verbosity level";
    };

    # ── JobTread configuration ───────────────────────────────────────────
    jt = {
      orgId = lib.mkOption {
        type = lib.types.str;
        default = "22Nm3uFevXMb";
        description = "JobTread organization ID";
      };

      userId = lib.mkOption {
        type = lib.types.str;
        default = "22Nm3uFeRB7s";
        description = "JobTread user ID";
      };

      apiUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://api.jobtread.com/pave";
        description = "JobTread PAVE API endpoint";
      };
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = mkIf cfg.enable {

    #--------------------------------------------------------------------------
    # TMPFILES (Runtime directories)
    #--------------------------------------------------------------------------
    systemd.tmpfiles.rules = [
      "d /run/heartwood-mcp 0750 ${cfg.user} users -"
    ];

    #--------------------------------------------------------------------------
    # ENVIRONMENT SETUP SERVICE (generates env file from secrets)
    #--------------------------------------------------------------------------
    systemd.services.heartwood-mcp-env = {
      description = "Generate Heartwood MCP environment from secrets";
      after = [ "network.target" ];
      before = [ "heartwood-mcp.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${envFileScript}";
        User = "root"; # Needs root to read agenix secrets
      };
    };

    #--------------------------------------------------------------------------
    # HEARTWOOD MCP SERVICE
    #--------------------------------------------------------------------------
    systemd.services.heartwood-mcp = {
      description = "Heartwood MCP Server — unified business system interface";
      after = [ "network.target" "heartwood-mcp-env.service" ];
      requires = [ "heartwood-mcp-env.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = mkMerge [
        {
          Type = "simple";
          ExecStart = "${pkgs.nodejs_22}/bin/node ${cfg.srcDir}/dist/index.js";
          EnvironmentFile = "/run/heartwood-mcp/env";
          WorkingDirectory = cfg.srcDir;
          Restart = "on-failure";
          RestartSec = "5s";
          User = lib.mkForce cfg.user;

          # Security hardening
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = false; # Needs access to srcDir
          ReadWritePaths = [ "/run/heartwood-mcp" ];
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          SystemCallArchitectures = "native";
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;

          # Resource limits
          MemoryMax = "512M";
          CPUQuota = "50%";
        }
      ];
    };

    #--------------------------------------------------------------------------
    # VALIDATION
    #--------------------------------------------------------------------------
    assertions = [
      {
        assertion = config.age.secrets ? jobtread-grant-key;
        message = ''
          hwc.ai.mcp.heartwood requires the jobtread-grant-key agenix secret.
          Ensure it is declared in domains/secrets/declarations/services.nix.
        '';
      }
    ];
  };
}
