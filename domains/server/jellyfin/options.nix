{ lib, ... }:
let
  inherit (lib) mkEnableOption mkOption types;
in
{
  options.hwc.server.jellyfin = {
    enable = mkEnableOption "Jellyfin media server (native service)";

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to open firewall ports automatically";
    };

    reverseProxy = {
      enable = mkEnableOption "Enable reverse proxy route for Jellyfin";

      path = mkOption {
        type = types.str;
        default = "/media";
        description = "Reverse proxy path";
      };

      upstream = mkOption {
        type = types.str;
        default = "localhost:8096";
        description = "Upstream server for reverse proxy";
      };
    };
  };
}