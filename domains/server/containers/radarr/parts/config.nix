# Radarr container configuration
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.containers.radarr;
  arrConfig = import ../../_shared/arr-config.nix { inherit lib pkgs; };
  configPath = "${config.hwc.paths.hot.downloads}/radarr";
  enforceScript = arrConfig.mkArrConfigScript {
    name = "radarr";
    inherit configPath;
    urlBase = "/radarr";
  };
in
{
  config = lib.mkIf cfg.enable {
    # Service dependencies
    systemd.services."podman-radarr".after = [ "network-online.target" "init-media-network.service" "agenix.service" "mnt-hot.mount" ];
    systemd.services."podman-radarr".wants = [ "network-online.target" "agenix.service" ];
    systemd.services."podman-radarr".requires = [ "mnt-hot.mount" ];

    # Enforce correct config.xml settings before container starts
    systemd.services."podman-radarr".serviceConfig.ExecStartPre = [
      "+${enforceScript}"  # + prefix runs as root
    ];
  };
}
