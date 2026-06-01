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
  imports = [ ./options.nix ];

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
    # SYSTEMD PATH UNIT — fast-path reindex trigger on top-level vault changes
    # systemd.path PathChanged= does NOT recurse: inotify on a directory only
    # fires for its immediate entries, not subdirectories. So this catches
    # edits to files directly in cfg.vaultPath (e.g. MEMORY.md, .gitignore)
    # but misses the common case (writes under wiki/, _llm-inbox/, etc.).
    # The periodic timer below is what actually keeps the index fresh.
    # TriggerLimitIntervalSec collapses bursts of edits into one call/min.
    #========================================================================
    systemd.paths = lib.mkIf (cfg.vaultPath != null) {
      persona-daemon-reindex = {
        description = "Trigger persona-daemon reindex on vault changes";
        wantedBy = [ "multi-user.target" ];
        pathConfig = {
          PathChanged = toString cfg.vaultPath;
          TriggerLimitIntervalSec = "60s";
          TriggerLimitBurst = 1;
        };
      };
    };

    #========================================================================
    # SYSTEMD TIMER — periodic reindex covering subdirectory edits
    # Reindex is incremental: the daemon stats files and only re-embeds
    # those whose mtime changed since the last run. A no-op pass is cheap.
    # 5 minutes is the staleness budget for RAG over the brain vault.
    #========================================================================
    systemd.timers = lib.mkIf (cfg.vaultPath != null) {
      persona-daemon-reindex = {
        description = "Periodic persona-daemon reindex (covers subdir edits PathChanged misses)";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "2min";
          OnUnitActiveSec = "5min";
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
      mode = "port";
      port = cfg.reverseProxyPort;
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
