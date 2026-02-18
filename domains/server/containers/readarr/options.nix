# domains/server/containers/readarr/options.nix
# NOTE: Using Bookshelf (Readarr revival) instead of original Readarr
# Original Readarr's metadata service (api.bookinfo.club) is dead
# Bookshelf uses Hardcover.app for working metadata
{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.server.containers.readarr = {
    enable = mkEnableOption "Bookshelf (Readarr revival) container for ebook/audiobook management";
    image  = mkOption { type = types.str; default = "ghcr.io/pennydreadful/bookshelf:hardcover"; description = "Container image (Bookshelf with Hardcover metadata)"; };
    network.mode = mkOption { type = types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable    = mkOption { type = types.bool; default = false; };
  };
}
