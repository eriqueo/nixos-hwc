# domains/system/mcp/index.nix
#
# HWC Infrastructure MCP Gateway — unified entry point for all MCP tools.
# Aggregates hwc-sys (local), heartwood-mcp (stdio), and n8n-mcp (stdio)
# into a single Streamable HTTP transport for Claude.ai and stdio for Claude Code.
#
# NAMESPACE: hwc.system.mcp.*
#
# DEPENDENCIES:
#   - hwc.paths (storage paths, repo location)
#   - Node.js 22 (runtime)
#   - agenix secrets: jobtread-grant-key, n8n-api-key

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.mcp;
  paths = config.hwc.paths;
  inherit (lib) mkIf mkMerge;

  srcDir = "${paths.nixos}/domains/system/mcp/src";

  # JT config (options from parts/jt.nix)
  jtCfg = config.hwc.system.mcp.jt;

  # n8n config
  n8nCfg = lib.attrByPath ["hwc" "automation" "n8n"] {} config;
  n8nPort = n8nCfg.port or 5678;
  n8nMcpVersion = "2.40.5";
  n8nMcpInstallDir = "/opt/n8n-mcp";

  # n8n-mcp npm install script — ensures the stdio backend package is available
  installN8nMcp = pkgs.writeShellScript "hwc-sys-mcp-install-n8n" ''
    set -euo pipefail
    ${pkgs.coreutils}/bin/mkdir -p "${n8nMcpInstallDir}"

    INSTALLED=""
    if [ -f "${n8nMcpInstallDir}/node_modules/n8n-mcp/package.json" ]; then
      INSTALLED=$(${pkgs.nodejs_22}/bin/node -e "console.log(require('${n8nMcpInstallDir}/node_modules/n8n-mcp/package.json').version)" 2>/dev/null || echo "")
    fi

    if [ "$INSTALLED" != "${n8nMcpVersion}" ]; then
      echo "Installing n8n-mcp@${n8nMcpVersion} (current: $INSTALLED)"
      cd "${n8nMcpInstallDir}"
      ${pkgs.nodejs_22}/bin/npm install --no-save "n8n-mcp@${n8nMcpVersion}" 2>&1
    else
      echo "n8n-mcp@${n8nMcpVersion} already installed"
    fi
  '';

  # Environment file generator — injects agenix secrets at runtime
  generateEnv = pkgs.writeShellScript "hwc-sys-mcp-gen-env" ''
    mkdir -p /run/hwc-sys-mcp
    ENV_FILE=/run/hwc-sys-mcp/env
    rm -f "$ENV_FILE"
    touch "$ENV_FILE"
    chmod 600 "$ENV_FILE"

    # JT secret
    if [ -f "${config.age.secrets.jobtread-grant-key.path}" ]; then
      echo "JT_GRANT_KEY=$(cat ${config.age.secrets.jobtread-grant-key.path})" >> "$ENV_FILE"
    fi

    # n8n API key
    if [ -f "/run/agenix/n8n-api-key" ]; then
      echo "N8N_API_KEY=$(cat /run/agenix/n8n-api-key)" >> "$ENV_FILE"
    fi

    chown eric:users "$ENV_FILE"
  '';
in
{
  imports = [
    ./parts/caddy.nix
    ./parts/jt.nix
  ];

  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.system.mcp = {
    enable = lib.mkEnableOption "HWC Infrastructure MCP Gateway — unified system, JT, and n8n tools";

    port = lib.mkOption {
      type = lib.types.port;
      default = 6200;
      description = "Streamable HTTP listen port";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Bind address";
    };

    transport = lib.mkOption {
      type = lib.types.enum [ "stdio" "sse" "both" ];
      default = "both";
      description = "MCP transport mode. 'both' runs Streamable HTTP on the configured port and also supports stdio.";
    };

    logLevel = lib.mkOption {
      type = lib.types.enum [ "debug" "info" "warn" "error" ];
      default = "info";
      description = "Server log level";
    };

    cacheTtl = lib.mkOption {
      type = lib.types.submodule {
        options = {
          runtime = lib.mkOption {
            type = lib.types.int;
            default = 60;
            description = "TTL in seconds for runtime queries (systemctl, podman)";
          };
          declarative = lib.mkOption {
            type = lib.types.int;
            default = 300;
            description = "TTL in seconds for Nix evaluation results";
          };
        };
      };
      default = {};
    };

    mutations = lib.mkOption {
      type = lib.types.submodule {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable mutation tools (restart, trigger backup, dry-build). Disabled by default for safety.";
          };
          allowedActions = lib.mkOption {
            type = lib.types.listOf (lib.types.enum [
              "restart-service"
              "restart-container"
              "trigger-backup"
              "dry-build"
              "flake-update"
              "run-health-check"
            ]);
            default = [ "restart-service" "restart-container" "run-health-check" ];
            description = "Whitelist of allowed mutation actions";
          };
        };
      };
      default = {};
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = mkIf cfg.enable {

    #--------------------------------------------------------------------------
    # TMPFILES (runtime directory for env file)
    #--------------------------------------------------------------------------
    systemd.tmpfiles.rules = [
      "d /run/hwc-sys-mcp 0750 eric users -"
      "d ${paths.nixos}/domains/business/website/site_files/.trash 0750 eric users -"
    ];

    #--------------------------------------------------------------------------
    # ENVIRONMENT SETUP SERVICE (generates env file from agenix secrets)
    #--------------------------------------------------------------------------
    systemd.services.hwc-sys-mcp-env = {
      description = "Generate HWC MCP Gateway environment from secrets";
      after = [ "network.target" ];
      before = [ "hwc-sys-mcp.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${generateEnv}";
        User = "root";
      };
    };

    #--------------------------------------------------------------------------
    # GATEWAY SERVICE
    #--------------------------------------------------------------------------
    systemd.services.hwc-sys-mcp = {
      description = "HWC MCP Gateway — unified system, JT, and n8n tools";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "tailscaled.service" "hwc-sys-mcp-env.service" "podman-n8n.service" ];
      wants = [ "network-online.target" "podman-n8n.service" ];
      requires = [ "hwc-sys-mcp-env.service" ];

      environment = {
        NODE_ENV = "production";
        HWC_MCP_PORT = toString cfg.port;
        HWC_MCP_HOST = cfg.host;
        HWC_MCP_TRANSPORT = cfg.transport;
        HWC_MCP_LOG_LEVEL = cfg.logLevel;
        HWC_NIXOS_CONFIG_PATH = paths.nixos;
        HWC_MCP_CACHE_TTL_RUNTIME = toString cfg.cacheTtl.runtime;
        HWC_MCP_CACHE_TTL_DECLARATIVE = toString cfg.cacheTtl.declarative;
        HWC_MCP_MUTATIONS_ENABLED = lib.boolToString cfg.mutations.enable;
        HWC_MCP_ALLOWED_ACTIONS = lib.concatStringsSep "," cfg.mutations.allowedActions;
        HWC_MCP_WORKSPACE = "${paths.nixos}/workspace";
        HWC_HOSTNAME = config.networking.hostName;

        # CMS app path for hwc_cms_* tools
        HWC_CMS_APP_PATH = "/opt/business/heartwood-cms";

        # stdio backend: heartwood-mcp (JT tools)
        HWC_JT_SRC_DIR = jtCfg.srcDir;
        JT_ORG_ID = jtCfg.jt.orgId;
        JT_USER_ID = jtCfg.jt.userId;
        JT_API_URL = jtCfg.jt.apiUrl;

        # stdio backend: n8n-mcp
        HWC_N8N_ENTRY_POINT = "/opt/n8n-mcp/node_modules/n8n-mcp/dist/mcp/index.js";
        N8N_API_URL = "http://localhost:${toString n8nPort}";

        # Node.js path for spawning child processes
        HWC_NODE_PATH = "${pkgs.nodejs_22}/bin/node";
      };

      serviceConfig = mkMerge [
        {
          Type = "simple";
          ExecStartPre = "+${installN8nMcp}";  # + = run as root (npm install needs write to /opt)
          ExecStart = "${pkgs.nodejs_22}/bin/node ${srcDir}/dist/index.js";
          EnvironmentFile = "/run/hwc-sys-mcp/env";
          WorkingDirectory = srcDir;
          Restart = "on-failure";
          RestartSec = "5s";
          User = lib.mkForce "eric";

          # Security hardening
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = "read-only";
          ReadWritePaths = [
            "/tmp"
            "/run/hwc-sys-mcp"
            # Mail tools need write access: notmuch tag (Xapian DB), sync-mail (mbsync marker + lock)
            "/home/eric/400_mail/Maildir"
            "/home/eric/.cache"
            # GPG needs write for lock files and random_seed during pass decrypt
            "/home/eric/.gnupg"
            # msmtp logs here
            "/home/eric/.config/msmtp"
            # Calendar tools: khal writes .ics files, vdirsyncer syncs to iCloud
            "/home/eric/.local/share/vdirsyncer"
            "/home/eric/.local/share/khal"
            # Website content editing via hwc_website_* tools
            "${paths.nixos}/domains/business/website/site_files/src"
            "${paths.nixos}/domains/business/website/site_files/.trash"
            # CMS app editing via hwc_cms_* tools (scope: cms)
            "/opt/business/heartwood-cms"
            # Calculator app editing via hwc_cms_* tools (scope: calculator)
            "${paths.nixos}/domains/business/website/calculator"
          ];
          SupplementaryGroups = [ "podman" ];
          ReadOnlyPaths = [
            paths.nixos
            "/nix/store"
            "/run/systemd"
            "/run/podman"
            # GPG agent socket for pass decrypt (msmtp passwordeval)
            "/run/user/1000/gnupg"
            # agenix secrets for gmail passwordeval
            "/run/agenix"
            # heartwood-mcp source (stdio backend reads dist/)
            jtCfg.srcDir
            # n8n-mcp npm package
            "/opt/n8n-mcp"
          ];
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;

          # Resource limits — gateway + child processes share cgroup
          MemoryMax = "1G";
          CPUQuota = "100%";
        }
      ];

      path = with pkgs; [
        nix
        git
        systemd
        podman
        tailscale
        curl
        jq
        borgbackup
        coreutils
        gawk
        gnugrep
        procps
        util-linux
        nodejs_22
        # msmtp passwordeval chain: sh -c 'pass show ...' → gpg → gpg-agent
        bash
        pass
        gnupg
      ];
    };

    #--------------------------------------------------------------------------
    # VALIDATION
    #--------------------------------------------------------------------------
    assertions = [
      {
        assertion = cfg.port != 0;
        message = "hwc.system.mcp.port must be configured";
      }
    ];
  };
}
