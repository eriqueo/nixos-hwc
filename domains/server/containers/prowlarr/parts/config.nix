# Prowlarr container configuration
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.containers.prowlarr;
  arrConfig = import ../../_shared/arr-config.nix { inherit lib pkgs; };
  configPath = "${config.hwc.paths.hot.downloads}/prowlarr";
  enforceScript = arrConfig.mkArrConfigScript {
    name = "prowlarr";
    inherit configPath;
    urlBase = "/prowlarr";
  };
in
{
  config = lib.mkIf cfg.enable {
    # Service dependencies
    systemd.services."podman-prowlarr".after = [ "network-online.target" "init-media-network.service" ];
    systemd.services."podman-prowlarr".wants = [ "network-online.target" ];

    # Enforce correct config.xml settings before container starts
    systemd.services."podman-prowlarr".serviceConfig.ExecStartPre = [
      "+${enforceScript}"  # + prefix runs as root
    ];
  };
}
