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
    # Override dataFolder to use hwc structure
    hwc.server.navidrome.settings.dataFolder = lib.mkDefault "/var/lib/hwc/navidrome";

    # Native Navidrome service configuration
    services.navidrome = {
      enable = true;
      settings = {
        Address = cfg.settings.address;
        Port = cfg.settings.port;
        MusicFolder = cfg.settings.musicFolder;
        DataFolder = "/var/lib/hwc/navidrome";  # Override default
        # Credentials for initial setup
        ND_INITIAL_ADMIN_USER = cfg.settings.initialAdminUser;
        # Use password from file if provided, otherwise use plaintext (deprecated)
        ND_INITIAL_ADMIN_PASSWORD =
          if cfg.settings.initialAdminPasswordFile != null
          then "" # Will be loaded via systemd credential below
          else cfg.settings.initialAdminPassword;
      } // lib.optionalAttrs (cfg.settings.baseUrl != "") {
        BaseURL = cfg.settings.baseUrl;
      };
    };

    # Service configuration for simplified permissions and credentials
    systemd.services.navidrome = {
      serviceConfig = {
        # Run as eric user for simplified permissions (single-user system)
        User = lib.mkForce "eric";
        Group = lib.mkForce "users";
        # Override state directory to use hwc structure
        StateDirectory = lib.mkForce "hwc/navidrome";
        WorkingDirectory = lib.mkForce cfg.settings.dataFolder;
      } // lib.optionalAttrs (cfg.settings.initialAdminPasswordFile != null) {
        LoadCredential = "navidrome-password:${cfg.settings.initialAdminPasswordFile}";
      };
      # Set environment variable from credential if using password file
      environment = lib.mkIf (cfg.settings.initialAdminPasswordFile != null) {
        ND_INITIAL_ADMIN_PASSWORD = "%d/navidrome-password";
      };
    };

    # Open firewall port
    networking.firewall.allowedTCPPorts = [ cfg.settings.port ];

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = !cfg.enable ||
                    (cfg.settings.initialAdminPassword != "" || cfg.settings.initialAdminPasswordFile != null);
        message = "hwc.server.navidrome requires either initialAdminPassword or initialAdminPasswordFile to be set";
      }
      {
        assertion = !cfg.enable ||
                    !(cfg.settings.initialAdminPassword != "" && cfg.settings.initialAdminPasswordFile != null);
        message = "hwc.server.navidrome: cannot set both initialAdminPassword and initialAdminPasswordFile";
      }
      {
        assertion = !cfg.reverseProxy.enable || config.hwc.server.reverseProxy.enable;
        message = "hwc.server.navidrome.reverseProxy requires hwc.server.reverseProxy.enable = true";
      }
    ];
  };
}