# domains/server/native/ai/hermes/index.nix
#
# Hermes Agent — native systemd deployment of Nous Research's self-improving
# AI agent (https://github.com/NousResearch/hermes-agent).
#
# - Two systemd units:
#     hermes-install.service  (oneshot, sentinel-gated) — runs the upstream
#         curl|bash installer once into $HOME and configures the model provider.
#     hermes-gateway.service  (long-lived) — runs `hermes gateway --discord`
#         when gateway.enable + gateway.discord.enable are both true.
#
# - $HOME is set to homeDir (default /var/lib/hwc/hermes) via systemd
#   StateDirectory so the installer's hardcoded $HOME/.hermes layout lands
#   inside a state dir owned by the service user.
#
# - The `hermes-deploy` CLI (TypeScript, hexagonal — see parts/bootstrap/) is
#   the human entry point for manual install/upgrade/status/doctor.
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.server.ai.hermes;

  hermesBin = "${cfg.homeDir}/.local/bin/hermes";
  installSentinel = "${cfg.homeDir}/.hermes/.installed";

  # TypeScript deploy CLI — runs directly via Node 22's --experimental-strip-types.
  # No npm install, no build step: source lives in parts/bootstrap/, runs in-place.
  #
  # Use sourceFilesBySuffices so cli.ts, core.ts, adapters.ts, types.ts land in
  # the SAME Nix store path. Individual `${./parts/bootstrap/cli.ts}` references
  # would put each .ts file in its own store path, breaking the relative imports
  # between cli.ts → ./adapters.ts → ./types.ts.
  hermes-bootstrap-src = lib.sources.sourceFilesBySuffices ./parts/bootstrap [ ".ts" ];

  # `hermes` shim on system PATH. The upstream binary lives at
  # ${cfg.homeDir}/.local/bin/hermes; the installer normally adds that dir to
  # the user's PATH via ~/.zshrc, but our $HOME is /var/lib/hwc/hermes so those
  # edits land in the wrong shell rc. This shim is the explicit, declarative
  # bridge: any user with /run/current-system/sw/bin in PATH gets `hermes`.
  hermes-shim = pkgs.writeShellApplication {
    name = "hermes";
    runtimeInputs = [ ];
    text = ''
      export HOME="${cfg.homeDir}"
      exec ${hermesBin} "$@"
    '';
  };

  hermes-deploy = pkgs.writeShellApplication {
    name = "hermes-deploy";
    runtimeInputs = [ pkgs.nodejs_22 pkgs.systemd ];
    text = ''
      export HERMES_HOME_DIR="${cfg.homeDir}"
      export HERMES_BIN="${hermesBin}"
      export HERMES_INSTALL_SENTINEL="${installSentinel}"
      export HERMES_MODEL_PROVIDER="${cfg.model.provider}"
      export HERMES_MODEL_KEY_FILE="/run/agenix/${cfg.model.keyFileSecret}"
      exec ${pkgs.nodejs_22}/bin/node \
        --experimental-strip-types \
        --no-warnings \
        ${hermes-bootstrap-src}/cli.ts "$@"
    '';
  };

  # Idempotent installer: skips if sentinel present.
  hermes-installer = pkgs.writeShellApplication {
    name = "hermes-installer";
    runtimeInputs = [ pkgs.curl pkgs.bash pkgs.coreutils pkgs.gnused ];
    text = ''
      set -euo pipefail

      if [ -f "${installSentinel}" ]; then
        echo "[hermes-install] sentinel present at ${installSentinel} — skipping installer"
        exit 0
      fi

      export HOME="${cfg.homeDir}"
      mkdir -p "$HOME/.hermes" "$HOME/.local/bin"

      echo "[hermes-install] running upstream installer"
      # --skip-setup: skip the interactive `hermes setup` wizard
      # --skip-browser: skip Playwright/Chromium (P1000 GPU + headless box)
      curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh \
        | bash -s -- --skip-setup --skip-browser

      echo "[hermes-install] configuring model provider: ${cfg.model.provider}"
      "${hermesBin}" config set model.provider "${cfg.model.provider}" || true
      # Override the upstream-default base_url. Hermes ships with
      # model.base_url = https://openrouter.ai/api/v1 (its multi-provider
      # routing default). When we explicitly choose provider = anthropic
      # the URL must match, or Anthropic-style model IDs get sent to
      # OpenRouter and 404 because OR uses different model name formats.
      "${hermesBin}" config set model.base_url "${
        if cfg.model.provider == "anthropic" then "https://api.anthropic.com"
        else if cfg.model.provider == "openai" then "https://api.openai.com/v1"
        else if cfg.model.provider == "nous-portal" then "https://portal.nousresearch.com/api/v1"
        else "https://openrouter.ai/api/v1"
      }" || true
      # For anthropic provider we DON'T set model.api_key_file. Eric's
      # nanoclaw-anthropic-key.age is a Claude Max subscription-tier API
      # key, but the live auth path is the symlinked Claude Code
      # credentials JSON (see tmpfiles below) which Hermes auto-detects
      # with Bearer auth + token refresh. Setting api_key_file would
      # short-circuit to x-api-key mode and fail with HTTP 401.
      # Also clear any stale ANTHROPIC_API_KEY left in .env by a previous
      # `hermes setup` or manual paste — it's checked first in the
      # lookup chain (ANTHROPIC_API_KEY -> ANTHROPIC_TOKEN ->
      # CLAUDE_CODE_OAUTH_TOKEN) and would override the symlink path.
      "${hermesBin}" config set ANTHROPIC_API_KEY "" || true
      "${hermesBin}" config set ANTHROPIC_TOKEN "" || true

      touch "${installSentinel}"
      echo "[hermes-install] done — sentinel written"
    '';
  };
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  imports = [ ./options.nix ];

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkMerge [

    # ── Common (when enabled) ──────────────────────────────────────────────
    (lib.mkIf cfg.enable {
      # hermes (shim) + hermes-deploy on PATH for manual ops
      environment.systemPackages = [ hermes-shim hermes-deploy ];

      # Symlink Eric's real Claude Code credentials into Hermes's $HOME so the
      # Anthropic adapter's auto-detector finds them. Hermes reads
      # `${HOME}/.claude/.credentials.json` (Path.home() respects HOME env),
      # extracts claudeAiOauth.{accessToken,refreshToken,expiresAt}, and uses
      # Bearer auth. Refreshes write back through the symlink so the personal
      # `claude` CLI sees the same fresh token.
      #
      # The symlink is owned by eric:users; the target file is mode 0600
      # owned by eric, so only the eric service user can read it.
      systemd.tmpfiles.rules = [
        "d ${cfg.homeDir}/.claude 0700 ${cfg.user} users - -"
        "L+ ${cfg.homeDir}/.claude/.credentials.json - - - - /home/${cfg.user}/.claude/.credentials.json"
      ];

      # nix-ld lets the upstream installer's uv-downloaded CPython run on NixOS.
      # Without this, /var/lib/hwc/hermes/.local/share/uv/python/cpython-*/bin/python3.11
      # fails with "Could not start dynamically linked executable" (no /lib64/ld-linux).
      # Library set is the Python-runtime baseline; Hermes's Python deps are pure-Python
      # or wheels that link against standard libs already covered here.
      programs.nix-ld.enable = true;
      programs.nix-ld.libraries = with pkgs; [
        stdenv.cc.cc.lib    # libstdc++
        zlib openssl libffi bzip2 xz
        sqlite              # FTS5 conversation index
        ncurses readline    # TUI
        glib
      ];

      # Reuse the existing nanoclaw-anthropic-key.age file under a hermes-* logical name.
      # Avoids re-encrypting. Same precedent as datax-discord-webhook in lead-scout.
      age.secrets = lib.mkMerge [
        (lib.mkIf (cfg.model.provider == "anthropic") {
          "${cfg.model.keyFileSecret}" = {
            file = ../../../../secrets/parts/services/nanoclaw-anthropic-key.age;
            mode = "0440";
            owner = "root";
            group = "secrets";
          };
        })
        (lib.mkIf cfg.gateway.discord.enable {
          "${cfg.gateway.discord.tokenSecret}" = {
            file = ../../../../secrets/parts/services/hermes-discord-bot-token.age;
            mode = "0440";
            owner = "root";
            group = "secrets";
          };
        })
      ];

      # One-shot install service
      systemd.services.hermes-install = {
        description = "Hermes Agent installer (oneshot, sentinel-gated)";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];

        environment = {
          HOME = cfg.homeDir;
          PATH = lib.mkForce "/run/current-system/sw/bin:/etc/profiles/per-user/${cfg.user}/bin";
        };

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = lib.mkForce cfg.user;
          Group = "users";
          StateDirectory = "hwc/hermes";
          StateDirectoryMode = "0750";
          ExecStart = "${hermes-installer}/bin/hermes-installer";

          # Hardening
          NoNewPrivileges = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
        };
      };
    })

    # ── Gateway daemon ─────────────────────────────────────────────────────
    (lib.mkIf (cfg.enable && cfg.gateway.enable && cfg.gateway.discord.enable) {
      systemd.services.hermes-gateway = {
        description = "Hermes Agent Gateway (Discord)";
        after = [ "network-online.target" "hermes-install.service" ];
        wants = [ "network-online.target" ];
        requires = [ "hermes-install.service" ];
        wantedBy = [ "multi-user.target" ];

        environment = {
          HOME = cfg.homeDir;
          PATH = lib.mkForce "/run/current-system/sw/bin:/etc/profiles/per-user/${cfg.user}/bin";
        };

        serviceConfig = {
          Type = "simple";
          User = lib.mkForce cfg.user;
          Group = "users";
          SupplementaryGroups = [ "secrets" ];
          StateDirectory = "hwc/hermes";
          StateDirectoryMode = "0750";
          WorkingDirectory = cfg.homeDir;
          # Hermes reads DISCORD_BOT_TOKEN directly from env (see upstream
          # gateway/config.py — `os.getenv("DISCORD_BOT_TOKEN")`), so we
          # source the secret file into the env right before exec. The
          # `gateway run --replace` form replaces any orphan gateway
          # instance left from a prior `hermes gateway restart`.
          ExecStart = pkgs.writeShellScript "hermes-gateway-start" ''
            set -eu
            DISCORD_BOT_TOKEN="$(cat /run/agenix/${cfg.gateway.discord.tokenSecret})"
            export DISCORD_BOT_TOKEN
            exec ${hermesBin} gateway run --replace
          '';
          Restart = "on-failure";
          RestartSec = "10s";
          # Must be >= agent.restart_drain_timeout (180s) + safety margin,
          # or systemd SIGKILLs the gateway mid-drain. Hermes warns
          # "TimeoutStopSec=90s but drain_timeout=180s (expected >=210s)".
          TimeoutStopSec = "240s";

          # Hardening
          NoNewPrivileges = true;
          PrivateTmp = true;
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

          ReadWritePaths = [ cfg.homeDir "/tmp" ];
        };
      };
    })

    # ── Caddy reverse proxy (port-mode) ────────────────────────────────────
    # Host header rewrite is mandatory: Hermes dashboard has an explicit
    # DNS-rebinding defense (GHSA-ppp5-vxwm-4cf7) that 400s any request
    # whose Host header doesn't match the bound interface. Forcing
    # Host: 127.0.0.1 satisfies the check while keeping Caddy on a
    # public-facing hostname.
    (lib.mkIf cfg.enable {
      hwc.networking.shared.routes = [{
        name = "hermes";
        mode = "port";
        port = cfg.reverseProxyPort;
        upstream = "http://127.0.0.1:${toString cfg.dashboardPort}";
        headers = { Host = "127.0.0.1"; };
      }];
    })

    # ── Dashboard daemon (long-lived) ──────────────────────────────────────
    # `hermes dashboard` is a separate process from `hermes chat`. Without
    # this service the Caddy upstream at :9119 has nothing to forward to,
    # producing 502 Bad Gateway on hermes.holthome.net.
    (lib.mkIf (cfg.enable && cfg.dashboard.enable) {
      systemd.services.hermes-dashboard = {
        description = "Hermes Agent web dashboard";
        after = [ "network-online.target" "hermes-install.service" ];
        wants = [ "network-online.target" ];
        requires = [ "hermes-install.service" ];
        wantedBy = [ "multi-user.target" ];

        environment = {
          HOME = cfg.homeDir;
          # nodejs_22 first so the dashboard's one-time `npm run build` can find
          # node/npm. After the initial build the dist persists in
          # ${cfg.homeDir}/.hermes/hermes-agent/hermes_cli/web_dist and Hermes
          # skips the build step on subsequent starts automatically.
          PATH = lib.mkForce "${pkgs.nodejs_22}/bin:/run/current-system/sw/bin:/etc/profiles/per-user/${cfg.user}/bin";
        };

        path = [ pkgs.nodejs_22 ];

        serviceConfig = {
          Type = "simple";
          User = lib.mkForce cfg.user;
          Group = "users";
          StateDirectory = "hwc/hermes";
          StateDirectoryMode = "0750";
          WorkingDirectory = cfg.homeDir;
          ExecStart = lib.concatStringsSep " " ([
            hermesBin "dashboard"
            "--host" "127.0.0.1"
            "--port" (toString cfg.dashboardPort)
            "--no-open"
          ] ++ lib.optional cfg.dashboard.tui "--tui");
          # First start may take ~60s while it npm-installs and builds the
          # SvelteKit dashboard dist. Don't let systemd time it out.
          TimeoutStartSec = "5min";
          # Must be >= agent.restart_drain_timeout (180s) + safety margin,
          # else systemd SIGKILLs the gateway mid-drain. Hermes warns
          # "TimeoutStopSec=90s but drain_timeout=180s (expected >=210s)".
          TimeoutStopSec = "240s";
          Restart = "on-failure";
          RestartSec = "10s";

          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
        };
      };
    })

    # ── VALIDATION ─────────────────────────────────────────────────────────
    {
      assertions = [
        {
          assertion = cfg.gateway.discord.enable -> cfg.gateway.enable;
          message = "hwc.server.ai.hermes.gateway.discord.enable requires hwc.server.ai.hermes.gateway.enable.";
        }
        {
          assertion = cfg.enable -> cfg.user != "root";
          message = "Hermes Agent must run as a non-root user (default: eric).";
        }
        {
          # Discord bot token .age file must exist on disk when gateway is enabled
          assertion = !cfg.gateway.discord.enable
            || builtins.pathExists ../../../../secrets/parts/services/hermes-discord-bot-token.age;
          message = ''
            hwc.server.ai.hermes.gateway.discord.enable = true but
            domains/secrets/parts/services/hermes-discord-bot-token.age is missing.

            Create the Discord bot at https://discord.com/developers/applications
            (enable MESSAGE CONTENT INTENT + SERVER MEMBERS INTENT) and encrypt
            the token:

              echo "$BOT_TOKEN" | age -e -r <server-pubkey> \
                > domains/secrets/parts/services/hermes-discord-bot-token.age
          '';
        }
      ];
    }
  ];
}
