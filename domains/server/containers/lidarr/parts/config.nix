# Lidarr container configuration
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.containers.lidarr;
  arrConfig = import ../../_shared/arr-config.nix { inherit lib pkgs; };
  appsRoot = config.hwc.paths.apps.root;
  configPath = "${appsRoot}/lidarr/config";
  enforceScript = arrConfig.mkArrConfigScript {
    name = "lidarr";
    inherit configPath;
    urlBase = "/lidarr";
  };
in
{
  config = lib.mkIf cfg.enable {
    # Service dependencies
    systemd.services."podman-lidarr".after = [ "network-online.target" "init-media-network.service" "agenix.service" "mnt-hot.mount" ];
    systemd.services."podman-lidarr".wants = [ "network-online.target" "agenix.service" ];
    systemd.services."podman-lidarr".requires = [ "mnt-hot.mount" ];

    # Enforce correct config.xml settings before container starts
    systemd.services."podman-lidarr".serviceConfig.ExecStartPre = [
      "+${enforceScript}"  # + prefix runs as root
    ];
  };
}
