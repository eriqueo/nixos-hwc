# domains/home/apps/jellyfin-media-player/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.jellyfin-media-player;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.jellyfin-media-player = {
    enable = lib.mkEnableOption "Jellyfin Media Player";

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Start Jellyfin Media Player automatically on login.";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.jellyfin-media-player ];

    # Optional autostart as a user service so it works across sessions.
    systemd.user.services.jellyfin-media-player = lib.mkIf cfg.autoStart {
      Unit = {
        Description = "Jellyfin Media Player (autostart)";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.jellyfin-media-player}/bin/jellyfin-media-player --fullscreen";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [ ];
  };
}