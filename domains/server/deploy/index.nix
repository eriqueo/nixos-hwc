# domains/server/deploy/index.nix
#
# `deploy` — interactive one-step deploy CLI for run-in-place server apps.
#
# NAMESPACE: hwc.server.deploy.*
#
# WHAT IT DOES:
#   `deploy`         → fzf picker, auto-populated from apps under appsDir that
#                      carry an executable recipe file (default deploy.sh).
#   `deploy <app>`   → run that app's recipe directly (non-interactive).
#
# The dispatcher is deliberately dumb: it discovers + picks + execs. The actual
# deploy logic lives WITH each app as `<repo>/deploy.sh` (late binding — adding a
# deployable app is just dropping a deploy.sh in its repo, no Nix edit). The
# toolchain apps need (node/npm, git, sudo+systemctl, podman-compose) is provided
# here via runtimeInputs so every exec'd recipe inherits a reliable PATH.

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.server.deploy;
in
{
  options.hwc.server.deploy = {
    enable = lib.mkEnableOption "interactive `deploy` CLI running per-app deploy.sh recipes discovered under appsDir";

    appsDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.hwc.paths.user.home}/600_apps";
      description = "Directory scanned for deployable app repos (each must contain an executable recipe).";
    };

    recipe = lib.mkOption {
      type = lib.types.str;
      default = "deploy.sh";
      description = "Recipe filename an app repo must contain (and be executable) to be deployable.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "deploy";
        # Toolchain inherited by exec'd recipes (they run in this augmented PATH).
        runtimeInputs = [
          pkgs.fzf pkgs.coreutils pkgs.findutils pkgs.gnugrep pkgs.bash
          pkgs.git pkgs.nodejs pkgs.sudo pkgs.systemd pkgs.podman-compose
        ];
        text = ''
          set -euo pipefail
          APPS_DIR="${cfg.appsDir}"
          RECIPE="${cfg.recipe}"

          if [ ! -d "$APPS_DIR" ]; then
            echo "deploy: apps dir not found: $APPS_DIR" >&2; exit 1
          fi

          # Auto-populate: app repos under APPS_DIR carrying the recipe file.
          mapfile -t apps < <(
            find "$APPS_DIR" -mindepth 2 -maxdepth 2 -type f -name "$RECIPE" \
              -printf '%h\n' | xargs -r -n1 basename | sort
          )

          if [ "''${#apps[@]}" -eq 0 ]; then
            echo "deploy: nothing deployable (no $APPS_DIR/*/$RECIPE found)" >&2
            exit 1
          fi

          if [ "$#" -ge 1 ]; then
            choice="$1"
          else
            choice="$(printf '%s\n' "''${apps[@]}" \
              | fzf --prompt='deploy ❯ ' --height=40% --reverse --no-multi \
                    --header='pick an app to deploy')" || exit 0
          fi

          recipe="$APPS_DIR/$choice/$RECIPE"
          if [ ! -e "$recipe" ]; then
            echo "deploy: unknown app '$choice' (no $recipe)" >&2; exit 1
          fi
          if [ ! -x "$recipe" ]; then
            echo "deploy: $recipe is not executable (run: chmod +x \"$recipe\")" >&2; exit 1
          fi

          echo "deploy: ▶ $choice"
          cd "$APPS_DIR/$choice"
          exec "$recipe"
        '';
      })
    ];
  };
}
