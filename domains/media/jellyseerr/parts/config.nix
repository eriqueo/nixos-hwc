{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.jellyseerr;
  appsRoot = config.hwc.paths.apps.root;
  configPath = "${appsRoot}/jellyseerr/config";


in
{
  config = lib.mkIf cfg.enable {
    # Create config directory only - settings.json is generated at runtime by setup.nix preStart
    systemd.tmpfiles.rules = [
      "d ${configPath} 0700 1000 100 -"
    ];

    systemd.services."podman-jellyseerr".after = [ "network-online.target" "init-media-network.service" ];
    systemd.services."podman-jellyseerr".wants = [ "network-online.target" ];
  };
}
