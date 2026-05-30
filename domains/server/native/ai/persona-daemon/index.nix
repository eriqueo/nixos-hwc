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
