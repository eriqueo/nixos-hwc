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
  imports = [ ./options.nix ];

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

    # ── agenix secrets ──────────────────────────────────────────────────────
    {
      age.secrets = lib.mkMerge [
        {
          "${cfg.model.keyFileSecret}" = {
            file = ../../../../secrets/parts/services/hermes-deepseek-key.age;
            mode = "0440";
            owner = "root";
            group = "secrets";
          };
        }
        (lib.mkIf cfg.gateway.discord.enable {
          "${cfg.gateway.discord.tokenSecret}" = {
            file = ../../../../secrets/parts/services/hermes-discord-bot-token.age;
            mode = "0440";
            owner = "root";
            group = "secrets";
          };
        })
      ];

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
        mode = "port";
        port = cfg.reverseProxyPort;
        upstream = "http://127.0.0.1:${toString cfg.dashboardPort}";
        headers = { Host = "127.0.0.1"; };
      }];
    }

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
