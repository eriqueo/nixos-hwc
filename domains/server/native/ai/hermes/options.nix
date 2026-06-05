# domains/server/native/ai/hermes/options.nix
#
# Hermes Agent options — Nous Research's self-improving AI agent.
# Namespace: hwc.server.ai.hermes (the `native/` path segment is grouping-only).
#
# Deployment model (2026-06-03): the OFFICIAL `nousresearch/hermes-agent`
# Podman container. The image bundles Python + Node + the prebuilt dashboard
# and supervises the gateway + dashboard together under s6 in one writable
# $HOME — the cohesive environment the app is designed for. This replaced the
# bespoke native-systemd deployment, which fragmented the app across three
# hardened units with split environments and broke the in-app controls
# (chat tab, gateway restart) that the dashboard assumes it owns.
#
# Upstream: https://github.com/NousResearch/hermes-agent
{ lib, config, ... }:
let
  paths = config.hwc.paths;
in
{
  options.hwc.server.ai.hermes = {
    enable = lib.mkEnableOption "Hermes Agent (official Podman container, Discord + dashboard)";

    image = lib.mkOption {
      type = lib.types.str;
      default = "docker.io/nousresearch/hermes-agent:latest";
      description = "OCI image for the Hermes Agent container.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.state}/hermes-agent";
      description = ''
        Host directory bind-mounted to the container's /opt/data volume.
        Holds .env, config.yaml, sessions/, memories/, skills/, logs/.
        A fresh path (not the old native /var/lib/hwc/hermes tree) because the
        container expects the upstream /opt/data layout, not the installer's
        $HOME/.hermes layout.
      '';
    };

    dashboardPort = lib.mkOption {
      type = lib.types.port;
      default = 9119;
      description = "Host loopback port published to the container's dashboard (container-side 9119).";
    };

    reverseProxyPort = lib.mkOption {
      type = lib.types.port;
      default = 25443;
      description = "External Caddy HTTPS port for the Hermes dashboard.";
    };

    dashboard = {
      tui = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Expose the in-browser Chat tab (HERMES_DASHBOARD_TUI=1).";
      };

      insecure = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Disable the dashboard's Nous-Portal OAuth gate (HERMES_DASHBOARD_INSECURE=1).
          Safe here because the dashboard is only reachable over the trusted
          tailnet behind Caddy, never the public internet. Set false to require
          OAuth login.
        '';
      };
    };

    model = {
      provider = lib.mkOption {
        type = lib.types.str;
        default = "deepseek";
        description = ''
          Hermes inference provider id (see PROVIDER_REGISTRY in
          hermes_cli/auth.py). `deepseek` has its base URL built in and reads
          the key from DEEPSEEK_API_KEY. Written to config.yaml `model.provider`.
        '';
      };

      modelName = lib.mkOption {
        type = lib.types.str;
        default = "deepseek-v4-pro";
        description = "Bare model id written to config.yaml `model.default`.";
      };

      baseUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://api.deepseek.com/v1";
        description = ''
          Inference base URL written to config.yaml `model.base_url`. The
          image's first-boot setup hard-codes this to OpenRouter, which forces
          ALL inference through OpenRouter regardless of provider — so we must
          override it to the provider's real endpoint.
        '';
      };

      keyEnvVar = lib.mkOption {
        type = lib.types.str;
        default = "DEEPSEEK_API_KEY";
        description = "Env var name the provider reads its API key from.";
      };

      keyFileSecret = lib.mkOption {
        type = lib.types.str;
        default = "hermes-deepseek-key";
        description = ''
          agenix secret NAME holding the model API key. Injected under
          `keyEnvVar` via a runtime-generated env file (never the Nix store).
        '';
      };
    };

    gateway = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Run the gateway (the container's `gateway run` command).";
      };

      discord = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable Discord. Requires the hermes-discord-bot-token.age secret.";
        };

        tokenSecret = lib.mkOption {
          type = lib.types.str;
          default = "hermes-discord-bot-token";
          description = "agenix secret NAME for the Discord bot token (DISCORD_BOT_TOKEN).";
        };

        allowedUsers = lib.mkOption {
          type = lib.types.str;
          default = "";
          example = "1501391621521150075";
          description = "Comma-separated Discord user-ID allowlist (DISCORD_ALLOWED_USERS).";
        };
      };
    };

    marketDashboard = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Static read-only dashboard for the paper-trading trials: Caddy
          file_server over a directory holding index.html + a data.json that a
          host timer regenerates from each book's ledger. Independent of the
          agent — it only views the engine's state.
        '';
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 25444;
        description = "External Caddy HTTPS port for the market-trials dashboard.";
      };

      dir = lib.mkOption {
        type = lib.types.path;
        default = "${paths.state}/market-dashboard";
        description = "Directory Caddy serves (index.html + generated data.json).";
      };

      refresh = lib.mkOption {
        type = lib.types.str;
        default = "*:0/15";
        description = "systemd OnCalendar for the data.json refresh aggregator.";
      };
    };
  };
}
