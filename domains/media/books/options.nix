{ lib, ... }:

{
  options.hwc.server.containers.books = {
    enable = lib.mkEnableOption "LazyLibrarian books management container";

    image = lib.mkOption {
      type = lib.types.str;
      default = "lscr.io/linuxserver/lazylibrarian:latest";
      description = "Container image for LazyLibrarian";
    };

    network.mode = lib.mkOption {
      type = lib.types.enum [ "media" "vpn" ];
      default = "media";
      description = "Network mode: media or vpn (through Gluetun)";
    };

    gpu.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable GPU support (not typically needed for LazyLibrarian)";
    };

    httpRoot = lib.mkOption {
      type = lib.types.str;
      default = "/books";
      description = "HTTP root path for reverse proxy (e.g., /books)";
    };
  };
}
