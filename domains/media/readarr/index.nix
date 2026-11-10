{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.readarr;
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  configPath = "${config.hwc.paths.apps.root}/readarr/config";
  enforceScript = pkgs.writeShellScript "enforce-readarr-config" ''
    CONFIG_FILE="${configPath}/config.xml"
    mkdir -p "${configPath}"

    # Clear UrlBase if config exists (don't interfere with first-run setup).
    # Empty = served at root; readarr.<vhostDomain> is a vhost, not a subpath.
    if [ -f "$CONFIG_FILE" ]; then
      ${pkgs.gnused}/bin/sed -i \
        -e 's|<UrlBase>[^<]*</UrlBase>|<UrlBase></UrlBase>|' \
        "$CONFIG_FILE"
    fi
  '';
in
{
  options.hwc.media.readarr = {
    enable = lib.mkEnableOption "Bookshelf (Readarr revival) container for ebook/audiobook management";
    port = lib.mkOption { type = lib.types.port; default = (import ../../networking/ports.nix).readarr.port; };
    image = lib.mkOption { type = lib.types.str; default = "ghcr.io/pennydreadful/bookshelf:hardcover"; description = "Container image (Bookshelf with Hardcover metadata)"; };
    network.mode = lib.mkOption { type = lib.types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable = lib.mkOption { type = lib.types.bool; default = false; };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (helpers.mkContainer {
      name = "readarr";
      image = cfg.image;
      networkMode = cfg.network.mode;
      gpuEnable = cfg.gpu.enable;
      gpuMode = "intel";
      timeZone = config.time.timeZone or "UTC";
      ports = [ "127.0.0.1:${toString cfg.port}:${toString (import ../../networking/ports.nix).readarr.port}" ];
      volumes = [
        "${configPath}:/config"
        # /books MUST denote the same host directory here as it does in the
        # calibre container, which mounts hwc.paths.media.books/ebooks at
        # /books. Readarr asks the calibre content server where it files
        # imports, gets back a path in *calibre's* namespace (/books/calibre),
        # and then resolves it in its own — so if the two disagree the check
        # fails and imports land nowhere. Mounting media.books here (one level
        # up) made /books mean two different things and broke every book import
        # from 2026-02-27 onward.
        "${config.hwc.paths.media.books}/ebooks:/books"
        # Audiobooks are not part of the calibre library, so they get their own
        # token rather than being smuggled in under /books.
        "${config.hwc.paths.media.audiobooks}:/audiobooks"
        "${config.hwc.paths.hot.root}/downloads:/downloads"
      ];
      environment = {
        # Empty = served at root; readarr.hwc.iheartwoodcraft.com is a vhost.
        READARR__URLBASE = "";
      };
      dependsOn = if cfg.network.mode == "vpn" then [ "gluetun" ] else [ "prowlarr" ];
    })
    {
    systemd.services."podman-readarr".after = [ "network-online.target" "init-media-network.service" "agenix.service" "mnt-hot.mount" ];
    systemd.services."podman-readarr".wants = [ "network-online.target" "agenix.service" ];
    systemd.services."podman-readarr".requires = [ "mnt-hot.mount" ];
    systemd.services."podman-readarr".serviceConfig.ExecStartPre = [ "+${enforceScript}" ];
  }
  ]);
}
