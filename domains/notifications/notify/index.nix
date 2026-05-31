# domains/notifications/notify/index.nix
#
# hwc-notify — hexagonal notification dispatcher.
#
# Phase 1.3: data-driven channels + routes. Channel registry and routing
# table live in parts/channels.nix and parts/routes.nix as plain Nix
# data; the module resolves agenix `secretRef`s into `secretFile` paths,
# serialises the whole thing to JSON, and passes the path to the runtime
# via HWC_NOTIFY_RUNTIME_CONFIG_FILE. Adding a channel or routing rule
# is now a Nix-only change.
#
# See ~/.claude/plans/hashed-snacking-crab.md for the full design.

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.notifications.notify;

  # ────────────────────────────────────────────────────────────────────
  # Resolve channel rows into the runtime-facing shape.
  # secretRef (an agenix secret name) becomes secretFile (the absolute
  # /run/agenix/<name> path). The TS service never sees the ref name.
  # ────────────────────────────────────────────────────────────────────
  resolveChannel = ch:
    let
      base = { inherit (ch) id name adapter; };

      discordParams = {
        # username/timeoutMs default in Zod (runtime-config.ts) when absent.
        username  = ch.params.username  or "HWC Notify";
        timeoutMs = ch.params.timeoutMs or 5000;
        secretFile = config.age.secrets.${ch.secretRef}.path;
      };

      # SMTP params must include host/port/login/from/to. secretRef →
      # passwordFile path; the rest pass through to Zod (defaults applied
      # there). All passthrough fields are required — channels.nix is the
      # source of truth and must be explicit.
      smtpParams = {
        host         = ch.params.host;
        port         = ch.params.port;
        requireTls   = ch.params.requireTls or false;
        login        = ch.params.login;
        from         = ch.params.from;
        to           = ch.params.to;
        timeoutMs    = ch.params.timeoutMs or 10000;
        passwordFile = config.age.secrets.${ch.secretRef}.path;
      };
    in
      if ch.adapter == "discord" then base // { params = discordParams; }
      else if ch.adapter == "smtp" then base // { params = smtpParams; }
      else base // { params = {}; }; # log-only

  resolvedChannels = map resolveChannel cfg.channels;

  # ────────────────────────────────────────────────────────────────────
  # Build the runtime-config JSON and stick it in the Nix store. The
  # path lives in the store, is immutable, and rotates on every rebuild
  # — exactly the right shape for a config file the service reads once
  # at startup.
  # ────────────────────────────────────────────────────────────────────
  runtimeConfigJson = builtins.toJSON {
    channels        = resolvedChannels;
    routes          = cfg.routes;
    defaultChannels = cfg.defaultChannels;
  };

  runtimeConfigFile = pkgs.writeText "hwc-notify-runtime-config.json" runtimeConfigJson;

  # ────────────────────────────────────────────────────────────────────
  # Hermetic Nix-built TS service.
  # ────────────────────────────────────────────────────────────────────
  hwc-notify-pkg = pkgs.buildNpmPackage {
    pname = "hwc-notify";
    version = "0.1.0";

    src = lib.cleanSourceWith {
      src = ./parts/src;
      filter = path: type:
        let base = baseNameOf path;
        in base != "node_modules" && base != "dist" && base != ".gitignore";
    };

    npmDepsHash = "sha256-aHTyFXqcdaOZHHwdyriSJqXFvrlFHVKZXPt4z0JvQ54=";
    npmBuildScript = "build";
    dontNpmPrune = false;
  };

  mainJs = "${hwc-notify-pkg}/lib/node_modules/hwc-notify/dist/main.js";

  # ────────────────────────────────────────────────────────────────────
  # Wrapper CLI — automates the npmDepsHash dance after npm install.
  # See wiki/nixos/nixos-buildnpmpackage-hash-workflow.md for the why.
  # ────────────────────────────────────────────────────────────────────
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

      [ -f "$lockfile" ]  || { echo "error: lockfile missing: $lockfile" >&2; exit 1; }
      [ -f "$pkg_json" ]  || { echo "error: package.json missing: $pkg_json" >&2; exit 1; }
      [ -f "$index_nix" ] || { echo "error: index.nix missing: $index_nix" >&2; exit 1; }

      if ! grep -q 'npmDepsHash = "sha256-' "$index_nix"; then
        echo "error: no 'npmDepsHash = \"sha256-...\"' line found in $index_nix" >&2
        exit 1
      fi

      echo "[deps-update] reading $lockfile"
      new_hash=$(prefetch-npm-deps "$lockfile")
      echo "[deps-update] new npmDepsHash: $new_hash"

      sed -i "s|npmDepsHash = \"sha256-[A-Za-z0-9+/=]*\"|npmDepsHash = \"$new_hash\"|" "$index_nix"

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

  # Channel IDs declared in cfg.channels — used for cross-ref assertions.
  declaredChannelIds = map (c: c.id) cfg.channels;

  # Channel IDs referenced anywhere a route/default points.
  referencedChannelIds =
    cfg.defaultChannels
    ++ lib.concatMap (r: r.channels) cfg.routes;

  unknownReferencedIds =
    lib.subtractLists declaredChannelIds referencedChannelIds;
in
{
  imports = [ ./options.nix ];

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
        HWC_NOTIFY_BIND_ADDR           = cfg.bindAddr;
        HWC_NOTIFY_PORT                = toString cfg.port;
        HWC_NOTIFY_STATE_DIR           = cfg.statePath;
        HWC_NOTIFY_LOG_LEVEL           = cfg.logLevel;
        HWC_NOTIFY_RUNTIME_CONFIG_FILE = "${runtimeConfigFile}";

        PATH = lib.mkForce "/run/current-system/sw/bin:/etc/profiles/per-user/${cfg.user}/bin";
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

        # Hardening — mirrors persona-daemon / brain-mcp.
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
        # Every Discord/SMTP channel needs a secretRef AND the named
        # agenix secret must exist. Catch typos at eval time, not at
        # runtime.
        assertion =
          lib.all
            (ch:
              (ch.adapter != "discord" && ch.adapter != "smtp")
              || (ch.secretRef != null
                  && (config.age.secrets ? ${ch.secretRef})))
            cfg.channels;
        message = ''
          One or more discord/smtp channels in
          hwc.notifications.notify.channels is missing a valid secretRef.
          Each row with adapter = "discord" or "smtp" must have secretRef
          set to an agenix secret name declared in
          domains/secrets/declarations/.
        '';
      }
      {
        # Every channel id referenced in routes/defaultChannels must be
        # declared in cfg.channels. Cross-ref check at eval time.
        assertion = unknownReferencedIds == [];
        message = ''
          hwc.notifications.notify.routes / .defaultChannels reference
          channel id(s) not declared in .channels: ${toString unknownReferencedIds}
          Declare them in cfg.channels or remove the references.
        '';
      }
    ];
  };
}
