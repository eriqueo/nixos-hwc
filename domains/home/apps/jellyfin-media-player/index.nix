{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.home.apps.jellyfinMediaPlayer;
  enabled = cfg.enable or false;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf enabled {
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
