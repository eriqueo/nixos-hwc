{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.containers.jellyseerr;
  appsRoot = config.hwc.paths.apps.root;
  configPath = "${appsRoot}/jellyseerr/config";
  settings = import ./settings.nix { inherit config pkgs; };

  # Jellyseerr permission flags (bitmask)
  # REQUEST = 2, AUTO_APPROVE = 4, REQUEST_MOVIE = 8, AUTO_APPROVE_MOVIE = 16,
  # REQUEST_4K = 32, REQUEST_TV = 64, AUTO_APPROVE_TV = 128, REQUEST_4K_TV = 256
  # For auto-approval: REQUEST (2) + AUTO_APPROVE (4) + REQUEST_MOVIE (8) + AUTO_APPROVE_MOVIE (16) + REQUEST_TV (64) + AUTO_APPROVE_TV (128) = 222
in
{
  config = lib.mkIf cfg.enable {
    # Create settings.json in the container's config directory
    systemd.tmpfiles.rules = [
      "d ${configPath} 0755 1000 100 -"
      # Use C+ to copy file content (overwrite to keep in sync)
      "C+ ${configPath}/settings.json 0644 1000 100 - ${settings.settingsFile}"
    ];

    systemd.services."podman-jellyseerr".after = [ "network-online.target" "init-media-network.service" ];
    systemd.services."podman-jellyseerr".wants = [ "network-online.target" ];
  };
}
