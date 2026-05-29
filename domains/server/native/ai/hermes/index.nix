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
        ${./parts/bootstrap/cli.ts} "$@"
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
      "${hermesBin}" config set model.api_key_file "/run/agenix/${cfg.model.keyFileSecret}" || true

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
      # hermes-deploy on PATH for manual ops
      environment.systemPackages = [ hermes-deploy ];

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
          HERMES_DISCORD_BOT_TOKEN_FILE = "/run/agenix/${cfg.gateway.discord.tokenSecret}";
          PATH = lib.mkForce "/run/current-system/sw/bin:/etc/profiles/per-user/${cfg.user}/bin";
        };

        serviceConfig = {
          Type = "simple";
          User = lib.mkForce cfg.user;
          Group = "users";
          StateDirectory = "hwc/hermes";
          StateDirectoryMode = "0750";
          WorkingDirectory = cfg.homeDir;
          ExecStart = "${hermesBin} gateway --discord";
          Restart = "on-failure";
          RestartSec = "10s";

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
    (lib.mkIf cfg.enable {
      hwc.networking.shared.routes = [{
        name = "hermes";
        mode = "port";
        port = cfg.reverseProxyPort;
        upstream = "http://127.0.0.1:${toString cfg.dashboardPort}";
      }];
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
