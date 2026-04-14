# domains/business/mcp/index.nix
#
# JT MCP Server — unified interface to all business systems
# (JobTread, Paperless-ngx, Firefly III, n8n workflows)
#
# NAMESPACE: hwc.business.mcp.*
#
# DEPENDENCIES:
#   - hwc.paths (storage paths)
#   - agenix secrets: jobtread-grant-key
#
# REPLACES: datax JT MCP connector ($50/month)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.business.mcp;
  paths = config.hwc.paths;
  inherit (lib) mkIf mkMerge;

  # Health check script — verifies the SSE port is reachable, restarts + notifies if not
  healthCheckScript = pkgs.writeShellScript "jt-mcp-health" ''
    PORT=${toString cfg.sse.port}
    export PATH="/run/current-system/sw/bin:$PATH"

    # Check if the service is supposed to be running
    if ! ${pkgs.systemd}/bin/systemctl is-active --quiet jt-mcp; then
      exit 0  # Service intentionally stopped, nothing to do
    fi

    # Try connecting to the SSE port (expect 404 on /, which means the server is up)
    HTTP_CODE=$(${pkgs.curl}/bin/curl -s -o /dev/null -w '%{http_code}' -m 5 "http://127.0.0.1:$PORT/" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" != "000" ]; then
      exit 0  # Got an HTTP response — server is alive
    fi

    # Port not responding — service is hung
    LOGS=$(${pkgs.systemd}/bin/journalctl -u jt-mcp -n 10 --no-pager 2>&1 || echo "no logs")

    # Send Gotify notification before restart
    hwc-gotify-send --priority 9 \
      "JT MCP Hung" \
      "Port $PORT not responding (HTTP $HTTP_CODE). Restarting. Recent logs: $LOGS" || true

    # Restart the service
    ${pkgs.systemd}/bin/systemctl restart jt-mcp
  '';

  # Build the environment file content from secrets
  envFileScript = pkgs.writeShellScript "jt-mcp-env" ''
    cat > /run/jt-mcp/env <<ENVEOF
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
    sed -i 's/^[[:space:]]*//' /run/jt-mcp/env
    chmod 0400 /run/jt-mcp/env
    chown ${cfg.user}:users /run/jt-mcp/env
  '';

in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.business.mcp = {
    enable = lib.mkEnableOption "JT MCP Server — unified business system interface";

    # ── Server source ────────────────────────────────────────────────────
    srcDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.business.root or "/opt/business"}/jt-mcp";
      description = "Path to the built JT MCP server (contains dist/)";
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
      "d /run/jt-mcp 0750 ${cfg.user} users -"
    ];

    #--------------------------------------------------------------------------
    # ENVIRONMENT SETUP SERVICE (generates env file from secrets)
    #--------------------------------------------------------------------------
    systemd.services.jt-mcp-env = {
      description = "Generate JT MCP environment from secrets";
      after = [ "network.target" ];
      before = [ "jt-mcp.service" ];
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
    systemd.services.jt-mcp = {
      description = "JT MCP Server — unified business system interface";
      after = [ "network.target" "jt-mcp-env.service" ];
      requires = [ "jt-mcp-env.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = mkMerge [
        {
          Type = "simple";
          ExecStart = "${pkgs.nodejs_22}/bin/node ${cfg.srcDir}/dist/index.js";
          EnvironmentFile = "/run/jt-mcp/env";
          WorkingDirectory = cfg.srcDir;
          Restart = "on-failure";
          RestartSec = "5s";
          User = lib.mkForce cfg.user;

          # Security hardening
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = false; # Needs access to srcDir
          ReadWritePaths = [ "/run/jt-mcp" ];
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
    # HEALTH CHECK (catches hung process that OnFailure can't detect)
    #--------------------------------------------------------------------------
    systemd.services.jt-mcp-health = {
      description = "JT MCP health check — detect hung process";
      after = [ "jt-mcp.service" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${healthCheckScript}";
        User = "root";  # Needs systemctl restart permission
      };
    };

    systemd.timers.jt-mcp-health = {
      description = "JT MCP health check timer";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnCalendar = "*:0/5";  # Every 5 minutes
        Persistent = false;
        RandomizedDelaySec = "30s";
      };
    };

    #--------------------------------------------------------------------------
    # VALIDATION
    #--------------------------------------------------------------------------
    assertions = [
      {
        assertion = config.age.secrets ? jobtread-grant-key;
        message = ''
          hwc.business.mcp requires the jobtread-grant-key agenix secret.
          Ensure it is declared in domains/secrets/declarations/services.nix.
        '';
      }
    ];
  };
}
