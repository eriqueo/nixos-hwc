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
        brain-mcp reserves 23443 via default; sr-board reserves 24443).
      '';
    };

    model = {
      provider = lib.mkOption {
        type = lib.types.enum [ "anthropic" "openai" "nous-portal" "openrouter" ];
        default = "anthropic";
        description = ''
          LLM provider Hermes drives by default. "anthropic" reuses the existing
          nanoclaw-anthropic-key.age secret. The Claude Code CLI subscription
          CANNOT be used here — Hermes only speaks OpenAI-style HTTP APIs.
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
