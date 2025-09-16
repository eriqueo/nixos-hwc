{ lib, config, pkgs, ... }:
let
  mediaNetworkName = "media-network";
  podman = "${pkgs.podman}/bin/podman";
in
{
  systemd.services.init-media-network = {
    description = "Create podman media network (idempotent)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail
      if ! ${podman} network ls --format "{{.Name}}" | grep -qx ${mediaNetworkName}; then
        ${podman} network create ${mediaNetworkName}
      else
        echo "${mediaNetworkName} exists"
      fi
    '';
  };

  # Ensure the network is created by the time services start
  systemd.targets.multi-user.wants = [ "init-media-network.service" ];
}
