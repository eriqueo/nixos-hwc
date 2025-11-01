{ lib, ... }:
let
  inherit (lib) mkEnableOption mkOption types;
in
{
  options.hwc.server.navidrome = {
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
        default = "/mnt/media/music";
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
        description = "Initial admin password";
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