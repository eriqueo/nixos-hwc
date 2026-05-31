# domains/notifications/notify/index.nix
#
# hwc-notify — hexagonal notification dispatcher (Node 22, --experimental-strip-types).
#
# Phase 1.1: minimal HTTP server with /health only. Subsequent chunks
# add channel adapters, routing, /notify endpoint, audit log, CLI, MCP.
#
# Runtime pattern mirrors domains/server/native/ai/hermes: TS source
# bundled into the Nix store via sourceFilesBySuffices; Node 22 strips
# types at parse time. No npm install, no build step, no node_modules
# at runtime. package.json + node_modules in the working tree are
# type-only metadata for IDE typechecking.
#
# See ~/.claude/plans/hashed-snacking-crab.md for the full design.

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.notifications.notify;

  # Bundle all .ts files under parts/src/src into ONE Nix store path so
  # relative imports between modules resolve. Individual file references
  # would put each .ts in its own store path and break ./adapters/log-stderr.ts
  # → ../ports/log.ts.
  src = lib.sources.sourceFilesBySuffices ./parts/src/src [ ".ts" ];

  node = "${pkgs.nodejs_22}/bin/node";
in
{
  # OPTIONS
  imports = [ ./options.nix ];

  # IMPLEMENTATION
  config = lib.mkIf cfg.enable {

    #========================================================================
    # SYSTEMD SERVICE
    #========================================================================
    systemd.services.hwc-notify = {
      description = "hwc-notify — hexagonal notification dispatcher";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        HWC_NOTIFY_BIND_ADDR  = cfg.bindAddr;
        HWC_NOTIFY_PORT       = toString cfg.port;
        HWC_NOTIFY_STATE_DIR  = cfg.statePath;
        HWC_NOTIFY_LOG_LEVEL  = cfg.logLevel;
        PATH = lib.mkForce "/run/current-system/sw/bin:/etc/profiles/per-user/${cfg.user}/bin";
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = lib.concatStringsSep " " [
          node
          "--experimental-strip-types"
          "--no-warnings"
          "${src}/main.ts"
        ];
        User = lib.mkForce cfg.user;
        Group = "users";
        Restart = "on-failure";
        RestartSec = "5s";

        StateDirectory = "hwc/notify";
        StateDirectoryMode = "0750";

        # Hardening — same set as persona-daemon / brain-mcp.
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        SystemCallArchitectures = "native";
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;

        ReadWritePaths = [ cfg.statePath ];
      };
    };

    #========================================================================
    # CADDY REVERSE PROXY — port mode over tailnet
    #========================================================================
    hwc.networking.shared.routes = [{
      name = "hwc-notify";
      mode = "port";
      port = cfg.reverseProxyPort;
      upstream = "http://${cfg.bindAddr}:${toString cfg.port}";
    }];

    #========================================================================
    # VALIDATION
    #========================================================================
    assertions = [
      {
        assertion = cfg.user != "root";
        message = "hwc.notifications.notify.user must not be root (Charter Law 4).";
      }
      {
        assertion = cfg.port != cfg.reverseProxyPort;
        message = "hwc.notifications.notify.port and reverseProxyPort must differ.";
      }
    ];
  };
}
