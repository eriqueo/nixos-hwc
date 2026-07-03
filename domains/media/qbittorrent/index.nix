{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.qbittorrent;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.qbittorrent = {
    enable = lib.mkEnableOption "qBittorrent torrent client container";
    image = lib.mkOption { type = lib.types.str; default = "lscr.io/linuxserver/qbittorrent:latest"; description = "Container image for qBittorrent"; };
    network.mode = lib.mkOption { type = lib.types.enum [ "media" "vpn" ]; default = "vpn"; description = "Network mode: 'media' for direct access, 'vpn' to route through gluetun"; };
    webPort = lib.mkOption { type = lib.types.port; default = 8080; description = "Web UI port"; };
    gpu.enable = lib.mkOption { type = lib.types.bool; default = false; description = "Enable GPU acceleration (not typically needed for qBittorrent)"; };
    privacy.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Privacy hardening for VPN operation. When enabled, disables DHT, LSD
        (Local Service Discovery) and PeX (Peer Exchange) and turns on anonymous
        mode, so qBittorrent never announces to or discovers peers outside the
        gluetun VPN tunnel. Trade-off: DHT-only magnet links cannot bootstrap
        ("cannot resolve magnet link with DHT disabled"); tracker-backed torrents
        and usenet are unaffected. Enforced into qBittorrent.conf on every start.
      '';
    };
    categories = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options.savePath = lib.mkOption { type = lib.types.str; description = "Save path for this category"; };
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
