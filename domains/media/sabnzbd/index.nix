{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.sabnzbd;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.sabnzbd = {
    enable = lib.mkEnableOption "SABnzbd usenet client container";
    image = lib.mkOption { type = lib.types.str; default = "lscr.io/linuxserver/sabnzbd:latest"; description = "Container image for SABnzbd"; };
    network.mode = lib.mkOption { type = lib.types.enum [ "media" "vpn" ]; default = "vpn"; description = "Network mode: 'media' for direct access, 'vpn' to route through gluetun"; };
    webPort = lib.mkOption { type = lib.types.port; default = 8081; description = "Web UI port"; };
    gpu.enable = lib.mkOption { type = lib.types.bool; default = false; description = "Enable GPU acceleration (not typically needed for SABnzbd)"; };
    categories = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          dir = lib.mkOption { type = lib.types.str; description = "Download directory for this category"; };
          priority = lib.mkOption { type = lib.types.int; default = -100; description = "Download priority for this category"; };
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

  imports = [
    ./sys.nix
    ./parts/config.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable { };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Add assertions and validation logic here
}
