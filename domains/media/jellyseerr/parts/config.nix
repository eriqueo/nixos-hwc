{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.jellyseerr;
  appsRoot = config.hwc.paths.apps.root;
  configPath = "${appsRoot}/jellyseerr/config";

  # Jellyseerr permission flags (bitmask)
  # REQUEST = 2, AUTO_APPROVE = 4, REQUEST_MOVIE = 8, AUTO_APPROVE_MOVIE = 16,
  # REQUEST_4K = 32, REQUEST_TV = 64, AUTO_APPROVE_TV = 128, REQUEST_4K_TV = 256
  # For auto-approval: REQUEST (2) + AUTO_APPROVE (4) + REQUEST_MOVIE (8) + AUTO_APPROVE_MOVIE (16) + REQUEST_TV (64) + AUTO_APPROVE_TV (128) = 222
in
{
  config = lib.mkIf cfg.enable {
    # Create config directory only - settings.json is generated at runtime by setup.nix preStart
    systemd.tmpfiles.rules = [
      "d ${configPath} 0755 1000 100 -"
    ];

    systemd.services."podman-jellyseerr".after = [ "network-online.target" "init-media-network.service" ];
    systemd.services."podman-jellyseerr".wants = [ "network-online.target" ];
  };
}
