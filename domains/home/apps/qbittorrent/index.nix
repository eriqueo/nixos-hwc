# domains/home/apps/qbittorrent/index.nix
# One-package app module via domains/lib/mkSimpleApp.nix (Law 2: name = folder).
import ../../../lib/mkSimpleApp.nix {
  name = "qbittorrent";
  description = "qBittorrent torrent client";
  package = pkgs: pkgs.qbittorrent;
}
