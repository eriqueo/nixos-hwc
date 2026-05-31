# domains/notifications/notify/options.nix
#
# Schema for hwc.notifications.notify.*
#
# Charter Law 2: namespace = folder. Charter Law 3: no hardcoded paths
# outside domains/paths/. Charter Law 4: service runs as eric:users.

{ lib, config, ... }:

let
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
in
{
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
}
