# domains/notifications/notify/index.nix
#
# hwc-notify — hexagonal notification dispatcher.
#
# Phase 1.1: minimal HTTP server with /health only. Subsequent chunks
# add channel adapters, routing, /notify endpoint, audit log, CLI, MCP.
#
# Deployment shape: pkgs.buildNpmPackage builds a hermetic derivation
# from parts/src/ — every nixos-rebuild produces an identical store
# path containing dist/*.js + a fully populated node_modules/. No
# `npm install` at deploy time, no network, no developer manual-build
# step. Reproducibility is enforced by `npmDepsHash` being content-
# pinned against package-lock.json — changing deps means regenerating
# the hash (see README for the workflow).
#
# See ~/.claude/plans/hashed-snacking-crab.md for the full design.

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.notifications.notify;

  # Hermetic Nix-built package. Reads parts/src/{package.json,package-lock.json}
  # to fetch deps offline (against npmDepsHash) and runs `npm run build` →
  # produces dist/*.js. Output lives at:
  #   ${hwc-notify-pkg}/lib/node_modules/hwc-notify/
  #     ├── dist/         (compiled JS + sourcemaps)
  #     ├── node_modules/ (runtime deps; zod, etc.)
  #     └── package.json
  hwc-notify-pkg = pkgs.buildNpmPackage {
    pname = "hwc-notify";
    version = "0.1.0";

    # Bundle only the files buildNpmPackage needs. node_modules + dist
    # are excluded from the dev tree by .gitignore and would just be
    # rebuilt anyway.
    src = lib.cleanSourceWith {
      src = ./parts/src;
      filter = path: type:
        let base = baseNameOf path;
        in base != "node_modules" && base != "dist" && base != ".gitignore";
    };

    # First-time setup: leave as lib.fakeHash, run nixos-rebuild, copy the
    # "got: sha256-…" line from the error into here, rebuild succeeds.
    # Subsequent dep updates require the same dance (a hash mismatch is
    # the build telling you the lockfile changed).
    npmDepsHash = "sha256-w76KLDIujl5jpChGB5hE1mgKLg1hGQeijtMA0ke0/GQ=";

    # npm run build → tsc → dist/. Default `npmBuildScript = "build"`,
    # so this is the existing behavior — declared explicitly for clarity.
    npmBuildScript = "build";

    # Disable npm version-tag checking. We don't publish to npm, so the
    # name@version aren't expected to be reachable on the registry.
    dontNpmPrune = false;
  };

  mainJs = "${hwc-notify-pkg}/lib/node_modules/hwc-notify/dist/main.js";
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
        # NODE_ENV=production silences the Node performance hint and gives
        # well-behaved libs their fast paths.
        NODE_ENV = "production";
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.nodejs_22}/bin/node ${mainJs}";
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
