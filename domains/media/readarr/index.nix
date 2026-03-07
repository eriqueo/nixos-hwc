{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.readarr;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  # NOTE: Using Bookshelf (Readarr revival) instead of original Readarr
  # Original Readarr's metadata service (api.bookinfo.club) is dead
  # Bookshelf uses Hardcover.app for working metadata
  options.hwc.media.readarr = {
    enable = lib.mkEnableOption "Bookshelf (Readarr revival) container for ebook/audiobook management";
    image = lib.mkOption { type = lib.types.str; default = "ghcr.io/pennydreadful/bookshelf:hardcover"; description = "Container image (Bookshelf with Hardcover metadata)"; };
    network.mode = lib.mkOption { type = lib.types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable = lib.mkOption { type = lib.types.bool; default = false; };
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
