# modules/server/containers/sabnzbd/options.nix
{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.server.containers.sabnzbd = {
    enable = mkEnableOption "SABnzbd usenet client container";

    image = mkOption {
      type = types.str;
      default = "lscr.io/linuxserver/sabnzbd:latest";
      description = "Container image for SABnzbd";
    };

    network.mode = mkOption {
      type = types.enum [ "media" "vpn" ];
      default = "vpn";
      description = "Network mode: 'media' for direct access, 'vpn' to route through gluetun";
    };

    webPort = mkOption {
      type = types.port;
      default = 8081;
      description = "Web UI port";
    };

    gpu.enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable GPU acceleration (not typically needed for SABnzbd)";
    };

    categories = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          dir = mkOption {
            type = types.str;
            description = "Download directory for this category (relative to /downloads inside container)";
          };
          priority = mkOption {
            type = types.int;
            default = -100;
            description = "Download priority for this category";
          };
        };
      });
      default = {
        movies = { dir = "/downloads/movies"; priority = -100; };
        tv = { dir = "/downloads/tv"; priority = -100; };
        music = { dir = "/downloads/music"; priority = -100; };
        books = { dir = "/downloads/books"; priority = -100; };
      };
      description = "Download categories with their directories";
    };
  };
}
