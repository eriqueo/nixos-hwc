# domains/server/native/ai/persona-daemon/index.nix
#
# Persona-aware HTTP daemon + SQLite conversation memory.
# Deno runtime (matches brain-mcp); TS source bundled into the Nix store
# via sourceFilesBySuffices (matches hermes).
#
# Commit 2 scope: conversations only. RAG indexer comes in Commit 3.

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.server.ai.personaDaemon;
  paths = config.hwc.paths;
  llamaCpp = config.hwc.server.ai.llamaCpp;
  deno = "${pkgs.deno}/bin/deno";

  # Bundle all .ts + deno.jsonc into one Nix store path so relative imports
  # between modules resolve. Same trick hermes uses for its bootstrap CLI.
  src = lib.sources.sourceFilesBySuffices ./parts/src [ ".ts" ".jsonc" ".json" ];

  # Deno also uses --allow-net to gate MODULE FETCHING from jsr.io / npm,
  # not just runtime sockets. Restricting to specific hosts would block
  # `import "jsr:@db/sqlite"` on a cold cache. Wide --allow-net mirrors
  # brain-mcp's pattern; defense-in-depth is bindAddr (loopback-only).
in
{
  #========================================================================
  # OPTIONS
  #========================================================================
  options.hwc.server.ai.personaDaemon = {
    enable = lib.mkEnableOption "persona-daemon (Deno) HTTP + memory layer";

    user = lib.mkOption {
      type = lib.types.str;
      default = "eric";
      description = "Service user (Charter: native services run as eric:users).";
    };

    bindAddr = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = ''
        Address to bind the HTTP listener. Default loopback-only;
        external access goes via Caddy (added in Commit 4).
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 11550;
      description = "TCP port for the HTTP listener.";
    };

    statePath = lib.mkOption {
      type = lib.types.path;
      default = "${paths.state}/persona-daemon";
      description = ''
        Directory holding SQLite state (conversations.db). systemd
        StateDirectory creates this owned by the service user:users at 0750.
      '';
    };

    personaManifestFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to the persona library JSON manifest. Normally set
        automatically by `domains/ai/personas/index.nix` when both
        modules are enabled. Set to null only if you want to ship a
        custom library outside the personas module.
      '';
    };

    vaultPath = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = paths.brain.server-replica or null;
      description = ''
        Path to the brain vault for RAG indexing. Defaults to
        hwc.paths.brain.server-replica (= /home/eric/900_vaults/brain on hwc-server).
        Set to null to disable RAG entirely; useKnowledge personas then
        receive no retrieval context (chat still works).
      '';
    };

    chatBackends = {
      gpu.url = lib.mkOption {
        type = lib.types.str;
        default = "http://127.0.0.1:${toString llamaCpp.gpu.port}";
        description = "Base URL of the GPU chat llama-server.";
      };
      cpu.url = lib.mkOption {
        type = lib.types.str;
        default = "http://127.0.0.1:${toString llamaCpp.cpu.port}";
        description = "Base URL of the CPU chat llama-server.";
      };
      embed.url = lib.mkOption {
        type = lib.types.str;
        default = "http://127.0.0.1:${toString llamaCpp.embed.port}";
        description = ''
          Base URL of the embeddings llama-server. Unused in the
          conversation-only commit; Commit 3 adds RAG over the vault.
        '';
      };
    };

    # Conversation memory tuning
    maxRecentTurns = lib.mkOption {
      type = lib.types.int;
      default = 16;
      description = ''
        When a conversation accumulates more than this many turns, the
        oldest will be eligible for background summarization
        (implemented in Commit 3 / later). For now we truncate.
      '';
    };

    keepRecentTurns = lib.mkOption {
      type = lib.types.int;
      default = 8;
      description = "Number of most-recent turns to keep verbatim post-summarization.";
    };

    # Logging
    logLevel = lib.mkOption {
      type = lib.types.enum [ "debug" "info" "warn" "error" ];
      default = "info";
      description = "Minimum severity for structured JSON log output.";
    };

    # Brain-MCP integration (used by inbox_capture MCP tool)
    brainMcp = {
      url = lib.mkOption {
        type = lib.types.str;
        default = "http://127.0.0.1:${toString (config.hwc.server.ai.brainMcp.port or 9876)}";
        description = ''
          Base URL of brain-mcp (Deno). Used by the daemon's inbox_capture
          tool — single-writer principle, daemon does not write the vault
          directly.
        '';
      };
      apiKeyFile = lib.mkOption {
        type = lib.types.path;
        default = "/run/agenix/brain-mcp-api-key";
        description = ''
          Path to brain-mcp's bearer-token secret. The daemon reads it once
          at startup. Same agenix secret brain-mcp itself uses, so eric needs
          read access (already granted via the secrets group).
        '';
      };
    };

    # External-facing reverse proxy (Caddy)
    reverseProxyPort = lib.mkOption {
      type = lib.types.port;
      default = 28443;
      description = ''
        External Caddy port for tailnet access. Loopback daemon is on
        `bindAddr:port`; Caddy fronts it on this port using the tailnet cert.
      '';
    };
  };

  config = lib.mkIf cfg.enable {

    #========================================================================
    # SYSTEMD SERVICE
    #========================================================================
    systemd.services.persona-daemon = {
      description = "Persona-aware HTTP daemon + SQLite memory (Deno)";
      after = [ "network-online.target" "llama-gpu.service" "llama-cpu.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        PERSONA_DAEMON_BIND_ADDR    = cfg.bindAddr;
        PERSONA_DAEMON_PORT         = toString cfg.port;
        PERSONA_DAEMON_STATE_DIR    = cfg.statePath;
        PERSONA_DAEMON_DB_PATH      = "${cfg.statePath}/store.db";
        # The assertion below catches the null case at eval time; toString
        # null = "" is a harmless placeholder until then.
        PERSONA_DAEMON_MANIFEST     = toString (cfg.personaManifestFile or "");
        PERSONA_DAEMON_GPU_URL      = cfg.chatBackends.gpu.url;
        PERSONA_DAEMON_CPU_URL      = cfg.chatBackends.cpu.url;
        PERSONA_DAEMON_EMBED_URL    = cfg.chatBackends.embed.url;
        PERSONA_DAEMON_VAULT_PATH   = toString (cfg.vaultPath or "");
        PERSONA_DAEMON_BRAIN_MCP_URL = cfg.brainMcp.url;
        PERSONA_DAEMON_BRAIN_MCP_KEY_FILE = toString cfg.brainMcp.apiKeyFile;
        PERSONA_DAEMON_MAX_RECENT   = toString cfg.maxRecentTurns;
        PERSONA_DAEMON_KEEP_RECENT  = toString cfg.keepRecentTurns;
        PERSONA_DAEMON_LOG_LEVEL    = cfg.logLevel;
        DENO_DIR                    = "/var/cache/persona-daemon/deno";
        HOME                        = "/home/${cfg.user}";
        PATH = lib.mkForce "/run/current-system/sw/bin:/etc/profiles/per-user/${cfg.user}/bin";
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = lib.concatStringsSep " " [
          deno "run"
          "--allow-read"
          "--allow-write=${cfg.statePath},/var/cache/persona-daemon"
          "--allow-net"
          "--allow-env"
          # @db/sqlite ships native SQLite via FFI. Path-scoping --allow-ffi
          # gates dlopen but not subsequent function calls; unscoped is
          # required. Mitigated by --allow-write being narrowly scoped, so
          # the daemon can't drop a malicious .so into the cache dir.
          "--allow-ffi"
          # Deno tries to write deno.lock next to main.ts; main.ts lives in
          # the Nix store (read-only). Deps are version-pinned in deno.jsonc
          # so the lockfile is redundant.
          "--no-lock"
          "${src}/main.ts"
        ];
        User = lib.mkForce cfg.user;
        Group = "users";
        Restart = "on-failure";
        RestartSec = "5s";

        StateDirectory = "hwc/persona-daemon";
        StateDirectoryMode = "0750";
        CacheDirectory = "persona-daemon";
        CacheDirectoryMode = "0750";

        # Hardening (mirror brain-mcp)
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

        ReadWritePaths = [
          cfg.statePath
          "/var/cache/persona-daemon"
        ];
      };
    };

    #========================================================================
    # SYSTEMD TIMER — slow reconcile backstop
    # The daemon itself watches the vault recursively (in-process inotify) and
    # reconciles on every burst of edits, plus once on startup — that is the
    # primary freshness mechanism. Reindex is content-addressed: it re-embeds
    # only notes whose bytes changed (sha256), so a no-op pass is genuinely
    # cheap (stat + read + hash, no embedding). This timer exists ONLY as a
    # backstop for the rare event the watcher misses (a dropped inotify event,
    # or the watch being re-established mid-change). 6h is ample.
    #
    # NOTE: there is deliberately no systemd.path unit — systemd PathChanged=
    # does not recurse into subdirectories, which is exactly the case the
    # in-process recursive watcher now handles.
    #========================================================================
    systemd.timers = lib.mkIf (cfg.vaultPath != null) {
      persona-daemon-reindex = {
        description = "Slow reconcile backstop for persona-daemon (in-process watcher is primary)";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "15min";
          OnUnitActiveSec = "6h";
          Persistent = false;
        };
      };
    };

    systemd.services.persona-daemon-reindex = lib.mkIf (cfg.vaultPath != null) {
      description = "POST /_internal/reindex to persona-daemon";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.curl}/bin/curl -fsS -X POST -H 'content-type: application/json' -d '{}' http://${cfg.bindAddr}:${toString cfg.port}/_internal/reindex";
        User = lib.mkForce cfg.user;
        Group = "users";
      };
    };

    #========================================================================
    # CADDY REVERSE PROXY — port mode on :28443 over tailnet
    #========================================================================
    hwc.networking.shared.routes = [{
      name = "persona-daemon";
      mode = "vhost";
      upstream = "http://${cfg.bindAddr}:${toString cfg.port}";
    }];

    #========================================================================
    # PROMETHEUS SCRAPE — register with the monitoring stack
    #========================================================================
    hwc.monitoring.prometheus.scrapeConfigs = [{
      job_name = "persona-daemon";
      static_configs = [{ targets = [ "${cfg.bindAddr}:${toString cfg.port}" ]; }];
      metrics_path = "/metrics";
      scrape_interval = "30s";
    }];

    #========================================================================
    # CLI — persona-admin reindex [--full|--note <path>]
    #========================================================================
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "persona-admin";
        runtimeInputs = [ pkgs.curl pkgs.jq ];
        text = ''
          base="http://${cfg.bindAddr}:${toString cfg.port}"
          case "''${1:-}" in
            reindex)
              shift
              full="false"
              note=""
              while [ $# -gt 0 ]; do
                case "$1" in
                  --full) full="true"; shift ;;
                  --note) note="$2"; shift 2 ;;
                  *) echo "unknown flag: $1" >&2; exit 2 ;;
                esac
              done
              body=$(jq -n --argjson full "$full" --arg note "$note" \
                '{full: $full} | if ($note | length) > 0 then . + {notePath: $note} else . end')
              curl -fsS -X POST -H 'content-type: application/json' -d "$body" \
                "$base/_internal/reindex" | jq
              ;;
            health|status)
              curl -fsS "$base/_internal/health" | jq
              ;;
            conversations)
              shift
              persona="''${1:-}"
              if [ -n "$persona" ]; then
                curl -fsS "$base/_internal/conversations?persona=$persona&limit=50" | jq
              else
                curl -fsS "$base/_internal/conversations?limit=50" | jq
              fi
              ;;
            *)
              cat >&2 <<'EOF'
usage:
  persona-admin reindex [--full] [--note <vault-relative-path>]
  persona-admin health
  persona-admin conversations [<persona>]
EOF
              exit 2
              ;;
          esac
        '';
      })
    ];

    #========================================================================
    # VALIDATION
    #========================================================================
    assertions = [
      {
        assertion = cfg.personaManifestFile != null;
        message = ''
          hwc.server.ai.personaDaemon.enable = true requires
          personaManifestFile to be set. Enable hwc.ai.personas (which
          wires it automatically) or provide an explicit manifest path.
        '';
      }
      {
        assertion = config.hwc.server.ai.llamaCpp.enable;
        message = ''
          hwc.server.ai.personaDaemon depends on hwc.server.ai.llamaCpp
          (the daemon proxies to llama-gpu/llama-cpu and, in Commit 3, llama-embed).
        '';
      }
      {
        assertion = cfg.keepRecentTurns < cfg.maxRecentTurns;
        message = ''
          hwc.server.ai.personaDaemon.keepRecentTurns (${toString cfg.keepRecentTurns})
          must be < maxRecentTurns (${toString cfg.maxRecentTurns}) — otherwise
          summarization never fires.
        '';
      }
    ];
  };
}
