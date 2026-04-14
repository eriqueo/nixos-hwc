# Radarr container configuration
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.radarr;
  arrConfig = import ../../../lib/arr-config.nix { inherit lib pkgs; };
  appsRoot = config.hwc.paths.apps.root;
  configPath = "${appsRoot}/radarr/config";
  enforceScript = arrConfig.mkArrConfigScript {
    name = "radarr";
    inherit configPath;
    urlBase = "/radarr";
  };
  webhookScript = arrConfig.mkArrWebhookScript {
    name = "radarr";
    inherit configPath;
    source = "radarr";
  };
in
{
  config = lib.mkIf cfg.enable {
    # Service dependencies
    systemd.services."podman-radarr".after = [ "network-online.target" "init-media-network.service" "agenix.service" "mnt-hot.mount" ];
    systemd.services."podman-radarr".wants = [ "network-online.target" "agenix.service" ];
    systemd.services."podman-radarr".requires = [ "mnt-hot.mount" ];

    # Enforce correct config.xml settings and webhook before container starts
    systemd.services."podman-radarr".serviceConfig.ExecStartPre = [
      "+${enforceScript}"   # + prefix runs as root
      "+${webhookScript}"
    ];
  };
}
