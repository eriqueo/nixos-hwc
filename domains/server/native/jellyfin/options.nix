{ lib, ... }:
let
  inherit (lib) mkEnableOption mkOption types;
in
{
  options.hwc.server.native.jellyfin = {
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

    gpu = {
      enable = mkEnableOption "GPU acceleration for video transcoding";
    };

    users = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          maxActiveSessions = mkOption {
            type = types.int;
            default = 0;
            description = "Maximum active sessions (0 = unlimited)";
          };
        };
      });
      default = {};
      description = "User policy overrides applied via API after startup";
    };

    apiKey = mkOption {
      type = types.str;
      default = "";
      description = "Jellyfin API key for policy management";
    };
  };
}