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
    privacy = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Master switch for privacy hardening of the BitTorrent session. When
          off, qBittorrent's own defaults are left untouched. When on, the
          individual toggles below are enforced into qBittorrent.conf on every
          container start (qBittorrent rewrites that file on exit).
        '';
      };

      anonymousMode = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Suppress the client fingerprint in peer/tracker handshakes. Cheap and
          has no effect on peer discovery, so it stays on unconditionally.
        '';
      };

      dht = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Distributed Hash Table. Required for magnet links: a magnet carries no
          metadata, so the client must locate peers to fetch it from. With DHT
          off and a magnet's trackers dead, the torrent parks in `metaDL` at 0%
          forever and Radarr/Sonarr surface "qBittorrent cannot resolve magnet
          link with DHT disabled".

          Default on. The IP exposed to the DHT swarm is gluetun's VPN exit, not
          the host's — the tunnel, not this flag, is the privacy boundary.
          Torrents carrying the BEP-27 `private` flag have DHT disabled
          per-torrent by libtorrent regardless of this setting, so private
          trackers are not implicated either way.
        '';
      };

      pex = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Peer Exchange. Second discovery path when a magnet's trackers are
          unreachable. Same VPN and `private`-flag reasoning as DHT.
        '';
      };

      lsd = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Local Service Discovery — multicasts to find peers on the local
          network. Useless here (the container's only "local" network is
          gluetun's namespace) so it stays off; it buys nothing and is the one
          discovery mechanism that could address a non-tunnelled interface.
        '';
      };
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
