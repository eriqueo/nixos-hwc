# domains/server/native/ai/hermes/index.nix
#
# Hermes Agent — official `nousresearch/hermes-agent` Podman container.
#
# One container, `gateway run`, with HERMES_DASHBOARD=1 so s6-overlay supervises
# the gateway AND the dashboard together in one writable $HOME (/opt/data). The
# model (DeepSeek V4) and Discord are wired purely through environment:
#   - OPENAI_BASE_URL / HERMES_MODEL  (non-secret) → container `environment`
#   - OPENAI_API_KEY / DISCORD_BOT_TOKEN (secret)  → runtime-generated env file
#     composed from /run/agenix in the <name>-setup preStart (never the Nix store)
#
# Secrets pattern mirrors domains/networking/pihole (mkInfraContainer +
# preStartScript + preStartDeps = [ "agenix.service" ]).
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.server.ai.hermes;
  paths = config.hwc.paths;

  infra = import ../../../../lib/mkInfraContainer.nix { inherit lib pkgs; };

  envFile = "${cfg.dataDir}/.env";


  # Non-secret environment. Secrets are added at runtime via envFile.
  containerEnv = {
    HERMES_DASHBOARD = "1";
    HERMES_DASHBOARD_HOST = "0.0.0.0";
    HERMES_DASHBOARD_PORT = "9119";
    PUID = "1000";
    PGID = "100";
    HERMES_UID = "1000";
    HERMES_GID = "100";
    TZ = "America/Denver";
  }
  // lib.optionalAttrs cfg.dashboard.tui { HERMES_DASHBOARD_TUI = "1"; }
  // lib.optionalAttrs cfg.dashboard.insecure { HERMES_DASHBOARD_INSECURE = "1"; }
  // lib.optionalAttrs (cfg.gateway.discord.enable && cfg.gateway.discord.allowedUsers != "") {
    DISCORD_ALLOWED_USERS = cfg.gateway.discord.allowedUsers;
  };

  # Compose the secret env file from agenix-decrypted secrets. $(cat) strips any
  # trailing newline so the values stay header-clean. The DeepSeek provider
  # reads its key from DEEPSEEK_API_KEY (cfg.model.keyEnvVar).
  preStartScript = ''
    mkdir -p ${cfg.dataDir}
    umask 077
    {
      echo "${cfg.model.keyEnvVar}=$(cat /run/agenix/${cfg.model.keyFileSecret})"
      ${lib.optionalString cfg.gateway.discord.enable ''
        echo "DISCORD_BOT_TOKEN=$(cat /run/agenix/${cfg.gateway.discord.tokenSecret})"
      ''}
    } > ${envFile}
    chmod 600 ${envFile}
  '';

  # The image's first-boot `setup` writes config.yaml with a default model
  # (anthropic/claude-opus-4.6), provider=auto, AND base_url=openrouter.ai —
  # the last of which forces all inference through OpenRouter regardless of
  # provider. None of these is overridable by env, so pin all three in the
  # persistent config.yaml once the CLI is reachable. Idempotent.
  postStartScript = ''
    for _ in $(seq 1 30); do
      ${pkgs.podman}/bin/podman exec hermes hermes config get model.default >/dev/null 2>&1 && break
      sleep 2
    done
    ${pkgs.podman}/bin/podman exec hermes hermes config set model.provider ${cfg.model.provider} || true
    ${pkgs.podman}/bin/podman exec hermes hermes config set model.default ${cfg.model.modelName} || true
    ${pkgs.podman}/bin/podman exec hermes hermes config set model.base_url ${cfg.model.baseUrl} || true
  '';
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
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

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable (lib.mkMerge [

    # ── The Hermes container (gateway + supervised dashboard) ───────────────
    (infra.mkInfraContainer {
      name = "hermes";
      image = cfg.image;
      networkMode = "media-network";

      cmd = [ "gateway" "run" ];

      # Dashboard published to host loopback only; Caddy fronts it.
      ports = [ "127.0.0.1:${toString cfg.dashboardPort}:9119" ];

      volumes = [ "${cfg.dataDir}:/opt/data" ];

      environment = containerEnv;
      environmentFiles = [ envFile ];

      # Image bundles Playwright/Chromium; give it headroom.
      memory = "4g";
      cpus = "2.0";
      memorySwap = "6g";

      preStartScript = preStartScript;
      preStartDeps = [ "agenix.service" ];
      postStartScript = postStartScript;
    })

    # ── runtime state dir ────────────────────────────────────────────────────
    # The hermes-deepseek-key + hermes-discord-bot-token secrets are now mounted
    # by the generated secrets layer (domains/secrets/declarations/generated.nix)
    # from parts/services/*.age — no inline age.secrets here.
    {
      # State dir for the /opt/data volume, owned by eric:users (PUID/PGID).
      systemd.tmpfiles.rules = [
        "d ${cfg.dataDir} 0750 eric users - -"
      ];
    }

    # ── Caddy reverse proxy (port-mode) ──────────────────────────────────────
    # Host header rewrite to 127.0.0.1 satisfies the dashboard's DNS-rebinding
    # defense (GHSA-ppp5-vxwm-4cf7) while Caddy stays on the public hostname.
    {
      hwc.networking.shared.routes = [{
        name = "hermes";
        mode = "vhost";
        upstream = "http://127.0.0.1:${toString cfg.dashboardPort}";
        headers = { Host = "127.0.0.1"; };
      }];
    }

    # ── Market-trials dashboard (static file_server + host refresh timer) ────
    # Read-only view: a host timer regenerates data.json from each book's ledger
    # (marking to live quotes); Caddy serves the directory over the tailnet.
    # Independent of the Hermes container — it never writes to the books.
    (lib.mkIf cfg.marketDashboard.enable {
      hwc.networking.shared.routes = [{
        name = "market-dashboard";
        mode = "vhost";
        root = cfg.marketDashboard.dir;
      }];

      systemd.tmpfiles.rules = [
        "d ${cfg.marketDashboard.dir} 0755 eric users - -"
      ];

      systemd.services.hwc-market-dashboard = {
        description = "Build market-trials dashboard data.json from the ledgers";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          User = lib.mkForce "eric";
          Group = "users";
          ExecStart = "${pkgs.python3}/bin/python3 ${cfg.dataDir}/scripts/dashboard_build.py";
          Environment = [
            "HERMES_BASE=${cfg.dataDir}"
            "DASHBOARD_OUT=${cfg.marketDashboard.dir}/data.json"
          ];
        };
      };

      systemd.timers.hwc-market-dashboard = {
        description = "Refresh market-trials dashboard data";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "2min";
          OnCalendar = cfg.marketDashboard.refresh;
          Persistent = true;
        };
      };
    })

    # ── VALIDATION ────────────────────────────────────────────────────────────
    {
      assertions = [
        {
          assertion = config.virtualisation.oci-containers.backend == "podman";
          message = "Hermes Agent requires Podman as the OCI container backend.";
        }
        {
          assertion = builtins.pathExists ../../../../secrets/parts/services/hermes-deepseek-key.age;
          message = "hwc.server.ai.hermes: domains/secrets/parts/services/hermes-deepseek-key.age is missing.";
        }
        {
          assertion = !cfg.gateway.discord.enable
            || builtins.pathExists ../../../../secrets/parts/services/hermes-discord-bot-token.age;
          message = "hwc.server.ai.hermes.gateway.discord.enable = true but hermes-discord-bot-token.age is missing.";
        }
      ];
    }
  ]);
}
