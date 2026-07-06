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

  paths = config.hwc.paths;

  # Submodule type for a single channel row. Mirrors the ChannelConfig
  # discriminated union in parts/src/src/schemas/runtime-config.ts —
  # both shapes must stay in sync (the runtime-config.json roundtrip
  # validates at startup, so a drift will fail fast).
  channelType = lib.types.submodule {
    options = {
      id = lib.mkOption {
        type = lib.types.str;
        description = "Stable channel id, used in routing rules + audit log.";
      };
      name = lib.mkOption {
        type = lib.types.str;
        description = "Human label for logs and the /health response.";
      };
      adapter = lib.mkOption {
        type = lib.types.enum [ "discord" "smtp" "log-only" ];
        description = "Adapter type. Must match a builder in main.ts.";
      };
      secretRef = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          agenix secret name (NOT a path). Resolved at module-eval to
          `config.age.secrets.<ref>.path` and surfaced to the runtime as
          `params.secretFile`. Required for adapter = "discord".
        '';
      };
      params = lib.mkOption {
        type = lib.types.attrs;
        default = {};
        description = ''
          Adapter-specific parameters. For "discord": optional
          `username` (string) and `timeoutMs` (int). For "log-only":
          empty.
        '';
      };
    };
  };

  routeMatchType = lib.types.submodule {
    options = {
      topic = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Exact-match notification.topic when set.";
      };
      source = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Exact-match notification.source when set.";
      };
      priority = lib.mkOption {
        type = lib.types.nullOr (lib.types.ints.between 1 5);
        default = null;
        description = "Exact-match notification.priority when set.";
      };
    };
  };

  routeType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Human label; appears in logs and POST /notify responses.";
      };
      match = lib.mkOption {
        type = routeMatchType;
        default = {};
        description = "Predicate. Empty = catchall.";
      };
      channels = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = "Channel ids to dispatch to when this rule matches.";
      };
    };
  };

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

  # hwc-notify-deps-update CLI — produced by the shared
  # domains/lib/deps-update.nix helper. Same shape for any other
  # buildNpmPackage-built service (e.g. hwc-leads in Phase 2.1).
  notify-deps-update = (import ../../lib/deps-update.nix { inherit pkgs config; }) {
    serviceName = "hwc-notify";
    serviceRel  = "domains/notifications/notify";
  };

  # ────────────────────────────────────────────────────────────────────
  # hwc-notify CLI — thin shell wrapper over the local HTTP service.
  #
  # Subcommands:
  #   hwc-notify send <topic> <title> [body] [--priority N] [--source S] [--tags t1,t2]
  #   hwc-notify recent [--limit N] [--topic X] [--source Y] [--status ok|failed]
  #   hwc-notify status        # circuit-breaker state
  #   hwc-notify health
  # ────────────────────────────────────────────────────────────────────
  notify-cli = pkgs.writeShellApplication {
    name = "hwc-notify";
    runtimeInputs = [ pkgs.curl pkgs.jq pkgs.coreutils ];
    text = ''
      set -euo pipefail
      base="http://${cfg.bindAddr}:${toString cfg.port}"

      usage() {
        cat >&2 <<EOF
Usage:
  hwc-notify send <topic> <title> [body] [--priority N] [--source S] [--tags t1,t2]
  hwc-notify recent [--limit N] [--topic X] [--source Y] [--status ok|failed]
  hwc-notify status
  hwc-notify health
EOF
        exit 2
      }

      [ $# -lt 1 ] && usage
      subcmd="$1"; shift

      case "$subcmd" in
        send)
          [ $# -lt 2 ] && usage
          topic="$1"; shift
          title="$1"; shift
          body=""
          priority=3
          source="cli"
          tags="[]"
          if [ $# -gt 0 ] && [[ "$1" != --* ]]; then
            body="$1"; shift
          fi
          while [ $# -gt 0 ]; do
            case "$1" in
              --priority) priority="$2"; shift 2 ;;
              --source) source="$2"; shift 2 ;;
              --tags)
                # Comma-separated -> JSON array
                tags=$(echo "$2" | jq -R -s 'split(",") | map(gsub("^\\s+|\\s+$"; ""))')
                shift 2 ;;
              *) echo "unknown flag: $1" >&2; usage ;;
            esac
          done
          payload=$(jq -nc \
            --arg topic "$topic" --arg title "$title" --arg body "$body" \
            --arg source "$source" --argjson priority "$priority" --argjson tags "$tags" \
            '{topic: $topic, title: $title, body: $body, priority: $priority, source: $source, tags: $tags}')
          curl -fsS --max-time 10 -X POST -H 'content-type: application/json' -d "$payload" "$base/notify" | jq
          ;;
        recent)
          limit=50
          q=""
          while [ $# -gt 0 ]; do
            case "$1" in
              --limit) limit="$2"; shift 2 ;;
              --topic) q+="&topic=$(jq -rn --arg v "$2" '$v|@uri')"; shift 2 ;;
              --source) q+="&source=$(jq -rn --arg v "$2" '$v|@uri')"; shift 2 ;;
              --status) q+="&status=$2"; shift 2 ;;
              *) echo "unknown flag: $1" >&2; usage ;;
            esac
          done
          curl -fsS --max-time 10 "$base/audit/recent?limit=$limit$q" | jq
          ;;
        status)
          curl -fsS --max-time 10 "$base/circuit/status" | jq
          ;;
        health)
          curl -fsS --max-time 10 "$base/health" | jq
          ;;
        --help|-h|help) usage ;;
        *) echo "unknown subcommand: $subcmd" >&2; usage ;;
      esac
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
  #========================================================================
  # OPTIONS
  #========================================================================
  options.hwc.notifications.notify = {
    enable = lib.mkEnableOption ''
      hwc-notify — hexagonal notification dispatcher.
      Routes Notifications to Discord + SMTP via pluggable adapters,
      with declarative channel + routing tables. Replaces the n8n
      alert-manager workflow and the per-script CLI senders. See
      ~/.claude/plans/hashed-snacking-crab.md.
    '';

    user = lib.mkOption {
      type = lib.types.str;
      default = "eric";
      description = "Service user (Charter Law 4: native services run as eric:users).";
    };

    bindAddr = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = ''
        Address to bind the HTTP listener. Default loopback-only; external
        access goes via Caddy on the reverseProxyPort.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 11600;
      description = "TCP port for the HTTP listener.";
    };

    reverseProxyPort = lib.mkOption {
      type = lib.types.port;
      default = 29443;
      description = ''
        External Caddy port for tailnet access. Loopback daemon is on
        bindAddr:port; Caddy fronts it on this port using the tailnet cert.
      '';
    };

    statePath = lib.mkOption {
      type = lib.types.path;
      default = "${paths.state}/notify";
      description = ''
        Directory holding service state (audit log SQLite DB, dedup cache).
        systemd StateDirectory creates this owned by user:users at 0750.
      '';
    };

    logLevel = lib.mkOption {
      type = lib.types.enum [ "debug" "info" "warn" "error" ];
      default = "info";
      description = "Minimum severity for structured JSON log output.";
    };

    # ── Channel registry + routing (data-driven) ────────────────────────
    # Defaults live in parts/channels.nix + parts/routes.nix; override or
    # append per-machine by setting these in the host's config.

    channels = lib.mkOption {
      type = lib.types.listOf channelType;
      default = import ./parts/channels.nix;
      description = ''
        Channel registry. The runtime-config.json passed to the service
        is built from this list with `secretRef` rewritten to its
        agenix-mounted path. Override or append per-machine to wire new
        channels without touching TS.
      '';
    };

    routes = lib.mkOption {
      type = lib.types.listOf routeType;
      default = import ./parts/routes.nix;
      description = ''
        Routing rules — first match wins. Each rule's match block is
        ANDed across set fields (empty match = catchall); channels lists
        the ids to dispatch to. Reference only channel ids declared in
        `channels` above (a startup cross-ref check fails loud otherwise).
      '';
    };

    defaultChannels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "discord-hwc-alerts" ];
      description = ''
        Channels to dispatch to when no routing rule matches. Empty list
        means "drop on the floor" (audit log still records the receipt).
      '';
    };
  };

  config = lib.mkIf cfg.enable {

    #========================================================================
    # SYSTEMD SERVICE
    #========================================================================
    systemd.services.hwc-notify = {
      description = "hwc-notify — hexagonal notification dispatcher";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      # Restart the service when any channel's source .age file content
      # changes — i.e., when an agenix secret rotates. Without this,
      # nixos-rebuild switch re-mounts /run/agenix/<name> but doesn't
      # restart hwc-notify (the unit definition didn't change), and the
      # in-memory cached password keeps failing auth.
      # See ~/.claude/projects/-home-eric--nixos/memory/reference_agenix_rotate_needs_restart.md
      restartTriggers = builtins.filter (x: x != null) (
        map (ch:
          if ch.secretRef != null
          then config.age.secrets.${ch.secretRef}.file
          else null
        ) cfg.channels
      );

      environment = {
        HWC_NOTIFY_BIND_ADDR           = cfg.bindAddr;
        HWC_NOTIFY_PORT                = toString cfg.port;
        HWC_NOTIFY_STATE_DIR           = cfg.statePath;
        HWC_NOTIFY_LOG_LEVEL           = cfg.logLevel;
        HWC_NOTIFY_RUNTIME_CONFIG_FILE = "${runtimeConfigFile}";

        PATH = lib.mkForce "/run/current-system/sw/bin:/etc/profiles/per-user/${cfg.user}/bin";
        NODE_ENV = "production";
      };

      unitConfig.StartLimitIntervalSec = 0;

      serviceConfig = {
        Type = "simple";
        # --experimental-sqlite enables node:sqlite (Node 22.5+).
        # --no-warnings silences the "experimental feature" notice;
        # we'll drop both flags when sqlite goes stable.
        ExecStart = "${pkgs.nodejs_22}/bin/node --experimental-sqlite --no-warnings ${mainJs}";
        User = lib.mkForce cfg.user;
        Group = "users";
        # "always" (not on-failure): a clean-exit bug must not leave the
        # dispatcher down. StartLimitIntervalSec=0: never lock into "failed"
        # after a restart burst (the redis-main boot-race lesson, 2026-07-06).
        Restart = "always";
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

    # Expose the deps-update + user CLIs on the system PATH.
    environment.systemPackages = [ notify-deps-update notify-cli ];

    #========================================================================
    # WATCHDOG — catches hangs Restart= can't see (process alive, HTTP dead)
    #========================================================================
    systemd.timers.hwc-notify-watchdog = {
      description = "hwc-notify liveness probe timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "3min";
        OnUnitActiveSec = "5min";
        Persistent = false;
      };
    };

    systemd.services.hwc-notify-watchdog = {
      description = "hwc-notify liveness probe (restart on dead /health)";
      after = [ "hwc-notify.service" ];
      serviceConfig = {
        Type = "oneshot";
        # Root: needs systemctl restart. Probe twice before acting so a
        # single slow GC pause doesn't bounce the service.
        ExecStart = pkgs.writeShellScript "hwc-notify-watchdog" ''
          probe() {
            ${pkgs.curl}/bin/curl -fsS --max-time 10 \
              "http://${cfg.bindAddr}:${toString cfg.port}/health" >/dev/null 2>&1
          }
          if probe; then exit 0; fi
          sleep 15
          if probe; then exit 0; fi
          echo "hwc-notify /health dead twice in 15s - restarting"
          ${pkgs.systemd}/bin/systemctl restart hwc-notify.service
        '';
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
