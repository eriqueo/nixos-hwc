# domains/server/native/ai/hermes/options.nix
#
# Hermes Agent options — Nous Research's self-improving AI agent
# Namespace: hwc.server.ai.hermes (matches folder: domains/server/native/ai/hermes/)
#
# Upstream: https://github.com/NousResearch/hermes-agent (successor to OpenClaw/NanoClaw)
{ lib, config, ... }:
let
  paths = config.hwc.paths;
in
{
  options.hwc.server.ai.hermes = {
    enable = lib.mkEnableOption "Hermes Agent (native systemd, Discord gateway)";

    user = lib.mkOption {
      type = lib.types.str;
      default = "eric";
      description = "User to run the Hermes Agent service as.";
    };

    homeDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.state}/hermes";
      description = ''
        Hermes Agent $HOME equivalent — upstream installer puts code at
        $HOME/.hermes/hermes-agent/, binary at $HOME/.local/bin/hermes, and
        data at $HOME/.hermes/. We unify everything under StateDirectory
        (/var/lib/hwc/hermes by default) since upstream doesn't split
        install tree from state.
      '';
    };

    dashboardPort = lib.mkOption {
      type = lib.types.port;
      default = 9119;
      description = ''
        Loopback port the `hermes dashboard` daemon listens on.
        9119 is the upstream default (see `hermes dashboard --help`).
      '';
    };

    dashboard = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Run `hermes dashboard` as a long-lived systemd service so the
          web UI is always reachable via the Caddy reverse-proxy route.
          The dashboard exposes config, sessions, skills, cron, and a
          browser-based chat pane (via PTY+WebSocket when --tui is on).
        '';
      };

      tui = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Expose the in-browser Chat tab (embedded `hermes --tui` over PTY/WebSocket).";
      };
    };

    reverseProxyPort = lib.mkOption {
      type = lib.types.port;
      default = 25443;
      description = ''
        External Caddy HTTPS port for the Hermes dashboard.
        Verified free against the active Caddy config (highest in-use: 22443;
        brain-mcp reserves 23443 via default; sr_analyzer reserves 24443).
      '';
    };

    model = {
      provider = lib.mkOption {
        # Subset of Hermes' upstream PROVIDER_REGISTRY (see
        # hermes_cli/auth.py). Add new entries here only after verifying
        # the canonical id matches what Hermes' config.yaml accepts.
        type = lib.types.enum [ "anthropic" "openai-api" "lmstudio" "nous" "openrouter" ];
        default = "anthropic";
        description = ''
          LLM provider Hermes drives. `anthropic` reuses the existing
          nanoclaw-anthropic-key.age secret (subject to Anthropic's
          third-party-app extra-usage billing). `openai-api` is the generic
          OpenAI-compatible client — combine with `baseUrl` to point at a
          local llama.cpp/Ollama/vLLM endpoint. `lmstudio` is identical in
          behaviour but the registry default URL is loopback :1234.
        '';
      };

      keyFileSecret = lib.mkOption {
        type = lib.types.str;
        default = "hermes-anthropic-key";
        description = ''
          agenix secret NAME containing the model provider API key.
          Default points at the existing nanoclaw-anthropic-key.age file via a
          re-named logical secret (see secrets/declarations/services.nix).
        '';
      };

      useApiKey = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether this endpoint is a REMOTE OpenAI-compatible API that
          authenticates with a real key (DeepSeek, OpenAI, OpenRouter), as
          opposed to a LOCAL no-auth endpoint (llama.cpp/Ollama/vLLM).

          When true: the `keyFileSecret` agenix secret is declared and its
          contents are injected as OPENAI_API_KEY into the gateway and
          dashboard services at start. When false with a `baseUrl` set, the
          endpoint is treated as local and gets the `sk-local-noauth`
          placeholder instead (the openai SDK still emits an Authorization
          header even when the local server ignores it).

          Has no effect for `provider = "anthropic"`, which uses the symlinked
          Claude Code credentials path rather than an API key file.
        '';
      };

      baseUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "http://127.0.0.1:11501/v1";
        description = ''
          Override the model API base URL. null = use the provider's canonical
          URL (api.anthropic.com, api.openai.com/v1, etc.). Set this to point
          at a local llama.cpp / Ollama / vLLM OpenAI-compat endpoint so
          Hermes' chat brain runs against on-host inference.
        '';
      };

      modelName = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "lfm2-24b";
        description = ''
          Override the default model name (config.yaml `model.default`).
          null = leave whatever upstream's setup wizard picked. Required
          when pointing at a local endpoint: llama.cpp expects the value
          set via `--alias`; Ollama expects the tag name (e.g. "llama3.2:3b").
        '';
      };
    };

    gateway = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Run the long-lived `hermes gateway` daemon for messaging platforms.";
      };

      discord = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Enable Discord gateway. Requires the hermes-discord-bot-token.age
            secret to exist. Off by default until Eric creates the bot at the
            Discord Developer Portal and encrypts the token.
          '';
        };

        tokenSecret = lib.mkOption {
          type = lib.types.str;
          default = "hermes-discord-bot-token";
          description = ''
            agenix secret NAME containing the Discord bot token (Gateway intents
            required: MESSAGE CONTENT + SERVER MEMBERS).
          '';
        };
      };
    };
  };
}
