# domains/automation/n8n/mcp-bridge.nix
#
# n8n-mcp HTTP bridge — exposes n8n workflows as MCP tools via HTTP.
# Uses the n8n-mcp npm package in HTTP mode, patched for JSON responses.
# Proxied via hwc-infra-mcp Express server: /n8n/* → :6201.
# Public access: Tailscale Funnel :443 → Express :6200 → /n8n/* → :6201.
#
# NAMESPACE: hwc.automation.n8n.mcpBridge.*

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.automation.n8n;
  bridge = cfg.mcpBridge;

  # Stable install location for n8n-mcp
  installDir = "/opt/n8n-mcp";
  n8nMcpVersion = "2.40.5";
  entryPoint = "${installDir}/node_modules/n8n-mcp/dist/mcp/index.js";

  # Install + patch script: ensures n8n-mcp is installed and patched for JSON responses.
  # Runs as ExecStartPre — idempotent (skips if already at correct version and patched).
  installAndPatchScript = pkgs.writeShellScript "n8n-mcp-install-patch" ''
    set -euo pipefail

    # Ensure install directory exists
    ${pkgs.coreutils}/bin/mkdir -p "${installDir}"

    # Install n8n-mcp if missing or wrong version
    INSTALLED=""
    if [ -f "${installDir}/node_modules/n8n-mcp/package.json" ]; then
      INSTALLED=$(${pkgs.nodejs_22}/bin/node -e "console.log(require('${installDir}/node_modules/n8n-mcp/package.json').version)" 2>/dev/null || echo "")
    fi

    if [ "$INSTALLED" != "${n8nMcpVersion}" ]; then
      echo "Installing n8n-mcp@${n8nMcpVersion} (current: $INSTALLED)"
      cd "${installDir}"
      ${pkgs.nodejs_22}/bin/npm install --no-save "n8n-mcp@${n8nMcpVersion}" 2>&1
    else
      echo "n8n-mcp@${n8nMcpVersion} already installed"
    fi

    # Patch: add enableJsonResponse: true to StreamableHTTPServerTransport
    # Required for Claude.ai compatibility (needs application/json, not text/event-stream)
    TARGET="${installDir}/node_modules/n8n-mcp/dist/http-server-single-session.js"
    if [ ! -f "$TARGET" ]; then
      echo "FATAL: $TARGET not found after install"
      exit 1
    fi
    if ! ${pkgs.gnugrep}/bin/grep -q 'enableJsonResponse: true' "$TARGET"; then
      ${pkgs.gnused}/bin/sed -i 's/transport = new streamableHttp_js_1\.StreamableHTTPServerTransport({/transport = new streamableHttp_js_1.StreamableHTTPServerTransport({\n                        enableJsonResponse: true,/' "$TARGET"
      echo "Patched enableJsonResponse into $TARGET"
    else
      echo "enableJsonResponse already patched"
    fi

    # Patch: disable SSE fallback in GET /mcp handler.
    # Problem: when Claude.ai sends GET /mcp with a stale session ID, the bridge
    # can't find the session and falls through to creating a legacy SSE session.
    # Claude.ai gets 200 instead of 404, so it never re-initializes.
    # Fix: if a session ID was provided but not found, return 404 immediately.
    MARKER="PATCHED_NO_SSE_FALLBACK"
    if ! ${pkgs.gnugrep}/bin/grep -q "$MARKER" "$TARGET"; then
      ${pkgs.gnused}/bin/sed -i '/app\.get.*\/mcp.*async.*req.*res/,/^[[:space:]]*});/{
        /const accept = req\.headers\.accept;/,/return;/{
          /const accept = req\.headers\.accept;/c\
            \/\/ '"$MARKER"': Return 404 for unknown sessions instead of SSE fallback\
            if (sessionId) {\
                logger_1.logger.warn("GET /mcp: unknown session, returning 404 (no SSE fallback)", { sessionId });\
                res.status(404).json({ jsonrpc: "2.0", error: { code: -32001, message: "Session not found" }, id: null });\
                return;\
            }\
            const accept = req.headers.accept;
        }
      }' "$TARGET"
      echo "Patched SSE fallback disabled in GET /mcp"
    else
      echo "SSE fallback already patched"
    fi

    # Patch: remove rate limiter from POST /mcp.
    # All traffic comes from our Express proxy on 127.0.0.1, so the per-IP
    # rate limiter blocks legitimate Claude.ai sessions.
    MARKER2="PATCHED_NO_RATE_LIMIT"
    if ! ${pkgs.gnugrep}/bin/grep -q "$MARKER2" "$TARGET"; then
      ${pkgs.gnused}/bin/sed -i "s|app.post('/mcp', authLimiter, jsonParser,|\/\/ $MARKER2: rate limiter removed (all traffic from local proxy)\n        app.post('/mcp', jsonParser,|" "$TARGET"
      echo "Patched rate limiter removed from POST /mcp"
    else
      echo "Rate limiter already patched"
    fi
  '';

  # Script to generate env file with API key from agenix
  generateEnv = pkgs.writeShellScript "n8n-mcp-bridge-gen-env" ''
    mkdir -p /run/n8n-mcp
    ENV_FILE=/run/n8n-mcp/bridge.env
    rm -f "$ENV_FILE"
    touch "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    echo "N8N_API_KEY=$(cat /run/agenix/n8n-api-key)" >> "$ENV_FILE"
    ${lib.optionalString (bridge.authTokenFile != null) ''
      echo "AUTH_TOKEN=$(cat ${bridge.authTokenFile})" >> "$ENV_FILE"
    ''}
    chown eric:users "$ENV_FILE"
  '';
in
{
  options.hwc.automation.n8n.mcpBridge = {
    enable = lib.mkEnableOption "n8n MCP HTTP bridge for Claude.ai access";

    port = lib.mkOption {
      type = lib.types.port;
      default = 6201;
      description = "HTTP port for the n8n-mcp bridge server";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Bind address for the n8n-mcp bridge server";
    };

    authTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to file containing AUTH_TOKEN for the HTTP API (via agenix). If null, a static internal token is used.";
    };
  };

  config = lib.mkIf (cfg.enable && bridge.enable) {
    # Env file generator — runs before the bridge service
    systemd.services.hwc-n8n-mcp-env = {
      description = "Generate n8n MCP bridge environment file";
      before = [ "hwc-n8n-mcp.service" ];
      requiredBy = [ "hwc-n8n-mcp.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = generateEnv;
      };
    };

    # Main bridge service
    systemd.services.hwc-n8n-mcp = {
      description = "HWC n8n MCP HTTP Bridge (Claude.ai access)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "podman-n8n.service" "hwc-n8n-mcp-env.service" ];
      wants = [ "network-online.target" "podman-n8n.service" ];
      requires = [ "hwc-n8n-mcp-env.service" ];

      environment = {
        MCP_MODE = "http";
        PORT = toString bridge.port;
        HOST = bridge.host;
        NODE_ENV = "production";
        LOG_LEVEL = "info";
        TRUST_PROXY = "1";
        N8N_API_URL = "http://localhost:${toString cfg.port}";
        N8N_API_TIMEOUT = "60000";  # 60s — default 30s too short for get_workflow full
        # Rate limiter: all traffic is from local Express proxy (127.0.0.1), so
        # the default 20 req/15min blocks legitimate Claude.ai sessions quickly.
        AUTH_RATE_LIMIT_MAX = "1000";
        AUTH_RATE_LIMIT_WINDOW = "60000";  # 1000 req/min — effectively disabled
        # Internal-only auth token (hwc-infra Express proxy injects this via Authorization header)
        AUTH_TOKEN = "hwc-n8n-mcp-internal-bridge-token-do-not-expose-externally";
      };

      serviceConfig = {
        Type = "simple";
        ExecStartPre = "+${installAndPatchScript}";  # + = run as root (npm install needs write to /opt)
        ExecStart = "${pkgs.nodejs_22}/bin/node ${entryPoint}";
        WorkingDirectory = installDir;
        Restart = "on-failure";
        RestartSec = "5s";
        User = lib.mkForce "eric";
        EnvironmentFile = [ "/run/n8n-mcp/bridge.env" ];

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths = [ installDir "/tmp" ];
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictRealtime = true;
        LockPersonality = true;

        # Resource limits
        MemoryMax = "512M";
        CPUQuota = "50%";
      };

      path = [ pkgs.nodejs_22 ];
    };

    # Firewall — localhost only
    networking.firewall.interfaces."lo".allowedTCPPorts = [ bridge.port ];

    assertions = [
      {
        assertion = bridge.port != cfg.port;
        message = "n8n MCP bridge port (${toString bridge.port}) must differ from n8n port (${toString cfg.port})";
      }
    ];
  };
}
