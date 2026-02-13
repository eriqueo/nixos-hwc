# Readarr container configuration
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.containers.readarr;
  arrConfig = import ../../_shared/arr-config.nix { inherit lib pkgs; };
  appsRoot = config.hwc.paths.apps.root;
  configPath = "${appsRoot}/readarr/config";
  enforceScript = arrConfig.mkArrConfigScript {
    name = "readarr";
    inherit configPath;
    urlBase = "/readarr";
  };
in
{
  config = lib.mkIf cfg.enable {
    # Service dependencies
    systemd.services."podman-readarr".after = [ "network-online.target" "init-media-network.service" "agenix.service" "mnt-hot.mount" ];
    systemd.services."podman-readarr".wants = [ "network-online.target" "agenix.service" ];
    systemd.services."podman-readarr".requires = [ "mnt-hot.mount" ];

    # Enforce correct config.xml settings before container starts
    systemd.services."podman-readarr".serviceConfig.ExecStartPre = [
      "+${enforceScript}"  # + prefix runs as root
    ];
  };
}
