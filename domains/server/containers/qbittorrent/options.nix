# modules/server/containers/qbittorrent/options.nix
{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.server.containers.qbittorrent = {
    enable = mkEnableOption "qBittorrent torrent client container";

    image = mkOption {
      type = types.str;
      default = "lscr.io/linuxserver/qbittorrent:latest";
      description = "Container image for qBittorrent";
    };

    network.mode = mkOption {
      type = types.enum [ "media" "vpn" ];
      default = "vpn";
      description = "Network mode: 'media' for direct access, 'vpn' to route through gluetun";
    };

    webPort = mkOption {
      type = types.port;
      default = 8080;
      description = "Web UI port";
    };

    gpu.enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable GPU acceleration (not typically needed for qBittorrent)";
    };

    categories = mkOption {
      type = types.attrsOf (types.submodule {
        options.savePath = mkOption {
          type = types.str;
          description = "Save path for this category (relative to /downloads inside container)";
        };
      });
      default = {
        movies = { savePath = "/downloads/movies"; };
        tv = { savePath = "/downloads/tv"; };
        music = { savePath = "/downloads/music"; };
        books = { savePath = "/downloads/books"; };
      };
      description = "Download categories with their save paths";
    };
  };
}
