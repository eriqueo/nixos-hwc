# domains/server/native/webdav/options.nix
#
# WebDAV server using dufs for file synchronization
# Primary use case: RetroArch save state sync between devices
{ lib, ... }:
let
  inherit (lib) mkEnableOption mkOption types;
in
{
  options.hwc.server.native.webdav = {
    enable = mkEnableOption "WebDAV server using dufs for file synchronization";

    settings = {
      port = mkOption {
        type = types.port;
        default = 8282;
        description = "Internal port for dufs WebDAV server";
      };

      bindAddress = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Address to bind the WebDAV server (localhost for reverse proxy)";
      };
    };

    # Authentication
    auth = {
      usernameFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to file containing WebDAV username (from agenix)";
      };

      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to file containing WebDAV password (from agenix)";
      };
    };

    # RetroArch-specific preset
    retroarch = {
      enable = mkEnableOption "Expose RetroArch save directories via WebDAV";

      syncSaves = mkOption {
        type = types.bool;
        default = true;
        description = "Expose .srm save RAM files for sync";
      };

      syncStates = mkOption {
        type = types.bool;
        default = true;
        description = "Expose save state files for sync";
      };

      dataDir = mkOption {
        type = types.path;
        default = "/var/lib/hwc/retroarch";
        description = "RetroArch data directory containing saves and states";
      };
    };

    # Caddy reverse proxy integration
    reverseProxy = {
      enable = mkEnableOption "Enable Caddy reverse proxy route for WebDAV";

      path = mkOption {
        type = types.str;
        default = "/retroarch-sync";
        description = "URL path for WebDAV access via reverse proxy";
      };
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open firewall port for direct WebDAV access (not needed with reverse proxy)";
    };
  };
}
