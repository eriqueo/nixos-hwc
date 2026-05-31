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

  # ──────────────────────────────────────────────────────────────────────────
  # hwc-notify-deps-update — automate the npmDepsHash dance
  #
  # `buildNpmPackage` content-pins package-lock.json via npmDepsHash. Any
  # `npm install/update` makes the hash stale and the next nixos-rebuild
  # fails. This CLI runs prefetch-npm-deps on the current lockfile, patches
  # the hash in this index.nix, and stages the touched files for commit.
  #
  # Anchored on config.hwc.paths.nixos (Charter Law 3 — no hardcoded paths
  # outside domains/paths/). When hwc-leads or another service needs the
  # same flow, lift the body into a parameterised helper.
  # ──────────────────────────────────────────────────────────────────────────
  notify-deps-update = pkgs.writeShellApplication {
    name = "hwc-notify-deps-update";
    runtimeInputs = [
      pkgs.prefetch-npm-deps
      pkgs.gnused
      pkgs.git
      pkgs.coreutils
    ];
    text = ''
      set -euo pipefail

      nixos_root="${config.hwc.paths.nixos}"
      service_rel="domains/notifications/notify"
      service_dir="$nixos_root/$service_rel"
      lockfile="$service_dir/parts/src/package-lock.json"
      pkg_json="$service_dir/parts/src/package.json"
      index_nix="$service_dir/index.nix"

      # ── preconditions ──
      [ -f "$lockfile" ]  || { echo "error: lockfile missing: $lockfile" >&2; exit 1; }
      [ -f "$pkg_json" ]  || { echo "error: package.json missing: $pkg_json" >&2; exit 1; }
      [ -f "$index_nix" ] || { echo "error: index.nix missing: $index_nix" >&2; exit 1; }

      if ! grep -q 'npmDepsHash = "sha256-' "$index_nix"; then
        echo "error: no 'npmDepsHash = \"sha256-...\"' line found in $index_nix" >&2
        exit 1
      fi

      # ── compute new hash ──
      echo "[deps-update] reading $lockfile"
      new_hash=$(prefetch-npm-deps "$lockfile")
      echo "[deps-update] new npmDepsHash: $new_hash"

      # ── patch index.nix in-place ──
      # base64 hashes contain + / = which are sed metacharacters; using |
      # as delim sidesteps slash collisions, and the rest are inert in
      # the replacement RHS.
      sed -i "s|npmDepsHash = \"sha256-[A-Za-z0-9+/=]*\"|npmDepsHash = \"$new_hash\"|" "$index_nix"

      # ── stage for commit ──
      git -C "$nixos_root" add \
        "$service_rel/index.nix" \
        "$service_rel/parts/src/package.json" \
        "$service_rel/parts/src/package-lock.json"

      cat <<MSG
[deps-update] patched and staged:
  $service_rel/index.nix
  $service_rel/parts/src/package.json
  $service_rel/parts/src/package-lock.json

Next:
  git -C "$nixos_root" diff --cached
  sudo nixos-rebuild switch --flake "$nixos_root#hwc-server"
MSG
    '';
  };
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

        # Channel secret file paths (resolved through agenix). When the
        # option is null the env var is omitted and the runtime falls back
        # to log-only for that channel — visible warning at startup.
      } // lib.optionalAttrs (cfg.channels.discordAlerts.secretRef != null) {
        HWC_NOTIFY_DISCORD_ALERTS_FILE =
          config.age.secrets.${cfg.channels.discordAlerts.secretRef}.path;
      } // {
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

    # Expose the deps-update CLI on the system PATH.
    environment.systemPackages = [ notify-deps-update ];

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
      {
        # If a secretRef is configured, the secret declaration must exist —
        # otherwise the systemd unit env eval crashes with a confusing
        # "attribute missing" trace.
        assertion =
          cfg.channels.discordAlerts.secretRef == null
          || (config.age.secrets ? ${cfg.channels.discordAlerts.secretRef});
        message = ''
          hwc.notifications.notify.channels.discordAlerts.secretRef =
          "${toString cfg.channels.discordAlerts.secretRef}" but no
          matching agenix secret is declared in
          domains/secrets/declarations/services.nix. Either declare the
          secret or set the secretRef to null to disable the channel.
        '';
      }
    ];
  };
}
