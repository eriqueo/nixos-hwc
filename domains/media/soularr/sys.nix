{ lib, config, pkgs, ... }:
let
  # Import PURE helper library - no circular dependencies
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  cfg = config.hwc.media.soularr;
  appsRoot = config.hwc.paths.apps.root;
  soularrRoot = "${appsRoot}/soularr";
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    # Container definition using helper
    (helpers.mkContainer {
      name = "soularr";
      image = cfg.image;
      networkMode = cfg.network.mode;
      gpuEnable = false;  # soularr doesn't need GPU
      timeZone = config.time.timeZone or "UTC";
      ports = [];  # No web UI, internal only
      volumes = [
        "${soularrRoot}/config:/config"
        "${soularrRoot}/data:/data"
        "${config.hwc.paths.hot.downloads}:/downloads"
      ];
      environment = {};
      extraOptions = [ "--memory=1g" "--cpus=0.5" ];
      dependsOn = [ "lidarr" "slskd" ];
    })

    # Service dependencies and wait script
    {
      systemd.services."podman-soularr" = {
        after = [ "init-media-network.service" "podman-lidarr.service" "podman-slskd.service" "soularr-config.service" ];
        requires = [ "podman-lidarr.service" "soularr-config.service" ];
        restartTriggers = [ config.systemd.services.soularr-config.serviceConfig.ExecStart ]
          ++ config.systemd.services.soularr-config.restartTriggers;
        serviceConfig.ExecStartPre = pkgs.writeShellScript "wait-for-lidarr" ''
          set -euo pipefail
          # Six attempts, each GET at most two seconds; jitter below one second.
          # An anonymous FD keeps the key out of argv and persistent header files.
          for ((attempt = 1; attempt <= 6; attempt++)); do
            if ${pkgs.curl}/bin/curl --fail --silent --connect-timeout 1 --max-time 2 \
              --header @<(printf 'X-Api-Key: '; ${pkgs.coreutils}/bin/cat ${lib.escapeShellArg config.age.secrets.lidarr-api-key.path}; printf '\n') \
              "http://localhost:8686/api/v1/system/status" >/dev/null 2>&1; then
              echo "Lidarr is ready"
              exit 0
            fi
            if ((attempt < 6)); then
              ${pkgs.coreutils}/bin/sleep "0.$((500 + RANDOM % 500))"
            fi
          done
          echo "Lidarr failed to become ready"
          exit 1
        '';
        serviceConfig.TimeoutStartSec = lib.mkForce "30s";
      };
    }
  ]);
}
