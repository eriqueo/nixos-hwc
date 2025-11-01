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
      };
    };

    # Register reverse proxy route if enabled
    hwc.services.shared.routes = lib.mkIf cfg.reverseProxy.enable [
      {
        path = cfg.reverseProxy.path;
        upstream = "127.0.0.1:${toString cfg.settings.port}";
        stripPrefix = true;
      }
    ];

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