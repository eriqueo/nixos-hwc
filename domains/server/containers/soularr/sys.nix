{ lib, config, pkgs, ... }:
let
  # Import PURE helper library - no circular dependencies
  helpers = import ../_shared/pure.nix { inherit lib pkgs; };
  cfg = config.hwc.server.containers.soularr;
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
        "${config.hwc.paths.hot.downloads}/soularr:/config"
        "${config.hwc.paths.hot.downloads}/soularr:/data"
        "${config.hwc.paths.hot.downloads}:/downloads"
      ];
      environment = {};
      extraOptions = [ "--memory=1g" "--cpus=0.5" ];
      dependsOn = [ "lidarr" "slskd" ];
    })

    # Service dependencies and wait script
    {
      systemd.services."podman-soularr" = {
        after = [ "init-media-network.service" "podman-lidarr.service" "podman-slskd.service" ];
        requires = [ "podman-lidarr.service" ];
        serviceConfig.ExecStartPre = pkgs.writeShellScript "wait-for-lidarr" ''
          for i in 1 1 2 3 5 8; do
            if ${pkgs.curl}/bin/curl -sf -H "X-Api-Key: $(cat ${config.age.secrets.lidarr-api-key.path})" \
              "http://localhost:8686/lidarr/api/v1/system/status" >/dev/null 2>&1; then
              echo "Lidarr is ready"
              exit 0
            fi
            echo "Waiting for Lidarr... ($i)"
            sleep $i
          done
          echo "Lidarr failed to become ready"
          exit 1
        '';
      };
    }
  ]);
}
