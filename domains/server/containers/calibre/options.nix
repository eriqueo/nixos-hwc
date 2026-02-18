# domains/server/containers/calibre/options.nix
{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.server.containers.calibre = {
    enable = mkEnableOption "Calibre ebook management container";

    image = mkOption {
      type = types.str;
      default = "lscr.io/linuxserver/calibre:latest";
      description = "Container image for Calibre";
    };

    network.mode = mkOption {
      type = types.enum [ "media" "vpn" ];
      default = "media";
      description = "Network mode: media or vpn (through Gluetun)";
    };

    gpu.enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable GPU support for Calibre";
    };

    ports = {
      desktop = mkOption {
        type = types.int;
        default = 8083;
        description = "Port for Calibre desktop interface (KasmVNC)";
      };

      webserver = mkOption {
        type = types.int;
        default = 8181;
        description = "Port for Calibre content server";
      };
    };

    library = mkOption {
      type = types.path;
      default = "/mnt/media/books/ebooks";
      description = "Path to ebooks library";
    };
  };
}
