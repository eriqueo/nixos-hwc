# domains/system/mcp/index.nix
#
# HWC Infrastructure MCP Server — exposes system config and runtime state
# as MCP tools for Claude Code and Claude.ai mobile access.
#
# NAMESPACE: hwc.system.mcp.*
#
# DEPENDENCIES:
#   - hwc.paths (storage paths, repo location)
#   - Node.js 22 (runtime)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.mcp;
  paths = config.hwc.paths;
  inherit (lib) mkIf mkMerge;

  srcDir = "${paths.nixos}/domains/system/mcp/src";
in
{
  imports = [
    ./parts/caddy.nix
  ];

  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.system.mcp = {
    enable = lib.mkEnableOption "HWC Infrastructure MCP server — system config and runtime state";

    port = lib.mkOption {
      type = lib.types.port;
      default = 6200;
      description = "SSE transport listen port";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "SSE transport bind address";
    };

    transport = lib.mkOption {
      type = lib.types.enum [ "stdio" "sse" "both" ];
      default = "both";
      description = "MCP transport mode. 'both' runs SSE on the configured port and also supports stdio.";
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
    # SYSTEMD SERVICE
    #--------------------------------------------------------------------------
    systemd.services.hwc-infra-mcp = {
      description = "HWC Infrastructure MCP Server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "tailscaled.service" ];
      wants = [ "network-online.target" ];

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
        # n8n MCP bridge proxy config (used by /n8n/* route in index.ts)
        HWC_N8N_MCP_PORT = toString ((lib.attrByPath ["hwc" "automation" "n8n" "mcpBridge" "port"] 6201 config));
        HWC_N8N_MCP_AUTH_TOKEN = "hwc-n8n-mcp-internal-bridge-token-do-not-expose-externally";
      };

      serviceConfig = mkMerge [
        {
          Type = "simple";
          ExecStart = "${pkgs.nodejs_22}/bin/node ${srcDir}/dist/index.js";
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
            # Mail tools need write access: notmuch tag (Xapian DB), sync-mail (mbsync marker + lock)
            "/home/eric/400_mail/Maildir"
            "/home/eric/.cache"
            # GPG needs write for lock files and random_seed during pass decrypt
            "/home/eric/.gnupg"
            # msmtp logs here
            "/home/eric/.config/msmtp"
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
          ];
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;

          # Resource limits
          MemoryMax = "512M";
          CPUQuota = "50%";
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
