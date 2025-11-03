{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.navidrome;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./options.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Native Navidrome service configuration
    services.navidrome = {
      enable = true;
      settings = {
        Address = cfg.settings.address;
        Port = cfg.settings.port;
        MusicFolder = cfg.settings.musicFolder;
        DataFolder = cfg.settings.dataFolder;
        # Credentials for initial setup
        ND_INITIAL_ADMIN_USER = cfg.settings.initialAdminUser;
        ND_INITIAL_ADMIN_PASSWORD = cfg.settings.initialAdminPassword;
      } // lib.optionalAttrs (cfg.settings.baseUrl != "") {
        BaseURL = cfg.settings.baseUrl;
      };
    };



    # Open firewall port
    networking.firewall.allowedTCPPorts = [ cfg.settings.port ];

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = !cfg.enable || (cfg.settings.initialAdminPassword != "");
        message = "hwc.server.navidrome requires initialAdminPassword to be set";
      }
      {
        assertion = !cfg.reverseProxy.enable || config.hwc.services.reverseProxy.enable;
        message = "hwc.server.navidrome.reverseProxy requires hwc.services.reverseProxy.enable = true";
      }
    ];
  };
}