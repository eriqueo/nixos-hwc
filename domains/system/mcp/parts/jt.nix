# domains/system/mcp/parts/jt.nix
#
# HWC JobTread MCP Server — Heartwood business tools (63 JT PAVE tools)
# Runs heartwood-mcp with streamable-http transport for Claude.ai access.
#
# NAMESPACE: hwc.system.mcp.jt.*
#
# DEPENDENCIES:
#   - agenix secrets: jobtread-grant-key
#   - Node.js 22 (runtime)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.mcp.jt;
  paths = config.hwc.paths;
  inherit (lib) mkIf mkMerge;

  # Health check script — verifies the Streamable HTTP port is reachable
  healthCheckScript = pkgs.writeShellScript "hwc-jt-mcp-health" ''
    PORT=${toString cfg.port}
    export PATH="/run/current-system/sw/bin:$PATH"

    # Check if the service is supposed to be running
    if ! ${pkgs.systemd}/bin/systemctl is-active --quiet hwc-jt-mcp; then
      exit 0  # Service intentionally stopped
    fi

    # Try the health endpoint
    HTTP_CODE=$(${pkgs.curl}/bin/curl -s -o /dev/null -w '%{http_code}' -m 5 "http://127.0.0.1:$PORT/health" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
      exit 0  # Healthy
    fi

    # Port not responding — service is hung
    LOGS=$(${pkgs.systemd}/bin/journalctl -u hwc-jt-mcp -n 10 --no-pager 2>&1 || echo "no logs")

    # Send Gotify notification before restart
    hwc-gotify-send --priority 9 \
      "HWC JT MCP Hung" \
      "Port $PORT not responding (HTTP $HTTP_CODE). Restarting. Recent logs: $LOGS" || true

    # Restart the service
    ${pkgs.systemd}/bin/systemctl restart hwc-jt-mcp
  '';

  # Build the environment file content from secrets
  envFileScript = pkgs.writeShellScript "hwc-jt-mcp-env" ''
    cat > /run/hwc-jt-mcp/env <<ENVEOF
    JT_GRANT_KEY=$(cat ${config.age.secrets.jobtread-grant-key.path})
    JT_ORG_ID=${cfg.jt.orgId}
    JT_USER_ID=${cfg.jt.userId}
    JT_API_URL=${cfg.jt.apiUrl}
    TRANSPORT=streamable-http
    SSE_HOST=${cfg.host}
    SSE_PORT=${toString cfg.port}
    LOG_LEVEL=${cfg.logLevel}
    ENVEOF
    # Strip leading whitespace from env file (heredoc indentation artifact)
    sed -i 's/^[[:space:]]*//' /run/hwc-jt-mcp/env
    chmod 0400 /run/hwc-jt-mcp/env
    chown eric:users /run/hwc-jt-mcp/env
  '';

in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.system.mcp.jt = {
    enable = lib.mkEnableOption "HWC JobTread MCP server — Heartwood business tools via Streamable HTTP";

    port = lib.mkOption {
      type = lib.types.port;
      default = 6102;
      description = "Streamable HTTP listen port";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Bind address";
    };

    logLevel = lib.mkOption {
      type = lib.types.enum [ "debug" "info" "warn" "error" ];
      default = "info";
      description = "Server log level";
    };

    srcDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.business.root or "/opt/business"}/heartwood-mcp";
      description = "Path to the built Heartwood MCP server (contains dist/)";
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
      "d /run/hwc-jt-mcp 0750 eric users -"
    ];

    #--------------------------------------------------------------------------
    # ENVIRONMENT SETUP SERVICE (generates env file from secrets)
    #--------------------------------------------------------------------------
    systemd.services.hwc-jt-mcp-env = {
      description = "Generate HWC JT MCP environment from secrets";
      after = [ "network.target" ];
      before = [ "hwc-jt-mcp.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${envFileScript}";
        User = "root"; # Needs root to read agenix secrets
      };
    };

    #--------------------------------------------------------------------------
    # HWC JT MCP SERVICE
    #--------------------------------------------------------------------------
    systemd.services.hwc-jt-mcp = {
      description = "HWC JobTread MCP Server — Heartwood business tools";
      after = [ "network.target" "hwc-jt-mcp-env.service" ];
      requires = [ "hwc-jt-mcp-env.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = mkMerge [
        {
          Type = "simple";
          ExecStart = "${pkgs.nodejs_22}/bin/node ${cfg.srcDir}/dist/index.js";
          EnvironmentFile = "/run/hwc-jt-mcp/env";
          WorkingDirectory = cfg.srcDir;
          Restart = "on-failure";
          RestartSec = "5s";
          User = lib.mkForce "eric";

          # Security hardening
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = false; # Needs access to srcDir
          ReadWritePaths = [ "/run/hwc-jt-mcp" ];
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
    # HEALTH CHECK (catches hung process)
    #--------------------------------------------------------------------------
    systemd.services.hwc-jt-mcp-health = {
      description = "HWC JT MCP health check — detect hung process";
      after = [ "hwc-jt-mcp.service" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${healthCheckScript}";
        User = "root";
      };
    };

    systemd.timers.hwc-jt-mcp-health = {
      description = "HWC JT MCP health check timer";
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
          hwc.system.mcp.jt requires the jobtread-grant-key agenix secret.
          Ensure it is declared in domains/secrets/declarations/services.nix.
        '';
      }
    ];
  };
}
