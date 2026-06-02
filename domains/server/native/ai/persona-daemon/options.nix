# domains/server/native/ai/persona-daemon/options.nix
#
# Persona-aware OpenAI-compatible HTTP daemon + SQLite conversation memory.
# Wraps the three llama-cpp services and exposes one unified API surface.
#
# Namespace: hwc.server.ai.personaDaemon (folder → namespace).
{ lib, config, ... }:
let
  paths = config.hwc.paths;
  llamaCpp = config.hwc.server.ai.llamaCpp;
in
{
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
}
