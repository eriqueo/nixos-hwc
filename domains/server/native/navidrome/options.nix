{ lib, config, ... }:
let
  inherit (lib) mkEnableOption mkOption types;
in
{
  options.hwc.server.native.navidrome = {
    enable = mkEnableOption "Navidrome music server (native service)";

    settings = {
      address = mkOption {
        type = types.str;
        default = "0.0.0.0";
        description = "Listen address for Navidrome server";
      };

      port = mkOption {
        type = types.port;
        default = 4533;
        description = "Port for Navidrome server";
      };

      musicFolder = mkOption {
        type = types.str;
        default = config.hwc.paths.media.music or "${config.hwc.paths.media.music}";
        description = "Path to music library";
      };

      dataFolder = mkOption {
        type = types.str;
        default = "/var/lib/navidrome";
        description = "Path to Navidrome data directory";
      };

      initialAdminUser = mkOption {
        type = types.str;
        default = "admin";
        description = "Initial admin username";
      };

      initialAdminPassword = mkOption {
        type = types.str;
        default = "";
        description = "Initial admin password (plaintext, use initialAdminPasswordFile instead for security)";
      };

      initialAdminPasswordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to file containing initial admin password (more secure than plaintext)";
      };

      baseUrl = mkOption {
        type = types.str;
        default = "";
        description = "Base URL for reverse proxy (e.g., /navidrome)";
      };
    };

    reverseProxy = {
      enable = mkEnableOption "Enable reverse proxy route for Navidrome";

      path = mkOption {
        type = types.str;
        default = "/navidrome";
        description = "Reverse proxy path";
      };
    };
  };
}