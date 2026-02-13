# Sonarr container configuration
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.containers.sonarr;
  arrConfig = import ../../_shared/arr-config.nix { inherit lib pkgs; };
  appsRoot = config.hwc.paths.apps.root;
  configPath = "${appsRoot}/sonarr/config";
  enforceScript = arrConfig.mkArrConfigScript {
    name = "sonarr";
    inherit configPath;
    urlBase = "/sonarr";
  };
in
{
  config = lib.mkIf cfg.enable {
    # Service dependencies
    systemd.services."podman-sonarr".after = [ "network-online.target" "init-media-network.service" "agenix.service" "mnt-hot.mount" ];
    systemd.services."podman-sonarr".wants = [ "network-online.target" "agenix.service" ];
    systemd.services."podman-sonarr".requires = [ "mnt-hot.mount" ];

    # Enforce correct config.xml settings before container starts
    systemd.services."podman-sonarr".serviceConfig.ExecStartPre = [
      "+${enforceScript}"  # + prefix runs as root
    ];
  };
}
