# domains/system/mcp/index.nix
#
# HWC Infrastructure MCP Gateway — unified entry point for all MCP tools.
# Aggregates hwc-sys (local), jt-mcp (stdio), and n8n-mcp (stdio)
# into a single Streamable HTTP transport for Claude.ai and stdio for Claude Code.
#
# NAMESPACE: hwc.system.mcp.*
#
# DEPENDENCIES:
#   - hwc.paths (storage paths, repo location)
#   - Node.js 22 (runtime)
#   - agenix secrets: jobtread-grant-key, n8n-api-key

{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.hwc.system.mcp;
  paths = config.hwc.paths;
  inherit (lib) mkIf mkMerge;

  # khalt supersedes plain khal — its package ships the full `khal`/`ikhal` CLI
  # (source fork). The MCP's hwc_calendar tool shells out to this `khal` and
  # reads the khalt config (calendars-radicale). Resolved from the flake input
  # so we never hardcode a /nix/store path (precedent: agenix in
  # domains/system/core/packages.nix).
  khaltPkg = inputs.khalt.packages.${pkgs.system}.default;
  khaltConfigPath = "${paths.user.home}/.config/khalt/config";

  srcDir = "${paths.nixos}/domains/system/mcp/src";

  # JT config (options from parts/jt.nix)
  jtCfg = config.hwc.system.mcp.jt;

  # Law 3: derive from hwc.paths. apps/business/mail roots are nullable
  # (machine-scoped options), so fall back to their canonical defaults to
  # keep evaluation safe on machines where they are null.
  appsRoot = if paths.apps.root != null then paths.apps.root else "/opt";
  businessRoot = if paths.business.root != null then paths.business.root else "/opt/business";
  mailRoot = if paths.user.mail != null then paths.user.mail else "${paths.user.home}/400_mail";
  cmsAppPath = "${businessRoot}/heartwood-cms";

  # n8n config
  n8nCfg = lib.attrByPath ["hwc" "automation" "n8n"] {} config;
  n8nPort = n8nCfg.port or 5678;
  n8nMcpVersion = "2.40.5";
  n8nMcpInstallDir = "${appsRoot}/n8n-mcp";

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

  # JT PAVE tools — gateway stdio backend (moved from parts/jt.nix; parts/ must be pure)
  options.hwc.system.mcp.jt = {
    enable = lib.mkEnableOption "HWC JobTread MCP tools — JT PAVE tools via gateway stdio backend";

    port = lib.mkOption {
      type = lib.types.port;
      default = 6102;
      description = "Legacy option — no longer used (JT is a stdio backend). Kept for config compat.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Legacy option — no longer used (JT is a stdio backend).";
    };

    logLevel = lib.mkOption {
      type = lib.types.enum [ "debug" "info" "warn" "error" ];
      default = "info";
      description = "Server log level (passed to jt-mcp child process)";
    };

    srcDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.business.root or "/opt/business"}/jt-mcp";
      description = "Path to the built JT MCP server (contains dist/)";
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
    # TMPFILES (runtime directory for env file)
    #--------------------------------------------------------------------------
    systemd.tmpfiles.rules = [
      "d /run/hwc-sys-mcp 0750 eric users -"
      "d /opt/business/website-site/.trash 0750 eric users -"
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
        HWC_CMS_APP_PATH = cmsAppPath;

        # datax_* tools (workbench DataX hub). The gateway consumes the live SR
        # board from the sr_analyzer container (loopback) and overlays the SR
        # gauntlet's investigation ledger — it never touches Firestore directly,
        # so no firebase creds here. ProtectHome=read-only already permits the
        # ledger read; loopback HTTP needs no extra grant.
        HWC_DATAX_ANALYZER_URL = "http://127.0.0.1:8788";
        HWC_DATAX_LEDGER_PATH = "${paths.user.home}/700_datax/sr_gauntlet/state/ledger.json";

        # stdio backend: jt-mcp (JT tools)
        HWC_JT_SRC_DIR = jtCfg.srcDir;
        JT_ORG_ID = jtCfg.jt.orgId;
        JT_USER_ID = jtCfg.jt.userId;
        JT_API_URL = jtCfg.jt.apiUrl;

        # stdio backend: n8n-mcp
        HWC_N8N_ENTRY_POINT = "${n8nMcpInstallDir}/node_modules/n8n-mcp/dist/mcp/index.js";
        N8N_API_URL = "http://localhost:${toString n8nPort}";

        # Node.js path for spawning child processes
        HWC_NODE_PATH = "${pkgs.nodejs_22}/bin/node";

        # Calendar (hwc_calendar): khalt's `khal` binary + the khalt config that
        # points at the Radicale-synced calendars. khalt supersedes plain khal.
        HWC_KHAL_BIN = "${khaltPkg}/bin/khal";
        HWC_KHALT_CONFIG = khaltConfigPath;
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
            "${mailRoot}/Maildir"
            "${paths.user.home}/.cache"
            # GPG needs write for lock files and random_seed during pass decrypt
            "${paths.user.home}/.gnupg"
            # msmtp logs here
            "${paths.user.home}/.config/msmtp"
            # Calendar tools: khal writes .ics files, vdirsyncer syncs to iCloud
            "${paths.user.home}/.local/share/vdirsyncer"
            "${paths.user.home}/.local/share/khal"
            # Website content editing via hwc_website_* tools
            "/opt/business/website-site/src"
            "/opt/business/website-site/.trash"
            # CMS app editing via hwc_cms_* tools (scope: cms)
            cmsAppPath
            # Calculator app editing via hwc_cms_* tools (scope: calculator)
            "${paths.nixos}/domains/business/website/calculator"
            # hwc_nightly_review: flips review JSON status (merge/requeue) and
            # drops the rebuild-request spool under /var/lib/refinery. ProtectHome
            # is read-only here (not tmpfs), so the vault card-requeue write needs
            # its own RW entry on the nightly_builds dir.
            "/var/lib/refinery"
            "${paths.user.home}/900_vaults/brain/_inbox/nightly_builds"
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
            # jt-mcp source (stdio backend reads dist/)
            jtCfg.srcDir
            # n8n-mcp npm package
            n8nMcpInstallDir
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
        gh  # GitHub CLI for hwc_nightly_review merge/requeue (gh pr merge|close)
        postgresql  # psql binary for estimator tools (peer auth as eric)
        # msmtp passwordeval chain: sh -c 'pass show ...' → gpg → gpg-agent
        bash
        pass
        gnupg
      ] ++ [
        # khalt's `khal`/`ikhal`/`vdirsyncer` for the hwc_calendar tool. khalt
        # supersedes plain khal; HWC_KHAL_BIN points at this package's `khal`.
        khaltPkg
        pkgs.vdirsyncer
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
