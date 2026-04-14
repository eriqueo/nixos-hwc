{ lib, config, pkgs, ... }:

let
  cfg = config.hwc.media.calibre;
  paths = config.hwc.paths;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.calibre = {
    enable = lib.mkEnableOption "Calibre ebook management container";
    image = lib.mkOption { type = lib.types.str; default = "lscr.io/linuxserver/calibre:latest"; description = "Container image for Calibre"; };
    network.mode = lib.mkOption { type = lib.types.enum [ "media" "vpn" ]; default = "media"; description = "Network mode"; };
    gpu.enable = lib.mkOption { type = lib.types.bool; default = false; description = "Enable GPU support for Calibre"; };
    ports = {
      desktop = lib.mkOption { type = lib.types.int; default = 8083; description = "Port for Calibre desktop interface (KasmVNC)"; };
      webserver = lib.mkOption { type = lib.types.int; default = 8181; description = "Port for Calibre content server"; };
    };
    library = lib.mkOption { type = lib.types.path; default = "${paths.media.books}/ebooks"; description = "Path to ebooks library"; };
  };

  imports = [
    ./sys.nix
    ./parts/config.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Container definition is in sys.nix
    # Service dependencies are in parts/config.nix

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = cfg.network.mode != "vpn" || config.hwc.networking.gluetun.enable;
        message = "calibre container with VPN mode requires gluetun to be enabled";
      }
      {
        assertion = config.hwc.paths.hot.root != null;
        message = "calibre container requires hwc.paths.hot.root to be defined (for downloads)";
      }
      {
        assertion = config.hwc.paths.media.root != null;
        message = "calibre container requires hwc.paths.media.root to be defined (for book libraries)";
      }
    ];
  };
}
